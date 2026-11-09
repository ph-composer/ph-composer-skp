# frozen_string_literal: true

module PhComposer
  module ColourBy
    # A readout's output, checked where the service builds it, inside the readout's failure boundary,
    # rather than inside `draw`: anchors at finite points, outlines of finite point pairs, and every part
    # plain text or a quantity the units module knows (core/units.rb) with a finite value. Pure.
    module ReadoutOutput
      module_function

      def check!(result)
        raise ArgumentError, "A readout returns a ColourBy::Readout." unless result.is_a?(Readout)

        Array(result.anchors).each do |anchor|
          raise ArgumentError, "A readout anchor needs a finite point." unless finite_point?(anchor.point)

          check_parts!(anchor.parts)
        end
        Array(result.outlines).each do |outline|
          points = Array(outline.points)
          next if points.length.even? && points.all? { |point| finite_point?(point) }

          raise ArgumentError, "A readout outline needs pairs of finite points."
        end
        Array(result.hud).each { |parts| check_parts!(parts) }
        result
      end

      # A legend label's or figure's parts, checked as a readout's are; answers them.
      def parts!(parts)
        check_parts!(parts)
        parts
      end

      # Plain text, or `[quantity, si_value]` formatted in the display units (core/units.rb).
      def text(parts, system)
        Array(parts).map do |part|
          part.is_a?(Array) ? Units.format(part.last, :quantity => part.first, :system => system) : part.to_s
        end.join
      end

      def finite_point?(point)
        %i[x y z].all? do |axis|
          value = point.respond_to?(axis) && point.public_send(axis)
          value.is_a?(Numeric) && value.to_f.finite?
        end
      end
      private_class_method :finite_point?

      def check_parts!(parts)
        Array(parts).each do |part|
          next if part.is_a?(String)

          quantity, value = part
          valid = part.is_a?(Array) && part.length == 2 && Units::DEFINITIONS.key?(quantity.to_s) &&
                  value.is_a?(Numeric) && value.to_f.finite?
          raise ArgumentError, "A readout part is text or a known quantity with a finite value." unless valid
        end
      end
      private_class_method :check_parts!
    end
  end
end
