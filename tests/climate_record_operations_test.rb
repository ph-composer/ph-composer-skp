# frozen_string_literal: true

require_relative "test_helper"
require_relative "support/climate_fixtures"

# The climate record's operations through the public API: each write is one native Undo step guarded by the
# editable fields last read, and the limit check follows the site with nothing stored.
class ClimateRecordOperationsTest < PhComposerTestCase
  SCHEMA = PhComposer::Climate::Schema
  KIND = SCHEMA::KIND
  SITE = { "latitude_deg" => 41.0, "longitude_deg" => -74.0, "elevation_m" => 30.0, "climate_zone" => 14,
           "hours_from_utc" => -5 }.freeze

  def setup
    super
    PhComposer.compose unless PhComposer::Registry.installed?("ph_composer.climate")
    @model = Sketchup.active_model
    @session = PhComposer::Sessions.for(@model)
    @context = PhComposer::API.connect(:session_id => @session.id)
    @sequence = 0
  end

  def test_the_kind_and_the_operations_are_registered_with_their_undo_names_and_codes
    registry = PhComposer::Registry.current

    assert_equal KIND, registry.catalog.kind(SCHEMA::KIND_ID)
    assert registry.queries.key?("ph_composer.climate.climate.get")
    assert registry.queries.key?("ph_composer.climate.site.preview_limit_check")
    assert_equal({ "enter_values" => "Enter Climate Values", "save_values" => "Edit Climate Values",
                   "restore_original" => "Restore Climate Values", "clear" => "Clear Climate" },
                 %w[enter_values save_values restore_original clear].to_h { |verb|
                   [verb, registry.actions.fetch("ph_composer.climate.climate.#{verb}").undo_name]
                 })
    %w[climate.not_found climate.no_original].each do |code|
      assert_equal "ph_composer.climate", registry.codes.fetch(code).owner
    end
  end

  def test_a_new_model_reads_no_climate_without_writing
    revision = @session.revision

    found = get

    assert_equal({ "state" => "none", "climate" => nil, "missing" => [], "edited_cells" => [],
                   "limit_check" => nil }, found)
    refute @model.modified?
    assert_equal revision, @session.revision
  end

  def test_enter_values_saves_with_gaps_as_one_undo_step_and_reads_incomplete
    operations = @model.operations.length

    result = invoke("enter_values", "values" => ClimateFixtures.sparse_values)

    assert_equal "committed", result.fetch("effect")
    assert_equal [["Enter Climate Values", :committed]], new_operations(operations)
    found = get
    assert_equal %w[incomplete hand], [found.fetch("state"), found.dig("climate", "values", "origin")]
    assert_equal "daily_temp_swing_k", found.fetch("missing").first.fetch("row")
    assert_nil found.dig("climate", "values", "daily_temp_swing_k")
    assert_equal({ "state" => "incomplete", "origin" => "hand", "verdict" => "not_checked", "edited" => false },
                 summary.fetch("climate"))
    @model.undo
    assert_equal "none", get.fetch("state")
  end

  def test_enter_values_needs_a_name_and_station_elevation_and_refuses_over_a_climate
    operations = @model.operations.length
    nameless = invoke("enter_values", "values" => ClimateFixtures.sparse_values.merge("name" => ""))
    no_elevation = invoke("enter_values", "values" => ClimateFixtures.sparse_values.merge("station_elevation_m" => nil))
    assert_equal operations, @model.operations.length
    invoke("enter_values", "values" => ClimateFixtures.sparse_values)
    revision = @session.revision

    again = invoke("enter_values", "values" => ClimateFixtures.hand_values)

    assert_equal %w[params.invalid params.invalid target.changed],
                 [nameless, no_elevation, again].map { |result| result.fetch("code") }
    assert_equal ["incomplete", revision], [get.fetch("state"), @session.revision]
  end

  def test_save_values_can_leave_gaps_in_a_complete_climate
    invoke("enter_values", "values" => ClimateFixtures.hand_values)
    operations = @model.operations.length

    result = invoke("save_values", "values" => ClimateFixtures.hand_values.merge("wind_speed_m_s" => nil),
                                   "expected_values" => editable)

    assert_equal ["incomplete", [{ "row" => "wind_speed_m_s", "columns" => [] }]],
                 result.fetch("value").values_at("state", "missing")
    assert_equal [["Edit Climate Values", :committed]], new_operations(operations)
  end

  def test_a_stale_read_refuses_restore_and_clear_and_writes_nothing
    seed_station
    read = editable
    values = editable
    values["monthly"]["air_c"][0] = -9.0
    invoke("save_values", "values" => values, "expected_values" => read)
    stored = KIND.store.read(@model, SCHEMA::RECORD_ID)
    revision = @session.revision

    restore = invoke("restore_original", "expected_values" => read)
    clear = invoke("clear", "expected_values" => read)

    assert_equal %w[target.changed target.changed], [restore, clear].map { |result| result.fetch("code") }
    assert_equal [stored, revision], [KIND.store.read(@model, SCHEMA::RECORD_ID), @session.revision]
  end

  def test_save_values_completes_a_hand_climate_and_a_stale_read_refuses
    invoke("enter_values", "values" => ClimateFixtures.sparse_values)
    read = editable
    operations = @model.operations.length

    saved = invoke("save_values", "values" => ClimateFixtures.hand_values, "expected_values" => read)
    stale = invoke("save_values", "values" => ClimateFixtures.sparse_values, "expected_values" => read)

    assert_equal "committed", saved.fetch("effect")
    assert_equal "target.changed", stale.fetch("code")
    assert_equal [["Edit Climate Values", :committed]], new_operations(operations)
    assert_equal ["complete", [], []], get.values_at("state", "missing", "edited_cells")
  end

  def test_an_edit_to_a_station_turns_its_source_user_defined_and_restore_and_undo_each_turn_it_back
    seed_station
    operations = @model.operations.length
    values = editable
    values["monthly"]["air_c"][0] = -9.0

    invoke("save_values", "values" => values, "expected_values" => editable)
    edited = get
    invoke("restore_original", "expected_values" => editable)
    restored = get
    @model.undo
    undone = get
    @model.undo

    assert_equal [["Edit Climate Values", :committed], ["Restore Climate Values", :committed]],
                 new_operations(operations)
    assert_equal "user_defined", edited.dig("climate", "values", "provenance", "source_type")
    assert_equal [{ "row" => "air_c", "column" => "jan", "value" => -9.0, "as_read" => 0.5 }],
                 edited.dig("climate", "values", "provenance", "assumptions", "ph_composer", "edited_values")
    assert_equal [{ "row" => "air_c", "column" => "jan" }], edited.fetch("edited_cells")
    assert_equal [0.5, "phius_approved", []],
                 [restored.dig("climate", "values", "monthly", "air_c", 0),
                  restored.dig("climate", "values", "provenance", "source_type"), restored.fetch("edited_cells")]
    assert_equal edited, undone
    assert_equal "phius_approved", get.dig("climate", "values", "provenance", "source_type")
    assert_equal false, summary.dig("climate", "edited")
  end

  def test_a_wind_speed_change_is_not_an_edit
    seed_station
    values = editable.merge("wind_speed_m_s" => 7.0)

    invoke("save_values", "values" => values, "expected_values" => editable)

    assert_equal [[], "phius_approved", 7.0],
                 [get.fetch("edited_cells"), get.dig("climate", "values", "provenance", "source_type"),
                  get.dig("climate", "values", "wind_speed_m_s")]
  end

  def test_edit_values_keeps_a_stations_name_and_coordinates
    seed_station
    stored = KIND.store.read(@model, SCHEMA::RECORD_ID)

    renamed = invoke("save_values", "values" => editable.merge("name" => "Other"), "expected_values" => editable)
    moved = invoke("save_values", "values" => editable.merge("station_latitude_deg" => 40.0),
                                  "expected_values" => editable)

    assert_equal %w[validation.failed validation.failed], [renamed, moved].map { |result| result.fetch("code") }
    assert_equal stored, KIND.store.read(@model, SCHEMA::RECORD_ID)
  end

  def test_restore_refuses_for_a_hand_climate_and_every_write_refuses_with_no_climate
    nothing = ClimateFixtures.sparse_values
    missing = [invoke("save_values", "values" => nothing, "expected_values" => nothing),
               invoke("restore_original", "expected_values" => nothing),
               invoke("clear", "expected_values" => nothing)]
    invoke("enter_values", "values" => nothing)
    revision = @session.revision

    restore = invoke("restore_original", "expected_values" => editable)

    assert_equal ["climate.not_found"] * 3, missing.map { |result| result.fetch("code") }
    assert_equal "climate.no_original", restore.fetch("code")
    assert_match(/Nothing was written\.\z/, restore.fetch("message"))
    assert_equal revision, @session.revision
  end

  def test_clear_deletes_the_climate_and_leaves_the_site_and_design_temperatures
    update_site(SITE)
    invoke("design_temperatures.update", { "values" => { "heating_99_c" => -12.0 },
                                           "expected_values" => { "heating_99_c" => nil } }, "")
    seed_station
    operations = @model.operations.length

    result = invoke("clear", "expected_values" => editable)

    assert_equal [["Clear Climate", :committed]], new_operations(operations)
    assert_equal ["none", [], 0], result.fetch("value").values_at("state", "removed_user_data",
                                                                  "removed_user_data_total")
    assert_empty KIND.store.ids(@model)
    assert_equal "set", query("site.get").dig("value", "state")
    assert_equal(-12.0, query("design_temperatures.get").dig("value", "heating_99_c"))
    @model.undo
    assert_equal "complete", get.fetch("state")
  end

  def test_a_site_change_changes_the_verdict_with_no_climate_write
    seed_station
    stored = KIND.store.read(@model, SCHEMA::RECORD_ID)

    near = update_site(SITE)
    far = update_site(SITE.merge("latitude_deg" => 42.0))
    found = get

    assert_equal "pass", near.dig("value", "limit_check", "verdict")
    assert_equal "fail", far.dig("value", "limit_check", "verdict")
    assert_equal [false, true], found.fetch("limit_check").values_at("distance_ok", "elevation_ok")
    assert_equal "fail", summary.dig("climate", "verdict")
    assert_equal stored, KIND.store.read(@model, SCHEMA::RECORD_ID)
  end

  def test_the_preview_gives_the_verdict_at_a_proposed_site_and_writes_nothing
    seed_station
    revision = @session.revision

    pass = query("site.preview_limit_check", SITE.slice("latitude_deg", "longitude_deg", "elevation_m"))
    fail = query("site.preview_limit_check", { "latitude_deg" => 41.0, "longitude_deg" => -74.0,
                                               "elevation_m" => 200.0 })
    unset = query("site.preview_limit_check", { "latitude_deg" => nil, "longitude_deg" => nil,
                                                "elevation_m" => nil })

    assert_equal %w[pass fail not_checked],
                 [pass, fail, unset].map { |result| result.dig("value", "limit_check", "verdict") }
    assert_equal revision, @session.revision
    assert_equal "no_site", get.dig("limit_check", "reason")
  end

  def test_a_hand_climate_without_coordinates_reads_not_checked
    update_site(SITE)
    invoke("enter_values", "values" => ClimateFixtures.hand_values)

    assert_equal %w[not_checked no_station_coordinates], get.fetch("limit_check").values_at("verdict", "reason")
  end

  # The largest reply climate.get can give, a station with every value edited and a large user_data map, still
  # fits one agent reply: 17,826 bytes of value when measured, against 24,576, since the map is not in it.
  def test_the_largest_read_fits_one_reply
    seed_station
    values = editable
    values["monthly"].each_value { |row| row.map! { |value| value + 1000.123456 } }
    values["peak_loads"].each_value { |row| row.transform_values! { |value| value + 1000.123456 } }
    values["daily_temp_swing_k"] = 1.123456
    invoke("save_values", "values" => values, "expected_values" => editable)

    update = { "reference" => { "kind" => SCHEMA::KIND_ID, "id" => SCHEMA::RECORD_ID },
               "expected_metadata" => { "user_data" => {}, "extension_data" => {} },
               "user_data" => { "note" => "x" * 8192 } }
    metadata = invoke("update_metadata", { "updates" => [update] }, "", "ph_composer.records.")

    assert_equal "committed", metadata.fetch("effect"), metadata.inspect
    assert_operator JSON.generate(query("climate.get")).bytesize, :<, PhComposer::Pages::REPLY_BYTES
  end

  def test_a_climate_survives_save_and_reopen
    seed_station
    values = editable
    values["monthly"]["air_c"][0] = -9.0
    invoke("save_values", "values" => values, "expected_values" => editable)
    @model.save("/tmp/ph-composer-climate-record.skp")
    Sketchup.open_file("/tmp/ph-composer-climate-record.skp")
    engine = PhComposer::Records::Engine.new(Sketchup.active_model, PhComposer::Registry.current.catalog)

    record = PhComposer::Climate::Operations.stored(engine)

    assert_equal [-9.0, 0.5], [record.dig("monthly", "air_c", 0), record.dig("as_read", "monthly", "air_c", 0)]
  end

  private

  # A station climate written as the station reader's attach will write one, through the builder.
  def seed_station
    @model.start_operation("Seed station climate", true)
    KIND.store.write(@model, ClimateFixtures.station_record)
    @model.commit_operation
  end

  def editable
    get.dig("climate", "values").slice(*SCHEMA::EDITABLE)
  end

  def get
    query("climate.get").fetch("value")
  end

  def summary
    query("summary.get").fetch("value")
  end

  def new_operations(before)
    @model.operations.drop(before).map { |row| row.values_at(0, 2) }
  end

  def update_site(values)
    expected = query("site.get").fetch("value").slice(*SITE.keys)
    invoke("site.update", { "values" => values, "expected_values" => expected }, "")
  end

  def query(name, params = {})
    PhComposer::API.query(:context => @context, :name => "ph_composer.climate.#{name}", :params => params)
  end

  def invoke(name, params, prefix = "climate.", owner = "ph_composer.climate.")
    @sequence += 1
    PhComposer::API.invoke(:context => @context, :name => "#{owner}#{prefix}#{name}", :params => params,
                           :request => { "sequence" => @sequence, "expected_revision" => @session.revision })
  end
end
