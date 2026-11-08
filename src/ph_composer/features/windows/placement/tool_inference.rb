# frozen_string_literal: true

module PhComposer
  module Windows
    module Placement
      # SketchUp's own inference for the Place tool's cursor: endpoints, midpoints, edges and guides, shown
      # the way native tools show them. `position` is world coordinates whether or not an edit context is
      # open (context/SKETCHUP_HOST_BEHAVIOR.md).
      class ToolInference
        def initialize
          @input = Sketchup::InputPoint.new
        end

        # The inferred world point in metres; nil when SketchUp inferred nothing here.
        def point_m(view, x, y)
          @input.pick(view, x, y)
          return unless @input.valid?

          position = @input.position
          [position.x, position.y, position.z].map { |value| value.to_f * INCH_TO_M }
        end

        # What SketchUp calls the inference ("Endpoint", "On Edge"); nil when it has no word for it.
        def tooltip
          text = @input.valid? ? @input.tooltip.to_s : ""
          text.empty? ? nil : text
        end

        def draw(view)
          @input.draw(view) if @input.valid? && @input.display?
        end

        def clear
          @input.clear
        end
      end
    end
  end
end
