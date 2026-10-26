# frozen_string_literal: true

require_relative "export_assessment"

module PhComposer
  module Windows
    # Both sections consume one cached detached assessment. The preflight captures once and uses
    # that same projection; export never performs another native walk or repairs authored records.
    module ExportProjection
      CONSTRUCTIONS = "#{FEATURE_ID}.export.window_constructions"
      APERTURES = "#{FEATURE_ID}.export.apertures"
      PREFLIGHT = "#{FEATURE_ID}.export_preflight"
      # The Zones Faces section, whose registered projection gives each Face's host context.
      FACES = "ph_composer.zones.faces.export.faces"

      module_function

      def install(feature)
        feature.query(PREFLIGHT, :description => "Placed Window geometry, hosts and thermal readiness for export.",
                                 :refuses => [],
                                 :params => Shapes::NONE, :result => Export::PREFLIGHT_RESULT,
                                 :examples => [{}]) { |request| preflight(request) }
        # Both sections read one assessment, which places each Unit on its host Face.
        feature.export_contributor(CONSTRUCTIONS, :section_version => 1, :requires => [FACES]) do |reader|
          ready(reader).constructions
        end
        feature.export_contributor(APERTURES,
                                   :section_version => 1, :preflight => PREFLIGHT, :requires => [FACES],
                                   :result => {
                                     "window_usage" => [Export::Privacy.fields(%w[type_id type_name zone_id unit_count
                                                                                  aperture_count
                                                                                  install_names])],
                                     "window_schema_exceptions" => [Export::Privacy.fields(%w[
                                       construction_id g_value
                                     ])],
                                     "window_face_areas" => [Export::Privacy.fields(%w[face_id zone_id gross_area_m2
                                                                                       glazed_area_m2
                                                                                       net_area_m2])]
                                   }, :report => method(:report),
                                   :projection => method(:outlines)) { |reader| apertures(reader) }
      end

      def assess(**values)
        ExportAssessment.call(**values)
      end

      # Computed once, as the Apertures section whichever section asks first, so what it reads (Unit
      # user_data counted among them) is reported under Apertures.
      def projection(reader)
        reader.projection(APERTURES) { reader.within(APERTURES) { assessment(reader) } }
      end

      # The Apertures section's registered projection: each Unit's world outline in metres as
      # `{unit_id, entity_path, outline_m}`, from the assessment's own placement of it, for a contributor that
      # needs to know where Windows sit (`reader.section(APERTURES)`). A Unit whose Type cannot be placed has
      # no outline.
      def outlines(reader)
        DeepCopy.call(projection(reader).outlines)
      end

      def assessment(reader)
        types = reader.records(TYPE_KIND).to_h { |row| [row.fetch("id"), row] }
        products = Products::KINDS.to_h do |collection, kind|
          [collection, reader.records(kind.id).to_h { |row| [row.fetch("id"), row] }]
        end
        settings = ExportGeometry.record(reader.snapshot.model_dictionaries, Settings::SERVICE.store) ||
                   DeepCopy.call(Settings::DEFAULTS)
        Settings::SERVICE.validate!(settings)
        reader.snapshot.records(Units::STORE.dictionary).each do |_entry, record|
          Units.validate!(record)
          reader.entity_record(record, :fields => %w[window_type_id anchor], :target_kind => Units::REFERENCE_KIND,
                                       :user_data => true)
        end
        assess(:snapshot => reader.snapshot, :types => types, :products => products, :settings => settings,
               :faces => reader.section(FACES))
      end

      # The Apertures contract is the Units' owning section, so claimed Unit data is captured here, once,
      # and never by the assessment both sections share.
      def apertures(reader)
        result = ready(reader).apertures
        reader.snapshot.records(Units::STORE.dictionary).each do |entry, record|
          reader.capture_entity(record, :target_kind => Units::REFERENCE_KIND, :path => entry.path)
        end
        result
      end

      def ready(reader)
        result = projection(reader)
        blocking = result.findings.find { |row| row.fetch("blocks_export") }
        if blocking
          raise Export::Blocked.new(blocking.fetch("code"), blocking.fetch("message"), "section" => APERTURES)
        end

        result
      end

      def preflight(request)
        snapshot = Export::GeometrySnapshot.capture(request.model, :revision => request.session.revision)
        records = Export::RecordReader.new(request.engine, request.registry.catalog,
                                           :claims => Export::Collection.claims(request.registry),
                                           :reserved => Export::Collection.reserved(request.registry))
        reader = Export::SnapshotReader.new(records, snapshot, :registry => request.registry)
        result = reader.within(APERTURES) { projection(reader) }
        { "findings" => result.findings, "repairs" => result.repairs.uniq { |row| row.fetch("id") } }
      rescue CodedError => error
        { "findings" => [{ "code" => error.code, "section" => APERTURES, "object_id" => nil,
                           "message" => error.message, "blocks_export" => true }], "repairs" => [] }
      end

      def report(result, display_units)
        usage = result.fetch("window_usage", [])
        return [] if usage.empty?

        rows = usage.map do |row|
          [row.fetch("type_name"), row.fetch("zone_id"), row.fetch("unit_count"), row.fetch("aperture_count"),
           row.fetch("install_names").join(", ")]
        end
        html = Export::ReportHtml.table(["Window Type", "Zone", "Units", "Apertures", "Psi-Install Types"], rows)
        areas = result.fetch("window_face_areas", []).map do |row|
          values = %w[gross_area_m2 glazed_area_m2 net_area_m2].map do |key|
            format("%.2f", PhComposer::Units.to_display(row.fetch(key), :quantity => "area", :system => display_units))
          end
          [row.fetch("face_id"), *values]
        end
        unit = PhComposer::Units.label(:quantity => "area", :system => display_units)
        html += Export::ReportHtml.table(["Host Face", "Gross area (#{unit})", "Glazed area (#{unit})",
                                          "Net opaque area (#{unit})"], areas)
        html += Export::ReportHtml.paragraph(
          "PH-Composer authors no Window shading factors. Honeybee serializes its own shading defaults. " \
          "Psi-install values are carried on the construction Frames; Aperture install types remain empty."
        )
        result.fetch("window_schema_exceptions", []).each do |row|
          html += Export::ReportHtml.paragraph(
            "#{row.fetch('construction_id')}: authored g-value #{row.fetch('g_value')} is retained exactly; " \
            "Honeybee's simple glazing schema normally requires a value strictly between 0 and 1."
          )
        end
        [Export::ReportHtml.section("Windows", html)]
      end
    end
  end
end
