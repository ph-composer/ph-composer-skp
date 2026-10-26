# frozen_string_literal: true

module PhComposer
  module ThermalBridges
    # The Thermal bridges Colour-by mode (context/EXTENSIBILITY.md, "Colour-by derived geometry"). Each assigned
    # Edge occurrence is one entry carrying the Edge as its entity, so Locate, Show only this and the
    # occurrence-path visibility walk work as for a Face, and its one world segment as derived geometry, which
    # is all an Edge draws. The legend sums each type's length. An Edge naming a missing or unreadable type is
    # incomplete, so one bad record does not turn the mode off; an assignment that cannot be read is the
    # schedule's to report and draws nothing, and an unassigned Edge has no entry.
    module ColourModes
      BY_TYPE = "#{FEATURE_ID}.by_type"
      # Pixels: thick enough to read over SketchUp's own Edges, which a line at the outline weight joins.
      STROKE = 5
      MISSING = "Missing type"

      module_function

      def install(feature)
        feature.colour_mode(BY_TYPE, :label => "Thermal bridges", :entity_kind => "edge", :stroke => STROKE,
                                     :colours => method(:no_value_colour)) { |read| entries(read) }
      end

      # One Model walk and one read of the types per rebuild. Zones is not asked anything: an Edge outside a
      # Zone still draws, which is how a stray one is found.
      def entries(read)
        types = Type::Reads.entries(read.engine, read.engine.ids(TYPE_KIND)).to_h
                           .select { |_id, row| row.key?("values") }
        tagged, _unreadable = Scan.walk(read.model)
        tagged.map do |edge|
          id = edge.record.fetch("thermal_bridge_type_id")
          type = types[id]
          world = [edge.edge.start, edge.edge.end].map { |vertex| vertex.position.transform(edge.transform) }
          ColourBy::Entry.new(:entity => edge.edge, :transform => edge.transform, :path => edge.path,
                              :value => id, :label => type ? type.dig("values", "name") : MISSING,
                              :colour => type && rgb(type.dig("display", "color")), :state => type ? nil : :incomplete,
                              :derived => ColourBy::Derived.new(:polygons => [], :segments => [world]),
                              :figure => ["length", length_m(edge.points_m)])
        end
      end

      def length_m(points)
        Math.sqrt(points.first.zip(points.last).sum { |from, to| (to - from)**2 })
      end

      # "#RRGGBB" as [r, g, b].
      def rgb(color)
        color.delete_prefix("#").scan(/../).map { |component| component.to_i(16) }
      end

      # A type's colour belongs to its record, so it comes on each entry; the id alone has none.
      def no_value_colour(_value)
        nil
      end
    end
  end
end
