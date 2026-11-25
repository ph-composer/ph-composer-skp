# frozen_string_literal: true

require_relative "test_helper"
require_relative "support/referrer_probe"

# The Ventilator kind with the panel closed: its stored shape and defaults, the values it refuses, guarded edits,
# Duplicate and Delete, each one Undo step, and its user_data and extension payloads kept through each of them,
# Undo, Redo and a reopen.
class MechanicalVentilatorsTest < PhComposerTestCase
  API = PhComposer::API
  M = PhComposer::Mechanical
  PREFIX = "ph_composer.mechanical.ventilators"
  KIND = M::VENTILATOR_KIND
  REVIEW = "probe.mechanical.review"
  USER_DATA = { "firm" => { "tag" => ["original"] } }.freeze

  # A third party's payload on a Ventilator, valid when it holds a status.
  module Review
    module_function

    def name
      "Review"
    end

    def install(registry)
      registry.feature("probe.mechanical", :contract_version => 1).extension(PhComposer::Records::Extension.new(
        :namespace => REVIEW, :schema_version => 1, :export_relevance => "local_only",
        :validate => ->(payload) { payload["status"].is_a?(String) ? [] : ["status is missing"] }
      ))
    end
  end

  def setup
    super
    @model = Sketchup.active_model
    @session = PhComposer::Sessions.for(@model)
    @context = API.connect(:session_id => @session.id)
    @sequence = 0
  end

  def test_a_ventilator_round_trips_and_an_unknown_key_or_another_version_is_unreadable
    id = create("name" => "ERV-1", "manufacturer" => "Maker", "subsoil_heat_exchange_efficiency" => 0.2)
    engine = PhComposer::Records::Engine.new(@model, PhComposer::Registry.current.catalog)
    record = engine.find(KIND, id)
    store = engine.kind(KIND).store
    assert_equal "ph_composer.records.#{KIND}", store.dictionary
    assert_match(/\Avnt_[A-Za-z0-9]{12}\z/, id)
    assert_equal record, JSON.parse(JSON.generate(record))
    store.write(@model, record.merge("rated_flow_m3h" => 120))
    assert_equal "record.unreadable", refusal { engine.find(KIND, id) }
    store.write(@model, record.merge("schema_version" => 2))
    assert_equal "record.unreadable", refusal { engine.find(KIND, id) }
    store.write(@model, record)
    assert_equal record, engine.find(KIND, id)
  end

  def test_a_new_ventilator_takes_the_defaults_and_leaves_both_optional_fields_absent
    values = row(create("name" => " ERV-1 ")).fetch("values")
    assert_equal({ "name" => "ERV-1", "notes" => "", "datasheet_links" => [], "source" => { "kind" => "manual" },
                   "quantity" => 1, "sensible_heat_recovery" => 0.0, "latent_heat_recovery" => 0.0,
                   "electric_efficiency_wh_m3" => 0.55, "frost_protection_reqd" => true,
                   "temperature_below_defrost_used_c" => -5.0, "in_conditioned_space" => true }, values)
    assert_instance_of Float, values.fetch("temperature_below_defrost_used_c")
  end

  def test_an_optional_value_is_set_and_a_null_removes_it_but_a_null_required_value_refuses
    id = create("name" => "ERV-2")
    update!(id, { "subsoil_heat_exchange_efficiency" => 0.2, "preheated_intake_temperature_c" => 2.5 }, {})
    assert_equal [0.2, 2.5], row(id).fetch("values").values_at("subsoil_heat_exchange_efficiency",
                                                               "preheated_intake_temperature_c")
    update!(id, { "subsoil_heat_exchange_efficiency" => nil }, { "subsoil_heat_exchange_efficiency" => 0.2 })
    refute row(id).fetch("values").key?("subsoil_heat_exchange_efficiency")
    revision = @session.revision
    outcome = invoke("update", "id" => id, "values" => { "quantity" => nil }, "expected_values" => {})
    assert_equal %w[refused validation.failed], outcome.values_at("status", "code"), outcome.inspect
    assert_equal revision, @session.revision
  end

  def test_out_of_range_values_refuse_and_write_nothing
    revision = @session.revision
    [{ "sensible_heat_recovery" => 1.2 }, { "latent_heat_recovery" => -0.1 },
     { "electric_efficiency_wh_m3" => -0.1 }, { "quantity" => 0 }, { "quantity" => 1.5 },
     { "subsoil_heat_exchange_efficiency" => 1.2 }].each do |bad|
      outcome = invoke("create", "values" => { "name" => "Bad" }.merge(bad))
      assert_equal %w[refused params.invalid], outcome.values_at("status", "code"), "#{bad}: #{outcome.inspect}"
      assert_equal revision, @session.revision, bad.inspect
    end
    assert_empty query("all").fetch("records")
    id = create("name" => "ERV-1")
    revision = @session.revision
    outcome = invoke("update", "id" => id, "values" => { "sensible_heat_recovery" => 1.2 }, "expected_values" => {})
    assert_equal %w[refused params.invalid], outcome.values_at("status", "code"), outcome.inspect
    assert_equal [revision, 0.0], [@session.revision, row(id).dig("values", "sensible_heat_recovery")]
    assert_equal "validation.failed", invoke("create", "values" => { "name" => "ERV-1" })["code"], "names are unique"
  end

  def test_a_stale_expected_value_refuses_the_whole_edit_and_writes_nothing
    id = create("name" => "ERV-1")
    revision = @session.revision
    outcome = invoke("update", "id" => id, "values" => { "quantity" => 3, "name" => "ERV-9" },
                               "expected_values" => { "quantity" => 1, "sensible_heat_recovery" => 0.85 })
    assert_equal %w[refused target.changed none], outcome.values_at("status", "code", "effect"), outcome.inspect
    assert_equal revision, @session.revision
    assert_equal ["ERV-1", 1], row(id).fetch("values").values_at("name", "quantity")
    create("name" => "ERV-2")
    revision = @session.revision
    taken = invoke("update", "id" => id, "values" => { "name" => "erv-2" }, "expected_values" => { "quantity" => 5 })
    assert_equal %w[refused target.changed], taken.values_at("status", "code"), "a stale read is reported first"
    assert_equal "validation.failed", invoke("update", "id" => id, "values" => { "name" => " erv-2 " },
                                                       "expected_values" => { "quantity" => 1 })["code"]
    engine = PhComposer::Records::Engine.new(@model, PhComposer::Registry.current.catalog)
    proposal = PhComposer::Operations::Proposal.new
    caller = Struct.new(:engine).new(engine)
    assert_raises(PhComposer::CodedError) do
      M::Ventilators::Operations.update(caller, proposal, :id => id, :values => { "name" => "ERV-2" },
                                                          :expected_values => {})
    end
    assert proposal.refusal, "a composing caller that rescues the refusal cannot commit the staged rename"
    stale = invoke("delete", "id" => id, "expected_values" => { "name" => "ERV-9" })
    assert_equal %w[refused target.changed], stale.values_at("status", "code"), stale.inspect
    assert_equal revision, @session.revision
  end

  def test_an_unknown_id_refuses_every_write_as_not_found
    missing = "vnt_AAAAAAAAAAAA"
    [["update", { "id" => missing, "values" => { "quantity" => 2 }, "expected_values" => {} }],
     ["duplicate", { "id" => missing }], ["delete", { "id" => missing }]].each do |name, params|
      assert_equal %w[refused target.not_found], invoke(name, params).values_at("status", "code"), name
    end
  end

  def test_duplicate_gives_a_new_id_an_independent_user_data_copy_and_a_derived_source
    id = create({ "name" => "ERV-1", "sensible_heat_recovery" => 0.85 }, USER_DATA)
    copy = invoke!("duplicate", "id" => id).dig("value", "id")
    refute_equal id, copy
    assert_match(/\Avnt_/, copy)
    values = row(copy).fetch("values")
    assert_equal ["ERV-1 (copy)", { "kind" => "derived" }, 0.85],
                 values.values_at("name", "source", "sensible_heat_recovery")
    assert_equal({ "kind" => "manual" }, row(id).dig("values", "source"), "the original keeps its source")
    metadata!(copy, { "firm" => { "tag" => ["changed"] } })
    assert_equal [USER_DATA, { "firm" => { "tag" => ["changed"] } }], [row(id), row(copy)].map { |r| r["user_data"] }
    named = invoke!("duplicate", "id" => id, "name" => "ERV-2").dig("value", "id")
    assert_equal "ERV-2", row(named).dig("values", "name")
  end

  def test_deleting_an_unused_ventilator_is_one_undo_step_that_restores_its_metadata
    PhComposer::Registry.install([Review])
    id = create({ "name" => "ERV-1" }, USER_DATA)
    metadata!(id, USER_DATA, REVIEW => { "status" => "checked" })
    before = row(id)
    result = invoke!("delete", "id" => id, "expected_values" => { "name" => "ERV-1" })
    assert_equal [{ "id" => id, "user_data_keys" => ["firm"], "user_data_key_total" => 1 }],
                 result.dig("value", "removed_user_data")
    assert_empty query("all").fetch("records")
    @model.undo
    assert_equal before, row(id)
    @model.redo
    assert_empty query("all").fetch("records")
  end

  def test_metadata_and_extension_payloads_survive_edit_duplicate_undo_redo_and_reopen
    PhComposer::Registry.install([Review])
    id = create({ "name" => "ERV-1" }, USER_DATA)
    metadata!(id, USER_DATA, REVIEW => { "status" => "draft" })
    tagged = row(id)
    payload = tagged.dig("extension_data", REVIEW)
    assert_equal({ REVIEW => "understood" }, tagged.fetch("extension_status"))
    @model.undo
    assert_equal [USER_DATA, {}], row(id).values_at("user_data", "extension_data"), "Undo takes the payload back"
    @model.redo
    assert_equal tagged, row(id)
    update!(id, { "notes" => "Edited", "quantity" => 2 }, { "quantity" => 1 })
    edited = row(id)
    assert_equal tagged.values_at("user_data", "extension_data", "extension_status"),
                 edited.values_at("user_data", "extension_data", "extension_status")
    @model.undo
    assert_equal tagged, row(id)
    @model.redo
    assert_equal edited, row(id)
    copy = invoke!("duplicate", "id" => id).dig("value", "id")
    @model.undo
    assert_nil query("all").fetch("records").find { |entry| entry["id"] == copy }
    @model.redo
    path = File.join(Dir.tmpdir, "ph-composer-ventilators.skp")
    @model.save(path)
    Sketchup.open_file(path)
    @session = PhComposer::Sessions.for(Sketchup.active_model)
    @context = API.connect(:session_id => @session.id)
    [id, copy].each do |kept|
      reopened = row(kept)
      assert_equal [USER_DATA, { REVIEW => payload }, { REVIEW => "understood" }, 2],
                   reopened.values_at("user_data", "extension_data", "extension_status") +
                   [reopened.dig("values", "quantity")], kept
    end
  end

  def test_the_snapshot_section_carries_the_all_read_and_each_row_is_ready_to_export
    id = create("name" => "ERV-1")
    sections = PhComposer::Snapshot.build(@context).fetch("sections")
    assert_equal query("all"), sections.dig(PREFIX, "value")
    assert_equal [true, []], row(id).values_at("export_ready", "export_blockers")
    records = API.query(:context => @context, :name => "ph_composer.records.list", :params => { "kind" => KIND })
    assert_equal [id], records.dig("value", "records").map { |entry| entry["id"] }
    assert_empty query("list", "ids" => ["vnt_AAAAAAAAAAAA"]).fetch("records"), "a well-formed absent id"
    wrong = API.query(:context => @context, :name => "#{PREFIX}.list", :params => { "ids" => ["frm_AAAAAAAAAAAA"] })
    assert_equal %w[refused params.invalid], wrong.values_at("status", "code"), "another kind's id"
    page = query("list", "limit" => 1, "fields" => ["export_ready"])
    assert_equal [[KIND, id, 1, true]], page.fetch("records").map { |r|
      r.values_at("kind", "id", "schema_version",
                  "export_ready")
    }
  end

  # Another feature's entity records naming a Ventilator: its registered retargeter moves them to the replacement,
  # or clears them with null, in the delete's one Undo step, and Mechanical names no such feature.
  def test_a_delete_retargets_another_features_referrer_through_the_engine
    ReferrerProbe.install(KIND, "ventilator_id")
    one = create("name" => "ERV-1")
    two = create("name" => "ERV-2")
    @model.entities << ReferrerProbe.holder(9000, "ventilator_id", one)
    assert_equal %w[refused reference.in_use], invoke("delete", "id" => one).values_at("status", "code")
    invoke!("delete", "id" => one, "replacement_id" => two)
    assert_equal two, ReferrerProbe.named(@model, 9000, "ventilator_id")
    @model.undo
    assert_equal one, ReferrerProbe.named(@model, 9000, "ventilator_id")
    invoke!("delete", "id" => one, "replacement_id" => nil)
    assert_nil ReferrerProbe.named(@model, 9000, "ventilator_id")
    assert_equal [two], query("all").fetch("records").map { |record| record.fetch("id") }
  end

  # ---------------------------------------------------------------- helpers

  def create(values, user_data = nil)
    params = { "values" => values }
    params["user_data"] = user_data if user_data
    invoke!("create", params).dig("value", "id")
  end

  def update!(id, values, expected)
    invoke!("update", "id" => id, "values" => values, "expected_values" => expected)
  end

  def row(id)
    query("all").fetch("records").find { |entry| entry["id"] == id } || flunk("no Ventilator #{id}")
  end

  def metadata!(id, map, payloads = nil)
    current = row(id)
    update = { "reference" => { "kind" => KIND, "id" => id }, "user_data" => map,
               "expected_metadata" => current.slice("user_data", "extension_data") }
    update["extension_payloads"] = payloads if payloads
    @sequence += 1
    outcome = API.invoke(:context => @context, :name => "ph_composer.records.update_metadata",
                         :params => { "updates" => [update] },
                         :request => { "sequence" => @sequence, "expected_revision" => @session.revision })
    assert_equal "committed", outcome["effect"], outcome.inspect
  end

  def refusal
    yield
    nil
  rescue PhComposer::CodedError => error
    error.code
  end

  def query(name, params = {})
    outcome = API.query(:context => @context, :name => "#{PREFIX}.#{name}", :params => params)
    assert_equal "completed", outcome.fetch("status"), outcome.inspect
    outcome.fetch("value")
  end

  def invoke!(name, params)
    outcome = invoke(name, params)
    assert_equal "committed", outcome["effect"], "#{name}: #{outcome.inspect}"
    outcome
  end

  def invoke(name, params)
    @sequence += 1
    API.invoke(:context => @context, :name => "#{PREFIX}.#{name}", :params => params,
               :request => { "sequence" => @sequence, "expected_revision" => @session.revision })
  end
end
