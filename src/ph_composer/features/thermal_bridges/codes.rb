# frozen_string_literal: true

module PhComposer
  module ThermalBridges
    # The codes thermal bridges report under their own noun, published in docs/API_REFERENCE.md.
    module Codes
      ALL = {
        "thermal_bridge.psi_missing" => "A Thermal Bridge Type has no psi-value, so an Edge using it cannot export."
      }.freeze

      module_function

      def install(feature)
        ALL.each { |code, description| feature.code(code, :description => description) }
      end
    end
  end
end
