# frozen_string_literal: true

module PhComposer
  module Zones
    FEATURE_ID = "ph_composer.zones"
    REFERENCE_KIND = "#{FEATURE_ID}.zone"
    # Emitted when a Zone occurrence becomes independent, by the action or the copy watcher's follow-up.
    # The description is `zone_path`, `old_zone_id`, `new_zone_id`, `mapping` (every old id to its new
    # one), `revision`, and `references`: the Zone's and its Faces' new records as typed entries
    # (`kind`, `key`, `record`), so a child can remap its own references to them (context/CONTRACTS.md,
    # "Compound proposals").
    TRANSITION = "#{FEATURE_ID}.occurrence_independent"
    ZONE_DICTIONARY = "ph_composer.zone"
    STAMP_DICTIONARY = "ph_composer.zone_stamp"
    ZONE_STORE = Records::EntityStore.new(ZONE_DICTIONARY)
    STAMP_STORE = Records::EntityStore.new(STAMP_DICTIONARY)
    ID_PATTERN = Records::Identity.pattern("zon")

    PATH = { "type" => "array", "items" => { "type" => "integer" } }.freeze
    ZONE_REFERENCE = {
      "type" => "object", "additionalProperties" => false, "required" => %w[zone_id zone_path],
      "properties" => { "zone_id" => { "type" => "string" }, "zone_path" => PATH }
    }.freeze

    ZONE_VALUES = {
      "type" => "object", "additionalProperties" => false,
      "required" => %w[name building_segment level ground_depth_mm],
      "properties" => {
        "name" => { "type" => "string", "minLength" => 1 },
        "building_segment" => { "type" => "string", "minLength" => 1 },
        "level" => { "type" => %w[string null] },
        "ground_depth_mm" => { "type" => "number", "x-unit" => "mm" }
      }
    }.freeze

    MANAGED_VALUES = {
      "type" => "object", "additionalProperties" => false,
      "required" => %w[name building_segment_id level_id ground_depth_mm],
      "properties" => {
        "name" => { "type" => "string", "minLength" => 1 },
        "building_segment_id" => { "type" => "string", "minLength" => 1 },
        "level_id" => { "type" => %w[string null] },
        "ground_depth_mm" => { "type" => "number", "x-unit" => "mm" }
      }
    }.freeze
    # Schema 3: a Zone names at most one Building Segment; null is No Building Segment.
    MEMBERSHIP_VALUES = MANAGED_VALUES.merge(
      "properties" => MANAGED_VALUES.fetch("properties")
                                    .merge("building_segment_id" => { "type" => %w[string null], "minLength" => 1 })
    ).freeze
    # The version every Zone write produces. Versions 2 and 3 name model-owned options by id; version 1
    # stores the option names as text and is read until it is adopted.
    ZONE_SCHEMA_VERSION = 3
    MANAGED_VERSIONS = [2, 3].freeze
    VALUES_BY_VERSION = { 1 => ZONE_VALUES, 2 => MANAGED_VALUES, 3 => MEMBERSHIP_VALUES }.freeze
    # Public inputs describe every supported version; the owner checks complete version shapes. A
    # Building Segment given by name or by id may be null, which moves the Zone to No Building Segment.
    INPUT_VALUES = {
      "type" => "object", "additionalProperties" => false, "required" => %w[name ground_depth_mm],
      "properties" => ZONE_VALUES.fetch("properties").merge(MEMBERSHIP_VALUES.fetch("properties"))
                                 .merge("building_segment" => { "type" => %w[string null], "minLength" => 1 })
    }.freeze

    module Schema
      module_function

      # Whether `record` (a Zone or a membership stamp) names its options by id.
      def managed?(record)
        MANAGED_VERSIONS.include?(record["schema_version"])
      end

      # Whether export includes the Zone `record`: every Zone but a managed one in no Building Segment, which is
      # left out with its Faces and everything inside it. A legacy Zone always names a Segment.
      def exported?(record)
        !managed?(record) || !record["building_segment_id"].nil?
      end

      # `after`, a managed Zone or stamp about to be written, at the current version: a write never leaves
      # a version 2 record behind, and an unchanged record is never written.
      def current(after)
        managed?(after) ? after.merge("schema_version" => ZONE_SCHEMA_VERSION) : after
      end

      def problems(record)
        return ["Zone record must be a JSON object"] unless record.is_a?(Hash)

        version = record["schema_version"]
        schema = VALUES_BY_VERSION.fetch(version, ZONE_VALUES)
        allowed = %w[id schema_version user_data extension_data] + schema.fetch("properties").keys
        allowed << "choice_evidence" if managed?(record)
        found = (record.keys - allowed).map { |key| "Zone record has unknown field #{key}" }
        found << "Zone id is invalid" unless ID_PATTERN.match?(record["id"].to_s)
        found << "Zone schema_version must be 1, 2 or 3" unless VALUES_BY_VERSION.key?(version)
        values = record.reject { |key, _value|
          %w[id schema_version user_data extension_data choice_evidence].include?(key)
        }
        found.concat(JsonSchema.validate(values, schema))
        found.concat(metadata_problems(record))
        if managed?(record)
          found.concat(evidence_problems(record["choice_evidence"]))
          found << "Zone choice evidence does not match its assignments" unless evidence_matches?(record)
        end
        found
      end

      def validate!(record)
        found = problems(record)
        return record if found.empty?

        raise CodedError.new("validation.failed", "Zone #{record['id']} is not valid: #{found.first}.",
                             "findings" => found)
      end

      def view(record)
        {
          "id" => record.fetch("id"), "schema_version" => record.fetch("schema_version"),
          "values" => record.reject { |key, _value|
                        %w[id schema_version user_data extension_data choice_evidence].include?(key)
                      },
          "user_data" => DeepCopy.call(record.fetch("user_data", {})),
          "extension_data" => DeepCopy.call(record.fetch("extension_data", {}))
        }
      end

      def stamp(record)
        if managed?(record)
          { "schema_version" => record.fetch("schema_version"), "zone_id" => record.fetch("id"),
            "building_segment_id" => record.fetch("building_segment_id"), "level_id" => record.fetch("level_id"),
            "choice_evidence" => DeepCopy.call(record.fetch("choice_evidence")) }
        else
          { "schema_version" => 1, "zone_id" => record.fetch("id"),
            "building_segment" => record.fetch("building_segment"), "level" => record.fetch("level") }
        end
      end

      def stamp?(value)
        return false unless value.is_a?(Hash) && ID_PATTERN.match?(value["zone_id"].to_s)

        if managed?(value)
          segment_types = value["schema_version"] == 2 ? [String] : [String, NilClass]
          value.keys.sort == %w[building_segment_id choice_evidence level_id schema_version zone_id].sort &&
            segment_types.include?(value["building_segment_id"].class) &&
            [String, NilClass].include?(value["level_id"].class) &&
            evidence_problems(value["choice_evidence"]).empty? && evidence_matches?(value)
        else
          value["schema_version"] == 1 && value["building_segment"].is_a?(String) &&
            !value["building_segment"].strip.empty? && [String, NilClass].include?(value["level"].class)
        end
      end

      # The evidence names the same options as the record, each a full option record or null for none.
      def evidence_matches?(record)
        evidence = record["choice_evidence"]
        return false unless evidence.is_a?(Hash) &&
                            %w[building_segment level].all? { |field| [Hash, NilClass].include?(evidence[field].class) }

        evidence.dig("building_segment", "id") == record["building_segment_id"] &&
          evidence.dig("level", "id") == record["level_id"]
      end

      def evidence_problems(evidence)
        return ["Zone choice evidence is missing or invalid"] unless evidence.is_a?(Hash) &&
                                                                     evidence.keys.sort == %w[building_segment level
                                                                                              source_model_id].sort &&
                                                                     evidence["source_model_id"].is_a?(String)

        found = evidence["building_segment"] ? Options::SEGMENTS.problems(evidence["building_segment"]) : []
        found.concat(Options::LEVELS.problems(evidence["level"])) if evidence["level"]
        found
      end

      def metadata_problems(record)
        %w[user_data extension_data].flat_map do |key|
          next [] unless record.key?(key)

          value = record[key]
          if value.is_a?(Hash)
            JsonValue.problems(value).map { |problem| "#{key} #{problem}" }
          else
            ["#{key} must be an object"]
          end
        end
      end
      private_class_method :metadata_problems
    end
  end
end
