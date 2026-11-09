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

        module_function

        def read(request, paths)
          sources, left_out = ConvertSources.read(request.model, paths)
          hosts = ConvertHosts.new(request, sources)
          outlines = ReadContext.new(request)
          outlines = outlines.occurrences.filter_map { |item| outlines.read_polygon(item) }
          types = request.engine.ids(TYPE_KIND).map { |id| request.engine.find(TYPE_KIND, id) }
          built = []
          clusters(sources).each do |indices|
            cluster = sources.values_at(*indices)
            built << group(hosts, cluster, outlines)
          rescue CodedError => error
            left_out << left_out(cluster.map(&:path), error)
          end
          { "groups" => rows(built, types),
            "left_out" => left_out.sort_by { |row| row.fetch("paths").first } }
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
          near = outlines.select do |outline|
            outline.all? { |point| plane.signed_distance_m(point).abs <= FaceGeometry::QUANTUM_M }
          end
          taken = near.map { |outline| outline.map { |point| plane.project(point) } }
          return unless sources.any? do |source|
            rectangle = source.corners.map { |point| plane.project(point) }
            taken.any? { |outline| Placement::Polygons.overlap?(rectangle, outline) }
          end

          raise CodedError.new("window.overlap", "The rectangle overlaps a Window already on this Face's plane.")
        end

        def rows(built, types)
          ordered = built.sort_by { |item| item.fetch(:sources).first.path }
          firsts = []
          ordered.each_with_index.map do |item, index|
            layout = item.fetch(:layout)
            shared = firsts.find do |first|
              ConvertRectangles.same_layout?(layout, ordered[first].fetch(:layout), TYPE_MATCH_TOLERANCE_M)
            end
            firsts << index unless shared
            matching = matching_types(layout, types)
            { "host" => item.fetch(:host).reference, "columns_m" => layout.columns_m, "rows_m" => layout.rows_m,
              "layout_index" => shared || index, "matching_types" => matching,
              "preselected_type_id" => matching.first&.fetch("id"),
              "sources" => sources(item.fetch(:sources), layout) }
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
        private_class_method :clusters, :group, :check_size!, :check_clear!, :rows, :matching_types, :sources
      end
    end
  end
end
