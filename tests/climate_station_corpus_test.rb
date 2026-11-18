# frozen_string_literal: true

require_relative "test_helper"

# The reader over a licensed station corpus kept outside the repository, when PH_COMPOSER_CLIMATE_CORPUS names
# its folder (its location is recorded only in the gitignored _private/climate/MANIFEST.md). It asserts counts and
# timings only: no station name, coordinate or value appears in an assertion or its message.
class ClimateStationCorpusTest < PhComposerTestCase
  VARIABLE = "PH_COMPOSER_CLIMATE_CORPUS"
  STATIONS = PhComposer::Climate::Stations

  def test_every_station_file_in_the_corpus_parses_or_is_counted_as_not_read
    root = ENV.fetch(VARIABLE, "")
    skip "Set #{VARIABLE} to a folder of Phius station files to run this test." if root.empty?
    assert File.directory?(root), "#{VARIABLE} does not name a folder."

    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    scan = STATIONS::FolderScan.call(File.expand_path(root))
    walked = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started
    unreadable = scan.stations.count do |station|
      STATIONS::PhiusStationFile.parse(File.binread(station.path))
      false
    rescue STATIONS::PhiusStationFile::Unreadable
      true
    end
    files = Dir.glob("**/*", :base => root).count { |path| File.lstat(File.join(root, path)).file? }
    station_files = Dir.glob("**/*#{STATIONS::PhiusStationFile::SUFFIX}", :base => root).length

    assert scan.complete, "The walk stopped before the end of the corpus."
    assert_operator scan.stations.length, :>, 0, "No station was found."
    assert_operator scan.stations.length, :<=, station_files
    assert_equal 0, unreadable, "#{unreadable} listed stations did not parse whole."
    assert_operator scan.stations.map(&:state).uniq.length, :>, 0
    assert_equal files, scan.stations.length + scan.not_read.values.sum,
                 "A file was neither listed as a station nor counted as not read."
    assert_operator walked, :<, 2.0, "The walk took #{walked.round(3)} s."
  end
end
