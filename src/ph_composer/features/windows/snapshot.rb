# frozen_string_literal: true

module PhComposer
  module Windows
    # One detached inventory projection, with authored storage kept distinct from effective defaults.
    module Snapshot
      module_function

      # Every readable record of `kind`, in id order; an unreadable one is skipped, so a context menu
      # or Colour-by mode built from them keeps working around it.
      def readable(engine, kind)
        DefinitionLists.read(engine, kind.id, engine.ids(kind.id).sort).first
      end

      # The list query's page or the all query's whole inventory, each row as the block builds it.
      def rows(request, query, kind, paged, &row)
        paged ? DefinitionLists.list(request, query, kind.id, &row) : DefinitionLists.all(request.engine, kind.id, &row)
      end

      # Every product by collection, then id: what a Type's thermal values and findings read.
      def products_by_collection(request)
        Products::KINDS.to_h do |collection, kind|
          rows = DefinitionLists.read(request.engine, kind.id, request.engine.ids(kind.id)).first
          [collection, rows.to_h { |row| [row.fetch("id"), row] }]
        end
      end

      def types(request, paged: true)
        settings = Settings.read(request.model)
        products = products_by_collection(request)
        rows(request, "#{FEATURE_ID}.types.list", Types::KIND, paged) do |record|
          type(request.engine.view(TYPE_KIND, record), record, products, settings)
        end
      end

      def products(request, collection, paged: true)
        kind = Products::KINDS.fetch(collection)
        settings = Settings.read(request.model)
        types = DefinitionLists.read(request.engine, TYPE_KIND, request.engine.ids(TYPE_KIND)).first
        uses = Graph.uses(types, settings.fetch("default_psi_install_id"))
        rows(request, "#{FEATURE_ID}.#{collection}.list", kind, paged) do |record|
          product(request.engine.view(kind.id, record), record, kind, uses, settings)
        end
      end

      def type(view, record, products, settings)
        thermal = Thermal.calculate(record, products, settings.fetch("default_psi_install_id"))
        findings = product_findings(record, products)
        findings.concat(thermal.fetch("findings"))
        thermal.fetch("elements").each do |element|
          element_id = element.fetch("id")
          findings.concat(element.fetch("findings").map { |finding| finding.merge("element_id" => element_id) })
        end
        default_id = settings.fetch("default_psi_install_id")
        if default_id && !products.fetch("psi_install_types").key?(default_id)
          findings << { "code" => "window_type.default_install_dangling",
                        "message" => "The Model default Psi-Install Type is missing." }
        end
        view.merge("findings" => findings, "display" => {
          "thermal" => thermal, "width_m" => dimensions(record.fetch("columns_m")),
          "height_m" => dimensions(record.fetch("rows_m")),
          "install_depth_m" => record.fetch("install_depth_m", settings.fetch("default_install_depth_m")),
          "complete" => thermal.fetch("complete"), "install_topology" => Installs.topology_facts(record)
        })
      end

      def dimensions(bands)
        bands.any?(&:nil?) ? nil : bands.sum
      end

      # Each slot an element assigns: the product collection it names, the side, and the product id.
      def product_slots(element)
        [["glazings", "glazing", element["glazing_id"]]] +
          element.fetch("frames").map { |side, id| ["frames", side, id] } +
          element.fetch("installs").map { |side, id| ["psi_install_types", side, id] }
      end

      def product_findings(record, products)
        record.fetch("elements").flat_map do |element|
          product_slots(element).filter_map do |collection, side, id|
            next unless id && !products.fetch(collection).key?(id)

            { "code" => "window_type.product_dangling", "message" => "#{side}: the assigned product is missing.",
              "element_id" => element.fetch("id"), "side" => side, "product_id" => id }
          end
        end
      end

      def product(view, record, kind, uses, settings)
        rows = DeepCopy.call(uses[[kind.id, record.fetch("id")]])
        if kind.id == PSI_INSTALL_KIND && settings.fetch("default_psi_install_id") == record.fetch("id")
          rows << { "kind" => "model_default", "name" => "Model default" }
        end
        view.merge("findings" => [], "uses" => rows, "use_count" => rows.length,
                   "element_use_count" => rows.filter_map { |row|
                                            [row["type_id"], row["element_id"]] if row["element_id"]
                                          }.uniq.length)
      end
    end
  end
end
