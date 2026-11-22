# frozen_string_literal: true

require_relative "test_helper"
require_relative "support/assembly_assignment_fixtures"

# Catalog record metadata through the foundation's ph_composer.records.update_metadata (context/CONTRACTS.md,
# "Records and extension data"): whole-map user_data replacement under the metadata last read, every target
# resolved before anything is staged, one Undo entry per batch and none for a batch that writes what is
# stored. The kinds' own update actions no longer take user_data; their create actions still do.
class RecordMetadataTest < PhComposerTestCase
  include AssemblyAssignmentFixtures

  ACTION = "ph_composer.records.update_metadata"
  MATERIAL = PhComposer::Assemblies::MATERIAL_KIND
  ASSEMBLY = PhComposer::Assemblies::ASSEMBLY_KIND
  ATTACHED = PhComposer::Zones::Faces::AttachedZone::KIND_ID
  WINDOW_TYPE = PhComposer::Windows::TYPE_KIND
  EMPTY = { "user_data" => {}, "extension_data" => {} }.freeze
  REVIEW = "probe.records.review"
  LINK = "probe.records.link"

  # An installed extension whose payload is valid when its status is draft or checked.
  module Review
    module_function

    def name
      "Review"
    end

    def install(registry)
      feature = registry.feature("probe.records", :contract_version => 1)
      feature.extension(PhComposer::Records::Extension.new(
        :namespace => REVIEW, :schema_version => 1, :export_relevance => "local_only",
        :validate => ->(payload) { %w[draft checked].include?(payload["status"]) ? [] : ["status is unknown"] }
      ))
      feature.extension(PhComposer::Records::Extension.new(
        :namespace => LINK, :schema_version => 1, :export_relevance => "local_only",
        :references => [{ "path" => "$.material_id", "target_kind" => MATERIAL, "cardinality" => "one" }],
        :validate => ->(payload) { payload["material_id"].is_a?(String) ? [] : ["material_id is missing"] }
      ))
    end
  end

  # Two probe kinds sharing one follow-up that records each call, and a third with none.
  module FollowUp
    CALLS = [] # rubocop:disable Style/MutableConstant
    RECORD = ->(request, proposal) { CALLS << [request.owner, proposal.writes.map(&:id).sort] }
    KINDS = { "one" => "pfo", "two" => "pft", "three" => "pfh" }.freeze

    module_function

    def name
      "FollowUp"
    end

    def kind(name)
      "probe.follow.#{name}"
    end

    def install(registry)
      feature = registry.feature("probe.follow", :contract_version => 1)
      KINDS.each do |name, prefix|
        feature.record_kind(PhComposer::Records::RecordKind.new(
          :id => kind(name), :label => name.capitalize, :schema_version => 1, :id_prefix => prefix, :fields => [],
          :metadata_follow_up => name == "three" ? nil : RECORD
        ))
      end
    end
  end

  def setup
    super
    assignment_setup
    PhComposer::Registry.install([Review])
    @material = create("ph_composer.assemblies.materials.create", "name" => "Wool")
    @assembly = create("ph_composer.assemblies.assemblies.create", "name" => "Wall")
  end

  def create(name, values, user_data = nil)
    params = { "values" => values }
    params["user_data"] = user_data if user_data
    result = assignment_invoke(name, params)
    assert_equal "committed", result.fetch("effect"), result.inspect
    result.dig("value", "id")
  end

  def read(kind, id)
    assignment_query("ph_composer.records.list", "kind" => kind, "ids" => [id]).fetch("records").first
  end

  def entry(kind, id, user_data, expected = nil)
    { "reference" => { "kind" => kind, "id" => id }, "user_data" => user_data,
      "expected_metadata" => expected || read(kind, id).slice("user_data", "extension_data") }
  end

  # An Assembly part's entry, its pre-image read from the record's values: a part carries no extension data.
  def part_entry(part_ids, user_data, expected = nil)
    { "reference" => { "kind" => ASSEMBLY, "id" => @assembly, "part_ids" => part_ids }, "user_data" => user_data,
      "expected_metadata" => expected || { "user_data" => part(part_ids).fetch("user_data", {}),
                                           "extension_data" => {} } }
  end

  def part(part_ids)
    layer = read(ASSEMBLY, @assembly).dig("values", "layers").find { |row| row.fetch("id") == part_ids.first }
    part_ids.length == 1 ? layer : layer.fetch("segments").find { |row| row.fetch("id") == part_ids.last }
  end

  def layer_ids
    layers = read(ASSEMBLY, @assembly).dig("values", "layers")
    [layers.first.fetch("id"), layers.first.dig("segments", 0, "id")]
  end

  def write(*entries)
    assignment_invoke(ACTION, "updates" => entries)
  end

  def test_set_replace_and_clear_on_definitions_of_every_feature_with_detached_reads
    frame = create("ph_composer.windows.frames.create", "name" => "Frame")
    bridge = create("ph_composer.thermal_bridges.types.create", "name" => "Sill")
    [[MATERIAL, @material], [ASSEMBLY, @assembly], [PhComposer::Windows::FRAME_KIND, frame],
     [PhComposer::ThermalBridges::TYPE_KIND, bridge]].each do |kind, id|
      values = read(kind, id).fetch("values")
      submitted = { "firm" => { "status" => "draft" } }
      result = write(entry(kind, id, submitted))
      assert_equal "committed", result.fetch("effect"), result.inspect
      assert_equal [{ "reference" => { "kind" => kind, "id" => id }, "extension_status" => {} }],
                   result.dig("value", "updates")
      submitted["firm"]["status"] = "changed after the write"
      assert_equal({ "firm" => { "status" => "draft" } }, read(kind, id).fetch("user_data"), kind)

      write(entry(kind, id, { "other" => [1] }))
      replaced = read(kind, id)
      assert_equal({ "other" => [1] }, replaced.fetch("user_data"), "a map replaces the whole map")
      replaced.fetch("user_data")["other"] << 2
      assert_equal({ "other" => [1] }, read(kind, id).fetch("user_data"), "a read hands out a detached map")

      write(entry(kind, id, {}))
      cleared = read(kind, id)
      assert_equal({}, cleared.fetch("user_data"))
      assert_equal values, cleared.fetch("values"), "a metadata write leaves every value as stored"
    end
  end

  def test_a_stale_target_refuses_the_whole_two_target_batch
    first = entry(MATERIAL, @material, { "batch" => true })
    stale = entry(ASSEMBLY, @assembly, { "batch" => true }, "user_data" => { "old" => true }, "extension_data" => {})
    revision = @session.revision
    result = write(first, stale)
    assert_equal %w[refused target.changed none], result.values_at("status", "code", "effect")
    assert_match(/Nothing was written\./, result.fetch("message"))
    assert_equal revision, @session.revision
    assert_equal({}, read(MATERIAL, @material).fetch("user_data"))
    assert_equal({}, read(ASSEMBLY, @assembly).fetch("user_data"))
  end

  def test_invalid_json_refuses_before_any_write
    revision = @session.revision
    [Float::NAN, Float::INFINITY].each do |number|
      result = write(entry(MATERIAL, @material, { "x" => number }))
      # The dispatcher checks params are plain JSON before any handler runs.
      assert_equal %w[refused request.malformed], result.values_at("status", "code"), result.inspect
    end
    result = write(entry(MATERIAL, @material, { 1 => "x" }))
    assert_equal %w[refused request.malformed], result.values_at("status", "code"), result.inspect
    assert_equal revision, @session.revision
    assert_equal({}, read(MATERIAL, @material).fetch("user_data"))

    # A Ruby caller staging through the engine itself gets the engine's own refusal.
    engine = PhComposer::Records::Engine.new(@model, PhComposer::Registry.current.catalog)
    proposal = PhComposer::Operations::Proposal.new
    error = assert_raises(PhComposer::CodedError) do
      engine.propose_metadata_update(MATERIAL, @material, proposal,
                                     entry(MATERIAL, @material, { "x" => Float::INFINITY }, EMPTY))
    end
    assert_equal "params.invalid", error.code
    assert proposal.empty?
    assert proposal.refusal, "a refused metadata proposal is refused whole"
  end

  def test_a_payload_may_name_a_record_staged_earlier_in_the_same_proposal
    engine = PhComposer::Records::Engine.new(@model, PhComposer::Registry.current.catalog)
    proposal = PhComposer::Operations::Proposal.new
    created = engine.propose_create(MATERIAL, proposal, :values => { "name" => "Fibre" })
    update = entry(MATERIAL, @material, {}).merge("extension_payloads" => { LINK => { "material_id" => created } })
    engine.propose_metadata_update(MATERIAL, @material, proposal, update)
    assert_equal created, proposal.find(MATERIAL, @material).after.dig("extension_data", LINK, "payload", "material_id")

    missing = update.merge("extension_payloads" => { LINK => { "material_id" => "mat_000000000000" } })
    error = assert_raises(PhComposer::CodedError) do
      engine.propose_metadata_update(MATERIAL, @material, PhComposer::Operations::Proposal.new, missing)
    end
    assert_equal "reference.invalid", error.code
  end

  def test_unicode_null_false_zero_and_empty_containers_round_trip
    value = { "名前" => "Wärmebrücke ✓", "null" => nil, "false" => false, "zero" => 0, "float" => 0.0,
              "object" => {}, "array" => [], "nested" => { "list" => [nil, false, 0, "", {}] } }
    assert_equal "committed", write(entry(MATERIAL, @material, value)).fetch("effect")
    stored = read(MATERIAL, @material).fetch("user_data")
    assert_equal value, stored
    assert_kind_of Float, stored.fetch("float")
    assert_kind_of Integer, stored.fetch("zero")
    detail = assignment_query("ph_composer.records.detail", "kind" => MATERIAL, "id" => @material,
                                                            "path" => %w[user_data null])
    assert_equal "null", detail.dig("fragment", "text")
  end

  def test_a_no_op_batch_adds_no_undo_step_and_a_real_batch_adds_exactly_one
    write(entry(MATERIAL, @material, { "kept" => true }))
    revision = @session.revision
    no_op = write(entry(MATERIAL, @material, { "kept" => true }), entry(ASSEMBLY, @assembly, {}))
    assert_equal %w[completed none], no_op.values_at("status", "effect"), no_op.inspect
    assert_equal revision, @session.revision

    batch = write(entry(MATERIAL, @material, { "batch" => 1 }), entry(ASSEMBLY, @assembly, { "batch" => 2 }))
    assert_equal "committed", batch.fetch("effect"), batch.inspect
    @model.undo
    assert_equal({ "kept" => true }, read(MATERIAL, @material).fetch("user_data"), "one Undo reverts both")
    assert_equal({}, read(ASSEMBLY, @assembly).fetch("user_data"))
    @model.undo
    assert_equal({}, read(MATERIAL, @material).fetch("user_data"), "the earlier write was its own step")
  end

  def test_an_attached_zone_update_keeps_its_assignments_valid
    assignment_zone(100)
    faces = assignment_faces
    created = assignment_invoke("#{ATTACHED}.create_and_assign",
                                "faces" => faces.map { |face| face.fetch("reference") },
                                "values" => { "name" => "Garage", "kind" => "garage" })
    assert_equal "committed", created.fetch("effect"), created.inspect
    id = created.dig("value", "id")
    before = assignment_faces.map { |face| face.fetch("values") }
    result = write(entry(ATTACHED, id, { "firm" => { "door" => "rated" } }))
    assert_equal "committed", result.fetch("effect"), result.inspect
    assert_equal({ "firm" => { "door" => "rated" } }, read(ATTACHED, id).fetch("user_data"))
    after = assignment_faces
    refute_empty after
    assert_equal before, after.map { |face| face.fetch("values") }
    assert(after.all? { |face| face.fetch("attached_zone_state") == "resolved" })
  end

  def test_a_payload_writes_beside_user_data_and_its_refusals_write_nothing
    payloads = { REVIEW => { "status" => "draft" } }
    result = write(entry(MATERIAL, @material, { "a" => 1 }).merge("extension_payloads" => payloads))
    assert_equal "committed", result.fetch("effect"), result.inspect
    assert_equal({ REVIEW => "understood" }, result.dig("value", "updates", 0, "extension_status"))
    stored = read(MATERIAL, @material)
    assert_equal({ "status" => "draft" }, stored.dig("extension_data", REVIEW, "payload"))
    revision = @session.revision
    { "validation.failed" => { REVIEW => { "status" => "unknown" } },
      "extension.unavailable" => { "absent.extension" => {} } }.each do |code, payloads|
      refused = write(entry(MATERIAL, @material, {}).merge("extension_payloads" => payloads))
      assert_equal code, refused.fetch("code"), refused.inspect
    end
    assert_equal revision, @session.revision
    assert_equal stored, read(MATERIAL, @material)
  end

  def test_a_batch_collapses_repeats_and_refuses_conflicts_or_an_entry_naming_nothing
    first = entry(MATERIAL, @material, { "a" => 1 })
    revision = @session.revision
    [[first, first.merge("user_data" => { "a" => 2 })], [first.reject { |key, _value| key == "user_data" }]]
      .each do |batch|
      assert_equal %w[refused params.invalid none], write(*batch).values_at("status", "code", "effect")
    end
    assert_equal revision, @session.revision
    repeated = write(first, first)
    assert_equal "committed", repeated.fetch("effect"), repeated.inspect
    assert_equal 1, repeated.dig("value", "updates").length
    assert_equal({ "a" => 1 }, read(MATERIAL, @material).fetch("user_data"))
  end

  def test_unknown_kinds_missing_records_and_owner_written_kinds_refuse
    values = { "name" => "Block", "colour" => "#1F7478" }
    segment = assignment_invoke("ph_composer.zones.options.create",
                                "collection" => "building_segment", "values" => values)
    assert_equal "committed", segment.fetch("effect"), segment.inspect
    settings = PhComposer::Zones::Options::SETTINGS_KIND
    settings_id = PhComposer::Zones::Options::SETTINGS_ID
    revision = @session.revision
    cases = {
      "params.invalid" => entry("probe.unknown.kind", @material, {}, EMPTY),
      "target.not_found" => entry(MATERIAL, "mat_Zz99Zz99Zz99", {}, EMPTY),
      "target.wrong_kind" => entry(settings, settings_id, { "x" => 1 }, EMPTY)
    }
    cases.each do |code, refused|
      result = write(entry(MATERIAL, @material, { "first" => true }), refused)
      assert_equal %w[refused none], result.values_at("status", "effect"), result.inspect
      assert_equal code, result.fetch("code"), result.inspect
    end
    assert_equal revision, @session.revision
    assert_equal({}, read(MATERIAL, @material).fetch("user_data"))
    assert_equal({}, read(settings, settings_id).fetch("user_data"))
  end

  def test_a_shared_follow_up_runs_once_per_batch_that_changes_its_kinds_under_their_owner
    PhComposer::Registry.install([FollowUp])
    ids = FollowUp::KINDS.to_h do |name, prefix|
      id = "#{prefix}_Ab12Cd34Ef56"
      PhComposer::Registry.current.catalog.kind(FollowUp.kind(name)).store
                          .write(@model, { "id" => id, "schema_version" => 1 })
      [name, id]
    end
    FollowUp::CALLS.clear
    both = write(entry(FollowUp.kind("one"), ids["one"], { "a" => 1 }, EMPTY),
                 entry(FollowUp.kind("two"), ids["two"], { "b" => 1 }, EMPTY))
    assert_equal "committed", both.fetch("effect"), both.inspect
    assert_equal [["probe.follow", ids.values_at("one", "two").sort]], FollowUp::CALLS

    FollowUp::CALLS.clear
    unchanged = write(entry(FollowUp.kind("one"), ids["one"], { "a" => 1 }))
    assert_equal "none", unchanged.fetch("effect"), unchanged.inspect
    other = write(entry(FollowUp.kind("three"), ids["three"], { "c" => 1 }, EMPTY))
    assert_equal "committed", other.fetch("effect"), other.inspect
    assert_empty FollowUp::CALLS, "a batch that changes nothing, or no kind with a follow-up, calls none"
  end

  def test_a_layer_and_a_layer_segment_map_write_read_back_and_clear_by_id_path
    layer, segment = layer_ids
    values = read(ASSEMBLY, @assembly).fetch("values")
    [[layer], [layer, segment]].each do |part_ids|
      result = write(part_entry(part_ids, { "firm" => { "tag" => part_ids.last } }))
      assert_equal "committed", result.fetch("effect"), result.inspect
      assert_equal [{ "reference" => { "kind" => ASSEMBLY, "id" => @assembly, "part_ids" => part_ids },
                      "extension_status" => {} }], result.dig("value", "updates")
      assert_equal({ "firm" => { "tag" => part_ids.last } }, part(part_ids).fetch("user_data"))
    end
    assert_equal({}, read(ASSEMBLY, @assembly).fetch("user_data"), "a part map is not the record's")
    rows = assignment_query("ph_composer.assemblies.assemblies.segments.list", "assembly_id" => @assembly)
    assert_equal({ "firm" => { "tag" => segment } }, rows.dig("segments", 0, "segment", "user_data"))

    [[layer], [layer, segment]].each { |part_ids| write(part_entry(part_ids, {})) }
    assert_equal({}, part([layer]).fetch("user_data"))
    assert_equal({}, part([layer, segment]).fetch("user_data"))
    assert_equal values.fetch("layers").length, read(ASSEMBLY, @assembly).dig("values", "layers").length
  end

  def test_a_batch_writing_a_record_and_several_of_its_parts_is_one_undo_step
    layer, segment = layer_ids
    batch = write(entry(ASSEMBLY, @assembly, { "record" => 1 }), part_entry([layer], { "layer" => 2 }),
                  part_entry([layer, segment], { "segment" => 3 }))
    assert_equal "committed", batch.fetch("effect"), batch.inspect
    assert_equal({ "record" => 1 }, read(ASSEMBLY, @assembly).fetch("user_data"))
    assert_equal({ "layer" => 2 }, part([layer]).fetch("user_data"))
    assert_equal({ "segment" => 3 }, part([layer, segment]).fetch("user_data"))
    revision = @session.revision
    same = write(part_entry([layer], { "layer" => 2 }), part_entry([layer, segment], { "segment" => 3 }))
    assert_equal %w[completed none], same.values_at("status", "effect"), same.inspect
    assert_equal revision, @session.revision
    @model.undo
    assert_equal({}, read(ASSEMBLY, @assembly).fetch("user_data"))
    refute part([layer]).key?("user_data")
    refute part([layer, segment]).key?("user_data")
  end

  def test_part_refusals_write_nothing_and_clearing_an_absent_part_map_is_a_no_op
    layer, segment = layer_ids
    stored = read(ASSEMBLY, @assembly)
    revision = @session.revision
    cleared = write(part_entry([layer], {}))
    assert_equal %w[completed none], cleared.values_at("status", "effect"), cleared.inspect
    refute part([layer]).key?("user_data"), "clearing a part stored without a map writes nothing"
    stale = { "user_data" => { "old" => true }, "extension_data" => {} }
    cases = {
      "target.not_found" => [part_entry(["lyr_Zz99Zz99Zz99"], { "x" => 1 }, EMPTY),
                             part_entry([layer, "seg_Zz99Zz99Zz99"], { "x" => 1 }, EMPTY),
                             part_entry([segment], { "x" => 1 }, EMPTY),
                             part_entry([layer, segment, segment], { "x" => 1 }, EMPTY),
                             { "reference" => { "kind" => MATERIAL, "id" => @material, "part_ids" => [layer] },
                               "user_data" => { "x" => 1 }, "expected_metadata" => EMPTY }],
      "target.changed" => [part_entry([layer], { "x" => 1 }, stale)],
      "params.invalid" => [part_entry([layer], { "x" => 1 }).merge("extension_payloads" => { REVIEW => {} })]
    }
    cases.each do |code, entries|
      entries.each do |refused|
        result = write(entry(MATERIAL, @material, { "first" => true }), refused)
        assert_equal [code, "none"], result.values_at("code", "effect"), result.inspect
      end
    end
    assert_equal revision, @session.revision
    assert_equal stored, read(ASSEMBLY, @assembly)
    assert_equal({}, read(MATERIAL, @material).fetch("user_data"))
  end

  def test_a_window_element_map_writes_reads_back_and_clears_by_element_id
    type = create("ph_composer.windows.types.create", "name" => "Window")
    element = read(WINDOW_TYPE, type).dig("values", "elements", 0, "id")
    map = { "firm" => { "detail" => "A-503/7", "note" => "Fenêtre à l'est", "zero" => 0, "no" => false,
                        "none" => nil, "empty" => {}, "list" => [] } }
    target = { "kind" => WINDOW_TYPE, "id" => type, "part_ids" => [element] }
    result = write({ "reference" => target, "user_data" => map, "expected_metadata" => EMPTY })
    assert_equal "committed", result.fetch("effect"), result.inspect
    assert_equal map, read(WINDOW_TYPE, type).dig("values", "elements", 0, "user_data")
    assert_equal({}, read(WINDOW_TYPE, type).fetch("user_data"), "an element map is not the Type's")
    rows = assignment_query("ph_composer.windows.types.elements.list", "type_id" => type)
    assert_equal map, rows.dig("elements", 0, "element", "user_data")
    assert_equal [{ "label" => "Element", "path" => "elements[]" }],
                 PhComposer::API.describe(:name => WINDOW_TYPE).fetch("parts")

    stale = write({ "reference" => target, "user_data" => {}, "expected_metadata" => EMPTY })
    assert_equal %w[target.changed none], stale.values_at("code", "effect"), stale.inspect
    write({ "reference" => target, "user_data" => {},
            "expected_metadata" => { "user_data" => map, "extension_data" => {} } })
    assert_equal({}, read(WINDOW_TYPE, type).dig("values", "elements", 0, "user_data"))
  end

  def test_the_assembly_kind_publishes_its_parts_and_a_bad_part_map_is_unreadable
    described = PhComposer::API.describe(:name => ASSEMBLY)
    assert_equal [{ "label" => "Layer", "path" => "layers[]" },
                  { "label" => "Layer-Segment", "path" => "layers[].segments[]" }], described.fetch("parts")
    assert_equal [], PhComposer::API.describe(:name => MATERIAL).fetch("parts")
    kind = PhComposer::Assemblies::Assembly::Schema::KIND
    record = kind.store.read(@model, @assembly)
    record["layers"][0]["segments"][0]["user_data"] = []
    assert_includes kind.problems(record).join(" "), "user_data"
    record["layers"][0]["segments"][0]["user_data"] = { "x" => Float::NAN }
    assert_includes kind.problems(record).join(" "), "user_data"
  end

  def test_update_actions_refuse_user_data_and_create_actions_keep_it
    id = create("ph_composer.assemblies.materials.create", { "name" => "Cork" }, { "firm" => { "kept" => true } })
    assert_equal({ "firm" => { "kept" => true } }, read(MATERIAL, id).fetch("user_data"))
    {
      "ph_composer.assemblies.materials.update" => { "id" => id, "values" => { "name" => "Cork board" },
                                                     "expected_values" => {} },
      "ph_composer.assemblies.assemblies.update" => { "id" => @assembly, "values" => { "name" => "Wall 2" },
                                                      "expected_values" => {} }
    }.each do |name, params|
      result = assignment_invoke(name, params.merge("user_data" => {}))
      assert_equal %w[refused params.invalid], result.values_at("status", "code"), name
      edited = assignment_invoke(name, params)
      assert_equal "committed", edited.fetch("effect"), edited.inspect
    end
    assert_equal({ "firm" => { "kept" => true } }, read(MATERIAL, id).fetch("user_data"), "an edit keeps the map")

    actions = PhComposer::Registry.current.actions
    %w[assemblies.materials assemblies.assemblies windows.frames windows.glazings windows.psi_install_types
       windows.types thermal_bridges.types].each do |prefix|
      assert actions.fetch("ph_composer.#{prefix}.create").params.fetch("properties").key?("user_data"), prefix
      refute actions.fetch("ph_composer.#{prefix}.update").params.fetch("properties").key?("user_data"), prefix
    end
    installs = actions.fetch("ph_composer.windows.types.installs.save").params
                      .dig("properties", "psi_install_types", "properties")
    assert installs.dig("create", "items", "properties").key?("user_data")
    refute installs.dig("update", "items", "properties").key?("user_data")
  end
end
