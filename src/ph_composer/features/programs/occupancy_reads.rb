# frozen_string_literal: true

module PhComposer
  module Programs
    # The occupancy reads: `programs.zones`, one row per Zone with its assignment, what it works out to and its
    # findings, and each Building Segment's occupancy; `programs.dwellings`, each Dwelling with its Zones. Reads
    # never write: an unwritten default Program or Equipment Set is read from its definition.
    #
    # Findings report what the generic metadata routes can store but Programs' own actions refuse or advise
    # against (context/CONTRACTS.md, "Occupancy"). None blocks anything here; the Program export is to turn them
    # into preflight rows.
    module OccupancyReads
      SPACES = "ph_composer.spaces.all"
      FINDINGS = {
        "programs.dwelling_across_segments" => "A Dwelling holds Zones in more than one Building Segment.",
        "programs.single_dwelling_no_effect" => "Single dwelling is on in a non-residential Building Segment, " \
                                                "where it has no effect.",
        "programs.residential_without_dwelling" => "A residential Building Segment has no Dwelling.",
        "programs.non_residential_dwellings" => "A non-residential Building Segment holds Dwellings.",
        "programs.unassigned_zone" => "A Zone in a non-residential Building Segment has no Program of its own or " \
                                      "from its Segment.",
        "programs.equipment_watts_residential" => "A Zone's Program has electric equipment watts in a residential " \
                                                  "Building Segment; PHX reads only Equipment Set devices there.",
        "programs.single_dwelling_overrides" => "A Zone in a single dwelling keeps an assignment of its own, which " \
                                                "the setting overrides.",
        "programs.set_points_disagree" => "The Programs of a Building Segment's Zones give different heating or " \
                                          "cooling set points; the Segment carries one pair."
      }.freeze

      module_function

      def zones(request)
        rows = build(request)
        { "zones" => rows.fetch(:zones), "building_segments" => rows.fetch(:segments),
          "dwellings" => rows.fetch(:dwellings), "choices" => choices(request) }
      end

      # The Programs and Equipment Sets a Zone or a Segment may name, by name, and the Model's defaults.
      def choices(request)
        listed = lambda do |kind|
          Store.all(request, kind).first.map { |record| record.slice("id", "name") }.sort_by { |row| row.fetch("name") }
        end
        defaults = Settings.read(request.model)
        { "programs" => listed.call(PROGRAM_KIND), "equipment_sets" => listed.call(EQUIPMENT_SET_KIND),
          "default_program_id" => defaults.fetch("default_program_id"),
          "default_equipment_set_id" => defaults.fetch("default_equipment_set_id") }
      end

      def dwellings(request)
        { "dwellings" => build(request).fetch(:dwellings) }
      end

      # Every row the two reads answer, from one pass over the Model.
      def build(request)
        state = OccupancyState.read(request)
        inputs = Inputs.new(request, state)
        zones = state.zones.map { |zone| inputs.zone(zone) }
        groups = zones.group_by { |row| row.fetch(:dwelling)&.fetch("key") }
        counts = groups.reject { |key, _rows| key.nil? }.to_h do |key, rows|
          [key, Derive.counts(rows.first.fetch(:dwelling), rows.map { |row| row.fetch(:input) })]
        end
        zone_rows = zones.map { |row| zone_row(inputs, row, groups, counts) }
        dwelling_rows = groups.reject { |key, _rows| key.nil? }.map do |key, rows|
          dwelling_row(rows, counts.fetch(key))
        end
        dwelling_rows += unused_dwellings(state, groups)
        segment_rows = state.segments.map { |segment| segment_row(inputs, segment, zone_rows, dwelling_rows, state) }
        dwelling_rows = dwelling_rows.sort_by { |row| row.fetch("name") }
        { :zones => zone_rows, :segments => segment_rows, :dwellings => dwelling_rows }
      end

      def zone_row(inputs, row, groups, counts)
        zone = row.fetch(:zone)
        input = row.fetch(:input)
        program = inputs.program(row.fetch(:program_id))
        dwelling = row.fetch(:dwelling)
        members = dwelling ? groups.fetch(dwelling.fetch("key")).map { |member| member.fetch(:input) } : []
        dwelling_counts = dwelling && counts.fetch(dwelling.fetch("key"))
        means = program ? { "people" => inputs.mean(program, "people", "occupancy_schedule_id"),
                            "lighting" => inputs.mean(program, "lighting", "schedule_id") } : {}
        people = program && Derive.people(program, input, :dwelling_counts => dwelling_counts,
                                                          :dwelling_area_m2 => members.sum(&:floor_area_m2),
                                                          :presence_mean => means["people"])
        lighting = program && Derive.lighting(program, input, :units => dwelling&.fetch("units"),
                                                              :dwelling_icfa_m2 => members.sum(&:icfa_m2),
                                                              :schedule_mean => means["lighting"])
        ventilation = program ? Derive.ventilation(program, input, :people => people) : { "m3h" => nil,
                                                                                          "source" => nil }
        derived = { "people" => people, "lighting_w" => lighting, "ventilation_m3h" => ventilation.fetch("m3h") }
        missing = MissingValues.call(derived, MissingValues::Facts.new(:program => program, :zone => zone,
                                                                       :input => input, :dwelling => dwelling,
                                                                       :counts => dwelling_counts, :means => means))
        { "zone_id" => zone.id, "reference" => zone.reference, "name" => zone.name,
          "building_segment_id" => zone.segment_id, "assignment" => zone.assignment,
          "program_id" => row.fetch(:program_id), "program_name" => program&.fetch("name"),
          "dwelling_id" => dwelling&.fetch("id"), "dwelling_name" => dwelling&.fetch("name"),
          "single_dwelling" => dwelling ? dwelling.fetch("single") : false,
          "dwelling_units" => dwelling&.fetch("units"),
          "equipment_set_id" => dwelling ? dwelling["equipment_set_id"] : zone.assignment["equipment_set_id"],
          "floor_area_m2" => input.floor_area_m2, "icfa_m2" => input.icfa_m2,
          "people" => people, "lighting_w" => lighting, "ventilation_m3h" => ventilation.fetch("m3h"),
          "ventilation_source" => ventilation.fetch("source"), "missing" => missing,
          "findings" => zone_findings(inputs, zone, program) }
      end

      def zone_findings(inputs, zone, program)
        segment = inputs.state.segment(zone.segment_id)
        return [] unless segment

        found = []
        if segment.category == "non_residential" && zone.assignment["program_id"].nil? &&
           segment.settings["default_program_id"].nil?
          found << finding("programs.unassigned_zone", "#{zone.name} has no Program of its own or from " \
                                                       "#{segment.name}.")
        end
        watts = program && program.dig("electric_equipment", "watts_per_area")
        if segment.category == "residential" && watts&.positive?
          found << finding("programs.equipment_watts_residential", "#{program.fetch('name')} has electric " \
                                                                   "equipment watts; PHX reads only Equipment " \
                                                                   "Set devices in #{segment.name}.")
        end
        if segment.single? && !Occupancy.unassigned?(zone.assignment)
          found << finding("programs.single_dwelling_overrides", "#{zone.name} keeps an assignment of its own; " \
                                                                 "#{segment.name} is a single dwelling, which " \
                                                                 "overrides it.")
        end
        dwelling_id = zone.assignment["dwelling_id"]
        if dwelling_id && !segment.single? && across?(inputs.state, dwelling_id)
          found << finding("programs.dwelling_across_segments",
                           "#{Words.possessive(zone.name)} Dwelling holds Zones in more than one Building Segment.")
        end
        found
      end

      def across?(state, dwelling_id)
        state.dwelling_zones(dwelling_id).map(&:segment_id).uniq.length > 1
      end

      def dwelling_row(rows, counts)
        dwelling = rows.first.fetch(:dwelling)
        segments = rows.map { |row| row.fetch(:zone).segment_id }.uniq
        findings = segments.length > 1 ? [finding("programs.dwelling_across_segments",
                                                  "#{dwelling.fetch('name')} holds Zones in more than one " \
                                                  "Building Segment.")] : []
        { "id" => dwelling.fetch("id"), "name" => dwelling.fetch("name"), "units" => dwelling.fetch("units"),
          "single_dwelling" => dwelling.fetch("single"),
          "own_bedrooms" => dwelling["bedrooms"], "own_occupants" => dwelling["occupants"],
          "equipment_set_id" => dwelling["equipment_set_id"],
          "zone_ids" => rows.map { |row| row.fetch(:zone).id }, "building_segment_ids" => segments.compact,
          "floor_area_m2" => rows.sum { |row| row.fetch(:input).floor_area_m2 },
          "icfa_m2" => rows.sum { |row| row.fetch(:input).icfa_m2 }, "findings" => findings }.merge(counts)
      end

      # Dwellings no Zone counts in: kept as stored, read with no Zones.
      def unused_dwellings(state, groups)
        state.dwellings.reject { |record| groups.key?(record.fetch("id")) }.map do |record|
          { "id" => record.fetch("id"), "name" => record.fetch("name"), "units" => record.fetch("units"),
            "single_dwelling" => false, "own_bedrooms" => record["bedrooms"], "own_occupants" => record["occupants"],
            "equipment_set_id" => record["equipment_set_id"], "zone_ids" => [], "building_segment_ids" => [],
            "floor_area_m2" => 0.0, "icfa_m2" => 0.0, "findings" => [] }.merge(Derive.counts(record, []))
        end
      end

      def segment_row(inputs, segment, zone_rows, dwelling_rows, state)
        zones = zone_rows.select { |row| row.fetch("building_segment_id") == segment.id }
        house = dwelling_rows.find do |row|
          row.fetch("single_dwelling") && row.fetch("building_segment_ids") == [segment.id]
        end
        dwellings = zones.filter_map { |row| row.fetch("dwelling_id") }.uniq
        # In Zone id order, so the pair a disagreement shows first is the one the export writes.
        programs = zones.sort_by { |row| row.fetch("zone_id") }.map { |row| inputs.program(row.fetch("program_id")) }
                        .compact.uniq
        set_points = Derive.set_points(programs, inputs.schedules)
        { "id" => segment.id, "name" => segment.name, "category" => segment.category,
          "settings" => segment.settings, "stored" => segment.stored, "single_dwelling" => segment.single?,
          "dwelling" => house && house.slice("name", "units", "bedrooms", "occupants", "occupants_rule",
                                             "equipment_set_id"),
          "dwelling_count" => segment.single? && !zones.empty? ? 1 : dwellings.length,
          "set_points" => set_points,
          "single_dwelling_preview" => SingleDwelling.preview(state, segment.id),
          "sums" => sums(zones, dwelling_rows),
          "findings" => segment_findings(segment, zones, dwellings, set_points) + member_findings(zones) }
      end

      def segment_findings(segment, zones, dwellings, set_points)
        found = []
        unless set_points.fetch("agree")
          found << finding("programs.set_points_disagree",
                           "The Programs of #{Words.possessive(segment.name)} Zones give different set points.")
        end
        if segment.stored && segment.settings["single_dwelling"] && segment.category == "non_residential"
          found << finding("programs.single_dwelling_no_effect", "Single dwelling has no effect in " \
                                                                 "#{segment.name}, a non-residential Segment.")
        end
        if segment.category == "residential" && !segment.single? && !zones.empty? && dwellings.empty?
          found << finding("programs.residential_without_dwelling", "#{segment.name} is residential and has no " \
                                                                    "Dwelling.")
        end
        if segment.category == "non_residential" && !dwellings.empty?
          found << finding("programs.non_residential_dwellings", "#{segment.name} is non-residential and holds " \
                                                                 "Dwellings.")
        end
        found
      end

      # What a Segment's heading row shows for its Zones: the counts of the Dwellings they are in (a single
      # dwelling's house among them), their areas and their loads. A load sums the Zones that have one, and
      # `incomplete` names each load some Zone lacks, so the heading never passes a partial sum off as whole.
      def sums(zones, dwelling_rows)
        ids = zones.map { |row| row.fetch("zone_id") }
        counted = dwelling_rows.reject { |row| (row.fetch("zone_ids") & ids).empty? }
        loads = %w[people lighting_w ventilation_m3h]
        { "bedrooms" => Derive.sum(counted.map { |row| row.fetch("bedrooms") }),
          "occupants" => Derive.sum(counted.map { |row| row.fetch("occupants") }),
          "floor_area_m2" => zones.sum { |row| row.fetch("floor_area_m2") },
          "icfa_m2" => zones.sum { |row| row.fetch("icfa_m2") } }
          .merge(loads.to_h { |key| [key, Derive.sum(zones.map { |row| row.fetch(key) })] })
          .merge("incomplete" => loads.select { |key| zones.any? { |row| row.fetch(key).nil? } })
      end

      # Its Zones' findings, one per code for the heading: the Zone's own words for one Zone, else a count.
      def member_findings(zones)
        zones.flat_map { |row| row.fetch("findings") }.group_by { |row| row.fetch("code") }.map do |code, rows|
          next rows.first if rows.length == 1

          finding(code, "#{rows.length} Zones: #{FINDINGS.fetch(code)}")
        end
      end

      def finding(code, message)
        { "code" => code, "severity" => "warning", "message" => message }
      end

      # The records and sums the derivations read, each read once.
      class Inputs
        attr_reader :state, :schedules

        def initialize(request, state)
          @state = state
          @default_program_id = Settings.default_id(request.model, PROGRAM_KIND)
          @programs = Store.all(request, PROGRAM_KIND).first.to_h { |record| [record.fetch("id"), record] }
          @schedules = Store.all(request, SCHEDULE_KIND).first.to_h { |record| [record.fetch("id"), record] }
          @dwellings = state.dwellings.to_h { |record| [record.fetch("id"), record] }
          @sums = request.query(SPACES).fetch("zones").to_h { |row| [row.fetch("zone_id"), row] }
          @means = {}
        end

        def program(id)
          @programs[id]
        end

        def zone(zone)
          segment = @state.segment(zone.segment_id)
          { :zone => zone, :program_id => Derive.program_id(zone, segment, @default_program_id),
            :dwelling => Derive.dwelling(zone, segment, @dwellings), :input => input(zone) }
        end

        def input(zone)
          sums = @sums.fetch(zone.id, {})
          flows = sums.fetch("airflows", {}) || {}
          Derive::Zone.new(:id => zone.id, :segment_id => zone.segment_id, :assignment => zone.assignment,
                           :floor_area_m2 => sums.fetch("floor_area_m2", 0.0).to_f,
                           :icfa_m2 => sums.fetch("weighted_area_m2", 0.0).to_f,
                           :net_volume_m3 => sums.fetch("net_volume_m3", 0.0).to_f,
                           :airflow_mode => sums.fetch("airflow_mode", "by_program"),
                           :supply_m3h => flows["v_sup_m3h"], :extract_m3h => flows["v_eta_m3h"])
        end

        # The mean of the Schedule a Program's load names.
        def mean(program, load, key)
          id = program.dig(load, key)
          schedule = id && @schedules[id]
          return nil unless schedule

          @means[id] ||= Derive.mean(ScheduleProfile.call(Schedule::KIND.values(schedule)))
        end
      end
    end
  end
end
