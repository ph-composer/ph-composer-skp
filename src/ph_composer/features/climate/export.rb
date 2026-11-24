# frozen_string_literal: true

module PhComposer
  module Climate
    # The Site export section (context/CONTRACTS.md, "Translation sections and artifacts"): one record, always,
    # read from the export snapshot and never the live Model, for the Python section that sets one honeybee-ph
    # Site on every Building Segment (python/ph_composer_translation/site_sections.py). SiteRecord decides what
    # the record carries and which findings go with it; the preflight reads the same findings live. Every
    # finding is non-blocking: a Model exports without a climate, as it always has.
    module SiteExport
      SECTION = "#{FEATURE_ID}.export.site"
      PREFLIGHT = "#{FEATURE_ID}.export_preflight"
      ZONES = "ph_composer.zones.export.zones"
      LOCATION_FIELDS = %w[latitude_deg longitude_deg elevation_m climate_zone hours_from_utc].freeze
      IDENTITY_FIELDS = %w[name origin dataset_name station_name state source_type wind_speed_m_s].freeze
      CASE_FIELDS = %w[heat_1 heat_2 cool_1 cool_2].freeze
      LIMIT_FIELDS = %w[verdict reason distance_km elevation_difference_m distance_ok elevation_ok].freeze
      CELL_FIELDS = %w[row column value as_read].freeze
      Optional = PhComposer::Export::Privacy::Optional
      # What the Python section adds to the result for the report: the record's report block as Ruby wrote it,
      # what was written, and how many Building Segments carry it. `site_digest` lets conformance compare every
      # reloaded Building Segment's Site with the one built. Nothing here is named or holds a path.
      RESULT = {
        "location" => Optional.new(PhComposer::Export::Privacy.fields(LOCATION_FIELDS)),
        "climate" => Optional.new(PhComposer::Export::Privacy.fields(IDENTITY_FIELDS)),
        "climate_written" => nil, "climate_left_out" => nil, "missing_values" => nil,
        "peak_load_temperatures_c" => Optional.new(PhComposer::Export::Privacy.fields(CASE_FIELDS)),
        "limit_check" => Optional.new(PhComposer::Export::Privacy.fields(LIMIT_FIELDS)),
        "edited_cells" => [PhComposer::Export::Privacy.fields(CELL_FIELDS)],
        "design_temperatures" => PhComposer::Export::Privacy.fields(%w[heating_99_c cooling_1_c]),
        "design_temperature_source" => nil, "building_segments" => nil, "site_digest" => nil
      }.freeze

      module_function

      def install(feature)
        feature.export_contributor(SECTION, :section_version => 1, :preflight => PREFLIGHT, :requires => [ZONES],
                                            :result => RESULT, :report => SiteReport.method(:call),
                                            :projection => method(:readings)) do |reader|
          records(reader)
        end
        feature.query(PREFLIGHT, :description => "Climate export checks: what the Site section writes as unset, " \
                                                 "and a climate it leaves out and why. None blocks the export.",
                                 :refuses => %w[record.unreadable], :params => SchemaShapes.object({}),
                                 :result => PhComposer::Export::PREFLIGHT_RESULT, :examples => [{}]) do |request|
          preflight(request)
        end
      end

      # The one record, with each finding as a note on it. The climate record passes the metadata boundary like
      # any record, so its user_data stays in the Model with a finding.
      def records(reader)
        snapshot = reader.snapshot
        site = snapshot_settings(snapshot, Settings::SITE)
        design = snapshot_settings(snapshot, Settings::DESIGN_TEMPERATURES)
        stored = reader.records(Schema::KIND_ID).first
        climate = stored && Schema::KIND.values(stored)
        SiteRecord.findings(site, climate).each { |code, message| reader.note(code, SiteRecord::ID, message) }
        [SiteRecord.call(site, design, climate)]
      end

      # What another feature's export section reads of the climate, through `reader.section` (CONTRACTS section 9,
      # "What other features read"): the monthly mean air temperatures and the two design temperatures, as stored
      # and in C, each null when not entered. The blended heat pump reads them.
      def readings(reader)
        design = snapshot_settings(reader.snapshot, Settings::DESIGN_TEMPERATURES)
        stored = reader.records(Schema::KIND_ID).first
        monthly = stored && Schema::KIND.values(stored).dig("monthly", "air_c")
        { "monthly_air_c" => monthly && DeepCopy.call(monthly), "heating_99_c" => design.fetch("heating_99_c"),
          "cooling_1_c" => design.fetch("cooling_1_c") }
      end

      def snapshot_settings(snapshot, settings)
        text = snapshot.model_dictionaries.fetch(settings.store.dictionary, {})[settings.store.key]
        settings.validate!(settings.effective(text.nil? ? nil : JSON.parse(text)))
      rescue JSON::ParserError, CodedError
        raise PhComposer::Export::Blocked.new("record.unreadable", "#{settings.label} settings cannot be read, so " \
                                                                   "the Model cannot be exported. Nothing was " \
                                                                   "written.")
      end

      # The same findings, read live, each about the Site record and none blocking; a settings dictionary the
      # export could not read is the one blocking row, as it blocks the export.
      def preflight(request)
        site = Settings::SITE.read(request.model)
        Settings::DESIGN_TEMPERATURES.read(request.model) # the export reads it too, and refuses it unreadable
        stored = Operations.stored(request.engine)
        climate = stored && Schema::KIND.values(stored)
        findings = SiteRecord.findings(site, climate).map do |code, message|
          { "code" => code, "section" => SECTION, "object_id" => SiteRecord::ID, "message" => message,
            "blocks_export" => false }
        end
        { "findings" => findings, "repairs" => [] }
      rescue CodedError => error
        { "findings" => [{ "code" => error.code, "section" => SECTION, "object_id" => SiteRecord::ID,
                           "message" => error.message, "blocks_export" => true }], "repairs" => [] }
      end
    end
  end
end
