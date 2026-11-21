# frozen_string_literal: true

module PhComposer
  module Programs
    # Why a Zone's derived people, lighting or ventilation is unknown, in words the Zones / Programs view shows
    # on its amber "?" (context/CONTRACTS.md, "Occupancy"). It reads what the derivations read and answers one
    # sentence for each value that is nil, keyed as the `programs.zones` row keys the value. Pure: no Model access.
    module MissingValues
      # What the derivations read for one Zone: its effective Program (nil when that record is gone), the Zone
      # record, its Derive::Zone input, its Dwelling and that Dwelling's counts (nil in none), and the means of the
      # Program's people and lighting Schedules by load.
      Facts = Struct.new(:program, :zone, :input, :dwelling, :counts, :means, :keyword_init => true)

      module_function

      # `derived` holds the three values as the row keys them. With no Program, each is unknown for that reason.
      def call(derived, facts)
        unless facts.program
          return derived.select { |_key, value|
            value.nil?
          }.keys.to_h { |key| [key, "#{facts.zone.name} has no Program."] }
        end

        found = {}
        found["people"] = people(facts) if derived["people"].nil?
        found["lighting_w"] = lighting(facts) if derived["lighting_w"].nil?
        found["ventilation_m3h"] = ventilation(facts, found["people"]) if derived["ventilation_m3h"].nil?
        found
      end

      def people(facts)
        name = facts.program.fetch("name")
        return "#{name} sets no people per area." unless facts.program.dig("people", "rule")
        return "#{facts.zone.name} is in no Dwelling, so the Phius occupancy rule has no occupants." unless
          facts.dwelling
        if facts.counts.nil? || facts.counts["occupants"].nil?
          return "Enter the bedrooms of #{facts.dwelling.fetch('name')}: the Phius rule counts occupants from them."
        end

        mean = facts.means["people"]
        return "#{name} has no occupancy Schedule, or it is never occupied." if mean.nil? || !mean.positive?
        return "#{facts.zone.name} has no floor area: add its Spaces." unless facts.input.floor_area_m2.positive?

        "#{facts.dwelling.fetch('name')} has no floor area to share its occupants over."
      end

      def lighting(facts)
        name = facts.program.fetch("name")
        return "#{name} sets no lighting per area." unless facts.program.dig("lighting", "rule")
        return "#{facts.zone.name} is in no Dwelling, so the Phius lighting rule has no units." unless facts.dwelling

        mean = facts.means["lighting"]
        return "#{name} has no lighting Schedule, or it is never on." if mean.nil? || !mean.positive?
        return "#{facts.zone.name} has no iCFA: add its Spaces." unless facts.input.icfa_m2.positive?

        "#{facts.dwelling.fetch('name')} has no iCFA to share its lighting over."
      end

      # Ventilation is unknown when the Program sets no term, or sets a rate per person over people still unknown.
      def ventilation(facts, people_reason)
        per_person = facts.program.dig("ventilation", "flow_per_person").to_f
        return "Ventilation per person waits for the people. #{people_reason}" if people_reason && per_person.positive?

        "#{facts.program.fetch('name')} sets no ventilation."
      end
    end
  end
end
