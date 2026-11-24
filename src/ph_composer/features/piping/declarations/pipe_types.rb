# frozen_string_literal: true

module PhComposer
  module Piping
    # What the Pipe Type catalog registers: the kind, two reads, the panel's snapshot section and four actions,
    # each write one native Undo step through the record engine.
    module PipeTypeRegistration
      PREFIX = "#{FEATURE_ID}.pipe_types".freeze
      KIND = PipeType::KIND
      # The codes beyond each kind's common set (context/CONTRACTS.md, "Outcomes and codes").
      PAGE = %w[query.cursor_expired query.limit_invalid].freeze
      CREATE = %w[record.unreadable validation.failed].freeze
      EDIT = %w[record.unreadable reference.invalid target.changed target.not_found validation.failed].freeze
      DUPLICATE = %w[copy.rule_missing extension.invalid record.unreadable reference.invalid target.not_found
                     validation.failed].freeze
      # A delete scans every record for references to it, so an unreadable record anywhere refuses it.
      DELETE = %w[copy.rule_missing record.unreadable reference.in_use target.changed target.not_found
                  validation.failed].freeze
      EXISTS = ["The Pipe Type exists and is readable."].freeze
      UNIQUE = "Its name, trimmed and in any case, is not another Pipe Type's."

      DISPLAY = Shapes.object({ "color" => Shapes.described(SchemaShapes::HEX_COLOUR,
                                                            "The stored color, or the default one for the id.") })
      ROW = Shapes.with(Shapes.view(KIND),
                        "display" => DISPLAY,
                        "export_ready" => Shapes.described({ "type" => "boolean" },
                                                           "Whether a pipe using this type can export."),
                        "export_blockers" => Shapes.described(Shapes.list(Shapes::TEXT),
                                                              "The codes keeping it out of an export once a pipe " \
                                                              "uses it; empty when export_ready."))
      LIST_PARAMS = DefinitionLists.params(ROW).tap do |params|
        params["properties"]["ids"]["items"] = Shapes.id(KIND.id_prefix, "A Pipe Type id.")
      end.freeze
      DELETE_PARAMS = Shapes.object(
        { "id" => Shapes.id(KIND.id_prefix, "The #{KIND.label} to delete."),
          "expected_values" => Shapes.expected(KIND),
          "replacement_id" => Shapes.id(KIND.id_prefix, "Another existing Pipe Type to take this one's place on " \
                                                        "every pipe using it, or null to leave those pipes with no " \
                                                        "type, which blocks their export.",
                                        :nullable => true) },
        :optional => %w[expected_values replacement_id]
      ).freeze
      CREATE_EXAMPLE = { "values" => { "name" => "PEX 3/4", "material" => 6, "diameter_mm" => 19.05,
                                       "insulation_thickness_mm" => 25.4 } }.freeze
      UPDATE_EXAMPLE = { "id" => Shapes.example_id(KIND), "values" => { "insulation_conductivity_w_mk" => 0.035 },
                         "expected_values" => { "insulation_conductivity_w_mk" => 0.04 } }.freeze
      LIST_EXAMPLES = [{}, { "limit" => 20 }, { "fields" => %w[values export_ready] }].freeze

      module_function

      def install(feature)
        feature.record_kind(KIND)
        install_reads(feature)
        install_create_and_update(feature)
        install_duplicate_and_delete(feature)
      end

      def install_reads(feature)
        list = PipeType::Reads::LIST
        feature.query(list, :description => "One bounded page of Pipe Types in id order, with export readiness.",
                            :refuses => PAGE, :params => LIST_PARAMS,
                            :result => DefinitionLists.result(ROW, :paged => true),
                            :examples => LIST_EXAMPLES) { |request| PipeType::Reads.list(request) }
        feature.query("#{PREFIX}.all", :description => "Every Pipe Type with its values and export readiness, " \
                                                       "for the panel snapshot.",
                                       :response => { "bounded" => false, "prefer" => list },
                                       :refuses => [], :params => Shapes::NONE,
                                       :result => DefinitionLists.result(ROW, :paged => false),
                                       :examples => [{}]) { |request| PipeType::Reads.all(request) }
        feature.snapshot_section(PREFIX, :query => "#{PREFIX}.all")
      end

      def install_create_and_update(feature)
        feature.action("#{PREFIX}.create",
                       :description => "Create one #{KIND.label}. Unless values give them, it is a 1/2 in " \
                                       "(diameter_mm 12.7) Copper L pipe (material 2) with 12.7 mm of reflective " \
                                       "insulation at 0.04 W/mK, insulation_quality 1, and no stored color.",
                       :refuses => CREATE, :params => Shapes.create(KIND), :result => Shapes::RESULT,
                       :undo_name => "Create #{KIND.label}", :preconditions => [UNIQUE],
                       :side_effects => "Creates one Model-owned definition.",
                       :examples => [CREATE_EXAMPLE]) do |request, proposal|
          PipeType::Operations.create(request, proposal, :values => request.params.fetch("values"),
                                                         :user_data => request.params["user_data"])
        end
        feature.action("#{PREFIX}.update",
                       :description => "Edit guarded values of one #{KIND.label}; a changed expected value refuses " \
                                       "and writes nothing.",
                       :refuses => EDIT, :params => Shapes.update(KIND), :result => Shapes::RESULT,
                       :undo_name => "Edit #{KIND.label}", :preconditions => EXISTS + ["A new name: #{UNIQUE}"],
                       :side_effects => "Updates one definition and preserves its metadata.",
                       :examples => [UPDATE_EXAMPLE]) do |request, proposal|
          params = request.params
          PipeType::Operations.update(request, proposal, :id => params.fetch("id"), :values => params.fetch("values"),
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
          PipeType::Operations.duplicate(request, proposal, :id => request.params.fetch("id"),
                                                            :name => request.params["name"])
        end
        feature.action("#{PREFIX}.delete",
                       :description => "Delete one #{KIND.label}. A type a pipe still uses refuses as " \
                                       "reference.in_use unless replacement_id names another type to take its " \
                                       "place, or is null to clear it.",
                       :refuses => DELETE, :params => DELETE_PARAMS,
                       :result => Shapes.with_removed_user_data(Shapes::RESULT),
                       :undo_name => "Delete #{KIND.label}", :preconditions => EXISTS,
                       :side_effects => "Deletes one definition and its metadata; Undo restores both.",
                       :examples => [{ "id" => Shapes.example_id(KIND) },
                                     { "id" => Shapes.example_id(KIND),
                                       "replacement_id" => "ppt_Zy98Xw76Vu54" }]) do |request, proposal|
          params = request.params
          replacement = params.fetch("replacement_id", PipeType::Operations::KEEP)
          Assignment::Operations.delete_type(request, proposal, :id => params.fetch("id"),
                                                                :expected_values => params.fetch("expected_values", {}),
                                                                :replacement_id => replacement)
        end
      end
    end
  end
end
