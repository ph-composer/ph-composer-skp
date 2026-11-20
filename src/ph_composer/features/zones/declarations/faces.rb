# frozen_string_literal: true

module PhComposer
  module Zones
    module Faces
      # The Face submodule's public contract: the Face descriptor and inventory, the faces read,
      # Classify, Suggest classification, Reverse, the viewport commands and the Attached zone kind
      # and its writes. The handlers are Faces module functions (faces/operations.rb and
      # faces/attached_zone_operations.rb).
      module Registration
        # Declared, so the engine refuses deleting an Attached zone any Face still names.
        ATTACHED_ZONE_REFERENCE = Records::Reference.new(
          :key => "attached_zone_id", :target_kind => AttachedZone::KIND_ID, :cardinality => "one", :required => false
        )
        ASSEMBLY_REFERENCE = Records::Reference.new(
          :key => "assembly_id", :target_kind => "ph_composer.assemblies.assembly", :cardinality => "one",
          :required => false
        )
        TARGET = Records::ReferenceTarget.new(
          :id => REFERENCE_KIND, :label => "Face", :records => ReferenceTargets.method(:entries),
          :validate => Schema.method(:problems), :schema_version => 1, :values => FACE_VALUES,
          :occurrence => FACE_REFERENCE, :references => [ATTACHED_ZONE_REFERENCE, ASSEMBLY_REFERENCE],
          :locate => Zones::Occurrences.method(:locate_face), :locate_index => Zones::Index.method(:new)
        )
        ATTACHED_ZONE = AttachedZone::RECORD_KIND.descriptor
        EXAMPLE_FACE = { "zone_id" => "zon_Ab12Cd34Ef56", "zone_path" => [1201], "entity_path" => [1202],
                         "entity_id" => nil }.freeze
        EXAMPLE_ATTACHED = { "name" => "Garage", "kind" => "garage", "temperature_reduction_factor" => 0.95 }.freeze

        INTENT = Shapes.object({
          "mode" => { "type" => "string", "enum" => %w[keep set clear] },
          "value" => { "type" => %w[string null], "description" => "The value `set` writes." }
        }, :optional => ["value"])
        FACES = { "type" => "array", "items" => FACE_REFERENCE, "minItems" => 1 }.freeze
        USER_DATA = { "type" => "object",
                      "description" => "Local JSON metadata kept with the record in the Model. Export needs an " \
                                       "explicit mapping; arbitrary metadata is left out with a finding." }.freeze
        EXPECTED = FACE_VALUES.merge("description" => "The values last read for every target; a change refuses.")
        CLASSIFY_PARAMS = Shapes.object({
          # The ceiling is a feature bound, not a schema bound, so one Face over it refuses with
          # gesture.too_large rather than a generic schema error the palette cannot explain.
          "faces" => FACES.merge("description" => "One gesture's deduplicated Face occurrences."),
          "intent" => Shapes.object({ "face_type" => INTENT, "boundary_condition" => INTENT,
                                      "attached_zone_id" => INTENT, "assembly_id" => INTENT },
                                    :optional => %w[face_type boundary_condition attached_zone_id assembly_id],
                                    :description => "Per field: keep each Face's value, set one value on every " \
                                                    "Face, or clear it. An absent field is kept."),
          "expected_values" => EXPECTED
        }, :optional => ["expected_values"]).freeze
        FACE_IDS_RESULT = Shapes.object({
          "face_ids" => Shapes.list(Shapes::ID, :description => "Face records written; empty when nothing changed.")
        }).freeze
        AUTO_CLASSIFY_PARAMS = Shapes.object({
          "zone" => ZONE_REFERENCE.merge("description" => "The Zone occurrence whose unrecorded Faces get the " \
                                                          "suggested classification.")
        }).freeze
        AUTO_CLASSIFY_RESULT = Shapes.object({
          "classified" => Shapes::COUNT.merge("description" => "Faces given a suggested record."),
          "kept" => Shapes::COUNT.merge("description" => "Faces that already had a record and were left alone.")
        }).freeze
        REVERSE_PARAMS = Shapes.object({
          "face" => FACE_REFERENCE.merge("description" => "The Face occurrence whose orientation to reverse.")
        }).freeze
        SUGGESTED = Shapes.object({ "face_type" => { "type" => "string", "enum" => FACE_TYPES },
                                    "boundary_condition" => { "type" => "string", "enum" => BOUNDARY_CONDITIONS } },
                                  :description => "What Suggest classification would write.")
        FACE_ROW = Shapes.object({
          "reference" => FACE_REFERENCE, "zone_name" => { "type" => "string" },
          "area_m2" => { "type" => "number", "x-unit" => "m2" },
          "values" => FACE_VALUES.merge("description" => "Empty for a Face with no record."),
          "user_data" => { "type" => "object" }, "extension_data" => { "type" => "object" },
          "extension_status" => ZoneRegistration::EXTENSION_STATUS,
          "suggested" => SUGGESTED,
          "attached_zone_state" => { "type" => %w[string null], "enum" => [nil, "absent", "resolved", "dangling",
                                                                           "invalid"],
                                     "description" => "How an AttachedZone reference stands; null otherwise." },
          "adjacency_state" => { "type" => %w[string null],
                                 "enum" => [nil, "current", "stale", "unresolved", "invalid"],
                                 "description" => "How a Surface pair stands; null for any other boundary." },
          "assembly_state" => { "type" => "string", "enum" => %w[absent resolved dangling invalid] },
          "findings" => AssemblyRegistration::FINDINGS,
          "state" => { "type" => "string", "enum" => %w[unclassified incomplete classified] }
        }).freeze
        ALL_RESULT = Shapes.object({
          "faces" => Shapes.list(FACE_ROW, :description => "Every Face occurrence inside a Zone, recorded or not."),
          "units" => Shapes.object({ "area_m2" => { "type" => "string", "enum" => ["m2"] } }),
          "assembly_usage" => AssemblyRegistration::USAGE
        }).freeze
        # A row as `list` returns it: whole, or with `fields` only its reference and those values.
        PROJECTED_FACE_ROW = FACE_ROW.merge(
          "required" => %w[reference values],
          "description" => "Whole without fields; with fields, the reference and the named values only."
        )
        LIST_PARAMS = Shapes.object({
          "zone_ids" => { "type" => "array", "items" => Shapes::ID, "maxItems" => Pages::MAXIMUM_LIMIT,
                          "description" => "Only Faces inside occurrences of these Zone ids." },
          "zone_paths" => { "type" => "array", "items" => PATH, "maxItems" => Pages::MAXIMUM_LIMIT,
                            "description" => "Only Faces inside the Zones at these root-to-Zone paths." },
          "ids" => { "type" => "array", "items" => Shapes::ID, "maxItems" => Pages::MAXIMUM_LIMIT,
                     "description" => "Only the occurrences of these Face record ids." },
          "fields" => { "type" => "array",
                        "items" => { "type" => "string", "enum" => FACE_VALUES.fetch("properties").keys },
                        "description" => "Project each row to these values; the whole row when absent." },
          "limit" => Pages::LIMIT, "cursor" => Pages::CURSOR
        }, :optional => %w[zone_ids zone_paths ids fields limit cursor]).freeze
        LIST_EXAMPLE = { "zone_ids" => [EXAMPLE_FACE.fetch("zone_id")], "fields" => ["face_type"] }.freeze
        LIST_RESULT = Shapes.object(
          ALL_RESULT.fetch("properties").reject { |key, _value| key == "assembly_usage" }.merge(
            "faces" => Shapes.list(PROJECTED_FACE_ROW, :description => "One page of Face occurrences in path order."),
            "next_cursor" => Pages::NEXT_CURSOR, "total" => Pages::TOTAL
          )
        ).freeze
        HOST_CONTEXT_PARAMS = Shapes.object({
          "paths" => { "type" => "array", "items" => PATH.merge("minItems" => 1), "minItems" => 1,
                       "maxItems" => Pages::MAXIMUM_LIMIT,
                       "description" => "Root-to-Face persistent-id paths, as a pick or a glued instance holds them." }
        }).freeze
        HOST_CONTEXT_RESULT = Shapes.object({
          "faces" => Shapes.list(Shapes.object({
            "path" => PATH, "reference" => FACE_REFERENCE,
            "values" => FACE_VALUES.merge("description" => "Empty for a Face with no record."),
            "write_refusal" => {
              "type" => %w[object null], "additionalProperties" => false, "required" => %w[code message],
              "properties" => { "code" => { "type" => "string" }, "message" => { "type" => "string" } },
              "description" => "The refusal a write to this Face meets from its path alone (a shared, nested " \
                               "or locked Zone, locked or shared storage, or a stamp naming another Zone), or " \
                               "null. A duplicated Zone or Face id is not visible here; the write itself still " \
                               "checks it."
            }
          }), :description => "One row per path that names a Zone Face, in request order. Other paths are omitted.")
        }).freeze
        CHOOSE_PARAMS = Shapes.object({
          "field" => { "type" => "string", "enum" => %w[face_type boundary_condition attached_zone_id assembly_id],
                       "description" => "The Classify palette field to choose a value for." },
          "value" => { "type" => %w[string null],
                       "description" => "The value to set, or null to keep whatever each Face has." },
          "reset" => { "type" => "boolean", "description" => "Clear other palette choices before this choice." }
        }, :optional => ["reset"]).freeze
        TOOL_STATE = Shapes.object({
          "active" => { "type" => "boolean", "description" => "Whether the Classify tool has the viewport." },
          "palette" => { "type" => "object", "additionalProperties" => { "type" => %w[string null] },
                         "description" => "The chosen value per field; a field absent is kept." },
          "face_types" => Shapes.list({ "type" => "string" }),
          "boundary_conditions" => Shapes.list({ "type" => "string" }),
          "gesture_face_limit" => Shapes::COUNT.merge("description" => "The most Faces one gesture or one bulk " \
                                                                       "assignment may change.")
        }).freeze
        LOCATE_PARAMS = Shapes.object({
          "faces" => FACES.merge("description" => "The Face occurrences to bring into view and outline.")
        }).freeze
        SELECT_PARAMS = Shapes.object({
          "faces" => FACES.merge("description" => "The Face occurrences to select and bring into view.")
        }).freeze
        LOCATE_RESULT = Shapes.object({
          "found" => Shapes::COUNT.merge("description" => "How many references still resolved."),
          "missing" => Shapes::COUNT.merge("description" => "How many did not, and were skipped.")
        }).freeze
        ATTACHED_ZONE_SAVE_PARAMS = Shapes.object({
          "id" => { "type" => "string", "description" => "The record to edit; absent creates one." },
          "values" => ATTACHED_ZONE.patch_schema.merge("description" => "The Attached zone values to write; only " \
                                                                        "those given change."),
          "user_data" => USER_DATA.merge("description" => "Only when creating, without id. " \
                                                          "#{USER_DATA.fetch('description')} Edit an existing " \
                                                          "record's map with ph_composer.records.update_metadata."),
          "expected_values" => ATTACHED_ZONE.patch_schema.merge("description" => "The values last read.")
        }, :optional => %w[id user_data expected_values]).freeze
        ATTACHED_ZONE_ID_RESULT = Shapes.object({ "id" => Shapes::ID }).freeze
        ATTACHED_ZONE_CREATE_ASSIGN_PARAMS = Shapes.object({
          "faces" => FACES.merge("description" => "The Face occurrences to assign the new Attached zone to."),
          "values" => ATTACHED_ZONE.patch_schema.merge("description" => "The new Attached zone's values."),
          "user_data" => USER_DATA,
          "intent" => Shapes.object({ "face_type" => INTENT },
                                    :optional => ["face_type"],
                                    :description => "Optionally keep, set or clear the Faces' face_type in the " \
                                                    "same step."),
          "expected_values" => EXPECTED
        },
                                                           :optional => %w[user_data intent expected_values]).freeze
        ATTACHED_ZONE_CREATE_ASSIGN_RESULT = Shapes.with(ATTACHED_ZONE_ID_RESULT,
                                                         FACE_IDS_RESULT.fetch("properties")).freeze
        ATTACHED_ZONE_DELETE_PARAMS = Shapes.object({
          "id" => Shapes::ID.merge("description" => "The Attached zone to delete."),
          # Either another Attached zone every referencing Face moves to, or an explicit boundary
          # condition they are reclassified as. There is no third, silent route.
          "replacement" => Shapes.object({
            "mode" => { "type" => "string", "enum" => %w[attached_zone boundary_condition] },
            "attached_zone_id" => { "type" => "string", "description" => "With mode attached_zone." },
            "boundary_condition" => { "type" => "string", "enum" => %w[Outdoors Ground Adiabatic],
                                      "description" => "With mode boundary_condition." }
          }, :optional => %w[attached_zone_id boundary_condition],
             :description => "Where the Faces naming it go: to another Attached zone, or reclassified to a " \
                             "boundary condition.")
        }).freeze
        ATTACHED_ZONE_DELETE_RESULT = Shapes.with_removed_user_data(
          Shapes.object({ "id" => Shapes::ID, "reassigned_faces" => Shapes::COUNT })
        ).freeze
        ATTACHED_ZONE_DUPLICATE_PARAMS = Shapes.object({
          "ids" => { "type" => "array", "items" => Shapes::ID, "minItems" => 1,
                     "description" => "The Attached zones to copy, each under a new id and a numbered name." }
        }).freeze
        ATTACHED_ZONE_DUPLICATE_RESULT = Shapes.object({
          "ids" => { "type" => "object", "additionalProperties" => Shapes::ID,
                     "description" => "Each original id and the id of its copy." }
        }).freeze

        module_function

        def install(feature)
          feature.reference_target(TARGET)
          ColourModes.install(feature)
          ClassifyMenu.install(feature)
          feature.query("#{PREFIX}.list",
                        :description => "One page of path-qualified Face occurrences in authored Zones, filtered " \
                                        "and projected.",
                        :refuses => Refuses::READ + Refuses::PAGE + %w[geometry.invalid],
                        :params => LIST_PARAMS, :result => LIST_RESULT,
                        :examples => [{}, LIST_EXAMPLE]) { |request| Faces.list(request) }
          feature.query("#{PREFIX}.all",
                        :response => { "bounded" => false, "prefer" => "#{PREFIX}.list" },
                        :description => "Every Face occurrence in authored Zones in one complete projection, for the " \
                                        "panel. Scripts page #{PREFIX}.list instead.",
                        :refuses => Refuses::READ + %w[geometry.invalid],
                        :params => Shapes::NONE, :result => ALL_RESULT, :examples => [{}]) do |request|
            Faces.all(request)
          end
          feature.query("#{PREFIX}.host_context",
                        :description => "The reference and values of the Faces at explicit native paths, for a " \
                                        "feature that hosts objects on Faces. Scans only each path, never the " \
                                        "whole Model; Zone state is in ph_composer.zones.all.",
                        :refuses => %w[record.unreadable validation.failed],
                        :params => HOST_CONTEXT_PARAMS, :result => HOST_CONTEXT_RESULT,
                        :examples => [{ "paths" => [[1201, 1202]] }]) do |request|
            Faces.host_context(request, :paths => request.params.fetch("paths"))
          end
          declare_writes(feature)
          declare_clear_classification(feature)
          declare_viewport(feature)
          declare_locate(feature)
          declare_attached_zones(feature)
          feature.snapshot_section("#{PREFIX}.faces", :query => "#{PREFIX}.all")
          ExportProjection.install(feature)
        end

        RECORDED_FACE = FACE_REFERENCE.merge(
          "properties" => FACE_REFERENCE.fetch("properties").merge("entity_id" => { "type" => "string" })
        ).freeze
        CLEAR_CLASSIFICATION_PARAMS = Shapes.object({
          "faces" => { "type" => "array", "items" => RECORDED_FACE, "minItems" => 1,
                       "description" => "The classified Face occurrences whose records to remove, each with the " \
                                        "entity_id last read." }
        }).freeze

        def declare_metadata(feature)
          feature.action("#{PREFIX}.update_metadata",
                         :description => "Replace the user_data and installed extension payloads of recorded " \
                                         "Faces, guarded by the metadata last read.",
                         :refuses => (Refuses::FACE_TARGET + Refuses::METADATA).uniq,
                         :params => Shapes.metadata_updates(RECORDED_FACE, Pages::MAXIMUM_LIMIT),
                         :result => Shapes.metadata_result(RECORDED_FACE), :undo_name => "Edit Face Metadata",
                         :examples => [{ "updates" => [{ "reference" => EXAMPLE_FACE.merge(
                           "entity_id" => "fac_Ab12Cd34Ef56"
                         ), "user_data" => {}, "expected_metadata" => { "user_data" => {},
                                                                        "extension_data" => {} } }] }],
                         :side_effects => "Rewrites only the named Faces' metadata.") do |request, proposal|
            Faces.update_metadata(request, proposal, :updates => request.params.fetch("updates"))
          end
        end

        def declare_writes(feature)
          declare_metadata(feature)
          classify = { "faces" => [EXAMPLE_FACE], "expected_values" => {},
                       "intent" => { "face_type" => { "mode" => "set", "value" => "Wall" },
                                     "boundary_condition" => { "mode" => "set", "value" => "Outdoors" } } }
          feature.action("#{PREFIX}.classify",
                         :description => "Apply explicit keep, set or clear intent to Faces.",
                         :refuses => Refuses::CLASSIFY + %w[reference.invalid],
                         :params => CLASSIFY_PARAMS, :result => FACE_IDS_RESULT, :undo_name => "Classify Faces",
                         :examples => [classify,
                                       { "faces" => [EXAMPLE_FACE],
                                         "intent" => { "assembly_id" => { "mode" => "set",
                                                                          "value" => "asm_Ab12Cd34Ef56" } } }],
                         :side_effects => "Writes face assignments and Zone stamps.") do |request, proposal|
            params = request.params
            Faces.classify(request, proposal, :faces => params.fetch("faces"), :intent => params.fetch("intent"),
                                              :expected_values => params.fetch("expected_values", {}))
          end
          feature.action("#{PREFIX}.auto_classify",
                         :description => "Suggest a classification for every unrecorded Face in one Zone.",
                         :refuses => Refuses::FACE_TARGET + %w[geometry.invalid],
                         :params => AUTO_CLASSIFY_PARAMS, :result => AUTO_CLASSIFY_RESULT,
                         :undo_name => "Suggest Classification",
                         :examples => [{ "zone" => EXAMPLE_FACE.slice("zone_id", "zone_path") }],
                         :side_effects => "Writes suggested values to Faces that have no record " \
                                          "yet.") do |request, proposal|
            Faces.auto_classify(request, proposal, :zone => request.params.fetch("zone"))
          end
          feature.action("#{PREFIX}.reverse",
                         :description => "Reverse one Face and keep its assignment record.",
                         :refuses => Refuses::FACE_TARGET,
                         :params => REVERSE_PARAMS, :result => Shapes::NONE, :undo_name => "Reverse Face",
                         :examples => [{ "face" => EXAMPLE_FACE }],
                         :side_effects => "Flips the Face normal; any Surface pair goes stale.") do |request, proposal|
            Faces.reverse(request, proposal, :face => request.params.fetch("face"))
          end
        end

        def declare_clear_classification(feature)
          feature.action("#{PREFIX}.clear_classification",
                         :description => "Remove the classification records of Faces, so each reads as never " \
                                         "classified.",
                         :refuses => Refuses::CLEAR_CLASSIFICATION, :params => CLEAR_CLASSIFICATION_PARAMS,
                         :result => FACE_IDS_RESULT, :undo_name => "Clear Classification",
                         :examples => [{ "faces" => [EXAMPLE_FACE.merge("entity_id" => "fac_Ab12Cd34Ef56")] }],
                         :side_effects => "Removes Face assignment records; Zone stamps stay.") do |request, proposal|
            Faces.clear_classification(request, proposal, :faces => request.params.fetch("faces"))
          end
        end

        # What reaches the viewport rather than the Model: the Classify tool's palette and the tool itself.
        # Neither writes a record, so neither is an action.
        def declare_viewport(feature)
          feature.query("#{PREFIX}.classify_tool", :description => "The Classify tool's palette and whether it runs.",
                                                   :refuses => [],
                                                   :params => Shapes::NONE, :result => TOOL_STATE,
                                                   :examples => [{}]) do |request|
            Faces.tool_state(request.session)
          end
          feature.snapshot_section("#{PREFIX}.palette", :query => "#{PREFIX}.classify_tool")
          feature.view_command("#{PREFIX}.choose",
                               :description => "Set one Classify palette field and give the tool the viewport.",
                               :refuses => %w[record.unreadable reference.invalid],
                               :params => CHOOSE_PARAMS, :result => TOOL_STATE,
                               :examples => [{ "field" => "face_type", "value" => "Wall" },
                                             { "field" => "assembly_id", "value" => "asm_Ab12Cd34Ef56" }]) do |request|
            if request.params["field"] == "assembly_id" && request.params["value"]
              AssemblyAssignment.resolve(request, request.params.fetch("value"))
            end
            Faces.classify_tool(request.session).choose(request.params.fetch("field"), request.params.fetch("value"),
                                                        :reset => request.params.fetch("reset", false))
            Faces.tool_state(request.session)
          end
          feature.view_command("#{PREFIX}.stop_classifying",
                               :description => "Give the viewport back to whatever tool the user had.",
                               :refuses => [],
                               :params => Shapes::NONE, :result => TOOL_STATE, :examples => [{}]) do |request|
            Faces.classify_tool(request.session).stop
            Faces.tool_state(request.session)
          end
        end

        # Locate, its outline and Select: they reach the camera, the viewport's outline and the selection,
        # never a record, so none is an action. A new selection ends the outline.
        def declare_locate(feature)
          feature.on_host_event(:selection_changed) { |session| Faces.locate_highlight(session).clear }
          feature.view_command("#{PREFIX}.locate",
                               :description => "Bring an explicit set of Faces into view and outline them, " \
                                               "leaving the selection alone.",
                               :refuses => [],
                               :side_effects => "Moves the camera to frame the Faces and outlines them until " \
                                                "the selection changes. The edit path, the selection and the " \
                                                "revision are unchanged.",
                               :params => LOCATE_PARAMS, :result => LOCATE_RESULT,
                               :examples => [{ "faces" => [EXAMPLE_FACE] }]) do |request|
            Faces.locate(request, :faces => request.params.fetch("faces"))
          end
          feature.view_command("#{PREFIX}.clear_locate",
                               :description => "Remove the outline the last Locate left in the viewport.",
                               :refuses => [],
                               :params => Shapes::NONE, :result => Shapes::NONE, :examples => [{}]) do |request|
            Faces.locate_highlight(request.session).clear
            {}
          end
          feature.view_command("#{PREFIX}.select",
                               :description => "Select an explicit set of Faces and bring them into view.",
                               :refuses => [],
                               :params => SELECT_PARAMS, :result => LOCATE_RESULT,
                               :examples => [{ "faces" => [EXAMPLE_FACE] }]) do |request|
            Faces.select(request, :faces => request.params.fetch("faces"))
          end
        end

        # Attached zones are read through the foundation's own ph_composer.records.list, so this feature
        # registers only the kind and the writes that need its reference rules.
        def declare_attached_zones(feature)
          feature.record_kind(AttachedZone::RECORD_KIND)
          # Read through the foundation's own records query, so the picker needs no reader of its own.
          feature.snapshot_section("#{AttachedZone::KIND_ID}.list", :query => "ph_composer.records.list",
                                                                    :params => { "kind" => AttachedZone::KIND_ID })
          feature.action("#{AttachedZone::KIND_ID}.save",
                         :description => "Create or edit one Attached zone.",
                         :refuses => Refuses::RECORD_EDIT,
                         :params => ATTACHED_ZONE_SAVE_PARAMS, :result => ATTACHED_ZONE_ID_RESULT,
                         :undo_name => "Save Attached Zone", :examples => [{ "values" => EXAMPLE_ATTACHED }],
                         :side_effects => "Writes one Attached zone record.") do |request, proposal|
            params = request.params
            Faces.save_attached_zone(request, proposal,
                                     :values => params.fetch("values"), :id => params["id"],
                                     :expected_values => params.fetch("expected_values", {}),
                                     :user_data => params["user_data"])
          end
          feature.action("#{AttachedZone::KIND_ID}.create_and_assign",
                         :description => "Create one Attached zone and assign it to explicit Face occurrences.",
                         :refuses => Refuses::CLASSIFY,
                         :params => ATTACHED_ZONE_CREATE_ASSIGN_PARAMS, :result => ATTACHED_ZONE_CREATE_ASSIGN_RESULT,
                         :undo_name => "Create and Assign Attached Zone",
                         :examples => [{ "faces" => [EXAMPLE_FACE], "values" => EXAMPLE_ATTACHED }],
                         :side_effects => "Creates one Attached zone and classifies its Faces in one Undo " \
                                          "step.") do |request, proposal|
            params = request.params
            Faces.create_and_assign_attached_zone(request, proposal,
                                                  :values => params.fetch("values"),
                                                  :faces => params.fetch("faces"),
                                                  :intent => params.fetch("intent", {}),
                                                  :expected_values => params.fetch("expected_values", {}),
                                                  :user_data => params["user_data"])
          end
          feature.action("#{AttachedZone::KIND_ID}.duplicate",
                         :description => "Copy Attached zones without reassigning any Face.",
                         :refuses => Refuses::RECORD_COPY,
                         :params => ATTACHED_ZONE_DUPLICATE_PARAMS, :result => ATTACHED_ZONE_DUPLICATE_RESULT,
                         :undo_name => "Duplicate Attached Zone", :examples => [{ "ids" => ["atz_Ab12Cd34Ef56"] }],
                         :side_effects => "Creates Attached zone records with fresh ids.") do |request, proposal|
            { "ids" => request.engine.propose_duplicate(AttachedZone::KIND_ID, request.params.fetch("ids"), proposal) }
          end
          declare_attached_zone_delete(feature)
        end

        def declare_attached_zone_delete(feature)
          delete = { "id" => "atz_Ab12Cd34Ef56",
                     "replacement" => { "mode" => "boundary_condition", "boundary_condition" => "Outdoors" } }
          feature.action("#{AttachedZone::KIND_ID}.delete",
                         :description => "Delete one Attached zone, moving every Face that names it in the same step.",
                         :refuses => Refuses::RECORD_DELETE,
                         :params => ATTACHED_ZONE_DELETE_PARAMS, :result => ATTACHED_ZONE_DELETE_RESULT,
                         :undo_name => "Delete Attached Zone", :examples => [delete],
                         :side_effects => "Reassigns or reclassifies referencing Faces and deletes the " \
                                          "record.") do |request, proposal|
            Faces.delete_attached_zone(request, proposal, :id => request.params.fetch("id"),
                                                          :replacement => request.params.fetch("replacement"))
          end
        end
      end
    end
  end
end
