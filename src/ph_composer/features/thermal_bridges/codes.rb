# frozen_string_literal: true

module PhComposer
  module ThermalBridges
    # The codes thermal bridges report under their own noun, published in docs/API_REFERENCE.md.
    module Codes
      ALL = {
        "thermal_bridge.psi_missing" => "A Thermal Bridge Type has no psi-value, so an Edge using it cannot export.",
        "thermal_bridge.type_missing" => "Assigned Edges name a Thermal Bridge Type that no longer exists, so they " \
                                         "cannot export.",
        "thermal_bridge.outside_zone" => "An assigned Edge is in no Zone, so it is not exported.",
        "thermal_bridge.no_envelope_face" => "An assigned Edge bounds no classified envelope Face; it is likely a " \
                                             "stray line.",
        "thermal_bridge.interior_junction" => "An assigned Edge lies only between interior Faces (Surface or To " \
                                              "neighbour).",
        "thermal_bridge.counted_twice" => "An assigned Edge coincides with an assigned Edge in another Zone, so the " \
                                          "bridge is counted twice.",
        "thermal_bridge.shared_definition" => "An assigned Edge is in shared component storage and counts once per " \
                                              "placement.",
        "thermal_bridge.hidden" => "An Edge to locate, or a Group holding it, is hidden or on a hidden tag."
      }.freeze

      module_function

      def install(feature)
        ALL.each { |code, description| feature.code(code, :description => description) }
      end
    end
  end
end
