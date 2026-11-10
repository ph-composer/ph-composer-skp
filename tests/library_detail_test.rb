# frozen_string_literal: true

require_relative "test_helper"
require_relative "support/library_provider_fixtures"
require_relative "support/assembly_record_fixtures"
require_relative "support/agent_reads"
require_relative "../tools/examples/library_provider/bldgtyp_example_library/install"

# Library catalogs, comparisons and exports read completely through the agent connection
# (context/AGENT_INTERFACE.md, "Focused reads"): every reply goes through the real executor and fits its
# budget, the compact forms keep the state, identity and counts, and the notes, row parts and omissions they
# leave out page or fragment back to exactly what the whole read answers in process, each bound to the
# generation, revision or projection it was read from.
class LibraryDetailTest < PhComposerTestCase
  include LibraryProviderFixtures
  include AssemblyRecordFixtures
  include AgentReads

  A = PhComposer::AgentAccess
  L = "ph_composer.library"
  TEXT = "Wärme \"Dämmung\"\n漢字 🙂 tab\t\\ ".freeze
  SELECTED = { "provider_id" => "synthetic.file", "kind" => "materials" }.freeze

  def setup
    super
    @directory = Dir.mktmpdir("library-detail")
    @path = File.join(@directory, "synthetic.json")
    write_library(@path)
    PhComposer::Library::Setup.add_file(:id => "synthetic.file", :label => "Synthetic", :path => @path)
    @session = PhComposer::Sessions.for(Sketchup.active_model)
    @context = PhComposer::API.connect(:session_id => @session.id, :capabilities => %w[read view model_write setup])
    @executor = A::Executor.new(:tools => A::Tools::TABLE)
    issued = A::Tokens.issue(:capabilities => %w[read model_write setup export])
    @token = A::Tokens.snapshot.fetch(A::Tokens.digest(issued.fetch("token")))
    @replies = []
    @sequence = 0
  end

  def teardown
    FileUtils.rm_rf(@directory)
    super
  end

  # Every reply is kept, so a test can check that none carries a private string.
  def agent(tool, arguments)
    super.tap { |content| @replies << JSON.generate(content) }
  end

  def load(compact: true)
    agent("setup", "name" => "#{L}.load", "params" => SELECTED.merge(compact ? { "compact" => true } : {}))
  end

  def whole(name, params = SELECTED)
    PhComposer::API.query(:context => @context, :name => name, :params => params).fetch("value")
  end

  def invoke(name, params, digest = nil)
    @sequence += 1
    request = { "sequence" => @sequence, "expected_revision" => @session.revision }
    request["proposal_digest"] = digest if digest
    PhComposer::API.invoke(:context => @context, :name => name, :params => params, :request => request)
  end

  def refute_private(*strings)
    @replies.each { |reply| strings.each { |text| refute_includes reply, text } }
  end

  def test_350_rejected_rows_load_compactly_and_every_warning_pages_bound_to_the_generation
    write_library(@path, envelope([library_row] + Array.new(350, false)))

    whole_load = load(:compact => false)
    assert_equal [nil, %w[value affected findings]], [whole_load["value"], whole_load.dig("detail", "omitted")]
    loaded = completed(load)
    assert_equal %w[loaded 0], loaded.values_at("state", "unavailable_total").map(&:to_s)
    refute loaded.key?("warnings")
    generation = loaded.fetch("generation")
    selected = SELECTED.merge("generation" => generation)

    assert_equal "request.response_too_large", query("#{L}.catalog", selected.merge("limit" => 1)).fetch("code")
    %w[catalog in_file].each do |read|
      page = completed(query("#{L}.#{read}", selected.merge("compact" => true, "limit" => 1)))
      assert_equal [1, loaded.fetch("warning_total"), generation],
                   page.values_at("total", "warning_total", "generation")
      refute page.dig("rows", 0).key?("snapshot")
    end
    expected = whole("#{L}.catalog", selected)
    warnings = rows_of("#{L}.warnings.list", selected.merge("limit" => 500), "warnings", :pages => 2)
    assert_equal expected.fetch("warnings"), warnings
    assert_equal loaded.fetch("warning_total"), warnings.length
    assert_equal 350, warnings.count { |note| note.fetch("code") == "library.row_required_invalid" }
    assert_equal [0, []], completed(query("#{L}.unavailable.list", selected)).values_at("total", "unavailable")

    first = completed(query("#{L}.warnings.list", selected.merge("limit" => 500).reject { |key, _|
      key == "generation"
    }))
    completed(load)
    stale = query("#{L}.warnings.list", SELECTED.merge("limit" => 500, "cursor" => first.fetch("next_cursor")))
    assert_equal "query.cursor_expired", stale.fetch("code")
    assert_equal "library.catalog_stale", query("#{L}.warnings.list", selected).fetch("code")
    refute_private @directory
  end

  ROW = { "library_id" => "synthetic.one", "record_id" => "public-1" }.freeze
  NOTES = (TEXT * 1_100).freeze

  # A catalog of one valid row with a 30 KB note and a 400-character name: [its params, the row's params].
  def large_note_catalog(notes = NOTES)
    write_library(@path, envelope([library_row.merge("notes" => notes, "name" => "N" * 400)]))
    SELECTED.merge("generation" => completed(load).fetch("generation"))
  end

  def test_a_30_kb_note_and_a_long_name_read_exactly_bound_to_the_generation
    params = large_note_catalog
    assert_equal "request.response_too_large", query("#{L}.catalog", params.merge("limit" => 1)).fetch("code")
    compact = completed(query("#{L}.catalog", params.merge("compact" => true))).dig("rows", 0)
    assert_equal [256, ["display_label"]], [compact.fetch("display_label").length, compact.fetch("truncated")]
    snapshot = fragments_of("#{L}.catalog.detail", params.merge(ROW, "path" => ["snapshot"]),
                            compact.fetch("snapshot_summary"))
    assert_equal whole("#{L}.catalog", params).dig("rows", 0, "snapshot"), snapshot
    assert_equal NOTES, fragments_of("#{L}.catalog.detail", params.merge(ROW, "path" => %w[snapshot notes]))
    assert_equal "N" * 400, fragments_of("#{L}.catalog.detail", params.merge(ROW, "path" => ["display_label"]))

    first = completed(query("#{L}.catalog.detail", SELECTED.merge(ROW, "path" => %w[snapshot notes])))
    completed(load)
    stale = query("#{L}.catalog.detail", SELECTED.merge(ROW, "path" => %w[snapshot notes],
                                                             "cursor" => first.fetch("next_cursor")))
    assert_equal "query.cursor_expired", stale.fetch("code")
    assert_equal "library.row_unavailable",
                 query("#{L}.catalog.detail", SELECTED.merge(ROW, "record_id" => "missing", "path" => ["snapshot"]))
                   .fetch("code")
    assert_equal "params.invalid", query("#{L}.catalog.detail", SELECTED.merge(ROW, "path" => ["record_id"]))
      .fetch("code")
    refute_private @directory
  end

  # The local copy of the large row, then the library's changed edition reloaded: [the copy's id, the reviewed
  # comparison's expected_values read through in_file.detail, the params at the new generation].
  def reviewed_comparison
    create = large_note_catalog.merge(ROW, "choice" => "create")
    # A create names a fresh id each run, but its preview stays whole: no candidates, references only.
    refute_nil agent("preview", "name" => "#{L}.copy", "params" => create).fetch("value")
    created = invoke("#{L}.copy", create)
    assert_equal "committed", created.fetch("effect"), created.inspect
    local = created.dig("value", "local_id")
    params = large_note_catalog(NOTES.reverse)
    candidate = completed(query("#{L}.in_file", params.merge("compact" => true))).dig("rows", 0, "resolution",
                                                                                      "candidates", 0)
    assert_equal [local, ["notes"], true], candidate.values_at("id", "difference_fields", "source_changed")
    expected = fragments_of("#{L}.in_file.detail",
                            params.merge(ROW, "path" => ["resolution", "candidates", 0, "expected_values"]),
                            candidate.fetch("expected_values_summary"))
    assert_equal whole("#{L}.in_file", params).dig("rows", 0, "resolution", "candidates", 0, "expected_values"),
                 expected
    [local, expected, params]
  end

  def test_a_reviewed_comparison_guards_a_large_compound_replacement_read_whole_before_apply
    local, expected, params = reviewed_comparison
    assembly = fixture_assembly([[100.0, [[600.0, nil]]]])
    Assemblies::Assembly::Schema::KIND.store.write(Sketchup.active_model, assembly)
    layer = assembly.dig("layers", 0)
    segment = { "id" => assembly.fetch("id"), "layer_id" => layer.fetch("id"),
                "segment_id" => layer.dig("segments", 0, "id"), "expected_values" => {} }
    replace = params.merge(ROW, "choice" => "use_library", "local_id" => local, "expected_values" => expected,
                                "assignment" => segment)
    preview = agent("preview", "name" => "#{L}.copy", "params" => replace)
    assert_nil preview.fetch("value")
    in_process = PhComposer::API.preview(:context => @context, :name => "#{L}.copy", :params => replace)
    preview.dig("detail", "parts").each do |part, summary|
      assert summary.fetch("stable"), part
      read = lambda do |cursor|
        completed(agent("preview", { "name" => "#{L}.copy", "params" => replace, "part" => part }
                                     .merge(cursor ? { "cursor" => cursor } : {})))
      end
      assert_equal in_process.fetch(part), joined(read, summary)
    end
    applied = invoke("#{L}.copy", replace, preview.fetch("proposal_digest"))
    assert_equal "committed", applied.fetch("effect"), applied.inspect
    assert_equal NOTES.reverse, Assemblies::Materials::Schema::KIND.store.read(Sketchup.active_model, local)["notes"]
    stored = Assemblies::Assembly::Schema::KIND.store.read(Sketchup.active_model, assembly.fetch("id"))
    assert_equal local, stored.dig("layers", 0, "segments", 0, "material_id")

    first = completed(query("#{L}.in_file.detail", params.merge(ROW, "path" => ["resolution"])))
    invoke("#{Assemblies::FEATURE_ID}.materials.create", "values" => { "name" => "Another" })
    stale = query("#{L}.in_file.detail", params.merge(ROW, "path" => ["resolution"],
                                                           "cursor" => first.fetch("next_cursor")))
    assert_equal "query.cursor_expired", stale.fetch("code")
    refute_private @directory
  end

  # 180 Materials whose user_data an export leaves out, and an approved destination already holding a file.
  def omitted_materials
    kind = Assemblies::Materials::Schema::KIND
    180.times do |index|
      values = Assemblies::Materials::Schema.defaults("name" => "Synthetic #{index}")
      kind.store.write(Sketchup.active_model, values.merge("id" => format("mat_%012d", index), "schema_version" => 1,
                                                           "user_data" => { "internal" => "x" }))
    end
    PhComposer::ApprovedLocations.approve(:kind => "save_file", :path => @path).fetch("id")
  end

  def test_an_all_scope_export_with_180_omissions_previews_compactly_and_pages_against_its_projection
    location = omitted_materials
    assert_equal "request.response_too_large", query("#{L}.export_preview", "location" => location).fetch("code")
    preview = completed(query("#{L}.export_preview", "location" => location, "compact" => true))
    assert_equal [180, "all", true], [preview.fetch("omission_total"), preview.fetch("scope"),
                                      preview.dig("destination", "exists")]
    digest = preview.fetch("projection_digest")
    reviewed = { "projection_digest" => digest, "limit" => 500 }
    pages = pages_of("#{L}.export_preview.omissions", reviewed, "omissions")
    assert_operator pages.length, :>=, 2
    assert(pages.all? { |page| page.fetch("projection_digest") == digest })
    assert_equal whole("#{L}.export_preview", {}).fetch("omissions"), pages.flat_map { |page| page.fetch("omissions") }

    cursor = pages.first.fetch("next_cursor")
    unreviewed = completed(query("#{L}.export_preview.omissions", "limit" => 500)).fetch("next_cursor")
    selected = { "scope" => "selected", "records" => [{ "record_kind" => Assemblies::MATERIAL_KIND,
                                                        "id" => "mat_000000000000" }] }
    assert_equal "params.invalid",
                 query("#{L}.export_preview.omissions",
                       selected.merge("limit" => 500, "cursor" => cursor)).fetch("code")
    kind = Assemblies::Materials::Schema::KIND
    kind.store.write(Sketchup.active_model, kind.store.read(Sketchup.active_model, "mat_000000000000")
                                                .merge("name" => "Changed after review"))
    assert_equal "revision.stale",
                 query("#{L}.export_preview.omissions", reviewed.merge("cursor" => cursor)).fetch("code")
    later = query("#{L}.export_preview.omissions", "limit" => 500, "cursor" => unreviewed)
    assert_equal "query.cursor_expired", later.fetch("code")
    refute_private @directory
  end

  def test_a_compact_export_replaces_from_its_review_and_names_the_state_it_wrote
    location = omitted_materials
    preview = completed(query("#{L}.export_preview", "location" => location, "compact" => true))
    digest = preview.fetch("projection_digest")
    approved = { "id" => location, "replace" => true, "expected_destination" => preview.dig("destination", "state") }
    export = { "location" => approved, "projection_digest" => digest, "compact" => true }
    written = completed(agent("export_file", "name" => "#{L}.export_file", "params" => export))
    assert_equal [true, 180, digest], written.values_at("written", "omission_total", "projection_digest")
    after = completed(query("#{L}.export_preview", "location" => location, "compact" => true))
    assert_equal written.fetch("destination_state"), after.dig("destination", "state")
    parsed = PhComposer::Library::LibraryFile.parse(File.binread(@path), :adapters => lambda do |wire|
      PhComposer::Library::State.kind(wire, PhComposer::Registry.current).adapter
    end)
    assert_equal [written.fetch("library_id"), 180],
                 [parsed.dig("library", "id"), parsed.dig("rows", "materials").length]

    changed = export.merge("location" => approved.merge("expected_destination" => "0" * 64))
    stale = agent("export_file", "name" => "#{L}.export_file", "params" => changed)
    assert_equal %w[refused library.destination_changed], stale.values_at("status", "code")
    assert_equal written.fetch("destination_state"), PhComposer::Library::FileWriter.state(@path)
    refute_private @directory, @path
  end

  # A hosted (version 2) catalog read compactly while it loads and once ready, its notes and a row's part:
  # no reply names the credential the connection stores or its connection identity.
  def test_a_hosted_catalog_reads_compactly_without_its_credential
    PhComposer::Registry.install([HostedLibraryFixtures::Feature])
    server = HostedLibraryFixtures.server
    PhComposer::Library::Connection::Manager.clock = -> { 100.0 }
    declaration = PhComposer::Registry.current.library_providers.fetch(HostedLibraryFixtures::PROVIDER_KIND)
    PhComposer::Library::Connection::Manager.connection(declaration).finish_sign_in("connection-secret-id")
    hosted = { "provider_id" => HostedLibraryFixtures::PROVIDER_ID, "kind" => "materials" }

    loading = completed(agent("setup", "name" => "#{L}.load", "params" => hosted.merge("compact" => true)))
    assert_equal %w[loading 0 0], loading.values_at("state", "warning_total", "unavailable_total").map(&:to_s)
    row = { "id" => "rec-1", "name" => "Hosted insulation", "conductivity_w_mk" => 0.035, "notes" => TEXT * 900 }
    server.response = Class.new { include HostedLibraryFixtures }.new.hosted_response(:rows => [row])
    UI.run_timers
    page = completed(query("#{L}.catalog", hosted.merge("compact" => true)))
    assert_equal ["ready", 1, "snap-1"], [page.fetch("state"), page.fetch("total"), page.dig("snapshot", "id")]
    notes = completed(query("#{L}.warnings.list", hosted))
    assert_equal [page.fetch("warning_total"), whole("#{L}.catalog", hosted).fetch("warnings")],
                 notes.values_at("total", "warnings")
    part = hosted.merge("library_id" => "firm-lib", "record_id" => "rec-1", "path" => %w[snapshot notes])
    assert_equal TEXT * 900, fragments_of("#{L}.catalog.detail", part)
    assert_equal TEXT * 900, fragments_of("#{L}.in_file.detail", part)
    refute_private "synthetic-refresh", "connection-secret-id"
  end

  def test_in_file_pages_bind_the_revision_and_a_compact_comparison_caps_its_candidates
    write_library(@path, envelope(%w[public-1 public-2 public-3].map { |id| library_row(id) }))
    params = SELECTED.merge("generation" => completed(load).fetch("generation"), "compact" => true, "limit" => 1)
    kind = Assemblies::Materials::Schema::KIND
    25.times do |index|
      values = Assemblies::Materials::Schema.defaults("name" => "Synthetic insulation")
      kind.store.write(Sketchup.active_model, values.merge("id" => format("mat_%012d", index), "schema_version" => 1))
    end
    page = completed(query("#{L}.in_file", params))
    resolution = page.dig("rows", 0, "resolution")
    assert_equal [20, 25], [resolution.fetch("candidates").length, resolution.fetch("candidate_total")]
    last = fragments_of("#{L}.in_file.detail", params.slice("provider_id", "kind", "generation")
                                                     .merge(ROW, "path" => ["resolution", "candidates", 24]))
    assert_equal whole("#{L}.in_file", params.slice("provider_id", "kind")).dig("rows", 0, "resolution",
                                                                                "candidates", 24), last

    catalog = completed(query("#{L}.catalog", params))
    invoke("#{Assemblies::FEATURE_ID}.materials.create", "values" => { "name" => "Edited meanwhile" })
    assert_equal %w[public-2], completed(query("#{L}.catalog", params.merge("cursor" => catalog.fetch("next_cursor"))))
      .fetch("rows").map { |row| row.fetch("record_id") }
    assert_equal "query.cursor_expired",
                 query("#{L}.in_file", params.merge("cursor" => page.fetch("next_cursor"))).fetch("code")
  end

  # An extension enabled between pages adds a library kind to an all-kinds export: the projection changes at the
  # same Model revision, and the next page of the old one refuses.
  def test_an_omission_page_of_a_changed_projection_refuses_at_the_same_revision
    omitted_materials
    first = completed(query("#{L}.export_preview.omissions", "limit" => 1))
    revision = @session.revision
    assert BldgtypExampleLibrary.activate
    assert_equal revision, @session.revision
    refute_equal first.fetch("projection_digest"),
                 completed(query("#{L}.export_preview", "compact" => true)).fetch("projection_digest")
    stale = query("#{L}.export_preview.omissions", "limit" => 1, "cursor" => first.fetch("next_cursor"))
    assert_equal "query.cursor_expired", stale.fetch("code")
  end
end
