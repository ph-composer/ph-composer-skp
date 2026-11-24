# frozen_string_literal: true

require_relative "test_helper"
require_relative "support/space_fixtures"
require_relative "support/zone_options"
require_relative "support/zone_payload_probe"

# A feature's payload on the Zone record that names its own records through a `one` and a `many` declared reference
# (context/CONTRACTS.md, "Records and extension data"), written through Zones' proposal participant by the
# test-only ZonePayloadProbe: a plain delete of an item either slot names refuses, a delete with a replacement moves
# both slots in one Undo step, a copy of the Zone carries the payload, and a locked Zone refuses the write.
# The Zone-keyed Colour-by projection reaches each Zone occurrence from Zones' public read, as Zones' own mode does.
class ZonePayloadReferencesTest < PhComposerTestCase
  include SpaceFixtures
  include ZoneOptionsSupport

  API = PhComposer::API
  PROBE = ZonePayloadProbe
  INCHES = 1.0 / 0.0254

  def setup
    super
    @model = Sketchup.active_model
    @session = PhComposer::Sessions.for(@model)
    @context = API.connect(:session_id => @session.id)
    @sequence = 0
    shifted = Sketchup::Group.new(8000, Sketchup::Entities.new([zone(2000, "B", "Apt 2", [0, 0, 5, 5])]),
                                  :transformation => Geom::Transformation.translation([400, 0, 0]))
    @model.entities << zone(1000, "A", "Apt 1", [0, 0, 5, 5]) << shifted
    adopt_zone_options
    PhComposer::Registry.install([PROBE])
    @items = %w[First Second Third].to_h do |name|
      [name, completed(invoke(PROBE::CREATE, "name" => name)).fetch("id")]
    end
  end

  def test_a_plain_delete_refuses_an_item_named_in_either_slot_and_deletes_one_named_nowhere
    first, second, third = @items.values_at("First", "Second", "Third")
    completed(assign("Apt 1" => { "single_id" => first, "multiple_ids" => [] },
                     "Apt 2" => { "single_id" => nil, "multiple_ids" => [second] }))
    revision = @session.revision
    operations = @model.operations.length

    refused(delete(first), "reference.in_use")
    refused(delete(second), "reference.in_use")
    assert_equal [revision, operations], [@session.revision, @model.operations.length]
    completed(delete(third))
    refute_includes item_ids, third
  end

  def test_a_delete_with_a_replacement_moves_both_slots_in_one_undo_step
    first, second, third = @items.values_at("First", "Second", "Third")
    completed(assign("Apt 1" => { "single_id" => first, "multiple_ids" => [first, second] },
                     "Apt 2" => { "single_id" => nil, "multiple_ids" => [first] }))
    before = payloads
    operations = @model.operations.length

    completed(delete(first, :replacement => third))
    assert_equal operations + 1, @model.operations.length
    assert_equal({ "Apt 1" => { "single_id" => third, "multiple_ids" => [third, second] },
                   "Apt 2" => { "single_id" => nil, "multiple_ids" => [third] } }, payloads)
    refute_includes item_ids, first

    @model.undo
    assert_equal before, payloads
    assert_includes item_ids, first
  end

  def test_a_replacement_already_in_the_list_is_held_once
    first, second = @items.values_at("First", "Second")
    completed(assign("Apt 1" => { "single_id" => nil, "multiple_ids" => [first, second] }))

    completed(delete(first, :replacement => second))
    assert_equal({ "single_id" => nil, "multiple_ids" => [second] }, payloads.fetch("Apt 1"))
  end

  # The stub's copy carries the Group's attribute dictionaries, as SketchUp's native copy does; the host shows the
  # native gesture itself.
  def test_a_copy_of_the_zone_keeps_its_payload
    first, second = @items.values_at("First", "Second")
    completed(assign("Apt 1" => { "single_id" => first, "multiple_ids" => [second] }))
    original = zone_group_named("Apt 1")
    copy = Sketchup::Group.new(9000, original.entities, :name => "Apt 1")
    Array(original.attribute_dictionaries).each do |dictionary|
      dictionary.each { |key, value| copy.set_attribute(dictionary.name, key, value) }
    end
    @model.entities << copy
    treat_duplicates_as_existing(@model)
    completed(invoke("ph_composer.zones.make_independent", "zone_path" => [9000]))

    rows = zone_rows.select { |row| row.dig("values", "name") == "Apt 1" }
    assert_equal 2, rows.map { |row| row.fetch("id") }.uniq.length, "the copy is its own Zone"
    expected = { "single_id" => first, "multiple_ids" => [second] }
    assert_equal [expected, expected], rows.map { |row| payload(row) }

    original_reference = rows.find { |row| row.dig("reference", "zone_path") == [1000] }.fetch("reference")
    completed(invoke(PROBE::ASSIGN, "zones" => [{ "reference" => original_reference, "payload" => PROBE::EMPTY }]))
    refused(delete(second), "reference.in_use")
  end

  def test_a_locked_zone_refuses_the_write_and_a_replacement_delete_touching_it
    first, third = @items.values_at("First", "Third")
    completed(assign("Apt 1" => { "single_id" => nil, "multiple_ids" => [first] }))
    zone_group_named("Apt 1").locked = true
    revision = @session.revision
    operations = @model.operations.length

    refused(assign("Apt 1" => { "single_id" => first, "multiple_ids" => [first] }), "target.locked")
    refused(delete(first, :replacement => third), "target.locked")
    assert_equal [revision, operations], [@session.revision, @model.operations.length]
    assert_equal({ "single_id" => nil, "multiple_ids" => [first] }, payloads.fetch("Apt 1"))
    assert_includes item_ids, first
  end

  # A copy that keeps its Zone id is a second occurrence of one Zone: one entry each, as Zones' mode gives.
  def test_a_zone_keyed_projection_from_the_public_read_reaches_the_entities_the_zone_mode_paints
    first = @items.fetch("First")
    completed(assign("Apt 1" => { "single_id" => first, "multiple_ids" => [] }))
    original = zone_group_named("Apt 1")
    copy = Sketchup::Group.new(9000, original.entities, :name => "Apt 1")
    Array(original.attribute_dictionaries).each do |dictionary|
      dictionary.each { |key, value| copy.set_attribute(dictionary.name, key, value) }
    end
    @model.entities << copy
    treat_duplicates_as_existing(@model)

    probe = project(PROBE::BY_SINGLE).sort_by { |entry| entry.path }
    zones = project(PhComposer::Zones::ColourModes::BY_ZONE).sort_by { |entry| entry.path }
    assert_equal [[1000], [8000, 2000], [9000]], probe.map(&:path)
    assert_equal zones.map { |entry| [entry.entity, entry.path, entry.transform.to_a] },
                 probe.map { |entry| [entry.entity, entry.path, entry.transform.to_a] }
    assert_equal [first, nil, first], probe.map(&:value)
    assert_in_delta 400, probe[1].transform.to_a[12], 1e-9, "the nested Zone's parent offset is composed"

    service = PhComposer::ColourBy.for(@session).activate(PROBE::BY_SINGLE)
    assert_equal [2, 1], service.rows.map(&:count), "two occurrences with the item, one unclassified"
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

  def project(mode)
    declaration = PhComposer::Registry.current.colour_modes.fetch(mode)
    read = PhComposer::HandlerRequest.for(@session, :owner => declaration.owner, :name => declaration.name)
    Array(declaration.projection.call(read))
  end

  def assign(payloads_by_name)
    zones = payloads_by_name.map { |name, payload| { "reference" => reference(name), "payload" => payload } }
    invoke(PROBE::ASSIGN, "zones" => zones)
  end

  def delete(id, replacement: nil)
    params = { "id" => id }
    params["replacement_id"] = replacement if replacement
    invoke(PROBE::DELETE, params)
  end

  def zone_rows
    query("ph_composer.zones.all").fetch("zones")
  end

  def payload(row)
    row.fetch("extension_data", {}).dig(PROBE::NAMESPACE, "payload")
  end

  def payloads
    zone_rows.to_h { |row| [row.dig("values", "name"), payload(row)] }.compact
  end

  def reference(name)
    zone_rows.find { |row| row.dig("values", "name") == name }.fetch("reference")
  end

  def item_ids
    query("ph_composer.records.list", "kind" => PROBE::ITEM_KIND).fetch("records").map { |row| row.fetch("id") }
  end

  def zone_group_named(name)
    @model.entities.to_a.find { |entity| entity.is_a?(Sketchup::Group) && entity.name == name }
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
