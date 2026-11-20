# frozen_string_literal: true

module PhComposer
  module Zones
    # This feature's Colour-by modes: Zone, Building-Segment and Level. Their values are open, so they
    # take the shared categorical ramp rather than fixed hues, spread so each value differs (Palette.spread).
    #
    # Each mode paints the Zone Group itself, which the shared service tessellates; nothing here draws.
    module ColourModes
      BY_ZONE = "#{FEATURE_ID}.by_zone"
      BY_BUILDING_SEGMENT = "#{FEATURE_ID}.by_building_segment"
      BY_LEVEL = "#{FEATURE_ID}.by_level"
      # A Zone in no Building Segment is classified, not missing a record: one neutral swatch under its own
      # legend value, a grey outside the categorical ramp.
      NO_SEGMENT_VALUE = "no_building_segment"
      NO_SEGMENT_LABEL = "No Building Segment"
      NO_SEGMENT_COLOUR = [176, 176, 176].freeze

      module_function

      def install(feature)
        feature.colour_mode(BY_ZONE, :label => "Zone", :entity_kind => "zone",
                                     :colours => ColourBy::Palette.ramp) do |read|
          ColourBy::Palette.spread_entries(entries(read.model) { |record| [record.fetch("id"), record.fetch("name")] })
        end
        feature.colour_mode(BY_BUILDING_SEGMENT, :label => "Building-Segment", :entity_kind => "zone",
                                                 :colours => ColourBy::Palette.ramp) do |read|
          ColourBy::Palette.spread_entries(option_entries(read, "building_segment"))
        end
        feature.colour_mode(BY_LEVEL, :label => "Level", :entity_kind => "zone",
                                      :colours => ColourBy::Palette.ramp) do |read|
          ColourBy::Palette.spread_entries(option_entries(read, "level"))
        end
      end

      def option_entries(read, field)
        Occurrences.zones(read.model).map do |zone|
          record = zone.record
          if record.fetch("schema_version") == 1
            value = record[field]
            label = value
            colour = nil
          elsif field == "building_segment" && record["building_segment_id"].nil?
            value = NO_SEGMENT_VALUE
            label = NO_SEGMENT_LABEL
            colour = NO_SEGMENT_COLOUR
          else
            value = record["#{field}_id"]
            display = Options.display(read.engine, record)
            label = display[field]
            hex = display["#{field}_colour"]
            colour = hex && hex.delete_prefix("#").scan(/../).map { |pair| pair.to_i(16) }
          end
          ColourBy::Entry.new(:entity => zone.entity, :transform => zone.transform, :value => value,
                              :label => label, :colour => colour, :path => zone.path)
        end
      end

      # A Zone whose Level was never named has no value, so it joins the legend's unclassified row
      # rather than taking a colour of its own.
      def entries(model)
        Occurrences.zones(model).map do |zone|
          value, label = yield(zone.record)
          ColourBy::Entry.new(:entity => zone.entity, :transform => zone.transform, :value => value,
                              :label => label, :path => zone.path)
        end
      end
    end
  end
end
