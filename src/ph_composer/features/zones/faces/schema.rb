# frozen_string_literal: true

module PhComposer
  module Zones
    module Faces
      # Every name the Face submodule registers: its actions, queries, view commands, colour modes,
      # menu items, snapshot sections, export section and the Face and Attached-zone kinds. The
      # feature id is Zones::FEATURE_ID; this is not a second feature.
      PREFIX = "#{FEATURE_ID}.faces"
      # The stored dictionary name predates the move into Zones and stays: renaming it would orphan
      # every Face record saved so far.
      FACE_DICTIONARY = "ph_composer.face_assignment"
      FACE_STORE = Records::EntityStore.new(FACE_DICTIONARY)
      ID_PATTERN = Records::Identity.pattern("fac")
      FACE_TYPES = %w[Wall RoofCeiling Floor AirBoundary].freeze
      # AirBoundary round trips through HBJSON but the Classify tool does not offer it.
      ASSIGNABLE_FACE_TYPES = %w[Wall RoofCeiling Floor].freeze
      BOUNDARY_CONDITIONS = %w[Outdoors Ground Adiabatic Surface AttachedZone].freeze
      # Surface belongs to Solve adjacencies; every other condition is the Classify tool's.
      ASSIGNABLE_BOUNDARIES = %w[Outdoors Ground Adiabatic AttachedZone].freeze
      # What the palette lists. Surface is in it and is not assignable: it is shown and refused,
      # because a user who looks for it and finds nothing learns nothing about why.
      PALETTE_BOUNDARIES = (ASSIGNABLE_BOUNDARIES + %w[Surface]).freeze
      # The ceiling on Face occurrences one gesture may affect, counterparts included. Lowered from
      # the proposed 1,000 on 2026-09-20: a gesture affecting 1,000 Faces measured about 13 seconds
      # against the offline stub, because occurrence resolution walks the Model once per Face. 250 is
      # still far above a realistic drag and bounds the worst case to roughly a quarter of that. The
      # per-Face walk was later replaced by one `Zones::Index` walk per read phase; the ceiling bounds
      # the blast radius, it cannot bound elapsed time.
      GESTURE_FACE_LIMIT = 250

      class << self
        # The shipped bound is always GESTURE_FACE_LIMIT. The writer exists so a test can reach the
        # ceiling through reciprocal retirement targets without building a thousand-Face model, and
        # reset_for_test puts it back. Nothing in the extension sets it; raise the constant instead.
        attr_writer :gesture_face_limit

        def gesture_face_limit
          @gesture_face_limit ||= GESTURE_FACE_LIMIT
        end

        def reset_for_test
          @gesture_face_limit = nil
        end
      end
      PhComposer.on_reset("zones.faces") { reset_for_test }

      # One Face occurrence: its Zone's reference, the path from the Zone to the Face, and the Face
      # record's id, or null for a Face with no record yet.
      FACE_REFERENCE = {
        "type" => "object", "additionalProperties" => false,
        "required" => %w[zone_id zone_path entity_path entity_id],
        "properties" => {
          "zone_id" => { "type" => "string" }, "zone_path" => PATH, "entity_path" => PATH,
          "entity_id" => { "type" => %w[string null] }
        }
      }.freeze

      # One Face record's values. Every field is optional: a Face is classified a field at a time.
      # The rules between fields (a reference only with its boundary condition) are Schema's.
      FACE_VALUES = {
        "type" => "object", "additionalProperties" => false,
        "properties" => {
          "face_type" => { "type" => "string", "enum" => FACE_TYPES },
          "boundary_condition" => { "type" => "string", "enum" => BOUNDARY_CONDITIONS },
          "attached_zone_id" => { "type" => %w[string null],
                                  "description" => "Id of an Attached zone record; only with AttachedZone." },
          "assembly_id" => { "type" => %w[string null], "description" => "Id of the Face's Assembly." },
          "assembly_reversed" => { "type" => "boolean",
                                   "description" => "True on the counterpart side of a Surface pair: the pair's " \
                                                    "Assembly seen from the other Zone, layers reversed. Only " \
                                                    "with Surface and an assembly_id." },
          "adjacency" => { "type" => "object",
                           "description" => "The Surface pair envelope Solve adjacencies writes; only with Surface." }
        }
      }.freeze

      module Schema
        module_function

        def problems(record)
          return ["Face assignment must be a JSON object"] unless record.is_a?(Hash)

          found = JsonSchema.validate(values(record), FACE_VALUES)
          found << "Face id is invalid" unless ID_PATTERN.match?(record["id"].to_s)
          found << "Face schema_version must be 1" unless record["schema_version"] == 1
          # An AttachedZone with no chosen record is stored: it is a visible incomplete authoring
          # state that blocks canonical export, not data the record layer refuses to keep.
          if record.key?("attached_zone_id") && record["boundary_condition"] != "AttachedZone"
            found << "attached_zone_id is only valid for AttachedZone"
          end
          if record["boundary_condition"] == "Surface" && !record["adjacency"].is_a?(Hash)
            found << "Surface needs adjacency"
          elsif record.key?("adjacency") && record["boundary_condition"] != "Surface"
            found << "adjacency is only valid for Surface"
          end
          found.concat(Zones::Adjacency.validate_envelope(record["adjacency"])) if record["adjacency"].is_a?(Hash)
          if record["assembly_reversed"] && !(record["boundary_condition"] == "Surface" && record["assembly_id"])
            found << "assembly_reversed is only valid on a Surface Face with an Assembly"
          end
          found.concat(metadata_problems(record))
          found
        end

        def validate!(record)
          found = problems(record)
          return record if found.empty?

          raise CodedError.new("validation.failed", "Face #{record['id']} is not valid: #{found.first}.",
                               "findings" => found)
        end

        # A Face leaving its Surface pair loses what only the pair explains: the adjacency envelope and
        # which side of the pair's Assembly it holds.
        def leave_pair!(record)
          record.delete("adjacency")
          record.delete("assembly_reversed")
          record
        end

        def values(record)
          record.reject { |key, _value| %w[id schema_version user_data extension_data].include?(key) }
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
end
