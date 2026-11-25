# frozen_string_literal: true

module PhComposer
  module Piping
    # The pipe role and Pipe Type Colour-by modes, each pipe occurrence one entry of the shared line-group shape
    # (LineGroups::ColourModes). The legend sums each row's drawn length, so a role's row reads what the schedule's
    # totals by role read. A pipe naming a missing or unreadable type is incomplete in the type mode.
    module ColourModes
      BY_ROLE = "#{FEATURE_ID}.by_role".freeze
      BY_TYPE = "#{FEATURE_ID}.by_type".freeze
      Lines = LineGroups::ColourModes
      STROKE = Lines::STROKE
      MISSING = "Missing type"
      ROLE_WORDS = { "trunk" => "Trunk", "branch" => "Branch", "twig" => "Twig",
                     "recirculation" => "Recirculation" }.freeze
      ROLE_COLOURS = { "trunk" => [31, 119, 180], "branch" => [44, 160, 44], "twig" => [255, 127, 14],
                       "recirculation" => [148, 103, 189] }.freeze

      module_function

      def install(feature)
        feature.colour_mode(BY_ROLE, :label => "Pipe role", :entity_kind => "edge", :stroke => STROKE,
                                     :colours => ColourBy::Palette.fixed(ROLE_COLOURS),
                                     :sort => method(:role_order)) { |read| by_role(read) }
        feature.colour_mode(BY_TYPE, :label => "Pipe Type", :entity_kind => "edge", :stroke => STROKE,
                                     :colours => Lines.method(:no_value_colour)) { |read| by_type(read) }
      end

      def by_role(read)
        Lines.edges(LINE_GROUP, read) do |edge, occurrence, record, _type|
          role = record.fetch("role")
          Lines.entry(edge, occurrence, role, ROLE_WORDS.fetch(role), true)
        end
      end

      def by_type(read)
        Lines.edges(LINE_GROUP, read) do |edge, occurrence, record, type|
          Lines.entry(edge, occurrence, record.fetch("pipe_type_id"), type ? type.fetch("name") : MISSING, type,
                      :colour => type && rgb(PipeType.color(type)))
        end
      end

      def rgb(color)
        Lines.rgb(color)
      end

      # The roles keep the order every list of them has.
      def role_order(row)
        [Assignment::ROLES.index(row.value) || Assignment::ROLES.length, row.value.to_s]
      end
    end
  end
end
