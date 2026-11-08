# frozen_string_literal: true

require_relative "test_helper"
require_relative "support/assembly_record_fixtures"

class AssemblyRecordsOperationsTest < PhComposerTestCase
  include AssemblyRecordFixtures

  API = PhComposer::API

  def setup
    super
    PhComposer::Registry.install([Assemblies]) unless PhComposer::Registry.installed?(Assemblies::FEATURE_ID)
    @model = Sketchup.active_model
    @session = PhComposer::Sessions.for(@model)
    @context = API.connect(:session_id => @session.id)
    @sequence = 0
  end

  def test_every_declaration_has_a_valid_example_and_no_feature_dependency
    registry = PhComposer::Registry.current
    assert_empty registry.features.fetch(Assemblies::FEATURE_ID).requires
    declarations = registry.queries.values + registry.actions.values
    owned = declarations.select { |declaration| declaration.owner == Assemblies::FEATURE_ID }
    assert_equal 26, owned.length
    owned.each do |declaration|
      refute_empty declaration.examples, declaration.name
      declaration.examples.each do |example|
        assert_empty PhComposer::JsonSchema.validate(example, declaration.params), declaration.name
      end
    end
  end

  def test_list_is_paged_and_stored_values_are_not_changed_by_display_defaults
    first = create("assemblies", "name" => "First")
    second = create("assemblies", "name" => "Second")
    result = query("assemblies", "limit" => 1)
    assert_equal 2, result.fetch("total")
    assert_equal 1, result.fetch("records").length
    refute_nil result["next_cursor"]
    tail = query("assemblies", "limit" => 1, "cursor" => result["next_cursor"])
    assert_nil tail["next_cursor"]
    assert_equal [first, second].sort, (result["records"] + tail["records"]).map { |row| row.fetch("id") }
    row = result["records"].first
    refute row["values"].key?("color")
    assert_match(/\A#[0-9a-f]{6}\z/, row["display"]["color"])
    assert_equal ["assembly.segment_unassigned"], row["display"]["thermal"]["flags"]
    assert_nil row["display"]["thermal"]["u_effective_w_m2k"]
    assert_equal 100, row["display"]["total_thickness_mm"]
  end

  def test_stale_expected_values_refuse_without_writing
    id = create("materials", "name" => "Wool", "conductivity_w_mk" => 0.04)
    original = record(Assemblies::MATERIAL_KIND, id)
    result = invoke("materials.update", "id" => id, "values" => { "conductivity_w_mk" => 0.035 },
                                        "expected_values" => { "conductivity_w_mk" => 0.05 })
    assert_equal %w[refused target.changed none], result.values_at("status", "code", "effect")
    assert_equal original, record(Assemblies::MATERIAL_KIND, id)
  end

  def test_a_material_colour_is_written_only_as_six_digit_hex
    id = create("materials", "name" => "Brick")
    refused = invoke("materials.update", "id" => id, "values" => { "color" => "red; background-image: url(x)" },
                                         "expected_values" => { "color" => "#ffffff" })
    assert_equal %w[refused none], refused.values_at("status", "effect")
    assert_includes %w[params.invalid validation.failed], refused["code"]
    accepted = invoke("materials.update", "id" => id, "values" => { "color" => "#A1b2C3" },
                                          "expected_values" => { "color" => "#ffffff" })
    assert_equal "committed", accepted["effect"]
    assert_equal "#A1b2C3", record(Assemblies::MATERIAL_KIND, id)["color"]
  end

  def test_material_delete_rewrites_every_occurrence_in_one_undo_step
    old, replacement, ids = seed_repeated_uses
    refused = invoke("materials.delete", "id" => old)
    assert_equal %w[refused reference.in_use none], refused.values_at("status", "code", "effect")
    original = ids.map { |id| record(Assemblies::ASSEMBLY_KIND, id) }
    result = invoke("materials.delete", "id" => old, "replacement_id" => replacement)
    assert_equal "committed", result["effect"]
    ids.each do |id|
      assert_equal [replacement], Assemblies::Assembly::Schema::KIND.references.first
                                                                    .ids(record(Assemblies::ASSEMBLY_KIND, id)).uniq
    end
    assert_raises(PhComposer::CodedError) { record(Assemblies::MATERIAL_KIND, old) }
    @model.undo
    assert_equal original, ids.map { |id| record(Assemblies::ASSEMBLY_KIND, id) }
    assert_equal old, record(Assemblies::MATERIAL_KIND, old)["id"]
    @model.redo
    ids.each do |id|
      assert_equal [replacement], Assemblies::Assembly::Schema::KIND.references.first
                                                                    .ids(record(Assemblies::ASSEMBLY_KIND, id)).uniq
    end
  end

  def test_failure_on_last_delete_rolls_back_all_preceding_rewrites
    old, replacement, ids = seed_repeated_uses
    original = ids.map { |id| record(Assemblies::ASSEMBLY_KIND, id) }
    material_store = Assemblies::Materials::Schema::KIND.store
    original_delete = material_store.method(:delete)
    material_store.define_singleton_method(:delete) do |_model, _id|
      raise PhComposer::InternalError, "Injected failure."
    end
    result = invoke("materials.delete", "id" => old, "replacement_id" => replacement)
    assert_equal %w[failed operation.failed rolled_back], result.values_at("status", "code", "effect")
    assert_equal original, ids.map { |id| record(Assemblies::ASSEMBLY_KIND, id) }
    assert_equal old, record(Assemblies::MATERIAL_KIND, old)["id"]
  ensure
    material_store&.define_singleton_method(:delete, original_delete) if original_delete
  end

  def test_duplicate_regenerates_nested_ids_preserves_metadata_and_clears_photos
    material = create("materials", "name" => "Wool", "conductivity_w_mk" => 0.04)
    values = fixture_assembly([[140, [[850, "wool"], [150, "wool"]]]])
    values["layers"][0]["segments"].each { |segment| segment["material_id"] = material }
    values["air_barrier"] = { "layer_id" => values["layers"][0]["id"], "face" => "interior" }
    values["photo_collections"] = { "site" => ["photo"] }
    id = create("assemblies", Assemblies::Assembly::Schema::KIND.values(values),
                "review" => { "notes" => ["original"] })
    original = record(Assemblies::ASSEMBLY_KIND, id)
    result = invoke("assemblies.duplicate", "id" => id)
    assert_equal "committed", result["effect"]
    copy = record(Assemblies::ASSEMBLY_KIND, result.dig("value", "id"))
    refute_equal id, copy["id"]
    refute_equal original["layers"][0]["id"], copy["layers"][0]["id"]
    assert_empty(original["layers"][0]["segments"].map { |row| row["id"] } &
                 copy["layers"][0]["segments"].map { |row| row["id"] })
    assert_equal copy["layers"][0]["id"], copy["air_barrier"]["layer_id"]
    assert_equal [material], Assemblies::Assembly::Schema::KIND.references.first.ids(copy).uniq
    assert_equal original["user_data"], copy["user_data"]
    copy["user_data"]["review"]["notes"] << "copy"
    assert_equal ["original"], record(Assemblies::ASSEMBLY_KIND, id)["user_data"]["review"]["notes"]
    assert_equal({}, copy["photo_collections"])
  end

  def test_unknown_extension_payload_survives_edit_and_copy_refuses_missing_rules
    id = create("assemblies", "name" => "Unknown payload")
    kind = Assemblies::Assembly::Schema::KIND
    original = record(kind.id, id)
    payload = { "schema_version" => 9, "payload" => { "secret_notes" => ["kept"] },
                "references" => [], "export_relevance" => "required" }
    kind.store.write(@model, original.merge("extension_data" => { "outside.vendor" => payload }))
    edit = invoke("assemblies.update", "id" => id, "values" => { "name" => "Edited" },
                                       "expected_values" => { "name" => original["name"] })
    assert_equal "committed", edit["effect"]
    assert_equal payload, record(kind.id, id).dig("extension_data", "outside.vendor")
    duplicate = invoke("assemblies.duplicate", "id" => id)
    assert_equal %w[refused copy.rule_missing none], duplicate.values_at("status", "code", "effect")
    assert_equal 1, query("assemblies")["total"]
  end

  def test_material_uses_and_incomplete_conditions_are_readable_with_the_panel_closed
    old, _replacement, ids = seed_repeated_uses
    material = query("materials", "ids" => [old])["records"].first
    assert_equal 2, material["use_count"]
    assert_equal ids.sort, material["uses"].map { |row| row["assembly_id"] }.sort
    assembly = query("assemblies", "ids" => [ids.first])["records"].first
    assert_equal true, assembly["display"]["complete"]
    assert_equal ["material.thermal_mass_defaulted"], assembly["findings"].map { |row| row["code"] }.uniq
    refute assembly["findings"].any? { |row| row.key?("severity") }
  end

  # W-112: `describe` gave layer and segment ids as plain strings while the validator wanted the
  # prefix and twelve alphanumerics, so an agent's first layered create was refused.
  def test_the_published_create_schema_is_enough_to_create_a_layered_assembly
    values = API.describe(:name => "#{Assemblies::FEATURE_ID}.assemblies.create").dig("params", "properties", "values")
    fields = values.fetch("properties")
    layer = fields.dig("layers", "items", "properties")
    segment = layer.dig("segments", "items", "properties")
    published = { "lyr_Ab12Cd34Ef56" => layer.fetch("id"), "seg_Ab12Cd34Ef56" => segment.fetch("id"),
                  material_id("board") => segment.fetch("material_id") }
    published.each { |id, schema| assert_match PhComposer::JsonSchema.pattern(schema), id, schema.inspect }
    published.each_value { |schema| refute_empty schema.fetch("description") }
    assert_equal layer.fetch("id").fetch("pattern"),
                 fields.dig("air_barrier", "properties", "layer_id", "pattern")

    invalid = layered_values("name" => "Plain ids", "layer" => "layer-1", "segment" => "segment-1")
    refused = invoke("assemblies.create", "values" => invalid)
    assert_equal "params.invalid", refused["code"], refused.inspect
    assert_includes refused["message"], layer.fetch("id").fetch("pattern")

    create("materials", "name" => "Board", "conductivity_w_mk" => 0.038)
    board = query("materials")["records"].first.fetch("id")
    id = create("assemblies", layered_values("name" => "Agent wall", "layer" => "lyr_Ab12Cd34Ef56",
                                             "segment" => "seg_Ab12Cd34Ef56", "material" => board))
    stored = record(Assemblies::ASSEMBLY_KIND, id).fetch("layers").first
    assert_equal ["lyr_Ab12Cd34Ef56", "seg_Ab12Cd34Ef56", board],
                 [stored.fetch("id"), *stored.fetch("segments").first.values_at("id", "material_id")]
  end

  def test_preview_digest_rebuilds_create_duplicate_and_each_new_nested_identity
    id = preview_invoke("assemblies.create", "values" => { "name" => "Preview wall" }).fetch("value").fetch("id")
    row = record(Assemblies::ASSEMBLY_KIND, id)
    first_ids = row["layers"].flat_map { |layer| [layer["id"]] + layer["segments"].map { |segment| segment["id"] } }
    preview_invoke("assemblies.layers.add", "id" => id, "thickness_mm" => 140,
                                            "expected_values" => { "layers" => row.fetch("layers") })
    row = record(Assemblies::ASSEMBLY_KIND, id)
    last = row.fetch("layers").last
    preview_invoke("assemblies.segments.add", "id" => id, "layer_id" => last.fetch("id"), "width_mm" => 150,
                                              "expected_values" => { "layers" => row.fetch("layers") })
    copy = preview_invoke("assemblies.duplicate", "id" => id).fetch("value").fetch("id")
    duplicate = record(Assemblies::ASSEMBLY_KIND, copy)
    duplicate_ids = duplicate["layers"].flat_map do |layer|
      [layer["id"]] + layer["segments"].map { |segment| segment["id"] }
    end
    assert_empty first_ids & duplicate_ids
    row = record(Assemblies::ASSEMBLY_KIND, id)
    previous = row["layers"].last["id"]
    preview_invoke("assemblies.layers.add", "id" => id, "thickness_mm" => 140,
                                            "expected_values" => { "layers" => row.fetch("layers") })
    refute_equal previous, record(Assemblies::ASSEMBLY_KIND, id)["layers"].last["id"]
  end

  def test_material_aliases_names_and_datasheet_duplicate_behavior_use_normal_operations
    id = create("materials", "name" => " Framing ", "category" => "Wood",
                             "datasheet_links" => ["https://example.invalid/framing.pdf"])
    assert_equal ["Framing", "woods"], record(Assemblies::MATERIAL_KIND, id).values_at("name", "category")
    copy = invoke("materials.duplicate", "id" => id).fetch("value").fetch("id")
    assert_empty record(Assemblies::MATERIAL_KIND, copy).fetch("datasheet_links")
    kept = invoke("materials.duplicate", "id" => id, "copy_datasheets" => true).fetch("value").fetch("id")
    assert_equal ["https://example.invalid/framing.pdf"], record(Assemblies::MATERIAL_KIND, kept)["datasheet_links"]
    refused = invoke("materials.create", "values" => { "name" => "framing" })
    assert_equal %w[refused validation.failed none], refused.values_at("status", "code", "effect")
    invalid = invoke("materials.update", "id" => id, "values" => { "category" => "invented" },
                                         "expected_values" => { "category" => "woods" })
    assert_equal "validation.failed", invalid["code"]
  end

  def test_layer_operations_undo_redo_and_invalid_ids_share_the_registered_api
    id = create("assemblies", "name" => "Gestures")
    original = record(Assemblies::ASSEMBLY_KIND, id)
    layer = original["layers"].first
    edit = invoke("assemblies.layers.update", "id" => id, "layer_id" => layer["id"], "thickness_mm" => 50,
                                              "expected_values" => { "layers" => original["layers"] })
    assert_equal "committed", edit["effect"]
    @model.undo
    assert_equal original, record(Assemblies::ASSEMBLY_KIND, id)
    @model.redo
    assert_equal 50, record(Assemblies::ASSEMBLY_KIND, id)["layers"].first["thickness_mm"]
    wrong = invoke("assemblies.segments.update",
                   "id" => id, "layer_id" => layer["id"],
                   "segment_id" => "seg_MISSING00000", "values" => { "width_mm" => 150 }, "expected_values" => {})
    assert_equal %w[refused target.not_found none], wrong.values_at("status", "code", "effect")
  end

  def test_layer_reorder_is_one_undo_step_refuses_a_stale_order_and_writes_nothing_in_place
    values = fixture_assembly([[12, [[1000, nil]]], [140, [[1000, nil]]], [40, [[1000, nil]]]])
    id = create("assemblies", Assemblies::Assembly::Schema::KIND.values(values))
    original = record(Assemblies::ASSEMBLY_KIND, id)
    last = original["layers"].last
    revision = @session.revision
    moved = invoke("assemblies.layers.reorder", "id" => id, "layer_id" => last["id"], "index" => 0,
                                                "expected_values" => { "layers" => original["layers"] })
    assert_equal %w[completed committed], moved.values_at("status", "effect")
    assert_equal [revision + 1, "Move Assembly Layer"], [@session.revision, @model.operations.last.first]
    assert_equal last["id"], record(Assemblies::ASSEMBLY_KIND, id)["layers"].first["id"]
    stale = invoke("assemblies.layers.reorder", "id" => id, "layer_id" => last["id"], "index" => 2,
                                                "expected_values" => { "layers" => original["layers"] })
    assert_equal %w[refused target.changed none], stale.values_at("status", "code", "effect")
    assert stale["message"].end_with?("Nothing was written."), stale["message"]
    current = record(Assemblies::ASSEMBLY_KIND, id)
    assert_equal last["id"], current["layers"].first["id"]
    operations = @model.operations.length
    revision = @session.revision
    same = invoke("assemblies.layers.reorder", "id" => id, "layer_id" => last["id"], "index" => 0,
                                               "expected_values" => { "layers" => current["layers"] })
    assert_equal %w[completed none], same.values_at("status", "effect")
    assert_equal [operations, revision], [@model.operations.length, @session.revision]
    @model.undo
    assert_equal original, record(Assemblies::ASSEMBLY_KIND, id)
  end

  def test_unreadable_inventory_rows_are_reported_without_repair
    id = create("assemblies", "name" => "Broken")
    kind = Assemblies::Assembly::Schema::KIND
    kind.store.write(@model, record(kind.id, id).merge("unknown" => 1))
    before = @model.attribute_dictionary(kind.store.dictionary)[id]
    result = query("assemblies")
    assert_empty result["records"]
    assert_equal "record.unreadable", result["unreadable"].first["code"]
    assert_equal before, @model.attribute_dictionary(kind.store.dictionary)[id]
  end

  def test_supported_extension_and_metadata_duplicate_as_independent_json_copies
    extension = PhComposer::Records::Extension.new(:namespace => "fixture.assemblies.review", :schema_version => 1,
                                                   :export_relevance => "local_only", :validate => ->(_payload) {
                                                                                                     []
                                                                                                   })
    feature = Module.new do
      define_singleton_method(:install) do |registry|
        registry.feature("fixture.assemblies", :contract_version => 1).extension(extension)
      end
    end
    PhComposer::Registry.install([feature])
    id = create("assemblies", "name" => "Supported payload")
    kind = Assemblies::Assembly::Schema::KIND
    payload = extension.envelope("comments" => ["original"])
    kind.store.write(@model, record(kind.id, id).merge("extension_data" => { extension.namespace => payload }))
    result = invoke("assemblies.duplicate", "id" => id)
    assert_equal "committed", result["effect"]
    copy = record(kind.id, result.dig("value", "id"))
    assert_equal payload, copy.dig("extension_data", extension.namespace)
    copy["extension_data"][extension.namespace]["payload"]["comments"] << "copy"
    assert_equal ["original"], record(kind.id, id).dig("extension_data", extension.namespace, "payload", "comments")
  end

  def test_membrane_replacement_and_stale_delete_refuse_all_rewrites
    old, replacement, ids = seed_repeated_uses
    original = ids.map { |id| record(Assemblies::ASSEMBLY_KIND, id) }
    membrane = create("materials", "name" => "Membrane", "category" => "membrane")
    mixed = invoke("materials.delete", "id" => old, "replacement_id" => membrane)
    assert_equal %w[refused validation.failed none], mixed.values_at("status", "code", "effect")
    stale = invoke("materials.delete", "id" => old, "replacement_id" => replacement,
                                       "expected_values" => { "name" => "Changed elsewhere" })
    assert_equal %w[refused target.changed none], stale.values_at("status", "code", "effect")
    assert_equal original, ids.map { |id| record(Assemblies::ASSEMBLY_KIND, id) }
    assert_equal old, record(Assemblies::MATERIAL_KIND, old)["id"]
  end

  def test_identical_synthetic_ids_are_isolated_between_model_sessions
    kind = Assemblies::Materials::Schema::KIND
    one = fixture_materials.fetch(material_id("wool"))
    kind.store.write(@model, one)
    other = Sketchup::Model.new
    kind.store.write(other, one.merge("name" => "Other Model"))
    context = API.connect(:session_id => PhComposer::Sessions.for(other).id)
    row = API.query(:context => context, :name => "#{Assemblies::FEATURE_ID}.materials.list",
                    :params => { "ids" => [one.fetch("id")] }).dig("value", "records", 0)
    assert_equal "Other Model", row.dig("values", "name")
    edit = invoke("materials.update", "id" => one.fetch("id"), "values" => { "name" => "First Model" },
                                      "expected_values" => { "name" => one.fetch("name") })
    assert_equal "committed", edit["effect"]
    assert_equal "Other Model", kind.store.read(other, one.fetch("id"))["name"]
    assert_equal "First Model", record(kind.id, one.fetch("id"))["name"]
  end

  def test_explicit_duplicate_whitespace_and_default_suffix_use_the_same_name_rule
    id = create("materials", "name" => "Trimmed")
    explicit = invoke("materials.duplicate", "id" => id, "name" => " Trimmed (copy) ")
    assert_equal "committed", explicit["effect"]
    assert_equal "Trimmed (copy)", record(Assemblies::MATERIAL_KIND, explicit.dig("value", "id"))["name"]
    default = invoke("materials.duplicate", "id" => id)
    assert_equal "committed", default["effect"]
    assert_equal "Trimmed (copy 2)", record(Assemblies::MATERIAL_KIND, default.dig("value", "id"))["name"]
  end

  def test_calculation_limit_is_saved_and_reported_as_an_incomplete_display_condition
    material = create("materials", "name" => "Limit wool", "conductivity_w_mk" => 0.04)
    values = fixture_assembly(Array.new(30) { [100, [[500, "wool"], [500, "wool"]]] })
    values["layers"].each { |layer| layer["segments"].each { |segment| segment["material_id"] = material } }
    id = create("assemblies", Assemblies::Assembly::Schema::KIND.values(values))
    row = query("assemblies", "ids" => [id])["records"].first
    assert_equal false, row["display"]["complete"]
    assert_equal ["assembly.calculation_limit"], row["display"]["thermal"]["flags"]
    assert_includes row["findings"].map { |finding| finding["code"] }, "assembly.calculation_limit"
    assert_equal 30, record(Assemblies::ASSEMBLY_KIND, id)["layers"].length
    edit = invoke("assemblies.update", "id" => id, "values" => { "notes" => "Still editable" },
                                       "expected_values" => { "notes" => "" })
    assert_equal "committed", edit["effect"]
  end

  private

  def layered_values(options)
    { "name" => options.fetch("name"), "orientation" => "first_layer_outside",
      "layers" => [{ "id" => options.fetch("layer"), "thickness_mm" => 140,
                     "segments" => [{ "id" => options.fetch("segment"), "width_mm" => 1000,
                                      "material_id" => options["material"], "is_continuous_insulation" => false,
                                      "steel_stud_spacing_mm" => nil }] }] }
  end

  def preview_invoke(name, params)
    preview = API.preview(:context => @context, :name => "#{Assemblies::FEATURE_ID}.#{name}", :params => params)
    assert_equal "ok", preview["code"], preview.inspect
    @sequence += 1
    result = API.invoke(:context => @context, :name => "#{Assemblies::FEATURE_ID}.#{name}", :params => params,
                        :request => { "sequence" => @sequence, "expected_revision" => preview.fetch("revision"),
                                      "proposal_digest" => preview.fetch("proposal_digest") })
    assert_equal "committed", result["effect"], result.inspect
    result
  end

  def create(collection, values, user_data = nil)
    params = { "values" => values }
    params["user_data"] = user_data if user_data
    result = invoke("#{collection}.create", params)
    assert_equal "committed", result["effect"], result.inspect
    result.fetch("value").fetch("id")
  end

  def invoke(name, params)
    @sequence += 1
    API.invoke(:context => @context, :name => "#{Assemblies::FEATURE_ID}.#{name}", :params => params,
               :request => { "sequence" => @sequence, "expected_revision" => @session.revision })
  end

  def query(collection, params = {})
    result = API.query(:context => @context, :name => "#{Assemblies::FEATURE_ID}.#{collection}.list", :params => params)
    assert_equal "completed", result["status"], result.inspect
    result.fetch("value")
  end

  def record(kind, id)
    PhComposer::Records::Engine.new(@model, PhComposer::Registry.current.catalog).find(kind, id)
  end

  def seed_repeated_uses
    old = create("materials", "name" => "Original", "conductivity_w_mk" => 0.04)
    replacement = create("materials", "name" => "Replacement", "conductivity_w_mk" => 0.035)
    ids = 2.times.map do |index|
      values = fixture_assembly([[12, [[1000, "wool"]]], [140, [[850, "wool"], [150, "wool"]]]])
      values["name"] = "Assembly #{index}"
      values["layers"].each { |layer| layer["segments"].each { |segment| segment["material_id"] = old } }
      create("assemblies", Assemblies::Assembly::Schema::KIND.values(values))
    end
    [old, replacement, ids]
  end
end
