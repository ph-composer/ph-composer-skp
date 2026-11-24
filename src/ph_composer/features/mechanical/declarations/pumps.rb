# frozen_string_literal: true

module PhComposer
  module Mechanical
    # What the Pump catalog registers: the kind, two reads, the panel's snapshot section and four actions,
    # each write one native Undo step through the record engine (CatalogOperations). The reads add the Zones each
    # pump serves and its findings, and the delete moves or empties the Zones' pump lists naming it, from Serves.
    module PumpRegistration
      PREFIX = "#{FEATURE_ID}.pumps"
      KIND = Pumps::KIND
      EXISTS = ["The Pump exists and is readable."].freeze
      UNIQUE = "Its name, trimmed and in any case, is not another Pump's."
      ROW = Shapes.with(Shapes.row(KIND), ServesRegistration::SERVED.merge(
        "ihg_usage_profile_default" => Shapes.described({ "type" => "integer", "minimum" => 1, "maximum" => 4 },
                                                        "The usage profile its device_type gives, which it " \
                                                        "exports while ihg_usage_profile is absent.")
      ))
      LIST_PARAMS = DefinitionLists.params(ROW).tap do |params|
        params["properties"]["ids"]["items"] = Shapes.id(KIND.id_prefix, "A Pump id.")
      end.freeze
      DELETE_PARAMS = Shapes.delete(KIND).then do |params|
        params["properties"]["replacement_id"] =
          Shapes.id(KIND.id_prefix, "The #{KIND.label} that takes this one's place in every Zone's pump list, or " \
                                    "null to take it out of them. Needed while a Zone names it.", :nullable => true)
        params
      end.freeze
      CREATE_EXAMPLE = { "values" => { "name" => "P-1", "device_type" => 4, "norm_energy_demand_w" => 25.0,
                                       "manufacturer" => "Kaltwerk" } }.freeze
      UPDATE_EXAMPLE = { "id" => Shapes.example_id(KIND), "values" => { "norm_energy_demand_w" => 40.0 },
                         "expected_values" => { "norm_energy_demand_w" => 25.0 } }.freeze
      LIST_EXAMPLES = [{}, { "limit" => 20 }, { "fields" => %w[values zones] }].freeze

      module_function

      def install(feature)
        feature.record_kind(KIND)
        install_reads(feature)
        install_create_and_update(feature)
        install_duplicate_and_delete(feature)
      end

      def install_reads(feature)
        list = Pumps::Reads::LIST
        feature.query(list, :description => "One bounded page of Pumps in id order, with the Zones each " \
                                            "serves and its findings.",
                            :refuses => VentilatorRegistration::PAGE + Serves::State::REFUSES,
                            :params => LIST_PARAMS, :result => DefinitionLists.result(ROW, :paged => true),
                            :examples => LIST_EXAMPLES) do |request|
          Pumps::Reads.list(request, :extra => Serves::Reads.usage(request, KIND.id))
        end
        feature.query("#{PREFIX}.all", :description => "Every Pump with its values, the Zones it serves " \
                                                       "and its findings, for the panel snapshot.",
                                       :response => { "bounded" => false, "prefer" => list },
                                       :refuses => Serves::State::REFUSES, :params => Shapes::NONE,
                                       :result => DefinitionLists.result(ROW, :paged => false),
                                       :examples => [{}]) do |request|
          Pumps::Reads.all(request, :extra => Serves::Reads.usage(request, KIND.id))
        end
        feature.snapshot_section(PREFIX, :query => "#{PREFIX}.all")
      end

      def install_create_and_update(feature)
        feature.action("#{PREFIX}.create",
                       :description => "Create one #{KIND.label}. Unless values give it, it is one hot water " \
                                       "circulation pump (device_type 6) in conditioned space drawing 0 W for 8.76 " \
                                       "kh a year, its whole energy an internal heat gain (ihg_utilization_factor " \
                                       "1.0) in the usage profile its type gives (no ihg_usage_profile), with no " \
                                       "manufacturer or model.",
                       :refuses => VentilatorRegistration::CREATE, :params => Shapes.create(KIND),
                       :result => Shapes::RESULT, :undo_name => "Create #{KIND.label}", :preconditions => [UNIQUE],
                       :side_effects => "Creates one Model-owned definition.",
                       :examples => [CREATE_EXAMPLE]) do |request, proposal|
          CatalogOperations.create(request, proposal, KIND.id, :defaults => Pumps,
                                                               :values => request.params.fetch("values"),
                                                               :user_data => request.params["user_data"])
        end
        feature.action("#{PREFIX}.update",
                       :description => "Edit guarded values of one #{KIND.label}; a changed expected value refuses " \
                                       "and writes nothing.",
                       :refuses => VentilatorRegistration::EDIT, :params => Shapes.update(KIND),
                       :result => Shapes::RESULT, :undo_name => "Edit #{KIND.label}",
                       :preconditions => EXISTS + ["A new name: #{UNIQUE}"],
                       :side_effects => "Updates one definition and preserves its metadata.",
                       :examples => [UPDATE_EXAMPLE]) do |request, proposal|
          params = request.params
          CatalogOperations.update(request, proposal, KIND.id, :id => params.fetch("id"),
                                                               :values => params.fetch("values"),
                                                               :expected_values => params.fetch("expected_values"))
        end
      end

      def install_duplicate_and_delete(feature)
        feature.action("#{PREFIX}.duplicate",
                       :description => "Duplicate one #{KIND.label} with a new id and source derived.",
                       :refuses => VentilatorRegistration::DUPLICATE, :params => Shapes.duplicate(KIND),
                       :result => Shapes::RESULT, :undo_name => "Duplicate #{KIND.label}", :preconditions => EXISTS,
                       :side_effects => "Creates one definition; user_data is copied.",
                       :examples => [{ "id" => Shapes.example_id(KIND) }]) do |request, proposal|
          CatalogOperations.duplicate(request, proposal, KIND.id, :id => request.params.fetch("id"),
                                                                  :name => request.params["name"])
        end
        feature.action("#{PREFIX}.delete",
                       :description => "Delete one #{KIND.label}. While a Zone names it, name a replacement_id, " \
                                       "which takes its place in every Zone's pump list (once, where the list " \
                                       "already holds it), or null, which takes it out of them; without one it " \
                                       "refuses as reference.in_use, naming the Zones.",
                       :refuses => VentilatorRegistration::DELETE, :params => DELETE_PARAMS,
                       :result => Shapes.with_removed_user_data(Shapes::RESULT),
                       :participants => [Serves::State::STAGE], :undo_name => "Delete #{KIND.label}",
                       :preconditions => EXISTS,
                       :side_effects => "Deletes one definition and its metadata, and rewrites the Zones that name " \
                                        "it; Undo restores all of them.",
                       :examples => [{ "id" => Shapes.example_id(KIND) },
                                     { "id" => Shapes.example_id(KIND),
                                       "replacement_id" => "pmp_Zy98Xw76Vu54" }]) do |request, proposal|
          params = request.params
          id = params.fetch("id")
          expected = params.fetch("expected_values", {})
          replacement = params.fetch("replacement_id", Serves::Operations::KEEP)
          Serves::Operations.delete(request, proposal, KIND.id, :id => id, :expected_values => expected,
                                                                :replacement => replacement) do |plan|
            CatalogOperations.delete(request, proposal, KIND.id, :id => id, :expected_values => expected,
                                                                 :reference_plan => plan)
          end
        end
      end
    end
  end
end
