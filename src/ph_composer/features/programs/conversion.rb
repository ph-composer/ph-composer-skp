# frozen_string_literal: true

module PhComposer
  module Programs
    # Pure: an airtightness test result in, the honeybee Infiltration flow that PHX reads back as that result out.
    #
    # The Infiltration load is the only airtightness path to WUFI-Passive and METr: a flow per exposed envelope
    # area, in m³/s per m² at 4 Pa. The pinned PHX (from_HBJSON/create_variant.py, get_infiltration_at_50Pa)
    # turns it into q50 with flow exponent 0.65 and air density 1, and n50 as q50 times the Building Segment's
    # gross envelope area over its net volume. `flow_per_exterior_area` is that conversion's inverse, so the q50
    # or n50 the user entered is the one PHX reports.
    #
    # PHX merges the Rooms of one Segment by weighting each Room's flow with its Outdoors and Ground Face area
    # (from_HBJSON/cleanup.py, merge_infiltrations). Every Room of a Segment carries the same flow, so that
    # weighting returns it unchanged; it fails only when the Segment has no such Face, as the merged flow is
    # then 0. The area that matters is the one n50 divides by: every Face of the merged Room
    # (`Envelope`, export.rb).
    module Conversion
      FLOW_EXPONENT = 0.65
      TEST_PRESSURE_PA = 50.0
      REFERENCE_PRESSURE_PA = 4.0
      SECONDS_PER_HOUR = 3600.0
      # q50 in m³/h·m² per m³/s·m² at 4 Pa: (50 / 4)^0.65 × 3600, about 18,640.
      Q50_PER_FLOW = ((TEST_PRESSURE_PA / REFERENCE_PRESSURE_PA)**FLOW_EXPONENT) * SECONDS_PER_HOUR

      module_function

      # The q50 a test result stands for, in m³/h·m² of envelope. An n50 result needs the Segment's gross
      # envelope area and net volume, each greater than zero; a q50 result needs neither.
      def q50(basis, value, envelope_area_m2: nil, net_volume_m3: nil)
        return Float(value) if basis == "q50"
        raise ArgumentError, "unknown airtightness basis #{basis.inspect}" unless basis == "n50"

        Float(value) * Float(net_volume_m3) / Float(envelope_area_m2)
      end

      # The honeybee Infiltration flow per exterior area, m³/s·m² at 4 Pa, that PHX reads back as `q50`.
      def flow_per_exterior_area(q50)
        Float(q50) / Q50_PER_FLOW
      end

      # PHX's conversion, the other way: the q50 it reports for a flow per exterior area.
      def q50_from_flow(flow_per_exterior_area)
        Float(flow_per_exterior_area) * Q50_PER_FLOW
      end

      # PHX's n50 for a q50 over a Segment's gross envelope area and net volume.
      def n50_from_q50(q50, envelope_area_m2:, net_volume_m3:)
        Float(q50) * Float(envelope_area_m2) / Float(net_volume_m3)
      end
    end
  end
end
