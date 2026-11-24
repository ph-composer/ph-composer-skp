# frozen_string_literal: true

module PhComposer
  module Mechanical
    # What the heat pump reads compose over the four catalogs: each table row's count of the records naming it, an
    # indoor unit's Zones and the plan's findings about the record; the plan's inputs over the live Model, the
    # climate among them through Climate's published reads; and the Blended result.
    module HeatPumpReads
      CLIMATE = "ph_composer.climate.climate.get"
      DESIGN_TEMPERATURES = "ph_composer.climate.design_temperatures.get"
      OutdoorEquipment = HeatPumps::OutdoorEquipment
      IndoorEquipment = HeatPumps::IndoorEquipment
      OutdoorUnits = HeatPumps::OutdoorUnits
      IndoorUnits = HeatPumps::IndoorUnits
      # What each kind's row counts of the records naming it: the row key, the naming kind and its key.
      COUNTS = {
        OutdoorEquipment::KIND_ID => ["unit_count", OutdoorUnits::KIND_ID, "outdoor_equipment_id"],
        IndoorEquipment::KIND_ID => ["unit_count", IndoorUnits::KIND_ID, "indoor_equipment_id"],
        OutdoorUnits::KIND_ID => ["indoor_unit_count", IndoorUnits::KIND_ID, "outdoor_unit_id"]
      }.freeze
      # The live inputs of HeatPumpPlan: stored records by id, the ids that cannot be read, and the climate.
      Inputs = Struct.new(:zones, :outdoor_equipment, :outdoor_units, :indoor_units, :unreadable, :climate,
                          keyword_init: true)

      module_function

      # What a row of `kind` adds beside the record, from one read of the four catalogs and the Zones: its count
      # of the records naming it, an indoor unit's Zones, and the plan's findings about it. `zones` are the
      # Serves Zones when the caller has read them.
      def extra(request, kind, zones: Serves::State.zones(request))
        inputs = inputs(request, :zones => ExportZones.live(zones), :climate => false)
        found = HeatPumpPlan.call(**plan_args(inputs)).findings.group_by(&:record_id)
        counter = COUNTS[kind]
        counts = counter ? members(request.engine, counter[1]).map { |row| row.fetch(counter[2]) }.tally : {}
        served = kind == IndoorUnits::KIND_ID ? Serves::Reads.usage(request, kind, :zones => zones) : nil
        lambda do |record|
          id = record.fetch("id")
          row = { "findings" => found.fetch(id, []).map { |finding| read_finding(finding) } }
          row[counter[0]] = counts.fetch(id, 0) if counter
          row["zones"] = served.call(record).fetch("zones") if served
          row
        end
      end

      # A plan finding as a read row's: a blocking one is an error, an outdoor model left out of the blend and a
      # unit with nothing to pair are warnings, and the rest is info.
      def read_finding(finding)
        severity = if finding.blocks then "error"
                   elsif [Codes::HP_EQUIPMENT_INCOMPLETE,
                          Codes::HP_UNIT_UNPAIRED].include?(finding.code) then "warning"
                   else "info"
                   end
        Codes.finding(finding.code, severity, finding.message)
      end

      # The plan's inputs over the live Model: each Zone once (`zones`, ExportZones), the readable records of the
      # three kinds the plan reads, the ids that cannot be read, and the climate (or why it cannot be read). With
      # `climate: false` the climate is not read, for a caller that needs only the findings about records.
      def inputs(request, zones: ExportZones.live(Serves::State.zones(request)), climate: true)
        engine = request.engine
        read = [OutdoorEquipment::KIND_ID, OutdoorUnits::KIND_ID, IndoorUnits::KIND_ID].to_h do |kind|
          [kind, DefinitionLists.read(engine, kind, engine.ids(kind).sort)]
        end
        by_id = ->(kind) { read.fetch(kind).first.to_h { |record| [record.fetch("id"), record] } }
        Inputs.new(:zones => zones, :outdoor_equipment => by_id.call(OutdoorEquipment::KIND_ID),
                   :outdoor_units => by_id.call(OutdoorUnits::KIND_ID),
                   :indoor_units => by_id.call(IndoorUnits::KIND_ID),
                   :unreadable => read.values.flat_map { |_records, bad| bad.map { |row| row.fetch("id") } },
                   :climate => climate ? climate(request) : "The climate was not read.")
      end

      def plan_args(inputs)
        { :zones => inputs.zones, :outdoor_equipment => inputs.outdoor_equipment,
          :outdoor_units => inputs.outdoor_units, :indoor_units => inputs.indoor_units,
          :climate => inputs.climate, :unreadable => inputs.unreadable }
      end

      # The climate through Climate's published reads (its CONTRACTS section 9): the air temperature row and the
      # two design temperatures, or why they cannot be read.
      def climate(request)
        stored = request.query(CLIMATE)
        design = request.query(DESIGN_TEMPERATURES)
        monthly = stored.dig("climate", "values", "monthly", "air_c")
        HeatPumpPlan.climate(monthly, design["heating_99_c"], design["cooling_1_c"])
      rescue CodedError => error
        "The Model's climate cannot be read: #{error.message}"
      end

      # The readable records of `kind`; an unreadable one is reported by its own read.
      def members(engine, kind)
        DefinitionLists.read(engine, kind, engine.ids(kind).sort).first
      end

      # The Blended result: each exported Building Segment's blend, the climate the blends read, and every
      # finding of the heat pump plan, each with its severity.
      def blended(request)
        inputs = inputs(request)
        plan = HeatPumpPlan.call(**plan_args(inputs))
        climate = inputs.climate
        { "climate" => climate.is_a?(String) ? { "state" => "missing", "reason" => climate } :
                                               { "state" => "complete", "reason" => nil },
          "segments" => plan.blends,
          "findings" => plan.findings.map { |found| read_finding(found).merge("object_id" => found.record_id) } }
      end
    end
  end
end
