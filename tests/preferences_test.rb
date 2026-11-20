# frozen_string_literal: true

require_relative "test_helper"

# The display preference store: what it reads back, what it refuses, and how it survives values it did
# not write. The panel's message handling is in panel_test.rb.
class PreferencesTest < PhComposerTestCase
  Preferences = PhComposer::Preferences
  SECTION = Preferences::SECTION

  def test_first_use_is_si_with_no_remembered_scope
    snapshot = Preferences.snapshot

    assert_equal "SI", snapshot.fetch("unit_system")
    assert_equal({}, snapshot.fetch("dimension_formats"))
    assert_equal({ "decimal" => ".", "locale" => "en-US" }, snapshot.fetch("number_format"))
  end

  def test_each_scope_remembers_its_si_and_ip_formats_separately
    Preferences.set("dimension_format", "cm", :scope => "example.editor", :system => "SI")
    Preferences.set("dimension_format", "ft-in", :scope => "example.editor", :system => "IP")
    Preferences.set("dimension_format", "m", :scope => "example.builder", :system => "SI")

    assert_equal({ "example.editor" => { "SI" => "cm", "IP" => "ft-in" },
                   "example.builder" => { "SI" => "m", "IP" => "in" } }, Preferences.dimension_formats)
  end

  # SketchUp 26.1 reads back nil for a stored string holding a double quote; the stub does the same.
  def test_the_remembered_formats_survive_the_hosts_quote_handling
    Preferences.set("dimension_format", "in-frac", :scope => "example.editor", :system => "IP")

    stored = Sketchup.read_default(SECTION, "dimension_formats")
    refute_nil stored
    refute_includes stored, '"'
  end

  def test_values_the_store_did_not_write_read_as_defaults
    Sketchup.write_default(SECTION, "unit_system", "metric")
    formats = { "example.editor" => { "SI" => "in", "IP" => "yards" }, "Not A Scope" => { "SI" => "cm" } }
    Sketchup.write_default(SECTION, "dimension_formats", [JSON.generate(formats)].pack("m0"))

    assert_equal "SI", Preferences.unit_system
    assert_equal({ "example.editor" => { "SI" => "mm", "IP" => "in" } }, Preferences.dimension_formats)
    Sketchup.write_default(SECTION, "dimension_formats", "not base64 json")
    assert_equal({}, Preferences.dimension_formats)
  end

  def test_a_bad_scope_or_too_many_scopes_are_refused_without_writing
    error = assert_raises(PhComposer::UserError) do
      Preferences.set("dimension_format", "mm", :scope => "Editor", :system => "SI")
    end
    assert_equal "The dimension scope name is not valid.", error.message

    Preferences::MAX_SCOPES.times do |index|
      Preferences.set("dimension_format", "cm", :scope => "example.scope_#{index}", :system => "SI")
    end
    Sketchup.clear_default_writes
    assert_raises(PhComposer::UserError) do
      Preferences.set("dimension_format", "cm", :scope => "example.one_more", :system => "SI")
    end
    assert_empty Sketchup.instance_variable_get(:@default_writes)
    Preferences.set("dimension_format", "m", :scope => "example.scope_0", :system => "SI")
    assert_equal "m", Preferences.dimension_formats.dig("example.scope_0", "SI"), "a known scope still changes"
  end

  def test_each_host_table_remembers_its_last_view_and_refuses_a_bad_name
    assert_equal({}, Preferences.snapshot.fetch("table_views"))
    Preferences.set("table_view", "example.zones.areas", :scope => "example.zones")
    Preferences.set("table_view", "example.other.view", :scope => "example.other")
    Preferences.set("table_view", "example.zones.faces", :scope => "example.zones")

    assert_equal({ "example.zones" => "example.zones.faces", "example.other" => "example.other.view" },
                 Preferences.snapshot.fetch("table_views"))
    assert_raises(PhComposer::UserError) { Preferences.set("table_view", "Faces", :scope => "example.zones") }
    assert_raises(PhComposer::UserError) { Preferences.set("table_view", "example.zones.faces", :scope => nil) }
    Sketchup.write_default(SECTION, "table_views", [JSON.generate("example.zones" => 3, "Bad" => "x.y")].pack("m0"))
    assert_equal({}, Preferences.table_views)
  end

  # REVIEW F06: a stubbed write_default returning false still returned the value as saved.
  def test_a_write_the_host_refuses_is_reported_as_not_saved
    Sketchup.refuse_default_writes = true

    error = assert_raises(PhComposer::UserError) { Preferences.set("unit_system", "IP") }
    assert_equal "PH-Composer could not save that display preference.", error.message
    assert_raises(PhComposer::UserError) do
      Preferences.set("dimension_format", "cm", :scope => "example.editor", :system => "SI")
    end
    assert_equal "SI", Preferences.unit_system
  end

  def test_a_write_the_host_accepts_but_does_not_read_back_is_not_saved
    Sketchup.refuse_default_writes = :silently

    assert_raises(PhComposer::UserError) { Preferences.set("unit_system", "IP") }
    assert_raises(PhComposer::UserError) do
      Preferences.set("table_view", "example.zones.faces", :scope => "example.zones")
    end
  end

  def test_a_stored_map_it_cannot_read_is_left_unchanged
    # Damaged, and a string the host stores but reads back as nil.
    { "table_views" => "not base64 json", "dimension_formats" => 'held "quoted"' }.each do |key, damaged|
      Sketchup.write_default(SECTION, key, damaged)
    end
    Sketchup.clear_default_writes

    error = assert_raises(PhComposer::UserError) do
      Preferences.set("table_view", "example.zones.faces", :scope => "example.zones")
    end
    assert_equal "Your saved display preferences could not be read, so they were left unchanged.", error.message
    assert_raises(PhComposer::UserError) do
      Preferences.set("dimension_format", "cm", :scope => "example.editor", :system => "SI")
    end
    assert_empty Sketchup.default_writes
    assert_equal "not base64 json", Sketchup.read_default(SECTION, "table_views")
  end

  def test_a_scope_entry_it_cannot_read_is_left_unchanged
    stored = [JSON.generate("example.editor" => %w[cm ft-in])].pack("m0")
    Sketchup.write_default(SECTION, "dimension_formats", stored)
    Sketchup.clear_default_writes

    assert_raises(PhComposer::UserError) do
      Preferences.set("dimension_format", "m", :scope => "example.editor", :system => "SI")
    end
    assert_empty Sketchup.default_writes
    assert_equal stored, Sketchup.read_default(SECTION, "dimension_formats")
  end

  # A later version may keep more scopes than this one reads; changing one would save what is never shown.
  def test_a_map_with_more_scopes_than_it_reads_is_refused_without_writing
    many = (0..Preferences::MAX_SCOPES).to_h { |index| ["example.scope_#{index}", "example.view"] }
    Sketchup.write_default(SECTION, "table_views", [JSON.generate(many)].pack("m0"))
    Sketchup.clear_default_writes

    assert_raises(PhComposer::UserError) do
      Preferences.set("table_view", "example.other", :scope => "example.scope_#{Preferences::MAX_SCOPES}")
    end
    assert_empty Sketchup.default_writes
  end

  # Preserved entries can fill the store; a map the readers would refuse is never written.
  def test_a_map_too_large_to_read_back_is_refused_without_writing
    later = (1..Preferences::MAX_SCOPES - 1).to_h { |index| ["example.scope_#{index}", "x" * 176] }
    Sketchup.write_default(SECTION, "table_views", [JSON.generate(later)].pack("m0"))
    assert_operator Sketchup.read_default(SECTION, "table_views").bytesize, :<=, Preferences::MAX_ENCODED_BYTES
    Sketchup.clear_default_writes

    error = assert_raises(PhComposer::UserError) do
      Preferences.set("table_view", "example.zones.faces", :scope => "example.zones")
    end
    assert_equal "Too many display preferences are remembered.", error.message
    assert_empty Sketchup.default_writes
  end

  # A later version's entry this one does not recognize survives a change to another scope.
  def test_changing_one_scope_keeps_entries_this_version_does_not_recognize
    later = { "example.editor" => { "SI" => "dm", "IP" => "yd" } }
    Sketchup.write_default(SECTION, "dimension_formats", [JSON.generate(later)].pack("m0"))

    Preferences.set("dimension_format", "cm", :scope => "example.builder", :system => "SI")

    stored = JSON.parse(Sketchup.read_default(SECTION, "dimension_formats").unpack1("m0"))
    assert_equal({ "SI" => "dm", "IP" => "yd" }, stored.fetch("example.editor"))
    assert_equal({ "SI" => "cm", "IP" => "in" }, stored.fetch("example.builder"))
  end

  def test_reset_returns_every_display_preference_to_its_default_even_when_unreadable
    Preferences.set("unit_system", "IP")
    Preferences.set("table_view", "example.zones.faces", :scope => "example.zones")
    Preferences.set("colour_by_mode", "example.mode")
    Sketchup.write_default(SECTION, "dimension_formats", "not base64 json")
    Sketchup.write_default(PhComposer::EXTENSION_ID, "library_setup", "kept")

    assert_equal Preferences::RESETTABLE, Preferences.reset_display

    assert_equal({ "unit_system" => "SI", "dimension_formats" => {}, "table_views" => {} },
                 Preferences.snapshot.slice("unit_system", "dimension_formats", "table_views"))
    assert_nil Preferences.colour_by_mode
    assert_equal "kept", Sketchup.read_default(PhComposer::EXTENSION_ID, "library_setup"), "other stores stay"
    Preferences.set("dimension_format", "cm", :scope => "example.editor", :system => "SI")
  end

  # A units subscriber hears each units write and nothing else; one that raises is logged and the change
  # stands for the rest; an unsubscribed one hears nothing more.
  def test_a_units_change_reaches_each_subscriber_and_a_raising_one_does_not_undo_it
    heard = []
    Preferences.on_units_change { raise "the repaint failed" }
    unsubscribe = Preferences.on_units_change { heard << Preferences.unit_system }

    Preferences.set("unit_system", "IP")
    Preferences.set("table_view", "example.zones.faces", :scope => "example.zones")
    Preferences.reset_display
    unsubscribe.call
    Preferences.set("unit_system", "IP")

    assert_equal %w[IP SI], heard
    assert_equal "IP", Preferences.unit_system
  end

  def test_the_regional_format_takes_the_macos_region_and_the_sketchup_decimal
    Sketchup::RegionalSettings.decimal_separator = ","
    Preferences.apple_locale_reader = proc { "de_DE" }
    assert_equal({ "decimal" => ",", "locale" => "de-DE" }, Preferences.snapshot.fetch("number_format"))

    PhComposer::Preferences.reset_for_test
    Preferences.apple_locale_reader = proc { "en_US@rg=chzzzz" }
    assert_equal "en-CH", Preferences.snapshot.dig("number_format", "locale"), "a chosen region replaces the language's"
  end

  def test_the_regional_format_falls_back_to_sketchups_locale_and_is_read_once
    reads = 0
    Sketchup.locale_value = "fr-FR"
    Preferences.apple_locale_reader = proc {
      reads += 1
      raise IOError, "defaults unavailable"
    }

    assert_equal "fr-FR", Preferences.snapshot.dig("number_format", "locale")
    assert_equal "fr-FR", Preferences.snapshot.dig("number_format", "locale")
    assert_equal 1, reads
  end
end
