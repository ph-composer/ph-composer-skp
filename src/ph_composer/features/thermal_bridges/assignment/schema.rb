# frozen_string_literal: true

module PhComposer
  module ThermalBridges
    EDGE_KIND = "#{FEATURE_ID}.edge"

    # The assignment a thermal bridge keeps on one Sketchup::Edge inside a Zone: the Thermal Bridge Type
    # it names and how many times it counts. The Edge is the record; no registry lists tagged Edges
    # (context/TECH_STACK.md, "Edge-owned assignments"). The `tbe_` id proves identity in a reference, as
    # a Face's `fac_` does. A split or a native copy carries the record, id included, so one id held by
    # several Edges is routine: reads mark it copied and nothing re-issues it.
    module Assignment
      STORE = Records::EntityStore.new("ph_composer.thermal_bridge")
      # One assign or clear reaches at most this many Edge occurrences; one more refuses the whole command.
      GESTURE_EDGE_LIMIT = 250
      DEFAULT_QUANTITY = 1

      TYPE_REFERENCE = Records::Reference.new(:key => "thermal_bridge_type_id", :target_kind => TYPE_KIND,
                                              :cardinality => "one", :required => true)
      RECORD_KIND = Records::RecordKind.new(
        :id => EDGE_KIND, :label => "Thermal bridge assignment", :schema_version => 1, :id_prefix => "tbe",
        :fields => [TYPE_REFERENCE,
                    Fields.field("quantity", { "type" => "number", "exclusiveMinimum" => 0 }, :required => true)]
      )

      class << self
        # The shipped bound is always GESTURE_EDGE_LIMIT. The writer exists so a test can reach the ceiling
        # without building hundreds of Edges, and reset_for_test puts it back.
        attr_writer :gesture_edge_limit

        def gesture_edge_limit
          @gesture_edge_limit ||= GESTURE_EDGE_LIMIT
        end

        def reset_for_test
          @gesture_edge_limit = nil
        end
      end
      PhComposer.on_reset("thermal_bridges.assignment") { reset_for_test }

      module_function

      def validate!(record)
        found = RECORD_KIND.problems(record)
        return record if found.empty?

        raise CodedError.new("validation.failed", "A thermal bridge assignment record is invalid: #{found.first}.",
                             "findings" => found)
      end

      def values(record)
        record ? RECORD_KIND.values(record) : {}
      end

      def check_limit!(count)
        limit = gesture_edge_limit
        return if count <= limit

        raise CodedError.new("gesture.too_large", "One command changes at most #{limit} Edges; this one has #{count}.")
      end
    end
  end
end
