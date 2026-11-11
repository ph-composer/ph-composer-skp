# frozen_string_literal: true

require "digest"
require_relative "test_helper"
require_relative "support/assembly_assignment_fixtures"
require_relative "support/test_feature"
require_relative "support/agent_reads"

# Large definitions and metadata read completely through the agent connection (AW-04, contract C03,
# acceptance A07a): every reply goes through the real executor and fits its budget, and what the pages and
# fragments carry joins back to exactly what the whole read answers in process.
class DefinitionDetailTest < PhComposerTestCase
  include AssemblyAssignmentFixtures
  include AgentReads

  A = PhComposer::AgentAccess
  P = "ph_composer"
  MATERIALS = PhComposer::Assemblies::Materials::Schema
  ASSEMBLIES = PhComposer::Assemblies::Assembly::Schema
  # Multibyte text, escapes and a four-byte character, so fragment cuts land inside characters and escapes.
  TEXT = "Wärme \"Brücke\"\n漢字 🙂 tab\t\\ ".freeze

  def setup
    super
    assignment_setup
    PhComposer::Registry.install([TestFeature])
    @executor = A::Executor.new(:tools => A::Tools::TABLE)
    issued = A::Tokens.issue(:capabilities => %w[read model_write])
    @token = A::Tokens.snapshot.fetch(A::Tokens.digest(issued.fetch("token")))
  end

  def test_a_large_metadata_scalar_and_many_keys_reassemble_exactly
    large = (TEXT * 1200)[0, 30_000]
    many = Array.new(1500) { |index| ["key_#{index}", "#{TEXT}#{index}"] }.to_h
    user_data = { "large" => large, "nothing" => nil, "no" => false, "emoji" => "🙂" * 5000,
                  "control" => "\u0001" * 5000 }.merge(many)
    id = create_material("Large metadata", user_data)
    list = { "kind" => MATERIALS::KIND.id, "ids" => [id], "fields" => [] }

    assert_equal "request.response_too_large", query("#{P}.records.list", list).fetch("code")
    row = completed(query("#{P}.records.list", list.merge("metadata" => "summary"))).dig("records", 0)
    refute row.key?("user_data")
    assert_equal({ "keys" => user_data.length }.merge(PhComposer::Fragments.summary(user_data)),
                 row.dig("metadata", "user_data"))
    assert_equal CanonicalJson.generate("Large metadata").bytesize, row.dig("value_bytes", "name")

    assert_equal large, detail(MATERIALS::KIND.id, id, %w[user_data large])
    assert_equal "🙂" * 5000, detail(MATERIALS::KIND.id, id, %w[user_data emoji])
    assert_equal "\u0001" * 5000, detail(MATERIALS::KIND.id, id, %w[user_data control])
    assert_equal user_data, detail(MATERIALS::KIND.id, id, %w[user_data])
    assert_equal [nil, "null"], detail_type(MATERIALS::KIND.id, id, %w[user_data nothing])
    assert_equal [false, "boolean"], detail_type(MATERIALS::KIND.id, id, %w[user_data no])
    missing = query("#{P}.records.detail", "kind" => MATERIALS::KIND.id, "id" => id, "path" => %w[user_data absent])
    assert_equal "target.not_found", missing.fetch("code")
    outside = query("#{P}.records.detail", "kind" => MATERIALS::KIND.id, "id" => id, "path" => %w[id])
    assert_equal "params.invalid", outside.fetch("code")
  end

  def test_unavailable_extension_data_and_an_unreadable_record_stay_visible_without_their_payloads
    payload = { "notes" => TEXT * 1500 }
    id = "mat_#{'A' * 12}"
    record = MATERIALS.defaults("name" => "Preserved").merge("id" => id, "schema_version" => 1)
    record["extension_data"] = { "absent.extension" => { "schema_version" => 1, "payload" => payload,
                                                         "references" => [], "export_relevance" => "local_only" } }
    MATERIALS::KIND.store.write(@model, record)
    MATERIALS::KIND.store.write(@model, "id" => "mat_#{'B' * 12}", "schema_version" => 1)
    list = { "kind" => MATERIALS::KIND.id, "metadata" => "summary" }

    page = completed(query("#{P}.records.list", list))
    extensions = page.dig("records", 0, "metadata", "extension_data")
    assert_equal [1, { "unavailable" => 1 }], extensions.values_at("namespaces", "statuses")
    refute page.dig("records", 0).key?("extension_status")
    assert_equal({ "absent.extension" => "unavailable" }, detail(MATERIALS::KIND.id, id, %w[extension_status]))
    assert_equal [["mat_#{'B' * 12}", "record.unreadable"]], page.fetch("unreadable").map { |row|
      row.values_at("id", "code")
    }
    assert_equal 2, page.fetch("total")
    assert_equal payload, detail(MATERIALS::KIND.id, id, ["extension_data", "absent.extension", "payload"])
    unreadable = query("#{P}.records.detail", "kind" => MATERIALS::KIND.id, "id" => "mat_#{'B' * 12}",
                                              "path" => %w[values])
    assert_equal "record.unreadable", unreadable.fetch("code")
  end

  def test_a_fragment_of_a_value_that_changed_refuses_instead_of_mixing_versions
    id = create_material("Changing", "large" => TEXT * 1500)
    params = { "kind" => MATERIALS::KIND.id, "id" => id, "path" => %w[user_data large] }
    first = completed(query("#{P}.records.detail", params))
    refute_nil first.fetch("next_cursor")

    create_material("Someone else's edit")

    expired = query("#{P}.records.detail", params.merge("cursor" => first.fetch("next_cursor")))
    assert_equal "query.cursor_expired", expired.fetch("code")
    other = query("#{P}.records.detail", params.merge("path" => %w[user_data], "cursor" => first.fetch("next_cursor")))
    assert_equal "params.invalid", other.fetch("code")
    assert_equal TEXT * 1500, detail(MATERIALS::KIND.id, id, %w[user_data large])
  end

  def test_an_outside_catalog_kind_is_read_completely_through_the_generic_route
    kind = RecordFixtures::DEFINITION
    id = "tdf_#{'C' * 12}"
    kind.store.write(@model, "id" => id, "schema_version" => 1, "label" => "Outside",
                             "user_data" => { "note" => TEXT * 1500 })
    list = { "kind" => kind.id, "ids" => [id] }

    assert_equal "request.response_too_large", query("#{P}.records.list", list).fetch("code")
    row = completed(query("#{P}.records.list", list.merge("metadata" => "summary"))).dig("records", 0)
    assert_equal({ "label" => "Outside" }, row.fetch("values"))
    assert_equal({ "note" => TEXT * 1500 }, detail(kind.id, id, %w[user_data]))
  end

  def test_a_ten_by_ten_window_type_reads_its_elements_topology_and_product_uses_in_pages
    frame = assignment_invoke("#{P}.windows.frames.create", "values" => { "name" => "Shared frame" }).dig("value", "id")
    id = create_grid_type(frame)
    whole = completed(API.query(:context => @context, :name => "#{P}.windows.types.list",
                                :params => { "ids" => [id] })).dig("records", 0)
    stored = whole.dig("values", "elements")
    assert_equal "request.response_too_large",
                 query("#{P}.windows.types.list", "ids" => [id], "fields" => ["values"]).fetch("code")

    pages = pages_of("#{P}.windows.types.elements.list", { "type_id" => id }, "elements")
    rows = pages.flat_map { |page| page.fetch("elements") }
    display = whole.fetch("display")
    topology = display.fetch("install_topology")
    assert_equal stored, rows.map { |row| row.fetch("element") }
    assert_equal display.dig("thermal", "elements"), rows.map { |row| row.fetch("thermal") }
    assert_equal stored.map { |element| topology.fetch("edges")[element.fetch("id")] },
                 rows.map { |row| row.fetch("install_edges") }
    assert_equal stored.map { |element| topology.fetch("copy_slots").fetch(element.fetch("id")) },
                 rows.map { |row| row.fetch("copy_slot") }
    summary = pages.first.fetch("type")
    assert_equal display.fetch("thermal").reject { |key, _value| key == "elements" }, summary.fetch("thermal")
    assert_equal topology.fetch("copy_key"), summary.fetch("copy_key")
    assert_equal whole.fetch("findings").sort_by(&:to_s),
                 (summary.fetch("findings") + rows.flat_map { |row| row.fetch("findings") }).sort_by(&:to_s)
    assert_equal stored, detail(PhComposer::Windows::TYPE_KIND, id, %w[values elements])

    product = completed(API.query(:context => @context, :name => "#{P}.windows.frames.list",
                                  :params => { "ids" => [frame] })).dig("records", 0)
    assert_operator product.fetch("use_count"), :>=, 400
    assert_equal "request.response_too_large", query("#{P}.windows.frames.list", "ids" => [frame]).fetch("code")
    uses = pages_of("#{P}.windows.frames.uses.list", { "id" => frame }, "uses").flat_map { |page| page.fetch("uses") }
    assert_equal product.fetch("uses"), uses
  end

  def test_an_oversized_assembly_reads_its_layers_segments_and_material_uses_in_pages
    material = create_material("Mineral wool", {}, "conductivity_w_mk" => 0.035)
    layers = Array.new(30) do |layer|
      { "id" => format("lyr_%012d", layer), "thickness_mm" => 20.0,
        "segments" => Array.new(12) do |segment|
          { "id" => format("seg_%012d", segment), "width_mm" => 100.0, "material_id" => segment.even? ? material : nil,
            "is_continuous_insulation" => false, "steel_stud_spacing_mm" => nil }
        end }
    end
    created = assignment_invoke("#{P}.assemblies.assemblies.create",
                                "values" => { "name" => "Many layers", "layers" => layers })
    assert_equal "committed", created.fetch("effect"), created.inspect
    id = created.dig("value", "id")
    assert_equal "request.response_too_large",
                 query("#{P}.assemblies.assemblies.list", "ids" => [id], "fields" => ["values"]).fetch("code")

    layer_rows = pages_of("#{P}.assemblies.assemblies.layers.list", { "assembly_id" => id }, "layers")
                 .flat_map { |page| page.fetch("layers") }
    assert_equal layers.map { |layer| [layer.fetch("id"), layer.fetch("thickness_mm"), 12] },
                 layer_rows.map { |row| row.values_at("id", "thickness_mm", "segment_count") }
    segments = pages_of("#{P}.assemblies.assemblies.segments.list", { "assembly_id" => id }, "segments")
               .flat_map { |page| page.fetch("segments") }
    assert_equal layers.flat_map { |layer| layer.fetch("segments") }, segments.map { |row| row.fetch("segment") }
    assert_equal [[], ["assembly.segment_unassigned"]], segments.map { |row| row.fetch("flags") }.uniq
    assert_equal ["Mineral wool", nil], segments.map { |row| row.fetch("material_name") }.uniq
    one = completed(query("#{P}.assemblies.assemblies.segments.list",
                          "assembly_id" => id, "layer_id" => layers.last.fetch("id")))
    assert_equal [[29, 12]], [[one.dig("segments", 0, "layer_index"), one.fetch("total")]]
    assert_equal "target.not_found",
                 query("#{P}.assemblies.assemblies.segments.list", "assembly_id" => id,
                                                                   "layer_id" => "lyr_#{'Z' * 12}").fetch("code")

    write_assemblies_using(material, 600)
    ASSEMBLIES::KIND.store.write(@model, "id" => "asm_#{'B' * 12}", "schema_version" => 1)
    whole = completed(API.query(:context => @context, :name => "#{P}.assemblies.materials.list",
                                :params => { "ids" => [material] })).dig("records", 0)
    assert_equal "request.response_too_large",
                 query("#{P}.assemblies.materials.list", "ids" => [material]).fetch("code")
    use_pages = pages_of("#{P}.assemblies.materials.uses.list", { "material_id" => material }, "uses")
    assert_equal [1], use_pages.map { |page| page.fetch("unreadable") }.uniq
    uses = use_pages.flat_map { |page| page.fetch("uses") }
    assert_equal whole.fetch("uses").sort_by { |use| use.fetch("assembly_id") }, uses
  end

  def test_an_oversized_preview_keeps_its_digest_and_is_reviewed_in_full_then_applied
    old = create_material("Old")
    replacement = create_material("Replacement")
    write_assemblies_using(old, 400)
    action = { "name" => "#{P}.assemblies.materials.delete",
               "params" => { "id" => old, "replacement_id" => replacement } }
    whole = API.preview(:context => @context, :name => action.fetch("name"), :params => action.fetch("params"))
    assert_operator JSON.generate(whole).bytesize, :>, BUDGET
    revision = @session.revision

    compact = agent("preview", action)
    assert_equal %w[completed ok], compact.values_at("status", "code")
    assert_equal whole.fetch("proposal_digest"), compact.fetch("proposal_digest")
    assert_equal [nil, [], []], compact.values_at("value", "affected", "findings")
    assert_equal whole.fetch("affected").length, compact.dig("detail", "parts", "affected", "count")
    assert(compact.dig("detail", "parts").values.all? { |part| part.fetch("stable") })
    reviewed = PreviewParts::PARTS.to_h { |part| [part, preview_part(action, part, compact)] }
    assert_equal whole.slice(*PreviewParts::PARTS), reviewed
    assert_equal revision, @session.revision

    stray = agent("preview", action.merge("cursor" => "x"))
    assert_equal "params.invalid", stray.fetch("code")
    first = agent("preview", action.merge("part" => "affected"))
    create_material("Someone else's edit")
    expired = agent("preview", action.merge("part" => "affected", "cursor" => first.dig("value", "next_cursor")))
    assert_equal "query.cursor_expired", expired.fetch("code")

    again = agent("preview", action)
    applied = agent("invoke", action.merge("expected_revision" => again.fetch("revision"),
                                           "proposal_digest" => again.fetch("proposal_digest")))
    assert_equal %w[completed committed], applied.values_at("status", "effect")
  end

  def test_the_new_reads_change_nothing
    id = create_material("Still", "large" => TEXT * 1500)
    assembly = assignment_assembly("Still")
    frame = assignment_invoke("#{P}.windows.frames.create", "values" => { "name" => "Still" }).dig("value", "id")
    type = create_grid_type(frame)
    @model.instance_variable_set(:@modified, false)
    operations = @model.operations.length
    revision = @session.revision

    detail(MATERIALS::KIND.id, id, %w[user_data])
    completed(query("#{P}.records.list", "kind" => MATERIALS::KIND.id, "metadata" => "summary"))
    completed(query("#{P}.assemblies.materials.uses.list", "material_id" => id))
    completed(query("#{P}.assemblies.assemblies.layers.list", "assembly_id" => assembly))
    completed(query("#{P}.assemblies.assemblies.segments.list", "assembly_id" => assembly))
    completed(query("#{P}.windows.types.elements.list", "type_id" => type))
    completed(query("#{P}.windows.frames.uses.list", "id" => frame))
    agent("preview", "name" => "#{P}.assemblies.materials.delete", "params" => { "id" => id })
    agent("preview", "name" => "#{P}.assemblies.materials.delete", "params" => { "id" => id }, "part" => "affected")

    refute @model.modified?
    assert_equal [operations, revision], [@model.operations.length, @session.revision]
  end

  def test_a_fragment_never_splits_a_character_and_a_cursor_for_other_text_expires
    request = PreviewParts::Request.new(@session, {}, @session.revision)
    value = "é" * 10_000
    first, cursor = PhComposer::Fragments.read(request, "probe", value)
    # The canonical text opens with a one-byte quote, so the budget in raw bytes ends inside an é.
    assert_equal PhComposer::Fragments::MAX_TEXT_BYTES - 1, first.fetch("bytes")
    assert first.fetch("text").valid_encoding?

    request.params = { "cursor" => cursor }
    second, = PhComposer::Fragments.read(request, "probe", value)
    assert_equal first.fetch("bytes"), second.fetch("offset")
    error = assert_raises(PhComposer::CodedError) { PhComposer::Fragments.read(request, "probe", "#{value}x") }
    assert_equal "query.cursor_expired", error.code
    forged = JSON.parse(cursor.unpack1("m0")).merge("after" => [2, second.fetch("sha256")])
    request.params = { "cursor" => [JSON.generate(forged)].pack("m0") }
    error = assert_raises(PhComposer::CodedError) { PhComposer::Fragments.read(request, "probe", value) }
    assert_equal "params.invalid", error.code
  end

  def test_many_extension_namespaces_and_long_names_still_fit_one_row
    kind = RecordFixtures::DEFINITION
    id = "tdf_#{'E' * 12}"
    envelopes = Array.new(300) do |index|
      ["absent.extension_#{index}", { "schema_version" => 1, "payload" => {}, "references" => [],
                                      "export_relevance" => "local_only" }]
    end.to_h
    kind.store.write(@model, "id" => id, "schema_version" => 1, "label" => "Outside", "extension_data" => envelopes)
    row = completed(query("#{P}.records.list", "kind" => kind.id, "fields" => [], "metadata" => "summary"))
          .dig("records", 0)
    assert_equal({ "unavailable" => 300 }, row.dig("metadata", "extension_data", "statuses"))
    assert_equal envelopes, detail(kind.id, id, %w[extension_data])

    long = "n" * 30_000
    material = create_material(long)
    layer = { "id" => "lyr_#{'L' * 12}", "thickness_mm" => 50.0,
              "segments" => [{ "id" => "seg_#{'S' * 12}", "width_mm" => 100.0, "material_id" => material,
                               "is_continuous_insulation" => false, "steel_stud_spacing_mm" => nil }] }
    assembly = assignment_invoke("#{P}.assemblies.assemblies.create",
                                 "values" => { "name" => long, "layers" => [layer] }).dig("value", "id")
    segment = completed(query("#{P}.assemblies.assemblies.segments.list", "assembly_id" => assembly))
              .dig("segments", 0)
    assert_equal [256, ["material_name"]], [segment.fetch("material_name").length, segment.fetch("truncated")]
    use = completed(query("#{P}.assemblies.materials.uses.list", "material_id" => material)).dig("uses", 0)
    assert_equal ["name"], use.fetch("truncated")

    elements = Array.new(100) do |index|
      PhComposer::Windows::Types.blank(index / 10, index % 10, :identity => ->(_prefix) { format("wel_%012d", index) })
                                .merge("name" => "e" * 9_000)
    end
    type = assignment_invoke("#{P}.windows.types.create",
                             "values" => { "name" => "t" * 9_000, "rows_m" => [0.3] * 10, "columns_m" => [0.3] * 10,
                                           "elements" => elements }).dig("value", "id")
    rows = pages_of("#{P}.windows.types.elements.list", { "type_id" => type }, "elements")
    assert_equal [["element.name"]], rows.flat_map { |page| page.fetch("elements") }.map { |row| row["truncated"] }.uniq
    assert_equal ["name"], rows.first.dig("type", "truncated")
    assert_equal "e" * 9_000, detail(PhComposer::Windows::TYPE_KIND, type, ["values", "elements", 99, "name"])
  end

  # A create's ids derive from the session, revision, action and params (context/AGENT_INTERFACE.md, "Writes
  # with observable outcomes"), so its preview reads by part across calls and its invoke stages those ids.
  def test_a_preview_that_creates_records_reads_by_part_across_calls_and_its_invoke_names_the_same_ids
    parts = Array.new(800) { |index| { "label" => "Part #{index}", "length_mm" => 10.0 } }
    action = { "name" => "test.fixture.create", "params" => { "parts" => parts } }
    whole = API.preview(:context => @context, :name => action.fetch("name"), :params => action.fetch("params"))
    compact = agent("preview", action)
    assert_equal [nil, []], compact.values_at("value", "affected")
    assert_equal({ "value" => true, "affected" => true, "findings" => true },
                 compact.dig("detail", "parts").transform_values { |part| part.fetch("stable") })
    fragments = 0
    counted = ->(cursor) { preview_fragment(action, "value", cursor).tap { fragments += 1 } }
    assert_equal whole.fetch("value"), joined(counted, compact.dig("detail", "parts", "value"))
    assert_operator fragments, :>, 1
    assert_equal whole.fetch("affected"), preview_part(action, "affected", compact)

    created = assignment_invoke(action.fetch("name"), action.fetch("params"), compact.fetch("proposal_digest"))
    assert_equal "committed", created.fetch("effect"), created.inspect
    assert_equal whole.fetch("value"), created.fetch("value")
  end

  # `stable` still marks a part a second run answers differently, here a create given random ids.
  def test_a_preview_that_names_other_ids_each_run_marks_those_parts_unstable
    parts = Array.new(350) { |index| { "label" => "Part #{index}", "length_mm" => 10.0 } }
    random = ->(_session, _name, _params) { PhComposer::Records::Identity.method(:mint) }
    compact = PhComposer::HandlerRequest.stub(:proposal_ids, random) do
      agent("preview", "name" => "test.fixture.create", "params" => { "parts" => parts })
    end
    assert_equal({ "value" => false, "affected" => false, "findings" => true },
                 compact.dig("detail", "parts").transform_values { |part| part.fetch("stable") })
  end

  def test_preview_ids_differ_for_other_params_and_after_a_write
    one = { "parts" => [{ "label" => "Sill", "length_mm" => 1200.0 }] }
    other = { "parts" => [{ "label" => "Head", "length_mm" => 1200.0 }] }
    ids = lambda do |params|
      API.preview(:context => @context, :name => "test.fixture.create", :params => params).fetch("value")
    end
    first = ids.call(one)
    assert_equal first, ids.call(one)
    refute_equal first.fetch("part_ids"), ids.call(other).fetch("part_ids")
    refute_equal first.fetch("definition_id"), ids.call(other).fetch("definition_id")
    create_material("Someone else's edit")
    refute_equal first.fetch("part_ids"), ids.call(one).fetch("part_ids")
  end

  def test_a_duplicate_previewed_twice_and_invoked_names_the_same_ids
    parts = assignment_invoke("test.fixture.create", "parts" => [{ "label" => "Sill", "length_mm" => 1200.0 }] * 2)
            .dig("value", "part_ids")
    params = { "ids" => parts }
    preview = -> { API.preview(:context => @context, :name => "test.fixture.duplicate_parts", :params => params) }
    mapping = preview.call.fetch("value")
    assert_equal mapping, preview.call.fetch("value")
    assert_equal parts, mapping.fetch("mapping").keys
    assert_equal 2, mapping.fetch("mapping").values.uniq.length
    assert_equal mapping, assignment_invoke("test.fixture.duplicate_parts", params).fetch("value")
  end

  # A derived id already stored or staged is passed over for the next one in the sequence.
  def test_a_derived_id_already_reserved_is_skipped
    first = PhComposer::Records::Identity.sequence("session", 1) { { "n" => 1 } }.call("tpt")
    reserved = [first]
    taken = PhComposer::Records::Identity.sequence("session", 1) { { "n" => 1 } }
    second = PhComposer::Records::Identity.fresh("tpt", reserved, taken)
    refute_equal first, second
    assert_equal [first, second], reserved
    assert_match PhComposer::Records::Identity.pattern("tpt"), second
  end

  def test_an_unreadable_record_with_a_long_diagnostic_does_not_block_the_records_behind_it
    kind = RecordFixtures::DEFINITION
    kind.store.write(@model, "id" => "tdf_#{'A' * 12}", "schema_version" => 1, "label" => "Broken", "x" * 30_000 => 1)
    kind.store.write(@model, "id" => "tdf_#{'B' * 12}", "schema_version" => 1, "label" => "Valid")
    params = { "kind" => kind.id, "fields" => [], "metadata" => "summary", "limit" => 1 }
    pages = [completed(query("#{P}.records.list", params))]
    pages << completed(query("#{P}.records.list", params.merge("cursor" => pages.first.fetch("next_cursor"))))
    assert_nil pages.last.fetch("next_cursor")
    assert_equal [["tdf_#{'A' * 12}"], []], pages.map { |page| page.fetch("unreadable").map { |row| row.fetch("id") } }
    assert_equal [[], ["tdf_#{'B' * 12}"]], pages.map { |page| page.fetch("records").map { |row| row.fetch("id") } }
  end

  def test_a_long_key_is_read_without_echoing_its_path
    key = "k" * 14_000
    id = create_material("Long key", key => TEXT * 400)
    assert_equal TEXT * 400, detail(MATERIALS::KIND.id, id, ["user_data", key])
  end

  def test_an_incomplete_window_type_with_an_empty_element_reads_null_results
    elements = [PhComposer::Windows::Types.blank(0, 0),
                PhComposer::Windows::Types.blank(1, 0).merge("kind" => "empty")]
    created = assignment_invoke("#{P}.windows.types.create",
                                "values" => { "name" => "Incomplete", "rows_m" => [0.5, nil], "columns_m" => [0.8],
                                              "elements" => elements })
    assert_equal "committed", created.fetch("effect"), created.inspect
    page = completed(query("#{P}.windows.types.elements.list", "type_id" => created.dig("value", "id")))

    assert_equal [false, nil], page.fetch("type").values_at("complete", "height_m")
    assert_equal [nil, nil], page.fetch("elements").map { |row| row.fetch("thermal") }
    assert_nil page.dig("elements", 1, "install_edges")
    assert_includes page.dig("type", "findings").map { |finding| finding.fetch("code") },
                    "window_type.dimensions_incomplete"
  end

  private

  PreviewParts = PhComposer::PreviewParts
  CanonicalJson = PhComposer::CanonicalJson

  def detail(kind, id, path)
    params = { "kind" => kind, "id" => id, "path" => path }
    joined(->(cursor) { completed(query("#{P}.records.detail", params.merge(cursor ? { "cursor" => cursor } : {}))) })
  end

  def detail_type(kind, id, path)
    value = completed(query("#{P}.records.detail", "kind" => kind, "id" => id, "path" => path))
    [JSON.parse(value.dig("fragment", "text"), :quirks_mode => true), value.fetch("type")]
  end

  def preview_part(action, part, compact)
    joined(lambda do |cursor|
      value = preview_fragment(action, part, cursor)
      assert_equal compact.fetch("proposal_digest"), value.fetch("proposal_digest")
      value
    end, compact.dig("detail", "parts", part))
  end

  def preview_fragment(action, part, cursor)
    arguments = action.merge("part" => part)
    arguments["cursor"] = cursor if cursor
    completed(agent("preview", arguments))
  end

  def create_material(name, user_data = {}, values = {})
    created = assignment_invoke("#{P}.assemblies.materials.create", "values" => { "name" => name }.merge(values),
                                                                    "user_data" => user_data)
    assert_equal "committed", created.fetch("effect"), created.inspect
    created.dig("value", "id")
  end

  # Direct store writes are test setup only, equivalent to creating each Assembly at an earlier revision.
  def write_assemblies_using(material, count)
    count.times do |index|
      layer = ASSEMBLIES.layer(100.0, :identity => ->(prefix) { format("#{prefix}_%012d", index) })
      layer.fetch("segments").first["material_id"] = material
      values = ASSEMBLIES.defaults({ "name" => "User #{index}" }, :identity => ->(prefix) { "#{prefix}_#{'D' * 12}" })
      ASSEMBLIES::KIND.store.write(@model, values.merge("id" => format("asm_%012d", index), "schema_version" => 1,
                                                        "layers" => [layer]))
    end
  end

  def create_grid_type(frame)
    elements = Array.new(100) do |index|
      element = PhComposer::Windows::Types.blank(index / 10, index % 10,
                                                 :identity => ->(_prefix) { format("wel_%012d", index) })
      element.merge("frames" => PhComposer::Windows::Types::SIDES.to_h { |side| [side, frame] })
    end
    created = assignment_invoke("#{P}.windows.types.create",
                                "values" => { "name" => "Grid", "rows_m" => [0.3] * 10, "columns_m" => [0.3] * 10,
                                              "elements" => elements })
    assert_equal "committed", created.fetch("effect"), created.inspect
    created.dig("value", "id")
  end
end
