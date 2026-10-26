# frozen_string_literal: true

module PhComposer
  module Assemblies
    module Commands
      ASSEMBLY_EDITABLE = %w[name type orientation exterior_condition ventilated_cladding color air_barrier notes
                             datasheet_links].freeze

      module_function

      def update_assembly(record, values:, materials: {})
        unknown = values.keys - ASSEMBLY_EDITABLE
        unless unknown.empty?
          raise CodedError.new("params.invalid", "Assembly fields #{unknown.join(', ')} cannot be edited here.")
        end

        changes = DeepCopy.call(values)
        changes["name"] = changes["name"].strip if changes["name"]
        candidate = patch(record, changes)
        mutate(record, materials) { |next_record| next_record.replace(candidate) }
      end

      def fresh_nested_id(prefix, reserved, identity)
        loop do
          id = identity.call(prefix)
          next if reserved.include?(id)

          reserved << id
          return id
        end
      end
      private_class_method :fresh_nested_id

      # Only authored values cross the engine's duplicate transform; identity and metadata remain
      # engine-owned. The air-barrier marker follows its new Layer identity.
      def duplicate_assembly_values(values, records, identity: Records::Identity.method(:mint))
        copy = DeepCopy.call(values)
        layer_ids = {}
        reserved = copy.fetch("layers").flat_map do |layer|
          [layer.fetch("id")] + layer.fetch("segments").map { |segment| segment.fetch("id") }
        end
        copy.fetch("layers").each do |layer|
          old_id = layer.fetch("id")
          layer["id"] = fresh_nested_id("lyr", reserved, identity)
          layer_ids[old_id] = layer.fetch("id")
          layer.fetch("segments").each { |segment| segment["id"] = fresh_nested_id("seg", reserved, identity) }
        end
        barrier = copy["air_barrier"]
        barrier["layer_id"] = layer_ids.fetch(barrier.fetch("layer_id")) if barrier
        copy["photo_collections"] = {}
        copy["name"] = Records::Names.copy_name(copy.fetch("name"), records)
        copy["source"] = { "kind" => "derived" }
        copy
      end
    end
  end
end
