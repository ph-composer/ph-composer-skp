# frozen_string_literal: true

module PhComposer
  module Assemblies
    module Commands
      MATERIAL_EDITABLE = %w[name category conductivity_w_mk density_kg_m3 specific_heat_j_kgk emissivity color
                             notes datasheet_links].freeze

      module_function

      def update_material(record, values:)
        unknown = values.keys - MATERIAL_EDITABLE
        unless unknown.empty?
          raise CodedError.new("params.invalid", "Material fields #{unknown.join(', ')} cannot be edited here.")
        end

        changes = DeepCopy.call(values)
        changes["category"] = Materials::Schema.category(changes["category"]) if changes["category"]
        changes["name"] = changes["name"].strip if changes["name"]
        candidate = patch(record, changes)
        problems = Materials::Schema::KIND.problems(candidate)
        raise CodedError.new("validation.failed", problems.first, "findings" => problems) unless problems.empty?

        Change.new(:record => candidate, :findings => Validation.material(candidate))
      end

      def duplicate_material_values(values, records, name: nil, copy_datasheets: false)
        copy = DeepCopy.call(values)
        copy["name"] = (name || Records::Names.copy_name(copy.fetch("name"), records)).strip
        Records::Names.unique!(copy.fetch("name"), records)
        copy["datasheet_links"] = [] unless copy_datasheets
        copy["source"] = { "kind" => "derived" }
        copy
      end

      def replace_material(record, material_id:, replacement:, materials:)
        mutate(record, materials) do |assembly|
          assembly.fetch("layers").each do |layer|
            uses = layer.fetch("segments").select { |segment| segment["material_id"] == material_id }
            next if uses.empty?

            if Materials::Schema.membrane?(replacement) && layer.fetch("segments").length > 1
              raise CodedError.new("validation.failed", "A membrane Layer must hold one Layer-Segment.")
            end

            uses.each { |segment| segment["material_id"] = replacement.fetch("id") }
            snap_membrane!(layer, materials)
          end
        end
      end
    end
  end
end
