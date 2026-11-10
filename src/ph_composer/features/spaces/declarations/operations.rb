# frozen_string_literal: true

module PhComposer
  module Spaces
    # The operations' public contract: Create Space and its preview, Volume and Floor Segment edits,
    # update, batch, delete, remove, metadata, Make independent and Move Space to Zone. The handlers are
    # Authoring module functions.
    module OperationRegistration
      ZONE = Shapes.object({ "zone_id" => Shapes::TEXT, "zone_path" => Shapes::ZONE_PATH },
                           :description => "The Zone occurrence, as ph_composer.zones.list returns it.")
      OPTIONAL_ZONE = ZONE.merge("type" => %w[object null])
      PATHS = Shapes.list(PATH).merge("minItems" => 1, "maxItems" => Pages::MAXIMUM_LIMIT,
                                      "description" => "Root-to-Face persistent-id paths.")
      # Any one of the three references: the id key it carries says which.
      REFERENCE = Shapes.object({ "space_id" => Shapes::TEXT, "volume_id" => Shapes::TEXT,
                                  "floor_segment_id" => Shapes::TEXT, "entity_path" => PATH },
                                :optional => %w[space_id volume_id floor_segment_id],
                                :description => "A Space, Volume or Floor Segment reference, as list returns it.")
      FACTOR = Schema.factor("The weighting factor to write, 0 to 1; 1 counts the whole area.")
      # Every editable field of the three kinds, typed from its definition with its unit, and the kinds that
      # take it. An optional field accepts null, which removes it. Runtime still refuses a field the
      # referenced kind does not take.
      def self.editable_fields(nullable:)
        Authoring::EDITABLE.each_with_object({}) do |(kind_id, keys), fields|
          kind = KINDS.fetch(kind_id)
          keys.each do |key|
            definition = kind.fields.find { |field| field.key == key }
            schema = fields[key] || definition.schema.dup
            types = Array(schema["type"]) | (nullable || !definition.required ? ["null"] : [])
            takers = Authoring::EDITABLE.select { |_id, editable| editable.include?(key) }
                                        .map { |id, _editable| KINDS.fetch(id).label }
            fields[key] = schema.merge("type" => types.length == 1 ? types.first : types,
                                       "description" => "#{definition.schema['description'] || key} " \
                                                        "(#{takers.join(', ')})".strip)
          end
        end
      end

      EDIT = Shapes.object({
        "reference" => REFERENCE,
        "values" => { "type" => "object", "additionalProperties" => false,
                      "properties" => editable_fields(:nullable => false),
                      "description" => "The values to change, each taken by the kinds named; null removes " \
                                       "an optional value." },
        "expected_values" => { "type" => "object", "additionalProperties" => false,
                               "properties" => editable_fields(:nullable => true),
                               "description" => "Each named value as last read; a key absent here, or null, " \
                                                "expects the value absent." }
      })
      IDS = Shapes.object({ "ids" => Shapes.list(Shapes::TEXT) })
      LEFT_OUT = Shapes.object({ "path" => PATH, "reason" => Shapes::TEXT, "message" => Shapes::TEXT })
      PREVIEW = Shapes.object({
        "accepted" => Shapes.list(PATH), "left_out" => Shapes.list(LEFT_OUT),
        "zone" => OPTIONAL_ZONE.merge("description" => "The open Zone, or else the Zone whose plan footprint holds " \
                                                       "the floor surface's centroid and whose height range holds " \
                                                       "it; null when none does."),
        "height_m" => { "type" => "number", "x-unit" => "m", "description" => "The height the new Space takes." },
        "height_source" => { "type" => "string", "enum" => %w[last_height default],
                             "description" => "Where the height comes from: the Model's last height, or the " \
                                              "default until one is entered." }
      })
      SOURCE_FACES = Shapes.list(PATH, :description => "The named Faces' root-to-Face paths before grouping, " \
                                                       "in floor_segment_ids order.")
      # One new Volume per set of Faces joined by shared Edges, in the order the first Face of each was named.
      NEW_VOLUMES = Shapes.list(Shapes.object({ "volume_id" => Shapes::TEXT,
                                                "floor_segment_ids" => Shapes.list(Shapes::TEXT),
                                                "faces" => SOURCE_FACES }),
                                :description => "Each new Volume and its Floor Segments, one per set of Faces " \
                                                "joined by shared Edges, numbered in that order.").freeze
      CREATED = Shapes.object({
        "space_id" => Shapes::TEXT, "volumes" => NEW_VOLUMES,
        "accepted" => Shapes.list(PATH, :description => "The named Faces taken, as create_preview accepts them."),
        "left_out" => Shapes.list(LEFT_OUT, :description => "The named Faces not taken, each with its reason, as " \
                                                            "create_preview leaves them out.")
      })
      TARGET = %w[record.unreadable target.ambiguous target.changed target.locked target.not_found
                  target.shared_definition validation.failed].freeze
      SPACE_PARAM = SPACE_REFERENCE.merge("description" => "The Space, as list returns it.").freeze
      VOLUME_PARAM = VOLUME_REFERENCE.merge("description" => "The Volume, as list returns it.").freeze
      # Removing an identity checks that nothing still names it.
      REMOVAL = (TARGET + %w[copy.rule_missing reference.in_use]).freeze
      # Erasing or exploding a Group also refuses while another feature's records are on it or inside it.
      GROUP_REMOVAL = (REMOVAL + %w[target.foreign_records]).freeze
      ZONE_TARGET = %w[record.unreadable target.ambiguous target.changed target.locked target.not_found
                       target.shared_definition target.wrong_hierarchy target.wrong_kind validation.failed].freeze
      EXAMPLE_ZONE = { "zone_id" => "zon_Ab12Cd34Ef56", "zone_path" => [1201] }.freeze
      EXAMPLE_SPACE = { "space_id" => "spc_Ab12Cd34Ef56", "entity_path" => [1201, 1300] }.freeze
      EXAMPLE_VOLUME = { "volume_id" => "vol_Ab12Cd34Ef56", "entity_path" => [1201, 1300, 1310] }.freeze

      PREVIEW_PARAMS = Shapes.object({ "faces" => PATHS })
      DEFAULT_FACTOR = 1.0
      # Each action as [name, declaration, handler]; a handler takes the request, the proposal and the params.
      ACTIONS = [
        ["create", {
          :description => "Make one new Space from a floor surface: explicit Faces loose in the open edit context, " \
                          "each becoming a Floor Segment. Faces joined by a shared Edge, a step included, share one " \
                          "Volume; Faces meeting only at a corner, or not at all, make separate Volumes. Works at " \
                          "the root, in a plain Group and in an open Zone, whose Space Group is placed outside the " \
                          "Zone at the same world position.",
          :refuses => (ZONE_TARGET + %w[space.context_required space.nothing_to_create target.edit_path_changed]).uniq,
          :params => Shapes.object(PREVIEW_PARAMS.fetch("properties").merge(
            "zone" => OPTIONAL_ZONE.merge("description" => "The Zone that hosts the new Space; absent or null for no " \
                                                           "Zone. ph_composer.spaces.create_preview names the one " \
                                                           "the review preselects."),
            "name" => Shapes::TEXT.merge("description" => "The new Space's name; empty when absent."),
            "number" => Shapes::TEXT.merge("description" => "The new Space's number; the " \
                                                            "next free one in its Zone, or among Spaces " \
                                                            "in no Zone, when absent."),
            "weighting_factor" => FACTOR
          ), :optional => %w[zone name number weighting_factor]),
          :result => CREATED, :undo_name => "Create Space",
          :side_effects => "Groups each set of joined Faces as a Volume, the Volumes as the Space, and writes the " \
                           "Space, Volume and Floor Segment records.",
          :examples => [{ "zone" => EXAMPLE_ZONE, "faces" => [[1202]], "name" => "Living" }]
        }, lambda { |request, proposal, params|
          Authoring.create(request, proposal, :zone => params["zone"], :faces => params.fetch("faces"),
                                              :name => params["name"], :number => params["number"],
                                              :weighting_factor => params.fetch("weighting_factor", DEFAULT_FACTOR))
        }],
        ["volumes.create", {
          :description => "Group explicit loose Faces at an open Space's root into its next Volumes: one per set " \
                          "of Faces joined by shared Edges, each with the Space's default height.",
          :refuses => (TARGET + %w[space.context_required space.shares_edge target.wrong_hierarchy
                                   target.wrong_kind]).uniq,
          :params => Shapes.object({ "space" => SPACE_PARAM,
                                     "faces" => PATHS, "weighting_factor" => FACTOR },
                                   :optional => ["weighting_factor"]),
          :result => Shapes.object({ "volumes" => NEW_VOLUMES }),
          :undo_name => "Add Volume", :side_effects => "Groups each set of joined Faces as a Volume and writes their " \
                                                       "records.",
          :examples => [{ "space" => EXAMPLE_SPACE, "faces" => [[1201, 1300, 1320]] }]
        }, lambda { |request, proposal, params|
          Authoring.create_volume(request, proposal, :space => params.fetch("space"), :faces => params.fetch("faces"),
                                                     :weighting_factor => params.fetch("weighting_factor",
                                                                                       DEFAULT_FACTOR))
        }],
        ["update", {
          :description => "Change one Space, Volume or Floor Segment's values, guarded by the values last read.",
          :refuses => TARGET, :params => EDIT, :result => IDS, :undo_name => "Edit Space",
          :side_effects => "Rewrites the record; a height edit also records the Model's last height.",
          :examples => [{ "reference" => EXAMPLE_SPACE, "values" => { "v_sup_m3h" => 60.0 }, "expected_values" => {} }]
        }, lambda { |request, proposal, params|
          Authoring.update(request, proposal, :reference => params.fetch("reference"),
                                              :values => params.fetch("values"),
                                              :expected_values => params.fetch("expected_values"))
        }],
        ["batch_update", {
          :description => "Change many Spaces, Volumes and Floor Segments in one all-or-nothing step.",
          :refuses => TARGET,
          :params => Shapes.object({ "edits" => Shapes.list(EDIT).merge("minItems" => 1,
                                                                        "maxItems" => Pages::MAXIMUM_LIMIT,
                                                                        "description" => "The edits, all or none.") }),
          :result => IDS, :undo_name => "Edit Spaces", :side_effects => "Rewrites every named record in one Undo step.",
          :examples => [{ "edits" => [{ "reference" => EXAMPLE_VOLUME, "values" => { "avg_ceiling_height_m" => 2.7 },
                                        "expected_values" => { "avg_ceiling_height_m" => 2.5 } }] }]
        }, ->(request, proposal, params) {
             Authoring.batch_update(request, proposal, :edits => params.fetch("edits"))
           }],
        ["volumes.remove", {
          :description => "Remove one Volume's structure: its Floor Segment records go and its Faces stay loose in " \
                          "the Space.",
          :refuses => GROUP_REMOVAL, :params => Shapes.object({ "volume" => VOLUME_PARAM }),
          :result => Shapes.object({ "volume_id" => Shapes::TEXT }), :undo_name => "Remove Volume",
          :side_effects => "Explodes the Volume Group and removes its records.",
          :examples => [{ "volume" => EXAMPLE_VOLUME }]
        }, lambda { |request, proposal, params|
          Authoring.remove_volume(request, proposal, :volume => params.fetch("volume"))
        }],
        ["volumes.delete", {
          :description => "Erase one Volume and its floor Faces, as SketchUp's Delete would. Deleting a Space's " \
                          "only Volume leaves the Space empty, which reads space.empty; the menu item and the " \
                          "panel offer ph_composer.spaces.delete instead.",
          :refuses => GROUP_REMOVAL, :params => Shapes.object({ "volume" => VOLUME_PARAM }),
          :result => Shapes.object({ "volume_id" => Shapes::TEXT }), :undo_name => "Delete Volume",
          :side_effects => "Erases the Volume Group, its Faces and their records.",
          :examples => [{ "volume" => EXAMPLE_VOLUME }]
        }, lambda { |request, proposal, params|
          Authoring.delete_volume(request, proposal, :volume => params.fetch("volume"))
        }],
        ["delete", {
          :description => "Erase one Space and everything in it.", :refuses => GROUP_REMOVAL,
          :params => Shapes.object({ "space" => SPACE_PARAM }),
          :result => Shapes.object({ "space_id" => Shapes::TEXT }),
          :undo_name => "Delete Space", :side_effects => "Erases the Space Group.",
          :examples => [{ "space" => EXAMPLE_SPACE }]
        }, ->(request, proposal, params) { Authoring.delete(request, proposal, :space => params.fetch("space")) }],
        ["remove", {
          :description => "Remove one Space and keep its floors: the records of the Space, its Volumes and their " \
                          "Floor Segments go, the Groups are exploded and the Faces stay where they are as plain " \
                          "geometry.",
          :refuses => GROUP_REMOVAL, :params => Shapes.object({ "space" => SPACE_PARAM }),
          :result => Shapes.object({ "space_id" => Shapes::TEXT }), :undo_name => "Remove Space",
          :side_effects => "Explodes the Space and Volume Groups and removes their records.",
          :examples => [{ "space" => EXAMPLE_SPACE }]
        }, ->(request, proposal, params) { Authoring.remove(request, proposal, :space => params.fetch("space")) }],
        ["update_metadata", {
          :description => "Replace the user_data and installed extension payloads of explicit Spaces, Volumes and " \
                          "Floor Segments, guarded by the metadata last read.",
          :refuses => (TARGET + %w[extension.invalid extension.migration_required extension.schema_unsupported
                                   extension.unavailable reference.invalid]).uniq,
          :params => Shapes.metadata_updates(REFERENCE, Pages::MAXIMUM_LIMIT),
          :result => Shapes.metadata_result(REFERENCE), :undo_name => "Edit Space Metadata",
          :side_effects => "Rewrites only the named records' metadata.",
          :examples => [{ "updates" => [{ "reference" => EXAMPLE_SPACE,
                                          "user_data" => { "example" => { "note" => "kept" } },
                                          "expected_metadata" => { "user_data" => {}, "extension_data" => {} } }] }]
        }, lambda { |request, proposal, params|
          Authoring.update_metadata(request, proposal, :updates => params.fetch("updates"))
        }],
        ["make_independent", {
          :description => "Give the named copy of a Space, Volume or Floor Segment, and every record inside it, " \
                          "new ids in one step. The named occurrence is the one rewritten; a Space takes the next " \
                          "free number in its Zone.",
          :refuses => (TARGET + %w[copy.rule_missing extension.invalid identity.conflict reference.invalid
                                   space.identity_unique]).uniq,
          :params => Shapes.object({ "reference" => REFERENCE }),
          :result => Shapes.object({ "ids" => Shapes.list(Shapes.object({ "kind" => Shapes::TEXT,
                                                                          "before" => Shapes::TEXT,
                                                                          "after" => Shapes::TEXT })) }),
          :undo_name => "Make Independent",
          :side_effects => "Gives the copy storage of its own and rewrites its records with new ids.",
          :examples => [{ "reference" => EXAMPLE_SPACE }]
        }, lambda { |request, proposal, params|
          Authoring.make_independent(request, proposal, :reference => params.fetch("reference"))
        }],
        ["move_to_zone", {
          :description => "Host one Space in another Zone: its record names the Zone, and its Group stays where it " \
                          "stands. Ids, numbers and values are kept; any edit context may be open.",
          :refuses => (ZONE_TARGET + %w[space.same_zone]).uniq,
          :params => Shapes.object({ "space" => SPACE_PARAM, "zone" => ZONE }),
          :result => Shapes.object({ "space_id" => Shapes::TEXT, "zone_id" => Shapes::TEXT }),
          :undo_name => "Move Space to Zone",
          :side_effects => "Writes the target Zone's id on the Space record; no geometry changes.",
          :examples => [{ "space" => EXAMPLE_SPACE, "zone" => EXAMPLE_ZONE }]
        }, lambda { |request, proposal, params|
          Authoring.move_to_zone(request, proposal, :space => params.fetch("space"), :zone => params.fetch("zone"))
        }],
        ["unhost", {
          :description => "Take one Space out of its Zone, the repair for a Space whose Zone is gone. Its Group " \
                          "stays where it stands and its finding becomes space.outside_zone.",
          :refuses => TARGET,
          :params => Shapes.object({ "space" => SPACE_PARAM }),
          :result => Shapes.object({ "space_id" => Shapes::TEXT }),
          :undo_name => "Remove Space from Zone",
          :side_effects => "Removes the Zone id from the Space record; no geometry changes.",
          :examples => [{ "space" => EXAMPLE_SPACE }]
        }, lambda { |request, proposal, params|
          Authoring.unhost(request, proposal, :space => params.fetch("space"))
        }],
        ["floors.mark", {
          :description => "Mark explicit Faces directly inside Volumes as Floor Segments with one weighting factor; " \
                          "a marked Face takes the factor.",
          :refuses => (TARGET + %w[gesture.too_large target.wrong_hierarchy target.wrong_kind]).uniq,
          :params => Shapes.object({ "faces" => PATHS, "weighting_factor" => FACTOR }),
          :result => Shapes.object({ "floor_segment_ids" => Shapes.list(Shapes::TEXT) }),
          :undo_name => "Mark Floor", :side_effects => "Writes Floor Segment records on the Faces.",
          :examples => [{ "faces" => [[1201, 1300, 1310, 1311]], "weighting_factor" => 1.0 }]
        }, lambda { |request, proposal, params|
          Authoring.mark_floors(request, proposal, :faces => params.fetch("faces"),
                                                   :weighting_factor => params.fetch("weighting_factor"))
        }],
        ["floors.unmark", {
          :description => "Remove explicit Floor Segment records; the Faces stay.", :refuses => REMOVAL,
          :params => Shapes.object({ "floor_segments" => Shapes.list(FLOOR_SEGMENT_REFERENCE).merge(
            "minItems" => 1, "description" => "The Floor Segments whose records go."
          ) }),
          :result => Shapes.object({ "floor_segment_ids" => Shapes.list(Shapes::TEXT) }),
          :undo_name => "Unmark Floor", :side_effects => "Removes Floor Segment records.",
          :examples => [{ "floor_segments" => [{ "floor_segment_id" => "fsg_Ab12Cd34Ef56",
                                                 "entity_path" => [1201, 1300, 1310, 1311] }] }]
        }, lambda { |request, proposal, params|
          Authoring.unmark_floors(request, proposal, :floor_segments => params.fetch("floor_segments"))
        }]
      ].freeze

      module_function

      def install(feature)
        feature.query("#{FEATURE_ID}.create_preview",
                      :description => "Which explicit Faces, loose in the open edit context, Create Space would take " \
                                      "into a new Space, why it leaves each other one out, the Zone it preselects " \
                                      "and the height the Space takes. Writes nothing.",
                      :refuses => (ZONE_TARGET + %w[geometry.invalid]).uniq, :params => PREVIEW_PARAMS,
                      :result => PREVIEW,
                      :examples => [{ "faces" => [[1202]] }]) do |request|
          Authoring.create_preview(request, :faces => request.params.fetch("faces"))
        end
        ACTIONS.each do |name, declaration, handler|
          feature.action("#{FEATURE_ID}.#{name}", **declaration) do |request, proposal|
            handler.call(request, proposal, request.params)
          end
        end
      end
    end
  end
end
