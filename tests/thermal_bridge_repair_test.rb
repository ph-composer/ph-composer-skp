# frozen_string_literal: true

require_relative "test_helper"
require "digest"

# The explicit repair of a thermal-bridge assignment ordinary clear cannot reach: text that is not a JSON
# object, or a readable record on an Edge no Zone holds. It names the Edge by path and the stored text by its
# SHA-256, discloses what it discards, removes that one record as one Undo step and refuses anything else.
class ThermalBridgeRepairTest < PhComposerTestCase
  API = PhComposer::API
  TB = PhComposer::ThermalBridges
  STORE = TB::Assignment::STORE
  BROKEN = "{broken é"
  FOREIGN = ["test.other_owner", "record"].freeze

  def setup
    super
    @model = Sketchup.active_model
    @session = PhComposer::Sessions.for(@model)
    @context = API.connect(:session_id => @session.id)
    @sequence = 0
    @type = invoke("types.create", "values" => { "name" => "Parapet", "psi_w_mk" => 0.05 }).dig("value", "id")
    fixture
  end

  # Zone A (100) holds Edge 101 with broken text and another owner's record, Edge 102 with a readable
  # assignment, a component placement (140) whose Edge 141 has broken text, a locked Group (130) whose Edge 131
  # has broken text, and Edge 103 with only another owner's record. Edge 5, at the root, holds a readable
  # assignment with user_data, stranded outside every Zone.
  def fixture
    @broken = edge(101)
    @broken.set_attribute(STORE.dictionary, STORE.key, BROKEN)
    @broken.set_attribute(*FOREIGN, "kept")
    @held = edge(102)
    STORE.write(@held, record("tbe_AAAAAAAAAAAA"))
    @foreign = edge(103)
    @foreign.set_attribute(*FOREIGN, "kept")
    shared = edge(141)
    shared.set_attribute(STORE.dictionary, STORE.key, BROKEN)
    locked = edge(131)
    locked.set_attribute(STORE.dictionary, STORE.key, BROKEN)
    definition = Sketchup::ComponentDefinition.new(Sketchup::Entities.new([shared]))
    @model.entities << zone(100, [@broken, @held, @foreign, Sketchup::ComponentInstance.new(140, definition),
                                  Sketchup::Group.new(130, Sketchup::Entities.new([locked]), :locked => true)])
    @stranded = edge(5)
    @stranded_text = PhComposer::CanonicalJson.generate(record("tbe_BBBBBBBBBBBB").merge(
      "user_data" => { "note" => "kept" }
    ))
    @stranded.set_attribute(STORE.dictionary, STORE.key, @stranded_text)
    @model.entities << @stranded
  end

  def test_candidates_list_every_edge_clear_cannot_reach_with_its_fingerprint
    value = query("edges.repair_candidates")
    rows = value.fetch("edges").to_h { |row| [row.fetch("path"), row] }
    assert_equal [[5], [100, 101], [100, 130, 131], [100, 140, 141]], rows.keys
    assert_equal 4, value.fetch("total")
    assert_equal ["unreadable", nil, digest(BROKEN), nil, nil],
                 rows.fetch([100, 101]).values_at("condition", "containment", "fingerprint", "record", "write_refusal")
    assert_equal ["stranded", "outside_zone", digest(@stranded_text), "tbe_BBBBBBBBBBBB"],
                 rows.fetch([5]).values_at("condition", "containment",
                                           "fingerprint").push(rows.dig([5], "record", "id"))
    assert_equal "target.locked", rows.dig([100, 130, 131], "write_refusal", "code")
    assert_equal "target.shared_definition", rows.dig([100, 140, 141], "write_refusal", "code")

    paged = query("edges.repair_candidates", "limit" => 1)
    assert_equal [[5]], paged.fetch("edges").map { |row| row.fetch("path") }
    STORE.write(@held, record("tbe_AAAAAAAAAAAA").merge("quantity" => 2))
    @session.host_event(:transaction_committed)
    assert_equal "query.cursor_expired",
                 raw_query("edges.repair_candidates", "cursor" => paged.fetch("next_cursor"))["code"]
  end

  def test_unreadable_text_is_previewed_removed_alone_and_restored_exactly_by_undo
    reference = { "zone_id" => "zon_AAAAAAAAAAAA", "zone_path" => [100], "entity_path" => [101], "entity_id" => nil }
    clear = invoke("edges.clear", "targets" => [{ "reference" => reference }])
    assert_equal "record.unreadable", clear["code"], "ordinary clear stays strict"

    params = { "path" => [100, 101], "fingerprint" => digest(BROKEN) }
    preview = API.preview(:context => @context, :name => "#{TB::FEATURE_ID}.edges.repair", :params => params)
    assert_equal "completed", preview["status"], preview.inspect
    assert_equal ["unreadable", false, false, BROKEN, nil],
                 [preview.dig("value", "condition"), preview.dig("value", "stored", "readable"),
                  preview.dig("value", "stored", "valid"), preview.dig("value", "stored", "excerpt"),
                  preview.dig("value", "discarded")]
    assert_equal BROKEN, @broken.get_attribute(STORE.dictionary, STORE.key), "a preview writes nothing"

    steps = undo_steps
    applied = invoke("edges.repair", params, preview["proposal_digest"])
    assert_equal "committed", applied["effect"], applied.inspect
    assert_equal steps + 1, undo_steps
    assert_nil live(100, 101).get_attribute(STORE.dictionary, STORE.key)
    assert_equal "kept", live(100, 101).get_attribute(*FOREIGN)
    assert_equal STORE.read(live(100, 102)), record("tbe_AAAAAAAAAAAA")

    @model.undo
    assert_equal BROKEN, live(100, 101).get_attribute(STORE.dictionary, STORE.key)
    assert_equal digest(BROKEN), digest(live(100, 101).get_attribute(STORE.dictionary, STORE.key))
    @model.redo
    assert_nil live(100, 101).get_attribute(STORE.dictionary, STORE.key)
    assert_equal "kept", live(100, 101).get_attribute(*FOREIGN)
  end

  def test_a_stranded_record_discloses_what_it_held_and_undo_restores_its_bytes
    params = { "path" => [5], "fingerprint" => digest(@stranded_text) }
    # Removing a readable id needs every record read to prove nothing names it, so unreadable text elsewhere
    # refuses first; it is repaired (or, here behind a lock and a component, removed by the user) before.
    assert_equal "record.unreadable", invoke("edges.repair", params)["code"]
    repaired = invoke("edges.repair", "path" => [100, 101], "fingerprint" => digest(BROKEN))
    assert_equal "committed", repaired["effect"], repaired.inspect
    [[100, 130, 131], [100, 140, 141]].each { |path| live(*path).delete_attribute(STORE.dictionary, STORE.key) }
    @session.host_event(:transaction_committed)
    held = STORE.read(@held)
    STORE.write(@held, held.merge("extension_data" => { "test.opaque" => "not an envelope" }))
    assert_equal "copy.rule_missing", invoke("edges.repair", params)["code"], "an opaque envelope fails closed"
    STORE.write(@held, held)
    preview = API.preview(:context => @context, :name => "#{TB::FEATURE_ID}.edges.repair", :params => params)
    assert_equal ["stranded", "outside_zone"], preview.fetch("value").values_at("condition", "containment")
    assert_equal({ "id" => "tbe_BBBBBBBBBBBB", "thermal_bridge_type_id" => @type, "quantity" => 1,
                   "user_data_keys" => ["note"], "user_data_key_total" => 1, "extension_namespaces" => [],
                   "extension_namespace_total" => 0 }, preview.dig("value", "discarded"))
    assert_equal [{ "kind" => "edge", "id" => "tbe_BBBBBBBBBBBB", "change" => "removed", "path" => [5] }],
                 preview["affected"]

    applied = invoke("edges.repair", params, preview["proposal_digest"])
    assert_equal "committed", applied["effect"], applied.inspect
    assert_nil live(5).get_attribute(STORE.dictionary, STORE.key)
    assert(query("thermal_bridges.schedule.list").fetch("edge_findings").empty?)
    @model.undo
    assert_equal @stranded_text, live(5).get_attribute(STORE.dictionary, STORE.key)
  end

  def test_changed_wrong_locked_shared_and_served_targets_refuse_before_any_write
    steps = undo_steps
    refusals = {
      "target.changed" => { "path" => [100, 101], "fingerprint" => digest("{other") },
      "target.locked" => { "path" => [100, 130, 131], "fingerprint" => digest(BROKEN) },
      "target.shared_definition" => { "path" => [100, 140, 141], "fingerprint" => digest(BROKEN) },
      "thermal_bridge.repair_not_needed" => { "path" => [100, 102],
                                              "fingerprint" => digest(stored(@held)) },
      "target.not_found" => { "path" => [100, 103], "fingerprint" => digest(BROKEN) },
      "target.wrong_kind" => { "path" => [100, 140], "fingerprint" => digest(BROKEN) }
    }
    refusals.each do |code, params|
      result = invoke("edges.repair", params)
      assert_equal [code, "none"], result.values_at("code", "effect"), "#{code}: #{result.inspect}"
    end
    assert_equal "target.not_found",
                 invoke("edges.repair", "path" => [100, 999], "fingerprint" => digest(BROKEN))["code"]
    assert_equal "params.invalid", invoke("edges.repair", "path" => [], "fingerprint" => digest(BROKEN))["code"]
    assert_equal steps, undo_steps
    assert_equal "kept", @foreign.get_attribute(*FOREIGN)
    assert_equal BROKEN, @broken.get_attribute(STORE.dictionary, STORE.key)

    # Text altered after the fingerprint was read refuses, and leaves the new text.
    params = { "path" => [100, 101], "fingerprint" => digest(BROKEN) }
    @broken.set_attribute(STORE.dictionary, STORE.key, "{also broken")
    @session.host_event(:transaction_committed)
    assert_equal "target.changed", invoke("edges.repair", params)["code"]
    assert_equal "{also broken", @broken.get_attribute(STORE.dictionary, STORE.key)
  end

  def test_a_stored_value_that_is_not_text_is_repaired_by_its_canonical_json
    @broken.set_attribute(STORE.dictionary, STORE.key, 123)
    row = query("edges.repair_candidates").fetch("edges").find { |candidate| candidate["path"] == [100, 101] }
    assert_equal ["unreadable", digest("123")], row.values_at("condition", "fingerprint")
    applied = invoke("edges.repair", "path" => [100, 101], "fingerprint" => digest("123"))
    assert_equal "committed", applied["effect"], applied.inspect
    assert_nil live(100, 101).get_attribute(STORE.dictionary, STORE.key)
  end

  def test_a_long_or_structured_record_is_cut_in_the_preview
    text = PhComposer::CanonicalJson.generate(record("tbe_BBBBBBBBBBBB").merge(
      "quantity" => Array.new(3000, 1),
      "user_data" => (1..80).to_h { |index| ["key#{index}", index] }
    ))
    @stranded.set_attribute(STORE.dictionary, STORE.key, text)
    [[100, 101], [100, 130, 131], [100, 140, 141]].each do |path|
      live(*path).delete_attribute(STORE.dictionary, STORE.key)
    end
    @session.host_event(:transaction_committed)
    preview = API.preview(:context => @context, :name => "#{TB::FEATURE_ID}.edges.repair",
                          :params => { "path" => [5], "fingerprint" => digest(text) })
    discarded = preview.dig("value", "discarded")
    assert_equal [50, 80, ["quantity"]], [discarded.fetch("user_data_keys").length,
                                          discarded.fetch("user_data_key_total"), discarded.fetch("truncated")]
    assert_operator JSON.generate(preview).bytesize, :<, PhComposer::Pages::REPLY_BYTES

    huge = text.sub(/"quantity":\[[^\]]*\]/, "\"quantity\":#{'9' * 30_001}")
    @stranded.set_attribute(STORE.dictionary, STORE.key, huge)
    @session.host_event(:transaction_committed)
    page = raw_query("edges.repair_candidates", "limit" => 1)
    assert_operator JSON.generate(page).bytesize, :<, PhComposer::Pages::REPLY_BYTES
    assert_equal [digest(huge), ["quantity"]], [page.dig("value", "edges", 0, "fingerprint"),
                                                page.dig("value", "edges", 0, "record", "truncated")]
  end

  def test_diagnostics_name_the_repair_route
    preflight = query("thermal_bridges.export_preflight")
    unreadable = preflight.fetch("findings").find { |row| row["code"] == "record.unreadable" }
    assert_includes unreadable.fetch("message"), "edges.repair_candidates"
    outside = query("thermal_bridges.schedule.list").fetch("edge_findings").find do |row|
      row["code"] == "thermal_bridge.outside_zone"
    end
    assert_includes outside.fetch("message"), "ph_composer.thermal_bridges.edges.repair"
  end

  private

  def record(id)
    { "id" => id, "schema_version" => 1, "thermal_bridge_type_id" => @type, "quantity" => 1, "user_data" => {},
      "extension_data" => {} }
  end

  def stored(entity)
    entity.get_attribute(STORE.dictionary, STORE.key)
  end

  def digest(text)
    Digest::SHA256.hexdigest(text.b)
  end

  def edge(id)
    Sketchup::Edge.new(id, Geom::Point3d.new(0, 0, 0), Geom::Point3d.new(100, id, 0))
  end

  def zone(persistent_id, children)
    group = Sketchup::Group.new(persistent_id, Sketchup::Entities.new(children))
    PhComposer::Zones::ZONE_STORE.write(group, "id" => "zon_AAAAAAAAAAAA", "schema_version" => 1, "name" => "Zone",
                                               "building_segment" => "Building", "level" => nil,
                                               "ground_depth_mm" => 0.0, "user_data" => {}, "extension_data" => {})
    group
  end

  # The entity at `path` in the Model as it stands now, which Undo replaces.
  def live(*path)
    path.reduce(@model.entities) do |entities, id|
      found = entities.to_a.find { |entity| entity.persistent_id == id }
      return found if id == path.last

      PhComposer::OccurrencePath.contents(found)
    end
  end

  def undo_steps
    @model.instance_variable_get(:@undo_stack).length
  end

  def query(name, params = {})
    result = raw_query(name, params)
    assert_equal "completed", result["status"], result.inspect
    result.fetch("value")
  end

  def raw_query(name, params = {})
    name = "#{TB::FEATURE_ID}.#{name}" unless name.start_with?("thermal_bridges.")
    name = "ph_composer.#{name}" unless name.start_with?("ph_composer.")
    API.query(:context => @context, :name => name, :params => params)
  end

  def invoke(name, params, digest = nil)
    @sequence += 1
    request = { "sequence" => @sequence, "expected_revision" => @session.revision }
    request["proposal_digest"] = digest if digest
    API.invoke(:context => @context, :name => "#{TB::FEATURE_ID}.#{name}", :params => params, :request => request)
  end
end
