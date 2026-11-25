# frozen_string_literal: true

module PhComposer
  module Piping
    PIPE_KIND = "#{FEATURE_ID}.pipe".freeze

    # The pipe assignment one Sketchup::Edge keeps directly inside a Piping group: its Pipe Type, its role and the
    # role's values. The Edge is the record; no registry lists pipes (context/TECH_STACK.md, "Edge-owned
    # assignments"). A split or a native copy carries the record, `ppe_` id included, onto each piece, so one id held
    # by several Edges is routine: reads mark it copied and nothing re-issues it.
    module Assignment
      STORE = Records::EntityStore.new(FEATURE_ID)
      # One assign or clear reaches at most this many Edges; one more refuses the whole command.
      GESTURE_EDGE_LIMIT = 250
      ID_PATTERN = Records::Identity.pattern("ppe")
      ROLES = %w[trunk branch twig recirculation].freeze
      # Each role's values with their defaults: required for that role and absent for every other, so a new role
      # drops what the old one carried. A trunk repeats `multiplier` times; a recirculation pipe runs at its water
      # temperature for its hours a day, honeybee-ph's 60 C and 24 h by default.
      ROLE_VALUES = {
        "trunk" => { "multiplier" => 1, "demand_recirculation" => false },
        "branch" => {}, "twig" => {},
        "recirculation" => { "water_temp_c" => 60.0, "daily_period" => 24 }
      }.freeze
      ROLE_SCHEMAS = {
        "multiplier" => { "type" => "integer", "minimum" => 1,
                          "description" => "A trunk only: how many identical risers this one stands for; 1 by " \
                                           "default." },
        "demand_recirculation" => { "type" => "boolean",
                                    "description" => "A trunk only: whether it has demand recirculation; false by " \
                                                     "default." },
        "water_temp_c" => { "type" => "number", "minimum" => 0, "maximum" => 100, "x-unit" => "C",
                            "description" => "A recirculation pipe only: its water temperature, 0 to 100; 60 by " \
                                             "default." },
        "daily_period" => { "type" => "number", "minimum" => 0, "maximum" => 24, "x-unit" => "h",
                            "description" => "A recirculation pipe only: hours a day it runs, 0 to 24; 24 by " \
                                             "default." }
      }.freeze

      TYPE_REFERENCE = Records::Reference.new(:key => "pipe_type_id", :target_kind => PIPE_TYPE_KIND,
                                              :cardinality => "one")
      RECORD_KIND = Records::RecordKind.new(
        :id => PIPE_KIND, :label => "Pipe assignment", :schema_version => 1, :id_prefix => "ppe",
        :fields => [
          Records::AuthoringFields.field("pipe_type_id", { "type" => %w[string null],
                                                           "description" => "The Pipe Type; null once its type " \
                                                                            "was deleted with null, which blocks " \
                                                                            "export." }, :required => true),
          Records::AuthoringFields.field("role", { "type" => "string", "enum" => ROLES }, :required => true)
        ] + ROLE_SCHEMAS.map { |key, schema| Records::AuthoringFields.field(key, schema) },
        :references => [TYPE_REFERENCE],
        :validate => ->(values) { Assignment.role_problems(values.fetch("role"), values) }
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
      PhComposer.on_reset("piping_assignment") { reset_for_test }

      module_function

      # Why `values` do not carry exactly `role`'s values: one it does not take, or one it needs and lacks.
      def role_problems(role, values)
        wanted = ROLE_VALUES.fetch(role, {}).keys
        extra = (ROLE_SCHEMAS.keys - wanted).select { |key| values.key?(key) }
        missing = wanted.reject { |key| values.key?(key) }
        extra.map { |key| "a #{role} pipe does not take #{key}" } + missing.map { |key| "a #{role} pipe needs #{key}" }
      end

      def identity(record)
        id = record && record["id"]
        ID_PATTERN.match?(id.to_s) ? id : nil
      end

      def values(record)
        record ? RECORD_KIND.values(record) : {}
      end
    end
  end
end
