# frozen_string_literal: true

require_relative "test_helper"
require_relative "support/space_fixtures"
require_relative "support/zone_options"

# What serves each Zone (context/CONTRACTS.md, "Mechanical equipment"): a payload on the Zone record that Zones
# stages. Apt 1 sits at the root and Apt 2 inside a Group moved 400 in, both in the Apartments Building Segment;
# ERV-1, ERV-2 and ERV-3 are Ventilators. Every write goes through the public actions, one Undo step each.
class MechanicalServesTest < PhComposerTestCase
  include SpaceFixtures
  include ZoneOptionsSupport

  API = PhComposer::API
  M = PhComposer::Mechanical
  SERVES = "ph_composer.mechanical.serves"
  VENTILATORS = "ph_composer.mechanical.ventilators"
  NAMESPACE = "ph_composer.mechanical.zone_serves"
  PROGRAMS = "ph_composer.programs"
  CERTIFICATION = PhComposer::Certification::Segment::NAMESPACE

  def setup
    super
    @model = Sketchup.active_model
    @session = PhComposer::Sessions.for(@model)
    @context = API.connect(:session_id => @session.id)
    @sequence = 0
    wrapper = Sketchup::Group.new(8000, Sketchup::Entities.new([zone(2000, "B", "Apt 2", [0, 0, 5, 5])]),
                                  :transformation => Geom::Transformation.translation([400, 0, 0]))
    @model.entities << zone(1000, "A", "Apt 1", [0, 0, 5, 5]) << wrapper
    adopt_zone_options
    @erv = %w[ERV-1 ERV-2 ERV-3].to_h do |name|
      [name, completed(invoke("#{VENTILATORS}.create", "values" => { "name" => name })).fetch("id")]
    end
  end

  # ---------------------------------------------------------------- assign

  def test_assign_stages_the_payload_a_second_refuses_naming_the_first_and_replace_replaces
    operations = @model.operations.length
    completed(assign(%w[Apt\ 1 Apt\ 2], "ERV-1"))
    assert_equal operations + 1, @model.operations.length
    assert_equal(M::Serves::EMPTY.merge("ventilator_id" => @erv.fetch("ERV-1")), stored_payload("Apt 1"),
                 "on the Zone record")
    assert_equal @erv.fetch("ERV-1"), slots("Apt 2").fetch("ventilator_id"), "the Zone in a Group too"

    revision = @session.revision
    refusal = assign(["Apt 1"], "ERV-2")
    refused(refusal, "mechanical.slot_filled")
    assert_match(/ERV-1/, refusal.dig("error", "message") || refusal.fetch("message"))
    assert_equal [revision, operations + 1], [@session.revision, @model.operations.length]
    completed(assign(["Apt 1"], "ERV-1"))

    completed(assign(["Apt 1"], "ERV-2", :replace => true))
    assert_equal @erv.fetch("ERV-2"), slots("Apt 1").fetch("ventilator_id")
    @model.undo
    assert_equal @erv.fetch("ERV-1"), slots("Apt 1").fetch("ventilator_id"), "Undo restores the previous slot"
    @model.redo
    assert_equal @erv.fetch("ERV-2"), slots("Apt 1").fetch("ventilator_id")
  end

  def test_a_stale_expected_value_on_one_of_two_zones_refuses_the_whole_command
    completed(assign(["Apt 1"], "ERV-1"))
    revision = @session.revision
    # The fresh target comes first, so a command that staged Zone by Zone would have written it.
    targets = [target("Apt 2"), target("Apt 1", "ventilator_id" => nil)]
    refused(invoke("#{SERVES}.assign", "zones" => targets, "slot" => "ventilator_id",
                                       "item_id" => @erv.fetch("ERV-2"), "replace" => true), "target.changed")
    refused(invoke("#{SERVES}.clear", "zones" => targets), "target.changed")
    assert_equal revision, @session.revision
    assert_nil stored_payload("Apt 2")
    assert_equal @erv.fetch("ERV-1"), slots("Apt 1").fetch("ventilator_id")
  end

  def test_an_item_that_is_not_stored_or_of_another_kind_refuses_before_staging
    revision = @session.revision
    refused(invoke("#{SERVES}.assign", "zones" => [target("Apt 1")], "slot" => "ventilator_id",
                                       "item_id" => "vnt_ZZZZZZZZZZZZ"), "target.not_found")
    refused(invoke("#{SERVES}.assign", "zones" => [target("Apt 1")], "slot" => "ventilator_id",
                                       "item_id" => "hws_ZZZZZZZZZZZZ"), "params.invalid")
    missing_zone = { "reference" => { "zone_id" => "zon_ZZZZZZZZZZZZ", "zone_path" => [1000] } }
    refused(invoke("#{SERVES}.assign", "zones" => [missing_zone], "slot" => "ventilator_id",
                                       "item_id" => @erv.fetch("ERV-1")), "target.not_found")
    refused(invoke("#{SERVES}.assign", "zones" => [target("Apt 1"), target("Apt 1")], "slot" => "ventilator_id",
                                       "item_id" => @erv.fetch("ERV-1")), "params.invalid")
    assert_equal revision, @session.revision
  end

  # Zones owns every write: a locked Group, a shared definition and a Zone inside a Zone refuse with its codes, and
  # nothing is written to either Zone. Clear writes only a Zone that stores a payload.
  def test_zones_write_refusals_pass_through_unchanged
    completed(assign(["Apt 1"], "ERV-1"))
    inner = zone(3000, "C", "Inner", [1, 1, 1, 1])
    zone_group_named("Apt 1").entities << inner
    definition = Sketchup::ComponentDefinition.new(Sketchup::Entities.new([zone(4000, "D", "Shared", [9, 9, 1, 1])]))
    @model.entities << Sketchup::ComponentInstance.new(4100, definition)
    revision = @session.revision
    operations = @model.operations.length

    { "Inner" => "target.wrong_hierarchy", "Shared" => "target.shared_definition" }.each do |name, code|
      refused(assign(["Apt 2", name], "ERV-1"), code)
    end
    zone_group_named("Apt 1").locked = true
    refused(assign(["Apt 2", "Apt 1"], "ERV-2", :replace => true), "target.locked")
    refused(invoke("#{SERVES}.clear", "zones" => [target("Apt 1")]), "target.locked")
    assert_equal [revision, operations], [@session.revision, @model.operations.length]
    assert_nil stored_payload("Apt 2")
    assert_equal @erv.fetch("ERV-1"), slots("Apt 1").fetch("ventilator_id")
  end

  # ---------------------------------------------------------------- clear

  def test_clear_leaves_a_zone_reading_as_served_by_nothing_as_a_zone_with_no_payload_does
    completed(assign(%w[Apt\ 1 Apt\ 2], "ERV-1"))
    operations = @model.operations.length
    completed(invoke("#{SERVES}.clear", "zones" => [target("Apt 1"), target("Apt 2")], "slot" => "ventilator_id"))
    assert_equal operations + 1, @model.operations.length, "two Zones, one Undo step"
    @model.undo
    assert_equal [@erv.fetch("ERV-1")] * 2, %w[Apt\ 1 Apt\ 2].map { |name| slots(name).fetch("ventilator_id") }
    operations = @model.operations.length
    completed(invoke("#{SERVES}.clear", "zones" => [target("Apt 1")], "slot" => "ventilator_id"))
    completed(invoke("#{SERVES}.clear", "zones" => [target("Apt 2")]))
    assert_equal operations + 2, @model.operations.length
    assert_equal M::Serves::EMPTY, stored_payload("Apt 1"), "a cleared Zone stores the empty payload"

    completed(invoke("#{SERVES}.clear", "zones" => [target("Apt 1")]))
    assert_equal operations + 2, @model.operations.length, "clearing an empty Zone writes nothing"
    @model.entities << zone(5000, "E", "Apt 3", [20, 0, 5, 5])
    rows = serves_rows
    shape = ->(row) { row.values_at("slots", "items").push(codes(row)) }
    assert_equal shape.call(rows.fetch("Apt 3")), shape.call(rows.fetch("Apt 1"))
    assert_equal shape.call(rows.fetch("Apt 3")), shape.call(rows.fetch("Apt 2"))
    assert_equal [M::Serves::EMPTY, [], %w[mechanical.zone_unventilated mechanical.zone_no_hot_water]],
                 shape.call(rows.fetch("Apt 1"))
    assert_nil rows.fetch("Apt 3").fetch("payload_status")
    assert_equal "understood", rows.fetch("Apt 1").fetch("payload_status")
  end

  # ---------------------------------------------------------------- delete in use

  def test_a_plain_delete_of_a_ventilator_a_zone_names_refuses_naming_the_zones
    completed(assign(%w[Apt\ 1 Apt\ 2], "ERV-1"))
    revision = @session.revision
    refusal = delete("ERV-1")
    refused(refusal, "reference.in_use")
    message = refusal.dig("error", "message") || refusal.fetch("message")
    assert_match(/Apt 1, Apt 2/, message)
    stale = invoke("#{VENTILATORS}.delete", "id" => @erv.fetch("ERV-1"), "expected_values" => { "quantity" => 2 })
    refused(stale, "target.changed")
    assert_equal revision, @session.revision
    completed(invoke("#{VENTILATORS}.delete", "id" => @erv.fetch("ERV-3"), "expected_values" => { "quantity" => 1 }))
  end

  def test_a_delete_with_a_replacement_moves_every_slot_in_one_undo_step
    completed(assign(%w[Apt\ 1 Apt\ 2], "ERV-1"))
    operations = @model.operations.length
    completed(delete("ERV-1", :replacement => @erv.fetch("ERV-2")))
    assert_equal operations + 1, @model.operations.length
    assert_equal [@erv.fetch("ERV-2")] * 2, %w[Apt\ 1 Apt\ 2].map { |name| slots(name).fetch("ventilator_id") }
    refute_includes ventilator_ids, @erv.fetch("ERV-1")

    @model.undo
    assert_equal [@erv.fetch("ERV-1")] * 2, %w[Apt\ 1 Apt\ 2].map { |name| slots(name).fetch("ventilator_id") }
    assert_includes ventilator_ids, @erv.fetch("ERV-1")
    @model.redo
    assert_equal [@erv.fetch("ERV-2")] * 2, %w[Apt\ 1 Apt\ 2].map { |name| slots(name).fetch("ventilator_id") }
  end

  def test_a_delete_with_null_empties_the_slots_and_a_bad_replacement_refuses
    completed(assign(%w[Apt\ 1 Apt\ 2], "ERV-1"))
    revision = @session.revision
    refused(delete("ERV-1", :replacement => @erv.fetch("ERV-1")), "params.invalid")
    refused(delete("ERV-1", :replacement => "vnt_ZZZZZZZZZZZZ"), "target.not_found")
    zone_group_named("Apt 1").locked = true
    refused(delete("ERV-1", :replacement => @erv.fetch("ERV-2")), "target.locked")
    assert_equal revision, @session.revision
    zone_group_named("Apt 1").locked = false

    operations = @model.operations.length
    completed(delete("ERV-1", :replacement => nil))
    assert_equal operations + 1, @model.operations.length
    assert_equal [M::Serves::EMPTY] * 2, %w[Apt\ 1 Apt\ 2].map { |name| slots(name) }
    @model.undo
    assert_equal [@erv.fetch("ERV-1")] * 2, %w[Apt\ 1 Apt\ 2].map { |name| slots(name).fetch("ventilator_id") }
  end

  # A caller composing Serves' operations in one proposal: the delete's move reads what the earlier assign staged,
  # not the stored payload, and its reference plan projects that Zone as the proposal leaves it.
  def test_a_delete_after_an_assign_in_one_proposal_builds_from_the_staged_payload
    completed(assign(%w[Apt\ 1 Apt\ 2], "ERV-1"))
    proposal = PhComposer::Operations::Proposal.new
    request = PhComposer::HandlerRequest.for(@session, :owner => M::FEATURE_ID, :name => "#{VENTILATORS}.delete",
                                                       :proposal => proposal)
    M::Serves::Operations.assign(request, proposal, :targets => [target("Apt 1")], :slot => "ventilator_id",
                                                    :item_id => @erv.fetch("ERV-3"), :replace => true)
    erv1 = @erv.fetch("ERV-1")
    M::Serves::Operations.delete(request, proposal, M::VENTILATOR_KIND, :id => erv1, :expected_values => {},
                                                                        :replacement => @erv.fetch("ERV-2")) do |plan|
      M::Ventilators::Operations.delete(request, proposal, :id => erv1, :reference_plan => plan)
    end
    assert_nil proposal.refusal
    staged = proposal.steps.filter_map do |step|
      after = step.descriptor["after"]
      after && [after.fetch("name"), after.dig("extension_data", NAMESPACE, "payload", "ventilator_id")]
    end
    assert_equal [["Apt 1", @erv.fetch("ERV-3")], ["Apt 2", @erv.fetch("ERV-2")]], staged.uniq.last(2).sort,
                 "Apt 1 keeps ERV-3, staged before the delete; Apt 2 moves to ERV-2"
  end

  # ---------------------------------------------------------------- copy

  def test_a_copied_zone_keeps_what_serves_it_with_no_step_of_this_feature
    completed(assign(["Apt 1"], "ERV-1"))
    copy = copy_of("Apt 1")
    # Before the copy is independent, both occurrences share one Zone id; a move refuses whole.
    revision = @session.revision
    refused(delete("ERV-1", :replacement => @erv.fetch("ERV-2")), "target.ambiguous")
    refused(assign(["Apt 1"], "ERV-2", :replace => true), "target.ambiguous")
    assert_equal revision, @session.revision

    completed(invoke("ph_composer.zones.make_independent", "zone_path" => [copy.persistent_id]))
    rows = query("#{SERVES}.all").fetch("zones").select { |row| row.fetch("name") == "Apt 1" }
    assert_equal 2, rows.map { |row| row.fetch("zone_id") }.uniq.length, "the copy is its own Zone"
    assert_equal [@erv.fetch("ERV-1")] * 2, rows.map { |row| row.dig("slots", "ventilator_id") }
    contributors = PhComposer::Registry.current.transition_contributors.values
    assert_empty contributors.select { |row| row.owner == M::FEATURE_ID }, "the payload travels with the record"

    completed(delete("ERV-1", :replacement => @erv.fetch("ERV-2")))
    rows = query("#{SERVES}.all").fetch("zones").select { |row| row.fetch("name") == "Apt 1" }
    assert_equal [@erv.fetch("ERV-2")] * 2, rows.map { |row| row.dig("slots", "ventilator_id") }
  end

  # ---------------------------------------------------------------- reads and findings

  def test_the_reads_carry_names_and_findings_and_a_zone_left_out_is_not_unventilated
    completed(assign(["Apt 1"], "ERV-1"))
    rows = serves_rows
    assert_equal [{ "slot" => "ventilator_id", "id" => @erv.fetch("ERV-1"), "name" => "ERV-1" }],
                 rows.fetch("Apt 1").fetch("items")
    assert_equal ["mechanical.zone_no_hot_water"], codes(rows.fetch("Apt 1"))
    assert_equal %w[mechanical.zone_unventilated mechanical.zone_no_hot_water], codes(rows.fetch("Apt 2"))
    erv = ventilator_rows
    assert_equal ["Apt 1"], erv.fetch("ERV-1").fetch("zones").map { |row| row.fetch("name") }
    assert_empty codes(erv.fetch("ERV-1"))
    assert_equal ["mechanical.item_unserved"], codes(erv.fetch("ERV-2"))
    refute(erv.fetch("ERV-2").fetch("findings").first.fetch("blocks_export"))

    completed(invoke("ph_composer.zones.update_field",
                     "field" => "building_segment", "value" => nil,
                     "targets" => %w[Apt\ 1 Apt\ 2].map do |name|
                       row = zone_row(name)
                       { "reference" => row.fetch("reference"), "expected_values" => row.fetch("values") }
                     end))
    rows = serves_rows
    assert_equal ["mechanical.zone_left_out"], codes(rows.fetch("Apt 1"))
    assert_empty codes(rows.fetch("Apt 2")), "an unserved Zone left out is no unventilated Zone"
    assert_equal ["mechanical.zone_left_out"], codes(ventilator_rows.fetch("ERV-1"))

    page = query("#{SERVES}.list", "limit" => 1)
    assert_equal [1, 2], [page.fetch("zones").length, page.fetch("total")]
    rest = query("#{SERVES}.list", "limit" => 1, "cursor" => page.fetch("next_cursor"))
    assert_nil rest.fetch("next_cursor")
    assert_equal query("#{SERVES}.all").fetch("zones"), page.fetch("zones") + rest.fetch("zones")
    listed = query("#{VENTILATORS}.list").fetch("records").to_h { |row| [row.dig("values", "name"), row] }
    assert_equal ventilator_rows, listed
  end

  # Every route through the engine refuses a slot naming no stored item, the generic metadata route included; a Zone
  # record written outside it, as one pasted from another Model arrives, can still hold one, and the read reports it.
  def test_a_payload_naming_a_missing_ventilator_reads_item_missing_and_an_unknown_key_refuses
    missing = M::Serves::EMPTY.merge("ventilator_id" => "vnt_ZZZZZZZZZZZZ")
    refused(metadata("Apt 1", missing), "reference.invalid")
    group = zone_group_named("Apt 1")
    record = ZONES::ZONE_STORE.read(group)
    envelope = M::Serves::Payload::EXTENSION.envelope(missing)
    ZONES::ZONE_STORE.write(group, record.merge("extension_data" => { NAMESPACE => envelope }))
    row = serves_rows.fetch("Apt 1")
    assert_equal [["mechanical.item_missing", true], ["mechanical.zone_no_hot_water", false]],
                 row.fetch("findings").map { |finding| finding.values_at("code", "blocks_export") }
    assert_equal [nil], row.fetch("items").map { |item| item.fetch("name") }
    refused(assign(["Apt 1"], "ERV-1"), "mechanical.slot_filled")
    completed(assign(["Apt 1"], "ERV-1", :replace => true))
    assert_equal ["mechanical.zone_no_hot_water"], codes(serves_rows.fetch("Apt 1")),
                 "the feature's own action repairs it"

    refused(metadata("Apt 2", M::Serves::EMPTY.merge("heat_pump_ids" => [])), "validation.failed")
    assert_equal ["unknown fields heat_pump_ids"], M::Serves::Payload.problems(M::Serves::EMPTY
                                                                                 .merge("heat_pump_ids" => []))
    assert_equal ["missing fields ventilator_id, hot_water_system_id, hp_indoor_unit_ids, heater_ids, pump_ids"],
                 M::Serves::Payload.problems({})
    assert_equal ["ventilator_id must be a Ventilator id or null",
                  "hot_water_system_id must be a Hot Water System id or null",
                  "hp_indoor_unit_ids must be a list of Heat Pump Indoor Unit ids",
                  "heater_ids must be a list of Electric Heater ids",
                  "pump_ids must be a list of Pump ids"],
                 M::Serves::Payload.problems("ventilator_id" => "hws_ZZZZZZZZZZZZ",
                                             "hot_water_system_id" => "vnt_ZZZZZZZZZZZZ",
                                             "hp_indoor_unit_ids" => ["hpi_ZZZZZZZZZZZZ"],
                                             "heater_ids" => ["hwh_ZZZZZZZZZZZZ"],
                                             "pump_ids" => ["ehr_ZZZZZZZZZZZZ"])
    assert_equal ["hp_indoor_unit_ids holds an id twice"],
                 M::Serves::Payload.problems(M::Serves::EMPTY.merge("hp_indoor_unit_ids" => ["hiu_ZZZZZZZZZZZZ"] * 2))
  end

  # ---------------------------------------------------------------- beside Programs

  def test_serves_and_programs_writes_leave_each_others_payload_on_the_zone
    completed(save_segment(CERTIFICATION => PhComposer::Certification::Segment::DEFAULTS
                                            .merge("category" => "non_residential")))
    program = completed(invoke("#{PROGRAMS}.programs.create",
                               "values" => PhComposer::Programs::Program::EMPTY.merge("name" => "Office")))
              .fetch("id")
    completed(invoke("#{PROGRAMS}.assign_program", "zones" => [zone_row("Apt 1").fetch("reference")],
                                                   "program_id" => program))
    assignment = zone_row("Apt 1").dig("extension_data", "#{PROGRAMS}.zone_assignment")
    refute_nil assignment

    completed(assign(["Apt 1"], "ERV-1"))
    completed(assign(["Apt 1"], "ERV-2", :replace => true))
    completed(invoke("#{SERVES}.clear", "zones" => [target("Apt 1")]))
    completed(assign(["Apt 1"], "ERV-1"))
    completed(delete("ERV-1", :replacement => @erv.fetch("ERV-3")))
    assert_equal assignment, zone_row("Apt 1").dig("extension_data", "#{PROGRAMS}.zone_assignment")

    serves = zone_row("Apt 1").dig("extension_data", NAMESPACE)
    completed(invoke("#{PROGRAMS}.assign_program", "zones" => [zone_row("Apt 1").fetch("reference")],
                                                   "program_id" => nil))
    assert_equal serves, zone_row("Apt 1").dig("extension_data", NAMESPACE)
  end

  def test_a_serves_payload_never_blocks_export
    completed(assign(["Apt 1"], "ERV-1"))
    codes = completed(API.export_preflight(:context => @context)).fetch("findings").map { |row| row["code"] }
    refute(codes.any? { |code| code.start_with?("extension.") || code == "export.blocked" }, codes.inspect)
  end

  private

  def zone(base, letter, name, (x0, y0, width, depth))
    space = space_group(base + 10, space_record(letter, :number => "1", :name => name),
                        [volume_group(base + 20, volume_record(letter),
                                      [floor_face(base + 30, rectangle(x0, y0, width, depth),
                                                  segment_record(letter))])])
    group = Sketchup::Group.new(base, Sketchup::Entities.new([space]), :name => name)
    ZONES::ZONE_STORE.write(group, { "id" => "zon_#{letter * 12}", "schema_version" => 1, "name" => name,
                                     "building_segment" => "Apartments", "level" => "L1", "ground_depth_mm" => 0.0 })
    host_children([space], "zon_#{letter * 12}")
    group
  end

  # A Group copied with its attribute dictionaries, as a native copy leaves it before Zones makes it independent.
  def copy_of(name)
    original = zone_group_named(name)
    copy = Sketchup::Group.new(9000, original.entities, :name => name)
    Array(original.attribute_dictionaries).each do |dictionary|
      dictionary.each { |key, value| copy.set_attribute(dictionary.name, key, value) }
    end
    @model.entities << copy
    treat_duplicates_as_existing(@model)
    copy
  end

  def assign(names, item, replace: nil)
    params = { "zones" => names.map { |name| target(name) }, "slot" => "ventilator_id", "item_id" => @erv.fetch(item) }
    params["replace"] = replace unless replace.nil?
    invoke("#{SERVES}.assign", params)
  end

  def delete(name, replacement: :none)
    params = { "id" => @erv.fetch(name) }
    params["replacement_id"] = replacement unless replacement == :none
    invoke("#{VENTILATORS}.delete", params)
  end

  def target(name, expected = nil)
    row = serves_rows.fetch(name)
    { "reference" => row.fetch("reference"), "expected_values" => expected || row.fetch("slots") }
  end

  def metadata(name, payload)
    row = zone_row(name)
    invoke("ph_composer.zones.update_metadata", "updates" => [{
      "reference" => row.fetch("reference"),
      "expected_metadata" => { "user_data" => row.fetch("user_data", {}),
                               "extension_data" => row.fetch("extension_data", {}) },
      "extension_payloads" => { NAMESPACE => payload }
    }])
  end

  def save_segment(payloads)
    all = query("ph_composer.zones.options.all")
    row = all.fetch("building_segments").find { |candidate| candidate.dig("values", "name") == "Apartments" }
    values = row.fetch("values").slice("name", "colour")
    invoke("ph_composer.zones.save_segment_settings",
           "id" => row.fetch("id"), "values" => values, "expected_values" => values,
           "default" => all.fetch("default_segment_id") == row.fetch("id"),
           "expected_default_segment_id" => all.fetch("default_segment_id"), "extension_payloads" => payloads,
           "expected_extension_data" => row.fetch("extension_data", {}))
  end

  def serves_rows
    query("#{SERVES}.all").fetch("zones").to_h { |row| [row.fetch("name"), row] }
  end

  def slots(name)
    serves_rows.fetch(name).fetch("slots")
  end

  def ventilator_rows
    query("#{VENTILATORS}.all").fetch("records").to_h { |row| [row.dig("values", "name"), row] }
  end

  def ventilator_ids
    ventilator_rows.values.map { |row| row.fetch("id") }
  end

  def zone_row(name)
    query("ph_composer.zones.all").fetch("zones").find { |row| row.dig("values", "name") == name }
  end

  def stored_payload(name)
    zone_row(name).dig("extension_data", NAMESPACE, "payload")
  end

  def zone_group_named(name)
    @model.entities.to_a.find { |entity| entity.is_a?(Sketchup::Group) && entity.name == name }
  end

  def codes(row)
    row.fetch("findings").map { |finding| finding.fetch("code") }
  end

  def query(name, params = {})
    completed(API.query(:context => @context, :name => name, :params => params))
  end

  def completed(outcome)
    assert_equal "completed", outcome.fetch("status"), outcome.inspect
    outcome.fetch("value")
  end

  def refused(outcome, code)
    refute_equal "completed", outcome.fetch("status"), outcome.inspect
    assert_equal code, outcome.dig("error", "code") || outcome["code"], outcome.inspect
  end

  def invoke(name, params)
    API.invoke(:context => @context, :name => name, :params => params,
               :request => { "sequence" => @sequence += 1, "expected_revision" => @session.revision })
  end
end
