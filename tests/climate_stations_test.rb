# frozen_string_literal: true

require "minitest/mock"
require_relative "test_helper"
require_relative "support/climate_station_files"

# The station reads and writes through the public API with the panel closed, over copies of the invented fixture
# folders: the folder counts, the station list against the site, attach and replace as one Undo step each, and
# the source status matched across folders by station name and state.
class ClimateStationsTest < PhComposerTestCase
  PREFIX = "ph_composer.climate"
  FIXTURES = File.expand_path("fixtures/climate", __dir__)
  SITE = ClimateStationFiles::SITE.merge("climate_zone" => nil, "hours_from_utc" => nil).freeze
  SCHEMA = PhComposer::Climate::Schema
  INSIDE = "XA/INSIDE_BOTH-mon.txt"

  def setup
    super
    PhComposer.compose unless PhComposer::Registry.installed?("ph_composer.climate")
    @model = Sketchup.active_model
    @session = PhComposer::Sessions.for(@model)
    @context = PhComposer::API.connect(:session_id => @session.id, :capabilities => %w[read setup model_write])
    @root = Dir.mktmpdir("climate_stations")
    @sequence = 0
  end

  def teardown
    FileUtils.rm_rf(@root)
    super
  end

  # A copy of a fixture folder under `name`, added as a climate data folder the user chose.
  def add_folder(fixture, name)
    path = File.join(@root, name)
    FileUtils.cp_r(File.join(FIXTURES, fixture), path)
    added = UI.stub(:select_directory, path) do
      PhComposer::NativeApproval.setup(@context, "#{PREFIX}.folders.add", {})
    end
    [added.dig("value", "id"), path]
  end

  def query(name, params = {})
    PhComposer::API.query(:context => @context, :name => "#{PREFIX}.#{name}", :params => params)
  end

  def invoke(name, params)
    @sequence += 1
    PhComposer::API.invoke(:context => @context, :name => "#{PREFIX}.#{name}", :params => params,
                           :request => { "sequence" => @sequence, "expected_revision" => @session.revision })
  end

  def set_site(values = SITE)
    expected = query("site.get").fetch("value").slice(*SITE.keys)
    assert_equal "committed", invoke("site.update", "values" => values, "expected_values" => expected).fetch("effect")
  end

  def climate
    query("climate.get").fetch("value")
  end

  def new_operations(before)
    @model.operations.drop(before).map(&:first)
  end

  def test_the_reads_and_writes_are_registered_with_their_grants_undo_names_and_codes
    registry = PhComposer::Registry.current
    grants = %W[#{PREFIX}.stations.list #{PREFIX}.climate.source_status #{PREFIX}.climate.attach_station
                #{PREFIX}.climate.replace_station].map { |name| PhComposer::API.describe(:name => name)["capability"] }

    assert_equal %w[read read model_write model_write], grants
    assert_equal %w[Attach\ Climate\ Station Replace\ Climate\ Station],
                 %w[attach_station replace_station].map { |verb|
                   registry.actions.fetch("#{PREFIX}.climate.#{verb}").undo_name
                 }
    %w[climate.site_not_set climate.station_not_found climate.station_unreadable].each do |code|
      assert_equal PREFIX, registry.codes.fetch(code).owner
    end
    %w[attach_station replace_station].each do |verb|
      assert_equal %w[folder_id station_key],
                   registry.actions.fetch("#{PREFIX}.climate.#{verb}").params.fetch("properties").keys
    end
  end

  def test_folders_list_counts_stations_states_and_files_not_read_and_the_setup_summary_follows
    id, path = add_folder("folder", "Phius A")
    absent_id, absent = add_folder("second_folder", "Gone")
    FileUtils.rm_rf(absent)

    rows = query("folders.list").dig("value", "folders").to_h { |row| [row.fetch("id"), row] }

    assert_equal({ "found" => true, "format" => "phius_station_file", "station_count" => 5, "state_count" => 3,
                   "files_not_read" => [{ "extension" => ".txt", "count" => 2 }, { "extension" => ".md", "count" => 1 },
                                        { "extension" => ".xls", "count" => 1 }],
                   "files_not_read_total" => 4, "complete" => true },
                 rows.fetch(id).reject { |key, _| %w[id name display_location].include?(key) })
    assert_equal [false, nil, nil, nil], rows.fetch(absent_id).values_at("found", "format", "station_count",
                                                                         "files_not_read")
    assert_equal "2 folders, 5 stations", PhComposer::Climate::Folders::Operations.setup_summary
    FileUtils.rm_rf(File.join(path, "XB"))
    assert_equal "2 folders, 2 stations", PhComposer::Climate::Folders::Operations.setup_summary
  end

  def test_the_station_list_refuses_with_no_site_or_folder
    id, path = add_folder("folder", "Phius A")
    no_site = query("stations.list", "folder_id" => id)
    set_site
    unknown = query("stations.list", "folder_id" => "climate_folder_AbCdEf123456")
    FileUtils.rm_rf(path)
    gone = query("stations.list", "folder_id" => id)

    assert_equal %w[climate.site_not_set climate.folder_not_found climate.folder_not_found],
                 [no_site, unknown, gone].map { |outcome| outcome.fetch("code") }
  end

  # Distances along the site's meridian, worked by hand: R * dlat * pi / 180 with R = 6,371.0088 km.
  def test_the_station_list_gives_hand_checked_distances_and_verdicts_on_both_sides_of_each_limit
    id, = add_folder("folder", "Phius A")
    set_site

    value = query("stations.list", "folder_id" => id).fetch("value")
    rows = value.fetch("stations").to_h { |row| [row.fetch("key"), row] }

    assert_equal ["Phius A", 5, nil, true], value.values_at("dataset_name", "total", "next_cursor", "complete")
    { INSIDE => [77.8366, 121.0, "pass", true, true],
      "XA/OUTSIDE_DISTANCE-mon.txt" => [82.2844, 0.0, "fail", false, true],
      "XB/OUTSIDE_ELEVATION-mon.txt" => [11.1195, 123.0, "fail", true, false],
      "XB/CAFE_STATION-mon.txt" => [5.5598, 120.0, "pass", true, true],
      "XB/XC/NESTED-mon.txt" => [11.1195, 0.0, "pass", true, true] }.each do |key, (km, metres, verdict, *oks)|
      check = rows.fetch(key).fetch("limit_check")
      assert_in_delta km, check.fetch("distance_km"), 1e-4, key
      assert_in_delta metres, check.fetch("elevation_difference_m"), 1e-9, key
      assert_equal [verdict, *oks], check.values_at("verdict", "distance_ok", "elevation_ok"), key
    end
    distances = value.fetch("stations").map { |row| row.dig("limit_check", "distance_km") }
    assert_equal distances.sort, distances
    assert_equal({ "key" => "XB/XC/NESTED-mon.txt", "name" => "Nested XC", "state" => "XC", "latitude_deg" => 39.9,
                   "longitude_deg" => -100.0, "elevation_m" => 500.0 },
                 rows.fetch("XB/XC/NESTED-mon.txt").reject { |key, _| key == "limit_check" })
  end

  def test_the_station_list_pages_nearest_first_and_a_site_change_expires_the_cursor
    id, = add_folder("folder", "Phius A")
    set_site

    first = query("stations.list", "folder_id" => id, "limit" => 2).fetch("value")
    second = query("stations.list", "folder_id" => id, "limit" => 2, "cursor" => first.fetch("next_cursor"))
    whole = query("stations.list", "folder_id" => id).dig("value", "stations").map { |row| row.fetch("key") }

    assert_equal "XB/CAFE_STATION-mon.txt", first.dig("stations", 0, "key")
    assert_equal whole.first(4), (first.fetch("stations") + second.dig("value", "stations")).map { |row| row["key"] }
    set_site(SITE.merge("latitude_deg" => 41.0))
    expired = query("stations.list", "folder_id" => id, "limit" => 2, "cursor" => first.fetch("next_cursor"))
    assert_equal "query.cursor_expired", expired.fetch("code")
  end

  # The station picker reads one folder whole in one call, past the bounded page's budget, in the list's order.
  def test_stations_all_reads_every_station_in_one_call_unbounded_in_the_lists_order
    id, path = add_folder("folder", "Phius A")
    80.times do |index|
      bytes = ClimateStationFiles.station_bytes(name: "Many #{index}", latitude: 41.0 + (index * 0.01),
                                                elevation: 500.0, offset: 1.0)
      FileUtils.mkdir_p(File.join(path, "XM"))
      File.binwrite(File.join(path, "XM", "MANY_#{index}-mon.txt"), bytes)
    end
    no_site = query("stations.all", "folder_id" => id)
    set_site

    value = query("stations.all", "folder_id" => id).fetch("value")
    paged = query("stations.list", "folder_id" => id).fetch("value")

    assert_equal "climate.site_not_set", no_site.fetch("code")
    assert_equal({ "bounded" => false, "prefer" => "#{PREFIX}.stations.list" },
                 PhComposer::Registry.current.queries.fetch("#{PREFIX}.stations.all").response)
    refute_nil paged.fetch("next_cursor"), "85 stations are more than one bounded page"
    assert_equal ["Phius A", 85, true], value.values_at("dataset_name", "total", "complete")
    assert_equal 85, value.fetch("stations").length
    assert_equal paged.fetch("stations"), value.fetch("stations").first(paged.fetch("stations").length)
    refute value.key?("next_cursor")
  end

  def test_attach_copies_the_values_the_as_read_copy_the_source_and_the_wind_prefill_in_one_undo_step
    id, path = add_folder("folder", "Phius A")
    set_site
    operations = @model.operations.length

    result = invoke("climate.attach_station", "folder_id" => id, "station_key" => INSIDE)

    assert_equal ["committed", "complete"], [result.fetch("effect"), result.dig("value", "state")]
    assert_equal ["Attach Climate Station"], new_operations(operations)
    values = climate.dig("climate", "values")
    parsed = PhComposer::Climate::Stations::PhiusStationFile.parse(File.binread(File.join(path, INSIDE)))
    assert_equal parsed.fetch("monthly"), values.fetch("monthly")
    assert_equal parsed.fetch("peak_loads"), values.fetch("peak_loads")
    assert_equal values.slice("monthly", "peak_loads"), values.fetch("as_read").slice("monthly", "peak_loads")
    assert_equal ["Inside Both XA", 40.7, -100.0, 621.0, 10.5, 3.0],
                 values.values_at("name", "station_latitude_deg", "station_longitude_deg", "station_elevation_m",
                                  "daily_temp_swing_k", "wind_speed_m_s")
    assert_equal ["Phius A", "INSIDE_BOTH", "XA", Digest::SHA256.file(File.join(path, INSIDE)).hexdigest,
                  "phius_approved"],
                 values.fetch("provenance").values_at("dataset_name", "station_name", "state", "source_checksum",
                                                      "source_type")
    assert_equal "pass", climate.dig("limit_check", "verdict")
    @model.undo
    assert_equal "none", climate.fetch("state")
  end

  def test_attach_refuses_with_no_site_an_unknown_key_a_file_that_does_not_parse_and_over_a_climate
    id, path = add_folder("folder", "Phius A")
    no_site = invoke("climate.attach_station", "folder_id" => id, "station_key" => INSIDE)
    set_site
    broken = File.join(path, "XA", "BROKEN-mon.txt")
    File.binwrite(broken, ClimateStationFiles.station_bytes(:name => "Broken XA", :latitude => 40.1,
                                                            :elevation => 500.0, :offset => 0.0, :drop => "Global"))
    operations = @model.operations.length

    refusals = [["climate_folder_AbCdEf123456", INSIDE], [id, "XA/ABSENT-mon.txt"], [id, "../folder/#{INSIDE}"],
                [id, "XA/INSIDE_BOTH-mon2.txt"], [id, "XA/BROKEN-mon.txt"]].map do |folder, key|
      invoke("climate.attach_station", "folder_id" => folder, "station_key" => key)
    end
    invoke("climate.attach_station", "folder_id" => id, "station_key" => INSIDE)
    again = invoke("climate.attach_station", "folder_id" => id, "station_key" => "XB/CAFE_STATION-mon.txt")

    assert_equal %w[climate.site_not_set climate.folder_not_found climate.station_not_found
                    climate.station_not_found climate.station_not_found climate.station_unreadable target.changed],
                 ([no_site] + refusals + [again]).map { |outcome| outcome.fetch("code") }
    assert_includes refusals.last.fetch("message"), "Global"
    assert_equal ["Attach Climate Station"], new_operations(operations)
  end

  def test_replace_is_one_undo_step_and_reports_the_edits_it_loses
    id, = add_folder("folder", "Phius A")
    set_site
    invoke("climate.attach_station", "folder_id" => id, "station_key" => INSIDE)
    values = climate.dig("climate", "values").slice(*SCHEMA::EDITABLE)
    edited = Marshal.load(Marshal.dump(values))
    edited["monthly"]["air_c"][0] = -40.0
    edited["daily_temp_swing_k"] = 1.0
    invoke("climate.save_values", "values" => edited, "expected_values" => values)
    operations = @model.operations.length

    result = invoke("climate.replace_station", "folder_id" => id, "station_key" => "XB/CAFE_STATION-mon.txt")

    assert_equal "committed", result.fetch("effect")
    assert_equal({ "name" => "Inside Both XA", "origin" => "station", "lost_edited_cells" => 2 },
                 result.dig("value", "replaced"))
    assert_equal ["Replace Climate Station"], new_operations(operations)
    assert_equal ["Café Station XB", []], [climate.dig("climate", "values", "name"), climate.fetch("edited_cells")]
    @model.undo
    assert_equal ["Inside Both XA", 2], [climate.dig("climate", "values", "name"), climate.fetch("edited_cells").length]
  end

  # A file whose optional swing and winds are absent attaches with them null; a file gone after the walk is
  # refused without its path.
  def test_attach_takes_null_optional_values_and_refuses_a_file_gone_after_the_walk
    id, path = add_folder("folder", "Phius A")
    set_site
    sparse = File.join(path, "XA", "INSIDE_BOTH-mon.txt")
    File.binwrite(sparse, File.binread(sparse).sub(/^Heating degree-hours[^\r]*\r\n/n, "")
                              .sub(/\tDaily temperature variation summer \(K\)\t[^\t]+/n, ""))
    scan = PhComposer::Climate::Stations::FolderScan
    walk = scan.method(:call)
    gone = scan.stub(:call, lambda { |root|
      walk.call(root).tap { File.delete(File.join(path, "XB", "CAFE_STATION-mon.txt")) }
    }) do
      invoke("climate.attach_station", "folder_id" => id, "station_key" => "XB/CAFE_STATION-mon.txt")
    end

    attached = invoke("climate.attach_station", "folder_id" => id, "station_key" => INSIDE)

    assert_equal "climate.station_not_found", gone.fetch("code")
    refute_includes JSON.generate(gone) + PhComposer::Diagnostics.tail.join, @root
    assert_equal %w[committed incomplete], [attached.fetch("effect"), attached.dig("value", "state")]
    assert_equal [nil, nil], climate.dig("climate", "values").values_at("daily_temp_swing_k", "wind_speed_m_s")
  end

  def test_replace_refuses_with_no_climate
    id, = add_folder("folder", "Phius A")
    set_site

    result = invoke("climate.replace_station", "folder_id" => id, "station_key" => INSIDE)

    assert_equal "climate.not_found", result.fetch("code")
  end

  def test_source_status_reads_found_changed_and_not_on_this_computer_matched_across_folders
    assert_equal "not_applicable", query("climate.source_status").dig("value", "status")
    id, path = add_folder("folder", "Phius A")
    set_site
    invoke("climate.attach_station", "folder_id" => id, "station_key" => INSIDE)

    found = query("climate.source_status").fetch("value")
    File.binwrite(File.join(path, INSIDE), "damaged\r\n".b)
    damaged = query("climate.source_status").fetch("value")
    File.binwrite(File.join(path, INSIDE), ClimateStationFiles.second_files.fetch(INSIDE))
    changed = query("climate.source_status").dig("value", "status")
    FileUtils.rm_rf(path)
    gone = query("climate.source_status").dig("value", "status")
    # The same file in a folder of another name is the same source (J6).
    other_id, other = add_folder("second_folder", "Renamed dataset")
    File.binwrite(File.join(other, INSIDE), ClimateStationFiles.folder_files.fetch(INSIDE))
    again = query("climate.source_status").fetch("value")

    assert_equal({ "status" => "found", "folder_id" => id, "station_key" => INSIDE }, found)
    assert_equal({ "status" => "changed", "folder_id" => id, "station_key" => INSIDE }, damaged)
    assert_equal %w[changed not_on_this_computer], [changed, gone]
    assert_equal({ "status" => "found", "folder_id" => other_id, "station_key" => INSIDE }, again)
  end

  def test_source_status_in_a_second_folder_with_other_values_reads_changed_and_update_from_file_replaces
    id, = add_folder("folder", "Phius A")
    set_site
    invoke("climate.attach_station", "folder_id" => id, "station_key" => INSIDE)
    second_id, = add_folder("second_folder", "Phius B")
    PhComposer::Climate::Folders::Operations.remove(id)

    status = query("climate.source_status").fetch("value")
    update = invoke("climate.replace_station", "folder_id" => status.fetch("folder_id"),
                                               "station_key" => status.fetch("station_key"))

    assert_equal({ "status" => "changed", "folder_id" => second_id, "station_key" => INSIDE }, status)
    assert_equal "committed", update.fetch("effect")
    assert_equal "found", query("climate.source_status").dig("value", "status")
    assert_equal "Phius B", climate.dig("climate", "values", "provenance", "dataset_name")
  end

  def test_a_hand_entered_climate_has_no_source_status
    invoke("climate.enter_values", "values" => { "name" => "Typed", "station_latitude_deg" => nil,
                                                 "station_longitude_deg" => nil, "station_elevation_m" => 1.0,
                                                 "daily_temp_swing_k" => nil, "wind_speed_m_s" => nil,
                                                 "monthly" => SCHEMA.empty_monthly,
                                                 "peak_loads" => SCHEMA.empty_peak_loads })

    assert_equal({ "status" => "not_applicable", "folder_id" => nil, "station_key" => nil },
                 query("climate.source_status").fetch("value"))
  end

  # No path enters the record, a result or the log, and no value of the file is in the params: attach names a
  # station and Ruby reads it.
  def test_no_path_reaches_the_record_the_answers_or_the_log
    id, path = add_folder("folder", "Phius A")
    set_site
    answers = [query("folders.list"), query("stations.list", "folder_id" => id),
               invoke("climate.attach_station", "folder_id" => id, "station_key" => INSIDE),
               query("climate.source_status"),
               invoke("climate.replace_station", "folder_id" => id, "station_key" => "XA/MALFORMED-mon.txt")]
    record = SCHEMA::KIND.store.read(@model, SCHEMA::RECORD_ID)

    text = JSON.generate(answers) + JSON.generate(record) + PhComposer::Diagnostics.tail.join
    [path, File.realpath(path), @root].each { |location| refute_includes text, location }
    refute_includes JSON.generate(answers), "\"monthly\""
  end
end
