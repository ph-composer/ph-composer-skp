# frozen_string_literal: true

module PhComposer
  module Mechanical
    # What the heat pump catalogs register: the four kinds, and for each a bounded list, the all read with its
    # snapshot section, and create, update, duplicate and delete; then the read-only Blended result. Every write goes
    # through the record engine, one native Undo step each. A delete with a replacement moves every record and Zone
    # naming the record to it, in the same step.
    module HeatPumpRegistration
      OUTDOOR_EQUIPMENT = HeatPumps::OutdoorEquipment::KIND
      INDOOR_EQUIPMENT = HeatPumps::IndoorEquipment::KIND
      OUTDOOR_UNITS = HeatPumps::OutdoorUnits::KIND
      INDOOR_UNITS = HeatPumps::IndoorUnits::KIND
      KINDS = [OUTDOOR_EQUIPMENT, INDOOR_EQUIPMENT, OUTDOOR_UNITS, INDOOR_UNITS].freeze
      PREFIXES = { OUTDOOR_EQUIPMENT.id => "#{FEATURE_ID}.heat_pumps.outdoor_equipment",
                   INDOOR_EQUIPMENT.id => "#{FEATURE_ID}.heat_pumps.indoor_equipment",
                   OUTDOOR_UNITS.id => "#{FEATURE_ID}.heat_pumps.outdoor_units",
                   INDOOR_UNITS.id => "#{FEATURE_ID}.heat_pumps.indoor_units" }.freeze
      BLENDED = "#{FEATURE_ID}.heat_pumps.blended"
      BLENDED_SECTION = "#{FEATURE_ID}.heat_pumps_blended"
      PAGE = VentilatorRegistration::PAGE
      # Every row reads the Zones, Climate is not read for them.
      READ = Serves::State::REFUSES
      CREATE = (VentilatorRegistration::CREATE + %w[reference.invalid]).sort.freeze
      EDIT = VentilatorRegistration::EDIT
      DUPLICATE = VentilatorRegistration::DUPLICATE
      DELETE = VentilatorRegistration::DELETE
      FINDINGS = ServesRegistration::FINDINGS
      COUNT = { "type" => "integer", "minimum" => 0 }.freeze
      ROWS = {
        OUTDOOR_EQUIPMENT.id => Shapes.with(Shapes.row(OUTDOOR_EQUIPMENT), {
          "unit_count" => Shapes.described(COUNT, "How many readable outdoor units install it."),
          "findings" => FINDINGS
        }),
        INDOOR_EQUIPMENT.id => Shapes.with(Shapes.row(INDOOR_EQUIPMENT), {
          "unit_count" => Shapes.described(COUNT, "How many readable indoor units install it."),
          "findings" => FINDINGS
        }),
        OUTDOOR_UNITS.id => Shapes.with(Shapes.row(OUTDOOR_UNITS), {
          "indoor_unit_count" => Shapes.described(COUNT, "How many readable indoor units it serves."),
          "findings" => FINDINGS
        }),
        INDOOR_UNITS.id => Shapes.with(Shapes.row(INDOOR_UNITS), ServesRegistration::SERVED)
      }.freeze
      # What each kind names, which its create requires.
      PARENTS = { OUTDOOR_UNITS.id => ["outdoor_equipment_id"],
                  INDOOR_UNITS.id => %w[indoor_equipment_id outdoor_unit_id] }.freeze
      DETAILS = {
        OUTDOOR_EQUIPMENT.id => ", with export readiness (false while it lacks a value the blend needs), its outdoor " \
                                "unit count and findings",
        INDOOR_EQUIPMENT.id => ", with its indoor unit count",
        OUTDOOR_UNITS.id => ", with its indoor unit count and findings: none of its indoor units serving a Zone, or " \
                            "Zones in two Building Segments",
        INDOOR_UNITS.id => ", with the Zones each serves and its findings"
      }.freeze
      DESCRIPTIONS = {
        OUTDOOR_EQUIPMENT.id => "Unless values give them, it is rated by a COP pair, honeybee-ph's 2.5 at 17 F and " \
                                "47 F, with HSPF2 and SEER2 versions and no cooling; its capacities stay absent " \
                                "until given, and the blend leaves it out until then.",
        INDOOR_EQUIPMENT.id => "It holds its Tag, Manufacturer, Model and Notes only.",
        OUTDOOR_UNITS.id => "Unless values give them, it is one unit outside the conditioned space.",
        INDOOR_UNITS.id => "Unless values give them, it is one unit inside the conditioned space."
      }.freeze
      MODEL_EXAMPLE = "hpo_Ab12Cd34Ef56"
      CREATE_EXAMPLES = {
        OUTDOOR_EQUIPMENT.id => { "values" => { "name" => "ODU-A", "heating_cap_17f_kw" => 6.4,
                                                "heating_cap_47f_kw" => 7.3, "cop_17f" => 2.4, "cop_47f" => 3.9 } },
        INDOOR_EQUIPMENT.id => { "values" => { "name" => "IDU-W09", "manufacturer" => "Kaltwerk" } },
        OUTDOOR_UNITS.id => { "values" => { "name" => "HP-1", "outdoor_equipment_id" => MODEL_EXAMPLE } },
        INDOOR_UNITS.id => { "values" => { "name" => "HP-1.1", "indoor_equipment_id" => "hpi_Ab12Cd34Ef56",
                                           "outdoor_unit_id" => "hou_Ab12Cd34Ef56" } }
      }.freeze
      UPDATE_EXAMPLES = {
        OUTDOOR_EQUIPMENT.id => { "values" => { "cooling_rating_mode" => "ieer", "cooling_cap_95f_kw" => 28.1,
                                                "ieer" => 21.4 },
                                  "expected_values" => { "cooling_rating_mode" => nil } },
        INDOOR_EQUIPMENT.id => { "values" => { "model" => "MSZ-09NA" }, "expected_values" => { "model" => nil } },
        OUTDOOR_UNITS.id => { "values" => { "quantity" => 2 }, "expected_values" => { "quantity" => 1 } },
        INDOOR_UNITS.id => { "values" => { "quantity" => 2 }, "expected_values" => { "quantity" => 1 } }
      }.freeze
      LIST_EXAMPLES = [{}, { "limit" => 20 }, { "fields" => %w[values export_ready] }].freeze
      SEGMENT = Shapes.object({
        "segment" => Shapes.described(Shapes::TEXT, "The Building Segment's name."),
        "identifier" => Shapes.described(Shapes::TEXT, "The blended heat pump's identifier on every Room it is " \
                                                       "written to."),
        "display_name" => Shapes::TEXT,
        "zones" => Shapes.list(Shapes.object({ "zone_id" => Shapes::TEXT, "name" => Shapes::TEXT }),
                               :description => "The served Zones it is written to."),
        "outdoor_unit_ids" => Shapes.list(Shapes::TEXT, :description => "The outdoor units its indoor units name."),
        "result" => Shapes.described({ "type" => "object" },
                                     "The estimator's sections: climate (design temperatures in F, monthly means " \
                                     "and heating months), devices (each outdoor model's inputs in kBtu/h), weighted " \
                                     "(each model's shares and weighted ratings), totals (capacity, COP and input " \
                                     "power for cooling and heating at 17 F and 47 F), energy_model (the Inputs for " \
                                     "Energy Model) and export (the SI values the HBJSON carries).")
      }).freeze
      OBJECT_ID = Shapes.described({ "type" => %w[string null] }, "The record the finding is about; null for a " \
                                                                  "Building Segment's or the climate's.").freeze
      BLENDED_RESULT = Shapes.object({
        "climate" => Shapes.object({ "state" => { "type" => "string", "enum" => %w[complete missing] },
                                     "reason" => { "type" => %w[string null] } }),
        "segments" => Shapes.list(SEGMENT, :description => "One blend per exported Building Segment with a served " \
                                                           "Zone, in name order."),
        "findings" => Shapes.list(Shapes.with(ServesRegistration::FINDING, "object_id" => OBJECT_ID))
      }).freeze

      module_function

      def install(feature)
        KINDS.each do |kind|
          feature.record_kind(kind)
          install_reads(feature, kind)
          install_create_and_update(feature, kind)
          install_duplicate(feature, kind)
          install_delete(feature, kind)
        end
        install_blended(feature)
      end

      def install_reads(feature, kind)
        prefix = PREFIXES.fetch(kind.id)
        row = ROWS.fetch(kind.id)
        list = HeatPumps::Reads::LISTS.fetch(kind.id)
        params = DefinitionLists.params(row).tap do |schema|
          schema["properties"]["ids"]["items"] = Shapes.id(kind.id_prefix, "A #{kind.label} id.")
        end
        feature.query(list, :description => "One bounded page of #{kind.label} records in id order" \
                                            "#{DETAILS.fetch(kind.id)}.",
                            :refuses => PAGE + READ, :params => params,
                            :result => DefinitionLists.result(row, :paged => true),
                            :examples => LIST_EXAMPLES) do |request|
          HeatPumps::Reads.list(request, kind.id, :extra => HeatPumpReads.extra(request, kind.id))
        end
        feature.query("#{prefix}.all", :description => "Every #{kind.label} record#{DETAILS.fetch(kind.id)}, for " \
                                                       "the panel snapshot.",
                                       :response => { "bounded" => false, "prefer" => list },
                                       :refuses => READ, :params => Shapes::NONE,
                                       :result => DefinitionLists.result(row, :paged => false),
                                       :examples => [{}]) do |request|
          HeatPumps::Reads.all(request, kind.id, :extra => HeatPumpReads.extra(request, kind.id))
        end
        feature.snapshot_section(prefix, :query => "#{prefix}.all")
      end

      def install_create_and_update(feature, kind)
        prefix = PREFIXES.fetch(kind.id)
        preconditions = ["Its name, trimmed and in any case, is not another #{kind.label}'s."]
        PARENTS.fetch(kind.id, []).each { |key| preconditions << "The record #{key} names exists." }
        feature.action("#{prefix}.create",
                       :description => "Create one #{kind.label}. #{DESCRIPTIONS.fetch(kind.id)}",
                       :refuses => CREATE, :params => create_params(kind), :result => Shapes::RESULT,
                       :undo_name => "Create #{kind.label}", :preconditions => preconditions,
                       :side_effects => "Creates one Model-owned definition.",
                       :examples => [CREATE_EXAMPLES.fetch(kind.id)]) do |request, proposal|
          HeatPumps::Operations.create(request, proposal, kind.id, :values => request.params.fetch("values"),
                                                                   :user_data => request.params["user_data"])
        end
        feature.action("#{prefix}.update",
                       :description => "Edit guarded values of one #{kind.label}; a changed expected value refuses " \
                                       "and writes nothing.#{update_detail(kind)}",
                       :refuses => EDIT, :params => Shapes.update(kind), :result => Shapes::RESULT,
                       :undo_name => "Edit #{kind.label}",
                       :preconditions => ["The #{kind.label} exists and is readable.",
                                          "A new name is not another #{kind.label}'s."],
                       :side_effects => "Updates one definition and preserves its metadata.",
                       :examples => [{ "id" => Shapes.example_id(kind) }
                                       .merge(UPDATE_EXAMPLES.fetch(kind.id))]) do |request, proposal|
          params = request.params
          HeatPumps::Operations.update(request, proposal, kind.id, :id => params.fetch("id"),
                                                                   :values => params.fetch("values"),
                                                                   :expected_values => params.fetch("expected_values"))
        end
      end

      # A unit names its models (and an indoor unit its outdoor unit) when it is created.
      def create_params(kind)
        params = Shapes.create(kind)
        parents = PARENTS.fetch(kind.id, [])
        return params if parents.empty?

        values = params.fetch("properties").fetch("values")
        params.merge("properties" => params.fetch("properties").merge(
          "values" => values.merge("required" => values.fetch("required") + parents)
        ))
      end

      def update_detail(kind)
        return "" unless kind == OUTDOOR_EQUIPMENT

        " Each rating mode reads only its own values; the other mode's stay stored and are read again when the " \
          "mode is switched back."
      end

      def install_duplicate(feature, kind)
        feature.action("#{PREFIXES.fetch(kind.id)}.duplicate",
                       :description => "Duplicate one #{kind.label} with a new id and source derived.",
                       :refuses => DUPLICATE, :params => Shapes.duplicate(kind), :result => Shapes::RESULT,
                       :undo_name => "Duplicate #{kind.label}", :preconditions => ["The #{kind.label} exists and is " \
                                                                                   "readable."],
                       :side_effects => "Creates one definition; user_data is copied.",
                       :examples => [{ "id" => Shapes.example_id(kind) }]) do |request, proposal|
          HeatPumps::Operations.duplicate(request, proposal, kind.id, :id => request.params.fetch("id"),
                                                                      :name => request.params["name"])
        end
      end

      # What names each kind, for its delete's description.
      def named_by(kind)
        case kind
        when OUTDOOR_EQUIPMENT then "an outdoor unit installs it"
        when INDOOR_EQUIPMENT then "an outdoor model pairs with it or an indoor unit installs it"
        when OUTDOOR_UNITS then "an indoor unit names it"
        else "a Zone names it"
        end
      end

      def install_delete(feature, kind)
        params = Shapes.delete(kind).then do |schema|
          schema["properties"]["replacement_id"] =
            Shapes.id(kind.id_prefix, "The #{kind.label} that takes this one's place on every record and Zone " \
                                      "naming it, or null to empty what may be empty.", :nullable => true)
          schema
        end
        feature.action("#{PREFIXES.fetch(kind.id)}.delete",
                       :description => "Delete one #{kind.label}. While #{named_by(kind)}, name a replacement_id, " \
                                       "which takes its place; null empties an outdoor model's pairing or a Zone's " \
                                       "indoor units, and a unit still naming it refuses. Without one it refuses " \
                                       "as reference.in_use.",
                       :refuses => DELETE, :params => params,
                       :result => Shapes.with_removed_user_data(Shapes::RESULT),
                       :participants => [Serves::State::STAGE], :undo_name => "Delete #{kind.label}",
                       :preconditions => ["The #{kind.label} exists and is readable."],
                       :side_effects => "Deletes one definition and its metadata, and rewrites the records and " \
                                        "Zones that name it; Undo restores all of them.",
                       :examples => [{ "id" => Shapes.example_id(kind) },
                                     { "id" => Shapes.example_id(kind),
                                       "replacement_id" => "#{kind.id_prefix}_Zy98Xw76Vu54" }]) do |request, proposal|
          params = request.params
          id = params.fetch("id")
          expected = params.fetch("expected_values", {})
          replacement = params.fetch("replacement_id", Serves::Operations::KEEP)
          Serves::Operations.delete(request, proposal, kind.id, :id => id, :expected_values => expected,
                                                                :replacement => replacement) do |plan|
            unless replacement == Serves::Operations::KEEP
              HeatPumps::Operations.move_referrers(request, proposal, kind.id, :from => id, :to => replacement)
            end
            HeatPumps::Operations.delete(request, proposal, kind.id, :id => id, :expected_values => expected,
                                                                     :reference_plan => plan)
          end
        end
      end

      def install_blended(feature)
        feature.query(BLENDED, :description => "The blended air-source heat pump of each exported Building Segment, " \
                                               "read-only, in the Phius Heat Pump Performance Estimator's sections " \
                                               "(v25.1.2), from the outdoor models whose outdoor units have indoor " \
                                               "units serving the Segment's Zones; with the climate it reads and " \
                                               "every heat pump finding. Fans and pumps are left out.",
                               :refuses => READ, :params => Shapes::NONE, :result => BLENDED_RESULT,
                               :examples => [{}]) { |request| HeatPumpReads.blended(request) }
        feature.snapshot_section(BLENDED_SECTION, :query => BLENDED)
      end
    end
  end
end
