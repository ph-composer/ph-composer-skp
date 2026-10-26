# frozen_string_literal: true

require_relative "test_helper"
require_relative "support/window_record_fixtures"

class WindowRecordsOperationsTest < PhComposerTestCase
  include WindowRecordFixtures

  API = PhComposer::API

  def setup
    super
    PhComposer::Registry.install([W]) unless PhComposer::Registry.installed?(W::FEATURE_ID)
    @model = Sketchup.active_model
    @session = PhComposer::Sessions.for(@model)
    @context = API.connect(:session_id => @session.id)
    @sequence = 0
  end

  def test_every_operation_and_reference_has_a_valid_declared_schema_and_example
    registry = PhComposer::Registry.current
    assert_equal ["ph_composer.zones", "ph_composer.library"], registry.features.fetch(W::FEATURE_ID).requires
    declarations = (registry.queries.values + registry.actions.values + registry.view_commands.values)
                   .select { |entry| entry.owner == W::FEATURE_ID }
    assert_equal 58, declarations.length
    declarations.each do |entry|
      assert_empty PhComposer::JsonSchema.schema_problems(entry.params), entry.name
      assert_empty PhComposer::JsonSchema.schema_problems(entry.result), entry.name
      refute_empty entry.examples, entry.name
      entry.examples.each { |example| assert_empty PhComposer::JsonSchema.validate(example, entry.params), entry.name }
    end
  end

  def test_defaults_work_in_a_model_with_no_zone_and_ip_dimensions_are_exact
    assert_empty @model.entities.to_a
    id = create("types", "name" => "Default")
    values = row("types", id).fetch("values")
    assert_equal [1.5], values["rows_m"]
    assert_equal [1.0], values["columns_m"]
    assert_nil row("types", id).dig("display", "thermal", "uw_w_m2k")
    refute values.key?("install_depth_m")
    # The same call authors the same values whatever the display system; a client that wants the round
    # imperial start passes it.
    PhComposer::Preferences.stub(:unit_system, "IP") do
      ip = create("types", "name" => "IP")
      assert_equal [[1.5], [1.0]], row("types", ip).fetch("values").values_at("rows_m", "columns_m")
    end
    sized = create("types", "name" => "Sized", "rows_m" => [1.524], "columns_m" => [1.016])
    assert_equal [[1.524], [1.016]], row("types", sized).fetch("values").values_at("rows_m", "columns_m")
    assert_equal({ "default_psi_install_id" => nil, "default_install_depth_m" => 0.0 }, settings)
  end

  def test_stale_update_noop_metadata_and_duplicate_nested_identity_rules
    id = create("types", "name" => "Original", "product_photos" => ["photo"], "install_depth_m" => 0.15)
    kind = W::Types::KIND
    record = stored(kind, id)
    record["user_data"] = { "fixture" => { "notes" => ["kept"] } }
    kind.store.write(@model, record)
    refused = invoke("types.update", "id" => id, "values" => { "name" => "Edited" },
                                     "expected_values" => { "name" => "stale" })
    assert_equal %w[refused target.changed none], refused.values_at("status", "code", "effect")
    no_op = invoke("types.update", "id" => id, "values" => { "name" => "Original" },
                                   "expected_values" => { "name" => "Original" })
    assert_equal "none", no_op["effect"]
    copy_id = preview_invoke("types.duplicate", "id" => id).dig("value", "id")
    copy = stored(kind, copy_id)
    refute_equal record["elements"][0]["id"], copy["elements"][0]["id"]
    assert_equal 0.15, copy["install_depth_m"]
    assert_empty copy["product_photos"]
    assert_equal record["user_data"], copy["user_data"]
    copy["user_data"]["fixture"]["notes"] << "changed"
    assert_equal ["kept"], stored(kind, id).dig("user_data", "fixture", "notes")
    payload = { "schema_version" => 9, "payload" => { "notes" => ["opaque"] },
                "references" => [], "export_relevance" => "required" }
    kind.store.write(@model, record.merge("extension_data" => { "fixture.unknown" => payload }))
    edit = invoke("types.update", "id" => id, "values" => { "notes" => "Edited" },
                                  "expected_values" => { "notes" => "" })
    assert_equal "committed", edit["effect"]
    assert_equal payload, stored(kind, id).dig("extension_data", "fixture.unknown")
    assert_equal "copy.rule_missing", invoke("types.duplicate", "id" => id)["code"]
  end

  def test_product_replacement_all_slots_model_default_undo_and_rollback
    first = create("psi_install_types", "name" => "Original", "psi_w_mk" => 0.04)
    second = create("psi_install_types", "name" => "Replacement", "psi_w_mk" => 0.03)
    ids = 2.times.map do |index|
      values = window_values("name" => "Type #{index}")
      values["elements"][0]["installs"] = W::Types::SIDES.to_h { |side| [side, first] }
      create("types", values)
    end
    set_settings("default_psi_install_id" => first, "default_install_depth_m" => 0.2)
    originals = ids.map { |id| stored(W::Types::KIND, id) }
    assert_equal "reference.in_use", invoke("psi_install_types.delete", "id" => first)["code"]
    usage = row("psi_install_types", first)
    assert_equal 9, usage["use_count"]
    result = invoke("psi_install_types.delete", "id" => first, "replacement_id" => second)
    assert_equal "committed", result["effect"], result.inspect
    assert_equal second, settings["default_psi_install_id"]
    ids.each { |id| assert_equal [second], stored(W::Types::KIND, id)["elements"][0]["installs"].values.uniq }
    @model.undo
    assert_equal originals, ids.map { |id| stored(W::Types::KIND, id) }
    assert_equal first, settings["default_psi_install_id"]
    store = W::Products::KINDS.fetch("psi_install_types").store
    deletion = store.method(:delete)
    store.define_singleton_method(:delete) { |_model, _id| raise PhComposer::InternalError, "Injected." }
    failure = invoke("psi_install_types.delete", "id" => first, "replacement_id" => second)
    assert_equal %w[failed operation.failed rolled_back], failure.values_at("status", "code", "effect")
    assert_equal originals, ids.map { |id| stored(W::Types::KIND, id) }
    assert_equal first, settings["default_psi_install_id"]
  ensure
    store&.define_singleton_method(:delete, deletion) if deletion
  end

  def test_grid_preview_digest_ids_and_invalid_gestures_do_not_mutate
    id = preview_invoke("types.create", "values" => { "name" => "Grid" }).dig("value", "id")
    original = row("types", id)["values"]
    preview_invoke("types.grid.insert", "id" => id, "axis" => "columns_m", "index" => 1,
                                        "value" => 1.0, "expected_values" => original)
    after = row("types", id)["values"]
    ids = after["elements"].map { |element| element["id"] }
    assert_equal 2, ids.uniq.length
    preview_invoke("types.grid.merge", "id" => id, "ids" => ids, "expected_values" => after)
    merged = row("types", id)["values"]
    preview_invoke("types.grid.split", "id" => id, "element_id" => merged["elements"][0]["id"],
                                       "expected_values" => merged)
    split = row("types", id)["values"]
    assert_empty ids & split["elements"].map { |element| element["id"] }
    failure = invoke("types.grid.merge", "id" => id, "ids" => ["wel_MISSING00000"], "expected_values" => split)
    assert_equal "target.not_found", failure["code"]
    assert_equal split, row("types", id)["values"]
  end

  # Each element field has its own action with a typed value, so describe teaches the shape; a Frame
  # is set on one side, and an Empty element takes a name but no product.
  def test_element_actions_take_typed_values_and_set_one_frame_side
    frame = API.describe(:name => "#{W::FEATURE_ID}.types.grid.set_element_frame").fetch("params")
    assert_equal %w[top right bottom left], frame.dig("properties", "side", "enum")
    operation = API.describe(:name => "#{W::FEATURE_ID}.types.grid.set_element_operation").fetch("params")
    assert_equal %w[fixed swing slide], operation.dig("properties", "operation", "properties", "type", "enum")
    frame_id = create("frames", "name" => "Typed frame")
    id = create("types", "name" => "Typed elements")
    values = row("types", id)["values"]
    element = values["elements"][0]["id"]
    preview_invoke("types.grid.set_element_frame", "id" => id, "element_id" => element, "side" => "left",
                                                   "frame_id" => frame_id, "expected_values" => values)
    frames = row("types", id).dig("values", "elements", 0, "frames")
    assert_equal({ "top" => nil, "right" => nil, "bottom" => nil, "left" => frame_id }, frames)
    values = row("types", id)["values"]
    preview_invoke("types.grid.kind", "id" => id, "ids" => [element], "kind" => "empty", "expected_values" => values)
    values = row("types", id)["values"]
    refused = invoke("types.grid.set_element_glazing", "id" => id, "element_id" => element, "glazing_id" => nil,
                                                       "expected_values" => values)
    assert_equal "validation.failed", refused["code"]
    preview_invoke("types.grid.set_element_name", "id" => id, "element_id" => element, "name" => "Spandrel",
                                                  "expected_values" => values)
    assert_equal "Spandrel", row("types", id).dig("values", "elements", 0, "name")
  end

  def test_dangling_each_product_slot_is_readable_without_repair_and_writes_refuse
    id = create("types", "name" => "Missing products")
    record = stored(W::Types::KIND, id)
    cell = record["elements"][0]
    cell["glazing_id"] = "glz_MISSING00000"
    cell["frames"] = W::Types::SIDES.to_h { |side| [side, "frm_MISSING00000"] }
    cell["installs"] = W::Types::SIDES.to_h { |side| [side, "psi_MISSING00000"] }
    W::Types::KIND.store.write(@model, record)
    before = @model.attribute_dictionary(W::Types::KIND.store.dictionary)[id]
    findings = row("types", id).fetch("findings").select { |finding| finding["code"] == "window_type.product_dangling" }
    assert_equal 9, findings.length
    assert_equal before, @model.attribute_dictionary(W::Types::KIND.store.dictionary)[id]
    bad = create_result("types", window_values("name" => "New dangling", "elements" => [cell]))
    assert_equal "reference.invalid", bad["code"]
  end

  def test_installs_session_is_atomic_with_new_products_and_stale_final_type
    ids = 2.times.map { |i| create("types", "name" => "Session #{i}") }
    baselines = ids.to_h { |id| [id, row("types", id)["values"]] }
    params = {
      "types" => ids.map do |id|
        { "id" => id, "expected_values" => baselines[id], "installs" => [
          { "element_id" => baselines[id]["elements"][0]["id"],
            "sides" => W::Types::SIDES.to_h { |side| [side, "draft:junction"] } }
        ] }
      end,
      "psi_install_types" => {
        "create" => [{ "client_id" => "draft:junction",
                       "values" => { "name" => "Draft", "psi_w_mk" => 0.04 } }], "update" => []
      },
      "expected_settings" => settings
    }
    params["types"].last["expected_values"]["name"] = "Stale"
    refusal = invoke("types.installs.save", params)
    assert_equal "target.changed", refusal["code"]
    assert_equal 0, query("psi_install_types")["total"]
    params["types"].last["expected_values"]["name"] = "Session 1"
    result = preview_invoke("types.installs.save", params)
    assert_equal "committed", result["effect"], result.inspect
    psi = result.dig("value", "psi_install_type_ids", "draft:junction")
    refute_nil psi
    ids.each { |id| assert_equal [psi], row("types", id)["values"]["elements"][0]["installs"].values.uniq }
    @model.undo
    assert_equal 0, query("psi_install_types")["total"]
    ids.each { |id| assert row("types", id)["values"]["elements"][0]["installs"].values.none? }
  end

  def test_frames_and_glazing_replacement_keep_references_metadata_and_thermal_inputs
    { "frames" => { "width_m" => 0.1, "uf_w_m2k" => 1.0, "psi_g_w_mk" => -0.02 },
      "glazings" => { "ug_w_m2k" => 0.7, "g_value" => 0.0 } }.each do |collection, values|
      first = create(collection, values.merge("name" => "First #{collection}"))
      second = create(collection, values.merge("name" => "Second #{collection}"))
      incomplete = create(collection, "name" => "Missing #{collection}")
      type = window_values("name" => "Uses #{collection}")
      element = type.fetch("elements").first
      if collection == "frames"
        element["frames"] = W::Types::SIDES.to_h { |side| [side, first] }
      else
        element["glazing_id"] = first
      end
      id = create("types", type)
      assert_equal "reference.in_use", invoke("#{collection}.delete", "id" => first)["code"]
      assert_equal "validation.failed", invoke("#{collection}.delete", "id" => first,
                                                                       "replacement_id" => incomplete)["code"]
      assert_equal "target.changed", invoke("#{collection}.delete",
                                            "id" => first, "replacement_id" => second,
                                            "expected_values" => { "name" => "stale" })["code"]
      assert_equal "committed", invoke("#{collection}.delete", "id" => first, "replacement_id" => second)["effect"]
      refs = W::Types::KIND.references.select { |reference| reference.target_kind == W::Products::KINDS[collection].id }
      assert_equal [second], refs.flat_map { |reference| reference.ids(stored(W::Types::KIND, id)) }.uniq
    end
  end

  def test_settings_stale_dangling_default_undo_and_type_override_are_separate
    id = create("types", "name" => "Override", "install_depth_m" => 0.1)
    psi = create("psi_install_types", "name" => "Zero", "psi_w_mk" => 0)
    before = settings
    set_settings("default_psi_install_id" => psi, "default_install_depth_m" => 0.2)
    assert_equal 0.1, row("types", id).dig("display", "install_depth_m")
    result = invoke("settings.update", "values" => before, "expected_values" => before)
    assert_equal "target.changed", result["code"]
    bad = invoke("settings.update", "values" => before.merge("default_psi_install_id" => "psi_MISSING00000"),
                                    "expected_values" => settings)
    assert_equal "target.not_found", bad["code"]
    @model.undo
    assert_equal before, settings
    @model.redo
    assert_equal psi, settings["default_psi_install_id"]
    reset = invoke("types.update", "id" => id, "values" => { "install_depth_m" => nil },
                                   "expected_values" => { "install_depth_m" => 0.1 })
    assert_equal "committed", reset["effect"]
    refute row("types", id)["values"].key?("install_depth_m")
    assert_equal 0.2, row("types", id).dig("display", "install_depth_m")
  end

  def test_supported_extension_copies_without_aliasing_and_product_duplicate_has_unique_names
    extension = PhComposer::Records::Extension.new(:namespace => "fixture.windows.review", :schema_version => 1,
                                                   :export_relevance => "local_only", :validate => ->(_payload) {
                                                                                                     []
                                                                                                   })
    feature = Module.new do
      define_singleton_method(:install) do |registry|
        registry.feature("fixture.windows", :contract_version => 1).extension(extension)
      end
    end
    PhComposer::Registry.install([feature])
    id = create("types", "name" => "Supported")
    original = stored(W::Types::KIND, id)
    payload = extension.envelope("comments" => ["kept"])
    W::Types::KIND.store.write(@model, original.merge("extension_data" => { extension.namespace => payload }))
    copy_id = invoke("types.duplicate", "id" => id).dig("value", "id")
    copy = stored(W::Types::KIND, copy_id)
    assert_equal payload, copy.dig("extension_data", extension.namespace)
    copy["extension_data"][extension.namespace]["payload"]["comments"] << "changed"
    assert_equal ["kept"], stored(W::Types::KIND, id).dig("extension_data", extension.namespace, "payload", "comments")
    product = create("glazings", "name" => "Trimmed", "datasheet_links" => ["https://example.invalid/test.pdf"])
    explicit = invoke("glazings.duplicate", "id" => product, "name" => " Trimmed (copy) ")
    assert_equal "committed", explicit["effect"]
    next_copy = invoke("glazings.duplicate", "id" => product, "copy_datasheets" => true).dig("value", "id")
    assert_equal "Trimmed (copy 2)", row("glazings", next_copy).dig("values", "name")
    assert_equal ["https://example.invalid/test.pdf"], row("glazings", next_copy).dig("values", "datasheet_links")
    assert_empty row("glazings", explicit.dig("value", "id")).dig("values", "datasheet_links")
  end

  def test_all_empty_and_missing_dimension_types_stay_saved_with_withheld_values
    id = create("types", "name" => "Empty")
    before = row("types", id)["values"]
    invoke("types.grid.kind", "id" => id, "ids" => [before["elements"][0]["id"]], "kind" => "empty",
                              "expected_values" => before)
    thermal = row("types", id).dig("display", "thermal")
    assert_nil thermal["uw_w_m2k"]
    assert_nil thermal["u_effective_w_m2k"]
    refute thermal["complete"]
    assert_equal [{ "code" => "window_type.no_glazed_elements", "message" => "No glazed elements." }],
                 thermal["findings"]
    before = row("types", id)["values"]
    invoke("types.grid.dimension", "id" => id, "axis" => "rows_m", "index" => 0, "value" => nil,
                                   "expected_values" => before)
    missing = row("types", id)
    assert_nil missing.dig("display", "height_m")
    assert_nil missing.dig("display", "thermal", "uw_w_m2k")
    assert_equal ["window_type.dimensions_incomplete"],
                 missing.dig("display", "thermal", "findings").map { |finding| finding.fetch("code") }
  end

  def test_installs_creation_and_update_cannot_finish_with_duplicate_product_names
    product = create("psi_install_types", "name" => "Existing", "psi_w_mk" => 0.04)
    params = { "types" => [], "expected_settings" => settings, "psi_install_types" => {
      "create" => [{ "client_id" => "draft:new", "values" => { "name" => "New", "psi_w_mk" => 0.03 } }],
      "update" => [{ "id" => product, "values" => { "name" => "New" }, "expected_values" => { "name" => "Existing" } }]
    } }
    result = invoke("types.installs.save", params)
    assert_equal "validation.failed", result["code"]
    assert_equal "none", result["effect"]
    assert_equal ["Existing"], query("psi_install_types")["records"].map { |record| record.dig("values", "name") }
  end

  def test_model_sessions_keep_identical_synthetic_ids_and_settings_separate
    kind = W::Types::KIND
    record = window_record
    kind.store.write(@model, record)
    other = Sketchup::Model.new
    kind.store.write(other, record.merge("name" => "Other Model"))
    context = API.connect(:session_id => PhComposer::Sessions.for(other).id)
    outcome = API.query(:context => context, :name => "#{W::FEATURE_ID}.types.list",
                        :params => { "ids" => [record["id"]] })
    assert_equal "Other Model", outcome.dig("value", "records", 0, "values", "name")
    before = row("types", record["id"])["values"]
    result = invoke("types.update", "id" => record["id"], "values" => { "name" => "First Model" },
                                    "expected_values" => before)
    assert_equal "committed", result["effect"]
    assert_equal "Other Model", kind.store.read(other, record["id"])["name"]
    set_settings("default_psi_install_id" => nil, "default_install_depth_m" => 0.4)
    assert_equal 0.0, W::Settings.read(other)["default_install_depth_m"]
    assert_equal 0.4, settings["default_install_depth_m"]
  end

  private

  def invoke(name, params)
    @sequence += 1
    API.invoke(:context => @context, :name => "#{W::FEATURE_ID}.#{name}", :params => params,
               :request => { "sequence" => @sequence, "expected_revision" => @session.revision })
  end

  def preview_invoke(name, params)
    preview = API.preview(:context => @context, :name => "#{W::FEATURE_ID}.#{name}", :params => params)
    assert_equal "ok", preview["code"], preview.inspect
    @sequence += 1
    outcome = API.invoke(:context => @context, :name => "#{W::FEATURE_ID}.#{name}", :params => params,
                         :request => { "sequence" => @sequence, "expected_revision" => preview.fetch("revision"),
                                       "proposal_digest" => preview.fetch("proposal_digest") })
    assert_equal "committed", outcome["effect"], outcome.inspect
    outcome
  end

  def create_result(collection, values)
    invoke("#{collection}.create", "values" => values)
  end

  def create(collection, values)
    result = create_result(collection, values)
    assert_equal "committed", result["effect"], result.inspect
    result.dig("value", "id")
  end

  def query(collection, params = {})
    result = API.query(:context => @context, :name => "#{W::FEATURE_ID}.#{collection}.list", :params => params)
    assert_equal "completed", result["status"], result.inspect
    result.fetch("value")
  end

  def row(collection, id)
    query(collection, "ids" => [id])["records"].first
  end

  def settings
    API.query(:context => @context, :name => "#{W::FEATURE_ID}.settings.get", :params => {}).fetch("value")
  end

  def set_settings(values)
    result = invoke("settings.update", "values" => values, "expected_values" => settings)
    assert_equal "committed", result["effect"], result.inspect
  end

  def stored(kind, id)
    PhComposer::Records::Engine.new(@model, PhComposer::Registry.current.catalog).find(kind.id, id)
  end
end
