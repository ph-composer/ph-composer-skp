# frozen_string_literal: true

module PhComposer
  module Library
    # What discovery and `describe` say about one registered library kind (context/AGENT_INTERFACE.md,
    # "Discover before acting"), read from its declaration alone, so an outside kind's adapter is
    # described with no change here or in any transport. `assignment` is the target shape
    # `ph_composer.library.copy` takes as its `assignment` param, with the adapter's own examples; a kind
    # without an assign callback says so rather than publishing an empty shape.
    module KindDescriptor
      module_function

      def summary(declaration)
        adapter = declaration.adapter
        { "name" => declaration.name, "owner" => declaration.owner, "wire_kind" => adapter.wire_kind,
          "wire_version" => adapter.wire_version, "record_kind" => declaration.record_kind,
          "assignment_supported" => !adapter.assign.nil? }
      end

      def call(declaration)
        adapter = declaration.adapter
        { "kind" => "library_kind" }.merge(summary(declaration)).merge(
          "contract_version" => declaration.contract_version, "fingerprint_version" => adapter.fingerprint_version,
          "wire_schema" => adapter.wire_schema, "copy" => "#{FEATURE_ID}.copy",
          "assignment" => assignment(adapter.assign)
        )
      end

      def assignment(callback)
        unless callback
          return { "supported" => false, "refusal" => "library.assignment_unavailable",
                   "description" => "This kind copies without assignment; ph_composer.library.copy refuses an " \
                                    "assignment for it." }
        end

        { "supported" => true, "target" => callback.params.dig("properties", "target"),
          "examples" => Array(callback.examples).filter_map { |example| example["target"] },
          "refuses" => callback.refuses.sort,
          "description" => "Send one target as ph_composer.library.copy's assignment; the copy and the " \
                           "assignment are one Undo step." }
      end
    end
  end
end
