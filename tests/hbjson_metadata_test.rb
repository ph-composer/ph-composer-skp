# frozen_string_literal: true

require_relative "test_helper"

# The artifact guard parses a copy of the canonical HBJSON. `user_data` may hold only the keys export
# contributors declare; extension envelopes, usernames and paths refuse at any depth; the bytes
# written are the translator's own.
class HbjsonMetadataTest < PhComposerTestCase
  FIXTURE = File.join(TESTS_ROOT, "fixtures", "phase_one", "two_zones.hbjson")
  Privacy = PhComposer::Export::Privacy

  def test_the_review_reproduction_refuses
    hbjson = JSON.generate("type" => "Model", "username" => "private-user", "extension_data" => { "secret" => "x" })

    assert_equal "export.privacy_undeclared", refusal(hbjson)
  end

  def test_the_real_two_zone_translation_passes_and_its_bytes_are_unchanged
    hbjson = File.read(FIXTURE)
    before = hbjson.dup
    document = result(hbjson)

    assert Privacy.validate!(document)
    assert_equal before, document.dig("canonical_model", "hbjson")
  end

  def test_nested_or_undeclared_metadata_refuses_and_declared_metadata_passes
    declared = model("user_data" => { "ph_composer" => { "level" => "L1", "building_segment" => "House" } })
    nested = model("faces" => [{ "properties" => { "extension_data" => { "a" => 1 } } }])
    undeclared = model("user_data" => { "ph_composer" => { "level" => "L1", "secret" => "x" } })

    assert Privacy.validate!(result(declared))
    [nested, undeclared].each { |hbjson| assert_equal "export.privacy_undeclared", refusal(hbjson) }
    assert_match(/ph_composer\.secret/, refusal_message(undeclared))
  end

  # A user's own top-level key passes through uninterpreted, beside the declared ones; its strings and
  # keys are still checked like any other.
  def test_a_users_own_user_data_passes_but_paths_and_prohibited_keys_inside_it_still_refuse
    passed = model("user_data" => { "firm" => { "note" => "x", "count" => 2 },
                                    "ph_composer" => { "level" => "L1" } })
    local_path = model("user_data" => { "firm" => { "drawing" => "/Users/someone/plans/a.pdf" } })
    prohibited = model("user_data" => { "firm" => { "extension_data" => { "a" => 1 } } })

    assert Privacy.validate!(result(passed))
    assert_match(/local file path/, refusal_message(local_path))
    assert_match(/extension_data/, refusal_message(prohibited))
  end

  # A record part's metadata_omitted finding carries the reference records.update_metadata takes; the result
  # allowlist names it, and nothing else may ride inside it.
  def test_a_part_findings_reference_passes_the_result_allowlist
    document = result(File.read(FIXTURE))
    reference = { "kind" => "ph_composer.windows.window_type", "id" => "wnt_AAAAAAAAAAAA", "part_ids" => ["wel_1"] }
    document["findings"] << { "code" => "export.metadata_omitted", "section" => "s", "object_id" => "wel_1",
                              "message" => "m", "blocks_export" => false, "reference" => reference }

    assert Privacy.validate!(document)
    document["findings"].last["reference"]["extra"] = 1
    assert_equal "export.privacy_undeclared", assert_raises(PhComposer::CodedError) { Privacy.validate!(document) }.code
  end

  def test_a_local_path_used_as_a_user_data_key_refuses
    home = model("user_data" => { "firm" => { "~/private/model.skp" => true } })
    unc = model("user_data" => { "\\\\server\\share\\model.skp" => true })

    [home, unc].each { |hbjson| assert_match(/local file path as a key/, refusal_message(hbjson)) }
  end

  # The report's count reads the canonical HBJSON, so only objects that reached it are counted, and
  # an object carrying PH-Composer's own keys alone is not.
  def test_the_passed_count_reads_only_objects_that_carry_a_users_keys
    hbjson = JSON.generate("type" => "Model", "rooms" => [{
      "type" => "Room", "user_data" => { "ph_composer" => { "level" => "L1" }, "firm" => {} },
      "faces" => [{ "type" => "Face", "user_data" => { "firm" => { "a" => 1 } } },
                  { "type" => "Face", "user_data" => { "ph_composer" => { "level" => "x" } } },
                  { "type" => "Face" }]
    }])

    counts = PhComposer::Export::HbjsonMetadata.passed(hbjson, ["ph_composer.level"])

    assert_equal({ "Face" => 1, "Room" => 1 }, counts)
  end

  def test_a_literal_dotted_key_is_a_users_own_and_objects_inside_user_data_are_not_counted
    hbjson = model("type" => "Room", "user_data" => { "ph_composer.note" => "keep",
                                                      "firm" => { "type" => "Room", "user_data" => { "t" => 1 } } })

    assert Privacy.validate!(result(hbjson))
    assert_equal({ "Room" => 1 }, PhComposer::Export::HbjsonMetadata.passed(hbjson, ["ph_composer.level"]))
  end

  def test_a_contributor_that_declares_its_keys_needs_no_guard_change
    feature = Module.new do
      define_singleton_method(:install) do |registry|
        registry.feature("outside.tags", :contract_version => 1)
                .export_contributor("outside.tags.export", :section_version => 1,
                                                           :user_data_keys => ["outside.tag"]) { [] }
      end
    end
    PhComposer::Registry.install([feature])

    assert Privacy.validate!(result(model("user_data" => { "outside" => { "tag" => "north" } })))
  end

  def test_a_contributor_declaration_cannot_widen_after_registration
    keys = ["outside.tag"]
    feature = Module.new do
      define_singleton_method(:install) do |registry|
        registry.feature("outside.tags", :contract_version => 1)
                .export_contributor("outside.tags.export", :section_version => 1, :user_data_keys => keys) { [] }
      end
    end
    PhComposer::Registry.install([feature])
    keys << "outside.secret"

    assert_equal "export.privacy_undeclared", refusal(model("user_data" => { "outside" => { "secret" => "x" } }))
    assert PhComposer::Registry.current.export_contributors.fetch("outside.tags.export").user_data_keys.frozen?
  end

  def test_a_malformed_key_declaration_refuses_registration
    feature = Module.new do
      define_singleton_method(:install) do |registry|
        registry.feature("outside.tags", :contract_version => 1)
                .export_contributor("outside.tags.export", :section_version => 1,
                                                           :user_data_keys => ["Not A Key"]) { [] }
      end
    end

    error = assert_raises(PhComposer::RegistrationError) { PhComposer::Registry.install([feature]) }
    assert_equal ["registration.schema_invalid"], error.diagnostics.map(&:code)
  end

  def test_escaped_path_spellings_inside_the_hbjson_are_caught
    [model("display_name" => "C:\\Users\\someone\\model.skp"),
     JSON.generate("type" => "Model", "rooms" => [], "note" => "/Users/someone/model.skp").gsub("/", "\\/")]
      .each { |hbjson| assert_equal "export.privacy_undeclared", refusal(hbjson) }
  end

  # Keys are read as keys, not recovered from a path string, so dots or brackets cannot hide one.
  def test_keys_containing_dots_or_brackets_are_read_whole
    assert_equal "export.privacy_undeclared", refusal(model("username.primary" => "x"))
    assert_equal "export.privacy_undeclared", refusal(model("username[0]" => "x"))
    assert Privacy.validate!(result(model("a.username" => "x", "x.user_data" => "y")))
  end

  def test_an_empty_nested_map_declares_nothing
    assert Privacy.validate!(result(model("user_data" => { "ph_composer" => {} })))
  end

  def test_a_refusal_names_where_it_found_the_problem
    assert_match(/rooms\[0\]\.display_name/, refusal_message(model("display_name" => "/Attic")))
  end

  private

  def model(room)
    JSON.generate("type" => "Model", "rooms" => [{ "identifier" => "zon_AAAAAAAAAAAA" }.merge(room)])
  end

  def result(hbjson)
    {
      "schema_version" => 1, "run_id" => "run", "state" => "complete",
      "summary" => { "objects" => 1, "unavailable" => 0, "findings" => 0, "publishable" => true },
      "sections" => [], "findings" => [], "failure" => nil,
      "canonical_model" => { "hbjson" => hbjson, "rooms" => 1, "faces" => 0, "surface_pairs" => 0 }
    }
  end

  def refusal(hbjson)
    assert_raises(PhComposer::CodedError) { Privacy.validate!(result(hbjson)) }.code
  end

  def refusal_message(hbjson)
    assert_raises(PhComposer::CodedError) { Privacy.validate!(result(hbjson)) }.message
  end
end
