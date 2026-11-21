# frozen_string_literal: true

module PhComposer
  module Programs
    # What occupancy registers: the two extensions, the four assignment actions, the occupancy reads and their
    # snapshot section, the Single dwelling contributor, and the Equipment Set retargeter that moves Dwellings to a
    # replacement Set (context/CONTRACTS.md, "Programs, occupancy and Single dwelling").
    module OccupancyDeclarations
      PREFIX = FEATURE_ID
      ZONE_REFERENCE = Zones::ZONE_REFERENCE
      ZONES = Shapes.list(ZONE_REFERENCE, :description => "Each Zone occurrence, as zones.all or programs.zones " \
                                                          "returns its reference.").merge("minItems" => 1)
      NULLABLE_ID = ->(prefix, description) { SchemaShapes.id(prefix, description, :nullable => true) }
      COUNT = { "type" => %w[number null], "minimum" => 0 }.freeze
      ZONE_EXAMPLE = { "zone_id" => "zon_Ab12Cd34Ef56", "zone_path" => [101] }.freeze
      ASSIGN = %w[programs.dwelling_across_segments programs.single_dwelling extension.invalid
                  extension.migration_required extension.schema_unsupported extension.unavailable record.unreadable
                  reference.in_use reference.invalid target.ambiguous target.changed target.locked target.not_found
                  target.shared_definition target.wrong_hierarchy target.wrong_kind validation.failed].freeze
      CODES = {
        Assignments::SINGLE => "The Zone is in a Building Segment that is a single dwelling, where the setting " \
                               "decides its Program, Dwelling and counts.",
        Assignments::ACROSS => "A Dwelling would hold Zones in more than one Building Segment."
      }.merge(OccupancyReads::FINDINGS).freeze
      FINDING = Shapes.object({ "code" => Shapes::TEXT, "severity" => Shapes::TEXT, "message" => Shapes::TEXT })
      SEGMENT_SETTINGS = Shapes.object({ "single_dwelling" => { "type" => "boolean" },
                                         "default_program_id" => { "type" => %w[string null] },
                                         "bedrooms" => COUNT, "occupants" => COUNT,
                                         "equipment_set_id" => { "type" => %w[string null] } })
      ZONE_ROW = Shapes.object({
        "zone_id" => Shapes::TEXT, "reference" => ZONE_REFERENCE, "name" => { "type" => %w[string null] },
        "building_segment_id" => { "type" => %w[string null] },
        "assignment" => Shapes.described(Shapes::OBJECT, "The stored assignment, every field null when it has none."),
        "program_id" => Shapes.described(Shapes::TEXT, "The Program it uses: under Single dwelling the Model's " \
                                                       "default, else its own, its Segment's default or the Model's."),
        "program_name" => { "type" => %w[string null] },
        "dwelling_id" => Shapes.described({ "type" => %w[string null] }, "Its Dwelling; null in none, and under " \
                                                                         "Single dwelling, whose house is no record."),
        "dwelling_name" => { "type" => %w[string null] },
        "single_dwelling" => { "type" => "boolean", "description" => "Whether its Segment's setting decides it." },
        "equipment_set_id" => Shapes.described({ "type" => %w[string null] }, "Its Dwelling's Set, or its own " \
                                                                              "when in none; null for the Model's " \
                                                                              "default."),
        "floor_area_m2" => { "type" => "number", "x-unit" => "m2", "description" => "Its Spaces' floor area." },
        "icfa_m2" => { "type" => "number", "x-unit" => "m2", "description" => "Its Spaces' weighted area." },
        "people" => Shapes.described({ "type" => %w[number null] }, "Peak people; null while a value is missing."),
        "lighting_w" => { "type" => %w[number null], "x-unit" => "W", "description" => "Peak interior lighting." },
        "ventilation_m3h" => { "type" => %w[number null], "x-unit" => "m3/h" },
        "ventilation_source" => { "type" => %w[string null], "enum" => ["by_program", "detailed", nil] },
        "findings" => Shapes.list(FINDING)
      })
      HOUSE = Shapes.object({ "name" => Shapes::TEXT, "units" => Shapes::COUNT, "bedrooms" => COUNT,
                              "occupants" => COUNT, "occupants_rule" => { "type" => "boolean" },
                              "equipment_set_id" => { "type" => %w[string null] } })
      PREVIEW = Shapes.object({
        "building_segment_id" => Shapes::TEXT,
        "programs" => Shapes.list(Shapes.object({ "zone_id" => Shapes::TEXT, "program_id" => Shapes::TEXT }),
                                  :description => "Each Zone's own Program, which gives way to the default."),
        "dwelling_ids" => Shapes.list(Shapes::TEXT, :description => "Dwellings its Zones are in."),
        "equipment_set_ids" => Shapes.list(Shapes::TEXT, :description => "Sets its Zones and Dwellings name."),
        "bedrooms" => COUNT.merge("description" => "The Zones' bedrooms summed; null when none holds a count."),
        "occupants" => COUNT.merge("description" => "The Zones' occupants summed; null when none holds a count.")
      }).freeze
      SEGMENT_ROW = Shapes.object({
        "id" => Shapes::TEXT, "name" => Shapes::TEXT, "category" => Shapes::TEXT,
        "settings" => Shapes.described(SEGMENT_SETTINGS, "Its occupancy settings, the defaults where it stores " \
                                                         "none."),
        "stored" => { "type" => "boolean" },
        "single_dwelling" => { "type" => "boolean", "description" => "On and residential: the setting applies." },
        "dwelling" => Shapes.described(HOUSE.merge("type" => %w[object null]), "The house under Single " \
                                                                               "dwelling, while it has Zones."),
        "dwelling_count" => Shapes::COUNT,
        "set_points" => Shapes.object({ "heating_c" => { "type" => %w[number null] },
                                        "cooling_c" => { "type" => %w[number null] },
                                        "agree" => { "type" => "boolean" } }),
        "single_dwelling_preview" => PREVIEW,
        "findings" => Shapes.list(FINDING)
      })
      NAMED = Shapes.object({ "id" => Shapes::TEXT, "name" => Shapes::TEXT })
      CHOICES = Shapes.object({
        "programs" => Shapes.list(NAMED, :description => "Every Program, by name."),
        "equipment_sets" => Shapes.list(NAMED, :description => "Every Equipment Set, by name."),
        "default_program_id" => Shapes::TEXT, "default_equipment_set_id" => Shapes::TEXT
      })
      DWELLING_ROW = Shapes.object({
        "id" => { "type" => %w[string null] }, "name" => Shapes::TEXT, "units" => Shapes::COUNT,
        "single_dwelling" => { "type" => "boolean" }, "own_bedrooms" => COUNT, "own_occupants" => COUNT,
        "bedrooms" => COUNT, "occupants" => COUNT, "occupants_rule" => { "type" => "boolean" },
        "equipment_set_id" => { "type" => %w[string null] }, "zone_ids" => Shapes.list(Shapes::TEXT),
        "building_segment_ids" => Shapes.list(Shapes::TEXT), "findings" => Shapes.list(FINDING)
      })

      module_function

      def install(feature)
        feature.extension(Occupancy::ZONE_EXTENSION)
        feature.extension(Occupancy::SEGMENT_EXTENSION)
        CODES.each { |code, description| feature.code(code, :description => description) }
        assign_program(feature)
        assign_dwelling(feature)
        set_counts(feature)
        assign_equipment_set(feature)
        reads(feature)
        SingleDwelling.install(feature)
        feature.reference_retargeter("#{PREFIX}.dwellings.retarget_equipment_set",
                                     :target_kind => EQUIPMENT_SET_KIND) do |request, proposal, from:, to:|
          retarget_dwellings(request, proposal, :from => from, :to => to)
        end
      end

      def action(feature, name, description:, params:, result:, undo_name:, side_effects:, examples:, &handler)
        feature.action("#{PREFIX}.#{name}", :description => description, :refuses => ASSIGN, :params => params,
                                            :result => result, :undo_name => undo_name,
                                            :participants => [Assignments::STAGE], :side_effects => side_effects,
                                            :examples => examples, &handler)
      end

      def assign_program(feature)
        params = Shapes.object({ "zones" => ZONES,
                                 "program_id" => NULLABLE_ID.call("pgm", "The Program; null returns each Zone to " \
                                                                         "its Segment's default.") })
        result = Shapes.object({ "zone_ids" => Shapes.list(Shapes::TEXT),
                                 "program_id" => { "type" => %w[string null] } })
        action(feature, "assign_program", :description => "Set the Program of Zones.", :params => params,
                                          :result => result, :undo_name => "Assign Program",
                                          :side_effects => "Writes each Zone's assignment; stores the residential " \
                                                           "default when it is named.",
                                          :examples => [{ "zones" => [ZONE_EXAMPLE],
                                                          "program_id" => "pgm_Ab12Cd34Ef56" }]) do |request, proposal|
          Assignments.assign_program(request, proposal, :zones => request.params.fetch("zones"),
                                                        :program_id => request.params.fetch("program_id"))
        end
      end

      def assign_dwelling(feature)
        params = Shapes.object({
          "zones" => ZONES,
          "choice" => { "type" => "string", "enum" => Assignments::CHOICES,
                        "description" => "shared: one new Dwelling for them all; each: one new Dwelling per Zone; " \
                                         "none: no Dwelling; existing: the Dwelling dwelling_id names." },
          "dwelling_id" => SchemaShapes.id("dwl", "The Dwelling, for existing.")
        }, :optional => ["dwelling_id"])
        result = Shapes.object({ "zone_ids" => Shapes.list(Shapes::TEXT), "dwelling_ids" => Shapes.list(Shapes::TEXT),
                                 "deleted_dwelling_ids" => Shapes.list(Shapes::TEXT) })
        action(feature, "assign_dwelling",
               :description => "Put Zones in a Dwelling: one shared, one each, none, or an existing one. A Dwelling " \
                               "left with no Zones is deleted in the same step.",
               :params => params, :result => result, :undo_name => "Assign Dwelling",
               :side_effects => "Writes each Zone's assignment; creates and deletes Dwellings.",
               :examples => [{ "zones" => [ZONE_EXAMPLE], "choice" => "shared" },
                             { "zones" => [ZONE_EXAMPLE], "choice" => "existing",
                               "dwelling_id" => "dwl_Ab12Cd34Ef56" }]) do |request, proposal|
          params = request.params
          Assignments.assign_dwelling(request, proposal, :zones => params.fetch("zones"),
                                                         :choice => params.fetch("choice"),
                                                         :dwelling_id => params["dwelling_id"])
        end
      end

      def set_counts(feature)
        params = Shapes.object({ "zone" => ZONE_REFERENCE.merge("description" => "The Zone occurrence, in a Dwelling."),
                                 "bedrooms" => COUNT.merge("description" => "Its bedrooms; null for none."),
                                 "occupants" => COUNT.merge("description" => "Its occupants; null lets the " \
                                                                             "Dwelling's sum or the Phius rule " \
                                                                             "decide.") })
        action(feature, "set_counts",
               :description => "Set one Zone's bedrooms and occupants, which its Dwelling sums.",
               :params => params, :result => Shapes.object({ "zone_id" => Shapes::TEXT }),
               :undo_name => "Set Bedrooms and Occupants", :side_effects => "Writes the Zone's assignment.",
               :examples => [{ "zone" => ZONE_EXAMPLE, "bedrooms" => 2, "occupants" => nil }]) do |request, proposal|
          params = request.params
          Assignments.set_counts(request, proposal, :zone => params.fetch("zone"),
                                                    :bedrooms => params.fetch("bedrooms"),
                                                    :occupants => params.fetch("occupants"))
        end
      end

      def assign_equipment_set(feature)
        params = Shapes.object({
          "equipment_set_id" => NULLABLE_ID.call("eqs", "The Equipment Set; null for the Model's default."),
          "dwelling_ids" => Shapes.list(SchemaShapes.id("dwl", "A Dwelling."), :description => "Dwellings to set."),
          "zones" => Shapes.list(ZONE_REFERENCE, :description => "Zones in no Dwelling to set.")
        }, :optional => %w[dwelling_ids zones])
        result = Shapes.object({ "dwelling_ids" => Shapes.list(Shapes::TEXT), "zone_ids" => Shapes.list(Shapes::TEXT),
                                 "equipment_set_id" => { "type" => %w[string null] } })
        action(feature, "assign_equipment_set",
               :description => "Set the Equipment Set of Dwellings, or of Zones in no Dwelling.",
               :params => params, :result => result, :undo_name => "Assign Equipment Set",
               :side_effects => "Updates each Dwelling and writes each Zone's assignment; stores the default " \
                                "Set when it is named.",
               :examples => [{ "equipment_set_id" => "eqs_Ab12Cd34Ef56",
                               "dwelling_ids" => ["dwl_Ab12Cd34Ef56"] }]) do |request, proposal|
          params = request.params
          Assignments.assign_equipment_set(request, proposal, :equipment_set_id => params.fetch("equipment_set_id"),
                                                              :dwelling_ids => params.fetch("dwelling_ids", []),
                                                              :zones => params.fetch("zones", []))
        end
      end

      def reads(feature)
        zones = Shapes.object({ "zones" => Shapes.list(ZONE_ROW), "building_segments" => Shapes.list(SEGMENT_ROW),
                                "choices" => CHOICES })
        feature.query("#{PREFIX}.zones", :response => { "bounded" => false, "prefer" => "ph_composer.zones.list" },
                                         :description => "Every Zone's assignment and what it works out to: its " \
                                                         "Program, Dwelling, peak people, lighting and " \
                                                         "ventilation, with findings; and each Building Segment's " \
                                                         "occupancy, set points and Single dwelling preview.",
                                         :refuses => %w[geometry.invalid record.unreadable], :params => Shapes::NONE,
                                         :result => zones, :examples => [{}]) do |request|
          OccupancyReads.zones(request)
        end
        feature.query("#{PREFIX}.dwellings", :response => { "bounded" => false,
                                                            "prefer" => "#{PREFIX}.dwellings.list" },
                                             :description => "Every Dwelling with its Zones and counts, the " \
                                                             "single-dwelling houses among them.",
                                             :refuses => %w[geometry.invalid record.unreadable],
                                             :params => Shapes::NONE,
                                             :result => Shapes.object({ "dwellings" => Shapes.list(DWELLING_ROW) }),
                                             :examples => [{}]) do |request|
          OccupancyReads.dwellings(request)
        end
        feature.snapshot_section("#{PREFIX}.occupancy", :query => "#{PREFIX}.zones")
        feature.query("#{PREFIX}.single_dwelling_preview",
                      :description => "What switching Single dwelling on in one Building Segment replaces: Programs " \
                                      "chosen per Zone, Dwellings and Equipment Sets, and the Zones' summed bedrooms " \
                                      "and occupants, which the Save then carries.",
                      :refuses => %w[geometry.invalid record.unreadable target.not_found],
                      :params => Shapes.object({ "id" => SchemaShapes.id("bsg", "The Building Segment.") }),
                      :result => PREVIEW, :examples => [{ "id" => "bsg_Ab12Cd34Ef56" }]) do |request|
          id = request.params.fetch("id")
          state = OccupancyState.read(request)
          raise CodedError.new("target.not_found",
                               "There is no Building Segment with id #{id}.") unless state.segment(id)

          SingleDwelling.preview(state, id)
        end
      end

      # Moves every Dwelling from one Equipment Set to its replacement, inside that Set's delete.
      def retarget_dwellings(request, proposal, from:, to:)
        request.engine.ids(DWELLING_KIND).sort.each do |id|
          record = request.engine.find(DWELLING_KIND, id, :change_set => proposal)
          next unless record.fetch("equipment_set_id") == from

          request.engine.propose_update(DWELLING_KIND, id, proposal, :values => { "equipment_set_id" => to })
        end
        Records::ReferencePlan.new(:entries => [])
      end
    end
  end
end
