# frozen_string_literal: true

module PhComposer
  module ColourBy
    # A readout's output, checked where the service builds it, inside the readout's failure boundary,
    # rather than inside `draw`: anchors at finite points, outlines of finite point pairs, and every part
    # plain text or a quantity the units module knows (core/units.rb) with a finite value. Pure.
    module ReadoutOutput
      # What a quantity part may set on its format, each checked here so a bad one fails with the readout.
      FORMAT_OPTIONS = %i[precision group_from].freeze

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

      # Plain text, or `[quantity, si_value]` formatted in the display units (core/units.rb), with an optional
      # third element, `{ precision:, group_from: }`, for a line that departs from the quantity's own format.
      def text(parts, system)
        Array(parts).map do |part|
          next part.to_s unless part.is_a?(Array)

          quantity, value, format = part
          Units.format(value, :quantity => quantity, :system => system, **(format || {}))
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

          quantity, value, format = part
          valid = part.is_a?(Array) && part.length.between?(2, 3) && Units::DEFINITIONS.key?(quantity.to_s) &&
                  value.is_a?(Numeric) && value.to_f.finite? && (format.nil? || format_options?(format))
          raise ArgumentError, "A readout part is text or a known quantity with a finite value." unless valid
        end
      end
      private_class_method :check_parts!

      def format_options?(format)
        format.is_a?(Hash) && (format.keys - FORMAT_OPTIONS).empty? &&
          format.values.all? { |number| number.is_a?(Integer) && !number.negative? }
      end
      private_class_method :format_options?
    end
  end
end
