# frozen_string_literal: true

require_relative "test_helper"
require_relative "support/space_fixtures"
require_relative "support/zone_options"

# Dwellings, each Zone's assignment and Single dwelling per Building Segment, over a synthetic house and an
# apartment block (planning ACCEPTANCE, reference models 1 and 2): House holds Living (5 × 4 m), Bedroom (3 × 4)
# and Bath (2 × 2, its floor weighted 0.5, so the house has 36 m² of floor and 34 m² of iCFA); Apartments holds
# Apt 1 (5 × 5), Apt 1 bed (5 × 5) and Corridor (2 × 10). Every Zone has one Space on its floor, 2.5 m high. The
# assignment is the programs feature's extension on each Zone and the occupancy settings its extension on each
# Segment; Zones stages both.
class OccupancyAssignmentsTest < PhComposerTestCase
  include SpaceFixtures
  include ZoneOptionsSupport

  API = PhComposer::API
  P = PhComposer::Programs
  O = PhComposer::Zones::Options
  ZONE_NAMESPACE = P::Occupancy::ZONE_NAMESPACE
  SEGMENT_NAMESPACE = P::Occupancy::SEGMENT_NAMESPACE
  CERTIFICATION = PhComposer::Certification::Segment::NAMESPACE
  # The pinned honeybee-ph default presence and lighting means (DefaultProgram), and
  # phius_residential.lighting_interior(34 m² in ft², 1.0, units) run from the vendored 1.33.68 wheel, for one
  # unit and for two.
  PRESENCE_MEAN = 17.3 / 24
  LIGHTING_MEAN = 1.0 / 24
  HOUSE_LIGHTING_KWH = 248.98998476435392
  TWO_UNIT_LIGHTING_KWH = 400.4926874670566

  def setup
    super
    @model = Sketchup.active_model
    @session = PhComposer::Sessions.for(@model)
    @context = API.connect(:session_id => @session.id)
    @sequence = 0
    @model.entities << zone(1000, "L", "Living", "House", [0, 0, 5, 4]) <<
      zone(2000, "B", "Bedroom", "House",
           [5, 0, 3, 4]) << zone(3000, "T", "Bath", "House", [8, 0, 2, 2], :weighting => 0.5) <<
      zone(4000, "A", "Apt 1", "Apartments",
           [0, 10, 5, 5]) << zone(5000, "C", "Apt 1 bed", "Apartments", [5, 10, 5, 5]) <<
      zone(6000, "R", "Corridor", "Apartments", [10, 10, 2, 10])
    adopt_zone_options
  end

  # ---------------------------------------------------------------- defaults and Single dwelling as read

  def test_an_absent_payload_reads_as_single_dwelling_and_a_non_residential_segment_is_never_one
    rows = segments
    assert_equal [true, true], rows.values.map { |row| row.fetch("single_dwelling") }
    assert_equal false, rows.fetch("House").fetch("stored")
    assert_equal "House", zone_row("Living").fetch("dwelling_name")
    assert_nil zone_row("Living").fetch("dwelling_id"), "the house is no record"

    completed(save("Apartments", CERTIFICATION => certification("non_residential")))
    apartments = segments.fetch("Apartments")
    assert_equal false, apartments.fetch("single_dwelling")
    assert_nil zone_row("Apt 1").fetch("dwelling_name")
    refute_includes codes(apartments), "programs.single_dwelling_no_effect",
                    "an absent payload is the default, not a choice to report"

    completed(save("Apartments", SEGMENT_NAMESPACE => settings("single_dwelling" => true)))
    assert_equal false, segments.fetch("Apartments").fetch("single_dwelling")
    assert_includes codes(segments.fetch("Apartments")), "programs.single_dwelling_no_effect"
  end

  # ---------------------------------------------------------------- Single dwelling on and off

  def test_switching_off_makes_the_house_a_dwelling_its_zones_keep_in_one_undo_step
    completed(save("House", SEGMENT_NAMESPACE => settings("bedrooms" => 3)))
    operations = @model.operations.length
    completed(save("House", SEGMENT_NAMESPACE => settings("single_dwelling" => false, "bedrooms" => 3)))

    assert_equal operations + 1, @model.operations.length
    dwelling = records.find { |row| row.fetch("name") == "House" }
    assert_equal 3, dwelling.fetch("own_bedrooms")
    assert_equal %w[Bath Bedroom Living], names(dwelling.fetch("zone_ids"))
    living = zone_row("Living")
    assert_equal dwelling.fetch("id"), living.fetch("dwelling_id")
    assert_nil living.dig("assignment", "program_id"), "the Zones keep the default Program"
    assert_equal P::DefaultProgram::PROGRAM_ID, living.fetch("program_id")

    @model.undo
    assert zone_row("Living").fetch("single_dwelling")
    assert_empty records
  end

  def test_a_rename_and_the_switch_land_together_in_one_save
    all = query("#{O::PREFIX}.all")
    row = all.fetch("building_segments").find { |candidate| candidate.dig("values", "name") == "House" }
    values = row.fetch("values").slice("name", "colour")
    operations = @model.operations.length
    completed(invoke(O::SegmentSettings::SAVE,
                     "id" => row.fetch("id"), "values" => values.merge("name" => "Cottage"),
                     "expected_values" => values, "default" => all.fetch("default_segment_id") == row.fetch("id"),
                     "expected_default_segment_id" => all.fetch("default_segment_id"),
                     "extension_payloads" => { SEGMENT_NAMESPACE => settings("single_dwelling" => false) },
                     "expected_extension_data" => row.fetch("extension_data", {})))
    assert_equal operations + 1, @model.operations.length
    assert_equal ["Cottage"], records.map { |dwelling| dwelling.fetch("name") }
    assert_equal "Cottage", zone_row("Living").fetch("dwelling_name")
    @model.undo
    assert_includes segments.keys, "House"
    assert P::Occupancy.unassigned?(zone_row("Living").fetch("assignment"))
  end

  def test_the_preview_names_what_switching_on_replaces
    switch_off("Apartments", :release => ["Corridor"])
    program = create_program("Corridor", {})
    set = completed(invoke("#{P::FEATURE_ID}.equipment_sets.create", "values" => { "name" => "Laundry" })).fetch("id")
    completed(invoke("#{P::FEATURE_ID}.assign_program", "zones" => [reference("Corridor")], "program_id" => program))
    completed(invoke("#{P::FEATURE_ID}.assign_equipment_set", "equipment_set_id" => set,
                                                              "zones" => [reference("Corridor")]))
    preview = query("#{P::FEATURE_ID}.single_dwelling_preview", "id" => segments.fetch("Apartments").fetch("id"))
    assert_equal [{ "zone_id" => zone_row("Corridor").fetch("zone_id"), "program_id" => program }],
                 preview.fetch("programs")
    assert_equal 1, preview.fetch("dwelling_ids").length
    assert_equal [set], preview.fetch("equipment_set_ids")
    assert_nil preview.fetch("bedrooms")
    refused(API.query(:context => @context, :name => "#{P::FEATURE_ID}.single_dwelling_preview",
                      :params => { "id" => "bsg_Ab12Cd34Ef56" }), "target.not_found")
  end

  def test_switching_off_where_the_segment_names_a_default_keeps_the_models
    program = create_program("Office", {})
    completed(save("House", SEGMENT_NAMESPACE => settings("default_program_id" => program)))
    completed(save("House", SEGMENT_NAMESPACE => settings("single_dwelling" => false, "default_program_id" => program)))
    assert_equal P::DefaultProgram::PROGRAM_ID, zone_row("Living").dig("assignment", "program_id"),
                 "the Zones keep the residential default they used, not the Segment's"
  end

  def test_switching_on_clears_the_zones_and_deletes_their_dwellings_in_one_undo_step
    switch_off("Apartments")
    assert_equal %w[Apt\ 1 Apt\ 1\ bed Corridor], names(records.first.fetch("zone_ids")),
                 "switching off put every Zone in the Segment's Dwelling"
    completed(invoke("#{P::FEATURE_ID}.assign_dwelling", "zones" => [reference("Apt 1"), reference("Apt 1 bed")],
                                                         "choice" => "shared"))
    completed(invoke("#{P::FEATURE_ID}.set_counts", "zone" => reference("Apt 1 bed"), "bedrooms" => 1,
                                                    "occupants" => nil))
    completed(invoke("#{P::FEATURE_ID}.set_counts", "zone" => reference("Apt 1"), "bedrooms" => 1,
                                                    "occupants" => nil))
    preview = segments.fetch("Apartments").fetch("single_dwelling_preview")
    assert_equal 2, preview.fetch("bedrooms"), "the Zones' bedrooms, summed for the section to enter"
    assert_equal 2, preview.fetch("dwelling_ids").length, "Apartments, still the Corridor's, and Apt 1"
    operations = @model.operations.length

    completed(save("Apartments", SEGMENT_NAMESPACE => settings("bedrooms" => preview.fetch("bedrooms"))))

    assert_equal operations + 1, @model.operations.length
    apartments = segments.fetch("Apartments")
    assert apartments.fetch("single_dwelling")
    assert_equal 2, apartments.dig("dwelling", "bedrooms")
    assert_equal 3, apartments.dig("dwelling", "occupants"), "the Phius rule, bedrooms + units"
    assert(%w[Apt\ 1 Apt\ 1\ bed Corridor].all? { |name| P::Occupancy.unassigned?(zone_row(name).fetch("assignment")) })
    assert_empty records, "the emptied Dwellings went"

    @model.undo
    assert_equal 2, records.length
    assert_equal 1, zone_row("Apt 1").dig("assignment", "bedrooms")
  end

  def test_house_counts_survive_off_and_on_and_an_explicit_null_is_kept
    completed(save("House", SEGMENT_NAMESPACE => settings("bedrooms" => 3, "occupants" => 5)))
    completed(save("House", SEGMENT_NAMESPACE => settings("single_dwelling" => false, "bedrooms" => 3,
                                                          "occupants" => 5)))
    preview = segments.fetch("House").fetch("single_dwelling_preview")
    assert_equal [3, 5], preview.values_at("bedrooms", "occupants"), "the Dwelling's own counts"
    completed(save("House", SEGMENT_NAMESPACE => settings("bedrooms" => 3, "occupants" => 5)))
    assert_equal [3, 5], segments.fetch("House").fetch("dwelling").values_at("bedrooms", "occupants")
    completed(save("House", SEGMENT_NAMESPACE => settings("single_dwelling" => false, "bedrooms" => 3)))
    assert_equal [3, 4, true], records.first.values_at("bedrooms", "occupants", "occupants_rule"),
                 "occupants cleared in the same Save stay cleared"
  end

  def test_overridden_assignments_neither_count_in_the_house_nor_outlive_switching_off
    completed(save("House", CERTIFICATION => certification("non_residential")))
    completed(invoke("#{P::FEATURE_ID}.assign_dwelling", "zones" => [reference("Living"), reference("Bedroom")],
                                                         "choice" => "shared"))
    completed(invoke("#{P::FEATURE_ID}.set_counts", "zone" => reference("Bedroom"), "bedrooms" => 2,
                                                    "occupants" => 9))
    completed(save("House", CERTIFICATION => certification("residential")))
    house = segments.fetch("House")
    assert house.fetch("single_dwelling")
    assert_equal [nil, nil], house.fetch("dwelling").values_at("bedrooms", "occupants"),
                 "the overridden Zone counts are not the house's"
    completed(save("House", SEGMENT_NAMESPACE => settings("single_dwelling" => false, "bedrooms" => 1)))
    assert_equal ["House"], records.map { |row| row.fetch("name") }, "the kept Dwelling gave way"
  end

  def test_a_category_change_alone_writes_no_assignment
    completed(save("House", CERTIFICATION => certification("non_residential")))
    assert_equal false, segments.fetch("House").fetch("single_dwelling")
    assert_empty records, "the setting no longer applies; nothing is written to the Zones"
    assert P::Occupancy.unassigned?(zone_row("Living").fetch("assignment"))
  end

  # ---------------------------------------------------------------- assign actions

  def test_each_assign_action_is_one_undo_step_and_round_trips
    switch_off("Apartments", :release => ["Corridor"])
    program = completed(invoke("#{P::FEATURE_ID}.programs.create", "values" => { "name" => "Corridor" })).fetch("id")
    set = completed(invoke("#{P::FEATURE_ID}.equipment_sets.create", "values" => { "name" => "Laundry" })).fetch("id")
    steps = [
      ["assign_program", { "zones" => [reference("Corridor")], "program_id" => program }],
      ["assign_dwelling", { "zones" => [reference("Apt 1"), reference("Apt 1 bed")], "choice" => "shared" }],
      ["set_counts", { "zone" => reference("Apt 1 bed"), "bedrooms" => 1, "occupants" => 2 }],
      ["assign_equipment_set", { "equipment_set_id" => set, "zones" => [reference("Corridor")] }]
    ]
    steps.each do |name, params|
      operations = @model.operations.length
      completed(invoke("#{P::FEATURE_ID}.#{name}", params))
      assert_equal operations + 1, @model.operations.length, name
    end
    corridor = zone_row("Corridor")
    assert_equal({ "program_id" => program, "dwelling_id" => nil, "equipment_set_id" => set, "bedrooms" => nil,
                   "occupants" => nil }, corridor.fetch("assignment"))
    assert_equal program, corridor.fetch("program_id")
    dwelling = records.find { |row| row.fetch("zone_ids").length == 2 }
    assert_equal "Apt 1", dwelling.fetch("name")
    assert_equal [1, 2], dwelling.values_at("bedrooms", "occupants")

    completed(invoke("#{P::FEATURE_ID}.assign_equipment_set", "equipment_set_id" => set,
                                                              "dwelling_ids" => [dwelling.fetch("id")]))
    assert_equal set, zone_row("Apt 1").fetch("equipment_set_id")
    refused(invoke("#{P::FEATURE_ID}.assign_equipment_set", "equipment_set_id" => set,
                                                            "zones" => [reference("Apt 1")]), "validation.failed")
    5.times { @model.undo }
    assert P::Occupancy.unassigned?(zone_row("Corridor").fetch("assignment"))
  end

  def test_each_and_none_create_and_delete_dwellings
    switch_off("Apartments", :release => ["Apt 1", "Apt 1 bed", "Corridor"])
    assert_empty records, "a Dwelling released from its last Zone goes"
    result = completed(invoke("#{P::FEATURE_ID}.assign_dwelling",
                              "zones" => [reference("Apt 1"), reference("Apt 1 bed")], "choice" => "each"))
    assert_equal ["Apt 1", "Apt 1 bed"], records.map { |row| row.fetch("name") }.sort
    shared = result.fetch("dwelling_ids").first
    moved = completed(invoke("#{P::FEATURE_ID}.assign_dwelling", "zones" => [reference("Apt 1 bed")],
                                                                 "choice" => "existing", "dwelling_id" => shared))
    assert_equal 1, moved.fetch("deleted_dwelling_ids").length, "the Dwelling left with no Zones goes"
    assert_equal ["Apt 1"], records.map { |row| row.fetch("name") }
    gone = completed(invoke("#{P::FEATURE_ID}.assign_dwelling",
                            "zones" => [reference("Apt 1"), reference("Apt 1 bed")], "choice" => "none"))
    assert_equal [shared], gone.fetch("deleted_dwelling_ids")
    assert_empty records
  end

  def test_a_dwelling_across_segments_refuses_and_a_single_dwelling_zone_refuses
    switch_off("Apartments")
    switch_off("House")
    house = records.find { |row| row.fetch("name") == "House" }.fetch("id")
    revision = @session.revision
    refused(invoke("#{P::FEATURE_ID}.assign_dwelling", "zones" => [reference("Apt 1")], "choice" => "existing",
                                                       "dwelling_id" => house), "programs.dwelling_across_segments")
    refused(invoke("#{P::FEATURE_ID}.assign_dwelling", "zones" => [reference("Living"), reference("Apt 1")],
                                                       "choice" => "shared"), "programs.dwelling_across_segments")
    assert_equal revision, @session.revision, "a refusal writes nothing"

    completed(save("House", SEGMENT_NAMESPACE => settings))
    refused(invoke("#{P::FEATURE_ID}.assign_program", "zones" => [reference("Living")], "program_id" => nil),
            "programs.single_dwelling")
  end

  def test_a_zone_moved_between_segments_is_a_finding_the_action_repairs
    switch_off("House")
    switch_off("Apartments", :release => ["Apt 1"])
    living = zone_row("Living")
    values = query("ph_composer.zones.all").fetch("zones").find { |row| row.fetch("id") == living.fetch("zone_id") }
                                           .fetch("values")
    completed(invoke("ph_composer.zones.update_field",
                     "targets" => [{ "reference" => living.fetch("reference"), "expected_values" => values }],
                     "field" => "building_segment", "value" => "Apartments"))
    assert_includes codes(zone_row("Bedroom")), "programs.dwelling_across_segments"
    completed(invoke("#{P::FEATURE_ID}.assign_dwelling", "zones" => [reference("Apt 1")], "choice" => "shared"))
    completed(invoke("#{P::FEATURE_ID}.assign_dwelling", "zones" => [reference("Living")], "choice" => "none"))
    refute_includes codes(zone_row("Bedroom")), "programs.dwelling_across_segments"
    refused(invoke("#{P::FEATURE_ID}.set_counts", "zone" => reference("Living"), "bedrooms" => 1,
                                                  "occupants" => nil), "validation.failed")
  end

  def test_a_zone_left_assigned_in_a_single_dwelling_is_a_finding
    switch_off("House")
    completed(save("House", SEGMENT_NAMESPACE => settings("single_dwelling" => true)))
    assert_empty codes(zone_row("Living")), "switching on clears the Zones"
    living = zone_row("Living")
    record = query("ph_composer.zones.all").fetch("zones").find { |row| row.fetch("id") == living.fetch("zone_id") }
    completed(invoke("ph_composer.zones.update_metadata", "updates" => [{
      "reference" => living.fetch("reference"),
      "expected_metadata" => { "user_data" => {}, "extension_data" => record.fetch("extension_data") },
      "extension_payloads" => { ZONE_NAMESPACE => P::Occupancy::UNASSIGNED.merge("bedrooms" => 2) }
    }]))
    assert_includes codes(zone_row("Living")), "programs.single_dwelling_overrides"
  end

  def test_a_zone_update_step_restores_the_record_it_replaced
    living = zone_group_named("Living")
    before = ZONES::ZONE_STORE.read(living)
    reference = zone_row("Living").fetch("reference")
    after = before.merge("extension_data" => { "x" => 1 })
    step = ZONES::UpdateZoneStep.new(:reference => reference, :before => before, :after => after)
    step.restore
    assert_equal before, ZONES::ZONE_STORE.read(living), "nothing before apply"
    step.apply(@model, nil)
    assert_equal after, ZONES::ZONE_STORE.read(living)
    step.restore
    assert_equal before, ZONES::ZONE_STORE.read(living)
  end

  def test_the_participant_refuses_a_locked_zone_and_writes_nothing
    switch_off("Apartments", :release => ["Apt 1"])
    zone_group_named("Apt 1").locked = true
    revision = @session.revision
    refused(invoke("#{P::FEATURE_ID}.assign_dwelling", "zones" => [reference("Apt 1")], "choice" => "shared"),
            "target.locked")
    assert_equal revision, @session.revision
    assert_empty records.select { |row| row.fetch("name") == "Apt 1" }
  end

  def test_naming_the_unwritten_default_stores_it_and_a_used_record_refuses_delete
    switch_off("Apartments", :release => ["Apt 1 bed"])
    completed(invoke("#{P::FEATURE_ID}.assign_program", "zones" => [reference("Corridor")],
                                                        "program_id" => P::DefaultProgram::PROGRAM_ID))
    stored = query("ph_composer.records.list", "kind" => P::PROGRAM_KIND).fetch("records").map { |row| row.fetch("id") }
    assert_includes stored, P::DefaultProgram::PROGRAM_ID
    program = completed(invoke("#{P::FEATURE_ID}.programs.create", "values" => { "name" => "Office" })).fetch("id")
    completed(invoke("#{P::FEATURE_ID}.assign_program", "zones" => [reference("Apt 1")], "program_id" => program))
    uses = query("#{P::FEATURE_ID}.programs.all").fetch("records").find { |row| row.fetch("id") == program }
    assert_equal 1, uses.fetch("use_count"), "the Zone assignment counts as a use"
    refused(invoke("#{P::FEATURE_ID}.programs.delete", "id" => program), "reference.in_use")
    dwelling = completed(invoke("#{P::FEATURE_ID}.assign_dwelling", "zones" => [reference("Apt 1 bed")],
                                                                    "choice" => "shared")).fetch("dwelling_ids").first
    refused(invoke("#{P::FEATURE_ID}.dwellings.delete", "id" => dwelling), "reference.in_use")
  end

  def test_a_dwelling_returns_to_its_zones_counts_and_the_default_set
    switch_off("House")
    house = records.first
    set = completed(invoke("#{P::FEATURE_ID}.equipment_sets.create", "values" => { "name" => "Laundry" })).fetch("id")
    completed(invoke("#{P::FEATURE_ID}.assign_equipment_set", "equipment_set_id" => set,
                                                              "dwelling_ids" => [house.fetch("id")]))
    completed(invoke("#{P::FEATURE_ID}.assign_equipment_set", "equipment_set_id" => nil,
                                                              "dwelling_ids" => [house.fetch("id")]))
    assert_nil zone_row("Living").fetch("equipment_set_id"), "back to the Model's default"
    completed(invoke("#{P::FEATURE_ID}.dwellings.update", "id" => house.fetch("id"), "values" => { "bedrooms" => 4 },
                                                          "expected_values" => {}))
    completed(invoke("#{P::FEATURE_ID}.set_counts", "zone" => reference("Bedroom"), "bedrooms" => 2,
                                                    "occupants" => nil))
    assert_equal 4, records.first.fetch("bedrooms")
    completed(invoke("#{P::FEATURE_ID}.dwellings.update", "id" => house.fetch("id"), "values" => { "bedrooms" => nil },
                                                          "expected_values" => { "bedrooms" => 4 }))
    assert_equal 2, records.first.fetch("bedrooms"), "the Zones' count again"
  end

  def test_an_emptied_dwelling_reports_the_map_it_held
    switch_off("Apartments", :release => ["Apt 1"])
    dwelling = completed(invoke("#{P::FEATURE_ID}.assign_dwelling", "zones" => [reference("Apt 1")],
                                                                    "choice" => "shared")).fetch("dwelling_ids").first
    completed(invoke("ph_composer.records.update_metadata", "updates" => [{
      "reference" => { "kind" => P::DWELLING_KIND, "id" => dwelling },
      "expected_metadata" => { "user_data" => {}, "extension_data" => {} },
      "user_data" => { "tag" => "A" }
    }]))
    result = completed(invoke("#{P::FEATURE_ID}.assign_dwelling", "zones" => [reference("Apt 1")],
                                                                  "choice" => "none"))
    assert_equal [dwelling], result.fetch("deleted_dwelling_ids")
    assert_equal [{ "id" => dwelling, "user_data_keys" => ["tag"], "user_data_key_total" => 1 }],
                 result.fetch("removed_user_data")
  end

  def test_an_equipment_set_delete_moves_its_dwellings_to_the_replacement
    switch_off("Apartments", :release => ["Apt 1"])
    first = completed(invoke("#{P::FEATURE_ID}.equipment_sets.create", "values" => { "name" => "A" })).fetch("id")
    second = completed(invoke("#{P::FEATURE_ID}.equipment_sets.create", "values" => { "name" => "B" })).fetch("id")
    dwelling = completed(invoke("#{P::FEATURE_ID}.assign_dwelling", "zones" => [reference("Apt 1")],
                                                                    "choice" => "shared")).fetch("dwelling_ids").first
    completed(invoke("#{P::FEATURE_ID}.assign_equipment_set", "equipment_set_id" => first,
                                                              "dwelling_ids" => [dwelling]))
    completed(invoke("#{P::FEATURE_ID}.equipment_sets.delete", "id" => first, "replacement_id" => second))
    assert_equal second, zone_row("Apt 1").fetch("equipment_set_id")
  end

  # A Program or Equipment Set deleted with a replacement moves every Zone assignment and Segment setting naming it,
  # with the delete, in one Undo step; Undo brings both back.
  def test_a_delete_with_a_replacement_moves_zone_and_segment_payloads_in_one_undo_step
    switch_off("Apartments", :release => %w[Apt\ 1 Corridor])
    office = create_program("Office", {})
    lab = create_program("Lab", {})
    first = completed(invoke("#{P::FEATURE_ID}.equipment_sets.create", "values" => { "name" => "A" })).fetch("id")
    second = completed(invoke("#{P::FEATURE_ID}.equipment_sets.create", "values" => { "name" => "B" })).fetch("id")
    completed(invoke("#{P::FEATURE_ID}.assign_program", "zones" => [reference("Apt 1"), reference("Corridor")],
                                                        "program_id" => office))
    completed(invoke("#{P::FEATURE_ID}.assign_equipment_set", "equipment_set_id" => first,
                                                              "zones" => [reference("Corridor")]))
    completed(save("House", SEGMENT_NAMESPACE => settings("default_program_id" => office, "equipment_set_id" => first)))

    operations = @model.operations.length
    completed(invoke("#{P::FEATURE_ID}.programs.delete", "id" => office, "replacement_id" => lab))
    assert_equal operations + 1, @model.operations.length
    assert_equal [lab, lab], [zone_row("Apt 1"), zone_row("Corridor")].map { |row| row.dig("assignment", "program_id") }
    assert_equal lab, segments.fetch("House").dig("settings", "default_program_id")

    completed(invoke("#{P::FEATURE_ID}.equipment_sets.delete", "id" => first, "replacement_id" => second))
    assert_equal second, zone_row("Corridor").dig("assignment", "equipment_set_id")
    assert_equal second, segments.fetch("House").dig("settings", "equipment_set_id")
    set_row = query("#{P::FEATURE_ID}.equipment_sets.all").fetch("records").find { |row| row.fetch("id") == second }
    assert_equal 2, set_row.fetch("use_count"), "the Corridor and the House"

    @model.undo
    assert_equal first, zone_row("Corridor").dig("assignment", "equipment_set_id")
    assert_equal first, segments.fetch("House").dig("settings", "equipment_set_id")
    @model.undo
    assert_equal office, zone_row("Apt 1").dig("assignment", "program_id")
    assert_equal office, segments.fetch("House").dig("settings", "default_program_id")
    assert(query("#{P::FEATURE_ID}.programs.all").fetch("records").any? { |row| row.fetch("id") == office })
  end

  def test_a_delete_with_a_replacement_refuses_whole_when_a_zone_is_locked
    switch_off("Apartments", :release => ["Apt 1"])
    office = create_program("Office", {})
    lab = create_program("Lab", {})
    completed(invoke("#{P::FEATURE_ID}.assign_program", "zones" => [reference("Apt 1")], "program_id" => office))
    zone_group_named("Apt 1").locked = true
    revision = @session.revision
    refused(invoke("#{P::FEATURE_ID}.programs.delete", "id" => office, "replacement_id" => lab), "target.locked")
    assert_equal revision, @session.revision
    assert_equal office, zone_row("Apt 1").dig("assignment", "program_id")
  end

  # ---------------------------------------------------------------- copy

  def test_a_copied_zone_keeps_its_assignment_and_dwelling
    switch_off("Apartments", :release => ["Apt 1"])
    dwelling = completed(invoke("#{P::FEATURE_ID}.assign_dwelling", "zones" => [reference("Apt 1")],
                                                                    "choice" => "shared")).fetch("dwelling_ids").first
    original = zone_group_named("Apt 1")
    copy = Sketchup::Group.new(9000, original.entities, :name => "Apt 1")
    Array(original.attribute_dictionaries).each do |dictionary|
      dictionary.each { |key, value| copy.set_attribute(dictionary.name, key, value) }
    end
    @model.entities << copy
    treat_duplicates_as_existing(@model)
    completed(invoke("ph_composer.zones.make_independent", "zone_path" => [9000]))

    rows = query("#{P::FEATURE_ID}.zones").fetch("zones").select { |row| row.fetch("name") == "Apt 1" }
    assert_equal 2, rows.map { |row| row.fetch("zone_id") }.uniq.length
    assert_equal [dwelling, dwelling], rows.map { |row| row.dig("assignment", "dwelling_id") }
  end

  # ---------------------------------------------------------------- derivations

  def test_the_house_derives_people_lighting_and_ventilation_by_the_phius_rules
    completed(save("House", SEGMENT_NAMESPACE => settings("bedrooms" => 3)))
    house = segments.fetch("House")
    assert_equal({ "name" => "House", "units" => 1, "bedrooms" => 3, "occupants" => 4, "occupants_rule" => true,
                   "equipment_set_id" => nil }, house.fetch("dwelling"))
    living = zone_row("Living")
    assert_equal [20.0, 20.0], living.values_at("floor_area_m2", "icfa_m2")
    assert_in_delta 4 / PRESENCE_MEAN * 20 / 36, living.fetch("people"), 1e-9, "people share the floor area"
    assert_in_delta HOUSE_LIGHTING_KWH * 1000 / (LIGHTING_MEAN * 8760) * 20 / 34, living.fetch("lighting_w"), 1e-6,
                    "lighting shares the iCFA"
    bath = zone_row("Bath")
    assert_in_delta 4 / PRESENCE_MEAN * 4 / 36, bath.fetch("people"), 1e-9
    assert_in_delta HOUSE_LIGHTING_KWH * 1000 / (LIGHTING_MEAN * 8760) * 2 / 34, bath.fetch("lighting_w"), 1e-6
    assert_in_delta 0.4 * 50, living.fetch("ventilation_m3h"), 1e-9, "0.4 ACH over 50 m³"
    assert_equal "by_program", living.fetch("ventilation_source")
    assert_equal({ "heating_c" => 20.0, "cooling_c" => 25.0, "agree" => true }, house.fetch("set_points"))
  end

  def test_an_apartment_derives_from_its_program_and_detailed_airflows
    switch_off("Apartments")
    program = create_program("Corridor", "people" => { "people_per_area" => 0.05 },
                                         "lighting" => { "watts_per_area" => 5.0 },
                                         "ventilation" => { "flow_per_area" => 0.0003 },
                                         "setpoint" => { "heating_c" => 18.0, "cooling_c" => 26.0 })
    completed(invoke("#{P::FEATURE_ID}.assign_program", "zones" => [reference("Corridor")], "program_id" => program))
    corridor = zone_row("Corridor")
    assert_in_delta 0.05 * 20, corridor.fetch("people"), 1e-9
    assert_in_delta 5.0 * 20, corridor.fetch("lighting_w"), 1e-9
    assert_in_delta 0.0003 * 20 * 3600, corridor.fetch("ventilation_m3h"), 1e-9
    assert_equal false, segments.fetch("Apartments").dig("set_points", "agree"), "the Zones' Programs disagree"
    assert_includes codes(segments.fetch("Apartments")), "programs.set_points_disagree"
    per_person = create_program("Lobby", "ventilation" => { "flow_per_person" => 0.01 })
    completed(invoke("#{P::FEATURE_ID}.assign_program", "zones" => [reference("Apt 1 bed")],
                                                        "program_id" => per_person))
    assert_nil zone_row("Apt 1 bed").fetch("ventilation_m3h"), "per person over unknown people is unknown"

    zone_space = zone_group_named("Apt 1").entities.to_a.grep(Sketchup::Group).first
    SPACES::SPACE_STORE.write(zone_space, SPACES::SPACE_STORE.read(zone_space).merge("v_sup_m3h" => 60.0,
                                                                                     "v_eta_m3h" => 45.0))
    apartment = zone_row("Apt 1")
    assert_equal ["detailed", 60.0], apartment.values_at("ventilation_source", "ventilation_m3h")
  end

  def test_a_dwelling_of_two_units_counts_them_in_the_rules
    switch_off("House")
    house = records.first
    completed(invoke("#{P::FEATURE_ID}.dwellings.update", "id" => house.fetch("id"), "values" => { "units" => 2 },
                                                          "expected_values" => { "units" => 1 }))
    completed(invoke("#{P::FEATURE_ID}.set_counts", "zone" => reference("Bedroom"), "bedrooms" => 3,
                                                    "occupants" => nil))
    assert_equal [3, 5, true], records.first.values_at("bedrooms", "occupants", "occupants_rule"),
                 "the Zones' bedrooms, and the Phius rule over two units"
    assert_in_delta TWO_UNIT_LIGHTING_KWH * 1000 / (LIGHTING_MEAN * 8760) * 20 / 34,
                    zone_row("Living").fetch("lighting_w"), 1e-6
  end

  # ---------------------------------------------------------------- findings

  def test_findings_follow_programs_actions_and_generic_metadata_writes
    completed(save("Apartments", CERTIFICATION => certification("non_residential")))
    assert_includes codes(zone_row("Corridor")), "programs.unassigned_zone"
    assert_includes codes(segments.fetch("Apartments")), "programs.unassigned_zone", "the heading carries it"
    switch_off("House")
    assert_empty codes(segments.fetch("House")), "the house's Dwelling counts"

    program = create_program("Gym", "electric_equipment" => { "watts_per_area" => 4.0 })
    completed(invoke("#{P::FEATURE_ID}.assign_program", "zones" => [reference("Bath")], "program_id" => program))
    assert_includes codes(zone_row("Bath")), "programs.equipment_watts_residential"

    # The generic route stores what Programs' actions refuse; the read reports it.
    house = records.find { |row| row.fetch("name") == "House" }.fetch("id")
    apartment = zone_row("Apt 1")
    payload = P::Occupancy::UNASSIGNED.merge("dwelling_id" => house)
    completed(invoke("ph_composer.zones.update_metadata", "updates" => [{
      "reference" => apartment.fetch("reference"),
      "expected_metadata" => { "user_data" => {}, "extension_data" => {} },
      "extension_payloads" => { ZONE_NAMESPACE => payload }
    }]))
    assert_includes codes(zone_row("Living")), "programs.dwelling_across_segments"
    assert_includes codes(segments.fetch("Apartments")), "programs.non_residential_dwellings"
    switch_off_without_dwelling = segments.fetch("House")
    refute_includes codes(switch_off_without_dwelling), "programs.residential_without_dwelling"
  end

  def test_an_assignment_never_blocks_export
    switch_off("Apartments")
    completed(invoke("#{P::FEATURE_ID}.assign_dwelling", "zones" => [reference("Apt 1")], "choice" => "shared"))
    completed(save("House", SEGMENT_NAMESPACE => settings("bedrooms" => 2)))
    codes = completed(API.export_preflight(:context => @context)).fetch("findings").map { |row| row["code"] }
    refute(codes.any? { |code| code.start_with?("extension.") || code == "export.blocked" }, codes.inspect)
  end

  # ---------------------------------------------------------------- fixture and helpers

  def zone(base, letter, name, segment, (x0, y0, width, depth), weighting: 1.0)
    space = space_group(base + 10, space_record(letter, :number => "1", :name => name),
                        [volume_group(base + 20, volume_record(letter),
                                      [floor_face(base + 30, rectangle(x0, y0, width, depth),
                                                  segment_record(letter, :weighting_factor => weighting))])])
    group = Sketchup::Group.new(base, Sketchup::Entities.new([space]), :name => name)
    ZONES::ZONE_STORE.write(group, { "id" => "zon_#{letter * 12}", "schema_version" => 1, "name" => name,
                                     "building_segment" => segment, "level" => "L1", "ground_depth_mm" => 0.0 })
    host_children([space], "zon_#{letter * 12}")
    group
  end

  def zone_group_named(name)
    @model.entities.to_a.find { |entity| entity.is_a?(Sketchup::Group) && entity.name == name }
  end

  def settings(values = {})
    P::Occupancy::SEGMENT_DEFAULTS.merge(values)
  end

  def certification(category)
    PhComposer::Certification::Segment::DEFAULTS.merge("category" => category)
  end

  # Switches Single dwelling off, which puts every Zone in the Segment's new Dwelling, then takes `release` out
  # of every Dwelling.
  def switch_off(segment, release: [])
    completed(save(segment, SEGMENT_NAMESPACE => settings("single_dwelling" => false)))
    return if release.empty?

    completed(invoke("#{P::FEATURE_ID}.assign_dwelling", "zones" => release.map { |name| reference(name) },
                                                         "choice" => "none"))
  end

  # A Program with every load PH-Composer's empty one has, under `loads`.
  def create_program(name, loads)
    values = P::Program::EMPTY.to_h { |key, load| [key, load.merge(loads.fetch(key, {}))] }
    completed(invoke("#{P::FEATURE_ID}.programs.create", "values" => values.merge("name" => name))).fetch("id")
  end

  # The Dwelling records: every Dwelling but the single-dwelling houses.
  def records
    dwellings.reject { |row| row.fetch("single_dwelling") }
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

  def segments
    query("#{P::FEATURE_ID}.zones").fetch("building_segments").to_h { |row| [row.fetch("name"), row] }
  end

  def zone_row(name)
    query("#{P::FEATURE_ID}.zones").fetch("zones").find { |row| row.fetch("name") == name }
  end

  def reference(name)
    zone_row(name).fetch("reference")
  end

  def dwellings
    query("#{P::FEATURE_ID}.dwellings").fetch("dwellings")
  end

  def names(zone_ids)
    rows = query("#{P::FEATURE_ID}.zones").fetch("zones")
    zone_ids.map { |id| rows.find { |row| row.fetch("zone_id") == id }.fetch("name") }.sort
  end

  def codes(row)
    row.fetch("findings").map { |finding| finding.fetch("code") }
  end

  def query(name, params = {})
    completed(API.query(:context => @context, :name => name, :params => params))
  end

  def completed(outcome)
    assert_equal "completed", outcome.fetch("status"), outcome.inspect
    outcome.fetch("value")
  end

  def refused(outcome, code)
    refute_equal "completed", outcome.fetch("status"), outcome.inspect
    assert_equal code, outcome.dig("error", "code") || outcome["code"], outcome.inspect
  end

  def invoke(name, params)
    API.invoke(:context => @context, :name => name, :params => params,
               :request => { "sequence" => @sequence += 1, "expected_revision" => @session.revision })
  end
end
