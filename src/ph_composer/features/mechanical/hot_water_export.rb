# frozen_string_literal: true

module PhComposer
  module Mechanical
    # The hot water export (context/CONTRACTS.md, "Mechanical equipment"): one record per (Hot Water System, exported
    # Zone) pair, as HotWaterPlan works it out, for the Python section that sets each served Room's hot water system
    # (python/ph_composer_translation/mechanical_sections.py). The Serves payload is claimed once, by the Ventilator
    # export, whose projection gives every Zone with its slots; this section requires that one and reads it. It reads
    # each Heater and Tank with its `user_data`, which their honeybee-ph objects carry, and each System without, since
    # honeybee-ph's PhHotWaterSystem has none: a System's map is left out with export.metadata_omitted.
    #
    # The preflight's hot water rows come from the same plan (`preflight_rows`).
    module HotWaterExport
      SECTION = "#{FEATURE_ID}.export.hot_water"
      ZONES = Zones::ExportProjection::SECTION
      KINDS = [HOT_WATER_SYSTEM_KIND, HOT_WATER_HEATER_KIND, HOT_WATER_TANK_KIND].freeze
      # Each slot's identifier and capacity: what conformance reads back per slot.
      SLOT_FIELDS = HotWater::Slotting::SLOTS.flat_map { |slot| ["#{slot}_identifier", "#{slot}_capacity_l"] }.freeze
      # One result row per pair: what conformance reads back. `digest` is the SHA-256 of the system's honeybee-ph
      # dictionary as translated, which conformance compares with each reloaded Room's own. The Python section's test
      # holds its rows to these keys (tests/fixtures/mechanical/result_fields.json).
      ROW_FIELDS = (%w[id item_id zone_id zone_name display_name system_identifier number_tap_points
                       heater_identifiers] + SLOT_FIELDS + %w[digest]).freeze
      RESULT_FIELDS = { "hot_water" => ROW_FIELDS }.freeze
      RESULT = RESULT_FIELDS.transform_values { |keys| [PhComposer::Export::Privacy.fields(keys)] }.freeze
      # Findings about a Zone the export writes as it is, which the preflight alone reports.
      PREFLIGHT_ONLY = [Codes::ZONE_NO_HOT_WATER].freeze

      module_function

      def install(feature)
        feature.export_contributor(SECTION, :section_version => 1, :requires => [ZONES, VentilationExport::SECTION],
                                            :result => RESULT) { |reader| records(reader) }
      end

      # The pairs, once the plan finds nothing blocking; every other finding but the preflight's own is a note.
      def records(reader)
        systems = reader.records(HOT_WATER_SYSTEM_KIND).to_h { |row| [row.fetch("id"), row] }
        plan = HotWaterPlan.call(:zones => reader.section(VentilationExport::SECTION), :systems => systems,
                                 :heaters => reader.records(HOT_WATER_HEATER_KIND, :user_data => true),
                                 :tanks => reader.records(HOT_WATER_TANK_KIND, :user_data => true))
        VentilationExport.raise_blocking!(plan.findings)
        plan.findings.reject { |finding| PREFLIGHT_ONLY.include?(finding.code) }.each do |finding|
          reader.note(finding.code, finding.record_id, finding.message)
        end
        plan.pairs
      end

      # The preflight's hot water rows: a blocking row for each unreadable hot water record and each metadata
      # problem the export refuses (a reserved `user_data` key, an extension payload it cannot leave out), then the
      # plan's findings over the live Model, each with the code and object the export notes. `zones` are the live
      # ExportZones and `references` each Zone's occurrence reference by id.
      def preflight_rows(request, zones, references)
        engine = request.engine
        read = KINDS.to_h { |kind| [kind, DefinitionLists.read(engine, kind, engine.ids(kind).sort)] }
        rows = read.values.flat_map do |_records, unreadable|
          unreadable.map do |row|
            Preflight.row(row.fetch("code"), SECTION, row.fetch("id"), row.fetch("message"), true)
          end
        end
        systems, unreadable = read.fetch(HOT_WATER_SYSTEM_KIND)
        members = read.fetch(HOT_WATER_HEATER_KIND).first + read.fetch(HOT_WATER_TANK_KIND).first
        rows.concat(Export::MetadataCheck.findings(request, systems, :section => SECTION))
        rows.concat(Export::MetadataCheck.findings(request, members, :section => SECTION, :user_data => true))
        plan = HotWaterPlan.call(:zones => zones, :systems => systems.to_h { |record| [record.fetch("id"), record] },
                                 :heaters => read.fetch(HOT_WATER_HEATER_KIND).first,
                                 :tanks => read.fetch(HOT_WATER_TANK_KIND).first,
                                 :unreadable => unreadable.map { |row| row.fetch("id") })
        rows + plan.findings.map do |found|
          Preflight.row(found.code, SECTION, found.record_id, found.message, found.blocks,
                        Preflight.zone_locate(found.record_id, references))
        end
      end
    end
  end
end
