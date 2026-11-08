# frozen_string_literal: true

module PhComposer
  module ColourBy
    # The drawing one rebuild assembles: the legend rows, each row's entities and framing points, and
    # the batches the overlay draws. It owns those buffers while entries are added. The service reads
    # them only once every entry is in, so a projection or tessellation failure leaves no partial
    # drawing behind.
    #
    # `visibility` and `set_aside` are the service's occurrence rules for this rebuild: what the viewport
    # hides, and which rows isolation mutes. `in_filter` is the session's occurrence mask.
    class Drawing
      attr_reader :unclassified_outlines, :unclassified_triangles

      def initialize(visibility:, set_aside:, in_filter:)
        @visibility = visibility
        @set_aside = set_aside
        @in_filter = in_filter
        @rows = {}
        @entities = batches
        @frames = batches
        @fills = batches
        @outlines = batches
        @lines = batches
        @unclassified_outlines = []
        @unclassified_triangles = []
      end

      # Counts the entry in its legend row and adds what it draws: its entity's geometry, its derived
      # shapes, or both.
      def add(entry, state, colour)
        key = [entry.value, state]
        row = @rows[key] ||= Row.new(:value => entry.value, :label => Legend.label(entry), :colour => colour,
                                     :count => 0, :state => state)
        row.count += 1
        Legend.add_figure(row, entry.figure)
        @entities[key] << [entry.entity, entry.transform] if entry.entity
        add_derived(entry, state, colour) if entry.derived
        return unless entry.entity && @visibility.visible?(entry.path, entry.entity)

        # A set-aside or filtered-out Face is left to SketchUp's own drawing: nothing is painted over it.
        return if @set_aside.call(entry.value, state)

        triangles, segments = Tessellation.partition(entry.entity, entry.transform, entry.path) do |path|
          @in_filter.call(path) && !@visibility.edit_hidden?(path)
        end
        if state == :unclassified
          @unclassified_outlines.concat(segments) unless entry.hatch_outline == false
          @unclassified_triangles.concat(triangles)
        else
          @fills[colour].concat(triangles) unless triangles.empty?
          @outlines[colour].concat(segments) unless segments.empty?
        end
      end

      def rows
        @rows.values
      end

      # Each finished batch map is a plain Hash: the default block is only for building, and a reader
      # must not create a batch by asking for one.
      def entities
        settled(@entities)
      end

      def frames
        settled(@frames)
      end

      def fills
        settled(@fills)
      end

      def outlines
        settled(@outlines)
      end

      def lines
        settled(@lines)
      end

      private

      def batches
        Hash.new { |table, key| table[key] = [] }
      end

      def settled(batches)
        batches.each_with_object({}) { |(key, points), table| table[key] = points }
      end

      # An entry's shapes: hidden with its occurrence, filtered and set aside as a whole, and otherwise
      # drawn in its colour, or with the hatch when it is unclassified.
      def add_derived(entry, state, colour)
        triangles, outlines, segments = Tessellation.derived(entry.derived)
        @frames[[entry.value, state]].concat(triangles + segments)
        # With an entity, the path must name it, as for the entity's own geometry; without one, the path
        # names the occurrence the shapes belong to.
        visible = if entry.entity
                    @visibility.visible?(entry.path, entry.entity) && !Tessellation.skipped?(entry.entity)
                  else
                    @visibility.path_visible?(entry.path)
                  end
        return unless visible
        return if @set_aside.call(entry.value, state) || !@in_filter.call(entry.path)

        if state == :unclassified
          @unclassified_triangles.concat(triangles)
          @unclassified_outlines.concat(outlines + segments) unless entry.hatch_outline == false
        else
          @fills[colour].concat(triangles) unless triangles.empty?
          @lines[colour].concat(outlines + segments) unless outlines.empty? && segments.empty?
        end
      end
    end
  end
end
