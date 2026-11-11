# frozen_string_literal: true

module PhComposer
  # What a query or action handler receives. Colour-by projections and native menu tests receive the
  # same shape as a read: no params and no proposal (context/CONTRACTS.md, "Handler-side dependency
  # reads"). `approval` is the location the user chose for a declaration that needs one
  # (Declarations::Approval), as a NativeApproval::Granted; it is nil everywhere else.
  #
  # A request is frozen, its params included: each request holds its own frozen copy, so an operation
  # cannot alter what a nested read or the dispatcher's digest sees. The foundation derives a nested
  # one with `with`; feature code passes the values it needs to its operations as arguments and never
  # derives or alters a request.
  # `selection` is the selected occurrences as full persistent-id paths, given only to a Colour-by readout
  # that declares it reads the selection; nil everywhere else.
  HandlerRequest = Struct.new(:session, :model, :params, :engine, :revision, :registry, :owner, :proposal, :query_stack,
                              :memos, :approval, :selection, keyword_init: true) do
    # The one place a request is built from a session. `name` is the declaration the request runs
    # for, so a nested read of the same name is refused as recursive.
    def self.for(session, owner:, name:, registry: Registry.current, params: {}, proposal: nil, approval: nil,
                 selection: nil)
      engine = Records::Engine.new(session.model, registry.catalog, :identity => proposal_ids(session, name, params))
      new(:session => session, :model => session.model, :params => params, :engine => engine,
          :revision => session.revision,
          :registry => registry, :owner => owner, :proposal => proposal, :query_stack => [name],
          :approval => approval, :selection => selection)
    end

    # The ids this request's creates and duplicates stage: derived from the session, revision, declaration and
    # params, so the same preview run again, and its invoke, name the same records (context/AGENT_INTERFACE.md,
    # "Writes with observable outcomes").
    def self.proposal_ids(session, name, params)
      Records::Identity.sequence(session.id, session.revision) do
        { "name" => name, "params" => CanonicalJson.digest(params || {}) }
      end
    end

    def initialize(**fields)
      super
      self.params = DeepCopy.frozen(params || {})
      self.selection = DeepCopy.frozen(selection) if selection
      self.query_stack ||= []
      self.memos ||= {}.compare_by_identity
      freeze
    end

    # The same request for a nested call the foundation makes: a dependency read, a retargeter, a
    # library callback or participant. Memos stay shared, so nested reads reuse what the caller computed.
    def with(params: self.params, owner: self.owner, proposal: self.proposal, engine: self.engine,
             query_stack: self.query_stack)
      HandlerRequest.new(**to_h, :params => params, :owner => owner, :proposal => proposal, :engine => engine,
                                 :query_stack => query_stack)
    end

    # A value computed once per request, shared with the nested reads and callbacks it makes. Keys
    # are scoped to the current owner, so two features cannot collide, and to the current engine, so
    # a value read through one engine is never reused under a projected one.
    def memo(key)
      slot = (memos[engine] ||= {})
      return slot[[owner, key]] if slot.key?([owner, key])

      slot[[owner, key]] = yield
    end

    # Whether this request's owner may use what `target_owner` declared: its own, or a feature it requires.
    def may_use?(target_owner)
      target_owner == owner || registry.features.fetch(owner).requires.include?(target_owner)
    end

    # Reads a declared dependency within the current read/proposal phase, without
    # re-entering the public dispatcher or bypassing the query's schemas.
    def query(name, params = {})
      declaration = registry.queries[name]
      raise CodedError.new("operation.query_missing", "No query named #{name} is installed.") unless declaration
      unless may_use?(declaration.owner)
        raise CodedError.new("operation.dependency_missing", "#{owner} does not require #{declaration.owner}.")
      end
      if query_stack.include?(name)
        raise CodedError.new("operation.query_cycle", "Recursive query #{name} was refused.")
      end
      unless params.is_a?(Hash) && JsonValue.problems(params).empty? &&
             JsonSchema.validate(params, declaration.params).empty?
        raise CodedError.new("params.invalid", "#{name} params do not match its schema.")
      end

      nested = with(:params => params, :owner => declaration.owner, :proposal => nil,
                    :query_stack => query_stack + [name])
      value = declaration.handler.call(nested)
      unless JsonValue.problems(value).empty? && JsonSchema.validate(value, declaration.result).empty?
        raise InternalError, "#{name} returned a result outside its schema."
      end

      DeepCopy.call(value)
    end

    # The owner's resolver for one entity reference target, under the same dependency rule as `query`.
    # A step keeps the returned callable and re-locates on the live Model at apply, where it has no
    # request. The caller may read the entity's geometry and glue to it; record writes stay with the
    # owner (context/EXTENSIBILITY.md, "Entity-owned reference targets").
    def locator(kind)
      locatable_target(kind).method(:locate)
    end

    # The owner's read-phase index for one locatable kind, or nil when the owner declares none. It is
    # valid only until the next write, so an action builds it while planning and passes it as `index:`
    # to each `locate`; a step never keeps it for apply (context/EXTENSIBILITY.md, "Entity-owned
    # reference targets").
    def locate_index(kind)
      locatable_target(kind).locate_index(model)
    end

    def locate(kind, reference, mutable: true, index: nil)
      locator(kind).call(model, reference, :mutable => mutable, :index => index)
    end

    def retarget_references(kind, from:, to:)
      raise InternalError, "Reference retargeting needs an action proposal." unless proposal

      engine.resolve_reference(kind, from)
      engine.resolve_reference(kind, to) unless to.nil?
      rows = registry.reference_retargeters.values.select { |item| item.target_kind == kind }.sort_by(&:name)
      plans = rows.map do |declaration|
        plan = declaration.handler.call(with(:owner => declaration.owner), proposal, :from => from, :to => to)
        unless plan.is_a?(Records::ReferencePlan)
          raise InternalError, "#{declaration.name} must return a ReferencePlan."
        end

        unless (plan.entries + plan.removals).all? { |entry| registry.owner_of(entry.kind) == declaration.owner }
          raise InternalError, "#{declaration.name} may project only its owner's entity targets."
        end

        plan
      end
      Records::ReferencePlan.new(:entries => plans.flat_map(&:entries), :removals => plans.flat_map(&:removals))
    rescue StandardError => error
      proposal&.refuse(error)
      raise
    end

    # Runs every contributor registered for `transition`, in name order, under its own owner and inside
    # this request's proposal, after the caller added its own step. Each receives a detached copy of
    # `description`, may write only its owner's kinds, may only add to the proposal, and returns the
    # references it affects, each `{"kind", "id"}` of a kind it owns. Every step it adds must answer
    # `restore`, since the transition also runs inside a host follow-up. Any failure refuses the whole
    # proposal.
    def contribute_transition(transition, description)
      raise InternalError, "A transition needs an action proposal." unless proposal
      unless Array(registry.actions[query_stack.last]&.transitions).include?(transition)
        raise InternalError, "#{query_stack.last} does not declare the transition #{transition}."
      end

      rows = registry.transition_contributors.values.select { |item| item.transition == transition }.sort_by(&:name)
      rows.flat_map { |declaration| contribution(declaration, description) }
    rescue StandardError => error
      proposal&.refuse(error)
      raise
    end

    # Calls a proposal participant inside this request's active proposal, under the same dependency
    # rule as `query`; the calling declaration names it in `participants` (shell/participant_invocation.rb).
    # Feature code never reaches a participant's handler directly.
    def participate(name, params = {})
      ParticipantInvocation.call(self, name, params)
    end

    private

    def contribution(declaration, description)
      writable = ParticipantInvocation.owned_kinds(registry, declaration.owner)
      nested = with(:owner => declaration.owner,
                    :engine => engine.projected(proposal, :writable_kinds => writable,
                                                          :refusal_code => "proposal.foreign_write"))
      before = Operations::Contributions.snapshot(proposal)
      affected = proposal.guarded(writable, "proposal.foreign_write") do
        declaration.handler.call(nested, proposal, DeepCopy.call(description))
      end
      Operations::Contributions.preserved!(proposal, before)
      unless proposal.steps.drop(before.steps.length).all? { |step| step.respond_to?(:restore) }
        raise InternalError, "#{declaration.name} added a step that cannot be restored."
      end
      unless affected_references?(affected, declaration.owner)
        raise InternalError, "#{declaration.name} must return the references it affects, each of a kind it owns."
      end

      DeepCopy.call(affected)
    end

    def affected_references?(value, owner)
      value.is_a?(Array) && JsonValue.problems(value).empty? && value.all? do |row|
        row.is_a?(Hash) && %w[kind id].all? { |key| row[key].is_a?(String) && !row[key].empty? } &&
          registry.owner_of(row["kind"]) == owner
      end
    end

    def locatable_target(kind)
      target = registry.reference_targets[kind]
      unless target
        raise CodedError.new("reference.invalid", "Reference target #{kind} is not registered.", "target_kind" => kind)
      end

      target_owner = registry.owner_of(kind)
      unless may_use?(target_owner)
        raise CodedError.new("operation.dependency_missing", "#{owner} does not require #{target_owner}.")
      end

      unless target.locatable?
        raise CodedError.new("operation.locate_missing", "Reference target #{kind} cannot be located.",
                             "target_kind" => kind)
      end

      target
    end
  end
end
