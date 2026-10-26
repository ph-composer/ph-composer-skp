# frozen_string_literal: true

module PhComposer
  module Windows
    # The staged session submits products and edge assignments as one atomic, guarded action.
    # Temporary client identities are resolved only in installation slots, never in metadata.
    module InstallSave
      module_function

      # The arguments are the action's params (InstallsRegistration::PARAMS).
      def call(request, proposal, types:, psi_install_types:, expected_settings:, imports: [])
        Units::Mutation.prepare(request, proposal)
        unless Settings.read(request.model) == expected_settings
          raise CodedError.new("target.changed", "Window defaults changed; reopen the Installs session.")
        end

        mapping = LibraryImports.resolve(request, imports, psi_install_types.fetch("create"))
        mapping.merge!(create_products(request, proposal, psi_install_types.fetch("create")))
        update_products(request, proposal, psi_install_types.fetch("update"))
        unique_final_names!(request, proposal)
        duplicate_targets!(types, "id")
        types.each { |target| update_type(request, proposal, target, mapping) }
        { "type_ids" => types.map { |target| target.fetch("id") }, "psi_install_type_ids" => mapping }
      end

      def duplicate_targets!(rows, key)
        unless rows.map { |row| row.fetch(key) }.uniq.length == rows.length
          raise CodedError.new("params.invalid", "The staged session repeats a target.")
        end
      end

      def create_products(request, proposal, rows)
        duplicate_targets!(rows, "client_id")
        kind = Products::KINDS.fetch("psi_install_types")
        known = Definitions.records(request, kind)
        rows.to_h do |row|
          if request.engine.ids(PSI_INSTALL_KIND).include?(row.fetch("client_id"))
            raise CodedError.new("params.invalid", "A temporary identity collides with a saved product.")
          end

          values = Products.defaults("psi_install_types", row.fetch("values"))
          Records::Names.unique!(values.fetch("name"), known)
          id = request.engine.propose_create(PSI_INSTALL_KIND, proposal, :values => values,
                                                                         :user_data => row["user_data"])
          known << values.merge("id" => id)
          [row.fetch("client_id"), id]
        end
      end

      def update_products(request, proposal, rows)
        duplicate_targets!(rows, "id")
        kind = Products::KINDS.fetch("psi_install_types")
        known = Definitions.records(request, kind)
        rows.each do |row|
          values = DeepCopy.call(row.fetch("values"))
          if values["name"]
            values["name"] = values["name"].strip
            Records::Names.unique!(values["name"], known, :except => row.fetch("id"))
            known.find { |record| record.fetch("id") == row.fetch("id") }&.merge!("name" => values["name"])
          end
          request.engine.propose_update(PSI_INSTALL_KIND, row.fetch("id"), proposal,
                                        :values => values,
                                        :expected_values => row.fetch("expected_values"),
                                        :user_data => row["user_data"])
        end
      end

      def unique_final_names!(request, proposal)
        rows = Definitions.records(request, Products::KINDS.fetch("psi_install_types"))
                          .to_h { |record| [record.fetch("id"), record] }
        proposal.writes.select { |write| write.kind == PSI_INSTALL_KIND }.each do |write|
          rows[write.id] = write.after
        end
        names = rows.values.map { |record| record.fetch("name").strip.downcase }
        return if names.uniq.length == names.length

        raise CodedError.new("validation.failed", "Installation products need unique names after this session.")
      end

      def update_type(request, proposal, target, mapping)
        before = request.engine.find(TYPE_KIND, target.fetch("id"))
        after = DeepCopy.call(before)
        edges = target.fetch("installs")
        duplicate_targets!(edges, "element_id")
        edges.each do |edge|
          element = after.fetch("elements").find { |cell| cell.fetch("id") == edge.fetch("element_id") }
          raise CodedError.new("target.not_found", "The staged element no longer exists.") unless element
          if element.fetch("kind") == "empty"
            raise CodedError.new("validation.failed", "Empty elements have no installation edges.")
          end

          element["installs"] = edge.fetch("sides").transform_values { |id| mapping.fetch(id, id) }
        end
        Installs.validate(after)
        request.engine.propose_update(TYPE_KIND, target.fetch("id"), proposal,
                                      :values => { "elements" => after.fetch("elements") },
                                      :expected_values => target.fetch("expected_values"))
      end
    end
  end
end
