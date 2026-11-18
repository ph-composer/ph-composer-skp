# frozen_string_literal: true

require_relative "test_helper"

class ClimateSettingsTest < PhComposerTestCase
  SETTINGS = PhComposer::Climate::Settings
  SITE = { "latitude_deg" => 40.68, "longitude_deg" => -73.94, "elevation_m" => 10.0, "climate_zone" => 14,
           "hours_from_utc" => -5 }.freeze

  def setup
    super
    PhComposer.compose unless PhComposer::Registry.installed?("ph_composer.climate")
    @model = Sketchup.active_model
    @session = PhComposer::Sessions.for(@model)
    @context = PhComposer::API.connect(:session_id => @session.id)
    @sequence = 0
  end

  def test_the_feature_installs_requiring_zones_with_its_operations_and_code
    row = PhComposer::API.discover.fetch("features").find { |feature| feature["id"] == "ph_composer.climate" }

    assert_equal ["ph_composer.zones"], row.fetch("requires")
    registry = PhComposer::Registry.current
    %w[site.get design_temperatures.get summary.get].each do |name|
      assert registry.queries.key?("ph_composer.climate.#{name}"), name
    end
    %w[site.update design_temperatures.update].each do |name|
      assert registry.actions.key?("ph_composer.climate.#{name}"), name
    end
    assert_equal "ph_composer.climate", registry.codes.fetch("climate.heating_not_below_cooling").owner
  end

  def test_a_new_model_reads_not_set_without_writing
    revision = @session.revision

    site = query("site.get").fetch("value")
    design = query("design_temperatures.get").fetch("value")

    assert_equal SETTINGS::SITE_DEFAULTS.merge("climate_zone_label" => nil, "state" => "not_set"), site
    assert_equal SETTINGS::DESIGN_DEFAULTS.merge("state" => "not_set", "warning" => nil), design
    assert_equal({ "site" => "not_set", "design_temperatures" => { "state" => "not_set", "warning" => nil },
                   "climate" => { "state" => "none", "origin" => nil, "verdict" => nil, "edited" => false } },
                 query("summary.get").fetch("value"))
    assert_nil SETTINGS::SITE.store.read(@model)
    assert_nil SETTINGS::DESIGN_TEMPERATURES.store.read(@model)
    refute @model.modified?
    assert_equal revision, @session.revision
  end

  def test_set_location_writes_all_five_fields_in_one_undo_step
    operations = @model.operations.length

    result = update_site(SITE)

    assert_equal "committed", result.fetch("effect")
    assert_equal SITE.merge("climate_zone_label" => "4", "state" => "set", "limit_check" => nil), result.fetch("value")
    assert_equal [["Set Site Location", :committed]], @model.operations.drop(operations).map { |row|
      row.values_at(0, 2)
    }
    assert_equal "set", query("summary.get").dig("value", "site")
    @model.undo
    assert_equal "not_set", query("site.get").dig("value", "state")
    @model.redo
    assert_equal SITE, query("site.get").fetch("value").slice(*SITE.keys)
  end

  def test_a_partial_location_refuses_and_writes_nothing
    operations = @model.operations.length
    [
      SITE.merge("elevation_m" => nil),
      SITE.merge("longitude_deg" => nil, "elevation_m" => nil),
      SETTINGS::SITE_DEFAULTS.merge("elevation_m" => 12.0)
    ].each do |values|
      result = update_site(values)

      assert_equal "validation.failed", result.fetch("code"), values.inspect
      assert_nil SETTINGS::SITE.store.read(@model)
    end
    assert_equal operations, @model.operations.length
    refute @model.modified?
  end

  # The declared schema refuses these before the handler runs.
  def test_out_of_range_values_and_unknown_zones_refuse
    [
      SITE.merge("latitude_deg" => 90.5), SITE.merge("longitude_deg" => -181), SITE.merge("hours_from_utc" => 15),
      SITE.merge("hours_from_utc" => -13), SITE.merge("hours_from_utc" => 1.5), SITE.merge("climate_zone" => 19),
      SITE.merge("climate_zone" => 4), SITE.merge("climate_zone" => 0), SITE.merge("climate_zone" => 142),
      SITE.merge("climate_zone" => "14")
    ].each do |values|
      assert_equal "params.invalid", update_site(values).fetch("code"), values.inspect
      assert_nil SETTINGS::SITE.store.read(@model)
    end
  end

  def test_every_listed_zone_is_accepted_and_labelled
    expected = ["Not defined", "1", "2", "3", "4", "4C", "5", "6", "7", "8"]

    labels = [1, 11, 12, 13, 14, 141, 15, 16, 17, 18].map do |code|
      update_site(SITE.merge("climate_zone" => code)).dig("value", "climate_zone_label")
    end

    assert_equal expected, labels
  end

  def test_a_site_saves_set_with_no_zone_and_no_offset_and_the_offset_is_kept_as_typed
    result = update_site(SITE.merge("climate_zone" => nil, "hours_from_utc" => nil))

    assert_equal "set", result.dig("value", "state")
    assert_nil result.dig("value", "climate_zone_label")
    assert_equal 9, update_site(SITE.merge("hours_from_utc" => 9)).dig("value", "hours_from_utc")
    assert_equal 9, update_site(SITE.merge("hours_from_utc" => 9, "longitude_deg" => 120.0))
      .dig("value", "hours_from_utc")
    assert_equal "not_set", update_site(SETTINGS::SITE_DEFAULTS).dig("value", "state")
  end

  def test_each_design_temperature_saves_alone_and_reads_its_state
    operations = @model.operations.length

    one = update_design({ "heating_99_c" => -12.2 })
    both = update_design({ "cooling_1_c" => 31.5 })

    assert_equal %w[incomplete set], [one, both].map { |result| result.dig("value", "state") }
    assert_equal [["Change Design Temperature", :committed]] * 2,
                 @model.operations.drop(operations).map { |row| row.values_at(0, 2) }
    assert_equal [-12.2, 31.5], query("design_temperatures.get").fetch("value").values_at("heating_99_c", "cooling_1_c")
    assert_equal "incomplete", update_design({ "heating_99_c" => nil }).dig("value", "state")
    @model.undo
    assert_equal "set", query("design_temperatures.get").dig("value", "state")
  end

  def test_heating_at_or_above_cooling_saves_with_the_warning
    update_design({ "cooling_1_c" => 20.0 })

    result = update_design({ "heating_99_c" => 20.0 })

    assert_equal "committed", result.fetch("effect")
    assert_equal "climate.heating_not_below_cooling", result.dig("value", "warning")
    assert_equal "climate.heating_not_below_cooling",
                 query("summary.get").dig("value", "design_temperatures", "warning")
    assert_nil update_design({ "heating_99_c" => 19.0 }).dig("value", "warning")
  end

  def test_the_source_note_round_trips_and_clears
    note = "ASHRAE 2021, station 725030"

    update_design({ "design_temperature_source" => note })

    assert_equal note, query("design_temperatures.get").dig("value", "design_temperature_source")
    assert_equal "not_set", query("design_temperatures.get").dig("value", "state")
    assert_nil update_design({ "design_temperature_source" => nil }).dig("value", "design_temperature_source")
  end

  def test_design_update_needs_matching_fields_in_expected_values
    assert_equal "validation.failed", update_design({}, {}).fetch("code")
    assert_equal "validation.failed", update_design({ "heating_99_c" => 1.0 }, {}).fetch("code")
    assert_nil SETTINGS::DESIGN_TEMPERATURES.store.read(@model)
  end

  def test_a_stale_expected_value_refuses_both_actions
    update_site(SITE)
    update_design({ "heating_99_c" => -10.0 })

    site = update_site(SITE.merge("elevation_m" => 20.0), SETTINGS::SITE_DEFAULTS)
    design = update_design({ "heating_99_c" => -11.0 }, { "heating_99_c" => nil })

    stale_note = update_design({ "design_temperature_source" => "x" }, { "design_temperature_source" => "y" })
    stale_cooling = update_design({ "cooling_1_c" => 30.0 }, { "cooling_1_c" => 29.0 })

    assert_equal ["target.changed"] * 4, [site, design, stale_note, stale_cooling].map { |result| result.fetch("code") }
    assert_equal 10.0, query("site.get").dig("value", "elevation_m")
    assert_equal(-10.0, query("design_temperatures.get").dig("value", "heating_99_c"))
  end

  def test_a_design_change_does_not_stale_a_site_read_or_the_reverse
    expected_site = SETTINGS.site(@model).slice(*SITE.keys)
    update_design({ "heating_99_c" => -10.0 })

    assert_equal "committed", update_site(SITE, expected_site).fetch("effect")
    assert_equal "committed", update_design({ "cooling_1_c" => 30.0 }, { "cooling_1_c" => nil }).fetch("effect")
  end

  def test_settings_survive_save_and_reopen
    update_site(SITE)
    update_design({ "heating_99_c" => -12.2, "cooling_1_c" => 31.5, "design_temperature_source" => "Note" })
    @model.save("/tmp/ph-composer-climate-settings.skp")
    Sketchup.open_file("/tmp/ph-composer-climate-settings.skp")
    model = Sketchup.active_model

    assert_equal SITE, SETTINGS.site(model).slice(*SITE.keys)
    assert_equal "set", SETTINGS.design_temperatures(model).fetch("state")
  end

  private

  def query(name)
    PhComposer::API.query(:context => @context, :name => "ph_composer.climate.#{name}")
  end

  def update_site(values, expected = SETTINGS.site(@model).slice(*SITE.keys))
    invoke("site.update", "values" => values, "expected_values" => expected)
  end

  def update_design(values, expected = SETTINGS.design_temperatures(@model).slice(*values.keys))
    invoke("design_temperatures.update", "values" => values, "expected_values" => expected)
  end

  def invoke(name, params)
    @sequence += 1
    PhComposer::API.invoke(:context => @context, :name => "ph_composer.climate.#{name}", :params => params,
                           :request => { "sequence" => @sequence, "expected_revision" => @session.revision })
  end
end
