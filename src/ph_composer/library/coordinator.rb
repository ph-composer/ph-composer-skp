# frozen_string_literal: true

require_relative "callback_invoker"
require_relative "dependencies"
require_relative "resolver"
require_relative "state"

module PhComposer
  module Library
    # Review resolves detached values. Explicit choices call only the record owner's registered
    # callbacks, with copy and assignment sharing the dispatcher's single guarded proposal. A row that names
    # records of other kinds (Dependencies) has each copied or reused first, in the same proposal.
    module Coordinator
      # What a copy reviews: the kind's declaration, the catalog entry and row, the row mapped to local
      # values, its source identity, and how it resolves against the local records. `mapped` keeps the row's
      # own record ids for its dependencies; the resolution compares it in local terms.
      Review = Struct.new(:declaration, :entry, :row, :mapped, :source, :resolution, keyword_init: true)
      FINGERPRINT = /\A[0-9a-f]{64}\z/.freeze

      module_function

      def inspect_row(request)
        review(request, *selected(request))
      end

      # The Review of one catalog row of `declaration`'s kind, read from `entry`.
      def review(request, declaration, entry, row)
        adapter = declaration.adapter
        mapped = map(adapter, row.fetch("snapshot"))
        source = source_identity(provider(request), row, adapter.wire_kind)
        Review.new(:declaration => declaration, :entry => entry, :row => row, :mapped => mapped, :source => source,
                   :resolution => resolution(request, declaration, source, mapped))
      end

      # How `mapped`, the row `source` names, resolves against the local records of its kind.
      def resolution(request, declaration, source, mapped)
        adapter = declaration.adapter
        locals = CallbackInvoker.call(request, declaration, adapter.local_read, {}, :readonly => true)
        resolve(adapter, source, Dependencies.in_local_terms(request, source, adapter, mapped), locals,
                :fingerprint_of => mapped)
      end

      # Compare incoming semantic content with the stored attribution, not with local edits.
      # An older fingerprint contract cannot establish whether the provider changed. The fingerprint is the
      # row's own (`fingerprint_of`), as its attribution stores it, when `mapped` is in local terms.
      def resolve(adapter, source, mapped, locals, fingerprint_of: mapped)
        result = Resolver.resolve(:source => source, :mapped => mapped, :label => label(adapter, mapped),
                                  :locals => locals.map { |row| labelled(adapter, row) })
        fingerprint = semantic_fingerprint(adapter, fingerprint_of)
        result.fetch("candidates").each do |candidate|
          attribution = locals.find { |row| row.fetch("id") == candidate.fetch("id") }["source"]
          compatible = attribution.is_a?(Hash) && attribution["kind"] == "library" &&
                       attribution["fingerprint_version"] == adapter.fingerprint_version &&
                       attribution["fingerprint"].is_a?(String) && FINGERPRINT.match?(attribution["fingerprint"])
          candidate["comparison_available"] = !!compatible
          candidate["source_changed"] = compatible ? attribution["fingerprint"] != fingerprint : nil
        end
        result
      end

      # The incoming row was admitted with a label, so its projection must give one again. A local
      # record may have none; it then matches by source only.
      def label(adapter, mapped)
        Admission.label_for(adapter, mapped) ||
          raise(Error.new("library.adapter_invalid", "The kind adapter returned no display label."))
      end

      def labelled(adapter, row)
        row.merge("display_label" => Admission.label_for(adapter, row.fetch("mapped")))
      end
      private_class_method :label, :labelled

      def copy(request, proposal)
        review = inspect_row(request)
        declaration = review.declaration
        resolution = review.resolution
        choice = request.params.fetch("choice")
        result = { "resolution" => resolution, "local_id" => nil, "assigned" => false, "dependencies" => [] }
        id = local_id(request.params["local_id"], resolution)
        use = nil
        case choice
        when "create"
          unless resolution.fetch("outcome") == "create"
            raise Error.new("library.review_required", "Resolve the existing local candidates before copying.")
          end

          use = authorize_use(request, review)
          values, result["dependencies"] = copy_dependencies(request, proposal, review)
          value = CallbackInvoker.call(request, declaration, declaration.adapter.create,
                                       { "values" => values.merge("source" => attribution(request, review, use)) })
          id = value.fetch("id")
        when "keep_local"
          raise Error.new("library.local_choice_required", "Choose an existing local record.") unless id
        when "use_library"
          raise Error.new("library.local_choice_required", "Choose an existing local record.") unless id

          expected = request.params["expected_values"]
          unless reviewed_values?(expected, id, resolution)
            raise Error.new("params.invalid", "Replacement needs the reviewed local values.")
          end

          use = authorize_use(request, review)
          values, result["dependencies"] = copy_dependencies(request, proposal, review)
          CallbackInvoker.call(request, declaration, declaration.adapter.replace,
                               { "id" => id, "values" => values.merge("source" => attribution(request, review, use)),
                                 "expected_values" => expected })
        else
          raise Error.new("params.invalid", "Choose an explicit library copy action.")
        end
        result["assigned"] = assign(request, declaration, id)
        hold_until_commit(use, proposal)
        result["local_id"] = id
        result
      rescue StandardError => error
        proposal.refuse(error)
        raise
      end

      # [`review`'s values in local terms, a report of each dependency]: every record the row names copied from
      # the same library first, or its local copy from that source reused, each once (`copying`, by kind and
      # record id). A record the loaded catalog does not hold refuses the copy, and so does one whose name a
      # local record of other values already holds, until that record is resolved by its own copy.
      def copy_dependencies(request, proposal, review, copying = {})
        adapter = review.declaration.adapter
        ids = {}
        reports = Dependencies.targets(adapter, review.mapped).flat_map do |target|
          local_id, rows = copy_dependency(request, proposal, review, target, copying)
          (ids[target.fetch("kind")] ||= {})[target.fetch("id")] = local_id
          rows
        end
        [Dependencies.remap(adapter, review.mapped, ids), reports]
      end

      def copy_dependency(request, proposal, referrer, target, copying)
        key = target.values_at("kind", "id")
        if copying.key?(key)
          raise Error.new("library.adapter_invalid", "Library dependencies refer to each other.") unless copying[key]

          return [copying[key], []]
        end

        copying[key] = nil
        review = dependency_review(request, referrer, target)
        resolution = review.resolution
        case resolution.fetch("outcome")
        when "reuse"
          id = resolution.fetch("candidates").first.fetch("id")
          reports = [Dependencies.report(target, id, "reused")]
        when "create"
          use = authorize_use(request, review)
          values, reports = copy_dependencies(request, proposal, review, copying)
          id = CallbackInvoker.call(request, review.declaration, review.declaration.adapter.create,
                                    { "values" => values.merge("source" => attribution(request, review, use)) })
                              .fetch("id")
          hold_until_commit(use, proposal)
          reports += [Dependencies.report(target, id, "created")]
        else
          raise Error.new("library.review_required", "#{review.row.fetch('display_label')} (#{target.fetch('kind')}) " \
                                                     "needs review: copy it on its own first.",
                          target.merge("outcome" => resolution.fetch("outcome")))
        end
        copying[key] = id
        [id, reports]
      end

      # The Review of a dependency's row, in the current catalog of its kind from the referrer's library.
      def dependency_review(request, referrer, target)
        kind = target.fetch("kind")
        library_id = referrer.row.fetch("library_id")
        entry = State.for(request.session).fetch(request.params.fetch("provider_id"), kind, request.registry)
        rows = entry.fetch("rows").select do |row|
          row.fetch("library_id") == library_id && row.fetch("record_id") == target.fetch("id")
        end
        unless rows.length == 1
          raise Error.new("library.dependency_missing",
                          "#{referrer.row.fetch('display_label')} names #{kind} #{target.fetch('id')}, which the " \
                          "loaded #{kind} catalog of its library does not hold. Load #{kind}, or correct the file.",
                          { "kind" => kind, "library_id" => library_id, "record_id" => target.fetch("id"),
                            "catalog_state" => entry.fetch("state") })
        end

        review(request, State.kind(kind, request.registry), entry, rows.first)
      end

      # A version 2 source's use check (Connection::Use) before any write is staged; nil for version 1.
      # Keeping a local record takes nothing from the library, so it needs none.
      def authorize_use(request, review)
        Connection::Use.authorize(request, provider(request), review.entry, review.row)
      end

      # The use answer must still hold now and when the enclosing action commits, which for a participant
      # may be after further imports; the proposal checks it again then.
      def hold_until_commit(use, proposal)
        return unless use

        use.confirm!
        proposal.add_commit_check { use.confirm! }
      end

      def assign(request, declaration, id)
        target = request.params["assignment"]
        return false unless target
        unless declaration.adapter.assign
          raise Error.new("library.assignment_unavailable", "This record kind does not support assignment.")
        end

        CallbackInvoker.call(request, declaration, declaration.adapter.assign, { "target" => target, "local_id" => id })
        true
      end

      def reviewed_values?(expected, id, resolution)
        # An empty guard is valid when the local record has no authored values to guard.
        return false unless expected.is_a?(Hash)

        candidate = resolution.fetch("candidates").find { |row| row.fetch("id") == id }
        actual = candidate.fetch("expected_values")
        actual.all? { |field, value| expected.key?(field) && expected[field] == value }
      end

      def selected(request)
        params = request.params
        declaration = State.kind(params.fetch("kind"), request.registry)
        entry = State.for(request.session).fetch(params.fetch("provider_id"), params.fetch("kind"), request.registry,
                                                 :generation => params.fetch("generation"))
        [declaration, entry, row_in(entry, params)]
      end

      # The one catalog row `params` names by `library_id` and `record_id`; none or two refuse.
      def row_in(entry, params)
        rows = entry.fetch("rows").select do |row|
          row.fetch("library_id") == params.fetch("library_id") && row.fetch("record_id") == params.fetch("record_id")
        end
        unless rows.length == 1
          raise Error.new("library.row_unavailable", "The selected library record is unavailable or ambiguous.")
        end

        rows.first
      end

      # A catalog snapshot mapped to local values by the kind's adapter, refused when the adapter returns
      # anything outside its declared mapped schema.
      def map(adapter, snapshot)
        mapped = adapter.map.call(DeepCopy.call(snapshot))
        validate!(mapped, adapter.mapped_schema)
        DeepCopy.call(mapped)
      end

      # Where a catalog row comes from, as a copied record's attribution names it.
      def source_identity(provider, row, record_kind)
        { "provider_kind" => provider.provider_kind, "library_id" => row.fetch("library_id"),
          "record_kind" => record_kind, "record_id" => row.fetch("record_id") }
      end

      def provider(request)
        State.for(request.session).provider(request.params.fetch("provider_id"), request.registry)
      end

      def semantic_fingerprint(adapter, mapped)
        fingerprint = adapter.fingerprint.call(DeepCopy.call(mapped))
        return fingerprint if fingerprint.is_a?(String) && FINGERPRINT.match?(fingerprint)

        raise Error.new("library.adapter_invalid", "The kind adapter returned an invalid semantic fingerprint.")
      end

      # The `source` a copied record carries: its identity, the semantic fingerprint and the snapshot fields
      # the adapter maps, and for a version 2 source its exact source revision.
      def attribution(request, review, use)
        adapter = review.declaration.adapter
        identity = review.source
        # The fingerprint is checked before the copy time is taken, so a refused copy caches no time.
        fingerprint = semantic_fingerprint(adapter, review.mapped)
        snapshot = review.row.fetch("snapshot").slice(*adapter.mapped_schema.fetch("properties").keys)
        copied_at = State.for(request.session).copy_time(request.revision, [review.entry.fetch("generation"), identity])
        value = identity.merge("kind" => "library", "fingerprint" => fingerprint,
                               "fingerprint_version" => adapter.fingerprint_version, "copied_at" => copied_at,
                               "snapshot" => DeepCopy.call(snapshot))
        return value unless use

        value.merge("source_revision" => use.source_revision, "source_revision_schema_version" => 1)
      end

      def local_id(id, resolution)
        candidates = resolution.fetch("candidates")
        return candidates.first.fetch("id") if id.nil? && candidates.length == 1
        return nil if id.nil? && candidates.empty?
        return id if candidates.any? { |row| row.fetch("id") == id }

        raise Error.new("library.local_choice_required", "Choose one of the reviewed local candidates.")
      end

      def validate!(value, schema)
        return if JsonValue.problems(value).empty? && JsonSchema.validate(value, schema).empty?

        raise Error.new("library.adapter_invalid", "The kind adapter returned invalid mapped values.")
      end
      private_class_method :reviewed_values?, :authorize_use, :hold_until_commit, :assign, :selected, :provider,
                           :copy_dependencies, :copy_dependency, :dependency_review,
                           :semantic_fingerprint, :attribution, :local_id, :validate!
    end
  end
end
