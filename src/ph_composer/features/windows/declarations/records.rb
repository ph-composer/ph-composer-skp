# frozen_string_literal: true

require_relative "../units/type_retargeter"

module PhComposer
  module Windows
    module RecordRegistration
      module_function

      def install(feature)
        Products::KINDS.each { |collection, kind| declare_product(feature, collection, kind) }
        declare_type(feature)
        Units::TypeRetargeter.install(feature)
      end

      def example_id(kind)
        "#{kind.id_prefix}_Ab12Cd34Ef56"
      end

      def update_example(kind)
        { "id" => example_id(kind), "values" => { "name" => "Edited" }, "expected_values" => { "name" => "Original" } }
      end

      def duplicate_params(kind)
        Shapes.object({ "id" => Shapes.id(kind.id_prefix, "The #{kind.label} to copy."),
                        "name" => { "type" => "string", "minLength" => 1,
                                    "description" => "The copy's name; \"<name> (copy)\" when absent. Names " \
                                                     "are unique." },
                        "copy_datasheets" => { "type" => "boolean", "description" => "Keep the datasheet links on " \
                                                                                     "the copy; false when absent." } },
                      :optional => %w[name copy_datasheets])
      end

      def delete_params(kind, replacement)
        Shapes.object({ "id" => Shapes.id(kind.id_prefix, "The #{kind.label} to delete."),
                        "expected_values" => Shapes.expected(kind), "replacement_id" => replacement },
                      :optional => %w[expected_values replacement_id])
      end

      def declare_product(feature, collection, kind)
        prefix = "#{FEATURE_ID}.#{collection}"
        feature.action("#{prefix}.create",
                       :description => "Create one #{kind.label} with local defaults.",
                       :refuses => Refuses::WRITE,
                       :params => Shapes.create(kind), :result => Shapes::RESULT, :undo_name => "Create #{kind.label}",
                       :side_effects => Shapes.side_effects("Creates one Model-owned definition."),
                       :examples => [{ "values" => { "name" => "Example #{kind.label}" } }]) do |request, proposal|
          Authoring.create_product(request, proposal, collection, :values => request.params.fetch("values"),
                                                                  :user_data => request.params["user_data"])
        end
        feature.action("#{prefix}.update",
                       :description => "Edit guarded authored values of one #{kind.label}.",
                       :refuses => Refuses::EDIT,
                       :params => Shapes.update(kind), :result => Shapes::RESULT, :undo_name => "Edit #{kind.label}",
                       :side_effects => Shapes.side_effects("Updates one definition and preserves its metadata."),
                       :examples => [update_example(kind)]) do |request, proposal|
          params = request.params
          Authoring.update_product(request, proposal, collection,
                                   :id => params.fetch("id"),
                                   :values => params.fetch("values"),
                                   :expected_values => params.fetch("expected_values"))
        end
        declare_product_copy_and_delete(feature, prefix, collection, kind)
      end

      def declare_product_copy_and_delete(feature, prefix, collection, kind)
        feature.action("#{prefix}.duplicate",
                       :description => "Duplicate a #{kind.label} with independent identity.",
                       :refuses => Refuses::DUPLICATE,
                       :params => duplicate_params(kind), :result => Shapes::RESULT,
                       :undo_name => "Duplicate #{kind.label}",
                       :side_effects => Shapes.side_effects("Copies definition metadata."),
                       :examples => [{ "id" => example_id(kind) }]) do |request, proposal|
          Authoring.duplicate_product(request, proposal, collection,
                                      :id => request.params.fetch("id"),
                                      :name => request.params["name"],
                                      :copy_datasheets => request.params.fetch("copy_datasheets",
                                                                               false))
        end
        replacement = Shapes.id(kind.id_prefix, "The #{kind.label} that every Window Type and default using the " \
                                                "deleted one takes. Needed while any uses it.")
        feature.action("#{prefix}.delete",
                       :description => "Delete #{kind.label}; live references require replacement.",
                       :refuses => Refuses::DELETE,
                       :params => delete_params(kind, replacement),
                       :result => Shapes.with_removed_user_data(Shapes::RESULT),
                       :undo_name => "Delete #{kind.label}",
                       :side_effects => Shapes.side_effects("Rewrites referring definitions and defaults, then " \
                                                            "deletes atomically."),
                       :examples => [{ "id" => example_id(kind) }]) do |request, proposal|
          params = request.params
          Authoring.delete_product(request, proposal, collection,
                                   :id => params.fetch("id"),
                                   :expected_values => params.fetch("expected_values", {}),
                                   :retarget => params.key?("replacement_id"),
                                   :replacement_id => params["replacement_id"])
        end
      end

      def declare_type(feature)
        kind = Types::KIND
        prefix = "#{FEATURE_ID}.types"
        width, height = Types::DEFAULT_SIZE_M
        feature.action("#{prefix}.create",
                       :description => "Create one Window Type with one glazed element, #{width} m wide by #{height} " \
                                       "m high unless values give columns_m and rows_m. The size does not follow the " \
                                       "display unit system.",
                       :refuses => Refuses::WRITE,
                       :params => Shapes.create(kind), :result => Shapes::RESULT, :undo_name => "Create #{kind.label}",
                       :side_effects => Shapes.side_effects("Creates one Model-owned definition."),
                       :examples => [{ "values" => { "name" => "Example #{kind.label}" } }]) do |request, proposal|
          Authoring.create_type(request, proposal, :values => request.params.fetch("values"),
                                                   :user_data => request.params["user_data"])
        end
        feature.action("#{prefix}.update",
                       :description => "Edit guarded authored values of one #{kind.label}.",
                       :refuses => Refuses::TYPE_EDIT,
                       :params => Shapes.update(kind), :result => Shapes::TYPE_RESULT,
                       :undo_name => "Edit #{kind.label}",
                       :side_effects => Shapes.side_effects("Updates one definition and preserves its metadata."),
                       :examples => [update_example(kind)]) do |request, proposal|
          params = request.params
          Authoring.update_type(request, proposal,
                                :id => params.fetch("id"), :values => params.fetch("values"),
                                :expected_values => params.fetch("expected_values"))
        end
        declare_type_copy_and_delete(feature, prefix, kind)
      end

      def declare_type_copy_and_delete(feature, prefix, kind)
        feature.action("#{prefix}.duplicate",
                       :description => "Duplicate a #{kind.label} with independent identity.",
                       :refuses => Refuses::DUPLICATE,
                       :params => duplicate_params(kind), :result => Shapes::RESULT,
                       :undo_name => "Duplicate #{kind.label}",
                       :side_effects => Shapes.side_effects(
                         "Copies definition metadata and retains shared products; new elements get fresh ids."
                       ),
                       :examples => [{ "id" => example_id(kind) }]) do |request, proposal|
          Authoring.duplicate_type(request, proposal,
                                   :id => request.params.fetch("id"),
                                   :name => request.params["name"],
                                   :copy_datasheets => request.params.fetch("copy_datasheets",
                                                                            false))
        end
        replacement = Shapes.id(kind.id_prefix, "The Window Type every Window of the deleted one takes, or null " \
                                                "to remove them. Needed while Windows use it.", :nullable => true)
        feature.action("#{prefix}.delete",
                       :description => "Delete #{kind.label}; live references require replacement.",
                       :refuses => Refuses::TYPE_DELETE,
                       :params => delete_params(kind, replacement),
                       :result => Shapes.with_removed_user_data(Shapes::RESULT),
                       :undo_name => "Delete #{kind.label}",
                       :side_effects => Shapes.side_effects("Rewrites referring definitions and defaults, then " \
                                                            "deletes atomically."),
                       :examples => [{ "id" => example_id(kind) }]) do |request, proposal|
          params = request.params
          Authoring.delete_type(request, proposal,
                                :id => params.fetch("id"),
                                :expected_values => params.fetch("expected_values", {}),
                                :retarget => params.key?("replacement_id"),
                                :replacement_id => params["replacement_id"])
        end
      end
    end
  end
end
