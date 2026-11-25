# frozen_string_literal: true

module PhComposer
  module Piping
    # The pipe role and Pipe Type Colour-by modes (context/EXTENSIBILITY.md, "Colour-by derived geometry"). Each
    # pipe occurrence is one entry carrying its Edge as the entity and its one world segment as derived geometry, at
    # the stroke weight every edge feature draws with. The legend sums each row's drawn length, so a role's row
    # reads what the schedule's totals by role read. A pipe naming a missing or unreadable type is incomplete in the
    # type mode; a record that cannot be read is the schedule's to report and draws nothing, and a line in a Piping
    # group with no assignment has no entry.
    module ColourModes
      BY_ROLE = "#{FEATURE_ID}.by_role".freeze
      BY_TYPE = "#{FEATURE_ID}.by_type".freeze
      # Pixels: the Edge weight every edge feature's Colour-by mode draws with, so they read alike.
      STROKE = 5
      MISSING = "Missing type"
      ROLE_WORDS = { "trunk" => "Trunk", "branch" => "Branch", "twig" => "Twig",
                     "recirculation" => "Recirculation" }.freeze
      ROLE_COLOURS = { "trunk" => [31, 119, 180], "branch" => [44, 160, 44], "twig" => [255, 127, 14],
                       "recirculation" => [148, 103, 189] }.freeze

      module_function

      def install(feature)
        feature.colour_mode(BY_ROLE, :label => "Pipe role", :entity_kind => "edge", :stroke => STROKE,
                                     :colours => ColourBy::Palette.fixed(ROLE_COLOURS),
                                     :sort => method(:role_order)) { |read| by_role(read) }
        feature.colour_mode(BY_TYPE, :label => "Pipe Type", :entity_kind => "edge", :stroke => STROKE,
                                     :colours => method(:no_value_colour)) { |read| by_type(read) }
      end

      def by_role(read)
        pipes(read) do |edge, occurrence, record, _type|
          role = record.fetch("role")
          entry(edge, occurrence, role, ROLE_WORDS.fetch(role), true)
        end
      end

      def by_type(read)
        pipes(read) do |edge, occurrence, record, type|
          entry(edge, occurrence, record.fetch("pipe_type_id"), type ? type.fetch("name") : MISSING, type,
                :colour => type && rgb(PipeType.color(type)))
        end
      end

      # The roles keep the order every list of them has.
      def role_order(row)
        [Assignment::ROLES.index(row.value) || Assignment::ROLES.length, row.value.to_s]
      end

      # One Model walk and one read of the types per rebuild: every readable pipe occurrence with its record and
      # Pipe Type, or nil for a missing one.
      def pipes(read)
        types = DefinitionLists.read(read.engine, PIPE_TYPE_KIND, read.engine.ids(PIPE_TYPE_KIND)).first
                               .to_h { |record| [record.fetch("id"), record] }
        groups, = Scan.walk(read.model)
        groups.flat_map do |occurrence|
          occurrence.edges.filter_map do |edge|
            record, problem = Group.read(edge, Assignment::STORE)
            next if problem || Assignment::RECORD_KIND.problems(record).any?

            yield edge, occurrence, record, types[record.fetch("pipe_type_id")]
          end
        end
      end

      def entry(edge, occurrence, value, label, complete, colour: nil)
        world = [edge.start, edge.end].map { |vertex| vertex.position.transform(occurrence.transform) }
        ColourBy::Entry.new(:entity => edge, :transform => occurrence.transform,
                            :path => occurrence.path + [edge.persistent_id], :value => value, :label => label,
                            :colour => colour, :state => complete ? nil : :incomplete,
                            :derived => ColourBy::Derived.new(:polygons => [], :segments => [world]),
                            :figure => ["length", length_m(world)])
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
