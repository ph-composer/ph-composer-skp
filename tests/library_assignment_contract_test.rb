# frozen_string_literal: true

require_relative "test_helper"
require_relative "support/library_provider_fixtures"
require_relative "support/assembly_record_fixtures"
require_relative "support/window_record_fixtures"
require_relative "support/agent_reads"
require_relative "../tools/examples/library_provider/bldgtyp_example_library/install"

# A copy that also assigns, built by an agent from the published contract alone (context/AGENT_INTERFACE.md,
# "Discover before acting"): discovery names each library kind, `describe` gives its assignment target and examples,
# and the agent fills an example's keys with ids and values it read through public reads, checks the target
# against the published schema, previews and applies the copy in one step, then reads both records back.
# Every built-in variant and the outside example's kind take the same route; an invalid target leaves
# neither the copy nor the assignment.
class LibraryAssignmentContractTest < PhComposerTestCase
  include LibraryProviderFixtures
  include AssemblyRecordFixtures
  include WindowRecordFixtures
  include AgentReads

  A = PhComposer::AgentAccess
  L = "ph_composer.library"
  PROVIDER = "synthetic.all"
  COLLECTIONS = %w[frames glazings psi_install_types].freeze

  def setup
    super
    @model = Sketchup.active_model
    @directory = Dir.mktmpdir("library-assignment")
    rows = COLLECTIONS.to_h do |collection|
      row = W::Products.defaults(collection, "name" => "Synthetic #{collection}")
      row.delete("source")
      W::Products.number_keys(collection).each { |key| row[key] = key.start_with?("psi") ? -0.01 : 0.25 }
      [collection, [row.merge("id" => "public-#{collection}")]]
    end
    library = envelope(:kinds => rows.merge("materials" => [library_row])).merge(
      "kind_schema_versions" => (COLLECTIONS + ["materials"]).to_h { |kind| [kind, 1] }
    )
    PhComposer::Library::Setup.add_file(:id => PROVIDER, :label => "Synthetic",
                                        :path => write_library(File.join(@directory, "all.json"), library))
    @session = PhComposer::Sessions.for(@model)
    @executor = A::Executor.new(:tools => A::Tools::TABLE)
    issued = A::Tokens.issue(:capabilities => %w[read model_write setup])
    @token = A::Tokens.snapshot.fetch(A::Tokens.digest(issued.fetch("token")))
  end

  def teardown
    FileUtils.rm_rf(@directory)
    super
  end

  # Every library kind discovery lists, each as `describe` publishes it, by wire kind.
  def described_kinds
    rows = []
    cursor = nil
    loop do
      page = @executor.call(@token, "discover", { "section" => "library_kinds" }
                                                  .merge(cursor ? { "cursor" => cursor } : {}))
                      .fetch("structuredContent")
      rows.concat(page.fetch("rows"))
      break unless (cursor = page.fetch("next_cursor"))
    end
    rows.to_h do |row|
      [row.fetch("wire_kind"),
       @executor.call(@token, "describe", "name" => row.fetch("name")).fetch("structuredContent")]
    end
  end

  # The published example whose keys are exactly `values`' keys, filled with them and checked against the
  # published target schema: the shape comes from the contract, the ids and guards from the Model.
  def target(assignment, values)
    example = assignment.fetch("examples").find { |row| row.keys.sort == values.keys.sort }
    assert example, "no published example has the keys #{values.keys.sort}"
    assert_empty PhComposer::JsonSchema.validate(values, assignment.fetch("target"))
    values
  end

  def generation(provider, kind)
    completed(agent("setup", "name" => "#{L}.load",
                             "params" => { "provider_id" => provider, "kind" => kind, "compact" => true }))
      .fetch("generation")
  end

  # The copy previewed, then applied with the preview's digest; `preview: false` applies it unreviewed, so the
  # copy is staged before its assignment is tried in the same proposal.
  def copy(provider, kind, record_id, assignment, library_id: "synthetic.one", choice: "create", preview: true)
    params = { "provider_id" => provider, "kind" => kind, "generation" => generation(provider, kind),
               "library_id" => library_id, "record_id" => record_id, "choice" => choice,
               "assignment" => assignment }
    request = { "name" => "#{L}.copy", "params" => params, "expected_revision" => @session.revision }
    return agent("invoke", request) unless preview

    reviewed = agent("preview", "name" => "#{L}.copy", "params" => params)
    return reviewed unless reviewed.fetch("status") == "completed"

    agent("invoke", request.merge("proposal_digest" => reviewed.fetch("proposal_digest")))
  end

  # Refused both when previewed and when applied unreviewed, with nothing written.
  def assert_refused_both(code, *arguments, **options)
    [true, false].each do |reviewed|
      outcome = copy(*arguments, **options, :preview => reviewed)
      assert_equal ["refused", "none", code], outcome.values_at("status", "effect", "code"), outcome.inspect
    end
  end

  # A record's values as `records.list` gives them.
  def values_of(kind, id)
    completed(query("ph_composer.records.list", "kind" => kind, "ids" => [id])).dig("records", 0, "values")
  end

  def window_type(name)
    id = completed(agent("invoke", "name" => "#{W::FEATURE_ID}.types.create",
                                   "params" => { "values" => window_values("name" => name) },
                                   "expected_revision" => @session.revision)).fetch("id")
    [id, values_of(W::Types::KIND.id, id)]
  end

  def assert_assigned(outcome)
    assert_equal %w[completed committed], outcome.values_at("status", "effect"), outcome.inspect
    assert_equal true, outcome.dig("value", "assigned")
    outcome.dig("value", "local_id")
  end

  def test_every_built_in_assignment_is_built_from_the_published_descriptor_alone
    kinds = described_kinds
    assert(kinds.values.all? { |row| row.dig("assignment", "supported") })

    assembly = fixture_assembly([[100.0, [[600.0, nil]]]])
    Assemblies::Assembly::Schema::KIND.store.write(@model, assembly)
    stored = values_of(Assemblies::ASSEMBLY_KIND, assembly.fetch("id"))
    layer = stored.dig("layers", 0)
    material = assert_assigned(copy(PROVIDER, "materials", "public-1", target(
      kinds.fetch("materials").fetch("assignment"),
      { "id" => assembly.fetch("id"), "layer_id" => layer.fetch("id"),
        "segment_id" => layer.dig("segments", 0, "id"), "expected_values" => stored }
    )))
    assert_equal material, values_of(Assemblies::ASSEMBLY_KIND, assembly.fetch("id"))
      .dig("layers", 0, "segments", 0, "material_id")

    COLLECTIONS.each do |collection|
      type_id, type = window_type("Type #{collection}")
      element = { "id" => type_id, "element_id" => type.dig("elements", 0, "id"), "expected_values" => type }
      element["side"] = "left" unless collection == "glazings"
      if collection == "psi_install_types"
        element.merge!("mode" => "perimeter",
                       "expected_settings" => completed(query("#{W::FEATURE_ID}.settings.get", {})))
      end
      id = assert_assigned(copy(PROVIDER, collection, "public-#{collection}",
                                target(kinds.fetch(collection).fetch("assignment"), element)))
      cell = values_of(W::Types::KIND.id, type_id).dig("elements", 0)
      assigned = { "frames" => cell.dig("frames", "left"), "glazings" => cell["glazing_id"],
                   "psi_install_types" => cell.dig("installs", "left") }
      assert_equal id, assigned.fetch(collection)
    end

    # The install type copied above is the one reviewed local candidate now, so it is kept and made the default.
    settings = completed(query("#{W::FEATURE_ID}.settings.get", {}))
    default = assert_assigned(copy(PROVIDER, "psi_install_types", "public-psi_install_types", target(
      kinds.fetch("psi_install_types").fetch("assignment"),
      { "mode" => "model_default", "expected_settings" => settings }
    ), :choice => "keep_local"))
    assert_equal default, completed(query("#{W::FEATURE_ID}.settings.get", {})).fetch("default_psi_install_id")
  end

  def test_an_invalid_target_leaves_neither_the_copy_nor_the_assignment
    kinds = described_kinds
    type_id, type = window_type("Guarded")
    before = [W::Products::KINDS.fetch("frames").store.ids(@model), values_of(W::Types::KIND.id, type_id),
              @session.revision]
    missing = target(kinds.fetch("frames").fetch("assignment"),
                     { "id" => type_id, "element_id" => "missing", "side" => "left", "expected_values" => type })
    assert_refused_both("target.not_found", PROVIDER, "frames", "public-frames", missing)
    stale = target(kinds.fetch("frames").fetch("assignment"),
                   { "id" => type_id, "element_id" => type.dig("elements", 0, "id"), "side" => "left",
                     "expected_values" => type.merge("name" => "Not what is stored") })
    assert_refused_both("target.changed", PROVIDER, "frames", "public-frames", stale)
    assert_refused_both("params.invalid", PROVIDER, "frames", "public-frames", { "id" => type_id })
    assert_equal before, [W::Products::KINDS.fetch("frames").store.ids(@model),
                          values_of(W::Types::KIND.id, type_id), @session.revision]
  end

  # The outside example's kind: discovery and describe publish its own callback's target and example, and the
  # same copy assigns its tag to a holder with no transport, MCP or core entry for it.
  def test_an_outside_kind_copies_and_assigns_from_its_own_published_target
    assert BldgtypExampleLibrary.activate
    tags = described_kinds.fetch("tags").fetch("assignment")
    holder = completed(agent("invoke", "name" => "#{BldgtypExampleLibrary::FEATURE_ID}.add_holder",
                                       "params" => { "position" => "North wall" },
                                       "expected_revision" => @session.revision)).fetch("id")
    provider = BldgtypExampleLibrary::Provider.new.id
    missing = target(tags, { "id" => "bth_missing00000" })
    assert_refused_both("target.not_found", provider, "tags", "north", missing,
                        :library_id => "bldgtyp.example.synthetic")
    assert_empty completed(query("ph_composer.records.list", "kind" => BldgtypExampleLibrary::TAG))
      .fetch("records")

    tag = assert_assigned(copy(provider, "tags", "north", target(tags, { "id" => holder }),
                               :library_id => "bldgtyp.example.synthetic"))
    assert_equal tag, values_of(BldgtypExampleLibrary::HOLDER, holder).fetch("tag_id")
    assert_equal "N-1", values_of(BldgtypExampleLibrary::TAG, tag).fetch("designation")
  end
end
