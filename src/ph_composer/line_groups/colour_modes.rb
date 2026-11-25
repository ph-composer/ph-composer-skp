# frozen_string_literal: true

module PhComposer
  module LineGroups
    # What every line group's Colour-by modes draw alike (context/EXTENSIBILITY.md, "Colour-by derived geometry"): each
    # assigned Edge occurrence is one entry carrying its Edge as the entity and its one world segment as derived
    # geometry, at the stroke weight every edge feature draws with, and a legend figure of its length. A record that
    # cannot be read is the schedule's to report and draws nothing, and a line with no assignment has no entry.
    module ColourModes
      # Pixels: the Edge weight every edge feature's Colour-by mode draws with, so they read alike.
      STROKE = 5

      module_function

      # One Model walk and one read of the types per rebuild: every readable assigned Edge occurrence with its record
      # and type, or nil for a missing one. While a repeated parent's edit context is open, SketchUp rebases its shared
      # child transforms, so an Edge in shared storage could draw at another placement's position
      # (context/SKETCHUP_HOST_BEHAVIOR.md, "Observers and edit contexts"): those are withheld until it closes.
      def edges(spec, read)
        types = DefinitionLists.read(read.engine, spec.type_kind, read.engine.ids(spec.type_kind)).first
                               .to_h { |record| [record.fetch("id"), record] }
        groups, = Scan.walk(spec, read.model)
        rebased = Array(read.model.active_path).any? { |entity| repeated?(entity) }
        groups.reject { |occurrence| rebased && occurrence.shared }.flat_map do |occurrence|
          occurrence.edges.filter_map do |edge|
            record, problem = LineGroups.read(edge, spec.edge_store)
            next if problem || spec.edge_record_kind.problems(record).any?

            yield edge, occurrence, record, types[record.fetch(spec.type_key)]
          end
        end
      end

      # A component, or a Group whose definition another Group shares: opening it rebases its children.
      def repeated?(entity)
        return true if entity.is_a?(Sketchup::ComponentInstance)

        definition = entity.respond_to?(:definition) ? entity.definition : nil
        definition.respond_to?(:instances) && definition.instances.length > 1
      end

      # One Edge occurrence's entry; its legend figure is its length times `count`, the lines it stands for.
      def entry(edge, occurrence, value, label, complete, colour: nil, count: 1)
        world = [edge.start, edge.end].map { |vertex| vertex.position.transform(occurrence.transform) }
        ColourBy::Entry.new(:entity => edge, :transform => occurrence.transform,
                            :path => occurrence.path + [edge.persistent_id], :value => value, :label => label,
                            :colour => colour, :state => complete ? nil : :incomplete,
                            :derived => ColourBy::Derived.new(:polygons => [], :segments => [world]),
                            :figure => ["length", length_m(world) * count])
      end

      def length_m(points)
        metres = points.map { |point| FaceCapture.point_m(point) }
        Math.sqrt(metres.first.zip(metres.last).sum { |from, to| (to - from)**2 })
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
