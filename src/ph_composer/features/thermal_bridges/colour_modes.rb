# frozen_string_literal: true

module PhComposer
  module ThermalBridges
    # The Thermal Bridge Type and Thermal bridge group Colour-by modes (context/EXTENSIBILITY.md, "Colour-by
    # derived geometry"). Each assigned Edge occurrence is one entry carrying the Edge as its entity, so
    # Locate, Show only this and the occurrence-path visibility walk work as for a Face, and its one world
    # segment as derived geometry, which
    # is all an Edge draws. The legend sums each row's length. An Edge naming a missing or unreadable type is
    # incomplete, so one bad record does not turn the mode off; an assignment that cannot be read is the
    # schedule's to report and draws nothing, and an unassigned Edge has no entry.
    module ColourModes
      BY_TYPE = "#{FEATURE_ID}.by_type"
      BY_GROUP = "#{FEATURE_ID}.by_group"
      # Pixels: thick enough to read over SketchUp's own Edges, which a line at the outline weight joins.
      STROKE = 5
      MISSING = "Missing type"
      # Ambient takes the Boundary mode's Outdoors hue and Perimeter its Ground hue; a group keeps its colour.
      GROUP_COLOURS = { "15-Ambient" => [64, 180, 255], "16-Perimeter" => [165, 82, 0],
                        "17-FS/BC" => [148, 103, 189] }.freeze

      module_function

      def install(feature)
        feature.colour_mode(BY_TYPE, :label => "Thermal Bridge Type", :entity_kind => "edge", :stroke => STROKE,
                                     :colours => method(:no_value_colour)) { |read| by_type(read) }
        feature.colour_mode(BY_GROUP, :label => "Thermal bridge group", :entity_kind => "edge", :stroke => STROKE,
                                      :colours => ColourBy::Palette.fixed(GROUP_COLOURS),
                                      :sort => method(:group_order)) { |read| by_group(read) }
      end

      def by_type(read)
        assigned(read) do |edge, id, type|
          entry(edge, id, type ? type.dig("values", "name") : MISSING, type,
                :colour => type && rgb(type.dig("display", "color")))
        end
      end

      # A missing type has no group, so all of them share one legend row, keyed by its own wording.
      def by_group(read)
        assigned(read) do |edge, _id, type|
          group = type ? type.dig("values", "group") : MISSING
          entry(edge, group, Type::GROUP_WORDS.fetch(group, group), type)
        end
      end

      # The groups keep the order every list of them has; anything else follows, by its own wording.
      def group_order(row)
        [Type::GROUPS.index(row.value) || Type::GROUPS.length, row.value.to_s]
      end

      # One Model walk and one read of the types per rebuild. Zones is not asked anything: an Edge outside a
      # Zone still draws, which is how a stray one is found.
      def assigned(read)
        types = DefinitionLists.read(read.engine, TYPE_KIND, read.engine.ids(TYPE_KIND)).first
                               .to_h { |record| [record.fetch("id"), Type::Reads.row(read.engine, record)] }
        tagged, _unreadable = Scan.walk(read.model)
        tagged.map do |edge|
          id = edge.record.fetch("thermal_bridge_type_id")
          yield edge, id, types[id]
        end
      end

      def entry(edge, value, label, type, colour: nil)
        world = [edge.edge.start, edge.edge.end].map { |vertex| vertex.position.transform(edge.transform) }
        ColourBy::Entry.new(:entity => edge.edge, :transform => edge.transform, :path => edge.path,
                            :value => value, :label => label, :colour => colour, :state => type ? nil : :incomplete,
                            :derived => ColourBy::Derived.new(:polygons => [], :segments => [world]),
                            :figure => ["length", length_m(edge.points_m)])
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
