# frozen_string_literal: true

require_relative "test_helper"
require_relative "support/climate_station_files"
require_relative "support/fixture_files"

# One walk of a climate data folder: stations, states and files not read by kind, with the walk's bounds. The
# committed fixture folders are ClimateStationFiles' output, written by `make fixtures`.
class ClimateFolderScanTest < PhComposerTestCase
  include FixtureFiles

  SCAN = PhComposer::Climate::Stations::FolderScan
  FIXTURES = File.expand_path("fixtures/climate", __dir__)

  def setup
    super
    @root = Dir.mktmpdir("climate_scan")
  end

  def teardown
    FileUtils.rm_rf(@root)
    super
  end

  def test_the_committed_fixture_folders_are_the_generators_output
    { "folder" => ClimateStationFiles.folder_files, "second_folder" => ClimateStationFiles.second_files }
      .each do |name, files|
        dir = File.join(FIXTURES, name)
        if FixtureFiles::WRITING
          files.each do |path, bytes|
            target = File.join(dir, path)
            ClimateStationFiles.write(target, bytes) unless File.exist?(target) && File.binread(target) == bytes
          end
        end
        on_disk = Dir.glob("**/*", File::FNM_DOTMATCH, :base => dir).select { |path| File.file?(File.join(dir, path)) }
        assert_equal files.keys.sort, on_disk.sort, "#{name}: run `make fixtures`"
        files.each { |path, bytes| assert_equal bytes, File.binread(File.join(dir, path)), "#{name}/#{path} is stale" }
      end
  end

  def test_the_walk_counts_stations_states_and_files_not_read_by_kind
    scan = SCAN.call(File.join(FIXTURES, "folder"))

    assert_equal %w[XA/INSIDE_BOTH-mon.txt XA/OUTSIDE_DISTANCE-mon.txt XB/CAFE_STATION-mon.txt
                    XB/OUTSIDE_ELEVATION-mon.txt XB/XC/NESTED-mon.txt], scan.stations.map(&:key)
    assert_equal({ ".txt" => 2, ".xls" => 1, ".md" => 1 }, scan.not_read)
    assert scan.complete
    nested = scan.stations.last
    assert_equal %w[XC NESTED Nested\ XC], [nested.state, nested.stem, nested.name]
    assert_equal "Café Station XB", scan.stations.find { |station| station.stem == "CAFE_STATION" }.name
  end

  # A near-duplicate -mon2.txt and a -mon.txt whose header does not read are counted, not listed; a hidden file
  # is neither.
  def test_a_stray_variant_and_a_malformed_file_are_not_stations
    scan = SCAN.call(File.join(FIXTURES, "folder"))

    refute(scan.stations.any? { |station| station.key.include?("mon2") || station.key.include?("MALFORMED") })
    assert_equal 2, scan.not_read.fetch(".txt")
    refute(scan.not_read.key?(""))
  end

  def test_an_oversized_or_nameless_station_file_is_counted_and_a_long_extension_is_cut
    dir = File.join(@root, "Dataset")
    ClimateStationFiles.write(File.join(dir, "XA", "BIG-mon.txt"),
                              station + (" ".b * PhComposer::Climate::Stations::PhiusStationFile::MAX_BYTES))
    ClimateStationFiles.write(File.join(dir, "XA", "-mon.txt"), station)
    ClimateStationFiles.write(File.join(dir, "XA", "odd.#{'x' * 40}"), "x".b)

    scan = SCAN.call(dir)

    assert_empty scan.stations
    assert_equal({ ".txt" => 2, ".#{'x' * 15}" => 1 }, scan.not_read)
  end

  def test_a_station_directly_in_the_folder_takes_the_folders_own_name_as_state
    dir = File.join(@root, "Dataset")
    ClimateStationFiles.write(File.join(dir, "TOP-mon.txt"), station)

    assert_equal [%w[TOP-mon.txt Dataset]], SCAN.call(dir).stations.map { |found| [found.key, found.state] }
  end

  def test_links_are_not_followed_so_a_loop_or_a_folder_outside_is_never_read
    dir = File.join(@root, "Dataset")
    outside = File.join(@root, "Outside")
    ClimateStationFiles.write(File.join(dir, "XA", "IN-mon.txt"), station)
    ClimateStationFiles.write(File.join(outside, "OUT-mon.txt"), station)
    File.symlink(outside, File.join(dir, "XA", "linked"))
    File.symlink(dir, File.join(dir, "XA", "loop"))
    File.symlink(File.join(outside, "OUT-mon.txt"), File.join(dir, "XA", "LINKED-mon.txt"))

    scan = SCAN.call(dir)

    assert_equal ["XA/IN-mon.txt"], scan.stations.map(&:key)
    assert_empty scan.not_read
    assert scan.complete
  end

  def test_a_folder_past_the_walks_bounds_stops_and_says_it_is_not_complete
    dir = File.join(@root, "Dataset")
    3.times { |index| ClimateStationFiles.write(File.join(dir, "XA", "S#{index}-mon.txt"), station) }
    deep = File.join(dir, *Array.new(SCAN::MAX_DEPTH + 1) { |index| "d#{index}" })
    ClimateStationFiles.write(File.join(deep, "DEEP-mon.txt"), station)

    deep_scan = SCAN.call(dir)
    refute deep_scan.complete
    assert_equal 3, deep_scan.stations.length
    refute SCAN.call(dir, :max_entries => 3).complete
    assert SCAN.call(File.join(dir, "XA"), :max_entries => 3).complete
  end

  def station
    ClimateStationFiles.station_bytes(:name => "Invented", :latitude => 40.0, :elevation => 10.0, :offset => 0.0)
  end
end
