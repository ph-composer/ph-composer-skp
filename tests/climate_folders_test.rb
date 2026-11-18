# frozen_string_literal: true

require "minitest/mock"
require_relative "test_helper"

class ClimateFoldersTest < PhComposerTestCase
  PREFIX = "ph_composer.climate.folders"
  Folders = PhComposer::Climate::Folders
  COMMANDS = %w[add locate rename remove remember_dataset].freeze

  def setup
    super
    PhComposer.compose unless PhComposer::Registry.installed?("ph_composer.climate")
    @model = Sketchup.active_model
    @session = PhComposer::Sessions.for(@model)
    @context = PhComposer::API.connect(:session_id => @session.id, :capabilities => %w[read setup])
    @root = Dir.mktmpdir("climate_folders")
  end

  def teardown
    FileUtils.rm_rf(@root)
    super
  end

  def folder(name)
    File.join(@root, name).tap { |path| FileUtils.mkdir_p(path) }
  end

  # The panel's route: the chooser answers `path`, then the command runs with what the user chose.
  def choose(name, path, params = {})
    UI.stub(:select_directory, path) { PhComposer::NativeApproval.setup(@context, "#{PREFIX}.#{name}", params) }
  end

  def setup_command(name, params)
    PhComposer::API.setup(:context => @context, :name => "#{PREFIX}.#{name}", :params => params)
  end

  def list
    PhComposer::API.query(:context => @context, :name => "#{PREFIX}.list").fetch("value")
  end

  def stored
    Folders::Store.read
  end

  def test_add_rename_locate_and_remove_change_the_section_and_never_the_model
    revision = @session.revision

    added = choose("add", folder("Phius 2022")).fetch("value")
    assert_equal({ "name" => "Phius 2022", "found" => true }, added.slice("name", "found"))
    id = added.fetch("id")
    assert_match(/\Aclimate_folder_[A-Za-z0-9]{12}\z/, id)
    renamed = setup_command("rename", "id" => id, "name" => "  Phius climate  ").fetch("value")
    assert_equal "Phius climate", renamed.fetch("name")
    moved = folder("moved")
    assert_equal id, choose("locate", moved, "id" => id).dig("value", "id")
    assert_equal [{ "id" => id, "name" => "Phius climate", "location" => File.expand_path(moved) }],
                 stored.fetch("folders")
    assert_equal id, setup_command("remember_dataset", "id" => id).dig("value", "last_dataset_id")

    removed = setup_command("remove", "id" => id)

    assert_equal({ "folders" => [], "last_dataset_id" => nil }, removed.fetch("value"))
    assert_equal({ "folders" => [], "last_dataset_id" => nil }, list)
    assert_equal revision, @session.revision
    assert_empty @model.operations
    refute @model.modified?
  end

  # Only the user chooses a folder: a scripted add is refused before any chooser opens. A folder they
  # approved in SketchUp may stand in for the chooser, as for every approved command.
  def test_a_scripted_add_with_no_approval_refuses_and_an_approved_folder_is_admitted
    UI.stub(:select_directory, ->(*) { flunk "A scripted add must not open the chooser." }) do
      %w[add locate].each do |name|
        outcome = setup_command(name, name == "add" ? {} : { "id" => "climate_folder_AbCdEf123456" })
        assert_equal %w[refused access.user_required none], outcome.values_at("status", "code", "effect"), name
      end
    end
    assert_equal "cancelled", choose("add", nil).fetch("status")
    assert_empty stored.fetch("folders")

    location = PhComposer::ApprovedLocations.approve(:kind => "open_folder", :path => folder("Approved"))
    outcome = setup_command("add", "location" => { "id" => location.fetch("id") })

    assert_equal "completed", outcome.fetch("status")
    assert_equal "Approved", outcome.dig("value", "name")
  end

  def test_the_folder_commands_need_the_setup_grant
    viewer = PhComposer::API.connect(:session_id => @session.id, :capabilities => %w[read view])
    outcome = PhComposer::API.setup(:context => viewer, :name => "#{PREFIX}.remove",
                                    :params => { "id" => "climate_folder_AbCdEf123456" })

    assert_equal "request.capability_denied", outcome.fetch("code")
    COMMANDS.each do |name|
      assert_equal "setup_command", PhComposer::API.describe(:name => "#{PREFIX}.#{name}").fetch("kind"), name
    end
  end

  # A folder may be on a drive that is not connected: its row stays, reads not found, and Locate repairs it.
  def test_a_missing_folder_keeps_its_row_reads_not_found_and_locate_repairs_it
    gone = folder("Unplugged drive")
    id = choose("add", gone).dig("value", "id")
    FileUtils.rm_rf(gone)

    2.times { assert_equal [false], list.fetch("folders").map { |row| row.fetch("found") } }
    assert_equal 1, stored.fetch("folders").length

    repaired = choose("locate", folder("Reconnected"), "id" => id).fetch("value")
    assert_equal({ "id" => id, "name" => "Unplugged drive", "found" => true }, repaired.slice("id", "name", "found"))
  end

  def test_a_folder_already_listed_or_inside_or_around_one_refuses
    listed = folder("climate/phius")
    choose("add", listed)

    link = File.join(@root, "link to phius")
    File.symlink(listed, link)
    [listed, "#{listed}/", folder("climate/phius/NY"), folder("climate"), link].each do |path|
      outcome = choose("add", path)
      assert_equal %w[refused climate.folder_overlaps], outcome.values_at("status", "code"), path
      refute_includes outcome.fetch("message"), @root
    end
    assert_equal "completed", choose("add", folder("climate/phius2")).fetch("status")
    other = choose("add", folder("other")).dig("value", "id")
    assert_equal "climate.folder_overlaps", choose("locate", listed, "id" => other).fetch("code")
    assert_equal "completed", choose("locate", folder("other/moved"), "id" => other).fetch("status")
    assert_equal 3, stored.fetch("folders").length
  end

  def test_an_unknown_id_refuses_folder_not_found_and_locate_opens_no_chooser
    choose("add", folder("Phius"))
    unknown = { "id" => "climate_folder_AbCdEf123456" }

    %w[rename remove remember_dataset].each do |name|
      params = name == "rename" ? unknown.merge("name" => "New") : unknown
      assert_equal "climate.folder_not_found", setup_command(name, params).fetch("code"), name
    end
    UI.stub(:select_directory, ->(*) { flunk "Locate must not open the chooser for an unknown setting." }) do
      assert_equal "climate.folder_not_found",
                   PhComposer::NativeApproval.setup(@context, "#{PREFIX}.locate", unknown).fetch("code")
    end
    ["never made", "x" * 1100, "nul\0name"].each do |name|
      assert_equal "climate.folder_not_found", choose("add", "#{@root}/#{name}").fetch("code"), name[0, 12]
    end
    assert_equal "params.invalid",
                 setup_command("rename", "id" => list.dig("folders", 0, "id"), "name" => "   ").fetch("code")
  end

  def test_removing_the_remembered_dataset_forgets_it
    first = choose("add", folder("First")).dig("value", "id")
    second = choose("add", folder("Second")).dig("value", "id")
    setup_command("remember_dataset", "id" => first)

    assert_equal first, setup_command("remove", "id" => second).dig("value", "last_dataset_id")
    assert_nil setup_command("remove", "id" => first).dig("value", "last_dataset_id")
  end

  # An unreadable settings file, or one a later version wrote, is reported and never replaced.
  def test_an_unreadable_settings_file_is_left_as_stored_reported_and_refused_before_the_chooser
    file = File.join(PhComposer::ComputerSettings.directory, PhComposer::ComputerSettings::FILE_NAME)
    FileUtils.mkdir_p(File.dirname(file))
    sections = [{ "folders" => "not a list" }, 5, nil, true, [], "text"].map do |section|
      JSON.generate("schema_version" => 1, "sections" => { "ph_composer.climate" => section })
    end
    (["not json"] + sections).each do |text|
      File.write(file, text)

      assert_equal "climate.settings_unreadable",
                   PhComposer::API.query(:context => @context, :name => "#{PREFIX}.list").fetch("code")
      UI.stub(:select_directory, ->(*) { flunk "An unreadable file must not open the chooser." }) do
        assert_equal "climate.settings_unreadable",
                     PhComposer::NativeApproval.setup(@context, "#{PREFIX}.add", {}).fetch("code")
      end
      assert_equal "climate.settings_unreadable",
                   setup_command("remove", "id" => "climate_folder_AbCdEf123456").fetch("code")
      assert_equal text, File.read(file)
    end
  end

  def test_the_setup_summary_reads_each_state
    summary = -> { Folders::Operations.setup_summary }
    assert_equal "No climate data folder", summary.call
    choose("add", folder("One"))
    assert_equal "1 folder", summary.call
    choose("add", folder("Two"))
    choose("add", folder("Three"))
    assert_equal "3 folders", summary.call

    File.write(File.join(PhComposer::ComputerSettings.directory, PhComposer::ComputerSettings::FILE_NAME), "{")
    assert_equal "The climate data settings cannot be read", summary.call
    Sketchup.platform_value = :platform_win
    assert_equal "Not available on this computer yet", summary.call
  end

  def test_on_a_platform_other_than_macos_the_folder_commands_refuse
    Sketchup.platform_value = :platform_win

    assert_equal "climate.settings_unavailable",
                 PhComposer::API.query(:context => @context, :name => "#{PREFIX}.list").fetch("code")
    UI.stub(:select_directory, ->(*) { flunk "No chooser opens where the settings file is unavailable." }) do
      assert_equal "climate.settings_unavailable",
                   PhComposer::NativeApproval.setup(@context, "#{PREFIX}.add", {}).fetch("code")
    end
    %w[rename remove remember_dataset].each do |name|
      params = { "id" => "climate_folder_AbCdEf123456" }
      params["name"] = "New" if name == "rename"
      assert_equal "climate.settings_unavailable", setup_command(name, params).fetch("code"), name
    end
    refute File.exist?(PhComposer::ComputerSettings.directory)
  end

  # The folder's path stays in the settings file: no declared param or result field names one, and no answer
  # or diagnostic line holds the absolute path, under the home folder or outside it.
  def test_no_absolute_path_reaches_params_results_or_the_log
    registry = PhComposer::Registry.current
    declarations = COMMANDS.map { |name| registry.setup_commands.fetch("#{PREFIX}.#{name}") } +
                   [registry.queries.fetch("#{PREFIX}.list")]
    declarations.each do |declaration|
      params = declaration.params.fetch("properties").keys - ["location"]
      assert_empty params - %w[id name], declaration.name
      location = declaration.params.dig("properties", "location")
      assert_equal %w[id], location.fetch("properties").keys, declaration.name if location
    end

    home_folder = File.join(Dir.home, ".ph_composer_test_#{SecureRandom.hex(4)}")
    FileUtils.mkdir_p(home_folder)
    begin
      answers = [choose("add", folder("Outside home")), choose("add", home_folder)]
      id = answers.last.dig("value", "id")
      answers << setup_command("rename", "id" => id, "name" => "Renamed")
      answers << choose("locate", folder("Moved"), "id" => id)
      answers << choose("add", folder("Moved"))
      answers << choose("add", File.join(@root, "absent"))
      answers << PhComposer::API.query(:context => @context, :name => "#{PREFIX}.list")
      answers << setup_command("remember_dataset", "id" => id)
      answers << setup_command("remove", "id" => id)
      # An unexpected failure carrying the path in its message is logged by class only.
      failed = PhComposer::Climate::Folders::Store.stub(:update, ->(*) { raise Errno::EIO, home_folder }) do
        choose("add", folder("Failing"))
      end
      assert_equal "operation.failed", failed.fetch("code")
      answers << failed
      refute_empty PhComposer::Diagnostics.tail
      text = JSON.generate(answers) + PhComposer::Diagnostics.tail.join

      [@root, File.realpath(@root), home_folder, Dir.home].each { |path| refute_includes text, path }
      assert_includes JSON.generate(answers), "~/#{File.basename(home_folder)}"
    ensure
      FileUtils.rm_rf(home_folder)
    end
  end

  def test_the_display_location_is_never_an_absolute_path
    show = ->(location) { Folders::Operations.display_location(location, "/Users/someone") }

    assert_equal "~/Dropbox/Phius climate", show.call("/Users/someone/Dropbox/Phius climate")
    assert_equal "~", show.call("/Users/someone")
    assert_equal "Climate Drive/Phius/2022", show.call("/Volumes/Climate Drive/Phius/2022")
    assert_equal "Climate Drive", show.call("/Volumes/Climate Drive")
    assert_equal "…/Shared/Climate", show.call("/Users/Shared/Climate")
    assert_equal "…/someone2/Climate", show.call("/Users/someone2/Climate")
    assert_equal "…", show.call("/")
  end
end
