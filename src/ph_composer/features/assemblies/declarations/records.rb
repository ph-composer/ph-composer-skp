# frozen_string_literal: true

module PhComposer
  module Assemblies
    # Record values and patches derive from the kind descriptor. The authoring actions leave
    # identity, references and metadata validation to the same engine available to contributors.
    module RecordRegistration
      module_function

      def install(feature)
        declare_materials(feature)
        declare_assemblies(feature)
      end

      def create_action(feature, prefix, kind, labelled, refuses, &handler)
        feature.action("#{prefix}.create",
                       :description => "Create one #{kind.label}, with default authoring values.", :refuses => refuses,
                       :params => Shapes.create(kind, :labelled => labelled), :result => Shapes::RESULT,
                       :undo_name => "Create #{kind.label}", :side_effects => "Creates one catalog record.",
                       :examples => [{ "values" => { "name" => "Example #{kind.label}" } }], &handler)
      end

      def update_action(feature, prefix, kind, editable, labelled, example_id, &handler)
        feature.action("#{prefix}.update",
                       :description => "Edit one #{kind.label}; changed expected values refuse.",
                       :refuses => Refuses::EDIT,
                       :params => Shapes.update(kind, editable, :labelled => labelled), :result => Shapes::RESULT,
                       :undo_name => "Edit #{kind.label}", :side_effects => "Updates values; metadata stays as stored.",
                       :examples => [{ "id" => example_id, "values" => { "name" => "Edited" },
                                       "expected_values" => { "name" => "Original" } }], &handler)
      end

      def duplicate_action(feature, prefix, kind, properties, example_id, &handler)
        feature.action("#{prefix}.duplicate",
                       :description => "Duplicate one #{kind.label} with independent identity.",
                       :refuses => Refuses::DUPLICATE,
                       :params => Shapes.object(properties, :optional => %w[name copy_datasheets]),
                       :result => Shapes::RESULT, :undo_name => "Duplicate #{kind.label}",
                       :side_effects => "Creates one catalog record, preserving shared definition references.",
                       :examples => [{ "id" => example_id }], &handler)
      end

      def delete_action(feature, prefix, kind, replacement, example_id, &handler)
        properties = { "id" => Shapes.id(kind.id_prefix, "The #{kind.label} to delete."),
                       "expected_values" => Shapes.expected(kind), "replacement_id" => replacement }
        feature.action("#{prefix}.delete",
                       :description => "Delete #{kind.label}; remaining references refuse.",
                       :refuses => Refuses::DELETE,
                       :params => Shapes.object(properties, :optional => %w[expected_values replacement_id]),
                       :result => Shapes::RESULT, :undo_name => "Delete #{kind.label}",
                       :side_effects => "Replacement or explicit clearing rewrites uses and deletes atomically.",
                       :examples => [{ "id" => example_id }], &handler)
      end

      def declare_materials(feature)
        kind = Materials::Schema::KIND
        prefix = "#{FEATURE_ID}.materials"
        example_id = "mat_Ab12Cd34Ef56"
        create_action(feature, prefix, kind, Materials::Schema::LABELLED_FIELDS,
                      Refuses::CREATE - %w[reference.invalid]) do |request, proposal|
          Materials::Operations.create(request, proposal, :values => request.params.fetch("values"),
                                                          :user_data => request.params["user_data"])
        end
        update_action(feature, prefix, kind, Commands::MATERIAL_EDITABLE, Materials::Schema::LABELLED_FIELDS,
                      example_id) do |request, proposal|
          params = request.params
          Materials::Operations.update(request, proposal,
                                       :id => params.fetch("id"), :values => params.fetch("values"),
                                       :expected_values => params.fetch("expected_values"))
        end
        duplicate = {
          "id" => Shapes.id(kind.id_prefix, "The #{kind.label} to copy."),
          "name" => { "type" => "string", "minLength" => 1,
                      "description" => "The copy's name; \"<name> (copy)\" when absent. Names are unique." },
          "copy_datasheets" => { "type" => "boolean", "description" => "Keep the datasheet links on the copy; " \
                                                                       "false when absent." }
        }
        duplicate_action(feature, prefix, kind, duplicate, example_id) do |request, proposal|
          Materials::Operations.duplicate(request, proposal,
                                          :id => request.params.fetch("id"),
                                          :name => request.params["name"],
                                          :copy_datasheets => request.params.fetch("copy_datasheets",
                                                                                   false))
        end
        replacement = Shapes.id("mat", "The Material every Layer-Segment using the deleted one takes instead. " \
                                       "Needed while any Assembly uses it.")
        delete_action(feature, prefix, kind, replacement, example_id) do |request, proposal|
          params = request.params
          Materials::Operations.delete(request, proposal,
                                       :id => params.fetch("id"),
                                       :expected_values => params.fetch("expected_values", {}),
                                       :replacement_id => params["replacement_id"])
        end
      end

      def declare_assemblies(feature)
        kind = Assembly::Schema::KIND
        prefix = "#{FEATURE_ID}.assemblies"
        example_id = Shapes::EXAMPLE_ID
        create_action(feature, prefix, kind, [], Refuses::CREATE) do |request, proposal|
          Assembly::Operations.create(request, proposal, :values => request.params.fetch("values"),
                                                         :user_data => request.params["user_data"])
        end
        update_action(feature, prefix, kind, Commands::ASSEMBLY_EDITABLE, [], example_id) do |request, proposal|
          params = request.params
          Assembly::Operations.update(request, proposal,
                                      :id => params.fetch("id"), :values => params.fetch("values"),
                                      :expected_values => params.fetch("expected_values"))
        end
        duplicate = { "id" => Shapes.id(kind.id_prefix, "The #{kind.label} to copy.") }
        duplicate_action(feature, prefix, kind, duplicate, example_id) do |request, proposal|
          Assembly::Operations.duplicate(request, proposal, :id => request.params.fetch("id"))
        end
        replacement = Shapes.id("asm", "The Assembly every Face using the deleted one takes instead, or null to " \
                                       "clear those Faces' Assembly. Needed while any Face uses it.", :nullable => true)
        delete_action(feature, prefix, kind, replacement, example_id) do |request, proposal|
          params = request.params
          Assembly::Operations.delete(request, proposal,
                                      :id => params.fetch("id"),
                                      :expected_values => params.fetch("expected_values", {}),
                                      :retarget => params.key?("replacement_id"),
                                      :replacement_id => params["replacement_id"])
        end
      end
    end
  end
end
