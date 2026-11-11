# frozen_string_literal: true

require_relative "test_helper"
require_relative "support/test_feature"
require_relative "../tools/examples/library_provider/bldgtyp_example_library/install"

# The connection's bounded discovery (context/AGENT_INTERFACE.md, "Discover before acting"): every
# section a client can page, each row reachable by `describe`, every page within one reply however many
# features are installed, cursors bound to what is registered, and the outside synthetic feature and
# library kind described with no change to the transport.
class AgentAccessDiscoveryTest < PhComposerTestCase
  AgentAccess = PhComposer::AgentAccess
  Discovery = AgentAccess::Discovery
  BUDGET = AgentAccess::Executor::MAX_RESULT_BYTES
  # Each list section's rows, by the key `describe` takes.
  DESCRIBED_BY = { "operations" => "name", "record_kinds" => "id", "reference_targets" => "id",
                   "extensions" => "namespace", "library_kinds" => "name" }.freeze

  def setup
    super
    PhComposer.compose
    PhComposer::Registry.install([TestFeature])
    @session = PhComposer::Sessions.for(Sketchup.active_model)
    @executor = AgentAccess::Executor.new(:tools => AgentAccess::Tools::TABLE)
    @reader = token(%w[read])
  end

  def token(capabilities, **options)
    issued = AgentAccess::Tokens.issue(:capabilities => capabilities, **options)
    AgentAccess::Tokens.snapshot.fetch(AgentAccess::Tokens.digest(issued.fetch("token")))
  end

  def discover(arguments = {}, row = @reader)
    result = @executor.call(row, "discover", arguments)
    assert_operator JSON.generate(result.fetch("structuredContent")).bytesize, :<=, BUDGET
    result
  end

  def page(arguments)
    result = discover(arguments)
    refute result["isError"], result.inspect
    result.fetch("structuredContent")
  end

  # Every row of a list section, following its cursors; every page within the reply budget.
  def all_rows(section, **filter)
    rows = []
    cursor = nil
    loop do
      found = page({ "section" => section, "cursor" => cursor }.merge(filter.transform_keys(&:to_s)).compact)
      rows.concat(found.fetch("rows"))
      cursor = found.fetch("next_cursor")
      break unless cursor
    end
    rows
  end

  def test_every_installed_kind_target_extension_and_library_kind_is_listed_and_described
    document = PhComposer::API.discover
    shipped = %w[record_kinds reference_targets].to_h do |section|
      [section, document.fetch(section).reject { |row| row.fetch("owner") == TestFeature::ID }.length]
    end

    assert_equal({ "record_kinds" => 11, "reference_targets" => 9 }, shipped)
    DESCRIBED_BY.each do |section, key|
      rows = all_rows(section)
      unless section == "operations"
        assert_equal document.fetch(section), rows, section
        assert_equal rows.length, page("section" => section).fetch("total")
      end
      rows.each do |row|
        result = @executor.call(@reader, "describe", "name" => row.fetch(key))
        described = result.fetch("structuredContent")
        refute result["isError"], "#{section} #{row.fetch(key)}"
        assert_nil described["status"], "#{section} #{row.fetch(key)} answered an outcome"
        assert_equal row.fetch(key), described.fetch(key), "#{section} #{row.fetch(key)}"
      end
    end
    assert_includes all_rows("record_kinds").map { |row| row.fetch("id") }, "test.fixture.part"
    assert_equal ["test.fixture.review"], all_rows("extensions").map { |row| row.fetch("namespace") }
  end

  def test_an_extension_describes_its_installed_contract_and_never_an_invented_schema
    described = @executor.call(@reader, "describe", "name" => "test.fixture.review").fetch("structuredContent")
    listed = page("section" => "extensions")

    assert_equal ["extension", TestFeature::ID, 2, [1]],
                 described.values_at("kind", "owner", "schema_version", "migrates_from")
    assert_nil described.fetch("payload_schema")
    assert_equal PhComposer::Records::Extension::STATUSES, described.fetch("statuses").keys
    assert_equal PhComposer::Records::Extension::STATUSES, listed.fetch("statuses").keys
    unmigrated = PhComposer::Records::Extension.new(:namespace => "test.fixture.review", :schema_version => 3)
    envelope = { "schema_version" => 1, "payload" => {}, "references" => [], "export_relevance" => "unknown" }
    assert_equal "unsupported", PhComposer::Records::Extension.status(envelope, unmigrated)
    assert_includes described.dig("statuses", "unsupported"), "older one the installed migrations cannot raise"
  end

  def test_operations_page_by_owner_and_kind_and_carry_no_participant
    rows = all_rows("operations", :owner => TestFeature::ID)
    every = all_rows("operations")

    assert_equal PhComposer::API.discover.values_at("queries", "view_commands", "setup_commands", "file_exports",
                                                    "actions").sum(&:length), every.length
    assert(rows.all? { |row| row.fetch("owner") == TestFeature::ID })
    assert_includes rows, { "kind" => "query", "name" => "test.fixture.total_length", "owner" => TestFeature::ID,
                            "description" => "Total part length." }
    refute_includes every.map { |row| row.fetch("kind") }, "participant"
  end

  # An outside adapter registered by the synthetic provider extension: its assignment target comes from
  # its own callback, and the transport has no entry for it.
  def test_an_outside_library_kind_is_described_from_its_own_registration
    BldgtypExampleLibrary.activate
    rows = all_rows("library_kinds")
    tags = rows.find { |row| row.fetch("wire_kind") == "tags" }
    described = @executor.call(@reader, "describe", "name" => tags.fetch("name")).fetch("structuredContent")

    assert_equal 5, rows.length
    assert_equal true, tags.fetch("assignment_supported")
    assert_equal({ "type" => "object", "required" => ["id"], "properties" => { "id" => { "type" => "string" } } },
                 described.dig("assignment", "target").slice("type", "required", "properties"))
    assert_equal [{ "id" => "bth_Ab12Cd34Ef56" }], described.dig("assignment", "examples")
    %w[discovery.rb tools.rb executor.rb].each do |file|
      refute_match(/tags|materials|frames/, File.read(File.join(SOURCE_ROOT, "ph_composer", "agent_access", file)))
    end
  end

  def test_refusals_give_every_common_code_a_meaning_the_contract_lists
    found = page("section" => "refusals")
    contract = File.read(File.expand_path("../context/CONTRACTS.md", __dir__))[/^## Outcomes and codes\n.*?(?=^## )/m]
    codes = PhComposer::Refusals::COMMON.values.flatten.uniq

    assert_equal PhComposer::Refusals::COMMON, found.fetch("sets")
    assert_equal codes.sort, found.fetch("codes").map { |row| row.fetch("code") }
    assert_equal codes.sort, PhComposer::Refusals::MEANINGS.keys.sort
    assert(found.fetch("codes").all? { |row| row.fetch("description").is_a?(String) })
    assert_empty(codes.reject { |code| contract.include?("`#{code}`") })
    assert_equal PhComposer::API.discover.fetch("refusal_documentation"), found.fetch("documentation")
  end

  def test_contracts_carry_versions_grants_and_task_retention
    found = page("section" => "contracts")

    assert_equal({ "major" => 1, "minor" => PhComposer::API::MINOR }, found.fetch("api"))
    assert_equal PhComposer::Export::Tasks::RETENTION_SECONDS,
                 found.dig("tasks", "export", "retention_seconds")
    assert_equal %w[outcome request], found.fetch("schemas").keys
    refute found.key?("sessions")
  end

  def test_a_cursor_is_bound_to_its_section_owner_and_registry
    first = page("section" => "operations", "limit" => 2)
    cursor = first.fetch("next_cursor")

    assert_equal "params.invalid", refusal("section" => "record_kinds", "cursor" => cursor)
    assert_equal "params.invalid", refusal("section" => "operations", "owner" => TestFeature::ID, "cursor" => cursor)
    assert_equal "params.invalid", refusal("section" => "operations", "cursor" => "bm90IGEgY3Vyc29y")
    assert discover("section" => "operations", "limit" => 0)["isError"]
    PhComposer::Registry.install([synthetic(0)])
    assert_equal "query.cursor_expired", refusal("section" => "operations", "cursor" => cursor)
    refute_equal first.fetch("registry"), page("section" => "operations").fetch("registry")
  end

  def test_a_section_refuses_arguments_it_does_not_take
    assert_equal "params.invalid", refusal("section" => "refusals", "limit" => 5)
    assert_equal "params.invalid", refusal("section" => "record_kinds", "topic" => "the_loop")
    assert_equal "params.invalid", refusal("section" => "library_kinds", "owner" => TestFeature::ID)
    assert_equal "params.invalid", refusal("section" => "operations", "owner" => "nope.missing")
    assert_equal "params.invalid", refusal("section" => "guide", "topic" => "nope")
    assert discover("section" => "everything")["isError"]
    assert_equal "params.invalid", refusal("topic" => "the_loop")
    assert_equal "params.invalid", refusal("owner" => TestFeature::ID, "cursor" => "x")
  end

  # A cursor is opaque but readable; one edited to point past the rows is refused, never answered empty.
  def test_an_edited_cursor_is_refused
    cursor = page("section" => "operations", "limit" => 2).fetch("next_cursor")
    decoded = JSON.parse(cursor.unpack1("m0"))
    edited = [JSON.generate(decoded.merge("after" => 2**70))].pack("m0")

    assert_equal "params.invalid", refusal("section" => "operations", "cursor" => edited)
  end

  # Many outside features later, the index and every page still fit one reply and together name
  # every operation once.
  def test_every_page_fits_however_many_features_are_installed
    PhComposer::Registry.install(Array.new(40) { |index| synthetic(index) })
    index = page({})
    rows = all_rows("operations")
    document = PhComposer::API.discover

    assert_equal rows.map { |row| row.fetch("name") }.uniq.length, rows.length
    assert_equal Discovery::OPERATION_KINDS.keys.sum { |kind| document.fetch(kind).length }, rows.length
    assert_nil index["operations"]
    assert_equal 12, index.dig("operation_counts", "queries", "synthetic.f7")
    assert_operator all_rows("operations", :owner => "synthetic.f7").length, :==, 12
  end

  # Hundreds of small features later, the index keeps only totals and the features page instead.
  def test_the_index_fits_with_hundreds_of_features
    PhComposer::Registry.install(Array.new(400) { |index| synthetic(index, :queries => 1) })
    index = page({})

    assert_nil index["features"]
    assert_nil index["operation_counts"]
    assert_includes index.fetch("next"), "section features"
    assert_equal PhComposer::API.discover.fetch("features").length, all_rows("features").length
  end

  # A feature requiring hundreds of others still pages whole through the executor, its list cut and named;
  # an identifier is never cut, so describe still finds what the row names.
  def test_long_lists_are_cut_and_identifiers_kept
    others = Array.new(400) { |index| synthetic(index, :queries => 1) }
    PhComposer::Registry.install(others)
    long_name = "synthetic.needy.#{'n' * (PhComposer::Registry::ID_MAX_BYTES - 16)}"
    needy = Module.new
    needy.define_singleton_method(:install) do |registry|
      feature = registry.feature("synthetic.needy", :contract_version => 1,
                                                    :requires => Array.new(400) { |index| "synthetic.f#{index}" })
      feature.query(long_name, :description => "Needs many.", :params => { "type" => "object" },
                               :result => { "type" => "object" }, :refuses => []) { {} }
    end
    PhComposer::Registry.install([needy])
    row = all_rows("features").find { |feature| feature.fetch("id") == "synthetic.needy" }
    operation = all_rows("operations", :owner => "synthetic.needy").first

    assert_equal ["requires"], row.fetch("truncated")
    assert_operator row.fetch("requires").length, :<, 400
    assert_equal long_name, operation.fetch("name")
    refute @executor.call(@reader, "describe", "name" => long_name)["isError"]
  end

  # The largest operations row registration admits: an owner and names near the identifier cap, and a
  # description and side effects that escape six times over (context/AGENT_INTERFACE.md, "Discover before
  # acting"). Paged alone by owner with a next cursor, it still fits one reply, identifiers whole.
  def test_the_largest_row_registration_admits_fits_one_reply
    owner = "a.#{'f' * (PhComposer::Registry::ID_MAX_BYTES - 6)}"
    escaped = "\u0001" * 5000
    largest = Module.new
    largest.define_singleton_method(:install) do |registry|
      feature = registry.feature(owner, :contract_version => 1)
      %w[r0 r1].each do |suffix|
        feature.action("#{owner}.#{suffix}", :description => escaped, :side_effects => escaped,
                                             :params => { "type" => "object" }, :result => { "type" => "object" },
                                             :refuses => [], :undo_name => "Largest", :examples => [{}]) { {} }
      end
    end
    PhComposer::Registry.install([largest])
    found = page("section" => "operations", "owner" => owner, "limit" => 1)
    row = found.fetch("rows").first

    assert_equal ["#{owner}.r0", owner], row.values_at("name", "owner")
    assert_equal PhComposer::Registry::ID_MAX_BYTES - 1, row.fetch("name").bytesize
    assert_equal %w[description side_effects], row.fetch("truncated")
    refute_nil found.fetch("next_cursor")
    assert_operator JSON.generate(found).bytesize, :>, PhComposer::Pages::MAX_PAGE_BYTES
  end

  # One registration with a very long description still pages, cut, with the cut named.
  def test_one_oversized_row_is_cut_to_fit_a_page
    PhComposer::Registry.install([synthetic(0, :queries => 1, :description => "Long. " * 5000)])
    found = page("section" => "operations", "owner" => "synthetic.f0", "limit" => 1)
    row = found.fetch("rows").first

    assert_equal ["description"], row.fetch("truncated")
    assert_equal Discovery::ROW_TEXT_BYTES, row.fetch("description").bytesize
    assert_nil found.fetch("next_cursor")
    cut = Discovery.bounded_row("name" => "x", "description" => "\u00e9t\u00e9 " * 400).fetch("description")
    assert cut.valid_encoding?
    assert_operator cut.bytesize, :<=, Discovery::ROW_TEXT_BYTES
  end

  # A list section of rows that are each large still pages within the budget and loses none.
  def test_large_rows_page_within_the_budget
    document = PhComposer::API.discover
    many = Array.new(600) do |index|
      { "id" => "synthetic.kind_#{index}", "owner" => "synthetic", "label" => "L" * 300 }
    end
    document = document.merge("record_kinds" => many)
    seen = []
    cursor = nil
    loop do
      found = Discovery.section(document, { "section" => "record_kinds", "cursor" => cursor }.compact)
      assert_operator JSON.generate(found).bytesize, :<=, BUDGET
      seen.concat(found.fetch("rows"))
      break unless (cursor = found.fetch("next_cursor"))
    end
    assert_equal many, seen
  end

  def test_sections_carry_no_session_and_the_index_keeps_token_filtering
    other = Sketchup::Model.new
    other.path = "/projects/other.skp"
    PhComposer::Sessions.for(other)
    Sketchup.active_model.path = "/projects/house.skp"
    bound = token(%w[read], :model_file => "/projects/house.skp")

    sessions = discover({}, bound).dig("structuredContent", "sessions").map { |row| row.fetch("file_name") }
    pages = Discovery::SECTIONS.map { |section| discover({ "section" => section }, bound).fetch("structuredContent") }

    assert_equal ["house.skp"], sessions
    assert(pages.none? { |found| found.key?("sessions") })
  end

  private

  def refusal(arguments)
    result = discover(arguments)
    refute result["isError"], result.inspect
    result.dig("structuredContent", "code")
  end

  # A feature of queries with long descriptions, built only from public registration calls.
  def synthetic(index, queries: 12, description: "A synthetic read. " * 12)
    id = "synthetic.f#{index}"
    Module.new.tap do |feature_module|
      feature_module.define_singleton_method(:install) do |registry|
        feature = registry.feature(id, :contract_version => 1)
        queries.times do |number|
          feature.query("#{id}.read_#{number}", :description => description,
                                                :params => { "type" => "object" }, :result => { "type" => "object" },
                                                :refuses => []) { {} }
        end
      end
    end
  end
end
