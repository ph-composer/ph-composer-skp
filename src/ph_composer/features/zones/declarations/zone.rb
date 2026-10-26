# frozen_string_literal: true

module PhComposer
  module Zones
    # The Zone's public contract: its descriptor and inventory, the list read and the Make and Edit
    # actions. The handlers are Zones module functions (zone/operations.rb).
    module ZoneRegistration
      TARGET = Records::ReferenceTarget.new(
        :id => REFERENCE_KIND, :label => "Zone", :records => Zones.method(:reference_entries),
        :validate => Schema.method(:problems), :schema_version => 2, :values => INPUT_VALUES,
        :references => Options::CHOICE_REFERENCES,
        :occurrence => ZONE_REFERENCE,
        :locate => Occurrences.method(:locate_zone), :locate_index => Index.method(:new)
      )
      EXAMPLE_REFERENCE = { "zone_id" => "zon_Ab12Cd34Ef56", "zone_path" => [1201] }.freeze
      EXAMPLE_VALUES = { "name" => "Zone 1", "building_segment" => "House", "level" => nil,
                         "ground_depth_mm" => 0.0 }.freeze

      MAKE_TARGET = Shapes.object({
        "parent_path" => PATH.merge("description" => "The edit context the Zone is made in."),
        "entity_ids" => { "type" => "array", "items" => { "type" => "integer" }, "minItems" => 1,
                          "description" => "One Group, or loose Faces and Edges, by persistent id." }
      })
      MAKE_PARAMS = Shapes.object(
        MAKE_TARGET.fetch("properties").merge("name" => { "type" => "string", "minLength" => 1,
                                                          "description" => "The new Zone's name; numbered when " \
                                                                           "absent." }), :optional => ["name"]
      ).freeze
      UPDATE_PARAMS = Shapes.object({
        "reference" => ZONE_REFERENCE.merge("description" => "The Zone occurrence to edit, as list returns it."),
        "values" => INPUT_VALUES.merge("description" => "The Zone's complete new values."),
        "expected_values" => INPUT_VALUES.merge("description" => "The values last read; a change refuses.")
      }).freeze
      DISPLAY = Shapes.object({
        "building_segment" => { "type" => %w[string null] }, "level" => { "type" => %w[string null] },
        "building_segment_colour" => { "type" => %w[string null] }, "level_colour" => { "type" => %w[string null] }
      }, :optional => %w[building_segment level building_segment_colour level_colour])
      INDEPENDENCE = Shapes.object({
        "available" => { "type" => "boolean", "description" => "Whether make_independent can act on it." },
        "code" => { "type" => %w[string null], "description" => "The refusal make_independent would give." },
        "reason" => { "type" => %w[string null], "description" => "That refusal's message: what to do first." },
        "retired_pairs" => Shapes::COUNT.merge("description" => "Surface pairs acting would retire.")
      }).merge("type" => %w[object null],
               "description" => "For an occurrence that is not found cleanly, whether Make Zone independent " \
                                "applies; null otherwise.")
      # A Zone read captures each Face's geometry for the area totals, so it answers what a Face read does.
      READ = (Refuses::READ + %w[geometry.invalid]).freeze
      EXTENSION_STATUS = { "type" => "object",
                           "description" => "Each extension envelope's status against what is installed, by " \
                                            "namespace." }.freeze
      AREA_TOTAL = { "type" => "number", "minimum" => 0, "x-unit" => "m2",
                     "description" => "Summed over this occurrence's Faces, each through its own transform." }.freeze
      ZONE_ROW = Shapes.with(TARGET.descriptor.view_schema, "display" => DISPLAY,
                                                            "extension_status" => EXTENSION_STATUS,
                                                            "reference" => ZONE_REFERENCE,
                                                            "state" => { "type" => "string",
                                                                         "enum" => %w[found ambiguous shared_definition
                                                                                      wrong_hierarchy] },
                                                            "face_count" => Shapes::COUNT,
                                                            "face_area_m2" => AREA_TOTAL,
                                                            "unclassified_face_area_m2" => AREA_TOTAL,
                                                            "independence" => INDEPENDENCE)
      # A row as `list` returns it: whole, or with `fields` only its identity, state and those values.
      PROJECTED_ZONE_ROW = ZONE_ROW.merge(
        "required" => %w[id reference state values],
        "properties" => ZONE_ROW.fetch("properties")
                                .merge("values" => INPUT_VALUES.reject { |key, _value| key == "required" }),
        "description" => "Whole without fields; with fields, id, reference, state and the named values only."
      )
      VALUE_KEYS = INPUT_VALUES.fetch("properties").keys.freeze
      LIST_PARAMS = Shapes.object({
        "ids" => { "type" => "array", "items" => Shapes::ID, "maxItems" => Pages::MAXIMUM_LIMIT,
                   "description" => "Only occurrences of these Zone ids." },
        "paths" => { "type" => "array", "items" => PATH, "maxItems" => Pages::MAXIMUM_LIMIT,
                     "description" => "Only the occurrences at these root-to-Zone paths." },
        "fields" => { "type" => "array", "items" => { "type" => "string", "enum" => VALUE_KEYS },
                      "description" => "Project each row to these values; the whole row when absent." },
        "limit" => Pages::LIMIT, "cursor" => Pages::CURSOR
      }, :optional => %w[ids paths fields limit cursor]).freeze
      RESTORABLE = Shapes.object({
        "zone_id" => Shapes::ID, "building_segment" => { "type" => %w[string null] },
        "level" => { "type" => %w[string null] }, "parent_path" => PATH,
        "entity_ids" => { "type" => "array", "items" => { "type" => "integer" } }, "member_count" => Shapes::COUNT,
        "refusal" => { "type" => %w[string null], "enum" => [nil, "mixed_context", "stamps_conflict", "shared_edge"],
                       "description" => "Why Restore would refuse, or null when it can run." },
        "choice_record" => { "type" => "object" },
        "unrecoverable" => Shapes.list({ "type" => "string" }, :description => "Zone fields Restore cannot recover.")
      }, :optional => ["choice_record"], :description => "An exploded Zone whose stamped members Restore can regroup.")
      FINDING = Shapes.object({
        "code" => { "type" => "string", "enum" => ["zone.component"] }, "message" => { "type" => "string" },
        "reference" => Shapes.object({ "zone_id" => Shapes::ID, "entity_path" => PATH })
      }, :description => "A Zone record no read takes as a Zone, such as one on a component, with the way back.")
      ALL_RESULT = Shapes.object({
        "zones" => Shapes.list(ZONE_ROW, :description => "Every Zone occurrence, copies and nested Zones included."),
        "make_zone" => MAKE_TARGET.merge("type" => %w[object null],
                                         "description" => "The params Make Zone takes for the current selection, " \
                                                          "or null when the selection cannot become a Zone."),
        "restorable" => Shapes.list(RESTORABLE),
        "findings" => Shapes.list(FINDING),
        "units" => Shapes.object({ "ground_depth_mm" => { "type" => "string", "enum" => ["mm"] },
                                   "face_area_m2" => { "type" => "string", "enum" => ["m2"] },
                                   "unclassified_face_area_m2" => { "type" => "string", "enum" => ["m2"] } })
      }).freeze
      LIST_RESULT = Shapes.object(
        ALL_RESULT.fetch("properties").merge(
          "zones" => Shapes.list(PROJECTED_ZONE_ROW, :description => "One page of Zone occurrences in path order."),
          "next_cursor" => Pages::NEXT_CURSOR, "total" => Pages::TOTAL
        )
      ).freeze
      ZONE_ID_RESULT = Shapes.object({ "zone_id" => Shapes::ID }).freeze
      STAMP_PARAMS = Shapes.object({
        "zone" => ZONE_REFERENCE.merge("description" => "The Zone occurrence the container is inside."),
        "slot" => { "type" => "string", "minLength" => 1,
                    "description" => "The proposal slot the calling step fills with the new Group's entity_path." }
      }).freeze

      module_function

      def install_reads(feature)
        feature.query("#{FEATURE_ID}.list",
                      :description => "One page of Zone occurrences, filtered and projected, and the Make Zone target.",
                      :refuses => READ + Refuses::PAGE, :params => LIST_PARAMS, :result => LIST_RESULT,
                      :examples => [{}, { "fields" => ["name"], "limit" => 20 }]) { |request| Zones.list(request) }
        feature.query("#{FEATURE_ID}.all",
                      :response => { "bounded" => false, "prefer" => "#{FEATURE_ID}.list" },
                      :description => "Every Zone occurrence in one complete projection, for the panel. Scripts " \
                                      "page #{FEATURE_ID}.list instead.",
                      :refuses => READ,
                      :params => Shapes::NONE, :result => ALL_RESULT, :examples => [{}]) do |request|
          Zones.all(request)
        end
        install_containment(feature)
      end

      def install_containment(feature)
        feature.query("#{FEATURE_ID}.containment",
                      :description => "The Zone occurrence holding the entity at each explicit native path, for a " \
                                      "feature storing records on geometry inside Zones. Scans only each path, " \
                                      "never the whole Model.",
                      :refuses => %w[record.unreadable validation.failed], :params => CONTAINMENT_PARAMS,
                      :result => CONTAINMENT_RESULT,
                      :examples => [{ "paths" => [[1201, 1202]] }]) do |request|
          Zones.containment(request, :paths => request.params.fetch("paths"))
        end
      end

      # The two edits of an existing Zone occurrence: its values, and its metadata.
      def declare_edits(feature)
        feature.action("#{FEATURE_ID}.update", :description => "Update one explicit Zone occurrence.",
                                               :refuses => Options::Registration::REFUSALS,
                                               :params => UPDATE_PARAMS, :result => ZONE_ID_RESULT,
                                               :undo_name => "Edit Zone",
                                               :examples => [{ "reference" => EXAMPLE_REFERENCE,
                                                               "values" => EXAMPLE_VALUES.merge("level" => "L1"),
                                                               "expected_values" => EXAMPLE_VALUES }],
                                               :side_effects => "Updates Zone values and membership stamps.") do |
                                                    request, proposal|
          Zones.update(request, proposal,
                       :reference => request.params.fetch("reference"),
                       :values => request.params.fetch("values"),
                       :expected_values => request.params.fetch("expected_values"))
        end
        feature.action("#{FEATURE_ID}.update_metadata",
                       :description => "Replace the user_data and installed extension payloads of explicit Zone " \
                                       "occurrences, guarded by the metadata last read.",
                       :refuses => (Refuses::ZONE_TARGET + Refuses::METADATA).uniq,
                       :params => Shapes.metadata_updates(ZONE_REFERENCE, Pages::MAXIMUM_LIMIT),
                       :result => Shapes.metadata_result(ZONE_REFERENCE), :undo_name => "Edit Zone Metadata",
                       :examples => [{ "updates" => [{ "reference" => EXAMPLE_REFERENCE,
                                                       "user_data" => { "example" => { "note" => "kept" } },
                                                       "expected_metadata" => { "user_data" => {},
                                                                                "extension_data" => {} } }] }],
                       :side_effects => "Rewrites only the named Zones' metadata.") do |request, proposal|
          Zones.update_metadata(request, proposal, :updates => request.params.fetch("updates"))
        end
      end

      REFUSAL = { "type" => %w[object null], "additionalProperties" => false, "required" => %w[code message],
                  "properties" => { "code" => { "type" => "string" }, "message" => { "type" => "string" } } }.freeze
      CONTAINMENT_PARAMS = Shapes.object({
        "paths" => { "type" => "array", "items" => PATH.merge("minItems" => 1), "minItems" => 1,
                     "maxItems" => Pages::MAXIMUM_LIMIT,
                     "description" => "Root-to-entity persistent-id paths, as a pick or a selection holds them." }
      }).freeze
      CONTAINMENT_RESULT = Shapes.object({
        "paths" => Shapes.list(Shapes.object({
          "path" => PATH,
          "zone" => {
            "type" => %w[object null], "additionalProperties" => false,
            "required" => %w[zone_id zone_path name building_segment level],
            "properties" => { "zone_id" => { "type" => "string" }, "zone_path" => PATH,
                              "name" => { "type" => "string" },
                              "building_segment" => { "type" => %w[string null] },
                              "level" => { "type" => %w[string null] } },
            "description" => "The Zone occurrence holding the entity, or null with a reason."
          },
          "entity_path" => PATH.merge("type" => %w[array null],
                                      "description" => "The path from inside the Zone to the entity; null " \
                                                       "with no Zone."),
          "reason" => { "type" => %w[string null],
                        "enum" => [nil, "not_found", "not_a_drawing_element", "cutting_instance", "outside_zone",
                                   "nested_container"],
                        "description" => "Why no Zone holds it: a step missing or repeated, not a drawing " \
                                         "element, under a cutting component, outside every Zone, or inside a " \
                                         "nested container. Null with a Zone." },
          "write_refusal" => REFUSAL.merge("description" => "The refusal a write through this path meets from " \
                                                            "the path alone (a shared, nested or locked Zone, " \
                                                            "locked or shared storage), or null. A duplicated " \
                                                            "Zone id needs a walk; the write still resolves " \
                                                            "strictly.")
        }))
      }).freeze

      def install(feature)
        feature.reference_target(TARGET)
        ColourModes.install(feature)
        install_reads(feature)
        feature.action("#{FEATURE_ID}.make",
                       :description => "Make one Zone from explicit entities in one edit context.",
                       :refuses => (Options::Registration::REFUSALS + %w[target.edit_path_changed]).uniq,
                       :params => MAKE_PARAMS, :result => ZONE_ID_RESULT, :undo_name => "Make Zone",
                       :examples => [{ "parent_path" => [], "entity_ids" => [1201] }],
                       :side_effects => "Groups loose geometry when needed and writes a Zone " \
                                        "record.") do |request, proposal|
          Zones.make(request, proposal,
                     :parent_path => request.params.fetch("parent_path"),
                     :entity_ids => request.params.fetch("entity_ids"), :name => request.params["name"])
        end
        declare_edits(feature)
        feature.proposal_participant("#{FEATURE_ID}.stamp_container",
                                     :description => "Stamp a Group the calling action's own earlier step " \
                                                     "creates inside a Zone occurrence, making it a nested " \
                                                     "container of that Zone. The step leaves the Group's " \
                                                     "root-to-Group path in its slot as entity_path.",
                                     :refuses => Refuses::ZONE_TARGET, :params => STAMP_PARAMS,
                                     :result => ZONE_ID_RESULT,
                                     :examples => [{ "zone" => EXAMPLE_REFERENCE,
                                                     "slot" => "spc_Ab12Cd34Ef56" }]) do |request, proposal|
          Zones.stamp_container(request, proposal, :zone => request.params.fetch("zone"),
                                                   :slot => request.params.fetch("slot"))
        end
        feature.snapshot_section("#{FEATURE_ID}.overview", :query => "#{FEATURE_ID}.all")
        feature.on_host_event(:selection_changed) { |session| session.request_refresh }
      end
    end
  end
end
