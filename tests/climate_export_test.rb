# frozen_string_literal: true

require "minitest/mock"
require_relative "test_helper"
require_relative "support/climate_fixtures"
require_relative "support/climate_station_files"

# The Site export section (CONTRACTS section 7): the one record by the table's five rows, the provenance passed
# through, the findings and the preflight, and the Export report's climate section. The golden extraction is
# board 18's case, an attached station with one edit and an unset UTC offset, read from a copy of the invented
# fixture folder; tests/python/test_site_sections.py translates it, and its result (tests/fixtures/climate/
# result.json) is what the report test renders.
class ClimateExportTest < PhComposerTestCase
  include FixtureFiles

  PREFIX = "ph_composer.climate"
  X = PhComposer::Climate::SiteExport
  RECORD = PhComposer::Climate::SiteRecord
  RECORD_LIMITS = PhComposer::Climate::LimitCheck
  SCHEMA = PhComposer::Climate::Schema
  FIXTURES = File.expand_path("fixtures/climate", __dir__)
  EXTRACTION = File.join(FIXTURES, "extraction.json")
  RESULT_FIELDS = File.join(FIXTURES, "result_fields.json")
  RESULT = File.join(FIXTURES, "result.json")
  # The fixture stations sit around ClimateStationFiles::SITE; INSIDE passes both limits.
  SITE = ClimateStationFiles::SITE.merge("climate_zone" => 15, "hours_from_utc" => -6).freeze
  INSIDE = "XA/INSIDE_BOTH-mon.txt"
  DATASET = "Synthetic Dataset"
  DESIGN = { "heating_99_c" => -17.2, "cooling_1_c" => 30.1, "design_temperature_source" => "ASHRAE 2021" }.freeze
  NO_DESIGN = { "heating_99_c" => nil, "cooling_1_c" => nil, "design_temperature_source" => nil }.freeze
  NO_SITE = PhComposer::Climate::Settings::SITE_DEFAULTS
  # The site ClimateFixtures' station sits at, for the pure record and findings.
  NEAR = { "latitude_deg" => 41.0, "longitude_deg" => -74.0, "elevation_m" => 30.0, "climate_zone" => 14,
           "hours_from_utc" => -5 }.freeze

  def setup
    super
    PhComposer.compose unless PhComposer::Registry.installed?(PREFIX)
    @model = Sketchup.active_model
    @session = PhComposer::Sessions.for(@model)
    @context = PhComposer::API.connect(:session_id => @session.id, :capabilities => %w[read setup model_write])
    @root = Dir.mktmpdir("climate_export")
    @sequence = 0
  end

  def teardown
    FileUtils.rm_rf(@root)
    super
  end

  def station(**edits)
    values = SCHEMA::KIND.values(ClimateFixtures.station_record)
    edits.empty? ? values : PhComposer::Climate::Record.with_values(values,
                                                                    values.slice(*SCHEMA::EDITABLE).merge(edits))
  end

  def hand(**options)
    PhComposer::Climate::Record.hand(ClimateFixtures.hand_values(**options))
  end

  def codes(site, climate)
    RECORD.findings(site, climate).map(&:first)
  end

  # Contract record, one case per row of the table.
  def test_the_record_follows_the_table_row_by_row
    complete = RECORD.call(NEAR, DESIGN, station)
    assert_equal [NEAR.slice("latitude_deg", "longitude_deg", "elevation_m", "climate_zone", "hours_from_utc"), nil],
                 [complete.fetch("location"), complete.fetch("climate_left_out")]
    peaks = complete.dig("climate", "peak_loads")
    assert_equal %w[cool_1 cool_2 heat_1 heat_2], peaks.keys.sort
    assert_equal peaks.fetch("cool_1"), peaks.fetch("cool_2")
    refute_same peaks.fetch("cool_1"), peaks.fetch("cool_2")
    assert_equal station.fetch("monthly"), complete.dig("climate", "monthly")
    assert_equal "phius_approved", complete.dig("provenance", "source_type")

    site_alone = RECORD.call(NEAR, NO_DESIGN, nil)
    assert_equal [true, nil, nil, nil], [site_alone.fetch("location").is_a?(Hash), site_alone.fetch("climate"),
                                         site_alone.fetch("provenance"), site_alone.fetch("climate_left_out")]

    gappy = station
    gappy["monthly"]["air_c"][0] = nil
    gappy["wind_speed_m_s"] = nil
    incomplete = RECORD.call(NEAR, NO_DESIGN, gappy)
    assert_equal ["incomplete", nil, nil], incomplete.values_at("climate_left_out", "climate", "provenance")
    assert_equal 2, incomplete.dig("report", "missing_values")
    refute_nil incomplete.fetch("location")

    no_site = RECORD.call(NO_SITE, NO_DESIGN, station)
    assert_equal [nil, nil, nil, "site_not_set"],
                 no_site.values_at("location", "climate", "provenance", "climate_left_out")
    assert_equal ["Synthetic Station", "Synthetic Dataset"],
                 no_site.dig("report", "climate").values_at("name", "dataset_name"), "a left-out climate is still named"

    neither = RECORD.call(NO_SITE, NO_DESIGN, nil)
    assert_equal [RECORD::ID, nil, nil, nil, nil],
                 neither.values_at("id", "location", "climate", "provenance", "climate_left_out")
    assert_nil neither.dig("report", "climate")
  end

  def test_an_unset_zone_writes_not_defined_and_an_unset_offset_writes_null
    location = RECORD.call(NEAR.merge("climate_zone" => nil, "hours_from_utc" => nil), NO_DESIGN, nil)
                     .fetch("location")
    assert_equal [1, nil], location.values_at("climate_zone", "hours_from_utc")
  end

  # Provenance: unedited, edited and hand-entered, passed through as stored with the Cooling 2 line added.
  def test_the_provenance_is_passed_through_as_stored_with_the_cooling_2_line
    unedited = RECORD.provenance(station)
    edited = RECORD.provenance(station("daily_temp_swing_k" => 11.0))
    typed = RECORD.provenance(hand(:latitude => 41.2, :longitude => -73.9))

    assert_equal %w[phius_approved user_defined user_defined], [unedited, edited, typed].map { |row|
      row["source_type"]
    }
    assert_equal ["Synthetic Dataset: Synthetic Station", "Synthetic Dataset: Synthetic Station", "Typed climate"],
                 [unedited, edited, typed].map { |row| row["source_name"] }
    assert_equal ["ab" * 32, "ab" * 32, nil], [unedited, edited, typed].map { |row| row["source_checksum"] }
    [unedited, edited, typed].each do |row|
      refute_includes row.keys, "source_uri"
      assert_empty row.keys & %w[dataset_name station_name state]
      assert_equal [true, true, nil], row.values_at("monthly_data_available", "peak_load_data_available",
                                                    "is_certification_approved")
      assert_equal "repeats cooling_load_1", row.dig("assumptions", "ph_composer", "cooling_load_2")
    end
    assert_equal [41.0, -74.0, []], unedited.dig("assumptions", "ph_composer")
                                            .values_at("station_latitude_deg", "station_longitude_deg", "edited_values")
    assert_equal [{ "row" => "daily_temp_swing_k", "column" => nil, "value" => 11.0, "as_read" => 10.5 }],
                 edited.dig("assumptions", "ph_composer", "edited_values")
    assert_equal [41.2, -73.9], typed.dig("assumptions", "ph_composer").values_at("station_latitude_deg",
                                                                                  "station_longitude_deg")
    stored = station.fetch("provenance")
    refute stored.fetch("assumptions").fetch("ph_composer").key?("cooling_load_2"), "the stored record is not changed"
  end

  # Preflight codes on their cases; none blocks.
  def test_each_finding_on_its_case
    unset = NEAR.merge("climate_zone" => nil, "hours_from_utc" => nil)
    assert_equal %w[climate.zone_not_set climate.utc_offset_not_set], codes(unset, station)
    assert_equal %w[climate.zone_not_set climate.utc_offset_not_set], codes(unset, nil),
                 "a written Location says which of its values it writes as unset, with or without a climate"
    assert_empty codes(NO_SITE, nil), "no site and no climate"
    assert_empty codes(NEAR, nil), "a site with no climate"
    assert_empty codes(NEAR, station)
    assert_equal %w[climate.site_not_set], codes(NO_SITE, station)
    gappy = station.merge("wind_speed_m_s" => nil)
    assert_equal %w[climate.incomplete], codes(NEAR, gappy)
    assert_match(/1 value missing/, RECORD.findings(NEAR, gappy).first.last)
    far = NEAR.merge("latitude_deg" => 30.0)
    assert_equal %w[climate.outside_phius_limits], codes(far, station)
    assert_equal %w[climate.not_checked], codes(NEAR, hand)
    assert_empty codes(NEAR, hand(:latitude => 41.2, :longitude => -73.9))
  end

  def test_the_codes_and_the_contributor_are_registered
    registry = PhComposer::Registry.current
    (RECORD::CODES.keys + [RECORD::SITE_NOT_SET]).each { |code| assert_equal PREFIX, registry.codes.fetch(code).owner }
    contributor = registry.export_contributors.fetch(X::SECTION)
    assert_equal [1, [X::ZONES], X::PREFLIGHT],
                 [contributor.section_version, contributor.requires, contributor.preflight]
  end

  def test_the_preflight_reads_the_findings_live_and_none_blocks
    assert_empty preflight
    update_site(SITE.merge("hours_from_utc" => nil))
    rows = preflight
    assert_equal [["climate.utc_offset_not_set", RECORD::ID, false]],
                 rows.map { |row| row.values_at("code", "object_id", "blocks_export") }
    seed(station)
    update_site(NO_SITE)
    assert_equal %w[climate.site_not_set], preflight.map { |row| row.fetch("code") }
  end

  # An unreadable design-temperature dictionary blocks the export, which reads it, and the preflight says so.
  def test_an_unreadable_settings_dictionary_blocks_the_export_and_its_preflight
    @model.set_attribute(PhComposer::Climate::Settings::DESIGN_TEMPERATURES.store.dictionary,
                         PhComposer::Climate::Settings::DESIGN_TEMPERATURES.store.key, "{not json")
    assert_equal "record.unreadable", assert_raises(PhComposer::Export::Blocked) { extract }.code
    assert_equal [["record.unreadable", true]], preflight.map { |row| row.values_at("code", "blocks_export") }
  end

  # The extraction carries the record and its notes; an incomplete climate and one with no site still export.
  def test_the_extraction_writes_one_record_and_its_notes_and_still_exports_a_left_out_climate
    assert_equal [RECORD.call(NO_SITE, NO_DESIGN, nil)], site_records(extract)

    seed(station.merge("wind_speed_m_s" => nil))
    extraction = extract
    assert_equal "site_not_set", site_records(extraction).first.fetch("climate_left_out")
    assert_equal %w[climate.incomplete climate.site_not_set],
                 extraction.findings.map { |row| row.fetch("code") }.sort
    assert(extraction.findings.all? { |row| row.fetch("section") == X::SECTION && row.fetch("object_id") == "Site" })
  end

  # Board 18's case through the station reader, from a copy of the fixture folder under a temporary folder. The
  # golden is the extraction; the folder's absolute path and its parent's name are nowhere in it or in the
  # preflight, while the dataset name, which defaults to the folder's own name, is.
  def test_board_18_extraction_owns_the_golden_and_carries_no_folder_location
    attach_board_18
    extraction = extract
    record = site_records(extraction).first
    assert_equal ["user_defined", nil], [record.dig("provenance", "source_type"), record.fetch("climate_left_out")]
    assert_equal %w[climate.utc_offset_not_set], extraction.findings.map { |row| row.fetch("code") }

    text = JSON.generate([extraction.document, extraction.findings, preflight])
    refute_includes text, @folder
    refute_includes text, File.basename(@root)
    assert_includes text, DATASET
    write_or_compare(EXTRACTION, extraction.document)
    write_or_compare(RESULT_FIELDS, X::RESULT.keys)
  end

  # The report renders the Python section's own result for board 18's extraction (tests/fixtures/climate/
  # result.json), every line of the board, in SI and IP.
  def test_the_report_shows_every_line_of_board_18_in_si_and_ip
    si = report(result_fields, "SI")
    [
      "40.000° N, 100.000° W · 500 m · climate zone 5 · hours from UTC not set",
      "#{DATASET} · Inside Both XA (XA), edited", "Pass. 77.8 km and 121 m from the site. Limits 80 km and 122 m.",
      "1 value differs from the station file: Air, January", "Exported as a user-defined climate.",
      "Heating 1", "Cooling 2", PhComposer::Climate::SiteReport::COOLING_2_LINE, "Wind speed",
      "99% heating -17.2 °C · 1% cooling 30.1 °C · ASHRAE 2021, invented note. Kept in the Model; not " \
      "written to the HBJSON."
    ].each { |line| assert_includes si, h(line) }
    ip = report(result_fields, "IP")
    assert_includes ip, h("99% heating 1 °F · 1% cooling 86.2 °F")
    assert_includes ip, h("1640.42 ft")
    assert_includes ip, h("Limits 50 mi and 400 ft.")
  end

  def test_the_report_names_a_left_out_climate_and_says_no_more_with_no_climate
    fields = result_fields
    left_out = fields.merge("climate_written" => false, "climate_left_out" => "incomplete", "missing_values" => 3,
                            "peak_load_temperatures_c" => nil)
    html = report(left_out, "SI")
    assert_includes html, "Left out of the HBJSON: 3 values missing."
    refute_includes html, "Peak loads"
    refute_includes html, "Exported as a user-defined climate", "a climate left out was not exported"
    no_site = report(fields.merge("location" => nil, "climate_written" => false, "climate_left_out" => "site_not_set",
                                  "limit_check" => RECORD_LIMITS.not_checked("no_site"),
                                  "peak_load_temperatures_c" => nil), "SI")
    assert_includes no_site, "<td>Site</td><td>Not set</td>"
    assert_includes no_site, "Left out of the HBJSON: the site location is not set."
    assert_includes no_site, "Not checked: the site location is not set"
    failing = RECORD_LIMITS.compare(82.3, 10.0)
    assert_includes report(fields.merge("limit_check" => failing), "SI"),
                    "Outside the Phius limits. 82.3 km and 10 m from the site."
    typed = fields.merge("climate" => fields.fetch("climate").merge("origin" => "hand", "name" => "Typed"),
                         "limit_check" => RECORD_LIMITS.not_checked("no_station_coordinates"), "edited_cells" => [])
    html = report(typed, "SI")
    assert_includes html, "Typed, entered by hand"
    assert_includes html, "<td>Phius limit check</td><td>Not checked, entered by hand</td>"
    assert_includes html, "<td>Edited values</td><td>None</td>"

    none = fields.merge("climate" => nil, "climate_written" => false, "limit_check" => nil, "edited_cells" => [],
                        "peak_load_temperatures_c" => nil)
    html = report(none, "SI")
    assert_includes html, "<td>Climate</td><td>No climate</td>"
    %w[Phius Design Wind Peak honeybee default].each { |word| refute_includes html, word }
    assert_empty report_sections({})
  end

  private

  def attach_board_18
    @folder = File.join(@root, DATASET)
    FileUtils.cp_r(File.join(FIXTURES, "folder"), @folder)
    added = UI.stub(:select_directory, @folder) do
      PhComposer::NativeApproval.setup(@context, "#{PREFIX}.folders.add", {})
    end
    update_site(SITE.merge("hours_from_utc" => nil))
    invoke("climate.attach_station", "folder_id" => added.dig("value", "id"), "station_key" => INSIDE)
    values = query("climate.get").fetch("value").dig("climate", "values").slice(*SCHEMA::EDITABLE)
    edited = PhComposer::DeepCopy.call(values)
    edited["monthly"]["air_c"][0] = values.dig("monthly", "air_c", 0) - 0.5
    assert_equal "committed",
                 invoke("climate.save_values", "values" => edited, "expected_values" => values).fetch("effect")
    design = DESIGN.merge("design_temperature_source" => "ASHRAE 2021, invented note")
    assert_equal "committed", invoke("design_temperatures.update", "values" => design,
                                                                   "expected_values" => NO_DESIGN).fetch("effect")
  end

  def result_fields
    JSON.parse(File.read(RESULT)).fetch(X::SECTION)
  end

  def report_sections(fields)
    contributor = PhComposer::Registry.current.export_contributors.fetch(X::SECTION)
    PhComposer::Climate::SiteReport.call(PhComposer::Export::ResultView.new({ X::SECTION => fields }, contributor),
                                         "SI")
  end

  def report(fields, units)
    contributor = PhComposer::Registry.current.export_contributors.fetch(X::SECTION)
    view = PhComposer::Export::ResultView.new({ X::SECTION => fields }, contributor)
    PhComposer::Climate::SiteReport.call(view, units).join
  end

  def h(text)
    PhComposer::Export::ReportHtml.h(text)
  end

  def seed(values)
    @model.start_operation("Seed climate", true)
    SCHEMA::KIND.store.write(@model, { "id" => SCHEMA::RECORD_ID, "schema_version" => 1 }.merge(values))
    @model.commit_operation
  end

  def extract
    PhComposer::Export::Collection.build(@model, :run_id => "run-climate", :contributors => [X::ZONES, X::SECTION])
  end

  def site_records(extraction)
    extraction.document.dig("sections", X::SECTION, "records")
  end

  def preflight
    query("export_preflight").fetch("value").fetch("findings")
  end

  def update_site(values)
    expected = query("site.get").fetch("value").slice(*NO_SITE.keys)
    assert_equal "committed", invoke("site.update", "values" => values, "expected_values" => expected).fetch("effect")
  end

  def query(name, params = {})
    PhComposer::API.query(:context => @context, :name => "#{PREFIX}.#{name}", :params => params)
  end

  def invoke(name, params)
    @sequence += 1
    PhComposer::API.invoke(:context => @context, :name => "#{PREFIX}.#{name}", :params => params,
                           :request => { "sequence" => @sequence, "expected_revision" => @session.revision })
  end
end
