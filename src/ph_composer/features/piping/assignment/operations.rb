# frozen_string_literal: true

module PhComposer
  module Piping
    module Assignment
      # Assign, over the shared layer's resolve and write step (LineGroups::EdgeOperations, which also owns Clear and
      # the rewrite a Pipe Type delete makes). It refuses the whole command if one target is stale, outside a Piping
      # group, in a Piping group a Zone holds or behind a write refusal; the dispatcher owns the native operation.
      module Operations
        module_function

        # One record per Edge, all in one step: a fresh `ppe_` id on a first assignment, the Edge's own id and
        # metadata on a reassignment. The role's values are `role_values` over the Edge's own when it keeps its role,
        # else over the role's defaults; a value the role does not take refuses, and a new role drops the old one's.
        def assign(request, proposal, targets:, pipe_type_id:, role:, role_values:)
          extra = role_values.keys - ROLE_VALUES.fetch(role).keys
          unless extra.empty?
            raise CodedError.new("params.invalid", "A #{role} pipe does not take #{extra.join(', ')}.")
          end

          request.engine.find(PIPE_TYPE_KIND, pipe_type_id)
          allocate = Records::Identity.allocator(request, request.params)
          edges = LineGroups::EdgeOperations
          resolved = edges.resolve(LINE_GROUP, request, targets, :limit => Assignment.gesture_edge_limit)
          updates = resolved.filter_map do |reference, before|
            if before && before["schema_version"] != 1
              raise CodedError.new("validation.failed", "An Edge's pipe assignment is schema version " \
                                                        "#{before['schema_version'].inspect}, which this version " \
                                                        "cannot rewrite.")
            end

            after = (before || {}).slice("id", "user_data", "extension_data")
            after["id"] = allocate.call("ppe") unless Assignment.identity(after)
            kept = before && before["role"] == role ? before.slice(*ROLE_VALUES.fetch(role).keys) : {}
            after = { "user_data" => {}, "extension_data" => {} }.merge(after).merge(
              "schema_version" => 1, "pipe_type_id" => pipe_type_id, "role" => role
            ).merge(ROLE_VALUES.fetch(role)).merge(kept).merge(role_values)
            next if after == before

            edges.update(LINE_GROUP, reference, before, LINE_GROUP.validate_edge!(after))
          end
          edges.propose(LINE_GROUP, proposal, updates)
          { "edge_ids" => updates.map { |row| row.fetch("after").fetch("id") } }
        end
      end
    end
  end
end
