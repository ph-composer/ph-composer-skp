# frozen_string_literal: true

module PhComposer
  module Mechanical
    # `ph_composer.mechanical.locate`: opens where a Mechanical finding is fixed. An item's ids open the Mechanical
    # tab on that item's table, narrowed to them; with none, Zones open on the Zones tab, checked. The preflight's
    # rows carry it (`row_locate`), each row naming the one object its finding is about.
    module Locate
      NAME = "#{FEATURE_ID}.locate"
      # A Locate names at most this many objects, as the Export pane caps a group's.
      LIMIT = 500
      # Each item kind a finding can name, with the param that opens its table. The panel table showing a kind
      # accepts its param (html/features/mechanical/).
      ITEMS = {
        Ventilators::KIND => "ventilator_ids", HotWater::Systems::KIND => "hot_water_system_ids",
        HotWater::Heaters::KIND => "hot_water_heater_ids", HotWater::Tanks::KIND => "hot_water_tank_ids"
      }.freeze
      PARAMS = Shapes.object(
        ITEMS.to_h do |kind, param|
          [param, Shapes.list(Shapes.id(kind.id_prefix, "A #{kind.label} id."),
                              :description => "#{kind.label}s to show on the Mechanical tab, their table narrowed " \
                                              "to them.").merge("maxItems" => LIMIT)]
        end.merge("zones" => Shapes.list(Zones::ZONE_REFERENCE,
                                         :description => "Zones to check on the Zones tab, when no item ids are " \
                                                         "given.").merge("maxItems" => LIMIT)),
        :optional => ITEMS.values + ["zones"]
      ).freeze

      module_function

      def install(feature)
        feature.view_command(NAME, :description => "Open where a Mechanical finding is fixed: the Mechanical tab " \
                                                   "on the table of the items named (ventilator_ids, " \
                                                   "hot_water_system_ids, hot_water_heater_ids or " \
                                                   "hot_water_tank_ids; one kind per request), narrowed to " \
                                                   "them, or, with none, the Zones tab with zones checked.",
                                   :refuses => %w[session.inactive], :params => PARAMS,
                                   :side_effects => "Opens or raises the panel on the Mechanical or the Zones tab.",
                                   :result => Shapes.object({ "opened" => { "type" => "boolean" } }),
                                   :examples => [{ "ventilator_ids" => [Shapes.example_id(Ventilators::KIND)] },
                                                 { "hot_water_tank_ids" => [Shapes.example_id(HotWater::Tanks::KIND)] },
                                                 { "zones" => [{ "zone_id" => "zon_Ab12Cd34Ef56",
                                                                 "zone_path" => [1201] }] }]) do |request|
          call(request)
        end
      end

      def call(request)
        items = request.params.slice(*ITEMS.values).reject { |_param, ids| ids.empty? }
        # The panel shows one table at a time, so a request naming two kinds would open one and drop the other.
        if items.length > 1
          raise CodedError.new("params.invalid", "Name items of one kind: #{items.keys.join(' or ')}, not both.")
        end

        if items.empty?
          request.session.open_in_panel("ph_composer.zones", "zones" => request.params.fetch("zones", []))
        else
          request.session.open_in_panel(FEATURE_ID, items)
        end
        { "opened" => true }
      end

      # Where a preflight row's object is fixed: an item on its Mechanical table, a Zone checked on the Zones tab
      # (`references` holds each Zone's occurrence reference by id); nil for anything else.
      def row_locate(object_id, references)
        kind = ITEMS.keys.find { |candidate| object_id.to_s.start_with?("#{candidate.id_prefix}_") }
        return { "name" => NAME, "params" => { ITEMS.fetch(kind) => [object_id] } } if kind

        reference = references[object_id]
        reference && { "name" => NAME, "params" => { "zones" => [reference.slice("zone_id", "zone_path")] } }
      end
    end
  end
end
