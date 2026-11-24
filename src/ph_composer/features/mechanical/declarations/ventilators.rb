# frozen_string_literal: true

module PhComposer
  module Mechanical
    # What the Ventilator catalog registers: the kind, two reads, the panel's snapshot section and four actions.
    # Every write goes through the record engine, one native Undo step each. The reads add what each Ventilator
    # serves, and the delete moves or clears the Zones naming it, from Serves.
    module VentilatorRegistration
      PREFIX = "#{FEATURE_ID}.ventilators".freeze
      KIND = Ventilators::KIND
      # The codes beyond each kind's common set (context/CONTRACTS.md, "Outcomes and codes").
      PAGE = %w[query.cursor_expired query.limit_invalid].freeze
      CREATE = %w[record.unreadable validation.failed].freeze
      # An installed extension's payload may name an entity whose id two occurrences share: target.ambiguous.
      EDIT = %w[record.unreadable reference.invalid target.ambiguous target.changed target.not_found
                validation.failed].freeze
      DUPLICATE = %w[copy.rule_missing extension.invalid record.unreadable reference.invalid target.ambiguous
                     target.not_found validation.failed].freeze
      # A delete scans every record for references to it, so an unreadable record anywhere refuses it. It reads
      # the Zones naming it, and the dispatcher adds the refusals of Zones' participant, which stages the moves.
      DELETE = (%w[copy.rule_missing record.unreadable reference.in_use reference.invalid
                   target.ambiguous target.changed target.not_found validation.failed] + Serves::State::REFUSES)
               .uniq.sort.freeze
      EXISTS = ["The Ventilator exists and is readable."].freeze
      UNIQUE = "Its name, trimmed and in any case, is not another Ventilator's."
      FLOW = { "type" => %w[number null], "minimum" => 0, "x-unit" => "m3/h" }.freeze
      BALANCE = Shapes.described(Shapes.object({
        "supply_m3h" => Shapes.described(FLOW, "Summed over the Zones the export writes it to; null while unknown."),
        "extract_m3h" => Shapes.described(FLOW, "As supply_m3h."),
        "imbalanced" => Shapes.described({ "type" => "boolean" }, "Supply and extract differ by more than a tenth " \
                                                                  "of the larger."),
        "missing" => Shapes.described({ "type" => %w[string null] }, "Why the sums are null; null when known.")
      }), "Its airflow balance: each Zone in Detailed airflows gives its Spaces' sums, a By Program Zone its " \
          "Program's flow as both supply and extract.").freeze
      ROW = Shapes.with(Shapes.row(KIND), ServesRegistration::SERVED.merge("balance" => BALANCE))
      LIST_PARAMS = DefinitionLists.params(ROW).tap do |params|
        params["properties"]["ids"]["items"] = Shapes.id(KIND.id_prefix, "A Ventilator id.")
      end.freeze
      DELETE_PARAMS = Shapes.delete(KIND).then do |params|
        params["properties"]["replacement_id"] =
          Shapes.id(KIND.id_prefix, "The #{KIND.label} that takes this one's place on every Zone, or null to empty " \
                                    "those slots. Needed while a Zone names it.", :nullable => true)
        params
      end.freeze
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
        feature.query(list, :description => "One bounded page of Ventilators in id order, with export readiness, " \
                                            "the Zones each serves and its airflow balance.",
                            :refuses => PAGE + Serves::State::REFUSES, :params => LIST_PARAMS,
                            :result => DefinitionLists.result(ROW, :paged => true),
                            :examples => LIST_EXAMPLES) do |request|
          usage = Serves::Reads.usage(request, KIND.id, :with_balance => true)
          Ventilators::Reads.list(request, :extra => usage)
        end
        feature.query("#{PREFIX}.all", :description => "Every Ventilator with its values, export readiness, the " \
                                                       "Zones it serves and its airflow balance, for the panel " \
                                                       "snapshot.",
                                       :response => { "bounded" => false, "prefer" => list },
                                       :refuses => Serves::State::REFUSES, :params => Shapes::NONE,
                                       :result => DefinitionLists.result(ROW, :paged => false),
                                       :examples => [{}]) do |request|
          usage = Serves::Reads.usage(request, KIND.id, :with_balance => true)
          Ventilators::Reads.all(request, :extra => usage)
        end
        feature.snapshot_section(PREFIX, :query => "#{PREFIX}.all")
      end

      def install_create_and_update(feature)
        feature.action("#{PREFIX}.create",
                       :description => "Create one #{KIND.label}. Unless values give them, its unit values take " \
                                       "honeybee-ph's defaults: quantity 1, no heat recovery, 0.55 Wh/m3, frost " \
                                       "protection on below -5 C, in conditioned space, and the subsoil heat " \
                                       "exchanger and preheated intake temperature absent.",
                       :refuses => CREATE, :params => Shapes.create(KIND), :result => Shapes::RESULT,
                       :undo_name => "Create #{KIND.label}", :preconditions => [UNIQUE],
                       :side_effects => "Creates one Model-owned definition.",
                       :examples => [CREATE_EXAMPLE]) do |request, proposal|
          Ventilators::Operations.create(request, proposal, :values => request.params.fetch("values"),
                                                            :user_data => request.params["user_data"])
        end
        feature.action("#{PREFIX}.update",
                       :description => "Edit guarded values of one #{KIND.label}; a changed expected value refuses " \
                                       "and writes nothing.",
                       :refuses => EDIT, :params => Shapes.update(KIND), :result => Shapes::RESULT,
                       :undo_name => "Edit #{KIND.label}", :preconditions => EXISTS + ["A new name: #{UNIQUE}"],
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
                       :description => "Delete one #{KIND.label}. While a Zone names it, name a replacement_id, " \
                                       "which takes its place on every Zone, or null, which empties those slots; " \
                                       "without one it refuses as reference.in_use, naming the Zones.",
                       :refuses => DELETE, :params => DELETE_PARAMS,
                       :result => Shapes.with_removed_user_data(Shapes::RESULT),
                       :participants => [Serves::State::STAGE],
                       :undo_name => "Delete #{KIND.label}", :preconditions => EXISTS,
                       :side_effects => "Deletes one definition and its metadata, and rewrites the Zones that name " \
                                        "it; Undo restores all of them.",
                       :examples => [{ "id" => Shapes.example_id(KIND) },
                                     { "id" => Shapes.example_id(KIND),
                                       "replacement_id" => "vnt_Zy98Xw76Vu54" }]) do |request, proposal|
          params = request.params
          id = params.fetch("id")
          expected = params.fetch("expected_values", {})
          replacement = params.fetch("replacement_id", Serves::Operations::KEEP)
          Serves::Operations.delete(request, proposal, KIND.id, :id => id, :expected_values => expected,
                                                                :replacement => replacement) do |plan|
            Ventilators::Operations.delete(request, proposal, :id => id, :expected_values => expected,
                                                              :reference_plan => plan)
          end
        end
      end
    end
  end
end
