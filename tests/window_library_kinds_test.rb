# frozen_string_literal: true

require_relative "test_helper"
require_relative "support/window_record_fixtures"
require_relative "support/library_provider_fixtures"

class WindowLibraryKindsTest < PhComposerTestCase
  include WindowRecordFixtures
  include LibraryProviderFixtures

  API = PhComposer::API
  L = "ph_composer.library"

  def setup
    super
    @model = Sketchup.active_model
    @session = PhComposer::Sessions.for(@model)
    @context = API.connect(:session_id => @session.id, :capabilities => %w[read view model_write setup])
    @sequence = 0
    @directory = Dir.mktmpdir("window-libraries")
    @path = File.join(@directory, "synthetic.json")
    @rows = W::Products::KINDS.keys.to_h do |collection|
      row = W::Products.defaults(collection, "name" => "Synthetic #{collection}")
      row.delete("source")
      W::Products.number_keys(collection).each { |key| row[key] = key.start_with?("psi") ? -0.01 : 0.25 }
      [collection, row.merge("id" => "public-#{collection}")]
    end
    write_library(@path, envelope(:kinds => @rows.transform_values { |row| [row] }).merge(
      "kind_schema_versions" => @rows.to_h { |kind, _row| [kind, 1] }
    ))
    PhComposer::Library::Setup.add_file(:id => "synthetic.windows", :label => "Synthetic", :path => @path)
    @generations = @rows.to_h do |collection, _row|
      loaded = API.setup(:context => @context, :name => "#{L}.load",
                         :params => { "provider_id" => "synthetic.windows", "kind" => collection })
      [collection, loaded.dig("value", "generation")]
    end
  end

  def teardown
    FileUtils.rm_rf(@directory)
    super
  end

  def adapter(collection)
    PhComposer::Library::State.kind(collection, PhComposer::Registry.current).adapter
  end

  def copy_params(collection, choice = "create")
    { "provider_id" => "synthetic.windows", "kind" => collection, "generation" => @generations[collection],
      "library_id" => "synthetic.one", "record_id" => @rows.fetch(collection).fetch("id"), "choice" => choice }
  end

  # What a copy of `collection`'s library row would resolve to, read without proposing anything.
  def resolution(collection)
    page = API.query(:context => @context, :name => "#{L}.in_file",
                     :params => copy_params(collection).slice("provider_id", "kind", "generation"))
    page.dig("value", "rows").find { |row| row.fetch("record_id") == @rows.fetch(collection).fetch("id") }
        .fetch("resolution")
  end

  def invoke(name, params)
    @sequence += 1
    API.invoke(:context => @context, :name => name, :params => params,
               :request => { "sequence" => @sequence, "expected_revision" => @session.revision })
  end

  def stored(collection, id)
    W::Products::KINDS.fetch(collection).store.read(@model, id)
  end

  def test_each_adapter_is_closed_si_and_semantic_roundtrip_is_detached
    @rows.each do |collection, wire|
      a = adapter(collection)
      assert_equal [1, 1], [a.wire_version, a.fingerprint_version]
      assert_empty PhComposer::JsonSchema.validate(wire, a.wire_schema)
      mapped = a.map.call(wire.merge("source" => { "secret" => "private" }, "user_data" => { "private" => true }))
      assert_empty PhComposer::JsonSchema.validate(mapped, a.mapped_schema)
      assert_equal mapped, a.map.call(a.reverse.call(mapped.merge("id" => "local-id")))
      assert_equal a.fingerprint.call(mapped), a.fingerprint.call(mapped.merge("id" => "other", "source" => {}))
      refute_includes a.fingerprint_fields, "source"
      mapped["datasheet_links"] << "mutated"
      assert_empty wire["datasheet_links"]
      assert_equal "m", a.wire_schema.dig("properties", "width_m", "x-unit") if collection == "frames"
      assert_equal "fraction", a.wire_schema.dig("properties", "g_value", "x-unit") if collection == "glazings"
      assert_equal "W/mK", a.wire_schema.dig("properties", "psi_w_mk", "x-unit") if collection == "psi_install_types"
    end
  end

  def test_a_frame_row_without_a_brand_maps_to_an_empty_one
    wire = @rows.fetch("frames").reject { |key, _| key == "brand" }
    assert_equal "", adapter("frames").map.call(wire).fetch("brand")
    assert_equal "Line", adapter("frames").map.call(wire.merge("brand" => "Line")).fetch("brand")
    refute W::Products::KINDS.fetch("glazings").values_schema["properties"].key?("brand")
  end

  def test_shared_copy_create_retry_source_reuse_and_reviewed_replacement_for_every_kind
    @rows.each_key do |collection|
      input = copy_params(collection)
      preview = API.preview(:context => @context, :name => "#{L}.copy", :params => input)
      assert_equal "completed", preview["status"], preview.inspect
      @sequence += 1
      request = { "sequence" => @sequence, "expected_revision" => @session.revision,
                  "proposal_digest" => preview.fetch("proposal_digest") }
      result = API.invoke(:context => @context, :name => "#{L}.copy", :params => input, :request => request)
      assert_equal "committed", result["effect"], result.inspect
      assert_equal result, API.invoke(:context => @context, :name => "#{L}.copy", :params => input, :request => request)
      id = result.dig("value", "local_id")
      before = stored(collection, id)
      assert_equal collection, before.dig("source", "record_kind")
      refute before.dig("source", "snapshot").key?("id")
      refute_includes JSON.generate(before), @directory
      edited = before.merge("name" => "Edited #{collection}", "notes" => "local edits",
                            "user_data" => { "fixture" => ["retain"] },
                            "extension_data" => { "fixture.unknown" => { "schema_version" => 8,
                                                                         "payload" => { "retain" => true } } })
      W::Products::KINDS.fetch(collection).store.write(@model, edited)
      reused = invoke("#{L}.copy", copy_params(collection, "keep_local"))
      assert_equal id, reused.dig("value", "local_id")
      assert_equal "none", reused["effect"]
      candidate = resolution(collection).dig("candidates", 0)
      assert_equal false, candidate["source_changed"]
      replaced = invoke("#{L}.copy", copy_params(collection, "use_library").merge(
        "expected_values" => candidate.fetch("expected_values")
      ))
      assert_equal "committed", replaced["effect"], replaced.inspect
      assert_equal before.fetch("name"), stored(collection, id).fetch("name")
      assert_equal edited.fetch("user_data"), stored(collection, id).fetch("user_data")
      assert_equal edited.fetch("extension_data"), stored(collection, id).fetch("extension_data")
    end
  end

  def test_copy_and_assignment_change_only_chosen_frame_side_glazing_or_psi_edge
    %w[frames glazings psi_install_types].each do |collection|
      type = window_values("name" => "Type #{collection}")
      id = invoke("#{W::FEATURE_ID}.types.create", "values" => type).dig("value", "id")
      before = W::Types::KIND.store.read(@model, id)
      target = { "id" => id, "element_id" => before.fetch("elements").first.fetch("id"),
                 "expected_values" => W::Types::KIND.values(before) }
      target["side"] = "left" unless collection == "glazings"
      target.merge!("mode" => "perimeter",
                    "expected_settings" => W::Settings.read(@model)) if collection == "psi_install_types"
      revision = @session.revision
      result = invoke("#{L}.copy", copy_params(collection).merge("assignment" => target))
      assert_equal "committed", result["effect"], result.inspect
      assert_equal true, result.dig("value", "assigned")
      assert_equal revision + 1, @session.revision
      after = PhComposer::DeepCopy.call(before)
      element = after.fetch("elements").first
      case collection
      when "frames" then element.fetch("frames")["left"] = result.dig("value", "local_id")
      when "glazings" then element["glazing_id"] = result.dig("value", "local_id")
      else element.fetch("installs")["left"] = result.dig("value", "local_id")
      end
      assert_equal after, W::Types::KIND.store.read(@model, id)
    end
  end

  def test_stale_assignment_refuses_copy_for_every_kind
    @rows.each_key do |collection|
      target = { "id" => "missing", "element_id" => "missing", "expected_values" => {} }
      target["side"] = "top" unless collection == "glazings"
      target.merge!("mode" => "perimeter",
                    "expected_settings" => W::Settings.read(@model)) if collection == "psi_install_types"
      result = invoke("#{L}.copy", copy_params(collection).merge("assignment" => target))
      assert_equal "refused", result["status"], result.inspect
      assert_empty W::Products::KINDS.fetch(collection).store.ids(@model)
    end
  end

  def type_target(collection)
    id = invoke("#{W::FEATURE_ID}.types.create", "values" => { "name" => "#{collection} target" }).dig("value", "id")
    record = W::Types::KIND.store.read(@model, id)
    target = { "id" => id, "element_id" => record.fetch("elements").first.fetch("id"),
               "expected_values" => W::Types::KIND.values(record) }
    target["side"] = "top" unless collection == "glazings"
    if collection == "psi_install_types"
      target.merge!("mode" => "perimeter", "expected_settings" => W::Settings.read(@model))
    end
    [record, target]
  end

  def test_native_write_failure_rolls_back_product_and_each_assignment
    @rows.each_key do |collection|
      before, target = type_target(collection)
      store = W::Types::KIND.store
      writing = store.method(:write)
      store.define_singleton_method(:write) { |*_args| raise PhComposer::InternalError, "Injected type write." }
      begin
        failed = invoke("#{L}.copy", copy_params(collection).merge("assignment" => target))
        assert_equal %w[failed operation.failed rolled_back], failed.values_at("status", "code", "effect"),
                     failed.inspect
        assert_equal before, store.read(@model, before.fetch("id"))
        assert_empty W::Products::KINDS.fetch(collection).store.ids(@model)
      ensure
        store.define_singleton_method(:write, writing)
      end
    end
  end

  def test_psi_default_assignment_and_late_product_failure_restore_settings
    input = copy_params("psi_install_types").merge("assignment" => {
      "mode" => "model_default", "expected_settings" => W::Settings.read(@model)
    })
    store = W::Products::KINDS.fetch("psi_install_types").store
    writing = store.method(:write)
    store.define_singleton_method(:write) { |*_args| raise PhComposer::InternalError, "Injected product write." }
    begin
      failed = invoke("#{L}.copy", input)
      assert_equal %w[failed operation.failed rolled_back], failed.values_at("status", "code", "effect"), failed.inspect
      assert_equal W::Settings::DEFAULTS, W::Settings.read(@model)
      assert_empty store.ids(@model)
    ensure
      store.define_singleton_method(:write, writing)
    end
    saved = invoke("#{L}.copy", input)
    assert_equal "committed", saved["effect"], saved.inspect
    assert_equal saved.dig("value", "local_id"), W::Settings.read(@model).fetch("default_psi_install_id")
    assert_equal 0.0, W::Settings.read(@model).fetch("default_install_depth_m")
    stale = invoke("#{L}.copy",
                   copy_params("psi_install_types", "keep_local").merge("assignment" => input["assignment"]))
    assert_equal "target.changed", stale["code"]
  end

  def imports_params
    before, target = type_target("imports")
    { "types" => [{ "id" => before.fetch("id"), "expected_values" => target.fetch("expected_values"),
                    "installs" => [{ "element_id" => target.fetch("element_id"),
                                     "sides" => W::Types::SIDES.to_h { |side| [side, "draft:import"] } }] }],
      "psi_install_types" => { "create" => [], "update" => [] },
      "expected_settings" => W::Settings.read(@model),
      "imports" => [{ "client_id" => "draft:import", "copy" => copy_params("psi_install_types") }] }
  end

  def test_staged_imports_preview_and_save_share_one_guarded_copy_and_trusted_provenance
    input = imports_params
    preview = API.preview(:context => @context, :name => "#{W::FEATURE_ID}.types.installs.save", :params => input)
    assert_equal "completed", preview["status"], preview.inspect
    assert_empty W::Products::KINDS.fetch("psi_install_types").store.ids(@model)
    revision = @session.revision
    @sequence += 1
    result = API.invoke(:context => @context, :name => "#{W::FEATURE_ID}.types.installs.save", :params => input,
                        :request => { "sequence" => @sequence, "expected_revision" => revision,
                                      "proposal_digest" => preview.fetch("proposal_digest") })
    assert_equal "committed", result["effect"], result.inspect
    assert_equal revision + 1, @session.revision
    id = result.dig("value", "psi_install_type_ids", "draft:import")
    assert_equal [id], W::Types::KIND.store.read(@model, input["types"].first["id"])
                                     .fetch("elements").first.fetch("installs").values.uniq
    source = stored("psi_install_types", id).fetch("source")
    assert_equal "public-psi_install_types", source.fetch("record_id")
    assert_equal "ph_composer.library.file", source.fetch("provider_kind")
    assert_equal @rows["psi_install_types"].reject { |key, _value| key == "id" }, source.fetch("snapshot")
  end

  def test_staged_import_and_all_previous_writes_roll_back_when_last_type_guard_is_stale
    input = imports_params
    second, _target = type_target("last imports")
    input["types"] << { "id" => second.fetch("id"), "expected_values" => { "name" => "stale" }, "installs" => [] }
    first_before = W::Types::KIND.store.read(@model, input["types"].first["id"])
    result = invoke("#{W::FEATURE_ID}.types.installs.save", input)
    assert_equal "target.changed", result["code"], result.inspect
    assert_empty W::Products::KINDS.fetch("psi_install_types").store.ids(@model)
    assert_equal first_before, W::Types::KIND.store.read(@model, first_before["id"])
    assert_equal second, W::Types::KIND.store.read(@model, second["id"])
  end

  def test_imports_refuse_duplicate_tokens_stale_catalog_and_smuggled_assignment
    input = imports_params
    input["psi_install_types"]["create"] << { "client_id" => "draft:import", "values" => { "name" => "Manual" } }
    assert_equal "params.invalid", invoke("#{W::FEATURE_ID}.types.installs.save", input)["code"]
    input["psi_install_types"]["create"] = []
    input["imports"][0]["copy"]["assignment"] = {}
    assert_equal "params.invalid", invoke("#{W::FEATURE_ID}.types.installs.save", input)["code"]
    input["imports"][0]["copy"].delete("assignment")
    API.setup(:context => @context, :name => "#{L}.load", :params => { "provider_id" => "synthetic.windows",
                                                                       "kind" => "psi_install_types" })
    assert_equal "library.catalog_stale", invoke("#{W::FEATURE_ID}.types.installs.save", input)["code"]
    assert_empty W::Products::KINDS.fetch("psi_install_types").store.ids(@model)
  end

  def test_public_export_file_provider_and_copy_into_fresh_model_preserve_semantics_all_three_kinds
    originals = @rows.to_h do |collection, _row|
      copied = invoke("#{L}.copy", copy_params(collection))
      id = copied.dig("value", "local_id")
      [collection, stored(collection, id)]
    end
    export_path = File.join(@directory, "export.json")
    export_context = API.connect(:session_id => @session.id, :capabilities => %w[read export model_write view])
    approval = PhComposer::NativeApproval::Granted.new(:path => export_path, :replace => false)
    result = PhComposer::Dispatch.new.file_export(export_context, "#{L}.export_file", { "kinds" => @rows.keys },
                                                  :approval => approval)
    assert_equal "completed", result["status"], result.inspect
    exported = JSON.parse(File.read(export_path))
    assert_equal @rows.keys.sort, exported.fetch("kinds").keys.sort
    @model = Sketchup::Model.new
    Sketchup.active_model = @model
    @session = PhComposer::Sessions.for(@model)
    @context = API.connect(:session_id => @session.id, :capabilities => %w[read view model_write setup])
    @sequence = 0
    PhComposer::Library::Setup.add_file(:id => "synthetic.windows", :label => "Roundtrip", :path => export_path)
    @rows.each_key do |collection|
      loaded = API.setup(:context => @context, :name => "#{L}.load", :params => { "provider_id" => "synthetic.windows",
                                                                                  "kind" => collection })
      assert_equal "loaded", loaded.dig("value", "state"), loaded.inspect
      assert_empty loaded.dig("value", "warnings")
      input = copy_params(collection).merge("generation" => loaded.dig("value", "generation"),
                                            "library_id" => exported.dig("library", "id"),
                                            "record_id" => originals[collection].fetch("id"))
      result = invoke("#{L}.copy", input)
      assert_equal "committed", result["effect"], result.inspect
      id = result.dig("value", "local_id")
      refute_equal originals[collection]["id"], id
      assert_equal adapter(collection).map.call(originals[collection]),
                   adapter(collection).map.call(stored(collection, id))
    end
  end

  def test_name_review_source_ambiguity_and_changed_provider_content_use_shared_resolution_for_every_kind
    @rows.each_key do |collection|
      a = adapter(collection)
      manual = invoke("#{W::FEATURE_ID}.#{collection}.create", "values" => a.map.call(@rows[collection]))
      id = manual.dig("value", "id")
      assert_equal "reuse", resolution(collection).fetch("outcome")
      before = stored(collection, id)
      edited = before.merge("notes" => "Differing manual content")
      W::Products::KINDS.fetch(collection).store.write(@model, edited)
      inspected = resolution(collection)
      assert_equal "review_required", inspected.fetch("outcome")
      expected = inspected.dig("candidates", 0, "expected_values")
      replaced = invoke("#{L}.copy", copy_params(collection, "use_library").merge("expected_values" => expected))
      assert_equal "committed", replaced["effect"], replaced.inspect
      second = stored(collection, id).merge("id" => PhComposer::Records::Identity.mint(
        W::Products::KINDS.fetch(collection).id_prefix
      ), "name" => "Second #{collection}")
      W::Products::KINDS.fetch(collection).store.write(@model, second)
      assert_equal "ambiguous_source", resolution(collection).fetch("outcome")
      refused = invoke("#{L}.copy", copy_params(collection, "keep_local"))
      assert_equal "library.local_choice_required", refused["code"]
      W::Products::KINDS.fetch(collection).store.delete(@model, second.fetch("id"))
      @rows[collection]["notes"] = "Changed provider content"
      write_library(@path, envelope(:kinds => @rows.transform_values { |row| [row] }).merge(
        "kind_schema_versions" => @rows.to_h { |kind, _row| [kind, 1] }
      ))
      loaded = API.setup(:context => @context, :name => "#{L}.load", :params => {
        "provider_id" => "synthetic.windows", "kind" => collection
      })
      @generations[collection] = loaded.dig("value", "generation")
      candidate = resolution(collection).dig("candidates", 0)
      assert_equal true, candidate["source_changed"]
      replaced = invoke("#{L}.copy", copy_params(collection, "use_library").merge(
        "expected_values" => candidate.fetch("expected_values")
      ))
      assert_equal "committed", replaced["effect"], replaced.inspect
      assert_equal id, replaced.dig("value", "local_id")
      assert_equal "Changed provider content", stored(collection, id).fetch("notes")
    end
  end

  def test_zero_signed_and_missing_numeric_values_and_invalid_colors
    @rows.each_key do |collection|
      a = adapter(collection)
      absent = a.map.call("name" => "Absent")
      W::Products.number_keys(collection).each { |key| assert_nil absent.fetch(key) }
      zero = @rows[collection].merge(W::Products.number_keys(collection).to_h { |key| [key, 0] })
      normalized = a.map.call(zero)
      assert_equal a.fingerprint.call(zero), a.fingerprint.call(normalized)
      assert_equal [], PhComposer::JsonSchema.validate(normalized, a.mapped_schema)
      next if collection == "psi_install_types"

      error = assert_raises(PhComposer::CodedError) { a.map.call(@rows[collection].merge("color" => "invalid")) }
      assert_equal "library.row_semantic_invalid", error.code
      assert_equal "#abcdef", a.map.call(@rows[collection].merge("color" => "#ABCDEF"))["color"]
    end
  end
end
