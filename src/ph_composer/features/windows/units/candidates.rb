# frozen_string_literal: true

require_relative "convert_rectangles"
require_relative "convert_sources"
require_relative "../placement/host"
require_relative "../placement/plane"
require_relative "../placement/polygons"

module PhComposer
  module Windows
    module Units
      # Where Convert to Window Type and Restore can start without a selection, read from one container named
      # by path. Each answers only what the geometry proves: a rectangle is a convert candidate by its shape,
      # which `units.convert_review` then groups and hosts; loose pane Faces name their Window Type by their
      # stamps, and a host only when exactly one writable Zone Face holds every pane on its plane and inside
      # its outline. Otherwise the row says what the user has to choose, never guessed from a name. Reads only.
      module Candidates
        CONVERT = "#{FEATURE_ID}.units.convert_candidates".freeze
        RESTORE = "#{FEATURE_ID}.units.restore_candidates".freeze
        OUTLINE_DIGITS = 6
        # What a restore row needs before units.restore can take it.
        NEEDS = %w[host selection].freeze

        module_function

        # The rectangles loose in the container (four square corners, no hole), each with the refusal
        # Convert's own source read gives it alone, such as locked or shared storage.
        def convert(request)
          model = request.model
          container = OccurrencePath.resolve(model, request.params.fetch("path", []))
          rectangles = container.entities.to_a.grep(Sketchup::Face).filter_map do |face|
            corners = corners(face, container.transform)
            [container.path + [face.persistent_id], corners, OccurrencePath.hidden?(face)] if corners
          end.sort_by(&:first)
          build = lambda do |rows|
            _sources, left_out = ConvertSources.read(model, rows.map(&:first))
            refusals = left_out.to_h { |row| [row.fetch("paths").first, row.slice("code", "message")] }
            rows.map do |path, corners, hidden|
              outline = corners.map { |point| point.map { |value| value.round(OUTLINE_DIGITS) } }
              { "path" => path, "outline_m" => outline, "hidden" => hidden, "refusal" => refusals[path] }
            end
          end
          page, next_cursor = Pages.bounded(request, CONVERT, rectangles, :key => ->(row) { row.first },
                                                                          :prepare => build)
          { "candidates" => page, "next_cursor" => next_cursor, "total" => rectangles.length }
        end

        # One row per Window Type stamped on the loose pane Faces in the container.
        def restore(request)
          container = OccurrencePath.resolve(request.model, request.params.fetch("path", []))
          faces = container.entities.to_a.grep(Sketchup::Face)
          panes = faces.filter_map { |face| (found = stamp(face)) && [face, found] }
          groups = panes.group_by { |_face, found| found.fetch("window_type_id") }.sort_by(&:first)
          build = lambda do |rows|
            hosts = host_faces(request, container, faces - panes.map(&:first))
            rows.map { |type_id, members| restore_row(request, container, type_id, members, hosts) }
          end
          page, next_cursor = Pages.bounded(request, RESTORE, groups, :key => ->(group) { [group.first] },
                                                                      :prepare => build)
          { "candidates" => page, "next_cursor" => next_cursor, "total" => groups.length }
        end

        def corners(face, transform)
          geometry = FaceCapture.call(face, transform)
          geometry.holes.empty? ? ConvertRectangles.corners(geometry.outer_loop) : nil
        end

        # A pane stamp as Restore reads one; nil for none or anything else.
        def stamp(face)
          found = PANE_STORE.read(face)
          valid = found.is_a?(Hash) && found["window_type_id"].is_a?(String) && found["element_id"].is_a?(String)
          valid ? found : nil
        rescue CodedError
          nil
        end

        def restore_row(request, container, type_id, members, hosts)
          paths = members.map { |face, _found| container.path + [face.persistent_id] }.sort
          elements = members.map { |_face, found| found.fetch("element_id") }
          row = { "type_id" => type_id, "pane_paths" => paths, "element_ids" => elements.sort, "host" => nil,
                  "needs" => nil, "refusal" => type_refusal(request, type_id) }
          # Two panes of one cell are two Windows of this Type exploded here: which panes are one is not proven.
          return row.merge("needs" => "selection") unless elements.uniq.length == elements.length

          outlines = members.map { |face, _found| FaceCapture.call(face, container.transform).outer_loop }
          holding = hosts.select { |host| holds?(host.geometry, outlines) }
          holding.length == 1 ? row.merge("host" => holding.first.reference) : row.merge("needs" => "host")
        end

        def type_refusal(request, type_id)
          request.engine.find(TYPE_KIND, type_id)
          nil
        rescue CodedError => error
          { "code" => error.code, "message" => error.message }
        end

        # The Zone Faces in the container a Window could be restored to: in a Zone, writable from their path and
        # not a paired Surface, as Placement::Hosts.placeable! reads a host.
        def host_faces(request, container, faces)
          rows = Placement::Hosts.context(request, faces.map { |face| container.path + [face.persistent_id] })
          faces.filter_map do |face|
            row = rows[container.path + [face.persistent_id]]
            next unless row && row["write_refusal"].nil? && row.fetch("values")["boundary_condition"] != "Surface"

            Placement::Host.new(:entity => face, :reference => row.fetch("reference"),
                                :geometry => FaceCapture.call(face, container.transform))
          end
        end

        # Every pane point on the host's plane, and every pane inside the host's outline.
        def holds?(geometry, outlines)
          plane = Placement::Plane.new(geometry)
          outer = geometry.outer_loop.map { |point| plane.project(point) }
          outlines.all? do |outline|
            outline.all? { |point| plane.signed_distance_m(point).abs <= FaceGeometry::QUANTUM_M } &&
              Placement::Polygons.contained?(outline.map { |point| plane.project(point) }, outer)
          end
        rescue CodedError
          false
        end
        private_class_method :corners, :stamp, :restore_row, :type_refusal, :host_faces, :holds?
      end
    end
  end
end
