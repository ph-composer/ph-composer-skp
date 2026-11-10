# frozen_string_literal: true

require_relative "../refuses"

module PhComposer
  module Windows
    # Bounded reads of one definition's parts, for a definition larger than one reply: a Window Type's
    # elements with their derived thermal and installation facts, and the elements that use a product.
    # Every derived value comes from the row `types.list` builds (Snapshot.type, which runs
    # Thermal.calculate and Installs.topology_facts) or from Graph.uses, so a page never computes a rule
    # of its own. Each pages by position (shell/pages.rb) bound to the revision.
    module PartRegistration
      NUM = InventoryRegistration::NUM
      THERMAL = InventoryRegistration::THERMAL
      TYPE_THERMAL = THERMAL.merge("required" => THERMAL.fetch("required") - ["elements"],
                                   "properties" => THERMAL.fetch("properties").reject { |key, _| key == "elements" })
      TYPE = Shapes.object({
        "id" => Shapes::TEXT, "name" => Shapes::TEXT,
        "rows_m" => Shapes.list(NUM.merge("x-unit" => "m")), "columns_m" => Shapes.list(NUM.merge("x-unit" => "m")),
        "width_m" => NUM.merge("x-unit" => "m"), "height_m" => NUM.merge("x-unit" => "m"),
        "install_depth_m" => NUM.merge("x-unit" => "m"), "complete" => { "type" => "boolean" },
        "copy_key" => Shapes.described(Shapes::TEXT, "Equal on two Types when an installation copy between them is " \
                                                     "accepted; opaque."),
        "thermal" => Shapes.described(TYPE_THERMAL, "The Type's totals, without the per-element results its rows " \
                                                    "carry."),
        "findings" => Shapes.described(Shapes::FINDINGS, "The Type's findings that name no element."),
        "element_count" => { "type" => "integer", "minimum" => 0 }
      })
      ELEMENT = Shapes.object({
        "index" => { "type" => "integer", "minimum" => 0 },
        "element" => Shapes.described(Types::ELEMENT, "The element as stored."),
        "thermal" => InventoryRegistration::ELEMENT_THERMAL.merge("type" => %w[object null],
                                                                  "description" => "Null for an empty element."),
        "install_edges" => Shapes.object(Types::SIDES.to_h { |side| [side, InventoryRegistration::INSTALL_EDGE] })
                                 .merge("type" => %w[object null],
                                        "description" => "Each edge's classification and whether an installation " \
                                                         "can be painted there; null for an empty element."),
        "copy_slot" => Shapes.described(Shapes::TEXT, "This element's slot in an installation copy."),
        "findings" => Shapes.described(Shapes::FINDINGS, "The Type's findings that name this element.")
      })
      PAGE = { "next_cursor" => Pages::NEXT_CURSOR, "total" => Pages::TOTAL }.freeze
      UNREADABLE = { "type" => "integer", "minimum" => 0 }.freeze
      REFUSES = (Refuses::PAGE + %w[record.unreadable target.not_found]).freeze

      module_function

      def install(feature)
        query(feature, "#{FEATURE_ID}.types.elements.list",
              "One bounded page of a Window Type's elements in stored order, each with its thermal result, " \
              "installation edges and copy slot, beside the Type's totals and findings.",
              { "type_id" => Shapes.id("wnt", "The Window Type to read.") },
              { "type" => TYPE, "elements" => Shapes.list(ELEMENT) },
              { "type_id" => "wnt_Ab12Cd34Ef56" }) { |request| elements(request) }
        Products::KINDS.each do |collection, kind|
          query(feature, "#{FEATURE_ID}.#{collection}.uses.list",
                "One bounded page of what uses a #{kind.label}: a #{collection} row's uses, in its order.",
                { "id" => Shapes.id(kind.id_prefix, "The #{kind.label} to read.") },
                { "id" => Shapes::TEXT, "uses" => Shapes.list(InventoryRegistration::USE),
                  "unreadable" => UNREADABLE.merge("description" => "Window Types that cannot be read, so " \
                                                                    "whether they use it is unknown.") },
                { "id" => "#{kind.id_prefix}_Ab12Cd34Ef56" }) { |request| uses(request, collection) }
        end
      end

      def query(feature, name, description, properties, result, example, &read)
        feature.query(name, :description => description, :refuses => REFUSES,
                            :params => Shapes.object(properties.merge("limit" => Pages::LIMIT,
                                                                      "cursor" => Pages::CURSOR),
                                                     :optional => Pages::PAGE_KEYS),
                            :result => Shapes.object(result.merge(PAGE)),
                            :examples => [example, example.merge("limit" => 20)], &read)
      end

      def elements(request)
        record = request.engine.find(TYPE_KIND, request.params.fetch("type_id"))
        row = Snapshot.type(request.engine.view(TYPE_KIND, record), record, Snapshot.products_by_collection(request),
                            Settings.read(request.model))
        display = row.fetch("display")
        thermal = display.fetch("thermal")
        topology = display.fetch("install_topology")
        by_element = thermal.fetch("elements").to_h { |element| [element.fetch("id"), element] }
        findings = row.fetch("findings").group_by { |finding| finding["element_id"] }
        rows = record.fetch("elements").each_with_index.map do |element, index|
          id = element.fetch("id")
          { "index" => index, "element" => element, "thermal" => by_element[id],
            "install_edges" => topology.fetch("edges")[id], "copy_slot" => topology.fetch("copy_slots").fetch(id),
            "findings" => findings.fetch(id, []) }
        end
        page, next_cursor = Pages.bounded(request, "#{FEATURE_ID}.types.elements.list", rows,
                                          :key => ->(element) { [element.fetch("index")] })
        { "type" => type_summary(record, display, findings.fetch(nil, [])), "elements" => page,
          "next_cursor" => next_cursor, "total" => rows.length }
      end

      def type_summary(record, display, findings)
        { "id" => record.fetch("id"), "name" => record.fetch("name"), "rows_m" => record.fetch("rows_m"),
          "columns_m" => record.fetch("columns_m"), "width_m" => display.fetch("width_m"),
          "height_m" => display.fetch("height_m"), "install_depth_m" => display.fetch("install_depth_m"),
          "complete" => display.fetch("complete"), "copy_key" => display.fetch("install_topology").fetch("copy_key"),
          "thermal" => display.fetch("thermal").reject { |key, _value| key == "elements" }, "findings" => findings,
          "element_count" => record.fetch("elements").length }
      end

      # A product row's uses, as Snapshot.product builds them, a page at a time by position.
      def uses(request, collection)
        kind = Products::KINDS.fetch(collection)
        id = request.params.fetch("id")
        record = request.engine.find(kind.id, id)
        settings = Settings.read(request.model)
        types, unreadable = DefinitionLists.read(request.engine, TYPE_KIND, request.engine.ids(TYPE_KIND))
        product = Snapshot.product(request.engine.view(kind.id, record), record, kind,
                                   Graph.uses(types, settings.fetch("default_psi_install_id")), settings)
        rows = product.fetch("uses").each_with_index.map { |use, index| [index, use] }
        page, next_cursor = Pages.bounded(request, "#{FEATURE_ID}.#{collection}.uses.list", rows,
                                          :key => ->(row) { [row.first] })
        { "id" => id, "uses" => page.map(&:last), "unreadable" => unreadable.length, "next_cursor" => next_cursor,
          "total" => rows.length }
      end
    end
  end
end
