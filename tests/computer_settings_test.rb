# frozen_string_literal: true

require_relative "test_helper"

class ComputerSettingsTest < PhComposerTestCase
  Settings = PhComposer::ComputerSettings

  def file
    File.join(Settings.directory, Settings::FILE_NAME)
  end

  def test_the_file_is_created_on_first_write_and_a_later_section_keeps_the_first
    assert_equal({}, Settings.read("ph_composer.first"))
    assert_equal "readable", Settings.state
    refute File.exist?(Settings.directory), "A read must not create the folder."

    Settings.write("ph_composer.first") { |values| values.merge("a" => 1) }
    Settings.write("ph_composer.second") { |values| values.merge("b" => [2]) }

    stored = JSON.parse(File.read(file))
    assert_equal({ "schema_version" => 1, "sections" => { "ph_composer.first" => { "a" => 1 },
                                                          "ph_composer.second" => { "b" => [2] } } }, stored)
    assert_equal({ "a" => 1 }, Settings.read("ph_composer.first"))
    assert_equal [Settings::FILE_NAME, Settings::LOCK_NAME].sort, Dir.children(Settings.directory).sort
  end

  # Two SketchUp processes may be open at once. Each holds the lock across re-read, change and rename, so
  # neither loses the other's section, however their writes interleave.
  def test_two_processes_writing_different_sections_lose_neither
    writes = 40
    child = fork do
      writes.times { |count| Settings.write("ph_composer.child") { { "count" => count + 1 } } }
      exit!(0)
    end
    writes.times { |count| Settings.write("ph_composer.parent") { { "count" => count + 1 } } }
    _pid, status = Process.wait2(child)

    assert_predicate status, :success?
    assert_equal({ "count" => writes }, Settings.read("ph_composer.child"))
    assert_equal({ "count" => writes }, Settings.read("ph_composer.parent"))
  end

  # A second writer waits for the lock and refuses when it does not come, rather than writing past it.
  def test_a_writer_that_cannot_take_the_lock_refuses_and_writes_nothing
    error = nil
    Settings.write("ph_composer.first") do
      error = assert_raises(Settings::Refused) { Settings.write("ph_composer.second") { { "b" => 1 } } }
      { "a" => 1 }
    end

    assert_equal :unwritable, error.reason
    assert_equal({}, Settings.read("ph_composer.second"))
    assert_equal({ "a" => 1 }, Settings.read("ph_composer.first"))
  end

  def test_an_interrupted_write_leaves_the_old_file_and_no_partial_copy
    Settings.write("ph_composer.first") { { "kept" => true } }
    before = File.binread(file)

    error = File.stub(:rename, ->(*) { raise Errno::EIO, file }) do
      assert_raises(Settings::Refused) { Settings.write("ph_composer.first") { { "kept" => false } } }
    end

    assert_equal :unwritable, error.reason
    refute_includes error.message, Settings.directory
    assert_equal before, File.binread(file)
    assert_equal [Settings::FILE_NAME, Settings::LOCK_NAME].sort, Dir.children(Settings.directory).sort
    # A copy a crashed process left beside the file is cleared by the next write.
    File.write(File.join(Settings.directory, ".#{Settings::FILE_NAME}.abc123.tmp"), "partial")
    Settings.write("ph_composer.first") { { "kept" => true } }
    assert_equal [Settings::FILE_NAME, Settings::LOCK_NAME].sort, Dir.children(Settings.directory).sort
  end

  def test_an_unreadable_file_and_a_later_version_are_left_as_stored_reads_report_and_writes_refuse
    FileUtils.mkdir_p(Settings.directory)
    { "not json {" => :unreadable, JSON.generate("schema_version" => 1) => :unreadable,
      JSON.generate("schema_version" => 2, "sections" => {}) => :later_version }.each do |text, reason|
      File.write(file, text)

      read = assert_raises(Settings::Refused) { Settings.read("ph_composer.first") }
      written = assert_raises(Settings::Refused) { Settings.write("ph_composer.first") { { "a" => 1 } } }

      assert_equal [reason, reason], [read.reason, written.reason]
      assert_equal reason.to_s, Settings.state
      assert_equal text, File.read(file)
      refute_includes read.message, Settings.directory
    end
  end

  def test_a_write_over_the_size_bound_refuses_and_an_oversized_file_is_unreadable
    error = assert_raises(Settings::Refused) do
      Settings.write("ph_composer.first") { { "text" => "x" * Settings::MAX_BYTES } }
    end
    assert_equal :too_large, error.reason
    refute File.exist?(file)

    File.write(file, JSON.generate("schema_version" => 1, "sections" => { "a" => "x" * Settings::MAX_BYTES }))
    assert_equal "unreadable", Settings.state
  end

  def test_on_a_platform_other_than_macos_the_service_is_unavailable_and_creates_nothing
    Sketchup.platform_value = :platform_win

    read = assert_raises(Settings::Refused) { Settings.read("ph_composer.first") }
    written = assert_raises(Settings::Refused) { Settings.write("ph_composer.first") { {} } }

    assert_equal %i[unavailable unavailable], [read.reason, written.reason]
    assert_equal "unavailable", Settings.state
    refute File.exist?(Settings.directory)
  end
end
