# frozen_string_literal: true

module PhComposer
  module Programs
    # The Program export (context/CONTRACTS.md, "Program export"): four sections, all worked out once from the
    # snapshot by ExportPlan, for the Python sections that build the honeybee objects
    # (python/ph_composer_translation/program_sections.py).
    #
    #   export.rooms           one record per exported Zone: its ProgramType, its People extension's counts and
    #                          Dwelling, and its Equipment Set devices. It claims the two occupancy extensions and
    #                          registers the plan as its projection, which the other three read.
    #   export.schedules       every Schedule the ProgramTypes use, as RulesetExport writes it
    #   export.program_types   one per Program, or per Program and Dwelling where a Phius rule applies
    #   export.set_points      one per exported Building Segment: its set points, and its Dwellings for the report
    #
    # A blocking finding stops the export with its code; every other finding is a note. `ProgramPreflight` reads the
    # same findings live.
    module ProgramExport
      ROOMS = "#{FEATURE_ID}.export.rooms"
      SCHEDULES = "#{FEATURE_ID}.export.schedules"
      PROGRAM_TYPES = "#{FEATURE_ID}.export.program_types"
      SET_POINTS = "#{FEATURE_ID}.export.set_points"
      SECTIONS = [ROOMS, SCHEDULES, PROGRAM_TYPES, SET_POINTS].freeze
      ZONES = Zones::ExportProjection::SECTION
      FACES = Zones::Faces::ExportProjection::SECTION
      SPACES = Spaces::ExportProjection::SECTION
      CERTIFICATION = Certification::SegmentExport::SECTION
      CLAIMS = [
        { "namespace" => Occupancy::ZONE_NAMESPACE, "target_kind" => Zones::REFERENCE_KIND,
          "source_section" => ZONES, "fields" => Occupancy::ZONE_FIELDS },
        { "namespace" => Occupancy::SEGMENT_NAMESPACE, "target_kind" => Occupancy::SEGMENT_KIND,
          "source_section" => ZONES, "fields" => Occupancy::SEGMENT_FIELDS }
      ].freeze
      # The rows each section's Python half adds to the result, by section and field: what conformance reads back
      # and, for the set points, what the report shows. The Python tests hold their rows to these keys.
      RESULT_FIELDS = {
        ROOMS => { "rooms" => %w[zone_id program_type_id number_bedrooms number_people dwelling_identifier
                                 num_dwellings device_count] },
        SCHEDULES => { "schedules" => %w[id days_per_week weeks_per_year period_count] },
        PROGRAM_TYPES => { "program_types" => %w[id people_per_area lighting_watts_per_area] },
        SET_POINTS => { "set_points" => %w[export_identifier name winter_c summer_c],
                        "dwellings" => %w[export_identifier name units bedrooms occupants] }
      }.transform_values { |fields| fields.transform_values(&:freeze).freeze }.freeze
      ROOMS_RESULT, SCHEDULES_RESULT, PROGRAM_TYPES_RESULT, SET_POINTS_RESULT = RESULT_FIELDS.values.map do |fields|
        fields.transform_values { |keys| [PhComposer::Export::Privacy.fields(keys)] }.freeze
      end
      TEXT_LEFT_OUT = "programs.text_left_out"
      # A blocked export names this many of its reasons, and counts the rest.
      BLOCKING_SHOWN = 3

      module_function

      def install(feature)
        feature.export_contributor(ROOMS, :section_version => 1, :requires => [ZONES, FACES, SPACES, CERTIFICATION],
                                          :result => ROOMS_RESULT, :preflight => ProgramPreflight::NAME,
                                          :entity_projections => CLAIMS,
                                          :projection => method(:plan)) { |reader| plan(reader).rooms }
        feature.export_contributor(SCHEDULES, :section_version => 1, :requires => [ROOMS],
                                              :result => SCHEDULES_RESULT) do |reader|
          reader.section(ROOMS).schedules
        end
        feature.export_contributor(PROGRAM_TYPES, :section_version => 1, :requires => [ROOMS],
                                                  :result => PROGRAM_TYPES_RESULT) do |reader|
          reader.section(ROOMS).program_types
        end
        feature.export_contributor(SET_POINTS, :section_version => 1, :requires => [ROOMS],
                                               :result => SET_POINTS_RESULT,
                                               :report => ProgramReport.method(:call)) do |reader|
          reader.section(ROOMS).segments
        end
      end

      # The plan, once per export, read inside the rooms section: it stops the export on a blocking finding and
      # notes every other one.
      def plan(reader)
        reader.projection(:programs_export_plan) do
          input = input(reader)
          findings = ExportPlan.findings(input)
          blocking = findings.select(&:blocks)
          unless blocking.empty?
            messages = blocking.map { |finding| safe(finding.message) }.uniq
            more = messages.length > BLOCKING_SHOWN ? " And #{messages.length - BLOCKING_SHOWN} more." : ""
            raise PhComposer::Export::Blocked.new(blocking.first.code,
                                                  messages.first(BLOCKING_SHOWN).join(" ") + more)
          end

          findings.each { |finding| reader.note(finding.code, finding.record_id, safe(finding.message)) }
          ExportPlan.call(input, :text => TEXT)
        end
      end

      # A finding's message as the export notes it: one that would carry a local file path into the result, which the
      # export refuses, says so instead.
      def safe(message)
        Diagnostics.absolute_path?(message) ? ProgramPreflight::PATH_LEFT_OUT : message
      end

      # A name or comment that reads as a local file path stays in the Model, since the export refuses one in the
      # HBJSON or its result: `fallback` takes its place. ExportPlan's `programs.text_left_out` findings note each.
      TEXT = ->(value, fallback) { Diagnostics.absolute_path?(value.to_s.strip) ? fallback : value }

      # ---------------------------------------------------------------- the snapshot

      # ExportPlan's input from the snapshot: the exported Zones with their assignments, their Segments with
      # their occupancy settings and Phius category, every Dwelling, the Programs, Schedules and Equipment Sets
      # with PH-Composer's unwritten defaults, and each Zone's areas.
      def input(reader)
        zones = reader.section(ZONES).select { |row| row.fetch("exported") }.uniq { |row| row.fetch("zone_id") }
        state = OccupancyState::State.new(:zones => zones(reader, zones), :segments => segments(reader, zones),
                                          :dwellings => values(reader, DWELLING_KIND))
        identifiers = zones.select { |row| row.fetch("building_segment_id") }.to_h do |row|
          [row.fetch("building_segment_id"), row.fetch("building_segment_export_identifier")]
        end
        ExportPlan::Input.new(:state => state, :catalog => catalog(reader), :areas => areas(reader, zones),
                              :export_identifiers => identifiers)
      end

      def zones(reader, rows)
        assignments = reader.entity_projection(Occupancy::ZONE_NAMESPACE, Zones::REFERENCE_KIND)
                            .sort_by { |row| row.fetch("path") || [] }.uniq { |row| row.fetch("id") }
                            .to_h { |row| [row.fetch("id"), row.fetch("payload")] }
        rows.map do |row|
          id = row.fetch("zone_id")
          OccupancyState::Zone.new(:id => id, :reference => { "zone_id" => id, "zone_path" => row.fetch("zone_path") },
                                   :name => row.fetch("name"), :segment_id => row.fetch("building_segment_id"),
                                   :assignment => assignments.fetch(id) { Occupancy::UNASSIGNED.dup })
        end
      end

      def segments(reader, rows)
        payloads = reader.entity_projection(Occupancy::SEGMENT_NAMESPACE, Occupancy::SEGMENT_KIND)
                         .to_h { |row| [row.fetch("id"), row.fetch("payload")] }
        categories = reader.section(CERTIFICATION).to_h { |row| [row.fetch("id"), row.fetch("category")] }
        rows.select { |row| row.fetch("building_segment_id") }.uniq { |row| row.fetch("building_segment_id") }
            .map do |row|
          id = row.fetch("building_segment_id")
          OccupancyState::Segment.new(:id => id, :name => row.fetch("building_segment"),
                                      :category => categories.fetch(id, Certification::Segment::DEFAULTS["category"]),
                                      :settings => payloads.fetch(id) { Occupancy::SEGMENT_DEFAULTS.dup },
                                      :stored => payloads.key?(id))
        end
      end

      # The stored records of `kind` as their values with id, in id order.
      def values(reader, kind)
        reader.records(kind).map { |row| row.reject { |key, _| key == "extensions" } }
      end

      def catalog(reader)
        stored = stored_settings(reader)
        records = Store::KINDS.keys.to_h { |kind| [kind, values(reader, kind)] }
        ids = records.transform_values { |rows| rows.map { |row| row.fetch("id") } }
        by_id = lambda do |kind|
          (records.fetch(kind) + Store.frozen(stored, kind, ids)).to_h { |row| [row.fetch("id"), row] }
        end
        defaults = Settings::FIELDS.to_h { |key, (_kind, reserved)| [key, stored[key] || reserved] }
        ExportPlan::Catalog.new(:programs => by_id.call(PROGRAM_KIND), :schedules => by_id.call(SCHEDULE_KIND),
                                :equipment_sets => by_id.call(EQUIPMENT_SET_KIND),
                                :default_program_id => defaults.fetch("default_program_id"),
                                :default_equipment_set_id => defaults.fetch("default_equipment_set_id"))
      end

      # The Model's stored defaults (Settings.stored), from the snapshot.
      def stored_settings(reader)
        store = Settings::SERVICE.store
        text = reader.snapshot.model_dictionaries.fetch(store.dictionary, {})[store.key]
        Settings::SERVICE.validate!(Settings::SERVICE.effective(text.nil? ? nil : JSON.parse(text)))
      rescue JSON::ParserError, CodedError
        raise PhComposer::Export::Blocked.new("record.unreadable", "The Programs settings cannot be read, so the " \
                                                                   "Model cannot be exported. Nothing was written.")
      end

      # Each exported Zone's Space totals and its Room's Floor Face area.
      def areas(reader, rows)
        spaces = reader.section(SPACES).to_h { |row| [row.fetch("zone_id"), row] }
        rows.to_h do |row|
          id = row.fetch("zone_id")
          totals = spaces.fetch(id, {})
          entry = Zones::ExportProjection.zone_entry(reader, id).first
          [id, ExportPlan::Area.new(:floor_area_m2 => totals.fetch("floor_area_m2", 0.0),
                                    :icfa_m2 => totals.fetch("weighted_area_m2", 0.0),
                                    :room_floor_area_m2 => Zones::Faces::ExportProjection.floor_area_m2(reader,
                                                                                                        entry))]
        end
      end
    end
  end
end
