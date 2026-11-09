# frozen_string_literal: true

require_relative "../placement/host"
require_relative "../placement/plane"
require_relative "../placement/polygons"

module PhComposer
  module Windows
    module Units
      # Which Zone Face a group of rectangles lies on (W7-1), read from Zones' public `zones.all` and
      # `host_context`, as Placement::Hosts does, with each refusal raised as a coded left-out reason.
      #
      # Inside a Zone the drawing has already cut the host: the rectangles' outer Edges are shared with
      # the Face around them, and the host's hole is the rectangles themselves. A drawn neighbour left
      # unselected counts as that Face's edge: Convert could not heal the host while it stays. Outside
      # every Zone nothing is cut, so the host is found by geometry among every Zone Face. Either
      # way a group that touches its host's edge is refused (W7-2), and a rectangle that is a Zone Face
      # with nothing around it is not drawn on one.
      class ConvertHosts
        FACE_LIST = "ph_composer.zones.faces.list"
        ZoneFace = Struct.new(:face, :parent_path, :transform, :geometry, :keyword_init => true)
        TOLERANCE_M = ConvertRectangles::COORDINATE_TOLERANCE_M

        def initialize(request, sources)
          @request = request
          @rows = Placement::Hosts.context(request, sources.map(&:path))
        end

        def resolve(sources)
          host = @rows.key?(sources.first.path) ? drawn_on_zone_face(sources) : outside_zones(sources)
          row = row_of(host)
          state = Placement::Hosts.zone_state(zone_states, row)
          Placement::Hosts.placeable!(row, state)
          Placement::Hosts.read(host.face, host.parent_path, host.transform, row, state)
        end

        private

        def drawn_on_zone_face(sources)
          members = sources.map(&:face)
          first = sources.first
          around = sources.flat_map { |source| source.face.edges }.flat_map(&:faces).uniq - members
          candidates = around.filter_map do |face|
            zone_face = ZoneFace.new(:face => face, :parent_path => first.parent_path, :transform => first.transform,
                                     :geometry => FaceCapture.call(face, first.transform))
            zone_face if on_plane?(zone_face.geometry, sources.flat_map(&:corners))
          end
          no_host! if candidates.empty?
          boundary! if candidates.any? { |candidate| touches?(candidate, sources, [candidate.geometry.outer_loop]) }
          ambiguous! if candidates.length > 1
          candidates.first
        end

        def outside_zones(sources)
          found = sources.flat_map { |source| lying_under(source) }.uniq(&:face)
          no_host! if found.empty?
          ambiguous! if found.length > 1
          host = found.first
          plane = Placement::Plane.new(host.geometry)
          outer = project(plane, host.geometry.outer_loop)
          holes = host.geometry.holes.map { |loop| project(plane, loop) }
          sources.each { |source| check_fit!(project(plane, source.corners), outer, holes) }
          host
        end

        def check_fit!(rectangle, outer, holes)
          unless Placement::Polygons.contained?(rectangle, outer) &&
                 holes.none? { |hole| Placement::Polygons.overlap?(rectangle, hole) }
            raise CodedError.new("window.overhang", "The rectangle leaves its Zone Face or crosses a hole in it.")
          end

          boundary! if ([outer] + holes).any? { |loop| Placement::Polygons.contact?(rectangle, loop) }
        end

        def touches?(host, sources, loops)
          plane = Placement::Plane.new(host.geometry)
          sources.any? do |source|
            rectangle = project(plane, source.corners)
            loops.any? { |loop| Placement::Polygons.contact?(rectangle, project(plane, loop)) }
          end
        end

        # The Zone Faces coplanar with a rectangle that share area with it: one wholly inside a Face's hole
        # is not on that Face.
        def lying_under(source)
          zone_faces.select do |zone_face|
            next false unless on_plane?(zone_face.geometry, source.corners)

            plane = Placement::Plane.new(zone_face.geometry)
            rectangle = project(plane, source.corners)
            Placement::Polygons.overlap?(rectangle, project(plane, zone_face.geometry.outer_loop)) &&
              zone_face.geometry.holes.none? do |hole|
                Placement::Polygons.contained?(rectangle, project(plane, hole))
              end
          end
        end

        # Every Zone Face occurrence, Zones' `faces.list` deciding which Faces those are, nested Groups included.
        def zone_faces
          @zone_faces ||= zone_face_paths.group_by { |path| path[0...-1] }.flat_map do |parent_path, paths|
            entities, transform = storage(parent_path)
            faces = entities.to_a.grep(Sketchup::Face).to_h { |face| [face.persistent_id, face] }
            paths.filter_map { |path| zone_face(faces.fetch(path.last), parent_path, transform) }
          end
        end

        def zone_face_paths
          paths = []
          params = { "fields" => ["face_type"], "limit" => Pages::MAXIMUM_LIMIT }
          loop do
            page = @request.query(FACE_LIST, params)
            paths.concat(page.fetch("faces").map { |row| row.fetch("reference") }.map do |face|
              face.fetch("zone_path") + face.fetch("entity_path")
            end)
            return paths unless page.fetch("next_cursor")

            params = params.merge("cursor" => page.fetch("next_cursor"))
          end
        end

        # A degenerate Zone Face cannot host a Window; it must not refuse rectangles elsewhere.
        def zone_face(face, parent_path, transform)
          ZoneFace.new(:face => face, :parent_path => parent_path, :transform => transform,
                       :geometry => FaceCapture.call(face, transform))
        rescue CodedError
          nil
        end

        # A Zone may sit in a Component instance; its write refusal then comes from `host_context`.
        def storage(path)
          collection = @request.model.entities
          transform = path.reduce(Geom::Transformation.new) do |carried, id|
            container = collection.to_a.find { |entity| entity.persistent_id == id }
            collection = container.respond_to?(:definition) ? container.definition.entities : container.entities
            carried * container.transformation
          end
          [collection, transform]
        end

        def row_of(host)
          path = host.parent_path + [host.face.persistent_id]
          Placement::Hosts.context(@request, [path])[path] || no_host!
        end

        def zone_rows
          @zone_rows ||= @request.query(Placement::Hosts::ZONES).fetch("zones")
        end

        def zone_states
          @zone_states ||= Placement::Hosts.zone_states(zone_rows)
        end

        def on_plane?(geometry, points)
          points.all? { |point| (Vector3.dot(geometry.normal, point) - geometry.plane_offset_m).abs <= TOLERANCE_M }
        end

        def project(plane, points)
          points.map { |point| plane.project(point) }
        end

        def no_host!
          raise CodedError.new("target.wrong_zone", "The rectangle does not lie on a Zone Face. Draw it on a Zone " \
                                                    "Face, or coplanar with one and within it.")
        end

        def ambiguous!
          raise CodedError.new("window.host_ambiguous", "The rectangle lies on more than one coplanar Zone Face.")
        end

        def boundary!
          raise CodedError.new("window.convert_on_boundary", "The rectangle touches its host Face's edge. Draw it " \
                                                             "inset, convert it, then move the Window.")
        end
      end
    end
  end
end
