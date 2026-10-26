# frozen_string_literal: true

module PhComposer
  module Assemblies
    # Detached read projections. Stored values remain unchanged; display defaults belong to the
    # display block, so expected_values can always be copied from values without inventing storage.
    module Snapshot
      module_function

      def materials(request, paged: true)
        assemblies = DefinitionLists.read(request.engine, ASSEMBLY_KIND, request.engine.ids(ASSEMBLY_KIND)).first
        rows(request, "#{FEATURE_ID}.materials.list", MATERIAL_KIND, paged) do |record|
          material(request.engine.view(MATERIAL_KIND, record), record, assemblies)
        end.merge("categories" => categories)
      end

      def assemblies(request, paged: true)
        materials = DefinitionLists.read(request.engine, MATERIAL_KIND, request.engine.ids(MATERIAL_KIND)).first
        materials_by_id = materials.to_h { |record| [record.fetch("id"), record] }
        material_findings = materials.to_h { |record| [record.fetch("id"), Validation.material(record)] }
        rows(request, "#{FEATURE_ID}.assemblies.list", ASSEMBLY_KIND, paged) do |record|
          assembly(request.engine.view(ASSEMBLY_KIND, record), record, materials_by_id,
                   :material_findings => material_findings)
        end
      end

      # The list query's page or the all query's whole inventory, each row as the block builds it.
      def rows(request, query, kind, paged, &row)
        paged ? DefinitionLists.list(request, query, kind, &row) : DefinitionLists.all(request.engine, kind, &row)
      end

      def categories
        Materials::Schema::CATEGORIES.map { |id, pair| { "id" => id, "label" => pair.first, "tone" => pair.last } }
      end

      def material(view, record, assemblies)
        uses = assemblies.select do |assembly|
          Assembly::Schema::MATERIAL_REFERENCE.ids(assembly).include?(record.fetch("id"))
        end.map { |assembly| { "assembly_id" => assembly.fetch("id"), "name" => assembly.fetch("name") } }
        view.merge("findings" => Validation.material(record), "uses" => uses, "use_count" => uses.length)
      end

      def assembly(view, record, materials, material_findings: nil)
        findings = Validation.assembly(record, materials, :material_findings => material_findings)
        thermal = Thermal.preview(record, materials)
        thermal["message_parts"] = MessageParts.plain(thermal.fetch("warnings"))
        layers = record.fetch("layers")
        total = layers.reject { |layer| Materials::Schema.membrane_layer?(layer, materials) }
                      .sum { |layer| layer.fetch("thickness_mm") }
        blockers = Validation.export_blockers(record, materials, findings)
        view.merge("findings" => findings, "export_ready" => blockers.empty?, "export_blockers" => blockers,
                   "display" => {
                     "color" => record.fetch("color", Assembly::Schema.color(record.fetch("id"))),
                     "layer_count" => layers.length, "total_thickness_mm" => total,
                     "thermal" => thermal, "complete" => Validation.complete?(findings)
                   })
      end
    end
  end
end
