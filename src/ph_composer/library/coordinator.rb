# frozen_string_literal: true

require_relative "callback_invoker"
require_relative "resolver"
require_relative "state"

module PhComposer
  module Library
    # Review resolves detached values. Explicit choices call only the record owner's registered
    # callbacks, with copy and assignment sharing the dispatcher's single guarded proposal.
    module Coordinator
      # What a copy reviews: the kind's declaration, the catalog entry and row, the row mapped to local
      # values, its source identity, and how it resolves against the local records.
      Review = Struct.new(:declaration, :entry, :row, :mapped, :source, :resolution, keyword_init: true)
      FINGERPRINT = /\A[0-9a-f]{64}\z/.freeze

      module_function

      def inspect_row(request)
        declaration, entry, row = selected(request)
        mapped = map(declaration.adapter, row.fetch("snapshot"))
        source = source_identity(provider(request), row, request.params.fetch("kind"))
        locals = CallbackInvoker.call(request, declaration, declaration.adapter.local_read, {}, :readonly => true)
        Review.new(:declaration => declaration, :entry => entry, :row => row, :mapped => mapped, :source => source,
                   :resolution => resolve(declaration.adapter, source, mapped, locals))
      end

      # Compare incoming semantic content with the stored attribution, not with local edits.
      # An older fingerprint contract cannot establish whether the provider changed.
      def resolve(adapter, source, mapped, locals)
        result = Resolver.resolve(:source => source, :mapped => mapped, :label => label(adapter, mapped),
                                  :locals => locals.map { |row| labelled(adapter, row) })
        fingerprint = semantic_fingerprint(adapter, mapped)
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
        result = { "resolution" => resolution, "local_id" => nil, "assigned" => false }
        id = local_id(request.params["local_id"], resolution)
        use = nil
        case choice
        when "create"
          unless resolution.fetch("outcome") == "create"
            raise Error.new("library.review_required", "Resolve the existing local candidates before copying.")
          end

          use = authorize_use(request, review)
          value = CallbackInvoker.call(request, declaration, declaration.adapter.create,
                                       { "values" => review.mapped.merge("source" => attribution(request, review,
                                                                                                 use)) })
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
          CallbackInvoker.call(request, declaration, declaration.adapter.replace,
                               { "id" => id, "values" => review.mapped.merge("source" => attribution(request, review,
                                                                                                     use)),
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
        rows = entry.fetch("rows").select do |row|
          row.fetch("library_id") == params.fetch("library_id") && row.fetch("record_id") == params.fetch("record_id")
        end
        unless rows.length == 1
          raise Error.new("library.row_unavailable", "The selected library record is unavailable or ambiguous.")
        end

        [declaration, entry, rows.first]
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
                           :semantic_fingerprint, :attribution, :local_id, :validate!
    end
  end
end
