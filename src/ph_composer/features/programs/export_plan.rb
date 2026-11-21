# frozen_string_literal: true

module PhComposer
  module Programs
    # Pure: everything the Program export writes, worked out from plain records (context/CONTRACTS.md, "Program
    # export"). The export reads its inputs from the snapshot and the preflight reads them live; both hand them here,
    # so the rows a preflight shows are the ones an export stops or notes on. Values are SI and honeybee units; the
    # translation builds honeybee objects from them and computes nothing of its own beyond honeybee's conversions
    # (python/ph_composer_translation/program_sections.py).
    #
    # Each exported Zone's effective Program and Dwelling follow Derive, as the Zones / Programs view reads them. A
    # Program with a Phius rule (People `phius_residential`, Lighting `phius_interior`, Service hot water
    # `building_america`) becomes one ProgramType per Dwelling, its rule loads worked out over that Dwelling as
    # honeybee-ph's Set Residential Program does (honeybee_grasshopper_ph at 8967c64c,
    # `gh_compo_io/program/set_res_program.py`): people per area from its occupants over the presence Schedule's
    # mean and its Rooms' floor area, lighting per area from the Phius interior formula over its iCFA and units, hot
    # water per area from Building America by bedrooms. Every other Program becomes one ProgramType.
    module ExportPlan
      HOURS_PER_YEAR = Derive::HOURS_PER_YEAR
      L_PER_US_GALLON = 3.785411784
      # Building America 2014 Table 11 as Set Residential Program codes it, gallons a day: a constant per dwelling
      # unit and a coefficient per bedroom for the clothes washer, dishwasher, shower, bath and sinks. The component's
      # shower coefficient is 1.17 where its docstring and the table say 4.67 (F4a-20); this matches the code.
      HOT_WATER_PER_UNIT = 2.35 + 2.26 + 14.0 + 3.5 + 12.5
      HOT_WATER_PER_BEDROOM = 0.78 + 0.75 + 1.17 + 1.17 + 4.16
      VENTILATION_TERMS = %w[flow_per_person flow_per_area flow_per_zone air_changes_per_hour].freeze
      RULES = { "people" => "phius_residential", "lighting" => "phius_interior",
                "service_hot_water" => "building_america" }.freeze

      # The records read: values by id (each with its "id") and the Model's two effective defaults.
      Catalog = Struct.new(:programs, :schedules, :equipment_sets, :default_program_id, :default_equipment_set_id,
                           keyword_init: true)
      # One exported Zone's areas: its Spaces' floor area and iCFA, and its Room's Floor Face area, which honeybee
      # multiplies a per-area load by (nil in a preflight, which builds nothing).
      Area = Struct.new(:floor_area_m2, :icfa_m2, :room_floor_area_m2, keyword_init: true)
      # `state` holds the exported Zones only (OccupancyState::State); `export_identifiers` each exported Segment's.
      Input = Struct.new(:state, :catalog, :areas, :export_identifiers, keyword_init: true)
      # One row: `blocks` stops the export; `zone_ids` and `segment_id` are what a locate opens.
      Finding = Struct.new(:code, :record_id, :message, :blocks, :zone_ids, :segment_id, keyword_init: true)
      Plan = Struct.new(:schedules, :program_types, :rooms, :segments, keyword_init: true)

      # One exported Zone resolved: its Program id and record (nil when gone), its Dwelling (Derive.dwelling) and
      # its Derive::Zone input.
      Row = Struct.new(:zone, :segment, :program_id, :program, :dwelling, :input, keyword_init: true) do
        def key
          dwelling && dwelling.fetch("key")
        end
      end

      module_function

      # ---------------------------------------------------------------- resolving

      def rows(input)
        dwellings = input.state.dwellings.to_h { |record| [record.fetch("id"), record] }
        input.state.zones.sort_by(&:id).map do |zone|
          segment = input.state.segment(zone.segment_id)
          program_id = Derive.program_id(zone, segment, input.catalog.default_program_id)
          area = input.areas.fetch(zone.id)
          Row.new(:zone => zone, :segment => segment, :program_id => program_id,
                  :program => input.catalog.programs[program_id],
                  :dwelling => Derive.dwelling(zone, segment, dwellings),
                  :input => Derive::Zone.new(:id => zone.id, :segment_id => zone.segment_id,
                                             :assignment => zone.assignment, :floor_area_m2 => area.floor_area_m2,
                                             :icfa_m2 => area.icfa_m2))
        end
      end

      # Each Dwelling's rows, by key, and its counts (Derive.counts).
      def groups(rows)
        rows.select(&:dwelling).group_by(&:key)
      end

      def counts(group)
        Derive.counts(group.first.dwelling, group.map(&:input))
      end

      # A Zone in no Dwelling is a group of its own, one unit, as honeybee-ph's Set Residential Program works its
      # rules over an untagged Room alone; its counts are its own, which only a Dwelling's Zone takes, so none.
      SOLO = { "units" => 1, "bedrooms" => nil, "occupants" => nil, "single" => false }.freeze

      def group_of(row, groups)
        row.dwelling ? groups.fetch(row.key) : [row]
      end

      def counts_of(row, group)
        row.dwelling ? counts(group) : Derive.counts(SOLO, [])
      end

      def units_of(row)
        row.dwelling ? row.dwelling.fetch("units") : 1
      end

      def rule?(program)
        RULES.any? { |load, _rule| program.dig(load, "rule") }
      end

      # ---------------------------------------------------------------- findings

      # Every row the export blocks or notes on, the same from the snapshot and live.
      def findings(input)
        rows = rows(input)
        program_findings(rows, input.catalog) + dwelling_findings(input, rows) + segment_findings(input, rows) +
          equipment_findings(rows, input.catalog) + text_findings(rows, input.catalog)
      end

      # Every name or device comment the export would write that reads as a local file path, which stays in the
      # Model (its id, its type or nothing takes its place): the export refuses a path in the HBJSON or its result.
      def text_findings(rows, catalog)
        texts = rows.flat_map { |row| row_texts(row, catalog) }
        texts.select { |_id, text| Diagnostics.absolute_path?(text.to_s.strip) }.uniq.map do |id, _text|
          warn("programs.text_left_out", id, "A name or device comment that reads as a local file path stays in " \
                                             "the Model; the export writes its id, its type or nothing in its place.",
               [], nil)
        end
      end

      # The [record id, text] pairs the export writes for one Zone's Room: its Program's name and its Schedules',
      # its Dwelling's and Segment's names, and its Equipment Set's device names and comments.
      def row_texts(row, catalog)
        texts = []
        if row.program
          texts << [row.program_id, row.program.fetch("name")]
          Program::SLOTS.each_key do |slot|
            id = row.program.dig(*slot.split("."))
            texts << [id, catalog.schedules[id]&.fetch("name")] if id
          end
        end
        texts << [row.dwelling["id"] || row.segment&.id, row.dwelling.fetch("name")] if row.dwelling
        texts << [row.segment.id, row.segment.name] if row.segment
        set = catalog.equipment_sets[equipment_set_id(row, catalog)]
        Array(set && set["devices"]).each do |device|
          texts << [device.fetch("id"), device["display_name"]] << [device.fetch("id"), device["comment"]]
        end
        texts
      end

      def program_findings(rows, catalog)
        rows.group_by(&:program_id).flat_map do |program_id, used|
          zone_ids = used.map { |row| row.zone.id }
          program = used.first.program
          next [block("programs.value_missing", program_id, "#{names(used)} use a Program that is not in the " \
                                                            "Model.", zone_ids)] unless program

          name = program.fetch("name")
          found = missing(program, catalog.schedules).map do |what|
            block("programs.value_missing", program_id, "#{name}: #{what}.", zone_ids)
          end
          heating, cooling = set_point_pair(program, catalog.schedules)
          if heating && cooling && heating > cooling
            found << block("programs.set_points_inverted", program_id, "#{name}'s heating set point, " \
                                                                       "#{heating} °C, is above its cooling set " \
                                                                       "point, #{cooling} °C.", zone_ids)
          end
          # A legacy Zone names no Segment record, so it has no Dwelling to put it in: no note.
          alone = used.select { |row| row.dwelling.nil? && row.segment }
          if rule?(program) && !alone.empty?
            found << warn("programs.rule_without_dwelling", program_id,
                          "#{names(alone)} use #{name}, whose Phius rules work over a Dwelling, and are in none: " \
                          "each exports as one unit with no occupants. Put them in a Dwelling, or give them a " \
                          "Program of their own.", alone.map { |row| row.zone.id })
          end
          found
        end
      end

      # What a Program lacks that its ProgramType needs. A Schedule left empty is honeybee's Always On, except where
      # a Phius rule divides by its mean.
      def missing(program, schedules)
        found = []
        people = program.fetch("people")
        if people["rule"]
          found << "its occupancy Schedule is missing or never occupied" unless mean(schedules,
                                                                                     people["occupancy_schedule_id"])
        elsif people["people_per_area"].nil?
          found << "people per area is missing"
        end
        lighting = program.fetch("lighting")
        if lighting["rule"]
          found << "its lighting Schedule is missing or never on" unless mean(schedules, lighting["schedule_id"])
        elsif lighting["watts_per_area"].nil?
          found << "lighting W per area is missing"
        end
        { "electric_equipment" => "electric equipment", "gas_equipment" => "gas equipment" }.each do |key, label|
          found << "#{label} W per area is missing" if program.dig(key, "watts_per_area").nil?
        end
        water = program.fetch("service_hot_water")
        found << "hot water flow per area is missing" if !water["rule"] && water["flow_per_area"].nil?
        found << "infiltration per exterior area is missing" if program.dig("infiltration", "flow_per_exterior_area")
                                                                       .nil?
        if VENTILATION_TERMS.all? { |key| program.dig("ventilation", key).nil? }
          found << "ventilation sets no rate"
        end
        heating, cooling = set_point_pair(program, schedules)
        found << "the heating set point is missing" if heating.nil?
        found << "the cooling set point is missing" if cooling.nil?
        found
      end

      # The positive mean of a fractional Schedule's day, or nil.
      def mean(schedules, id)
        schedule = id && schedules[id]
        value = schedule && Derive.mean(ScheduleProfile.call(schedule))
        value&.positive? ? value : nil
      end

      # A Program's heating and cooling set points, °C: each a constant or its temperature Schedule's value.
      def set_point_pair(program, schedules)
        setpoint = program.fetch("setpoint")
        %w[heating cooling].map do |side|
          schedule = schedules[setpoint["#{side}_schedule_id"]]
          schedule ? schedule["value_c"] : setpoint["#{side}_c"]
        end
      end

      # A Dwelling whose Zones use a Phius rule: its unknown bedrooms or occupants export as 0, and with no Floor Face
      # area its rule loads have nothing to share over and export at 0 per m² (honeybee-ph's Set Residential Program
      # refuses such Rooms; PHX reads the People counts and the devices either way).
      def dwelling_findings(input, rows)
        groups(rows).flat_map do |_key, group|
          next [] unless group.any? { |row| row.program && rule?(row.program) }

          dwelling = group.first.dwelling
          single = dwelling.fetch("single")
          zone_ids = single ? [] : group.map { |row| row.zone.id }
          segment_id = single ? group.first.segment.id : nil
          record_id = dwelling["id"] || group.first.segment.id
          found = []
          missing = %w[bedrooms occupants].select { |key| counts(group)[key].nil? }
          unless missing.empty?
            found << warn("programs.counts_missing", record_id,
                          "Enter the bedrooms of #{dwelling.fetch('name')}: it exports with no " \
                          "#{missing.join(' or ')}, so WUFI-Passive and METr count none.", zone_ids, segment_id)
          end
          floors = group.map { |row| input.areas.fetch(row.zone.id).room_floor_area_m2 }
          if floors.none?(&:nil?) && !floors.sum.positive?
            found << warn("programs.no_floor_area", record_id,
                          "#{dwelling.fetch('name')}'s Zones have no Floor Face, so its Phius rule loads export at 0 " \
                          "per m² and EnergyPlus sees no people, lighting or hot water there.",
                          group.map { |row| row.zone.id })
          end
          found
        end
      end

      # A Segment whose Zones' Programs give more than one pair of set points: it carries its first Zone's.
      def segment_findings(input, rows)
        rows.group_by { |row| row.zone.segment_id }.filter_map do |segment_id, members|
          segment = members.first.segment
          next if segment.nil?

          points = segment_set_points(members, input.catalog)
          next if points.fetch("agree")

          warn("programs.set_points_disagree", segment_id,
               "The Programs of #{segment.name}'s Zones give different set points; it exports " \
               "#{format_c(points['heating_c'])} °C heating and #{format_c(points['cooling_c'])} °C cooling, from " \
               "#{members.find(&:program)&.zone&.name}'s Program.", members.map { |row| row.zone.id }, segment_id)
        end
      end

      def format_c(value)
        value.nil? ? "no" : format("%g", value)
      end

      # A Segment's set points: its Zones' Programs' pairs in Zone id order, the first exported.
      def segment_set_points(members, catalog)
        programs = members.filter_map(&:program).uniq
        Derive.set_points(programs, catalog.schedules)
      end

      # A Zone carrying an Equipment Set in a non-residential Segment, where PHX drops the devices; and a Set no
      # longer in the Model.
      def equipment_findings(rows, catalog)
        found = []
        rows.each do |row|
          set_id = equipment_set_id(row, catalog)
          next unless set_id

          unless catalog.equipment_sets.key?(set_id)
            found << block("programs.value_missing", set_id, "#{row.zone.name} uses an Equipment Set that is not " \
                                                             "in the Model.", [row.zone.id])
            next
          end
          next unless row.segment&.category == "non_residential"

          found << warn("programs.equipment_set_non_residential", row.zone.id,
                        "#{row.zone.name} carries an Equipment Set in #{row.segment.name}, a non-residential " \
                        "Building Segment, where its Program's equipment watts stand for the equipment: the Set's " \
                        "devices are left out of the export.", [row.zone.id])
        end
        found.uniq { |finding| [finding.code, finding.record_id] }
      end

      # The Set a Zone's devices come from: its Dwelling's, else the Model's default; a Zone in none, its own.
      def equipment_set_id(row, catalog)
        return row.zone.assignment["equipment_set_id"] unless row.dwelling

        row.dwelling["equipment_set_id"] || catalog.default_equipment_set_id
      end

      NAMED = 5

      # The Zones' names, the first five and how many more, so a message stays short however many Zones it covers.
      def names(rows)
        listed = rows.first(NAMED).map { |row| row.zone.name }.join(", ")
        rows.length > NAMED ? "#{listed} and #{rows.length - NAMED} more" : listed
      end

      def block(code, record_id, message, zone_ids)
        Finding.new(:code => code, :record_id => record_id, :message => message, :blocks => true,
                    :zone_ids => zone_ids, :segment_id => nil)
      end

      def warn(code, record_id, message, zone_ids, segment_id = nil)
        Finding.new(:code => code, :record_id => record_id, :message => message, :blocks => false,
                    :zone_ids => zone_ids, :segment_id => segment_id)
      end

      # ---------------------------------------------------------------- the plan

      # What the export writes. Call it only once `findings` holds no blocking row: it reads every Program, Set and
      # Dwelling as whole.
      # `text` makes a name or comment safe for the HBJSON (ExportText.safe).
      def call(input, text: ->(value, _fallback) { value })
        rows = rows(input)
        groups = groups(rows)
        catalog = input.catalog
        types = {}
        rooms = rows.map do |row|
          group = group_of(row, groups)
          type = program_type(row, group, input, text)
          types[type.fetch("id")] ||= type
          room(row, group, type.fetch("id"), input, text)
        end
        # In an order of names, not of the ids a Model mints, so a golden compares.
        types = types.values.sort_by { |type| [type.fetch("name"), type.fetch("id")] }
        Plan.new(:schedules => schedules(types, catalog, text), :program_types => types, :rooms => rooms,
                 :segments => segments(input, rows, groups, text))
      end

      # The ProgramType a Zone's Room carries: its Program's, or its Program's over its Dwelling, or over the Zone
      # alone in none, when a rule applies.
      def program_type(row, group, input, text)
        program = row.program
        rule = rule?(program)
        over = row.dwelling ? dwelling_identifier(row) : row.zone.id
        id = rule ? "#{row.program_id}-#{over}" : row.program_id
        name = text.call(program.fetch("name"), row.program_id)
        group_name = row.dwelling ? row.dwelling.fetch("name") : row.zone.name
        values = rule ? rule_values(program, row, group, input) : {}
        { "id" => id, "program_id" => row.program_id,
          "name" => rule ? "#{name} (#{text.call(group_name, over)})" : name,
          "people" => people(program, values), "lighting" => lighting(program, values, id),
          "electric_equipment" => equipment(program, "electric_equipment"),
          "gas_equipment" => equipment(program, "gas_equipment"),
          "service_hot_water" => hot_water(program, values),
          "infiltration" => program.fetch("infiltration").slice("flow_per_exterior_area", "schedule_id"),
          "ventilation" => ventilation(program), "setpoint" => setpoint(row.program_id, program) }
      end

      # The rule loads of `program` over one Dwelling's Rooms, each per m² of their Floor area (0 with none).
      def rule_values(program, row, group, input)
        counts = counts_of(row, group)
        units = units_of(row)
        floor = group.sum { |member| input.areas.fetch(member.zone.id).room_floor_area_m2.to_f }
        icfa = group.sum { |member| member.input.icfa_m2 }
        per_floor = ->(value) { floor.positive? ? value / floor : 0.0 }
        schedules = input.catalog.schedules
        values = {}
        if program.dig("people", "rule")
          presence = mean(schedules, program.dig("people", "occupancy_schedule_id"))
          values["people_per_area"] = per_floor.call(counts["occupants"].to_f / presence)
        end
        if program.dig("lighting", "rule")
          kwh = Derive.lighting_interior_kwh(icfa * Derive::FT2_PER_M2,
                                             program.dig("lighting", "high_efficacy_fraction"), units)
          peak = kwh * 1000.0 / (mean(schedules, program.dig("lighting", "schedule_id")) * HOURS_PER_YEAR)
          values["watts_per_area"] = per_floor.call(peak)
        end
        if program.dig("service_hot_water", "rule")
          gallons = (HOT_WATER_PER_UNIT * units) + (HOT_WATER_PER_BEDROOM * counts["bedrooms"].to_f)
          values["flow_per_area"] = per_floor.call(gallons / 24.0 * L_PER_US_GALLON)
        end
        values
      end

      def people(program, values)
        load = program.fetch("people")
        { "people_per_area" => values.fetch("people_per_area", load["people_per_area"]),
          "occupancy_schedule_id" => load["occupancy_schedule_id"],
          "activity_schedule_id" => load["activity_schedule_id"], "radiant_fraction" => load["radiant_fraction"],
          "latent_fraction" => load["latent_fraction"] }
      end

      # The Phius interior lighting rule carries its honeybee-ph device, as Set Residential Program does; PHX takes
      # the Lighting of a Segment's first Room, so it reads one.
      def lighting(program, values, type_id)
        load = program.fetch("lighting")
        device = if load["rule"]
                   attributes = EquipmentTypes.hbph(EquipmentTypes.device("phius_lighting_interior", "dev_rule",
                                                                          "high_efficacy_fraction" =>
                                                                            load["high_efficacy_fraction"]), 1)
                   attributes.merge("identifier" => "#{type_id}-lighting_interior")
                 end
        { "watts_per_area" => values.fetch("watts_per_area", load["watts_per_area"]),
          "schedule_id" => load["schedule_id"], "return_air_fraction" => load["return_air_fraction"],
          "radiant_fraction" => load["radiant_fraction"], "visible_fraction" => load["visible_fraction"],
          "device" => device }
      end

      def equipment(program, key)
        program.fetch(key).slice("watts_per_area", "schedule_id", "radiant_fraction", "latent_fraction",
                                 "lost_fraction")
      end

      def hot_water(program, values)
        load = program.fetch("service_hot_water")
        { "flow_per_area" => values.fetch("flow_per_area", load["flow_per_area"]),
          "target_temperature_c" => load["target_temperature_c"], "schedule_id" => load["schedule_id"],
          "sensible_fraction" => load["sensible_fraction"], "latent_fraction" => load["latent_fraction"] }
      end

      # Ventilation sums its four terms; a term left empty is 0.
      def ventilation(program)
        load = program.fetch("ventilation")
        VENTILATION_TERMS.to_h { |key| [key, load[key].to_f] }.merge("schedule_id" => load["schedule_id"])
      end

      # A set point given as a number exports as a constant Schedule of its own, named for its Program. Composite
      # identifiers join record ids with "-", so each id stays a whole word in them.
      def setpoint(program_id, program)
        load = program.fetch("setpoint")
        { "heating_schedule_id" => load["heating_schedule_id"] || "#{program_id}-heating_setpoint",
          "cooling_schedule_id" => load["cooling_schedule_id"] || "#{program_id}-cooling_setpoint",
          "dehumidify_rh" => load["dehumidify_rh"], "humidify_rh" => load["humidify_rh"] }
      end

      def dwelling_identifier(row)
        row.dwelling["id"] || row.segment.id
      end

      # Every Schedule the ProgramTypes name, as RulesetExport writes it, and a constant for each set point given as
      # a number, in id order.
      def schedules(types, catalog, text)
        records = {}
        types.each do |type|
          program = catalog.programs.fetch(type.fetch("program_id"))
          %w[people lighting electric_equipment gas_equipment service_hot_water infiltration ventilation]
            .each do |load|
              type.fetch(load).each do |key, id|
                next unless key.end_with?("schedule_id") && id

                schedule = catalog.schedules.fetch(id)
                records[id] ||= RulesetExport.call(schedule, text.call(schedule.fetch("name"), id))
              end
            end
          %w[heating cooling].each do |side|
            id = type.dig("setpoint", "#{side}_schedule_id")
            records[id] ||= if catalog.schedules.key?(id)
                              schedule = catalog.schedules.fetch(id)
                              RulesetExport.call(schedule, text.call(schedule.fetch("name"), id))
                            else
                              RulesetExport.constant(id, "#{text.call(program.fetch('name'), program.fetch('id'))} " \
                                                         "#{side} set point", program.dig("setpoint", "#{side}_c"))
                            end
          end
        end
        records.values.sort_by { |record| record.fetch("id") }
      end

      # ---------------------------------------------------------------- Rooms

      # One Room: its ProgramType, its People extension's counts and Dwelling, and its devices.
      def room(row, group, type_id, input, text)
        counts = if row.dwelling
                   room_counts(row, group, input)
                 else
                   counts_of(row, group).slice("bedrooms", "occupants").transform_values(&:to_f)
                 end
        dwelling = row.dwelling && { "identifier" => dwelling_identifier(row), "num_dwellings" =>
          row.dwelling.fetch("units") }
        { "id" => row.zone.id, "program_type_id" => type_id, "number_bedrooms" => counts.fetch("bedrooms"),
          "number_people" => counts.fetch("occupants"), "dwelling" => dwelling,
          "devices" => devices(row, group, input, text) }
      end

      # A Zone's share of its Dwelling's counts, so its Rooms sum to the Dwelling's: each Zone's own while the
      # Dwelling's count is its Zones' sum; else, its own count or the Phius rule's, all on its largest Room.
      def room_counts(row, group, input)
        counts = counts(group)
        dwelling = row.dwelling
        largest = largest(group, input).zone.id == row.zone.id
        bedrooms = (largest_share(largest, counts["bedrooms"]) if dwelling["bedrooms"] || dwelling.fetch("single"))
        occupants = if dwelling["occupants"] || dwelling.fetch("single") || counts.fetch("occupants_rule")
                      largest_share(largest, counts["occupants"])
                    end
        { "bedrooms" => bedrooms || row.zone.assignment["bedrooms"].to_f,
          "occupants" => occupants || row.zone.assignment["occupants"].to_f }
      end

      def largest_share(largest, value)
        largest ? value.to_f : 0.0
      end

      # A Dwelling's largest Room by Floor area, the first by Zone id among equals.
      def largest(group, input)
        group.min_by { |row| [-input.areas.fetch(row.zone.id).room_floor_area_m2.to_f, row.zone.id] }
      end

      # A Dwelling's Set, once on its largest Room, each device's quantity times the Dwelling's units: PHX merges
      # devices across a Segment's Rooms by identifier and sums their quantities. A Zone in no Dwelling carries its
      # own Set's devices as they are. Each device's annual inputs are its Dwelling's, for the Process watts
      # honeybee-ph works out (EnergyPlus only; PHX reads the device).
      def devices(row, group, input, text)
        catalog = input.catalog
        set_id = equipment_set_id(row, catalog)
        return [] unless set_id
        return [] if largest(group, input).zone.id != row.zone.id
        # PHX takes a non-residential Room's equipment from its Program's watts and its Process loads' watts, so a
        # device there would count twice.
        return [] if row.segment&.category == "non_residential"

        units = units_of(row)
        counts = counts_of(row, group)
        icfa = group.sum { |member| member.input.icfa_m2 }
        catalog.equipment_sets.fetch(set_id).fetch("devices").map do |device|
          hbph = EquipmentTypes.hbph(device, device.fetch("quantity") * units)
          attributes = hbph.fetch("attributes")
          attributes["display_name"] = text.call(attributes.fetch("display_name"),
                                                 EquipmentTypes.fetch(device.fetch("type")).fetch("label"))
          attributes["comment"] = text.call(attributes.fetch("comment"), "")
          hbph.merge("identifier" => "#{set_id}-#{device.fetch('id')}",
                     "process_id" => "#{row.zone.id}-#{set_id}-#{device.fetch('id')}",
                     "occupants" => counts["occupants"].to_f, "bedrooms" => counts["bedrooms"].to_f,
                     "floor_area_ft2" => icfa * Derive::FT2_PER_M2)
        end
      end

      # ---------------------------------------------------------------- Segments

      # Each exported Segment's set points and, for the report, its Dwellings' counts. A legacy Zone names no Segment
      # record, so its BldgSegment keeps honeybee-ph's set points.
      def segments(input, rows, groups, text)
        rows.group_by { |row| row.zone.segment_id }.reject { |_id, members| members.first.segment.nil? }
            .sort_by { |segment_id, _members| input.export_identifiers.fetch(segment_id) }.map do |segment_id, members|
          points = segment_set_points(members, input.catalog)
          keys = members.filter_map(&:key).uniq.sort_by { |key| [groups.fetch(key).first.dwelling.fetch("name"), key] }
          dwellings = keys.map do |key|
            group = groups.fetch(key)
            counts = counts(group)
            { "name" => text.call(group.first.dwelling.fetch("name"), dwelling_identifier(group.first)),
              "units" => group.first.dwelling.fetch("units"), "bedrooms" => counts["bedrooms"],
              "occupants" => counts["occupants"] }
          end
          { "id" => segment_id, "export_identifier" => input.export_identifiers.fetch(segment_id),
            "name" => text.call(members.first.segment.name, segment_id), "winter_c" => points.fetch("heating_c"),
            "summer_c" => points.fetch("cooling_c"), "agree" => points.fetch("agree"),
            "dwellings" => dwellings }
        end
      end
    end
  end
end
