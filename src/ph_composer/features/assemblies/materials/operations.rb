# frozen_string_literal: true

module PhComposer
  module Assemblies
    module Materials
      # Material persistence. Each operation takes its inputs as arguments: a declaration unpacks its
      # params once, and a library callback calls the same operation with its own
      # (context/EXTENSIBILITY.md, "Organization and dependencies").
      module Operations
        module_function

        def create(request, proposal, values:, user_data: nil)
          Records::Names.unique!(values.fetch("name"), Definitions.records(request, MATERIAL_KIND))
          id = request.engine.propose_create(MATERIAL_KIND, proposal, :values => Schema.defaults(values),
                                                                      :user_data => user_data)
          { "id" => id }
        end

        # `source` is the library coordinator's provenance, never a value a client edits: the editable
        # allowlist in Commands excludes it, and only the library replace callback supplies it here.
        def update(request, proposal, id:, values:, expected_values:, user_data: nil, source: nil)
          record = request.engine.find(MATERIAL_KIND, id)
          if values["name"]
            Records::Names.unique!(values["name"], Definitions.records(request, MATERIAL_KIND), :except => id)
          end
          result = Commands.update_material(record, :values => values)
          changes = Definitions.changed_values(Schema::KIND, record, result.record)
          changes["source"] = DeepCopy.call(source) unless source.nil?
          request.engine.propose_update(MATERIAL_KIND, id, proposal,
                                        :values => changes, :expected_values => expected_values,
                                        :user_data => user_data)
          { "id" => id }
        end

        def duplicate(request, proposal, id:, name: nil, copy_datasheets: false)
          catalog = Definitions.records(request, MATERIAL_KIND)
          mapping = request.engine.propose_duplicate(MATERIAL_KIND, [id], proposal) do |values|
            Commands.duplicate_material_values(values, catalog, :name => name, :copy_datasheets => copy_datasheets)
          end
          { "id" => mapping.fetch(id) }
        end

        # With `replacement_id`, every Layer-Segment using the Material takes the replacement first.
        # Without it, any remaining use refuses the delete.
        def delete(request, proposal, id:, expected_values: {}, replacement_id: nil)
          request.engine.find(MATERIAL_KIND, id)
          if replacement_id
            raise CodedError.new("params.invalid", "Choose a different replacement Material.") if replacement_id == id

            catalog = Definitions.materials(request)
            replacement = request.engine.find(MATERIAL_KIND, replacement_id)
            Definitions.records(request, ASSEMBLY_KIND).each do |record|
              next unless Assembly::Schema::MATERIAL_REFERENCE.ids(record).include?(id)

              result = Commands.replace_material(record, :material_id => id, :replacement => replacement,
                                                         :materials => catalog)
              request.engine.propose_update(ASSEMBLY_KIND, record.fetch("id"), proposal,
                                            :values => Definitions.changed_values(Assembly::Schema::KIND, record,
                                                                                  result.record),
                                            :expected_values => { "layers" => record.fetch("layers") })
            end
          end
          request.engine.propose_delete(MATERIAL_KIND, id, proposal, :expected_values => expected_values)
          { "id" => id }
        end
      end
    end
  end
end
