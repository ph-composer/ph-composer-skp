# frozen_string_literal: true

require_relative "test_helper"
require_relative "support/space_fixtures"
require_relative "support/zone_options"
require_relative "support/library_provider_fixtures"

# What the Zones / Programs view needs from Ruby: a library Program chosen on a Zone copies with its
# Schedules and assigns in one Undo step (assign_library_program), and a second Zone reuses the local copy; the
# house row writes the Segment's occupancy payload through Zones' settings Save as one Undo step; and the
# occupancy read gives each Segment heading its sums, each unknown value its reason and the Dwellings the bubble
# lists. The fixture is
# OccupancyAssignmentsTest's house and apartments, reduced to what these rows read.
class ZonesProgramsViewTest < PhComposerTestCase
  include SpaceFixtures
  include ZoneOptionsSupport
  include LibraryProviderFixtures

  API = PhComposer::API
  P = PhComposer::Programs
  O = PhComposer::Zones::Options
  L = "ph_composer.library"
  PROVIDER = "synthetic.programs"
  SEGMENT_NAMESPACE = P::Occupancy::SEGMENT_NAMESPACE

  def setup
    super
    @model = Sketchup.active_model
    @session = PhComposer::Sessions.for(@model)
    @context = API.connect(:session_id => @session.id, :capabilities => %w[read view model_write setup])
    @sequence = 0
    @model.entities << zone(1000, "L", "Living", "House", [0, 0, 5, 4]) <<
      zone(2000, "B", "Bedroom", "House", [5, 0, 3, 4]) <<
      zone(4000, "A", "Apt 1", "Apartments", [0, 10, 5, 5]) <<
      zone(6000, "R", "Corridor", "Apartments", [10, 10, 2, 10])
    adopt_zone_options
    @directory = Dir.mktmpdir("zones-programs")
    path = write_library(File.join(@directory, "programs.json"), library)
    PhComposer::Library::Setup.add_file(:id => PROVIDER, :label => "Synthetic programs", :path => path)
    @generations = %w[schedules programs].to_h do |kind|
      loaded = API.setup(:context => @context, :name => "#{L}.load",
                         :params => { "provider_id" => PROVIDER, "kind" => kind })
      [kind, loaded.dig("value", "generation")]
    end
  end

  def teardown
    FileUtils.rm_rf(@directory)
    super
  end

  def test_a_library_program_on_a_zone_copies_once_and_a_second_zone_reuses_it
    completed(save("Apartments", SEGMENT_NAMESPACE => P::Occupancy::SEGMENT_DEFAULTS.merge("single_dwelling" => false)))
    operations = @model.operations.length
    copied = assign_library(copy_params("create"), "Apt 1")
    assert_equal "committed", copied["effect"], copied.inspect
    local_id = copied.dig("value", "program_id")
    assert_equal %w[created], copied.dig("value", "dependencies").map { |row| row.fetch("outcome") }
    assert_equal operations + 1, @model.operations.length, "copy, Schedules and assignment are one Undo step"
    assert_equal [local_id, "Office"], zone_row("Apt 1").values_at("program_id", "program_name")
    assert_equal 1, stored(P::SCHEDULE_KIND).length

    @model.undo
    assert_empty stored(P::PROGRAM_KIND) + stored(P::SCHEDULE_KIND)
    assert_nil zone_row("Apt 1").dig("assignment", "program_id")
    @model.redo
    assert_equal local_id, zone_row("Apt 1").fetch("program_id")

    resolution = query("#{L}.in_file", copy_params("create").slice("provider_id", "kind", "generation"))
                 .fetch("rows").first.fetch("resolution")
    assert_equal ["reuse", [local_id]], [resolution.fetch("outcome"), resolution.fetch("candidates").map { |c|
      c["id"]
    }]
    reused = assign_library(copy_params("keep_local").merge("local_id" => local_id), "Corridor")
    assert_equal "committed", reused["effect"], reused.inspect
    assert_equal [local_id], stored(P::PROGRAM_KIND).map { |row| row.fetch("id") } - [P::DefaultProgram::PROGRAM_ID]
    assert_equal 1, stored(P::SCHEDULE_KIND).length
    assert_equal local_id, zone_row("Corridor").fetch("program_id")
  end

  def test_a_library_program_on_a_single_dwelling_zone_refuses_and_writes_nothing
    revision = @session.revision
    refused(assign_library(copy_params("create"), "Living"), "programs.single_dwelling")
    assert_empty stored(P::PROGRAM_KIND) + stored(P::SCHEDULE_KIND)
    assert_equal revision, @session.revision
    stale = copy_params("create").merge("generation" => @generations.fetch("programs") + 10)
    refused(assign_library(stale, "Apt 1"), "library.catalog_stale")
  end

  def test_the_house_row_writes_the_segment_payload_as_one_undo_step_and_a_stale_revision_refuses
    operations = @model.operations.length
    house = P::Occupancy::SEGMENT_DEFAULTS.merge("bedrooms" => 3)
    completed(save("House", SEGMENT_NAMESPACE => house))
    assert_equal operations + 1, @model.operations.length
    assert_equal [3, 4, true], segment("House").fetch("dwelling").values_at("bedrooms", "occupants", "occupants_rule")
    stale = invoke_at(@session.revision - 1, O::SegmentSettings::SAVE, save_params("House", SEGMENT_NAMESPACE =>
      house.merge("bedrooms" => 4)))
    assert_equal "revision.stale", stale.dig("error", "code") || stale["code"], stale.inspect
    assert_equal 3, segment("House").dig("dwelling", "bedrooms")
    @model.undo
    assert_nil segment("House").dig("dwelling", "bedrooms")
  end

  def test_the_read_gives_heading_sums_unknown_value_reasons_and_the_dwellings
    house = segment("House")
    assert_equal [nil, nil, 32.0, 32.0], house.fetch("sums").values_at("bedrooms", "occupants", "floor_area_m2",
                                                                       "icfa_m2")
    assert_includes house.dig("sums", "incomplete"), "people"
    living = zone_row("Living")
    assert_nil living.fetch("people")
    assert_match(/Enter the bedrooms of House/, living.dig("missing", "people"))
    assert_equal [1, true], living.values_at("dwelling_units", "single_dwelling")

    completed(save("House", SEGMENT_NAMESPACE => P::Occupancy::SEGMENT_DEFAULTS.merge("bedrooms" => 3)))
    sums = segment("House").fetch("sums")
    assert_equal [3, 4], sums.values_at("bedrooms", "occupants")
    assert_empty sums.fetch("incomplete")
    assert_in_delta zone_row("Living").fetch("people") + zone_row("Bedroom").fetch("people"), sums.fetch("people"),
                    1e-9
    assert_empty zone_row("Living").fetch("missing")

    completed(save("Apartments", SEGMENT_NAMESPACE => P::Occupancy::SEGMENT_DEFAULTS.merge("single_dwelling" => false)))
    read = query("#{P::FEATURE_ID}.zones")
    apartments = read.fetch("dwellings").find { |row| row.fetch("name") == "Apartments" }
    assert_equal 2, apartments.fetch("zone_ids").length
    assert_in_delta 45.0, apartments.fetch("floor_area_m2"), 1e-9
    assert_in_delta 45.0, apartments.fetch("icfa_m2"), 1e-9
    assert_equal read.fetch("dwellings"), query("#{P::FEATURE_ID}.dwellings").fetch("dwellings")
  end

  # ---------------------------------------------------------------- fixture and helpers

  def library
    envelope(:kinds => {
      "schedules" => [{ "id" => "office-hours", "name" => "Office hours", "type" => "fractional",
                        "start_h" => 8, "end_h" => 18, "fraction_on" => 1, "fraction_off" => 0.1,
                        "days_per_week" => 5 }],
      "programs" => [{ "id" => "office", "name" => "Office",
                       "people" => { "people_per_area" => 0.05, "occupancy_schedule_id" => "office-hours" },
                       "lighting" => { "watts_per_area" => 7, "schedule_id" => "office-hours" } }]
    }).merge("kind_schema_versions" => { "schedules" => 1, "programs" => 1 })
  end

  def copy_params(choice)
    { "provider_id" => PROVIDER, "kind" => "programs", "generation" => @generations.fetch("programs"),
      "library_id" => "synthetic.one", "record_id" => "office", "choice" => choice }
  end

  def assign_library(copy, *names)
    invoke("#{P::FEATURE_ID}.assign_library_program",
           "zones" => names.map { |name| zone_row(name).fetch("reference") }, "copy" => copy)
  end

  def zone(base, letter, name, segment, (x0, y0, width, depth))
    space = space_group(base + 10, space_record(letter, :number => "1", :name => name),
                        [volume_group(base + 20, volume_record(letter),
                                      [floor_face(base + 30, rectangle(x0, y0, width, depth),
                                                  segment_record(letter))])])
    group = Sketchup::Group.new(base, Sketchup::Entities.new([space]), :name => name)
    ZONES::ZONE_STORE.write(group, { "id" => "zon_#{letter * 12}", "schema_version" => 1, "name" => name,
                                     "building_segment" => segment, "level" => "L1", "ground_depth_mm" => 0.0 })
    host_children([space], "zon_#{letter * 12}")
    group
  end

  def save_params(name, payloads)
    all = query("#{O::PREFIX}.all")
    row = all.fetch("building_segments").find { |candidate| candidate.dig("values", "name") == name }
    default_id = all.fetch("default_segment_id")
    values = row.fetch("values").slice("name", "colour")
    { "id" => row.fetch("id"), "values" => values, "expected_values" => values,
      "default" => default_id == row.fetch("id"), "expected_default_segment_id" => default_id,
      "extension_payloads" => payloads, "expected_extension_data" => row.fetch("extension_data", {}) }
  end

  def save(name, payloads)
    invoke(O::SegmentSettings::SAVE, save_params(name, payloads))
  end

  def stored(kind)
    P::Store::KINDS.fetch(kind).store.ids(@model).map { |id| P::Store::KINDS.fetch(kind).store.read(@model, id) }
  end

  def segment(name)
    query("#{P::FEATURE_ID}.zones").fetch("building_segments").find { |row| row.fetch("name") == name }
  end

  def zone_row(name)
    query("#{P::FEATURE_ID}.zones").fetch("zones").find { |row| row.fetch("name") == name }
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
    invoke_at(@session.revision, name, params)
  end

  def invoke_at(revision, name, params)
    API.invoke(:context => @context, :name => name, :params => params,
               :request => { "sequence" => @sequence += 1, "expected_revision" => revision })
  end
end
