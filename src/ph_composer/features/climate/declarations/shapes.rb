# frozen_string_literal: true

module PhComposer
  module Climate
    # Schema pieces the Climate declarations share: what a site read and a design-temperature read return.
    module Shapes
      extend SchemaShapes

      NONE = object({}).freeze
      SITE_STATE = { "type" => "string", "enum" => %w[not_set set],
                     "description" => "set when latitude, longitude and elevation are all present." }.freeze
      DESIGN_STATE = { "type" => "string", "enum" => %w[not_set incomplete set],
                       "description" => "incomplete when one of the two design temperatures is present." }.freeze
      WARNING = { "type" => %w[string null], "enum" => [Settings::CROSSED, nil],
                  "description" => "#{Settings::CROSSED} when heating is at or above cooling; the values still " \
                                   "save." }.freeze
      SITE = with(Settings::SITE_VALUES,
                  "climate_zone_label" => { "type" => %w[string null], "enum" => ClimateZones::LABELS.values + [nil],
                                            "description" => "The zone as the panel and the Export report show " \
                                                             "it; null when unset." },
                  "state" => SITE_STATE).freeze
      DESIGN_TEMPERATURES = with(Settings::DESIGN_VALUES,
                                 "state" => DESIGN_STATE,
                                 "warning" => WARNING).freeze
    end
  end
end
