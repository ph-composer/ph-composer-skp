# frozen_string_literal: true

require_relative "../units/actions"
require_relative "../units/host_extent"
require_relative "../units/outlines"
require_relative "../units/repairs"
require_relative "../units/update_step"

module PhComposer
  module Windows
    module UnitRegistration
      STATUS_MAP = { "type" => "object", "description" => "Each extension envelope's status, by namespace." }.freeze
      EXAMPLE_UNIT = { "unit_id" => "wun_Ab12Cd34Ef56", "entity_path" => [1201, 1203] }.freeze
      METADATA_EXAMPLE = { "updates" => [{ "reference" => EXAMPLE_UNIT, "user_data" => {},
                                           "expected_metadata" => { "user_data" => {}, "extension_data" => {} } }] }
                         .freeze
      ANCHOR = { "type" => "string", "enum" => Units::Anchors::ALL }.freeze
      ANCHOR_TEXT = "Which point of the opening sits at the placement point: sill, center or head, by left, " \
                    "center or right as seen from outside."

      module_function

      # A list of explicit Unit occurrence references, as units.list returns them.
      def units(reference, description)
        Shapes.list(reference).merge("minItems" => 1, "maxItems" => 500, "description" => description)
      end

      def unit(reference, description)
        Shapes.described(reference, description)
      end

      def host(face, description)
        Shapes.described(face, description)
      end

      def install(feature, registry)
        face = DeepCopy.call(registry.record_descriptor("ph_composer.zones.faces.face").occurrence_schema)
        reference = Units::TARGET.descriptor.occurrence_schema
        feature.reference_target(Units::TARGET)
        reads(feature, face, reference)
        repairs(feature, face, reference)
        batch_repairs(feature, reference)
        identity_repair(feature, reference)
        metadata(feature, reference)
        flip_repair(feature, reference)
        restore_repair(feature, face)
        place(feature, face)
        host_extent(feature, face, reference)
        outlines(feature, face, reference)
      end

      def reads(feature, face, reference)
        repair = Shapes.described(Shapes.object({ "name" => Shapes::TEXT, "params" => Shapes::OBJECT }),
                                  "The action that repairs this condition and its params for this Window; a rehost " \
                                  "adds `host` and a swap adds `type_id`. Null when no single action repairs it.")
                       .merge("type" => %w[object null])
        finding = Shapes.object({ "code" => Shapes::TEXT, "repair" => repair })
        view = Shapes.with(Units::RECORD_KIND.descriptor.view_schema,
                           "reference" => reference, "host" => face.merge("type" => %w[object null]),
                           "extension_status" => STATUS_MAP,
                           "findings" => Shapes.list(finding))
        prefix = "#{FEATURE_ID}.units"
        result = Shapes.object({ "units" => Shapes.list(view) })
        feature.query("#{prefix}.list",
                      :description => "Window occurrences and native findings, without writes.",
                      :refuses => Refuses::UNIT_READ + Refuses::PAGE,
                      :params => Shapes.list_params,
                      :result => Shapes.with(result, "next_cursor" => Pages::NEXT_CURSOR, "total" => Pages::TOTAL),
                      :examples => [{}]) { |request| Units::Actions.list(request) }
        feature.query("#{prefix}.all", :description => "All Window occurrences and native findings for the snapshot.",
                                       :response => { "bounded" => false, "prefer" => "#{prefix}.list" },
                                       :refuses => Refuses::UNIT_READ,
                                       :params => Shapes::NONE, :result => result, :examples => [{}]) do |request|
          Units::Actions.list(request, :paged => false)
        end
        feature.snapshot_section(prefix, :query => "#{prefix}.all")
      end

      def repairs(feature, face, reference)
        prefix = "#{FEATURE_ID}.units"
        feature.action("#{prefix}.remove",
                       :description => "Remove explicit Window occurrences with reference guards.",
                       :refuses => Refuses::DELETE + %w[window.nested_units],
                       :params => Shapes.object({ "units" => units(reference, "The Window occurrences to remove.") }),
                       :result => Shapes.object({ "unit_ids" => Shapes.list(Shapes::TEXT) }),
                       :undo_name => "Remove Windows",
                       :side_effects => Shapes.side_effects(
                         "Removes only the chosen instances; incoming references must remain valid."
                       ),
                       :examples => [{ "units" => [EXAMPLE_UNIT] }]) do |request, proposal|
          Units::Repairs.remove(request, proposal, :units => request.params.fetch("units"))
        end
        feature.action("#{prefix}.rehost",
                       :description => "Glue an unmoved Window to an explicit same-storage Face.",
                       :refuses => Refuses::UNIT_GEOMETRY + %w[window.definition_changed window.rehost_parent],
                       :params => Shapes.object({ "unit" => unit(reference, "The Window occurrence to glue."),
                                                  "host" => host(face, "The Face to glue it to, in the same parent " \
                                                                       "storage; the Window must lie on it.") }),
                       :result => Shapes.object({ "unit_id" => Shapes::TEXT }), :undo_name => "Re-host Window",
                       :side_effects => Shapes.side_effects("Changes glue only, after containment and overlap checks."),
                       :examples => [{ "unit" => { "unit_id" => "wun_Ab12Cd34Ef56", "entity_path" => [1201, 1203] },
                                       "host" => { "zone_id" => "zon_Ab12Cd34Ef56", "zone_path" => [1201],
                                                   "entity_path" => [1202],
                                                   "entity_id" => nil } }]) do |request, proposal|
          Units::Repairs.rehost(request, proposal, :unit => request.params.fetch("unit"),
                                                   :host => request.params.fetch("host"))
        end
      end

      def batch_repairs(feature, reference)
        feature.action("#{FEATURE_ID}.units.swap_type",
                       :description => "Swap explicit Windows, preserving their anchors.",
                       :refuses => Refuses::SWAP_TYPE,
                       :params => Shapes.object({ "units" => units(reference, "The Window occurrences to swap."),
                                                  "type_id" => Shapes.id("wnt", "The Window Type they take.") }),
                       :result => Shapes.object({ "unit_ids" => Shapes.list(Shapes::TEXT) }),
                       :undo_name => "Swap Window Type",
                       :side_effects => Shapes.side_effects(
                         "Reuses one target definition and preserves each Unit's metadata and host."
                       ),
                       :examples => [{ "units" => [EXAMPLE_UNIT],
                                       "type_id" => "wnt_Ab12Cd34Ef56" }]) do |request, proposal|
          Units::Repairs.swap_type(request, proposal, :units => request.params.fetch("units"),
                                                      :type_id => request.params.fetch("type_id"))
        end
        feature.action("#{FEATURE_ID}.units.reset_to_type",
                       :description => "Reset explicit Windows of one Type to its authored geometry.",
                       :refuses => Refuses::RESET_TO_TYPE,
                       :params => Shapes.object({ "units" => units(reference, "The Window occurrences to reset, all " \
                                                                              "of one Window Type.") }),
                       :result => Shapes.object({ "unit_ids" => Shapes.list(Shapes::TEXT) }),
                       :undo_name => "Reset Windows to Type",
                       :side_effects => Shapes.side_effects(
                         "Repairs selected instances; regenerating an edited primary affects all its Units."
                       ),
                       :examples => [{ "units" => [EXAMPLE_UNIT] }]) do |request, proposal|
          Units::Repairs.reset_to_type(request, proposal, :units => request.params.fetch("units"))
        end
      end

      def identity_repair(feature, reference)
        repair = Shapes.object({ "entity_path" => { "type" => "array", "items" => { "type" => "integer" } },
                                 "old_unit_id" => Shapes::TEXT, "new_unit_id" => Shapes::TEXT })
        feature.action("#{FEATURE_ID}.units.repair_copied_identities",
                       :description => "Give the copies sharing each chosen Window's identity new identities. The " \
                                       "first occurrence by entity path keeps the identity; a preview lists each old " \
                                       "and new id.",
                       :refuses => Refuses::EDIT,
                       :params => Shapes.object({ "units" => units(reference, "Windows whose identity a copy shares; " \
                                                                              "either the original or a copy names " \
                                                                              "the group.") }),
                       :result => Shapes.object({ "repairs" => Shapes.list(repair) }),
                       :undo_name => "Repair Copied Windows",
                       :side_effects => "Rewrites only the copied Unit records' identities; geometry, glue and " \
                                        "metadata stay.",
                       :examples => [{ "units" => [EXAMPLE_UNIT] }]) do |request, proposal|
          Units::Repairs.copied_identities(request, proposal, :units => request.params.fetch("units"))
        end
      end

      def metadata(feature, reference)
        feature.action("#{FEATURE_ID}.units.update_metadata",
                       :description => "Replace the user_data and installed extension payloads of explicit Window " \
                                       "occurrences, guarded by the metadata last read.",
                       :refuses => (Refuses::EDIT + %w[extension.migration_required extension.schema_unsupported
                                                       extension.unavailable]).uniq,
                       :params => Shapes.metadata_updates(reference, Pages::MAXIMUM_LIMIT),
                       :result => Shapes.metadata_result(reference), :undo_name => "Edit Window Metadata",
                       :side_effects => Shapes.side_effects("Rewrites only the named Windows' metadata."),
                       :examples => [METADATA_EXAMPLE]) do |request, proposal|
          Authoring.update_unit_metadata(request, proposal, :updates => request.params.fetch("updates"))
        end
      end

      def flip_repair(feature, reference)
        feature.action("#{FEATURE_ID}.units.new_flipped_type",
                       :description => "Create a horizontally flipped Type for one mirrored Window.",
                       :refuses => Refuses::NEW_FLIPPED_TYPE,
                       :params => Shapes.object({ "unit" => unit(reference, "The mirrored Window occurrence."),
                                                  "name" => { "type" => "string", "minLength" => 1,
                                                              "description" => "The new Type's name; " \
                                                                               "\"<Type> (flipped)\" when absent." } },
                                                :optional => ["name"]),
                       :result => Shapes.object({ "unit_id" => Shapes::TEXT, "type_id" => Shapes::TEXT }),
                       :undo_name => "New Flipped Window Type",
                       :side_effects => Shapes.side_effects(
                         "Creates one independent Type; preserves physical panes, metadata and glue."
                       ),
                       :examples => [{ "unit" => EXAMPLE_UNIT }]) do |request, proposal|
          Units::Repairs.new_flipped_type(request, proposal, :unit => request.params.fetch("unit"),
                                                             :name => request.params["name"])
        end
      end

      def restore_repair(feature, face)
        path = { "type" => "array", "minItems" => 1, "items" => { "type" => "integer", "minimum" => 1 } }
        feature.action("#{FEATURE_ID}.units.restore",
                       :description => "Recover a Unit from exact stamped pane Faces.",
                       :refuses => Refuses::RESTORE,
                       :params => Shapes.object({ "host" => host(face, "The Face the loose panes lie on."),
                                                  "type_id" => Shapes.id("wnt", "The Window Type the panes were " \
                                                                                "stamped with."),
                                                  "pane_paths" => Shapes.list(path).merge(
                                                    "minItems" => 1, "maxItems" => 500,
                                                    "description" => "Each stamped pane Face's entity path from the " \
                                                                     "Model root."
                                                  ) }),
                       :result => Shapes.object({ "unit_id" => Shapes::TEXT }), :undo_name => "Restore Window",
                       :side_effects => Shapes.side_effects(
                         "Creates a new default-anchor Unit and removes only its exact loose panes and edges."
                       ),
                       :examples => [{ "host" => { "zone_id" => "zon_Ab12Cd34Ef56", "zone_path" => [1201],
                                                   "entity_path" => [1202], "entity_id" => nil },
                                       "type_id" => "wnt_Ab12Cd34Ef56",
                                       "pane_paths" => [[1201, 1204]] }]) do |request, proposal|
          Units::Repairs.restore(request, proposal,
                                 :host => request.params.fetch("host"),
                                 :type_id => request.params.fetch("type_id"),
                                 :pane_paths => request.params.fetch("pane_paths"))
        end
      end

      def host_extent(feature, face, reference)
        number = { "type" => "number", "x-unit" => "m" }
        rectangle = { "x_m" => number, "y_m" => number, "width_m" => number, "height_m" => number }
        feature.query("#{FEATURE_ID}.units.host_extent",
                      :description => "A writable Zone Face's outline and bounding width and height in the frame " \
                                      "units.place offsets use, with the holes and Window outlines on its plane " \
                                      "to keep clear of.",
                      :refuses => Refuses::HOST_EXTENT + Refuses::PAGE,
                      :params => Shapes.object({ "host" => host(face, "The Zone Face a Window would be placed on."),
                                                 "limit" => Pages::LIMIT, "cursor" => Pages::CURSOR },
                                               :optional => %w[limit cursor]),
                      :result => Shapes.object({
                        "width_m" => number, "height_m" => number,
                        "outline_m" => Shapes.list({ "type" => "array", "items" => number, "minItems" => 2,
                                                     "maxItems" => 2 },
                                                   :description => "The Face's outer loop as [x_m, y_m] offsets; " \
                                                                   "a Face that is not a rectangle is narrower " \
                                                                   "than width_m by height_m in places."),
                        "holes" => Shapes.list(Shapes.object(rectangle),
                                               :description => "Each hole's bounding rectangle, in offsets."),
                        "units" => Shapes.list(Shapes.object({ "reference" => reference }.merge(rectangle)),
                                               :description => "One page of the Window outlines on the Face's plane " \
                                                               "that meet its bounding box, each as a bounding " \
                                                               "rectangle in offsets."),
                        "next_cursor" => Pages::NEXT_CURSOR, "total" => Pages::TOTAL
                      }),
                      :examples => [{ "host" => { "zone_id" => "zon_Ab12Cd34Ef56", "zone_path" => [1201],
                                                  "entity_path" => [1202], "entity_id" => nil } }]) do |request|
          Units::HostExtent.read(request, request.params.fetch("host"))
        end
      end

      def outlines(feature, face, reference)
        point = { "type" => "array", "items" => { "type" => "number", "x-unit" => "m" }, "minItems" => 3,
                  "maxItems" => 3 }
        host = face.merge("type" => %w[object null], "description" => "The Zone Face the Unit is glued to, or null.")
        outline = Shapes.list(point, :description => "The Unit's outer outline in world metres, one point per corner.")
        row = Shapes.object({ "reference" => reference, "host" => host, "outline_m" => outline })
        result = Shapes.object({ "units" => Shapes.list(row, :description => "One page of placed Windows, in path " \
                                                                             "order."),
                                 "next_cursor" => Pages::NEXT_CURSOR, "total" => Pages::TOTAL })
        feature.query(Units::Outlines::QUERY,
                      :description => "Each placed Window's world outline in metres, with the Zone Face it is " \
                                      "glued to.",
                      :refuses => Refuses::UNIT_READ + Refuses::PAGE, :params => Shapes.list_params,
                      :result => result, :examples => [{}, { "limit" => 20 }]) do |request|
          Units::Outlines.read(request)
        end
      end

      def place(feature, face)
        prefix = "#{FEATURE_ID}.units"
        feature.action("#{prefix}.place",
                       :description => "Place an anchored Window on an explicit writable Zone Face.",
                       :refuses => Refuses::UNIT_GEOMETRY + %w[window.definition_changed window.definition_missing],
                       :params => Shapes.object({ "host" => host(face, "The writable Zone Face to place on."),
                                                  "type_id" => Shapes.id("wnt", "The Window Type to place."),
                                                  "anchor" => ANCHOR.merge("description" => ANCHOR_TEXT),
                                                  "offsets" => Shapes.described(
                                                    Shapes.object({ "x_m" => { "type" => "number", "x-unit" => "m" },
                                                                    "y_m" => { "type" => "number", "x-unit" => "m" } }),
                                                    "Where the anchor goes on the Face, in metres right and up from " \
                                                    "the Face's lowest, leftmost extent as seen from outside."
                                                  ),
                                                  "user_data" => Shapes::USER_DATA },
                                                :optional => ["user_data"]),
                       :result => Shapes.object({ "unit_id" => Shapes::TEXT }),
                       :undo_name => "Place Window",
                       :side_effects => Shapes.side_effects(
                         "Creates or reuses the Type definition, glues an instance and stores its Unit record."
                       ),
                       :examples => [{ "host" => { "zone_id" => "zon_Ab12Cd34Ef56", "zone_path" => [1201],
                                                   "entity_path" => [1202], "entity_id" => nil },
                                       "type_id" => "wnt_Ab12Cd34Ef56", "anchor" => "sill_center",
                                       "offsets" => { "x_m" => 1.0, "y_m" => 0.8 } }]) do |request, proposal|
          params = request.params
          Units::Actions.place(request, proposal,
                               :host => params.fetch("host"), :type_id => params.fetch("type_id"),
                               :offsets => params.fetch("offsets"), :anchor => params.fetch("anchor"),
                               :user_data => params.fetch("user_data", {}))
        end
      end
    end
  end
end
