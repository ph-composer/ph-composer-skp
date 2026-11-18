# frozen_string_literal: true

require_relative "test_helper"

# Read from SketchUp Geolocation's query, against the shapes owed check 4 measured on SketchUp 2026
# (context/SKETCHUP_HOST_BEHAVIOR.md, "Geolocation"): a Model never geolocated still carries its template's
# location in ShadowInfo, and only Model#georeferenced? tells the two apart.
class ClimateGeolocationTest < PhComposerTestCase
  # Item 1 of the owed check, as the host reported it for a fresh copy of the default template.
  TEMPLATE_SHADOW = { "Latitude" => 40.018309, "Longitude" => -105.242139, "TZOffset" => -7.0,
                      "City" => "Boulder (CO)", "Country" => "USA", "DaylightSavings" => false }.freeze

  def setup
    super
    PhComposer.compose unless PhComposer::Registry.installed?("ph_composer.climate")
    @model = Sketchup.active_model
    @session = PhComposer::Sessions.for(@model)
    @context = PhComposer::API.connect(:session_id => @session.id)
  end

  def test_a_model_never_geolocated_reads_nothing_although_shadow_info_holds_the_template_location
    geolocate(false, TEMPLATE_SHADOW)
    revision = @session.revision

    value = geolocation

    assert_equal({ "geolocated" => false, "latitude_deg" => nil, "longitude_deg" => nil, "hours_from_utc" => nil },
                 value)
    refute @model.modified?
    assert_equal revision, @session.revision
  end

  def test_a_geolocated_model_reads_latitude_and_longitude_and_never_an_offset_or_elevation
    geolocate(true, TEMPLATE_SHADOW.merge("Latitude" => 42.3233, "Longitude" => -73.3887, "TZOffset" => -5.0))

    value = geolocation

    assert_equal({ "geolocated" => true, "latitude_deg" => 42.3233, "longitude_deg" => -73.3887,
                   "hours_from_utc" => nil }, value)
    refute value.key?("elevation_m")
    refute @model.modified?
  end

  def test_a_location_outside_the_site_ranges_reads_as_none
    geolocate(true, TEMPLATE_SHADOW.merge("Latitude" => 91.0))
    assert_equal false, geolocation.fetch("geolocated")

    geolocate(true, TEMPLATE_SHADOW.merge("Longitude" => -180.5))
    assert_equal false, geolocation.fetch("geolocated")
  end

  # The test stub's Model answers no georeferenced? unless a test gives it one, as an older host might not.
  def test_a_model_without_georeferenced_reads_nothing
    @model.shadow_info = TEMPLATE_SHADOW.dup

    assert_equal PhComposer::Climate::Geolocation::NONE, PhComposer::Climate::Geolocation.read(@model)
  end

  def test_the_query_and_the_two_snapshot_sections_are_registered
    registry = PhComposer::Registry.current

    assert registry.queries.key?("ph_composer.climate.site.geolocation")
    assert registry.snapshot_sections.key?("ph_composer.climate.site")
    assert registry.snapshot_sections.key?("ph_composer.climate.design_temperatures")
  end

  private

  def geolocate(georeferenced, shadow)
    @model.shadow_info = shadow.dup
    @model.define_singleton_method(:georeferenced?) { georeferenced }
  end

  def geolocation
    outcome = PhComposer::API.query(:context => @context, :name => "ph_composer.climate.site.geolocation")
    assert_equal "completed", outcome.fetch("status"), outcome.inspect
    outcome.fetch("value")
  end
end
