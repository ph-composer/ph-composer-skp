# frozen_string_literal: true

require_relative "test_helper"
require_relative "support/box_zone_fixtures"
require_relative "support/construction_export_fixtures"
require_relative "support/space_fixtures"
require_relative "support/zone_options"

# The Program export over the five prototype journeys in one synthetic Model of three Building Segments, each Zone a
# 3 m box standing alone with one Space on its floor:
#
# - House (journey 1), a single dwelling of three bedrooms: Living 5 × 4 m, Kitchen 4 × 4 and Bedroom 3 × 4.
# - Apartments (journeys 2 and 3): Apt 1 (5 × 5, two bedrooms) and Apt 2 (5 × 5, one bedroom, two units) each its
#   own Dwelling on the residential default; Corridor (2 × 10) and Laundry (3 × 3) in none on the Common Program,
#   Laundry carrying the Laundry Equipment Set.
# - School (journeys 4 and 5), non-residential: Classroom (6 × 5) on the Classroom Program, a 5-day, 44-week
#   Schedule; Lab (4 × 5) on the Lab Program, temperature set point Schedules and a ventilation Schedule, and the
#   Laundry Set.
#
# The golden feeds the Python translation and PHX round trip (tests/python/test_program_sections.py,
# test_program_phx_round_trip.py).
class ProgramExportTest < PhComposerTestCase
  include BoxZoneFixtures
  include ConstructionExportFixtures
  include FixtureFiles
  include SpaceFixtures
  include ZoneOptionsSupport

  API = PhComposer::API
  P = PhComposer::Programs
  O = PhComposer::Zones::Options
  E = P::ProgramExport
  SEGMENT_NAMESPACE = P::Occupancy::SEGMENT_NAMESPACE
  CERTIFICATION = PhComposer::Certification::Segment::NAMESPACE
  FIXTURE = File.join(TESTS_ROOT, "fixtures", "programs", "extraction.json")
  # The result fields each section declares, for the Python sections' test to hold their rows to.
  RESULT_FIELDS = File.join(TESTS_ROOT, "fixtures", "programs", "result_fields.json")
  PRESENCE_MEAN = P::DefaultProgram.mean(P::DefaultProgram::PRESENCE)
  LIGHTING_MEAN = P::DefaultProgram.mean(P::DefaultProgram::LIGHTING)
  FT2 = 1.0 / (0.3048 * 0.3048)
  # Building America as honeybee-ph's Set Residential Program codes it, US gallons a day.
  GALLONS_PER_UNIT = 2.35 + 2.26 + 14 + 3.5 + 12.5
  GALLONS_PER_BEDROOM = 0.78 + 0.75 + 1.17 + 1.17 + 4.16
  LITRES_PER_GALLON = 3.785411784

  def setup
    super
    @model = Sketchup.active_model
    @session = PhComposer::Sessions.for(@model)
    @context = API.connect(:session_id => @session.id)
    @sequence = 0
    @assembly_id = seed_export_construction
  end

  # ---------------------------------------------------------------- the Schedule form

  def test_a_five_day_44_week_schedule_rules_weekdays_and_leaves_a_summer_block_off
    values = { "id" => "sch_A", "type" => "fractional", "days_per_week" => 5, "weeks_per_year" => 44,
               "start_h" => 8, "end_h" => 16, "fraction_on" => 1.0, "fraction_off" => 0.1 }
    record = P::RulesetExport.call(values, "School day")
    assert_equal %w[monday tuesday wednesday thursday friday], record.fetch("operating_weekdays")
    # 56 days off centred on 1 August (day 213): days 185 to 240, 4 July to 28 August.
    assert_equal [[[1, 1], [7, 3]], [[8, 29], [12, 31]]], record.fetch("operating_dates")
    assert_equal [0.1] * 8 + [1.0] * 8 + [0.1] * 8, record.fetch("operating_day")
    assert_equal [0.1] * 24, record.fetch("off_day")
    assert_empty record.fetch("operating_periods"), "occupancy and lighting carry no periods"

    every = P::RulesetExport.call(values.merge("days_per_week" => 7, "weeks_per_year" => 52), "Always")
    assert_nil every.fetch("off_day")
    assert_equal [[[1, 1], [12, 31]]], every.fetch("operating_dates")
    one = P::RulesetExport.operating_dates(1)
    assert_equal [[[1, 1], [1, 8]]], one, "51 weeks off stay inside the year"
  end

  def test_a_ventilation_schedule_carries_its_four_periods_from_midnight
    periods = [["high", 2, 1.0], ["standard", 10, 0.8], ["basic", 8, 0.5], ["minimum", 4, 0.3]]
    values = { "id" => "sch_V", "type" => "ventilation", "days_per_week" => 6, "weeks_per_year" => 52,
               "periods" => periods.map { |name, hours, fraction|
                 { "period" => name, "hours" => hours,
                   "fraction" => fraction }
               } }
    record = P::RulesetExport.call(values, "Lab air")
    assert_equal [%w[high 0 2], %w[standard 2 12], %w[basic 12 20], %w[minimum 20 24]],
                 record.fetch("operating_periods").map { |row|
                   [row["name"], row["start_hour"].to_s,
                    row["end_hour"].to_s]
                 }
    assert_equal [0.3] * 24, record.fetch("off_day"), "a day off runs at the minimum"
    assert_equal "saturday", record.fetch("operating_weekdays").last
  end

  # ---------------------------------------------------------------- the five journeys

  def test_the_five_journeys_preflight_unblocked_with_their_warnings_and_write_the_golden
    journeys
    rows = preflight
    assert_empty rows.select { |row| row.fetch("blocks_export") }, rows.inspect
    codes = rows.map { |row| row.fetch("code") }
    assert_equal 2, codes.count("programs.set_points_disagree"), "Apartments and School"
    lab = rows.find { |row| row.fetch("code") == "programs.equipment_set_non_residential" }
    assert_equal [zone_row("Lab").fetch("reference").slice("zone_id", "zone_path")],
                 lab.dig("locate", "params", "zones")
    assert_equal P::ProgramPreflight::LOCATE, lab.dig("locate", "name")
    write_or_compare(FIXTURE, stable(extract.document))
    write_or_compare(RESULT_FIELDS, E::RESULT_FIELDS)
  end

  # Journey 1: one ProgramType for the house, its counts and devices on its largest Room.
  def test_the_house_is_one_program_type_with_its_counts_and_devices_on_its_largest_room
    journeys
    sections = extract.document.fetch("sections")
    rooms = by_zone(sections.dig(E::ROOMS, "records"))
    types = sections.dig(E::PROGRAM_TYPES, "records").to_h { |row| [row.fetch("id"), row] }
    house = types.fetch(rooms.fetch("Living").fetch("program_type_id"))
    assert_equal 1, %w[Living Kitchen Bedroom].map { |name| rooms.fetch(name).fetch("program_type_id") }.uniq.length
    assert_in_delta 4 / PRESENCE_MEAN / 48, house.dig("people", "people_per_area"), 1e-12,
                    "4 occupants by the Phius rule over 48 m² of floor"
    kwh = (0.2 + (0.8 * 1.0 / 3.7)) * (455 + (0.8 * 48 * FT2)) * 0.8
    assert_in_delta kwh * 1000 / (LIGHTING_MEAN * 8760) / 48, house.dig("lighting", "watts_per_area"), 1e-9
    assert_equal "PhPhiusLightingInterior", house.dig("lighting", "device", "class")
    gallons = GALLONS_PER_UNIT + (3 * GALLONS_PER_BEDROOM)
    assert_in_delta gallons / 24 * LITRES_PER_GALLON / 48, house.dig("service_hot_water", "flow_per_area"), 1e-12
    living = rooms.fetch("Living")
    assert_equal [3.0, 4.0, 8], living.values_at("number_bedrooms", "number_people") << living.fetch("devices").length
    kitchen = rooms.fetch("Kitchen")
    assert_equal [0.0, 0.0, 0], kitchen.values_at("number_bedrooms", "number_people") << kitchen.fetch("devices").length
    assert_equal({ "identifier" => segment_id("House"), "num_dwellings" => 1 }, living.fetch("dwelling"))
  end

  # Journeys 2 and 3: a ProgramType per Dwelling, the default Set's quantities times the units.
  def test_apartments_take_a_program_type_each_and_their_units_multiply_the_devices
    journeys
    sections = extract.document.fetch("sections")
    rooms = by_zone(sections.dig(E::ROOMS, "records"))
    refute_equal rooms.fetch("Apt 1").fetch("program_type_id"), rooms.fetch("Apt 2").fetch("program_type_id")
    assert_equal [1] * 8, rooms.fetch("Apt 1").fetch("devices").map { |row| row.dig("attributes", "quantity") }
    assert_equal [2] * 8, rooms.fetch("Apt 2").fetch("devices").map { |row| row.dig("attributes", "quantity") }
    assert_equal 2, rooms.fetch("Apt 2").dig("dwelling", "num_dwellings")
    assert_equal [1.0, 3.0], rooms.fetch("Apt 2").values_at("number_bedrooms", "number_people"),
                 "one bedroom; the Phius rule's bedrooms + units"
    assert_nil rooms.fetch("Corridor").fetch("dwelling")
    assert_empty rooms.fetch("Corridor").fetch("devices")
    assert_equal %w[PhClothesDryer PhClothesWasher],
                 rooms.fetch("Laundry").fetch("devices").map { |row| row.fetch("class") }.sort
    assert_equal rooms.fetch("Corridor").fetch("program_type_id"), rooms.fetch("Laundry").fetch("program_type_id"),
                 "a Program with no rule exports once"
  end

  # Journeys 4 and 5: the School's Schedules and set points.
  def test_the_school_writes_its_schedules_and_its_first_zones_set_points
    journeys
    sections = extract.document.fetch("sections")
    schedules = sections.dig(E::SCHEDULES, "records").to_h { |row| [row.fetch("name"), row] }
    assert_equal [[[1, 1], [7, 3]], [[8, 29], [12, 31]]], schedules.fetch("School day").fetch("operating_dates")
    assert_equal 4, schedules.fetch("Lab air").fetch("operating_periods").length
    points = sections.dig(E::SET_POINTS, "records").to_h { |row| [row.fetch("name"), row] }
    assert_equal [20.0, 26.0, false], points.fetch("School").values_at("winter_c", "summer_c", "agree"),
                 "the Classroom's, its first Zone's"
    assert_equal [20.0, 25.0, true], points.fetch("House").values_at("winter_c", "summer_c", "agree")
  end

  # ---------------------------------------------------------------- findings

  def test_a_fresh_house_exports_with_no_counts_and_says_so
    house_only
    rows = preflight
    assert_empty rows.select { |row| row.fetch("blocks_export") }
    missing = rows.find { |row| row.fetch("code") == "programs.counts_missing" }
    assert_equal({ "building_segment_id" => segment_id("House") }, missing.dig("locate", "params"))
    rooms = by_zone(extract.document.dig("sections", E::ROOMS, "records"))
    assert_equal [0.0, 0.0], rooms.fetch("Living").values_at("number_bedrooms", "number_people")
  end

  def test_a_program_value_missing_blocks_the_export_and_locates_its_zones
    house_only
    switch_off("House")
    program = create_program("Office", "people" => { "people_per_area" => nil })
    completed(invoke("#{P::FEATURE_ID}.assign_program", "zones" => [reference("Kitchen")], "program_id" => program))

    row = preflight.find { |finding| finding.fetch("code") == "programs.value_missing" }
    assert row.fetch("blocks_export")
    assert_match(/people per area/, row.fetch("message"))
    assert_equal [reference("Kitchen").slice("zone_id", "zone_path")], row.dig("locate", "params", "zones")
    error = assert_raises(PhComposer::Export::Blocked) { extract }
    assert_equal "programs.value_missing", error.code
  end

  def test_a_program_naming_a_schedule_no_longer_in_the_model_blocks
    house_only
    switch_off("House")
    day = create_schedule("Day", "start_h" => 8, "end_h" => 18)
    program = create_program("Office", "lighting" => { "watts_per_area" => 5.0, "schedule_id" => day })
    completed(invoke("#{P::FEATURE_ID}.assign_program", "zones" => [reference("Kitchen")], "program_id" => program))
    # A generic route could leave the reference behind; the Schedule's own delete refuses while it is named.
    @model.attribute_dictionary("ph_composer.records.#{P::SCHEDULE_KIND}").delete_key(day)
    refute(query("#{P::FEATURE_ID}.schedules.all").fetch("records").any? { |row| row.fetch("id") == day })

    row = preflight.find { |finding| finding.fetch("code") == "programs.value_missing" }
    assert row.fetch("blocks_export")
    assert_match(/lighting schedule names a Schedule that is not in the Model/, row.fetch("message"))
    assert_equal "programs.value_missing", assert_raises(PhComposer::Export::Blocked) { extract }.code
  end

  def test_a_heating_schedule_above_the_cooling_set_point_blocks
    house_only
    switch_off("House")
    warm = create_schedule("Warm", "type" => "temperature", "value_c" => 27.0)
    program = create_program("Warm room", "setpoint" => { "heating_schedule_id" => warm,
                                                          "cooling_c" => 22.0 })
    completed(invoke("#{P::FEATURE_ID}.assign_program", "zones" => [reference("Kitchen")], "program_id" => program))

    assert(preflight.any? { |row| row.fetch("code") == "programs.set_points_inverted" && row.fetch("blocks_export") })
    assert_equal "programs.set_points_inverted", assert_raises(PhComposer::Export::Blocked) { extract }.code
  end

  def test_a_rule_program_over_no_dwelling_exports_the_zone_alone_with_a_note
    house_only
    switch_off("House")
    completed(invoke("#{P::FEATURE_ID}.assign_dwelling", "zones" => [reference("Bedroom")], "choice" => "none"))

    row = preflight.find { |finding| finding.fetch("code") == "programs.rule_without_dwelling" }
    refute row.fetch("blocks_export")
    rooms = by_zone(extract.document.dig("sections", E::ROOMS, "records"))
    assert_nil rooms.fetch("Bedroom").fetch("dwelling")
    assert_equal "#{P::DefaultProgram::PROGRAM_ID}-#{rooms.fetch('Bedroom').fetch('id')}",
                 rooms.fetch("Bedroom").fetch("program_type_id")
  end

  def test_a_name_that_reads_as_a_local_path_stays_in_the_model
    house_only
    switch_off("House")
    completed(invoke("#{P::FEATURE_ID}.assign_dwelling", "zones" => [reference("Bedroom")], "choice" => "none"))
    program = create_program("~/standards/office", {})
    completed(invoke("#{P::FEATURE_ID}.assign_program", "zones" => [reference("Bedroom")], "program_id" => program))

    row = preflight.find { |finding| finding.fetch("code") == "programs.rule_without_dwelling" }
    assert_equal P::ProgramPreflight::PATH_LEFT_OUT, row.fetch("message")
    extraction = extract
    types = extraction.document.dig("sections", E::PROGRAM_TYPES, "records")
    bedroom = types.find { |type| type.fetch("program_id") == program }
    assert_equal "#{program} (Bedroom)", bedroom.fetch("name"), "the id takes the name's place"
    notes = extraction.findings.map { |finding| finding.fetch("code") }
    assert_includes notes, E::TEXT_LEFT_OUT
    assert(preflight.any? { |finding| finding.fetch("code") == E::TEXT_LEFT_OUT }, "the preflight says so too")
    refute(extraction.findings.any? { |finding| PhComposer::Diagnostics.absolute_path?(finding.fetch("message")) })
  end

  def test_legacy_zones_export_their_program_alone_and_no_set_points
    @model.entities << box(1000, "L", "Living", "House", [0, 5, 0, 4]) << box(2000, "K", "Kitchen", "House",
                                                                              [6, 10, 0, 4])
    refute(preflight.any? { |row| row.fetch("code").start_with?("programs.") && row.fetch("blocks_export") })
    sections = extract.document.fetch("sections")
    rooms = sections.dig(E::ROOMS, "records")
    assert_equal 2, rooms.map { |row| row.fetch("program_type_id") }.uniq.length, "each Zone a group of its own"
    assert(rooms.all? { |row| row.fetch("dwelling").nil? })
    assert_empty sections.dig(E::SET_POINTS, "records"), "no Segment record, so honeybee-ph's set points"
  end

  def test_a_dwelling_with_no_floor_face_exports_its_rule_loads_at_zero_with_a_note
    house_only
    %w[Living Kitchen Bedroom].each do |name|
      zone_faces(name).each do |face|
        record = Z::Faces::FACE_STORE.read(face)
        Z::Faces::FACE_STORE.write(face, record.merge("face_type" => "Wall")) if record.fetch("face_type") == "Floor"
      end
    end
    row = preflight.find { |finding| finding.fetch("code") == "programs.no_floor_area" }
    refute row.fetch("blocks_export")
    type = extract.document.dig("sections", E::PROGRAM_TYPES, "records").first
    assert_equal [0.0, 0.0], [type.dig("people", "people_per_area"), type.dig("lighting", "watts_per_area")]
  end

  # A Floor the Faces section leaves out, one with no boundary condition, counts no area in the preflight either.
  def test_the_preflight_counts_only_floors_the_export_writes
    house_only
    %w[Living Kitchen Bedroom].each do |name|
      zone_faces(name).each do |face|
        record = Z::Faces::FACE_STORE.read(face)
        next unless record.fetch("face_type") == "Floor"

        Z::Faces::FACE_STORE.write(face, record.reject { |key, _| %w[boundary_condition assembly_id].include?(key) })
      end
    end
    assert(preflight.any? { |finding| finding.fetch("code") == "programs.no_floor_area" })
    notes = extract.findings.map { |finding| finding.fetch("code") }
    assert_includes notes, "programs.no_floor_area", "the export finds the same"
  end

  def test_a_zone_in_no_dwelling_keeps_no_counts_from_a_stale_assignment
    house_only
    switch_off("House")
    completed(invoke("#{P::FEATURE_ID}.assign_dwelling", "zones" => [reference("Bedroom")], "choice" => "none"))
    # The generic metadata route can store counts on a Zone in no Dwelling, which Programs' own actions refuse.
    zone = query("ph_composer.zones.all").fetch("zones").find { |row| row.dig("values", "name") == "Bedroom" }
    completed(invoke("ph_composer.zones.update_metadata", "updates" => [{
      "reference" => zone.fetch("reference"),
      "expected_metadata" => { "user_data" => zone.fetch("user_data", {}),
                               "extension_data" => zone.fetch("extension_data", {}) },
      "extension_payloads" => { P::Occupancy::ZONE_NAMESPACE => P::Occupancy::UNASSIGNED.merge("bedrooms" => 2,
                                                                                               "occupants" => 3) }
    }]))
    assert_equal [2, 3], zone_row("Bedroom").fetch("assignment").values_at("bedrooms", "occupants")
    bedroom = by_zone(extract.document.dig("sections", E::ROOMS, "records")).fetch("Bedroom")
    assert_equal [0.0, 0.0], bedroom.values_at("number_bedrooms", "number_people")
  end

  def test_unreadable_programs_settings_answer_one_blocking_row_and_block_the_export
    house_only
    @model.set_attribute(P::Settings::DICTIONARY, P::Settings::SERVICE.store.key, "{not json")
    row = preflight.find { |finding| finding.fetch("section") == E::ROOMS }
    assert_equal ["record.unreadable", true], row.values_at("code", "blocks_export")
    assert_equal "record.unreadable", assert_raises(PhComposer::Export::Blocked) { extract }.code
  end

  def test_the_report_lists_each_segments_set_points_and_dwellings_in_the_display_units
    result = { "set_points" => [{ "export_identifier" => "bseg_a", "name" => "House", "winter_c" => 20.0,
                                  "summer_c" => 25.0 }],
               "dwellings" => [{ "export_identifier" => "bseg_a", "name" => "House", "units" => 1, "bedrooms" => 3,
                                 "occupants" => nil }] }
    si = P::ProgramReport.call(result, "SI").join
    assert_match(/Heating \(°C\)/, si)
    assert_match(%r{<td>20\.0</td>}, si)
    assert_match(%r{<td>3</td><td>\u2014</td>}, si, "an unknown count is a dash")
    assert_match(%r{<td>68\.0</td>}, P::ProgramReport.call(result, "IP").join)
    assert_empty P::ProgramReport.call({ "set_points" => [] }, "SI")
  end

  def test_the_locate_command_opens_the_zones_view_with_its_zones
    house_only
    opened = []
    @session.define_singleton_method(:open_in_panel) { |owner, intent| opened << [owner, intent] }
    zones = [reference("Living").slice("zone_id", "zone_path")]
    completed(API.view(:context => @context, :name => P::ProgramPreflight::LOCATE,
                       :params => { "zones" => zones, "building_segment_id" => segment_id("House") }))
    assert_equal [["ph_composer.zones", { "view" => "ph_composer.programs.zones", "zones" => zones,
                                          "segmentSettings" => segment_id("House") }]], opened
  end

  private

  def house_only
    @model.entities << box(1000, "L", "Living", "House", [0, 5, 0, 4]) <<
      box(2000, "K", "Kitchen", "House", [6, 10, 0, 4]) << box(3000, "B", "Bedroom", "House", [11, 14, 0, 4])
    adopt_zone_options
  end

  def journeys
    @model.entities << box(1000, "L", "Living", "House", [0, 5, 0, 4]) <<
      box(2000, "K", "Kitchen", "House", [6, 10, 0, 4]) << box(3000, "B", "Bedroom", "House", [11, 14, 0, 4]) <<
      box(4000, "A", "Apt 1", "Apartments", [0, 5, 10, 15]) << box(5000, "C", "Apt 2", "Apartments", [6, 11, 10, 15]) <<
      box(6000, "R", "Corridor", "Apartments", [12, 14, 10, 20]) <<
      box(7000, "W", "Laundry", "Apartments", [15, 18, 10, 13]) <<
      box(8000, "S", "Classroom", "School", [0, 6, 30, 35]) << box(9000, "X", "Lab", "School", [7, 11, 30, 35])
    adopt_zone_options
    completed(save("House", SEGMENT_NAMESPACE => settings("bedrooms" => 3)))
    completed(save("School", CERTIFICATION => certification("non_residential")))
    apartments
    school
  end

  def apartments
    switch_off("Apartments")
    completed(invoke("#{P::FEATURE_ID}.assign_dwelling", "zones" => [reference("Apt 1"), reference("Apt 2")],
                                                         "choice" => "each"))
    completed(invoke("#{P::FEATURE_ID}.assign_dwelling", "zones" => [reference("Corridor"), reference("Laundry")],
                                                         "choice" => "none"))
    completed(invoke("#{P::FEATURE_ID}.set_counts", "zone" => reference("Apt 1"), "bedrooms" => 2, "occupants" => nil))
    completed(invoke("#{P::FEATURE_ID}.set_counts", "zone" => reference("Apt 2"), "bedrooms" => 1, "occupants" => nil))
    apt2 = zone_row("Apt 2").fetch("dwelling_id")
    completed(invoke("#{P::FEATURE_ID}.dwellings.update", "id" => apt2, "values" => { "units" => 2 },
                                                          "expected_values" => { "units" => 1 }))
    common = create_program("Common", "people" => { "people_per_area" => 0.02 },
                                      "lighting" => { "watts_per_area" => 4.0 },
                                      "electric_equipment" => { "watts_per_area" => 0.0 },
                                      "gas_equipment" => { "watts_per_area" => 0.0 },
                                      "service_hot_water" => { "flow_per_area" => 0.0 },
                                      "infiltration" => { "flow_per_exterior_area" => 0.0003 },
                                      "ventilation" => { "flow_per_area" => 0.0003 },
                                      "setpoint" => { "heating_c" => 18.0, "cooling_c" => 26.0 })
    completed(invoke("#{P::FEATURE_ID}.assign_program", "zones" => [reference("Corridor"), reference("Laundry")],
                                                        "program_id" => common))
    @laundry = completed(invoke("#{P::FEATURE_ID}.equipment_sets.create",
                                "values" => { "name" => "Laundry" })).fetch("id")
    %w[clothes_washer clothes_dryer].each do |type|
      completed(invoke("#{P::FEATURE_ID}.equipment_sets.add_device", "id" => @laundry, "type" => type))
    end
    completed(invoke("#{P::FEATURE_ID}.assign_equipment_set", "equipment_set_id" => @laundry,
                                                              "zones" => [reference("Laundry")]))
  end

  def school
    day = create_schedule("School day", "start_h" => 8, "end_h" => 16, "fraction_on" => 1.0, "fraction_off" => 0.0,
                                        "days_per_week" => 5, "weeks_per_year" => 44)
    classroom = create_program("Classroom", "people" => { "people_per_area" => 0.25, "occupancy_schedule_id" => day },
                                            "lighting" => { "watts_per_area" => 8.0, "schedule_id" => day },
                                            "electric_equipment" => { "watts_per_area" => 5.0, "schedule_id" => day },
                                            "gas_equipment" => { "watts_per_area" => 0.0 },
                                            "service_hot_water" => { "flow_per_area" => 0.01 },
                                            "infiltration" => { "flow_per_exterior_area" => 0.0003 },
                                            "ventilation" => { "flow_per_person" => 0.0038 },
                                            "setpoint" => { "heating_c" => 20.0, "cooling_c" => 26.0 })
    periods = [["high", 2, 1.0], ["standard", 10, 0.8], ["basic", 8, 0.5], ["minimum", 4, 0.3]]
    air = create_schedule("Lab air", "type" => "ventilation", "days_per_week" => 6,
                                     "periods" => periods.map { |name, hours, fraction|
                                       { "period" => name, "hours" => hours, "fraction" => fraction }
                                     })
    heat = create_schedule("Lab heating", "type" => "temperature", "value_c" => 21.0)
    cool = create_schedule("Lab cooling", "type" => "temperature", "value_c" => 24.0)
    lab = create_program("Lab", "people" => { "people_per_area" => 0.1 }, "lighting" => { "watts_per_area" => 10.0 },
                                "electric_equipment" => { "watts_per_area" => 20.0 },
                                "gas_equipment" => { "watts_per_area" => 0.0 },
                                "service_hot_water" => { "flow_per_area" => 0.0 },
                                "infiltration" => { "flow_per_exterior_area" => 0.0003 },
                                "ventilation" => { "air_changes_per_hour" => 6.0, "schedule_id" => air },
                                "setpoint" => { "heating_schedule_id" => heat, "cooling_schedule_id" => cool })
    completed(invoke("#{P::FEATURE_ID}.assign_program", "zones" => [reference("Classroom")],
                                                        "program_id" => classroom))
    completed(invoke("#{P::FEATURE_ID}.assign_program", "zones" => [reference("Lab")], "program_id" => lab))
    completed(invoke("#{P::FEATURE_ID}.assign_equipment_set", "equipment_set_id" => @laundry,
                                                              "zones" => [reference("Lab")]))
  end

  def create_program(name, loads)
    values = P::Program::EMPTY.to_h { |key, load| [key, load.merge(loads.fetch(key, {}))] }
    defaults = P::DefaultProgram::PROGRAM
    # A load the journey leaves out takes the residential default's, so only what it names is new.
    values = values.to_h { |key, load| [key, loads.key?(key) ? load : PhComposer::DeepCopy.call(defaults.fetch(key))] }
    %w[people lighting service_hot_water].each { |key| values.fetch(key)["rule"] = nil if loads.key?(key) }
    completed(invoke("#{P::FEATURE_ID}.programs.create", "values" => values.merge("name" => name))).fetch("id")
  end

  def create_schedule(name, values)
    completed(invoke("#{P::FEATURE_ID}.schedules.create", "values" => values.merge("name" => name))).fetch("id")
  end

  def switch_off(segment)
    completed(save(segment, SEGMENT_NAMESPACE => settings("single_dwelling" => false)))
  end

  def settings(values = {})
    P::Occupancy::SEGMENT_DEFAULTS.merge(values)
  end

  def certification(category)
    PhComposer::Certification::Segment::DEFAULTS.merge("category" => category)
  end

  def save(name, payloads)
    all = query("#{O::PREFIX}.all")
    row = all.fetch("building_segments").find { |candidate| candidate.dig("values", "name") == name }
    default_id = all.fetch("default_segment_id")
    values = row.fetch("values").slice("name", "colour")
    invoke(O::SegmentSettings::SAVE, "id" => row.fetch("id"), "values" => values, "expected_values" => values,
                                     "default" => default_id == row.fetch("id"),
                                     "expected_default_segment_id" => default_id, "extension_payloads" => payloads,
                                     "expected_extension_data" => row.fetch("extension_data", {}))
  end

  def segment_id(name)
    query("#{O::PREFIX}.all").fetch("building_segments").find { |row| row.dig("values", "name") == name }.fetch("id")
  end

  def zone_row(name)
    query("#{P::FEATURE_ID}.zones").fetch("zones").find { |row| row.fetch("name") == name }
  end

  def reference(name)
    zone_row(name).fetch("reference")
  end

  def by_zone(records)
    names = query("ph_composer.zones.all").fetch("zones").to_h do |row|
      [row.dig("reference", "zone_id"), row.dig("values", "name")]
    end
    records.to_h { |row| [names.fetch(row.fetch("id")), row] }
  end

  def preflight
    completed(API.export_preflight(:context => @context)).fetch("findings")
  end

  def extract
    PhComposer::Export::Collection.build(@model, :run_id => "program-export")
  end

  # The document with the ids each run mints renumbered: Building Segments by name, then Programs, Schedules,
  # Equipment Sets and Dwellings by name, so the golden compares.
  def stable(document)
    fixed = {}
    { "bsg" => query("#{O::PREFIX}.all").fetch("building_segments").map { |row|
      [row.dig("values", "name"),
       row.fetch("id")]
    },
      "pgm" => listed("programs"), "sch" => listed("schedules"), "eqs" => listed("equipment_sets"),
      "dwl" => query("#{P::FEATURE_ID}.dwellings").fetch("dwellings").filter_map { |row|
        row.fetch("id") && [row.fetch("name"), row.fetch("id")]
      } }.each do |prefix, rows|
      rows.reject { |_name, id| id.include?("PHCDEFAULT") }.sort.each_with_index do |(_name, id), index|
        fixed[id] = format("#{prefix}_FIXED%<number>07d", :number => index + 1)
      end
    end
    devices = query("#{P::FEATURE_ID}.equipment_sets.all").fetch("records").sort_by { |row| row.dig("values", "name") }
                                                          .flat_map { |row| row.dig("values", "devices") }
    devices.map { |device| device.fetch("id") }.reject { |id| id.include?("PHCDEFAULT") }.each_with_index do |id, index|
      fixed[id] = format("dev_FIXED%<number>07d", :number => index + 1)
    end
    pattern = /\b(?:bsg|pgm|sch|eqs|dwl|dev)_[A-Za-z0-9]{12}\b/
    stable = JSON.parse(JSON.generate(document).gsub(pattern) { |id| fixed.fetch(id, id) })
    # Records in id order follow the minted ids, so they are put in renumbered order.
    stable.fetch("sections").each_value { |section| section.fetch("records").sort_by! { |row| row.fetch("id").to_s } }
    stable
  end

  def listed(kind)
    query("#{P::FEATURE_ID}.#{kind}.all").fetch("records").map { |row| [row.dig("values", "name"), row.fetch("id")] }
  end

  def query(name, params = {})
    completed(API.query(:context => @context, :name => name, :params => params))
  end

  def completed(outcome)
    assert_equal "completed", outcome.fetch("status"), outcome.inspect
    outcome.fetch("value")
  end

  def invoke(name, params)
    API.invoke(:context => @context, :name => name, :params => params,
               :request => { "sequence" => @sequence += 1, "expected_revision" => @session.revision })
  end
end
