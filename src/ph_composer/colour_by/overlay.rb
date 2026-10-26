# frozen_string_literal: true

module PhComposer
  module ColourBy
    # The one `Sketchup::Overlay` a Model gets while a Colour-by mode is active. It draws what the
    # service already cached and nothing else: no Model read, no record read and no repair, so the
    # cost of a frame is Ruby marshalling (context/SKETCHUP_HOST_BEHAVIOR.md, "Overlays").
    #
    # Fills are batched per colour, one `View#draw` a legend row rather than one a face, because that
    # marshalling is what dominates past about 10,000 triangles.
    class Overlay < Sketchup::Overlay
      OVERLAY_ID = "#{EXTENSION_ID}.colour_by"
      LINE_WIDTH = 2
      # The HUD sits in the upper left of the viewport.
      HUD_ORIGIN = [12, 12].freeze
      HUD_ROW_HEIGHT = 18
      HUD_SWATCH = 12

      def initialize(service)
        super(OVERLAY_ID, "PH-Composer Colour by", :description => "Colours the Model by the active mode.")
        @service = service
      end

      def draw(view)
        top = HUD_ORIGIN.last
        if @service.active?
          draw_wash(view)
          @service.fills.each do |colour, points|
            next if points.empty?

            view.drawing_color = fill_colour(colour)
            view.draw(GL_TRIANGLES, Tessellation.lift(points, view))
          end
          draw_lines(view)
          draw_outlines(view)
          top = draw_hud(view)
        end
        draw_readouts(view, top)
      end

      private

      def draw_wash(view)
        return if @service.wash_triangles.empty?

        colour = Palette::ISOLATION_WASH
        view.drawing_color = Sketchup::Color.new(*colour, Palette::ISOLATION_WASH_ALPHA)
        view.draw(GL_TRIANGLES, Tessellation.lift(@service.wash_triangles, view))
      end

      # Derived outlines and segments, in each entry's colour at the mode's stroke, else the outline weight.
      def draw_lines(view)
        return if @service.lines.empty?

        view.line_width = @service.mode&.stroke || LINE_WIDTH
        view.line_stipple = "" if view.respond_to?(:line_stipple=)
        @service.lines.each do |colour, points|
          next if points.empty?

          view.drawing_color = outline_colour(colour)
          view.draw(GL_LINES, Tessellation.lift(points, view))
        end
      end

      # Each readout's anchors at their points' screen positions, skipping any behind the camera, and its
      # HUD lines under the legend, or at its place when no mode is on. Text is not depth-tested.
      def draw_readouts(view, top)
        system = Preferences.unit_system
        @service.readout_drawings.each_value do |anchors, hud|
          anchors.each do |anchor|
            next if behind_camera?(view, anchor.point)

            draw_hud_text(view, *screen(view, anchor.point), readout_text(anchor.parts, system))
          end
          hud.each do |parts|
            top += HUD_ROW_HEIGHT
            draw_hud_text(view, HUD_ORIGIN.first, top, readout_text(parts, system))
          end
        end
      end

      def readout_text(parts, system)
        ReadoutOutput.text(parts, system)
      end

      def behind_camera?(view, point)
        return false unless view.respond_to?(:camera)

        camera = view.camera
        return false unless camera.respond_to?(:direction)

        direction = camera.direction
        eye = camera.eye
        ((point.x - eye.x) * direction.x) + ((point.y - eye.y) * direction.y) + ((point.z - eye.z) * direction.z) <= 0
      end

      def screen(view, point)
        return [point.x, point.y] unless view.respond_to?(:screen_coords)

        projected = view.screen_coords(point)
        [projected.x, projected.y]
      end

      def draw_outlines(view)
        view.line_width = LINE_WIDTH
        # Classified Faces carry fills only. Their native edges remain available to SketchUp's
        # selection, hover and inference highlights, including Outdoors' similar blue.
        return if @service.unclassified_outlines.empty? && @service.unclassified_hatch.empty?

        # A solid boundary remains legible on tiny Faces where no six-inch stripe crosses the mesh.
        # Hatch points were clipped and cached at rebuild time; draw only lifts them toward the eye.
        view.line_stipple = "" if view.respond_to?(:line_stipple=)
        view.drawing_color = outline_colour(Palette::UNCLASSIFIED)
        unless @service.unclassified_outlines.empty?
          view.draw(GL_LINES, Tessellation.lift(@service.unclassified_outlines, view))
        end
        return if @service.unclassified_hatch.empty?

        view.line_width = 1
        view.draw(GL_LINES, Tessellation.lift(@service.unclassified_hatch, view))
      end

      # The legend the HUD draws is the panel's legend: one source, so a QA screenshot and the panel
      # never disagree.
      # Answers the last row's top, so readout lines follow the legend.
      def draw_hud(view)
        left, top = HUD_ORIGIN
        draw_hud_text(view, left, top, @service.mode&.label.to_s)
        if @service.isolated
          row = @service.rows.find { |item| [item.value, item.state] == @service.isolated }
          top += HUD_ROW_HEIGHT
          draw_hud_text(view, left, top, "Showing only: #{readout_text(row.label, Preferences.unit_system)}") if row
        end
        @service.rows.each_with_index do |row, index|
          row_top = top + ((index + 1) * HUD_ROW_HEIGHT)
          draw_swatch(view, left, row_top, row.colour)
          draw_hud_text(view, left + HUD_SWATCH + 6, row_top, legend_text(row))
        end
        top + (@service.rows.length * HUD_ROW_HEIGHT)
      end

      # "101 Living (2) 24 m²": the label, the count and the row's summed figure, in the display units.
      def legend_text(row)
        system = Preferences.unit_system
        text = "#{readout_text(row.label, system)} (#{row.count})"
        row.figure ? "#{text} #{Legend.figure_text(row.figure, system)}" : text
      end

      def draw_swatch(view, left, top, colour)
        return unless view.respond_to?(:draw2d)

        view.drawing_color = fill_colour(colour)
        view.draw2d(GL_TRIANGLES, [
          Geom::Point3d.new(left, top, 0), Geom::Point3d.new(left + HUD_SWATCH, top, 0),
          Geom::Point3d.new(left + HUD_SWATCH, top + HUD_SWATCH, 0),
          Geom::Point3d.new(left, top, 0), Geom::Point3d.new(left + HUD_SWATCH, top + HUD_SWATCH, 0),
          Geom::Point3d.new(left, top + HUD_SWATCH, 0)
        ])
      end

      def draw_hud_text(view, left, top, text)
        return unless view.respond_to?(:draw_text)

        view.draw_text(Geom::Point3d.new(left, top, 0), text)
      end

      def fill_colour(colour)
        Sketchup::Color.new(colour[0], colour[1], colour[2], Palette::FILL_ALPHA)
      end

      def outline_colour(colour)
        Sketchup::Color.new(colour[0], colour[1], colour[2], Palette::OUTLINE_ALPHA)
      end
    end
  end
end
