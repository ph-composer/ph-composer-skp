# frozen_string_literal: true

module PhComposer
  module Mechanical
    module Serves
      # The airflow balance by ventilator (context/CONTRACTS.md, "Mechanical equipment"), pure: detached rows in,
      # supply, extract and whether they are out of balance out, so the read and its tests share one function.
      #
      # An item's sums run over the Zones the export writes it to: each served Zone once, in a Building Segment.
      # A Zone in Detailed airflows gives its Spaces' supply and extract sums; a By Program Zone gives its
      # Program's flow as both, which is what PHX writes for it; a Zone with no Spaces exports no ventilation and
      # adds nothing. The sums are unknown while a By Program Zone's Program cannot work its flow out, and while
      # the item serves no exported Zone.
      module Balance
        # Supply and extract differ by more than this share of the larger.
        IMBALANCE_SHARE = 0.1
        BY_PROGRAM = "by_program"
        UNSERVED = "It serves no Zone the export writes, so it moves no air."

        # One served Zone: `spaces` is its row of `ph_composer.spaces.all` and `programs` its row of
        # `ph_composer.programs.zones`, either nil when that read has none.
        Zone = Struct.new(:name, :spaces, :programs, keyword_init: true)

        module_function

        # The balance row of one item over the Zones it serves.
        def call(zones)
          return unknown(UNSERVED) if zones.empty?

          flows = zones.map { |zone| [zone, flow(zone)] }
          missing = flows.find { |_zone, rates| rates.nil? }
          return unknown(program_missing(missing.first)) if missing

          supply = flows.sum { |_zone, rates| rates.first }
          extract = flows.sum { |_zone, rates| rates.last }
          { "supply_m3h" => supply, "extract_m3h" => extract, "imbalanced" => imbalanced?(supply, extract),
            "missing" => nil }
        end

        # One Zone's [supply, extract] in m³/h, nil while its Program cannot work its flow out.
        def flow(zone)
          spaces = zone.spaces || {}
          return [0.0, 0.0] if spaces.fetch("space_count", 0).zero?
          return program_flow(zone.programs) if spaces.fetch("airflow_mode") == BY_PROGRAM

          airflows = spaces.fetch("airflows")
          [airflows.fetch("v_sup_m3h").to_f, airflows.fetch("v_eta_m3h").to_f]
        end

        def program_flow(row)
          flow = row && row["ventilation_m3h"]
          flow.nil? ? nil : [flow.to_f, flow.to_f]
        end

        def imbalanced?(supply, extract)
          larger = [supply, extract].max
          larger.positive? && (supply - extract).abs > IMBALANCE_SHARE * larger
        end

        def unknown(reason)
          { "supply_m3h" => nil, "extract_m3h" => nil, "imbalanced" => false, "missing" => reason }
        end

        def program_missing(zone)
          "Zone #{zone.name} is By Program, and its Program's ventilation cannot be worked out yet."
        end
      end
    end
  end
end
