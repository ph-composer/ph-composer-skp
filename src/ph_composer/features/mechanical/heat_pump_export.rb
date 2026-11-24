# frozen_string_literal: true

module PhComposer
  module Mechanical
    # The heat pump export (context/CONTRACTS.md, "Mechanical equipment"): one record per (Building Segment's blended
    # heat pump, served Zone) pair, as HeatPumpPlan works it out, for the Python section that adds the heat pump to
    # each served Room (python/ph_composer_translation/mechanical_sections.py). It reads the Zones with their slots
    # from the Ventilator export, which claims the Serves payload for the feature, and the climate from Climate's
    # Site export, which other features read through its projection (Climate CONTRACTS section 9).
    #
    # The blend is one object built from several records, so none of their `user_data` has an object of its own:
    # each map is left out with export.metadata_omitted.
    #
    # The preflight's heat pump rows come from the same plan (`preflight_rows`). Its projection is each exported
    # blend's Building Segment and whether it cools, which the Segment settings section compares with the Segment's
    # mechanical cooling switch (SegmentExport).
    module HeatPumpExport
      SECTION = "#{FEATURE_ID}.export.heat_pumps"
      ZONES = Zones::ExportProjection::SECTION
      CLIMATE = Climate::SiteExport::SECTION
      # The kinds the plan reads; an indoor model carries nothing the blend reads.
      KINDS = [HP_OUTDOOR_EQUIPMENT_KIND, HP_OUTDOOR_UNIT_KIND, HP_INDOOR_UNIT_KIND].freeze
      # One result row per pair: what conformance reads back. `digest` is the SHA-256 of the heat pump's honeybee-ph
      # dictionary as translated, which conformance compares with each reloaded Room's own. The Python section's
      # test holds its rows to these keys (tests/fixtures/mechanical/heat_pump_result_fields.json).
      ROW_FIELDS = %w[id zone_id zone_name segment display_name system_identifier cop_1 cop_2 cooling_used
                      capacity_kw flow_rate_m3_hr annual_cop digest].freeze
      RESULT_FIELDS = { "heat_pumps" => ROW_FIELDS }.freeze
      RESULT = RESULT_FIELDS.transform_values { |keys| [PhComposer::Export::Privacy.fields(keys)] }.freeze

      module_function

      def install(feature)
        feature.export_contributor(SECTION, :section_version => 1,
                                            :requires => [ZONES, VentilationExport::SECTION, CLIMATE],
                                            :result => RESULT, :projection => method(:cooling)) do |reader|
          records(reader)
        end
      end

      # The pairs, once the plan finds nothing blocking; every other finding is a note.
      def records(reader)
        found = plan(reader)
        VentilationExport.raise_blocking!(found.findings)
        found.findings.each { |finding| reader.note(finding.code, finding.record_id, finding.message) }
        found.pairs
      end

      # Each exported blend's Building Segment, by name as the plan keys it, and whether the blend cools.
      def cooling(reader)
        plan(reader).blends.map do |blend|
          { "segment" => blend.fetch("segment"),
            "cooling" => blend.fetch("result").fetch("export").fetch("cooling").fetch("used") }
        end
      end

      # The plan over the export's snapshot, worked out once per export for the records and the projection.
      def plan(reader)
        reader.projection([:mechanical_heat_pump_plan]) do
          by_id = ->(kind) { reader.records(kind).to_h { |row| [row.fetch("id"), row] } }
          climate = reader.section(CLIMATE)
          HeatPumpPlan.call(:zones => reader.section(VentilationExport::SECTION),
                            :outdoor_equipment => by_id.call(HP_OUTDOOR_EQUIPMENT_KIND),
                            :outdoor_units => by_id.call(HP_OUTDOOR_UNIT_KIND),
                            :indoor_units => by_id.call(HP_INDOOR_UNIT_KIND),
                            :climate => HeatPumpPlan.climate(*climate.values_at("monthly_air_c", "heating_99_c",
                                                                                "cooling_1_c")))
        end
      end

      # The preflight's heat pump rows: a blocking row for each unreadable heat pump record and each metadata
      # problem the export refuses (an extension payload it cannot leave out), then the plan's findings over the live
      # Model, each with the code and object the export notes. `zones` are the live ExportZones and `references`
      # each Zone's occurrence reference by id.
      def preflight_rows(request, zones, references)
        engine = request.engine
        rows = []
        records = KINDS.flat_map do |kind|
          readable, unreadable = DefinitionLists.read(engine, kind, engine.ids(kind).sort)
          rows.concat(unreadable.map do |row|
            Preflight.row(row.fetch("code"), SECTION, row.fetch("id"), row.fetch("message"), true)
          end)
          readable
        end
        rows.concat(Export::MetadataCheck.findings(request, records, :section => SECTION))
        rows + live_plan(request, zones).findings.map do |found|
          Preflight.row(found.code, SECTION, found.record_id, found.message, found.blocks,
                        Locate.row_locate(found.record_id, references))
        end
      end

      # The plan over the live Model, worked out once per request: the preflight's heat pump rows and its Segment
      # settings rows read the same blends.
      def live_plan(request, zones)
        request.memo([:mechanical_heat_pump_plan, zones.map(&:id)]) do
          HeatPumpPlan.call(**HeatPumpReads.plan_args(HeatPumpReads.inputs(request, :zones => zones)))
        end
      end
    end
  end
end
