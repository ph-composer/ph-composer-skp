# frozen_string_literal: true

module PhComposer
  module Windows
    module InventoryRegistration
      NUM = { "type" => %w[number null] }.freeze
      EDGE_INSTALL = Shapes.object({ "source" => Shapes::TEXT, "id" => { "type" => %w[string null] },
                                     "psi_w_mk" => NUM.merge("x-unit" => "W/mK") })
      EDGE = Shapes.object({ "side" => Shapes::TEXT, "length_m" => NUM.merge("x-unit" => "m"),
                             "install" => EDGE_INSTALL, "frame_area_m2" => NUM.merge("x-unit" => "m2"),
                             "glass_edge_m" => NUM.merge("x-unit" => "m"),
                             "h_frame_w_k" => NUM.merge("x-unit" => "W/K"),
                             "h_spacer_w_k" => NUM.merge("x-unit" => "W/K") },
                           :optional => %w[frame_area_m2 glass_edge_m h_frame_w_k h_spacer_w_k])
      THERMAL_FINDING = Shapes.object({ "code" => Shapes::TEXT, "message" => Shapes::TEXT, "side" => Shapes::TEXT },
                                      :optional => %w[side])
      ELEMENT_THERMAL = Shapes.object({ "id" => Shapes::TEXT, "area_m2" => NUM.merge("x-unit" => "m2"),
                                        "edges" => Shapes.list(EDGE), "findings" => Shapes.list(THERMAL_FINDING),
                                        "h_construction_w_k" => NUM.merge("x-unit" => "W/K"),
                                        "h_install_w_k" => NUM.merge("x-unit" => "W/K"),
                                        "glazing_area_m2" => NUM.merge("x-unit" => "m2"),
                                        "frame_area_m2" => NUM.merge("x-unit" => "m2"),
                                        "h_glazing_w_k" => NUM.merge("x-unit" => "W/K"), "g_value" => NUM,
                                        "uw_w_m2k" => NUM.merge("x-unit" => "W/m2K"),
                                        "u_effective_w_m2k" => NUM.merge("x-unit" => "W/m2K"),
                                        "complete" => { "type" => "boolean" } },
                                      :optional => %w[glazing_area_m2 frame_area_m2 h_glazing_w_k])
      THERMAL = Shapes.object({ "elements" => Shapes.list(ELEMENT_THERMAL), "findings" => Shapes.list(THERMAL_FINDING),
                                "area_m2" => NUM.merge("x-unit" => "m2"),
                                "empty_area_m2" => NUM.merge("x-unit" => "m2"),
                                "h_construction_w_k" => NUM.merge("x-unit" => "W/K"),
                                "h_install_w_k" => NUM.merge("x-unit" => "W/K"),
                                "uw_w_m2k" => NUM.merge("x-unit" => "W/m2K"),
                                "u_effective_w_m2k" => NUM.merge("x-unit" => "W/m2K"),
                                "complete" => { "type" => "boolean" } },
                              :optional => %w[area_m2 empty_area_m2 h_construction_w_k h_install_w_k])
      INSTALL_EDGE = Shapes.object({ "classification" => { "type" => "string", "enum" => %w[perimeter shared partial] },
                                     "paintable" => { "type" => "boolean" } })
      # Derived installation facts (Installs.topology_facts): never stored and never accepted by a write.
      INSTALL_TOPOLOGY = Shapes.object(
        { "edges" => { "type" => "object", "description" => "Each non-empty element's four edges, by element id.",
                       "additionalProperties" => Shapes.object(Types::SIDES.to_h { |side| [side, INSTALL_EDGE] }) },
          "copy_key" => Shapes.described(Shapes::TEXT, "Equal on two Types when an installation copy between " \
                                                       "them is accepted; opaque."),
          "copy_slots" => { "type" => "object", "description" => "Each element's slot in an installation copy, " \
                                                                 "by element id; equal slots receive each other's.",
                            "additionalProperties" => Shapes::TEXT } }
      )
      DISPLAY = Shapes.object({ "thermal" => THERMAL, "width_m" => NUM.merge("x-unit" => "m"),
                                "height_m" => NUM.merge("x-unit" => "m"),
                                "install_depth_m" => NUM.merge("x-unit" => "m"),
                                "complete" => { "type" => "boolean" }, "install_topology" => INSTALL_TOPOLOGY })
      USE = Shapes.object(%w[kind type_id element_id side name].to_h { |key| [key, Shapes::TEXT] },
                          :optional => %w[type_id element_id side])
      # What a Window Type row adds to its record view, and what a product row adds.
      TYPE_ROW = { "display" => DISPLAY }.freeze
      PRODUCT_ROW = { "uses" => Shapes.list(USE), "use_count" => { "type" => "integer", "minimum" => 0 },
                      "element_use_count" => { "type" => "integer", "minimum" => 0 } }.freeze

      module_function

      def install(feature)
        Products::KINDS.each do |collection, kind|
          declare(feature, collection, kind, PRODUCT_ROW) do |request, paged|
            Snapshot.products(request, collection, :paged => paged)
          end
        end
        declare(feature, "types", Types::KIND, TYPE_ROW) { |request, paged| Snapshot.types(request, :paged => paged) }
      end

      # The list and all queries for one collection; `read` takes the request and whether to page.
      def declare(feature, collection, kind, additions, &read)
        prefix = "#{FEATURE_ID}.#{collection}"
        row = Shapes.with(Shapes.view(kind), additions)
        feature.query("#{prefix}.list", :description => "A bounded page of #{collection} with display findings.",
                                        :refuses => Refuses::PAGE + %w[record.unreadable],
                                        :params => DefinitionLists.params(row),
                                        :result => DefinitionLists.result(row, :paged => true),
                                        :examples => [{}, { "limit" => 20 }, { "fields" => %w[values] }]) do |request|
          read.call(request, true)
        end
        feature.query("#{prefix}.all",
                      :response => { "bounded" => false, "prefer" => "#{prefix}.list" },
                      :description => "The complete #{collection} inventory for the panel snapshot.",
                      :refuses => %w[record.unreadable],
                      :params => Shapes::NONE, :result => DefinitionLists.result(row, :paged => false),
                      :examples => [{}]) do |request|
          read.call(request, false)
        end
        feature.snapshot_section(prefix, :query => "#{prefix}.all")
      end
    end
  end
end
