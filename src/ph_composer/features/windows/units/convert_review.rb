# frozen_string_literal: true

require_relative "convert_rectangles"
require_relative "convert_sources"
require_relative "convert_hosts"
require_relative "read_context"
require_relative "../placement/plane"
require_relative "../placement/polygons"

module PhComposer
  module Windows
    module Units
      # What Convert to Window Type would take from a selection of hand-drawn rectangles, and why it leaves
      # the rest out. Writes nothing. Rectangles sharing an Edge are one group and one Type (W7-5), and each
      # group names the Types already of its size (W7-6).
      module ConvertReview
        # Two layouts of one size within this are the same Type (W7-6).
        TYPE_MATCH_TOLERANCE_M = 0.001
        OUTLINE_DIGITS = 6
        METRES_PER_INCH = 0.0254

        module_function

        QUERY = "#{FEATURE_ID}.units.convert_review"
        DETAIL = "#{QUERY}.detail"
        PARTS = %w[groups left_out].freeze

        def read(request, paths)
          sources, left_out = ConvertSources.read(request.model, paths)
          built, unbuilt = assess(request, sources)
          { "groups" => rows(built, types(request)),
            "left_out" => (left_out + unbuilt).sort_by { |row| row.fetch("paths").first } }
        end

        # The review without its two lists that grow with the selection, a group's sources and a left-out
        # row's paths: each is counted and digested (Fragments.summary) in their place, and DETAIL reads it.
        # A group's sources digest is the handle of what was reviewed: the same review read again answers
        # the same digest until the geometry changes, and `units.convert` still takes the whole group.
        def compact(review)
          { "groups" => review.fetch("groups").map do |group|
            sources = group.fetch("sources")
            group.reject { |key, _value| key == "sources" }
                 .merge("source_count" => sources.length, "sources_digest" => Fragments.summary(sources))
          end,
            "left_out" => review.fetch("left_out").map do |row|
              paths = row.fetch("paths")
              row.reject { |key, _value| key == "paths" }
                 .merge("path_count" => paths.length, "first_path" => paths.first)
            end }
        end

        # One part of the whole review of `paths`, exactly, in fragments bound to the revision.
        def detail(request, paths, path)
          Fragments.detail(request, DETAIL, read(request, paths), path, :parts => PARTS)
        end

        # The groups the rectangles form, first path first, and a left-out row for each that cannot convert.
        def assess(request, sources)
          hosts = ConvertHosts.new(request, sources)
          outlines = ReadContext.new(request)
          outlines = outlines.occurrences.filter_map { |item| outlines.read_polygon(item) }
          built = []
          left_out = []
          clusters(sources).each do |indices|
            cluster = sources.values_at(*indices)
            built << group(hosts, cluster, outlines)
          rescue CodedError => error
            left_out << left_out(cluster.map(&:path), error)
          end
          crossing = crossing_indices(built)
          clear, refused = built.partition.with_index { |_item, index| !crossing.include?(index) }
          left_out.concat(refused.map { |item| left_out(item.fetch(:sources).map(&:path), crossing_error) })
          [clear.sort_by { |item| item.fetch(:sources).first.path }, left_out]
        end

        def types(request)
          request.engine.ids(TYPE_KIND).map { |id| request.engine.find(TYPE_KIND, id) }
        end

        def clusters(sources)
          ConvertRectangles.clusters(sources.map(&:edge_keys)) do |left, right|
            FaceGeometry.coplanar?(sources[left].geometry, sources[right].geometry,
                                   ConvertRectangles::COORDINATE_TOLERANCE_M)
          end
        end

        # One left-out row; a group that cannot convert names all of its Faces.
        def left_out(paths, error)
          { "paths" => paths, "code" => error.code, "message" => error.message }
        end

        def group(hosts, sources, outlines)
          host = hosts.resolve(sources)
          plane = Placement::Plane.new(host.geometry)
          unless sources.all? { |source| ConvertRectangles.aligned?(source.corners, plane) }
            raise CodedError.new("window.not_aligned", "The rectangle's sides are not parallel to its host Face's up " \
                                                       "and right.")
          end

          extents = sources.map { |source| ConvertRectangles.extent(source.corners, plane) }
          layout = ConvertRectangles.layout(extents)
          unless layout
            raise CodedError.new("window.mull_not_rectangular", "These rectangles share Edges but do not tile one " \
                                                                "rectangle exactly.")
          end

          check_size!(layout)
          check_clear!(sources, plane, outlines)
          { :host => host, :sources => sources, :layout => layout }
        end

        def check_size!(layout)
          limit = Types::BANDS.fetch("maxItems")
          return unless [layout.columns_m.length, layout.rows_m.length].max > limit

          raise CodedError.new("validation.failed", "A Window Type takes at most #{limit} rows and #{limit} columns.")
        end

        # An existing Window on the plane would refuse the placement, so the review says so first.
        def check_clear!(sources, plane, outlines)
          return unless overlaps?(sources, plane, outlines)

          raise CodedError.new("window.overlap", "The rectangle overlaps a Window already on this Face's plane.")
        end

        def overlaps?(sources, plane, outlines)
          near = outlines.select do |outline|
            outline.all? { |point| plane.signed_distance_m(point).abs <= FaceGeometry::QUANTUM_M }
          end
          taken = near.map { |outline| outline.map { |point| plane.project(point) } }
          sources.any? do |source|
            rectangle = source.corners.map { |point| plane.project(point) }
            taken.any? { |outline| Placement::Polygons.overlap?(rectangle, outline) }
          end
        end

        # Rectangles in separate Groups share no Edge, so they can overlap as separate groups. Neither is
        # the one to keep, so both are left out.
        def crossing_indices(built)
          built.each_index.with_object([]) do |left, crossing|
            plane = Placement::Plane.new(built[left].fetch(:host).geometry)
            sources = built[left].fetch(:sources)
            ((left + 1)...built.length).each do |right|
              others = built[right].fetch(:sources).map(&:corners)
              crossing.push(left, right) if overlaps?(sources, plane, others)
            end
          end.uniq
        end

        def crossing_error
          CodedError.new("window.overlap", "The rectangle overlaps another selected rectangle in a separate Group. " \
                                           "Select one of them.")
        end

        def rows(built, types)
          firsts = []
          names = {}
          taken = types.map { |type| type.fetch("name").strip.downcase }
          built.each_with_index.map do |item, index|
            layout = item.fetch(:layout)
            shared = firsts.find do |first|
              ConvertRectangles.same_layout?(layout, built[first].fetch(:layout), TYPE_MATCH_TOLERANCE_M)
            end
            firsts << index unless shared
            matching = matching_types(layout, types)
            names[shared || index] ||= default_name(layout, taken)
            { "host" => item.fetch(:host).reference, "columns_m" => layout.columns_m, "rows_m" => layout.rows_m,
              "layout_index" => shared || index, "matching_types" => matching,
              "default_name" => names.fetch(shared || index),
              "preselected_type_id" => matching.first&.fetch("id"),
              "sources" => sources(item.fetch(:sources), layout) }
          end
        end

        # The size in display units, with " (2)" when it is taken (W7-8); recorded as taken for the next layout.
        def default_name(layout, taken)
          stem = size_name(layout.columns_m.sum, layout.rows_m.sum)
          name = taken.include?(stem.downcase) ? numbered(stem, taken) : stem
          taken << name.downcase
          name
        end

        def size_name(width, height)
          return "Window #{(width * 1000).round} x #{(height * 1000).round}" if Preferences.unit_system == "SI"

          format("Window %<w>.1f x %<h>.1f", :w => width / METRES_PER_INCH, :h => height / METRES_PER_INCH)
        end

        def numbered(stem, taken)
          (2..).each do |index|
            name = "#{stem} (#{index})"
            return name unless taken.include?(name.downcase)
          end
        end

        def matching_types(layout, types)
          found = types.select do |type|
            candidate = ConvertRectangles::Layout.new(
              :columns_m => type.fetch("columns_m"), :rows_m => type.fetch("rows_m"),
              :spans => type.fetch("elements").map { |element| element.values_at("row_span", "column_span") }
            )
            ConvertRectangles.same_layout?(layout, candidate, TYPE_MATCH_TOLERANCE_M)
          end
          found.sort_by { |type| [type.fetch("name").downcase, type.fetch("id")] }
               .map { |type| type.slice("id", "name") }
        end

        # Top rows first, then left to right, with the geometry `convert` guards against.
        def sources(items, layout)
          rows = items.zip(layout.spans).map do |source, (row_span, column_span)|
            { "path" => source.path, "row_span" => row_span, "column_span" => column_span,
              "digest" => source.geometry.digest,
              "outline_m" => source.corners.map { |point| point.map { |value| value.round(OUTLINE_DIGITS) } } }
          end
          rows.sort_by { |row| [row.fetch("row_span").first, row.fetch("column_span").first] }
        end
        private_class_method :clusters, :group, :check_size!, :check_clear!, :overlaps?, :crossing_indices,
                             :crossing_error, :default_name, :size_name, :numbered, :matching_types, :sources
      end
    end
  end
end
