# frozen_string_literal: true

require_relative "read_context"

module PhComposer
  module Windows
    module Units
      # A writable host Face as `units.place` measures it, in the frame its offsets use (right and up from the
      # Face's lowest, leftmost extent as seen from outside): its outline and that outline's bounding width and
      # height, and the bounding rectangles a placement must stay clear of there, the Face's holes and the
      # Unit outlines on its plane that meet it, as Placement::Fit checks them. A Face that is not a rectangle
      # is narrower than its bounding box in places, so the outline is what an opening must stay inside.
      # Writes nothing; refuses what locating the host for a placement refuses.
      # The Unit rows come in bounded pages (Pages.bounded), so a facade carrying hundreds of Windows still
      # answers within an agent's reply budget; the Face's own extent comes on every page.
      # With `geometry` "summary" the outline and holes stay out, counted, and the Units page has the whole
      # page budget; `holes` and `points` page them, so a Face with hundreds of holes or vertices is read
      # completely. Every page measures the Face afresh, bound to the revision.
      module HostExtent
        QUERY = "#{FEATURE_ID}.units.host_extent"
        HOLES = "#{QUERY}.holes"
        POINTS = "#{QUERY}.points"
        # Offsets to a tenth of a millimetre: finer than any opening is set out, and short enough that a Face
        # tessellated into hundreds of vertices still fits a reply. `units.place` checks the real geometry.
        DIGITS = 4
        # The host as the offsets measure it: its outer loop and holes projected, and the frame's origin.
        Frame = Struct.new(:plane, :outer, :holes, :origin, :width, :height, keyword_init: true)

        module_function

        def read(request, host_reference)
          reads = ReadContext.new(request)
          frame = frame(reads.host_reference(host_reference))
          face = { "width_m" => round(frame.width), "height_m" => round(frame.height) }
          face.merge!(if request.params["geometry"] == "summary"
                        { "outline_points" => frame.outer.length, "hole_count" => frame.holes.length }
                      else
                        { "outline_m" => offsets(frame.outer, frame.origin),
                          "holes" => frame.holes.map { |loop| rectangle(loop, frame.origin) } }
                      end)
          rows = units(reads, frame.plane, frame.origin, frame.width, frame.height)
          # The Face's geometry rides on every page, so the rows get what of the page budget it leaves.
          budget = [Pages::MAX_PAGE_BYTES - JSON.generate(face).bytesize, 1].max
          key = ->(row) { row.dig("reference", "entity_path") }
          page, next_cursor = Pages.bounded(request, QUERY, rows, :key => key, :max_bytes => budget)
          face.merge("units" => page, "next_cursor" => next_cursor, "total" => rows.length)
        end

        # One page of the host's holes, each its bounding rectangle in offsets, as host_extent gives it, and
        # how many points its loop has.
        def holes(request, host_reference)
          frame = frame(ReadContext.new(request).host_reference(host_reference))
          rows = frame.holes.each_with_index.map do |loop, index|
            { "index" => index }.merge(rectangle(loop, frame.origin)).merge("point_count" => loop.length)
          end
          page, next_cursor = Pages.bounded(request, HOLES, rows, :key => ->(row) { [row.fetch("index")] })
          { "holes" => page, "next_cursor" => next_cursor, "total" => rows.length }
        end

        # One page of one loop's points in offsets, in loop order: the outer loop, or the hole `hole` names.
        def points(request, host_reference, hole)
          frame = frame(ReadContext.new(request).host_reference(host_reference))
          loop = hole.nil? ? frame.outer : frame.holes[hole]
          raise CodedError.new("target.not_found", "The Face has no hole #{hole}.") unless loop

          rows = offsets(loop, frame.origin).each_with_index.map { |(x, y), index| [index, x, y] }
          page, next_cursor = Pages.bounded(request, POINTS, rows, :key => ->(row) { [row.first] })
          { "points" => page.map { |index, x, y| { "index" => index, "x_m" => x, "y_m" => y } },
            "next_cursor" => next_cursor, "total" => rows.length }
        end

        def frame(host)
          plane = Placement::Plane.new(host.geometry)
          outer = host.geometry.outer_loop.map { |point| plane.project(point) }
          origin = [outer.map(&:first).min, outer.map(&:last).min]
          Frame.new(:plane => plane, :outer => outer, :origin => origin,
                    :holes => host.geometry.holes.map { |loop| loop.map { |point| plane.project(point) } },
                    :width => outer.map(&:first).max - origin[0], :height => outer.map(&:last).max - origin[1])
        end

        def offsets(points, origin)
          points.map { |x, y| [round(x - origin[0]), round(y - origin[1])] }
        end

        # Each Unit outline on the host's plane, glued or not, that meets the Face's bounding box: one anywhere
        # else on the plane cannot conflict with an opening inside the Face. One with unknown native geometry
        # has no footprint to report.
        def units(reads, plane, origin, width, height)
          reads.occurrences.sort_by(&:path).filter_map do |item|
            polygon = reads.read_polygon(item)
            next unless polygon&.all? { |point| plane.signed_distance_m(point).abs <= FaceGeometry::QUANTUM_M }

            box = rectangle(polygon.map { |point| plane.project(point) }, origin)
            next unless box["x_m"] <= width && box["x_m"] + box["width_m"] >= 0 &&
                        box["y_m"] <= height && box["y_m"] + box["height_m"] >= 0

            { "reference" => item.reference }.merge(box)
          end
        end

        # `points` already projected onto the host's plane.
        def rectangle(points, origin)
          xs = points.map(&:first)
          ys = points.map(&:last)
          { "x_m" => round(xs.min - origin[0]), "y_m" => round(ys.min - origin[1]),
            "width_m" => round(xs.max - xs.min), "height_m" => round(ys.max - ys.min) }
        end

        def round(value)
          value.round(DIGITS)
        end
        private_class_method :frame, :offsets, :units, :rectangle, :round
      end
    end
  end
end
