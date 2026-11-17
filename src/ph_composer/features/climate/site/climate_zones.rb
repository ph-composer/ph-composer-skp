# frozen_string_literal: true

module PhComposer
  module Climate
    # The climate zones a site may name. The Model stores the WUFI-Passive code, which export writes
    # unchanged; the panel and the Export report show the label. 1 is the user's choice of Not defined,
    # which differs from an unset zone (null).
    module ClimateZones
      LABELS = {
        1 => "Not defined", 11 => "1", 12 => "2", 13 => "3", 14 => "4", 141 => "4C", 15 => "5", 16 => "6",
        17 => "7", 18 => "8"
      }.freeze
      CODES = LABELS.keys.freeze

      module_function

      # The label for a stored code; nil for an unset zone.
      def label(code)
        code.nil? ? nil : LABELS.fetch(code)
      end
    end
  end
end
