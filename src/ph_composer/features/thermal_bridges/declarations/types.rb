# frozen_string_literal: true

module PhComposer
  module ThermalBridges
    # What the Thermal Bridge Type catalog registers: the kind, two reads, the panel's section and four
    # actions. Every write goes through the record engine, one native Undo step each.
    module TypeRegistration
      PREFIX = "#{FEATURE_ID}.types".freeze
      # The codes beyond each kind's common set (context/CONTRACTS.md, "Outcomes and codes").
      PAGE = %w[query.cursor_expired query.limit_invalid].freeze
      CREATE = %w[record.unreadable validation.failed].freeze
      EDIT = %w[record.unreadable reference.invalid target.changed target.not_found validation.failed].freeze
      DUPLICATE = %w[copy.rule_missing extension.invalid record.unreadable reference.invalid target.not_found
                     validation.failed].freeze
      # A delete scans every record for references to it, so an unreadable envelope anywhere refuses it.
      DELETE = %w[copy.rule_missing record.unreadable reference.in_use target.changed target.not_found
                  validation.failed].freeze
      CREATE_EXAMPLE = { "values" => { "name" => "Parapet", "psi_w_mk" => 0.12 } }.freeze

      DISPLAY = Shapes.object({ "color" => Shapes.described(SchemaShapes::HEX_COLOUR,
                                                            "The stored color, or the default one for the id.") })
      ROW = Shapes.with(Shapes.view(Type::KIND),
                        "display" => DISPLAY,
                        "export_ready" => Shapes.described({ "type" => "boolean" },
                                                           "Whether an Edge using this type can export."),
                        "export_blockers" => Shapes.described(Shapes.list(Shapes::TEXT),
                                                              "The codes keeping it out of an export once an Edge " \
                                                              "uses it; empty when export_ready."))

      module_function

      def install(feature)
        feature.record_kind(Type::KIND)
        install_reads(feature)
        install_create_and_update(feature)
        install_duplicate_and_delete(feature)
      end

      def result(paged:)
        properties = { "records" => Shapes.list(ROW), "unreadable" => Shapes::UNREADABLE }
        properties.merge!("next_cursor" => Pages::NEXT_CURSOR, "total" => Pages::TOTAL) if paged
        Shapes.object(properties)
      end

      def install_reads(feature)
        feature.query("#{PREFIX}.list", :description => "One bounded page of Thermal Bridge Types, with export " \
                                                        "readiness.",
                                        :refuses => PAGE, :params => Shapes.list_params,
                                        :result => result(:paged => true),
                                        :examples => [{}, { "limit" => 20 }]) { |request| Type::Reads.list(request) }
        feature.query("#{PREFIX}.all", :description => "Every Thermal Bridge Type, for the panel snapshot.",
                                       :response => { "bounded" => false, "prefer" => "#{PREFIX}.list" },
                                       :refuses => [], :params => Shapes::NONE, :result => result(:paged => false),
                                       :examples => [{}]) { |request| Type::Reads.all(request) }
        feature.snapshot_section(PREFIX, :query => "#{PREFIX}.all")
      end

      def install_create_and_update(feature)
        kind = Type::KIND
        feature.action("#{PREFIX}.create",
                       :description => "Create one #{kind.label}. The group starts at 15-Ambient and the psi-value " \
                                       "empty unless values give them.",
                       :refuses => CREATE, :params => Shapes.create(kind), :result => Shapes::RESULT,
                       :undo_name => "Create #{kind.label}", :side_effects => "Creates one Model-owned definition.",
                       :examples => [CREATE_EXAMPLE]) do |request, proposal|
          Type::Operations.create(request, proposal, :values => request.params.fetch("values"),
                                                     :user_data => request.params["user_data"])
        end
        feature.action("#{PREFIX}.update",
                       :description => "Edit guarded values of one #{kind.label}; a changed expected value refuses.",
                       :refuses => EDIT, :params => Shapes.update(kind), :result => Shapes::RESULT,
                       :undo_name => "Edit #{kind.label}",
                       :side_effects => "Updates one definition and preserves its metadata.",
                       :examples => [{ "id" => Shapes.example_id(kind), "values" => { "psi_w_mk" => -0.02 },
                                       "expected_values" => { "psi_w_mk" => nil } }]) do |request, proposal|
          params = request.params
          Type::Operations.update(request, proposal,
                                  :id => params.fetch("id"), :values => params.fetch("values"),
                                  :expected_values => params.fetch("expected_values"),
                                  :user_data => params["user_data"])
        end
      end

      def install_duplicate_and_delete(feature)
        kind = Type::KIND
        duplicate = Shapes.object(
          { "id" => Shapes.id(kind.id_prefix, "The #{kind.label} to copy."),
            "name" => { "type" => "string", "minLength" => 1,
                        "description" => "The copy's name; \"<name> (copy)\" when absent. Names are unique." },
            "copy_datasheets" => { "type" => "boolean",
                                   "description" => "Keep the datasheet links on the copy; false when absent." } },
          :optional => %w[name copy_datasheets]
        )
        feature.action("#{PREFIX}.duplicate",
                       :description => "Duplicate one #{kind.label} with a new id and source derived.",
                       :refuses => DUPLICATE, :params => duplicate, :result => Shapes::RESULT,
                       :undo_name => "Duplicate #{kind.label}",
                       :side_effects => "Creates one definition; user_data is copied.",
                       :examples => [{ "id" => Shapes.example_id(kind) }]) do |request, proposal|
          params = request.params
          Type::Operations.duplicate(request, proposal, :id => params.fetch("id"), :name => params["name"],
                                                        :copy_datasheets => params.fetch("copy_datasheets", false))
        end
        delete = Shapes.object({ "id" => Shapes.id(kind.id_prefix, "The #{kind.label} to delete."),
                                 "expected_values" => Shapes.expected(kind) }, :optional => ["expected_values"])
        feature.action("#{PREFIX}.delete",
                       :description => "Delete one #{kind.label}; a type still in use refuses.",
                       :refuses => DELETE, :params => delete, :result => Shapes::RESULT,
                       :undo_name => "Delete #{kind.label}", :side_effects => "Deletes one definition.",
                       :examples => [{ "id" => Shapes.example_id(kind) }]) do |request, proposal|
          Type::Operations.delete(request, proposal, :id => request.params.fetch("id"),
                                                     :expected_values => request.params.fetch("expected_values", {}))
        end
      end
    end
  end
end
