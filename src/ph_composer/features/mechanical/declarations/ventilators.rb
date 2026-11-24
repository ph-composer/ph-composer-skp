# frozen_string_literal: true

module PhComposer
  module Mechanical
    # What the Ventilator catalog registers: the kind, two reads, the panel's snapshot section and four actions.
    # Every write goes through the record engine, one native Undo step each.
    module VentilatorRegistration
      PREFIX = "#{FEATURE_ID}.ventilators".freeze
      KIND = Ventilators::KIND
      # The codes beyond each kind's common set (context/CONTRACTS.md, "Outcomes and codes").
      PAGE = %w[query.cursor_expired query.limit_invalid].freeze
      CREATE = %w[record.unreadable validation.failed].freeze
      EDIT = %w[record.unreadable reference.invalid target.changed target.not_found validation.failed].freeze
      DUPLICATE = %w[copy.rule_missing extension.invalid record.unreadable reference.invalid target.not_found
                     validation.failed].freeze
      # A delete scans every record for references to it, so an unreadable record anywhere refuses it.
      DELETE = %w[copy.rule_missing record.unreadable reference.in_use target.changed target.not_found
                  validation.failed].freeze
      EXISTS = ["The Ventilator exists and is readable."].freeze
      ROW = Shapes.row(KIND)
      CREATE_EXAMPLE = { "values" => { "name" => "ERV-1", "sensible_heat_recovery" => 0.85,
                                       "latent_heat_recovery" => 0.6, "electric_efficiency_wh_m3" => 0.45 } }.freeze
      LIST_EXAMPLES = [{}, { "limit" => 20 }, { "fields" => %w[values export_ready] }].freeze

      module_function

      def install(feature)
        feature.record_kind(KIND)
        install_reads(feature)
        install_create_and_update(feature)
        install_duplicate_and_delete(feature)
      end

      def install_reads(feature)
        list = Ventilators::Reads::LIST
        feature.query(list, :description => "One bounded page of Ventilators in id order, with export readiness.",
                            :refuses => PAGE, :params => DefinitionLists.params(ROW),
                            :result => DefinitionLists.result(ROW, :paged => true),
                            :examples => LIST_EXAMPLES) { |request| Ventilators::Reads.list(request) }
        feature.query("#{PREFIX}.all", :description => "Every Ventilator with its values and export readiness, for " \
                                                       "the panel snapshot.",
                                       :response => { "bounded" => false, "prefer" => list },
                                       :refuses => [], :params => Shapes::NONE,
                                       :result => DefinitionLists.result(ROW, :paged => false),
                                       :examples => [{}]) { |request| Ventilators::Reads.all(request) }
        feature.snapshot_section(PREFIX, :query => "#{PREFIX}.all")
      end

      def install_create_and_update(feature)
        feature.action("#{PREFIX}.create",
                       :description => "Create one #{KIND.label}. Unless values give them, its unit values take " \
                                       "honeybee-ph's defaults: quantity 1, no heat recovery, 0.55 Wh/m3, frost " \
                                       "protection on below -5 C, in conditioned space, and the subsoil heat " \
                                       "exchanger and preheated intake temperature absent.",
                       :refuses => CREATE, :params => Shapes.create(KIND), :result => Shapes::RESULT,
                       :undo_name => "Create #{KIND.label}", :side_effects => "Creates one Model-owned definition.",
                       :examples => [CREATE_EXAMPLE]) do |request, proposal|
          Ventilators::Operations.create(request, proposal, :values => request.params.fetch("values"),
                                                            :user_data => request.params["user_data"])
        end
        feature.action("#{PREFIX}.update",
                       :description => "Edit guarded values of one #{KIND.label}; a changed expected value refuses " \
                                       "and writes nothing.",
                       :refuses => EDIT, :params => Shapes.update(KIND), :result => Shapes::RESULT,
                       :undo_name => "Edit #{KIND.label}", :preconditions => EXISTS,
                       :side_effects => "Updates one definition and preserves its metadata.",
                       :examples => [{ "id" => Shapes.example_id(KIND), "values" => { "quantity" => 2 },
                                       "expected_values" => { "quantity" => 1 } }]) do |request, proposal|
          params = request.params
          Ventilators::Operations.update(request, proposal,
                                         :id => params.fetch("id"), :values => params.fetch("values"),
                                         :expected_values => params.fetch("expected_values"))
        end
      end

      def install_duplicate_and_delete(feature)
        feature.action("#{PREFIX}.duplicate",
                       :description => "Duplicate one #{KIND.label} with a new id and source derived.",
                       :refuses => DUPLICATE, :params => Shapes.duplicate(KIND), :result => Shapes::RESULT,
                       :undo_name => "Duplicate #{KIND.label}", :preconditions => EXISTS,
                       :side_effects => "Creates one definition; user_data is copied.",
                       :examples => [{ "id" => Shapes.example_id(KIND) }]) do |request, proposal|
          Ventilators::Operations.duplicate(request, proposal, :id => request.params.fetch("id"),
                                                               :name => request.params["name"])
        end
        feature.action("#{PREFIX}.delete",
                       :description => "Delete one #{KIND.label}; one still in use refuses as reference.in_use.",
                       :refuses => DELETE, :params => Shapes.delete(KIND),
                       :result => Shapes.with_removed_user_data(Shapes::RESULT),
                       :undo_name => "Delete #{KIND.label}", :preconditions => EXISTS,
                       :side_effects => "Deletes one definition and its metadata; Undo restores both.",
                       :examples => [{ "id" => Shapes.example_id(KIND) }]) do |request, proposal|
          params = request.params
          Ventilators::Operations.delete(request, proposal, :id => params.fetch("id"),
                                                            :expected_values => params.fetch("expected_values", {}))
        end
      end
    end
  end
end
