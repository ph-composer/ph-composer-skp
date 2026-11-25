# frozen_string_literal: true

module PhComposer
  module Ducting
    # What the Duct Type catalog registers: the kind, two reads, the panel's snapshot section and four actions, each
    # write one native Undo step through the record engine. The params are Mechanical's catalog shapes, which a flat
    # catalog of any feature above Mechanical shares.
    module DuctTypeRegistration
      PREFIX = "#{FEATURE_ID}.duct_types".freeze
      KIND = DuctType::KIND
      Shapes = Mechanical::Shapes
      # The codes beyond each kind's common set (context/CONTRACTS.md, "Outcomes and codes").
      PAGE = %w[query.cursor_expired query.limit_invalid].freeze
      CREATE = %w[record.unreadable validation.failed].freeze
      EDIT = %w[record.unreadable reference.invalid target.changed target.not_found validation.failed].freeze
      DUPLICATE = %w[copy.rule_missing extension.invalid record.unreadable reference.invalid target.not_found
                     validation.failed].freeze
      # A delete scans every record for references to it, so an unreadable record anywhere refuses it.
      DELETE = %w[copy.rule_missing record.unreadable reference.in_use target.changed target.not_found
                  validation.failed].freeze
      EXISTS = ["The Duct Type exists and is readable."].freeze
      UNIQUE = "Its name, trimmed and in any case, is not another Duct Type's."
      SHAPED = "The values written give the shape's dimensions and no other shape's: diameter_mm for round, " \
               "width_mm and height_mm for rectangular."

      DISPLAY = Shapes.object({ "color" => Shapes.described(SchemaShapes::HEX_COLOUR,
                                                            "The stored color, or the default one for the id.") })
      ROW = Shapes.with(KIND.descriptor.view_schema,
                        "kind" => Shapes::TEXT, "extension_status" => { "type" => "object" },
                        "display" => DISPLAY,
                        "export_ready" => Shapes.described({ "type" => "boolean" },
                                                           "Whether a duct using this type can export."),
                        "export_blockers" => Shapes.described(Shapes.list(Shapes::TEXT),
                                                              "The codes keeping it out of an export once a duct " \
                                                              "uses it; empty when export_ready."))
      LIST_PARAMS = DefinitionLists.params(ROW).tap do |params|
        params["properties"]["ids"]["items"] = Shapes.id(KIND.id_prefix, "A Duct Type id.")
      end.freeze
      DELETE_PARAMS = Shapes.object(
        { "id" => Shapes.id(KIND.id_prefix, "The #{KIND.label} to delete."),
          "expected_values" => Shapes.expected(KIND),
          "replacement_id" => Shapes.id(KIND.id_prefix, "Another existing Duct Type to take this one's place on " \
                                                        "every duct using it, or null to leave those ducts with no " \
                                                        "type, which blocks their export.",
                                        :nullable => true) },
        :optional => %w[expected_values replacement_id]
      ).freeze
      CREATE_EXAMPLE = { "values" => { "name" => "DT-2", "shape" => "rectangular", "width_mm" => 200.0,
                                       "height_mm" => 100.0, "insulation_thickness_mm" => 50.8 } }.freeze
      UPDATE_EXAMPLE = { "id" => Shapes.example_id(KIND),
                         "values" => { "shape" => "rectangular", "width_mm" => 200.0, "height_mm" => 100.0 },
                         "expected_values" => { "shape" => "round" } }.freeze
      LIST_EXAMPLES = [{}, { "limit" => 20 }, { "fields" => %w[values export_ready] }].freeze

      module_function

      def install(feature)
        feature.record_kind(KIND)
        install_reads(feature)
        install_create_and_update(feature)
        install_duplicate_and_delete(feature)
      end

      def install_reads(feature)
        list = DuctType::Reads::LIST
        feature.query(list, :description => "One bounded page of Duct Types in id order, with export readiness.",
                            :refuses => PAGE, :params => LIST_PARAMS,
                            :result => DefinitionLists.result(ROW, :paged => true),
                            :examples => LIST_EXAMPLES) { |request| DuctType::Reads.list(request) }
        feature.query("#{PREFIX}.all", :description => "Every Duct Type with its values and export readiness, " \
                                                       "for the panel snapshot.",
                                       :response => { "bounded" => false, "prefer" => list },
                                       :refuses => [], :params => Shapes::NONE,
                                       :result => DefinitionLists.result(ROW, :paged => false),
                                       :examples => [{}]) { |request| DuctType::Reads.all(request) }
        feature.snapshot_section(PREFIX, :query => "#{PREFIX}.all")
      end

      def install_create_and_update(feature)
        feature.action("#{PREFIX}.create",
                       :description => "Create one #{KIND.label}. Unless values give them, it is a round duct of " \
                                       "diameter_mm 160 with 25.4 mm of reflective insulation at 0.04 W/mK and no " \
                                       "stored color; a rectangular one gives width_mm and height_mm and no " \
                                       "diameter. A missing or other-shape dimension refuses params.invalid.",
                       :refuses => CREATE, :params => Shapes.create(KIND), :result => Shapes::RESULT,
                       :undo_name => "Create #{KIND.label}", :preconditions => [UNIQUE, SHAPED],
                       :side_effects => "Creates one Model-owned definition.",
                       :examples => [CREATE_EXAMPLE]) do |request, proposal|
          DuctType::Operations.create(request, proposal, :values => request.params.fetch("values"),
                                                         :user_data => request.params["user_data"])
        end
        feature.action("#{PREFIX}.update",
                       :description => "Edit guarded values of one #{KIND.label}; a changed expected value refuses " \
                                       "and writes nothing. A new shape removes the old shape's dimensions and " \
                                       "must give its own; a missing or other-shape dimension refuses " \
                                       "params.invalid. A null color returns the type to its default colour.",
                       :refuses => EDIT, :params => Shapes.update(KIND), :result => Shapes::RESULT,
                       :undo_name => "Edit #{KIND.label}",
                       :preconditions => EXISTS + ["A new name: #{UNIQUE}", SHAPED],
                       :side_effects => "Updates one definition and preserves its metadata.",
                       :examples => [UPDATE_EXAMPLE]) do |request, proposal|
          params = request.params
          DuctType::Operations.update(request, proposal, :id => params.fetch("id"), :values => params.fetch("values"),
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
          DuctType::Operations.duplicate(request, proposal, :id => request.params.fetch("id"),
                                                            :name => request.params["name"])
        end
        feature.action("#{PREFIX}.delete",
                       :description => "Delete one #{KIND.label}. A type a duct still uses refuses as " \
                                       "reference.in_use unless replacement_id names another type to take its " \
                                       "place, or is null to clear it.",
                       :refuses => DELETE, :params => DELETE_PARAMS,
                       :result => Shapes.with_removed_user_data(Shapes::RESULT),
                       :undo_name => "Delete #{KIND.label}", :preconditions => EXISTS,
                       :side_effects => "Deletes one definition and its metadata and, with replacement_id or null, " \
                                        "rewrites every duct assignment naming it; Undo restores all of them.",
                       :examples => [{ "id" => Shapes.example_id(KIND) },
                                     { "id" => Shapes.example_id(KIND),
                                       "replacement_id" => "dct_Zy98Xw76Vu54" }]) do |request, proposal|
          params = request.params
          replacement = params.fetch("replacement_id", DuctType::Operations::KEEP)
          LineGroups::EdgeOperations.delete_type(LINE_GROUP, request, proposal,
                                                 :types => DuctType::Operations, :id => params.fetch("id"),
                                                 :expected_values => params.fetch("expected_values", {}),
                                                 :replacement_id => replacement)
        end
      end
    end
  end
end
