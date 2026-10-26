# frozen_string_literal: true

module PhComposer
  class Registry
    # The checks a staged batch must pass before it publishes. Each problem becomes one diagnostic
    # naming the owner and, where one is missing, the dependency. Codes are the `registration.*` codes
    # in context/CONTRACTS.md, "Outcomes and codes".
    class Validation
      def initialize(live, staging)
        @live = live
        @staging = staging
        @diagnostics = []
      end

      def diagnostics
        check_features
        check_names
        check_operations
        check_record_kinds
        @diagnostics.concat(StoreValidation.new(@live, @staging).diagnostics)
        @diagnostics.concat(TermsValidation.new(@live, @staging).diagnostics)
        check_reference_targets
        check_extensions
        check_snapshot_sections
        @diagnostics.concat(ExportValidation.new(@live, @staging).diagnostics)
        check_reference_retargeters
        @diagnostics.concat(TransitionValidation.new(@live, @staging).diagnostics)
        @diagnostics.concat(ParticipantValidation.new(@live, @staging).diagnostics)
        @diagnostics.concat(LibraryValidation.new(@live, @staging).diagnostics)
        check_colour_modes
        check_colour_readouts
        check_menu_items
        check_subscriptions
        @diagnostics.concat(CodeValidation.new(@live, @staging).diagnostics)
        @diagnostics
      end

      private

      # Operations and local library callbacks publish the same checked code vocabulary. A callback's
      # owner is the library kind owner, and only the common codes all its callers share are excluded.
      def check_refusal_list(subject, refuses, common, label = "refuses")
        unless refuses.is_a?(Array) && refuses.all?(String)
          problem(subject, "needs #{label}, a list of codes")
          return
        end
        owners = (@live.codes.values + @staging.declared_codes).to_h { |code| [code.code, code.owner] }
        requires = @staging.declared_features.find { |feature| feature.id == subject.owner }&.requires || []
        refuses.tally.each do |code, count|
          owner = owners[code]
          if count > 1
            problem(subject, "#{label} lists #{code} more than once")
          elsif common.include?(code)
            problem(subject, "#{label} lists #{code}, which every operation of its kind answers")
          elsif Refusals::DISPATCH_ONLY.include?(code)
            problem(subject, "#{label} lists #{code}, which only dispatch gives")
          elsif !Declarations::FOUNDATION_CODES.include?(code) && owner.nil?
            problem(subject, "#{label} lists #{code}, which no feature declares and context/CONTRACTS.md does not list")
          elsif owner && owner != subject.owner && !requires.include?(owner)
            problem(subject, "#{label} lists #{code}, which belongs to #{owner}; #{subject.owner} must require it")
          end
        end
      end

      def check_features
        features = @staging.declared_features
        features.each do |feature|
          unless ID_PATTERN.match?(feature.id)
            message = "Feature id #{feature.id.inspect} must be lowercase and dotted, such as example.foundation."
            add("registration.schema_invalid", feature.id, feature.id, message)
          end
          if feature.contract_version != Declarations::CONTRACT_VERSION
            add("registration.contract_major", feature.id, feature.id,
                "#{feature.id} was written for contract #{feature.contract_version}; this build provides " \
                "#{Declarations::CONTRACT_VERSION}.")
          end
          feature.requires.each do |required|
            next if @live.features.key?(required) || features.any? { |other| other.id == required }

            message = "#{feature.id} requires #{required}, which is not installed."
            add("registration.missing_dependency", feature.id, feature.id, message, required)
          end
        end
        check_feature_cycles(features)
      end

      def check_feature_cycles(features)
        by_id = features.to_h { |feature| [feature.id, feature] }
        by_id.each_key do |start|
          path = cycle_from(start, by_id, [start])
          next unless path && path.first == path.min

          add("registration.cycle", start, start, "Features require each other in a cycle: #{path.join(' -> ')}.")
        end
      end

      def cycle_from(current, by_id, path)
        Array(by_id[current]&.requires).each do |required|
          return path + [required] if required == path.first
          next if path.include?(required)

          found = cycle_from(required, by_id, path + [required])
          return found if found
        end
        nil
      end

      def check_names
        seen = {}
        declared_names.each do |owner, name|
          prior_owner = @live.owner_of(name) || seen[name]
          if prior_owner
            add("registration.duplicate_id", owner, name, "#{name} is declared by both #{prior_owner} and #{owner}.",
                prior_owner)
          elsif !ID_PATTERN.match?(name) || !name.start_with?("#{owner}.")
            message = "#{name} must be lowercase, dotted and start with #{owner}."
            add("registration.schema_invalid", owner, name, message)
          end
          seen[name] ||= owner
        end
        @staging.declared_features.group_by(&:id).each do |id, copies|
          next unless copies.length > 1 || @live.features.key?(id)

          add("registration.duplicate_id", id, id, "Feature #{id} is installed more than once.")
        end
      end

      # Every [owner, name] the batch declared, in declaration order, duplicates included.
      def declared_names
        @staging.named
      end

      # A participant is checked as an operation is; it answers no client, so it has no approval.
      def check_operations
        (@staging.declared_operations + @staging.declared_proposal_participants).each do |operation|
          add_schema_problems(operation, "params", operation.params)
          add_schema_problems(operation, "result", operation.result)
          unless operation.params.is_a?(Hash) && operation.params["type"] == "object"
            add("registration.schema_invalid", operation.owner, operation.name,
                "#{operation.name} params must be an object.")
          end
          problem(operation, "needs a description") unless text?(operation.description)
          check_examples(operation)
          problem(operation, "needs a callable handler") unless operation.handler.respond_to?(:call)
          check_approval(operation) if operation.respond_to?(:approval)
          if operation.respond_to?(:precondition) && !(operation.precondition.nil? ||
                                                        operation.precondition.respond_to?(:call))
            problem(operation, "precondition must be callable")
          end
        end
        @staging.declared_file_exports.each do |operation|
          %i[params result].each do |part|
            schema = operation[part]
            next if schema.is_a?(Hash) && schema["type"] == "object" &&
                    schema["properties"].is_a?(Hash) && schema["additionalProperties"] == false

            problem(operation, "#{part} must be a closed object with declared properties")
          end
        end
        @staging.declared_actions.reject { |action| action.confirmation == "none" }.each do |action|
          add("registration.schema_invalid", action.owner, action.name,
              "#{action.name} declares confirmation #{action.confirmation.inspect}; only \"none\" is supported yet.")
        end
      end

      def check_approval(operation)
        approval = operation.approval
        return if approval.nil?
        unless approval.is_a?(Declarations::Approval) && Declarations::Approval::KINDS.include?(approval.kind) &&
               text?(approval.title)
          return problem(operation, "approval must be a Declarations::Approval of a known kind with a title")
        end

        params = operation.params.is_a?(Hash) ? operation.params : {}
        declared = params["properties"].is_a?(Hash) ? params["properties"]["location"] : nil
        return if declared == (approval.standing ? nil : ApprovedLocations.param(approval.kind)) &&
                  !Array(params["required"]).include?("location")

        problem(operation, "params must be an object whose properties leave location to registration, which " \
                           "adds it for an approval")
      end

      # Every example is plain JSON that its params accept. An operation whose params accept `{}` may
      # omit examples, since `{}` is then its example; any other needs at least one.
      def check_examples(operation)
        examples = operation.examples
        return problem(operation, "examples must be a list") unless examples.is_a?(Array)
        return unless operation.params.is_a?(Hash) && JsonSchema.schema_problems(operation.params).empty?

        if examples.empty? && !JsonSchema.validate({}, operation.params).empty?
          problem(operation, "needs an example of its params")
        end
        examples.each do |example|
          problems = example.is_a?(Hash) ? JsonValue.problems(example) : ["$ must be an object"]
          problems += JsonSchema.validate(example, operation.params) if problems.empty?
          problem(operation, "has an example its params refuse: #{problems.first}") unless problems.empty?
        end
      end

      def problem(operation, text)
        add("registration.schema_invalid", operation.owner, operation.name, "#{operation.name} #{text}.")
      end

      def add_schema_problems(operation, part, schema)
        JsonSchema.schema_problems(schema).each do |problem|
          add("registration.schema_invalid", operation.owner, operation.name, "#{operation.name} #{part}: #{problem}.")
        end
      end

      def check_reference_retargeters
        @staging.declared_reference_retargeters.each do |retargeter|
          require_kind(retargeter.owner, retargeter.name, retargeter.target_kind)
          problem(retargeter, "needs a callable handler") unless retargeter.handler.respond_to?(:call)
          target_owner = @staging.owner_of(retargeter.target_kind)
          feature = @staging.declared_features.find { |item| item.id == retargeter.owner }
          next if target_owner == retargeter.owner || feature.requires.include?(target_owner)

          add("registration.missing_dependency", retargeter.owner, retargeter.name,
              "#{retargeter.name} must require #{target_owner}.", target_owner)
        end
      end

      def check_record_kinds
        @staging.declared_record_kinds.each do |kind|
          owner = owner(kind.id)
          JsonSchema.schema_problems(kind.values_schema).each do |problem|
            add("registration.schema_invalid", owner, kind.id, "#{kind.id} fields: #{problem}.")
          end
          kind.references.each do |reference|
            require_kind(owner, kind.id, reference.target_kind)
            check_reference_shape(owner, kind.id, reference, kind.values_schema)
          end
        end
      end

      def check_reference_targets
        @staging.declared_reference_targets.each do |target|
          target.descriptor.references.each do |reference|
            require_kind(owner(target.id), target.id, reference.target_kind)
            check_reference_shape(owner(target.id), target.id, reference, target.descriptor.values_schema)
          end
          next if target.label.is_a?(String) && !target.label.empty? &&
                  target.provider.respond_to?(:call) && target.validator.respond_to?(:call)

          add("registration.schema_invalid", owner(target.id), target.id,
              "#{target.id} needs a label, a records provider and a pure validator.")
        end
      end

      def check_reference_shape(owner, subject, reference, values_schema)
        reference.declaration_problems(values_schema).each do |message|
          add("registration.schema_invalid", owner, subject, "#{subject}: #{message}.")
        end
      end

      def check_extensions
        @staging.declared_extensions.each do |extension|
          owner = owner(extension.namespace)
          envelope = extension.envelope({})
          unless extension.schema_version.is_a?(Integer) && extension.schema_version.positive? &&
                 Records::Extension.readable?(envelope) && %i[remap refuse].include?(extension.copy)
            add("registration.schema_invalid", owner, extension.namespace,
                "#{extension.namespace} needs a positive schema version, readable references, a known export " \
                "relevance and a copy rule of :remap or :refuse.")
          end
          extension.references.each { |reference| require_kind(owner, extension.namespace, reference["target_kind"]) }
        end
      end

      def check_snapshot_sections
        @staging.declared_snapshot_sections.each do |section|
          staged = @staging.declared_queries.any? { |query| query.name == section.query }
          next if staged || @live.queries.key?(section.query)

          add("registration.missing_dependency", section.owner, section.name,
              "#{section.name} projects query #{section.query}, which is not registered.", section.query)
        end
      end

      def check_subscriptions
        @staging.declared_subscriptions.each do |subscription|
          next if Sessions::HOST_EVENTS.include?(subscription.kind) && subscription.handler.respond_to?(:call)

          add("registration.schema_invalid", subscription.owner, subscription.kind.to_s,
              "#{subscription.owner} subscribes to #{subscription.kind.inspect}, which needs a known host event " \
              "and a callable handler.")
        end
      end

      # A menu item's submenu label is open prose, like a Colour-by mode's entity kind: `shell/` groups
      # by it and never interprets it.
      def check_menu_items
        @staging.declared_menu_items.each do |item|
          content = if item.entries
                      item.entries.respond_to?(:call)
                    else
                      text?(item.label) && item.handler.respond_to?(:call)
                    end
          next if content && text?(item.menu) &&
                  (item.state.nil? || item.state.respond_to?(:call)) &&
                  (item.available.nil? || item.available.respond_to?(:call))

          add("registration.schema_invalid", item.owner, item.name,
              "#{item.name} needs static content or an entries provider, a submenu name; state and available " \
              "must be callable.")
        end
      end

      # A mode's stroke, in pixels: one is a hairline, and past ten a line hides the geometry it marks.
      COLOUR_STROKES = (1..10).freeze

      # A Colour-by mode needs a legend label, the entity kind it paints, a colour function and a
      # projection. Entity kinds are open, so the kind is checked for shape alone and never against a
      # list the shared service would have to keep.
      def check_colour_modes
        @staging.declared_colour_modes.each do |mode|
          unless mode.stroke.nil? || (mode.stroke.is_a?(Integer) && COLOUR_STROKES.cover?(mode.stroke))
            add("registration.schema_invalid", mode.owner, mode.name,
                "#{mode.name}'s stroke, when given, is a whole number of pixels from 1 to 10.")
          end
          next if text?(mode.label) && text?(mode.entity_kind) && mode.colours.respond_to?(:call) &&
                  mode.projection.respond_to?(:call) && (mode.group.nil? || text?(mode.group))

          add("registration.schema_invalid", mode.owner, mode.name,
              "#{mode.name} needs a label, an entity kind, a colour function and a projection block; " \
              "a group, when given, is a name.")
        end
      end

      def check_colour_readouts
        @staging.declared_colour_readouts.each do |readout|
          next if text?(readout.label) && [true, false].include?(readout.selection) &&
                  readout.projection.respond_to?(:call)

          add("registration.schema_invalid", readout.owner, readout.name,
              "#{readout.name} needs a label, a true or false selection flag and a projection block.")
        end
      end

      def text?(value)
        value.is_a?(String) && !value.strip.empty?
      end

      def require_kind(owner, subject, kind_id)
        staged = @staging.declared_record_kinds.any? { |kind| kind.id == kind_id }
        staged ||= @staging.declared_reference_targets.any? { |target| target.id == kind_id }
        return if staged || @live.record_kinds.key?(kind_id) || @live.reference_targets.key?(kind_id)

        message = "#{subject} refers to record kind #{kind_id}, which is not registered."
        add("registration.missing_dependency", owner, subject, message, kind_id)
      end

      def owner(name)
        @staging.owners.fetch(name)
      end

      def add(code, owner, subject, message, dependency = nil)
        @diagnostics << Declarations::Diagnostic.new(:code => code, :owner => owner, :subject => subject,
                                                     :message => message, :dependency => dependency)
      end
    end

    # A contributor needs its own preflight query, a contract and a positive section version, a valid
    # user_data key declaration, result fields that form a privacy schema, and a dependency on the
    # feature of every section it reads.
    class ExportValidation < Validation
      def diagnostics
        check_section_cycles
        @staging.declared_export_contributors.each do |contributor|
          check_preflight_owner(contributor)
          check_contract(contributor)
          check_user_data_keys(contributor)
          check_result_fields(contributor)
          check_section_reads(contributor)
          check_entity_projections(contributor)
        end
        @diagnostics
      end

      private

      # A section read follows `request.query`'s rule: the section is registered, and belongs to the
      # reading contributor's own feature or one that feature requires.
      def check_section_reads(contributor)
        unless contributor.requires.is_a?(Array) && contributor.requires.all?(String)
          return add("registration.schema_invalid", contributor.owner, contributor.name,
                     "#{contributor.name} requires a list of section ids.")
        end
        unless contributor.projection.nil? || contributor.projection.respond_to?(:call)
          add("registration.schema_invalid", contributor.owner, contributor.name,
              "#{contributor.name} projection must be callable.")
        end
        feature = @staging.declared_features.find { |item| item.id == contributor.owner }
        contributor.requires.each do |section|
          provider = @staging.declared_export_contributors.find { |item| item.name == section } ||
                     @live.export_contributors[section]
          next if provider && (provider.owner == contributor.owner || feature&.requires&.include?(provider.owner))

          message = if provider
                      "#{contributor.name} reads #{section}, so #{contributor.owner} must require #{provider.owner}."
                    else
                      "#{contributor.name} reads #{section}, which is not a registered export contributor."
                    end
          add("registration.missing_dependency", contributor.owner, contributor.name, message, section)
        end
      end

      # Collection runs a section after the ones it requires, so sections that require each other,
      # or themselves, can never run.
      def check_section_cycles
        graph = @live.export_contributors.merge(@staging.declared_export_contributors.to_h { |item| [item.name, item] })
        done = {}
        @staging.declared_export_contributors.each do |start|
          path = section_cycle(graph, start.name, [], done)
          next unless path

          add("registration.cycle", start.owner, start.name,
              "Export sections require each other: #{path.join(' -> ')}.")
        end
      end

      # Depth-first with a completed set, so each section is explored once however many paths reach it.
      def section_cycle(graph, name, path, done)
        return path[path.index(name)..] + [name] if path.include?(name)
        return nil if done[name]

        Array(graph[name]&.requires).each do |next_name|
          found = section_cycle(graph, next_name, path + [name], done)
          return found if found
        end
        done[name] = true
        nil
      end

      CLAIM_KEYS = %w[namespace target_kind source_section fields].freeze

      # Each claim names an extension the contributor's own feature declares, a registered entity
      # reference target whose owner that feature is or requires, a source section in `requires:`, and
      # a non-empty field list. A namespace and target kind are claimed once across the registry.
      def check_entity_projections(contributor)
        claims = contributor.entity_projections
        well_formed = lambda do |claim|
          claim.is_a?(Hash) && claim.keys.all?(String) && claim.keys.sort == CLAIM_KEYS.sort
        end
        unless claims.is_a?(Array) && claims.all?(&well_formed)
          return claim_problem(contributor, "entity_projections must be a list of claims with #{CLAIM_KEYS.join(', ')}")
        end

        feature = @staging.declared_features.find { |item| item.id == contributor.owner }
        claims.each { |claim| check_claim(contributor, feature, claim) }
        taken = (@live.export_contributors.values + @staging.declared_export_contributors).reject do |other|
          other.equal?(contributor)
        end.flat_map { |other| Array(other.entity_projections) }
        claims.each do |claim|
          key = claim.values_at("namespace", "target_kind")
          next unless taken.any? { |other| other.is_a?(Hash) && other.values_at("namespace", "target_kind") == key } ||
                      claims.count { |item| item.values_at("namespace", "target_kind") == key } > 1

          claim_problem(contributor, "claims #{key.join(' on ')}, which another claim already projects")
        end
      end

      # The caller has checked that the claim has exactly CLAIM_KEYS. Each check adds its own diagnostic.
      def check_claim(contributor, feature, claim)
        namespace = claim.fetch("namespace")
        target_kind = claim.fetch("target_kind")
        source_section = claim.fetch("source_section")
        fields = claim.fetch("fields")
        unless fields.is_a?(Array) && !fields.empty? && fields.all? { |field| field.is_a?(String) && !field.empty? }
          claim_problem(contributor, "claim fields must be a non-empty list of payload field names")
        end

        extension = @staging.declared_extensions.any? { |item| item.namespace == namespace } ||
                    @live.extensions.key?(namespace)
        unless extension && @staging.owner_of(namespace) == contributor.owner
          claim_problem(contributor,
                        "claims #{namespace.inspect}, which is not an extension #{contributor.owner} declares")
        end

        target_owner = @staging.owner_of(target_kind)
        registered = @staging.declared_reference_targets.any? { |item| item.id == target_kind } ||
                     @live.reference_targets.key?(target_kind)
        reachable = target_owner && (target_owner == contributor.owner || feature&.requires&.include?(target_owner))
        unless registered && reachable
          add("registration.missing_dependency", contributor.owner, contributor.name,
              "#{contributor.name} projects onto #{target_kind.inspect}, a registered entity target its feature " \
              "must own or require.", target_owner || target_kind)
        end
        return if Array(contributor.requires).include?(source_section)

        add("registration.missing_dependency", contributor.owner, contributor.name,
            "#{contributor.name} projects from #{source_section.inspect}, which it must list in requires.",
            source_section)
      end

      def claim_problem(contributor, text)
        add("registration.schema_invalid", contributor.owner, contributor.name, "#{contributor.name} #{text}.")
      end

      def check_preflight_owner(contributor)
        return unless contributor.preflight

        query = @staging.declared_queries.find { |item| item.name == contributor.preflight } ||
                @live.queries[contributor.preflight]
        return if query && query.owner == contributor.owner

        add("registration.missing_dependency", contributor.owner, contributor.name,
            "#{contributor.name} needs its own registered preflight query.", contributor.preflight)
      end

      def check_contract(contributor)
        version = contributor.section_version
        return if contributor.contract && version.is_a?(Integer) && version.positive?

        add("registration.schema_invalid", contributor.owner, contributor.name,
            "#{contributor.name} needs a contract block and a positive section version.")
      end

      def check_result_fields(contributor)
        Export::Privacy.schema_problems(contributor.result).each do |problem|
          add("registration.schema_invalid", contributor.owner, contributor.name,
              "#{contributor.name} result: #{problem}.")
        end
      end

      # Each declared HBJSON user_data key is dotted and lowercase, like a registered name.
      def check_user_data_keys(contributor)
        keys = contributor.user_data_keys
        return if keys.is_a?(Array) && keys.all? { |key| key.is_a?(String) && ID_PATTERN.match?(key) }

        add("registration.schema_invalid", contributor.owner, contributor.name,
            "#{contributor.name} user_data_keys must be dotted lowercase keys such as ph_composer.level.")
      end
    end

    # A record kind's store is admitted before anything publishes, so publishing never meets a
    # dictionary it must refuse. The engine's methods are checked by presence; only `dictionary` is
    # called, once. The default `ph_composer.records.<kind id>` name is not required: a kind may keep a
    # legacy name, as the Attached zone does.
    # The optional terms `describe` publishes: a view command's `side_effects` and every command's
    # `preconditions` are sentences a caller reads, and a query's `response` names a bounded query that
    # exists.
    class TermsValidation < Validation
      def diagnostics
        (@staging.declared_operations + @staging.declared_proposal_participants).each do |operation|
          check_described_terms(operation)
        end
        check_responses
        @diagnostics
      end

      private

      def check_described_terms(operation)
        if operation.is_a?(Declarations::Query) && ![true, false].include?(operation.while_busy)
          problem(operation, "while_busy must be true or false")
        end
        if operation.is_a?(Declarations::ViewCommand) && !(operation.side_effects.nil? || text?(operation.side_effects))
          problem(operation, "side_effects must be a sentence when declared")
        end
        return unless operation.respond_to?(:preconditions)
        return if operation.preconditions.is_a?(Array) && operation.preconditions.all? { |item| text?(item) }

        problem(operation, "preconditions must be a list of sentences")
      end

      # A query's `response` marks it unbounded and names a registered query that is itself bounded.
      def check_responses
        queries = (@live.queries.values + @staging.declared_queries).to_h { |query| [query.name, query] }
        @staging.declared_queries.reject { |query| query.response.nil? }.each do |query|
          response = query.response
          next if response.is_a?(Hash) && response.keys.all?(String) && response.keys.sort == %w[bounded prefer] &&
                  response["bounded"] == false && queries.key?(response["prefer"]) &&
                  queries.fetch(response["prefer"]).response.nil?

          problem(query, "response must be {\"bounded\" => false, \"prefer\" => a registered bounded query's name}")
        end
      end
    end

    class StoreValidation < Validation
      STORE_METHODS = %i[dictionary ids read write delete].freeze

      def diagnostics
        @staging.declared_record_kinds.each { |kind| check_store(owner(kind.id), kind) }
        @diagnostics
      end

      private

      def check_store(owner, kind)
        missing = STORE_METHODS.reject { |method| kind.store.respond_to?(method) }
        return store_problem(owner, kind, "must answer #{missing.join(', ')}") unless missing.empty?

        name = begin
          kind.store.dictionary
        rescue InternalError
          raise
        rescue StandardError => error
          return store_problem(owner, kind, "dictionary raised #{error.class}")
        end
        return @staging.admitted_dictionaries[kind] = DeepCopy.frozen(name) if Dictionaries.valid_name?(name)

        store_problem(owner, kind, "dictionary #{name.inspect} must be a string starting with #{DICTIONARY_PREFIX}")
      end

      def store_problem(owner, kind, text)
        add("registration.schema_invalid", owner, kind.id, "#{kind.id} store #{text}.")
      end
    end

    # Transitions an action declares and the contributors that join them (Declarations::TransitionContributor).
    class TransitionValidation < Validation
      TRANSITION_NAME = /\A[a-z0-9_]+(\.[a-z0-9_]+)+\z/.freeze

      # The transition's owner is the feature id before its last segment; the contributor requires it.
      # An action emits only its own feature's transitions.
      def diagnostics
        @staging.declared_actions.each do |action|
          names = action.transitions.nil? ? [] : action.transitions
          valid = names.is_a?(Array) && names.uniq.length == names.length && names.all? do |name|
            name.is_a?(String) && TRANSITION_NAME.match?(name) && emitter(name) == action.owner
          end
          problem(action, "transitions must be distinct names of its own feature's transitions") unless valid
        end
        @staging.declared_transition_contributors.each do |contributor|
          problem(contributor, "needs a callable handler") unless contributor.handler.respond_to?(:call)
          check_refusal_list(contributor, contributor.refuses, Refusals::ANY_OPERATION)
          transition = contributor.transition
          unless transition.is_a?(String) && TRANSITION_NAME.match?(transition)
            problem(contributor, "needs a dotted transition name")
            next
          end

          emitter = emitter(transition)
          feature = @staging.declared_features.find { |item| item.id == contributor.owner }
          next if emitter == contributor.owner || feature.requires.include?(emitter)

          add("registration.missing_dependency", contributor.owner, contributor.name,
              "#{contributor.name} must require #{emitter}, which emits #{transition}.", emitter)
        end
        @diagnostics
      end

      private

      def emitter(transition)
        transition.split(".")[0...-1].join(".")
      end
    end

    # The `participants:` edges of actions, queries and participants. Each named participant must be
    # installed or in the batch, and owned by the caller's feature or one it requires; participants
    # that name each other in a cycle are refused, since a call through one would never end.
    class ParticipantValidation < Validation
      def diagnostics
        callers.each { |caller| check_edges(caller) }
        check_cycles
        @diagnostics
      end

      private

      def callers
        @staging.declared_queries + @staging.declared_actions + @staging.declared_proposal_participants
      end

      def participants
        @live.proposal_participants.merge(@staging.declared_proposal_participants.to_h { |item| [item.name, item] })
      end

      def check_edges(caller)
        names = caller.participants
        unless names.is_a?(Array) && names.all?(String) && names.uniq.length == names.length
          return problem(caller, "participants must be a list of distinct participant names")
        end

        names.each do |name|
          participant = participants[name]
          owner = participant&.owner
          next if participant && (owner == caller.owner || requires(caller.owner).include?(owner))

          message = if participant
                      "#{caller.name} calls #{name}, which belongs to #{participant.owner}; " \
                        "#{caller.owner} must require it."
                    else
                      "#{caller.name} calls #{name}, which no feature declares as a proposal participant."
                    end
          add("registration.missing_dependency", caller.owner, caller.name, message, owner || name)
        end
      end

      def requires(feature_id)
        feature = @staging.declared_features.find { |item| item.id == feature_id } || @live.features[feature_id]
        feature ? Array(feature.requires) : []
      end

      def check_cycles
        graph = participants
        @staging.declared_proposal_participants.each do |start|
          path = cycle_through(start.name, graph, [start.name])
          next unless path

          add("registration.cycle", start.owner, start.name,
              "Proposal participants call each other in a cycle: #{path.join(' -> ')}.")
        end
      end

      def cycle_through(name, graph, path)
        Array(graph[name]&.participants).each do |next_name|
          return path + [next_name] if next_name == path.first
          next if path.include?(next_name)

          found = cycle_through(next_name, graph, path + [next_name])
          return found if found
        end
        nil
      end
    end

    # Feature codes are not names under a feature id, so they take their own checks.
    class CodeValidation < Validation
      CODE_PATTERN = /\A[a-z][a-z0-9_]*\.[a-z][a-z0-9_]*\z/.freeze

      def diagnostics
        check_codes
        check_refusals
        @diagnostics
      end

      private

      # A code is `noun.condition`, declared once, with a description; one feature owns each noun, and
      # the foundation's nouns are listed in context/CONTRACTS.md rather than declared.
      def check_codes
        nouns = @live.codes.values.to_h { |code| [code.code.split(".").first, code.owner] }
        seen = @live.codes.keys
        @staging.declared_codes.each do |code|
          noun = code.code.to_s.split(".").first
          if !code.code.is_a?(String) || !CODE_PATTERN.match?(code.code) || !text?(code.description)
            add("registration.schema_invalid", code.owner, code.code.to_s,
                "#{code.code} must be a lowercase noun.condition string with a description.")
          elsif Declarations::FOUNDATION_CODE_NOUNS.include?(noun)
            add("registration.schema_invalid", code.owner, code.code,
                "#{code.code} uses a foundation noun; foundation codes are listed in context/CONTRACTS.md.")
          elsif seen.include?(code.code)
            add("registration.duplicate_id", code.owner, code.code, "#{code.code} is declared more than once.")
          elsif nouns.fetch(noun, code.owner) != code.owner
            add("registration.duplicate_id", code.owner, code.code,
                "The #{noun} noun belongs to #{nouns.fetch(noun)}.", nouns.fetch(noun))
          end
          seen << code.code
          nouns[noun] ||= code.owner
        end
      end

      def check_refusals
        (@staging.declared_operations + @staging.declared_proposal_participants).each do |operation|
          check_refusal_list(operation, operation.refuses, Refusals.common(operation))
        end
      end
    end

    # The two library seams form one registration boundary. Reuse the shared schema and diagnostic
    # helpers, while keeping these ownership and wire-contract checks together.
    class LibraryValidation < Validation
      def diagnostics
        check_library_kinds
        check_library_providers
        @diagnostics
      end

      private

      def check_library_version(item, part, version)
        return if version == Declarations::CONTRACT_VERSION

        add("registration.contract_major", item.owner, item.name,
            "#{item.name} #{part} #{version.inspect} is unsupported; this build provides 1.")
      end

      def wire_kind?(value)
        value.is_a?(String) && /\A[a-z][a-z0-9_]*\z/.match?(value)
      end

      def check_library_kinds
        seen = @live.library_kinds.values.to_h { |item| [item.adapter.wire_kind, item.name] }
        @staging.declared_library_kinds.each do |item|
          check_library_version(item, "contract", item.contract_version)
          check_library_kind_owner(item)
          adapter = item.adapter
          unless adapter.is_a?(Declarations::LibraryAdapter)
            problem(item, "needs a LibraryAdapter")
            next
          end
          check_library_wire_kind(item, adapter, seen)
          check_library_version(item, "wire version", adapter.wire_version)
          check_library_version(item, "fingerprint version", adapter.fingerprint_version)
          %i[wire_schema mapped_schema].each do |part|
            add_schema_problems(item, part, adapter[part])
            problem(item, "#{part} must be an object") unless adapter[part].is_a?(Hash) &&
                                                              adapter[part]["type"] == "object"
          end
          check_library_fingerprint_fields(item, adapter)
          %i[map reverse fingerprint display_label].each do |part|
            problem(item, "needs callable #{part}") unless adapter[part].respond_to?(:call)
          end
          check_library_identity(item, adapter)
          %i[local_read create replace assign].each do |part|
            next if part == :assign && adapter[part].nil?

            check_library_callback(item, part, adapter[part])
          end
        end
      end

      # A row's identity is its wire `id`: a required string, whatever else the kind's vocabulary holds.
      def check_library_identity(item, adapter)
        schema = adapter.wire_schema
        id = schema.is_a?(Hash) && schema["properties"].is_a?(Hash) ? schema["properties"]["id"] : nil
        return if id.is_a?(Hash) && Array(id["type"]) == ["string"] && Array(schema["required"]).include?("id")

        problem(item, "wire_schema must declare id as a required string")
      end

      def check_library_kind_owner(item)
        registered = @staging.declared_record_kinds.any? { |kind| kind.id == item.record_kind } ||
                     @live.record_kinds.key?(item.record_kind)
        unless registered
          add("registration.missing_dependency", item.owner, item.name,
              "#{item.name} needs registered catalog kind #{item.record_kind.inspect}.", item.record_kind)
          return
        end
        kind_owner = @staging.owner_of(item.record_kind)
        problem(item, "must own record kind #{item.record_kind}") unless kind_owner == item.owner
      end

      def check_library_wire_kind(item, adapter, seen)
        unless wire_kind?(adapter.wire_kind)
          problem(item, "wire kind must be a lowercase identifier")
          return
        end
        if seen.key?(adapter.wire_kind)
          add("registration.duplicate_id", item.owner, item.name,
              "Wire kind #{adapter.wire_kind} is declared by #{seen[adapter.wire_kind]} and #{item.name}.")
        end
        seen[adapter.wire_kind] ||= item.name
      end

      def check_library_fingerprint_fields(item, adapter)
        fields = adapter.fingerprint_fields
        properties = adapter.mapped_schema.is_a?(Hash) ? adapter.mapped_schema["properties"] : nil
        valid = fields.is_a?(Array) && !fields.empty? && fields.uniq.length == fields.length &&
                fields.all? { |field| text?(field) && properties.is_a?(Hash) && properties.key?(field) }
        problem(item, "fingerprint_fields must be ordered unique mapped property names") unless valid
      end

      def check_library_callback(item, part, callback)
        unless callback.is_a?(Declarations::LibraryCallback)
          problem(item, "#{part} needs a LibraryCallback")
          return
        end
        %i[params result].each { |schema| add_schema_problems(item, "#{part}.#{schema}", callback[schema]) }
        problem(item, "#{part} params must be an object") unless callback.params.is_a?(Hash) &&
                                                                 callback.params["type"] == "object"
        problem(item, "#{part} needs a callable handler") unless callback.handler.respond_to?(:call)
        check_refusal_list(item, callback.refuses, Refusals::ANY_OPERATION, "#{part}.refuses")
      end

      def check_library_providers
        adapters = @live.library_kinds.values + @staging.declared_library_kinds
        known = adapters.filter_map do |item|
          item.adapter.wire_kind if item.adapter.is_a?(Declarations::LibraryAdapter)
        end
        @staging.declared_library_providers.each do |item|
          check_library_version(item, "contract", item.contract_version)
          problem(item, "needs a callable factory") unless item.factory.respond_to?(:call)
          kinds = item.kinds
          next if kinds == ["*"]

          unless kinds.is_a?(Array) && !kinds.empty? && kinds.uniq.length == kinds.length &&
                 kinds.all? { |kind| wire_kind?(kind) }
            problem(item, "kinds must be unique wire identifiers or the exclusive wildcard [\"*\"]")
            next
          end
          (kinds - known).each do |kind|
            add("registration.missing_dependency", item.owner, item.name,
                "#{item.name} serves #{kind}, which has no registered adapter.", kind)
          end
        end
      end
    end
  end
end
