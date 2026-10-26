# frozen_string_literal: true

require_relative "test_helper"

# The Thermal Bridge Type catalog through its registered actions and reads, and the line that keeps
# the type independent of Edges, Zones and runs (context/EXTENSIBILITY.md, "Organization and
# dependencies").
class ThermalBridgeTypesTest < PhComposerTestCase
  API = PhComposer::API
  TB = PhComposer::ThermalBridges
  KIND = TB::Type::KIND
  FEATURES = File.expand_path("../src/ph_composer/features", __dir__)

  def setup
    super
    PhComposer.compose unless PhComposer::Registry.installed?(TB::FEATURE_ID)
    @model = Sketchup.active_model
    @session = PhComposer::Sessions.for(@model)
    @context = API.connect(:session_id => @session.id)
    @sequence = 0
  end

  def test_a_stored_type_round_trips_and_unknown_keys_or_versions_are_unreadable
    id = create("name" => "Parapet", "psi_w_mk" => 0.12)
    stored = record(id)
    assert_empty KIND.problems(JSON.parse(JSON.generate(stored)))
    refute_empty KIND.problems(stored.merge("invented" => 1))
    KIND.store.write(@model, stored.merge("schema_version" => 2))
    assert_equal "record.unreadable", list.dig("unreadable", 0, "code")
    assert_empty list["records"]
  end

  def test_psi_is_signed_and_nullable_and_group_takes_only_the_three_stored_strings
    negative = create("name" => "Corner", "psi_w_mk" => -0.02)
    assert_in_delta(-0.02, record(negative)["psi_w_mk"])
    assert_nil record(create("name" => "Unknown"))["psi_w_mk"]
    text = invoke("types.create", "values" => { "name" => "Text", "psi_w_mk" => "0.1" })
    assert_equal %w[refused params.invalid none], text.values_at("status", "code", "effect")
    refused = invoke("types.create", "values" => { "name" => "Words", "group" => "Ambient" })
    assert_equal %w[refused params.invalid none], refused.values_at("status", "code", "effect")
    TB::Type::GROUPS.each_with_index do |group, index|
      assert_equal group, record(create("name" => "Group #{index}", "group" => group))["group"]
    end
  end

  def test_create_defaults_the_group_and_reads_a_colour_for_the_id
    id = create("name" => "Defaults")
    assert_equal "15-Ambient", record(id)["group"]
    refute record(id).key?("color")
    row = list("ids" => [id])["records"].first
    assert_includes TB::Type::RAMP, row.dig("display", "color")
    edited = invoke("types.update", "id" => id, "values" => { "color" => "#123abc" },
                                    "expected_values" => { "color" => nil })
    assert_equal "committed", edited["effect"]
    assert_equal "#123abc", list("ids" => [id])["records"].first.dig("display", "color")
    reverted = invoke("types.update", "id" => id, "values" => { "color" => nil },
                                      "expected_values" => { "color" => "#123abc" })
    assert_equal "committed", reverted["effect"]
    refute record(id).key?("color")
    assert_equal row.dig("display", "color"), list("ids" => [id])["records"].first.dig("display", "color")
  end

  def test_a_stale_expected_value_refuses_the_whole_edit_and_writes_nothing
    id = create("name" => "Slab edge", "psi_w_mk" => 0.05)
    before = record(id)
    result = invoke("types.update", "id" => id, "values" => { "name" => "Renamed", "psi_w_mk" => 0.06 },
                                    "expected_values" => { "psi_w_mk" => 0.04 })
    assert_equal %w[refused target.changed none], result.values_at("status", "code", "effect")
    assert_equal before, record(id)
  end

  def test_duplicate_takes_a_new_id_independent_user_data_and_derived_source
    id = create({ "name" => "Balcony", "psi_w_mk" => 0.3, "datasheet_links" => ["calc.pdf"] },
                { "review" => { "notes" => ["original"] } })
    result = invoke("types.duplicate", "id" => id)
    assert_equal "committed", result["effect"]
    copy = record(result.dig("value", "id"))
    refute_equal id, copy["id"]
    assert_equal ["Balcony (copy)", { "kind" => "derived" }, [], 0.3],
                 copy.values_at("name", "source", "datasheet_links", "psi_w_mk")
    assert_equal({ "review" => { "notes" => ["original"] } }, copy["user_data"])
    named = invoke("types.duplicate", "id" => id, "name" => "Balcony", "copy_datasheets" => true)
    assert_equal %w[refused validation.failed none], named.values_at("status", "code", "effect")
    kept = invoke("types.duplicate", "id" => id, "name" => "Balcony B", "copy_datasheets" => true)
    assert_equal ["calc.pdf"], record(kept.dig("value", "id"))["datasheet_links"]
  end

  def test_delete_of_an_unused_type_is_one_undo_step_that_restores_its_metadata
    id = create({ "name" => "Unused" }, { "owner" => "fixture" })
    payload = { "schema_version" => 9, "payload" => { "kept" => true }, "references" => [],
                "export_relevance" => "required" }
    KIND.store.write(@model, record(id).merge("extension_data" => { "outside.vendor" => payload }))
    before = record(id)
    result = invoke("types.delete", "id" => id)
    assert_equal "committed", result["effect"]
    assert_equal 0, list["total"]
    @model.undo
    assert_equal before, record(id)
  end

  def test_an_unreadable_envelope_on_another_type_refuses_a_delete_as_declared
    id = create("name" => "Deleted")
    other = create("name" => "Damaged")
    KIND.store.write(@model, record(other).merge("extension_data" => { "outside.vendor" => { "garbage" => 1 } }))
    result = invoke("types.delete", "id" => id)
    assert_equal %w[refused copy.rule_missing none], result.values_at("status", "code", "effect")
    assert_equal id, record(id)["id"]
  end

  def test_a_list_page_is_cut_by_size_and_its_cursor_reads_every_type_once
    ids = Array.new(100) do |index|
      id = PhComposer::Records::Identity.mint("tbt")
      KIND.store.write(@model, TB::Type.defaults("name" => "Type #{index}", "notes" => "n" * 400)
                                 .merge("id" => id, "schema_version" => 1))
      id
    end
    first = list
    assert_operator first["records"].length, :<, 100
    assert_operator JSON.generate(first["records"]).bytesize, :<=, PhComposer::Pages::MAX_PAGE_BYTES
    read = first["records"].map { |row| row["id"] }
    cursor = first["next_cursor"]
    while cursor
      page = list("cursor" => cursor)
      read.concat(page["records"].map { |row| row["id"] })
      cursor = page["next_cursor"]
    end
    assert_equal ids.sort, read
  end

  def test_a_type_without_a_psi_value_is_not_export_ready
    rows = query_all.fetch("records").to_h { |row| [row.dig("values", "name"), row] }
    assert_empty rows
    create("name" => "Empty")
    create("name" => "Known", "psi_w_mk" => 0.1)
    rows = query_all.fetch("records").to_h { |row| [row.dig("values", "name"), row] }
    assert_equal [false, ["thermal_bridge.psi_missing"]],
                 rows.fetch("Empty").values_at("export_ready", "export_blockers")
    assert_equal [true, []], rows.fetch("Known").values_at("export_ready", "export_blockers")
  end

  def test_the_type_names_no_edge_zone_or_run_and_no_other_feature_names_thermal_bridges
    type_files = Dir[File.join(FEATURES, "thermal_bridges", "type", "**", "*.rb")]
    refute_empty type_files
    type_files.each do |path|
      refute_match(/Zones|Windows|Sketchup::Edge|runs\//, File.read(path), path)
    end
    others = Dir[File.join(FEATURES, "**", "*.{rb,js}")].reject { |path| path.include?("/thermal_bridges/") }
    others.each { |path| refute_match(/thermal.bridge|ThermalBridge/i, File.read(path), path) }
  end

  def test_every_declaration_has_a_valid_example
    registry = PhComposer::Registry.current
    owned = (registry.queries.values + registry.actions.values).select { |row| row.owner == TB::FEATURE_ID }
    assert_equal 10, owned.length
    owned.each do |declaration|
      declaration.examples.each do |example|
        assert_empty PhComposer::JsonSchema.validate(example, declaration.params), declaration.name
      end
    end
  end

  private

  def create(values, user_data = nil)
    params = { "values" => values }
    params["user_data"] = user_data if user_data
    result = invoke("types.create", params)
    assert_equal "committed", result["effect"], result.inspect
    result.fetch("value").fetch("id")
  end

  def invoke(name, params)
    @sequence += 1
    API.invoke(:context => @context, :name => "#{TB::FEATURE_ID}.#{name}", :params => params,
               :request => { "sequence" => @sequence, "expected_revision" => @session.revision })
  end

  def list(params = {})
    result = API.query(:context => @context, :name => "#{TB::FEATURE_ID}.types.list", :params => params)
    assert_equal "completed", result["status"], result.inspect
    result.fetch("value")
  end

  def query_all
    result = API.query(:context => @context, :name => "#{TB::FEATURE_ID}.types.all", :params => {})
    assert_equal "completed", result["status"], result.inspect
    result.fetch("value")
  end

  def record(id)
    PhComposer::Records::Engine.new(@model, PhComposer::Registry.current.catalog).find(TB::TYPE_KIND, id)
  end
end
