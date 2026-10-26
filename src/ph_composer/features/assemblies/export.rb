# frozen_string_literal: true

module PhComposer
  module Assemblies
    # The conversion allowlist is narrower than authored values. Each Assembly is a self-contained
    # translation record; the Section contract can therefore refuse it without shared mutable state.
    module ExportProjection
      SECTION = "ph_composer.assemblies.export.constructions"
      MATERIAL_FIELDS = %w[id name category conductivity_w_mk density_kg_m3 specific_heat_j_kgk emissivity color].freeze
      SEGMENT_FIELDS = %w[id width_mm material_id steel_stud_spacing_mm].freeze

      module_function

      def install(feature)
        feature.query("#{FEATURE_ID}.export_preflight",
                      :description => "Material and Assembly export conditions.",
                      :refuses => [],
                      :params => { "type" => "object", "properties" => {}, "additionalProperties" => false },
                      :result => Export::PREFLIGHT_RESULT, :examples => [{}]) { |request| preflight(request) }
        feature.export_contributor(SECTION,
                                   :section_version => 1, :preflight => "#{FEATURE_ID}.export_preflight",
                                   :user_data_keys => %w[ph_composer.assembly_id ph_composer.membrane_layers],
                                   :result => { "construction_definitions" => [Export::Privacy.fields(
                                     %w[assembly_id name thermal_layer_count membrane_names defaulted_material_ids]
                                   )] }, :report => method(:report)) { |reader| records(reader) }
      end

      def records(reader)
        materials = reader.records(MATERIAL_KIND).to_h { |row| [row.fetch("id"), row.slice(*MATERIAL_FIELDS)] }
        reader.records(ASSEMBLY_KIND, :user_data => true).map do |row|
          layers = row.fetch("layers").map do |layer|
            layer.slice("id", "thickness_mm").merge(
              "segments" => layer.fetch("segments").map { |segment| segment.slice(*SEGMENT_FIELDS) }
            )
          end
          used = layers.flat_map { |layer| layer.fetch("segments").map { |segment| segment["material_id"] } }.uniq
          row.slice("id", "name", "orientation", "user_data").merge(
            "layers" => layers, "materials" => used.compact.sort.filter_map { |id| materials[id] }
          )
        end
      end

      def preflight(request)
        materials, bad_materials = DefinitionLists.read(request.engine, MATERIAL_KIND,
                                                        request.engine.ids(MATERIAL_KIND))
        assemblies, bad_assemblies = DefinitionLists.read(request.engine, ASSEMBLY_KIND,
                                                          request.engine.ids(ASSEMBLY_KIND))
        by_id = materials.to_h { |row| [row.fetch("id"), row] }
        material_findings = materials.to_h { |row| [row.fetch("id"), Validation.material(row)] }
        findings = material_findings.values.flatten
        findings.concat(assemblies.flat_map do |row|
          Validation.assembly(row, by_id, :material_findings => material_findings)
        end)
        findings = findings.map do |finding|
          message = finding.fetch("message")
          if finding.fetch("code") == "material.thermal_mass_defaulted"
            name = by_id.fetch(finding.fetch("material_id")).fetch("name")
            message = "Missing thermal mass properties use 600 kg/m3 density and 1000 J/kgK specific heat " \
                      "for Material \"#{name}\"."
          end
          preflight_row(finding.fetch("code"), finding["assembly_id"] || finding["material_id"], message, false)
        end
        conversions = materials.flat_map { |row| Validation.material_conversion(row) } +
                      assemblies.flat_map { |row| Validation.assembly_conversion(row, by_id) }
        conversions.each do |finding|
          findings << preflight_row(finding.fetch("code"), finding["assembly_id"] || finding["material_id"],
                                    finding.fetch("message"), false)
        end
        findings.concat((bad_materials + bad_assemblies).map do |row|
          preflight_row(row.fetch("code"), row.fetch("id"), row.fetch("message"), true)
        end)
        { "findings" => findings, "repairs" => [] }
      end

      def preflight_row(code, id, message, blocking)
        { "code" => code, "section" => SECTION, "object_id" => id,
          "message" => message, "blocks_export" => blocking }
      end

      # Each translated definition and what its conversion discloses. How much Face area uses each one is
      # the Zones report's: a definition knows nothing of what uses it.
      def report(result, _display_units)
        definitions = result.fetch("construction_definitions", [])
        return [] if definitions.empty?

        rows = definitions.map do |definition|
          disclosures = []
          unless definition.fetch("membrane_names").empty?
            disclosures << "Membranes: #{definition.fetch('membrane_names').join(', ')}."
          end
          unless definition.fetch("defaulted_material_ids").empty?
            disclosures << "Missing thermal mass properties use 600 kg/m3 and 1000 J/kgK."
          end
          [definition.fetch("name"), disclosures.join(" ")]
        end
        body = Export::ReportHtml.table(%w[Assembly Disclosures], rows)
        body += Export::ReportHtml.paragraph(
          "Only Assemblies that a Face uses are written to the HBJSON; the Construction usage section lists them."
        )
        if definitions.any? { |row| !row.fetch("membrane_names").empty? }
          body += Export::ReportHtml.paragraph(
            "Membranes of a used Assembly are carried in HBJSON; the current PHX/METr conversion ignores them."
          )
        end
        body += Export::ReportHtml.paragraph(
          "Honeybee defaults: roughness MediumRough; thermal absorptance 0.9 when emissivity is absent; " \
          "solar and visible absorptance 0.7. Authored emissivity supplies thermal absorptance when present."
        )
        body += Export::ReportHtml.paragraph(
          "Air barrier, photos, ventilated cladding, hints and local notes remain in the Model."
        )
        [Export::ReportHtml.section("Authored constructions", body)]
      end
      private_class_method :preflight_row
    end
  end
end
