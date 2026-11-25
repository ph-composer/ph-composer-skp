# frozen_string_literal: true

module PhComposer
  module Ducting
    module Assignment
      # Assign, over the shared layer's resolve and write step (LineGroups::EdgeOperations, which also owns Clear and
      # the rewrite a Duct Type delete makes). It refuses the whole command if one target is stale, outside a Ducting
      # group, in a Ducting group a Zone holds or behind a write refusal; the dispatcher owns the native operation.
      module Operations
        # What a first assignment must be given; a reassign keeps what it is not given.
        FIRST_NEEDS = %w[duct_type_id direction].freeze

        module_function

        # One record per Edge, all in one step: a fresh `dce_` id and quantity 1 on a first assignment, the Edge's own
        # id, metadata and values on a reassignment, with `values` (any of duct_type_id, direction and quantity)
        # written over them.
        def assign(request, proposal, targets:, values:)
          request.engine.find(DUCT_TYPE_KIND, values["duct_type_id"]) if values.key?("duct_type_id")
          allocate = Records::Identity.allocator(request, request.params)
          edges = LineGroups::EdgeOperations
          resolved = edges.resolve(LINE_GROUP, request, targets, :limit => Assignment.gesture_edge_limit)
          updates = resolved.filter_map do |reference, before|
            check_rewritable!(before, values)
            after = { "user_data" => {}, "extension_data" => {}, "quantity" => 1 }
                    .merge((before || {}).slice("id", "user_data", "extension_data", *VALUE_SCHEMAS.keys))
                    .merge("schema_version" => 1).merge(values)
            after["id"] = allocate.call(RECORD_KIND.id_prefix) unless LINE_GROUP.edge_identity(after)
            next if after == before

            edges.update(LINE_GROUP, reference, before, LINE_GROUP.validate_edge!(after))
          end
          edges.propose(LINE_GROUP, proposal, updates)
          { "edge_ids" => updates.map { |row| row.fetch("after").fetch("id") } }
        end

        # A record of another schema version, which this version cannot rewrite, refuses; an Edge with none needs a
        # Duct Type and a direction, since a duct with no direction cannot be written.
        def check_rewritable!(before, values)
          if before && before["schema_version"] != 1
            raise CodedError.new("validation.failed", "An Edge's duct assignment is schema version " \
                                                      "#{before['schema_version'].inspect}, which this version " \
                                                      "cannot rewrite.")
          end
          missing = before ? [] : FIRST_NEEDS - values.keys
          return if missing.empty?

          raise CodedError.new("params.invalid", "An Edge with no duct assignment needs #{missing.join(' and ')}.")
        end
      end
    end
  end
end
