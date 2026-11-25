# frozen_string_literal: true

module PhComposer
  module Ducting
    # The duct direction and Duct Type Colour-by modes, each duct occurrence one entry of the shared line-group shape
    # (LineGroups::ColourModes). A legend row sums each duct's length times its quantity, so the rows read what the
    # schedule's totals by direction and each Duct Type's used length read. A duct naming a missing or unset type is
    # incomplete in the type mode.
    module ColourModes
      BY_DIRECTION = "#{FEATURE_ID}.by_direction".freeze
      BY_TYPE = "#{FEATURE_ID}.by_type".freeze
      Lines = LineGroups::ColourModes
      MISSING = "Missing type"
      DIRECTION_COLOURS = { "outdoor_air" => [31, 119, 180], "exhaust_air" => [255, 127, 14] }.freeze

      module_function

      def install(feature)
        feature.colour_mode(BY_DIRECTION, :label => "Duct direction", :entity_kind => "edge", :stroke => Lines::STROKE,
                                          :colours => ColourBy::Palette.fixed(DIRECTION_COLOURS),
                                          :sort => method(:direction_order)) { |read| by_direction(read) }
        feature.colour_mode(BY_TYPE, :label => "Duct Type", :entity_kind => "edge", :stroke => Lines::STROKE,
                                     :colours => Lines.method(:no_value_colour)) { |read| by_type(read) }
      end

      def by_direction(read)
        Lines.edges(LINE_GROUP, read) do |edge, occurrence, record, _type|
          direction = record.fetch("direction")
          Lines.entry(edge, occurrence, direction, Runs::DIRECTION_WORDS.fetch(direction), true,
                      :count => record.fetch("quantity"))
        end
      end

      def by_type(read)
        Lines.edges(LINE_GROUP, read) do |edge, occurrence, record, type|
          Lines.entry(edge, occurrence, record.fetch("duct_type_id"), type ? type.fetch("name") : MISSING, type,
                      :colour => type && Lines.rgb(DuctType.color(type)), :count => record.fetch("quantity"))
        end
      end

      # Outdoor air, then Exhaust air, as every list of them keeps.
      def direction_order(row)
        [Assignment::DIRECTIONS.index(row.value) || Assignment::DIRECTIONS.length, row.value.to_s]
      end
    end
  end
end
