# frozen_string_literal: true

module PhComposer
  module Ducting
    DUCT_KIND = "#{FEATURE_ID}.duct".freeze

    # The duct assignment one Sketchup::Edge keeps directly inside a Ducting group: its Duct Type, its direction and
    # how many identical ducts it stands for. The Edge is the record; no registry lists ducts (context/TECH_STACK.md,
    # "Edge-owned assignments"). A split or a native copy carries the record, `dce_` id included, onto each piece, so
    # one id held by several Edges is routine: reads mark it copied and nothing re-issues it.
    module Assignment
      STORE = Records::EntityStore.new(FEATURE_ID)
      # One assign or clear reaches at most this many Edges; one more refuses the whole command.
      GESTURE_EDGE_LIMIT = 250
      # Stored lower case, shown Outdoor air and Exhaust air: the cold intake from the outside to the ventilator, which
      # honeybee-ph calls supply, and the exhaust from the ventilator to the outside.
      DIRECTIONS = %w[outdoor_air exhaust_air].freeze
      # Far above any building's count of identical units, and low enough that a length times it stays a finite
      # number a reply can carry.
      QUANTITY_LIMIT = 10_000
      VALUE_SCHEMAS = {
        "duct_type_id" => { "type" => %w[string null],
                            "description" => "The Duct Type; null once its type was deleted with null, which " \
                                             "blocks export." },
        "direction" => { "type" => "string", "enum" => DIRECTIONS,
                         "description" => "outdoor_air (shown Outdoor air) or exhaust_air (shown Exhaust air)." },
        "quantity" => { "type" => "integer", "minimum" => 1, "maximum" => QUANTITY_LIMIT,
                        "description" => "How many identical ducts this line stands for; 1 by default." }
      }.freeze

      TYPE_REFERENCE = Records::Reference.new(:key => "duct_type_id", :target_kind => DUCT_TYPE_KIND,
                                              :cardinality => "one")
      RECORD_KIND = Records::RecordKind.new(
        :id => DUCT_KIND, :label => "Duct assignment", :schema_version => 1, :id_prefix => "dce",
        :fields => VALUE_SCHEMAS.map { |key, schema| Records::AuthoringFields.field(key, schema, :required => true) },
        :references => [TYPE_REFERENCE]
      )

      class << self
        # The shipped bound is always GESTURE_EDGE_LIMIT; a test lowers it, and reset_for_test puts it back.
        attr_writer :gesture_edge_limit

        def gesture_edge_limit
          @gesture_edge_limit ||= GESTURE_EDGE_LIMIT
        end

        def reset_for_test
          @gesture_edge_limit = nil
        end
      end
      PhComposer.on_reset("ducting_assignment") { reset_for_test }

      module_function

      def values(record)
        record ? RECORD_KIND.values(record) : {}
      end
    end
  end
end
