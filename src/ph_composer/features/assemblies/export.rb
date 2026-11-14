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
        reader.records(ASSEMBLY_KIND, :user_data => true, :parts => true).map do |row|
          layers = row.fetch("layers").map do |layer|
            layer_part = { "kind" => ASSEMBLY_KIND, "id" => row.fetch("id"), "part_ids" => [layer.fetch("id")] }
            carried = carries_segments?(layer, materials)
            segments = layer.fetch("segments").map do |segment|
              part = layer_part.merge("part_ids" => [layer.fetch("id"), segment.fetch("id")])
              reader.entity_record(segment, :fields => SEGMENT_FIELDS, :user_data => carried, :part => part)
            end
            reader.entity_record(layer, :fields => %w[thickness_mm], :user_data => carries_layer?(layer, materials),
                                        :part => layer_part).merge("segments" => segments)
          end
          used = layers.flat_map { |layer| layer.fetch("segments").map { |segment| segment["material_id"] } }.uniq
          row.slice("id", "name", "orientation", "user_data").merge(
            "layers" => layers, "materials" => used.compact.sort.filter_map { |id| materials[id] }
          )
        end
      end

      # Whether the translation builds the Layer as a grid of cell materials under a hybrid host
      # (constructions.py `LayerRecord.divided`): then each Layer-Segment has a material of its own for its map.
      # An undivided Layer's one Layer-Segment shares its Layer's material, so its map stays in the Model.
      def divided?(layer)
        segments = layer.fetch("segments")
        segments.length > 1 || !segments.first&.fetch("steel_stud_spacing_mm", nil).nil?
      end

      # A membrane Layer becomes no material (its Assembly's construction lists it in its own user_data), so its
      # map stays in the Model. `materials` maps each Material id to a row with its `category`.
      def carries_layer?(layer, materials)
        !Materials::Schema.membrane_layer?(layer, materials)
      end

      # Whether each Layer-Segment's map leaves with its cell material: only a divided Layer that is not a
      # membrane has cells, as a membrane Layer keeps a steel stud spacing yet becomes no material at all.
      def carries_segments?(layer, materials)
        carries_layer?(layer, materials) && divided?(layer)
      end

      # The Layers and Layer-Segments of `assembly` whose maps the translation carries, as the parts themselves.
      def carried_parts(assembly, materials)
        Array(assembly["layers"]).flat_map do |layer|
          (carries_layer?(layer, materials) ? [layer] : []) +
            (carries_segments?(layer, materials) ? layer.fetch("segments") : [])
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
        findings.concat(metadata_findings(request))
        { "findings" => findings, "repairs" => [] }
      end

      # The metadata extraction refuses, read as `records` reads it: Materials alone, Assemblies with their
      # user_data passed through, and each Layer and Layer-Segment whose map the translation carries.
      def metadata_findings(request)
        check = Export::MetadataCheck
        materials = check.definitions(request, MATERIAL_KIND)
        assemblies = check.definitions(request, ASSEMBLY_KIND)
        by_id = materials.to_h { |row| [row.fetch("id"), row] }
        parts = assemblies.flat_map { |assembly| carried_parts(assembly, by_id) }
        check.findings(request, materials, :section => SECTION) +
          check.findings(request, assemblies, :section => SECTION, :user_data => true) +
          check.findings(request, parts, :section => SECTION, :user_data => true)
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
      private_class_method :preflight_row, :divided?, :carries_layer?, :carries_segments?, :carried_parts
    end
  end
end
