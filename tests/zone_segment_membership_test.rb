# frozen_string_literal: true

require_relative "test_helper"
require_relative "support/zone_options"

# A Zone names at most one Building Segment (Zone schema 3). The Model keeps at least one Segment, the default
# is never none, and every change is one Undo step through the same agent operations the panel uses.
class ZoneSegmentMembershipTest < PhComposerTestCase
  include ZoneOptionsSupport

  API = PhComposer::API
  Z = PhComposer::Zones
  O = Z::Options

  def setup
    super
    @model = Sketchup.active_model
    Z::Faces::Settings::STORE.write(@model, Z::Faces::Settings::DEFAULTS.merge("suggest_on_make" => false))
    @session = PhComposer::Sessions.for(@model)
    @context = API.connect(:session_id => @session.id)
    @sequence = 0
  end

  # ---------------------------------------------------------------- schema 3

  def test_schema_three_names_no_segment_and_schema_two_still_reads
    zone_id = make_zone(100)
    classify(zone_id)
    current = record(zone_id)
    assert_equal 3, current.fetch("schema_version")
    none = current.merge("building_segment_id" => nil,
                         "choice_evidence" => current.fetch("choice_evidence").merge("building_segment" => nil))
    assert_empty Z::Schema.problems(none)
    assert Z::Schema.stamp?(Z::Schema.stamp(none))
    refute_empty Z::Schema.problems(none.merge("schema_version" => 2)), "schema 2 still requires a Segment"
    refute Z::Schema.stamp?(Z::Schema.stamp(none).merge("schema_version" => 2))
    assert_includes Z::Schema.problems(current.merge("schema_version" => 4)),
                    "Zone schema_version must be 1, 2 or 3"

    # A schema 2 Zone and its stamps read unchanged, and the next write leaves schema 3 on both.
    stored = current.merge("schema_version" => 2)
    Z::ZONE_STORE.write(group_of(zone_id), stored)
    group_of(zone_id).entities.to_a.each { |face| Z::STAMP_STORE.write(face, Z::Schema.stamp(stored)) }
    row = zone_row(zone_id)
    assert_equal 2, row.fetch("schema_version")
    assert_equal current.fetch("building_segment_id"), row.dig("values", "building_segment_id")
    completed(set_segment([row], nil))
    assert_equal [3, nil], record(zone_id).values_at("schema_version", "building_segment_id")
    assert_equal [[3, nil]], stamps(zone_id).map { |stamp| stamp.values_at("schema_version", "building_segment_id") }
                                            .uniq
  end

  # ---------------------------------------------------------------- assigning

  def test_update_field_moves_a_zone_out_of_every_segment_and_back_each_in_one_undo_step
    zone_id = make_zone(100)
    classify(zone_id)
    default_id = record(zone_id).fetch("building_segment_id")
    operations = @model.operations.length

    completed(set_segment(zone_rows, nil))

    assert_nil record(zone_id).fetch("building_segment_id")
    assert_nil record(zone_id).dig("choice_evidence", "building_segment")
    assert_equal [nil], stamps(zone_id).map { |stamp| stamp.fetch("building_segment_id") }.uniq
    assert_equal operations + 1, @model.operations.length
    assert_equal default_id, query("#{O::PREFIX}.all").fetch("default_segment_id"), "the default is unchanged"
    assert_equal [{ "live" => 0, "recoverable" => 0 }], segment_usage
    @model.undo
    assert_equal default_id, record(zone_id).fetch("building_segment_id")
    assert_equal [default_id], stamps(zone_id).map { |stamp| stamp.fetch("building_segment_id") }.uniq
    @model.redo
    assert_nil record(zone_id).fetch("building_segment_id")

    completed(set_segment(zone_rows, "Building"))
    assert_equal default_id, record(zone_id).fetch("building_segment_id")
    assert_equal operations + 2, @model.operations.length
  end

  def test_a_stale_expected_segment_refuses_and_writes_nothing
    zone_id = make_zone(100)
    other = create_zone_option("building_segment", "Annex")
    rows = zone_rows
    rows.first.fetch("values")["building_segment_id"] = other
    before = record(zone_id)
    operations = @model.operations.length

    result = set_segment(rows, nil)

    assert_equal %w[refused target.changed none], result.values_at("status", "code", "effect")
    assert_equal before, record(zone_id)
    assert_equal operations, @model.operations.length
  end

  def test_the_whole_zone_edit_takes_a_null_segment_by_name
    zone_id = make_zone(100)
    row = zone_row(zone_id)
    values = { "name" => "Zone 1", "building_segment" => nil, "level" => nil, "ground_depth_mm" => 0.0 }
    completed(invoke("#{Z::FEATURE_ID}.update", "reference" => row.fetch("reference"), "values" => values,
                                                "expected_values" => row.fetch("values")))
    assert_nil record(zone_id).fetch("building_segment_id")
  end

  # ---------------------------------------------------------------- management

  def test_deleting_the_last_segment_refuses_and_writes_nothing
    zone_id = make_zone(100)
    segment_id = record(zone_id).fetch("building_segment_id")
    before = [record(zone_id), query("#{O::PREFIX}.all").fetch("building_segments")]
    operations = @model.operations.length

    removed = invoke("#{O::PREFIX}.remove", "collection" => "building_segment", "id" => segment_id,
                                            "replacement_id" => nil)
    emptied = manage_params.merge("options" => [], "replacements" => { segment_id => nil },
                                  "default_segment_id" => nil)
    managed = invoke("#{O::PREFIX}.manage", emptied)

    [removed, managed].each do |result|
      assert_equal %w[refused zone.option_last_segment none], result.values_at("status", "code", "effect")
    end
    assert_equal before, [record(zone_id), query("#{O::PREFIX}.all").fetch("building_segments")]
    assert_equal operations, @model.operations.length
  end

  def test_deleting_a_used_segment_moves_its_zones_to_the_named_segment_or_to_none
    house = make_zone(100)
    annex = make_zone(200)
    default_id = record(house).fetch("building_segment_id")
    annex_id = create_zone_option("building_segment", "Annex")
    completed(set_segment([zone_row(annex)], "Annex"))
    assert_equal "reference.in_use",
                 invoke("#{O::PREFIX}.remove", "collection" => "building_segment", "id" => annex_id).fetch("code"),
                 "a used Segment still needs an explicit destination"

    result = completed(invoke("#{O::PREFIX}.remove", "collection" => "building_segment", "id" => annex_id,
                                                     "replacement_id" => nil))

    assert_equal({ annex_id => nil }, result.fetch("replacement_ids"))
    assert_nil record(annex).fetch("building_segment_id")
    assert_equal default_id, record(house).fetch("building_segment_id")
    assert_equal [default_id], segment_ids
    @model.undo
    assert_equal annex_id, record(annex).fetch("building_segment_id")
    assert_equal [default_id, annex_id].sort, segment_ids
    @model.redo
    assert_nil record(annex).fetch("building_segment_id")
    assert_equal [default_id], segment_ids
    @model.undo

    merged = completed(invoke("#{O::PREFIX}.merge", "collection" => "building_segment", "id" => annex_id,
                                                    "target_id" => default_id))
    assert_equal({ annex_id => default_id }, merged.fetch("replacement_ids"))
    assert_equal default_id, record(annex).fetch("building_segment_id")
  end

  def test_deleting_the_default_moves_it_to_the_destination_else_the_first_remaining_segment
    zone_id = make_zone(100)
    default_id = record(zone_id).fetch("building_segment_id")
    first, second = [create_zone_option("building_segment", "North"),
                     create_zone_option("building_segment", "South")].sort

    completed(invoke("#{O::PREFIX}.remove", "collection" => "building_segment", "id" => default_id,
                                            "replacement_id" => second))
    assert_equal second, query("#{O::PREFIX}.all").fetch("default_segment_id")
    assert_equal second, record(zone_id).fetch("building_segment_id")
    @model.undo
    assert_equal default_id, query("#{O::PREFIX}.all").fetch("default_segment_id")

    completed(invoke("#{O::PREFIX}.remove", "collection" => "building_segment", "id" => default_id,
                                            "replacement_id" => nil))
    assert_equal first, query("#{O::PREFIX}.all").fetch("default_segment_id"), "first remaining, in id order"
    assert_nil record(zone_id).fetch("building_segment_id")
    @model.undo

    # The whole-collection route: a null default while the default is removed takes the same rule.
    params = manage_params
    params["options"] = params.fetch("options").reject { |row| row.fetch("id") == default_id }.reverse
    params["replacements"] = { default_id => nil }
    params["default_segment_id"] = nil
    completed(invoke("#{O::PREFIX}.manage", params))
    assert_equal second, query("#{O::PREFIX}.all").fetch("default_segment_id"), "first in the final collection"
  end

  def test_removing_a_segment_reports_its_extension_namespaces_and_undo_restores_them
    extension = register_segment_extension
    make_zone(100)
    annex_id = create_zone_option("building_segment", "Annex")
    stored = query("ph_composer.records.list", "kind" => O::SEGMENT_KIND, "ids" => [annex_id]).fetch("records").first
    completed(invoke("ph_composer.records.update_metadata", "updates" => [{
      "reference" => { "kind" => O::SEGMENT_KIND, "id" => annex_id },
      "extension_payloads" => { extension.namespace => { "note" => "settings" } },
      "expected_metadata" => stored.slice("user_data", "extension_data")
    }]))

    result = completed(invoke("#{O::PREFIX}.remove", "collection" => "building_segment", "id" => annex_id))

    assert_equal [{ "id" => annex_id, "namespaces" => [extension.namespace] }], result.fetch("removed_extensions")
    assert_equal 1, result.fetch("removed_extensions_total")
    refute_includes segment_ids, annex_id
    @model.undo
    restored = O::SEGMENTS.store.read(@model, annex_id)
    assert_equal({ "note" => "settings" }, restored.dig("extension_data", extension.namespace, "payload"))

    default_id = query("#{O::PREFIX}.all").fetch("default_segment_id")
    merged = completed(invoke("#{O::PREFIX}.merge", "collection" => "building_segment", "id" => annex_id,
                                                    "target_id" => default_id))
    assert_equal [[{ "id" => annex_id, "namespaces" => [extension.namespace] }], 1],
                 merged.values_at("removed_extensions", "removed_extensions_total")
    assert_empty O::SEGMENTS.store.read(@model, default_id).fetch("extension_data", {}), "settings are never merged"
  end

  def test_an_option_rewrite_leaves_the_zone_and_its_stamps_at_schema_three
    zone_id = make_zone(100)
    classify(zone_id)
    stored = record(zone_id).merge("schema_version" => 2)
    Z::ZONE_STORE.write(group_of(zone_id), stored)
    group_of(zone_id).entities.to_a.each { |face| Z::STAMP_STORE.write(face, Z::Schema.stamp(stored)) }
    params = manage_params
    params.fetch("options").first["name"] = "Main house"

    completed(invoke("#{O::PREFIX}.manage", params))

    assert_equal 3, record(zone_id).fetch("schema_version")
    assert_equal "Main house", record(zone_id).dig("choice_evidence", "building_segment", "name")
    assert_equal [3], stamps(zone_id).map { |stamp| stamp.fetch("schema_version") }.uniq
  end

  # ---------------------------------------------------------------- Make and Restore

  def test_make_zone_joins_the_default_and_restore_keeps_no_segment
    make_zone(100)
    annex_id = create_zone_option("building_segment", "Annex")
    completed(invoke("#{O::PREFIX}.manage", manage_params.merge("default_segment_id" => annex_id)))
    joined = make_zone(200)
    assert_equal annex_id, record(joined).fetch("building_segment_id")

    classify(joined)
    completed(set_segment([zone_row(joined)], nil))
    group = group_of(joined)
    members = group.entities.to_a
    @model.entities.delete(group)
    members.each { |face| @model.entities << face }
    offer = query("#{Z::FEATURE_ID}.list").fetch("restorable").first
    assert_equal joined, offer.fetch("zone_id")
    assert_nil offer.fetch("building_segment")

    completed(invoke("#{Z::FEATURE_ID}.restore", "parent_path" => [], "zone_id" => joined))
    assert_equal [3, nil], record(joined).values_at("schema_version", "building_segment_id")
  end

  # ---------------------------------------------------------------- reads, adoption and export

  def test_colour_by_building_segment_shows_zones_in_no_segment_as_one_neutral_row
    out = make_zone(100)
    make_zone(200)
    completed(set_segment([zone_row(out)], nil))
    request = PhComposer::HandlerRequest.for(@session, :owner => Z::FEATURE_ID, :name => "colour")

    entries = Z::ColourModes.option_entries(request, "building_segment")

    none = entries.find { |entry| entry.entity.equal?(group_of(out)) }
    assert_equal ["no_building_segment", "No Building Segment", [176, 176, 176]],
                 [none.value, none.label, none.colour]
    refute_includes PhComposer::ColourBy::Palette::RAMP, none.colour
    assert_equal ["Building"], (entries - [none]).map(&:label)
  end

  def test_a_copied_zone_in_no_segment_or_level_has_nothing_to_adopt_and_stays_editable
    zone_id = make_zone(100)
    copied = record(zone_id).merge("building_segment_id" => nil,
                                   "choice_evidence" => { "source_model_id" => "another_model",
                                                          "building_segment" => nil, "level" => nil })
    refute O::Adoption.needs_adoption?(request_engine, copied)

    # Pasted into a Model with no options of its own: renaming it and creating a Level keep valid evidence.
    @model = Sketchup::Model.new
    Sketchup.active_model = @model
    @session = PhComposer::Sessions.for(@model)
    @context = API.connect(:session_id => @session.id)
    face = Sketchup::Face.new(101)
    pasted = Sketchup::Group.new(100, Sketchup::Entities.new([face]))
    @model.entities << pasted
    Z::ZONE_STORE.write(pasted, copied)
    Z::STAMP_STORE.write(face, Z::Schema.stamp(copied))
    row = zone_row(zone_id)
    completed(invoke("#{Z::FEATURE_ID}.update", "reference" => row.fetch("reference"),
                                                "values" => row.fetch("values").merge("name" => "Renamed"),
                                                "expected_values" => row.fetch("values")))
    create_zone_option("level", "Upper")
    assert_empty Z::Schema.problems(record(zone_id))
    assert_equal ["Renamed", "another_model"], [record(zone_id).fetch("name"),
                                                record(zone_id).dig("choice_evidence", "source_model_id")]
    assert completed(API.query(:context => @context, :name => "#{O::PREFIX}.all"))
  end

  def test_adopting_copied_zones_that_bring_only_a_level_makes_the_default_segment
    level = { "id" => "lvl_AAAAAAAAAAAA", "schema_version" => 1, "name" => "Upper", "colour" => "#ABCDEF" }
    copied = { "id" => "zon_AAAAAAAAAAAA", "schema_version" => 3, "name" => "Copied", "ground_depth_mm" => 0.0,
               "building_segment_id" => nil, "level_id" => level.fetch("id"),
               "choice_evidence" => { "source_model_id" => "another_model", "building_segment" => nil,
                                      "level" => level } }
    face = Sketchup::Face.new(101)
    group = Sketchup::Group.new(100, Sketchup::Entities.new([face]))
    @model.entities << group
    Z::ZONE_STORE.write(group, copied)
    Z::STAMP_STORE.write(face, Z::Schema.stamp(copied))

    adopt_zone_options

    options = query("#{O::PREFIX}.all")
    assert_equal ["Building"], options.fetch("building_segments").map { |row| row.dig("values", "name") }
    assert_equal options.dig("building_segments", 0, "id"), options.fetch("default_segment_id")
    adopted = record(copied.fetch("id"))
    assert_nil adopted.fetch("building_segment_id"), "adoption leaves the Zone in no Segment"
    assert_equal options.dig("levels", 0, "id"), adopted.fetch("level_id")
  end

  def test_export_preflight_blocks_a_zone_in_no_segment
    zone_id = make_zone(100)
    completed(set_segment([zone_row(zone_id)], nil))

    findings = completed(API.export_preflight(:context => @context)).fetch("findings")

    blocking = findings.find { |row| row["object_id"] == zone_id }
    assert_equal "reference.invalid", blocking.fetch("code")
    assert blocking.fetch("blocks_export")
  end

  private

  def make_zone(id)
    faces = 3.times.map do |index|
      Sketchup::Face.new(id + index + 1, {}, :points => [Geom::Point3d.new(0, 0, index),
                                                         Geom::Point3d.new(2, 0, index),
                                                         Geom::Point3d.new(2, 2, index)])
    end
    group = Sketchup::Group.new(id, Sketchup::Entities.new(faces))
    @model.entities << group
    completed(invoke("#{Z::FEATURE_ID}.make", "parent_path" => [], "entity_ids" => [id])).fetch("zone_id")
  end

  # The stub's Undo restores a copy of the entities, so a Zone is found again by id after each step.
  def group_of(zone_id)
    @model.entities.grep(Sketchup::Group).find { |group| Z::ZONE_STORE.read(group)&.fetch("id") == zone_id }
  end

  def record(zone_id)
    Z::ZONE_STORE.read(group_of(zone_id))
  end

  def stamps(zone_id)
    group_of(zone_id).entities.to_a.map { |face| Z::STAMP_STORE.read(face) }
  end

  # Classification stamps each Face with its Zone's membership, the evidence Restore reads.
  def classify(zone_id)
    faces = query("#{Z::Faces::PREFIX}.list").fetch("faces")
                                             .select { |face| face.dig("reference", "zone_id") == zone_id }
    completed(invoke("#{Z::Faces::PREFIX}.classify",
                     "faces" => faces.map { |face| face.fetch("reference") },
                     "intent" => { "face_type" => { "mode" => "set", "value" => "Wall" },
                                   "boundary_condition" => { "mode" => "set", "value" => "Outdoors" } },
                     "expected_values" => {}))
  end

  def query(name, params = {})
    completed(API.query(:context => @context, :name => name, :params => params))
  end

  def invoke(name, params)
    @sequence += 1
    API.invoke(:context => @context, :name => name, :params => params,
               :request => { "sequence" => @sequence, "expected_revision" => @session.revision })
  end

  def completed(outcome)
    assert_equal "completed", outcome.fetch("status"), outcome.inspect
    outcome.fetch("value")
  end

  def zone_rows
    query("#{Z::FEATURE_ID}.all").fetch("zones")
  end

  def zone_row(zone_id)
    zone_rows.find { |row| row.dig("reference", "zone_id") == zone_id }
  end

  def set_segment(rows, name)
    invoke("#{Z::FEATURE_ID}.update_field",
           "field" => "building_segment", "value" => name,
           "targets" => rows.map { |row|
             { "reference" => row.fetch("reference"),
               "expected_values" => row.fetch("values") }
           })
  end

  def segment_ids
    query("#{O::PREFIX}.all").fetch("building_segments").map { |row| row.fetch("id") }.sort
  end

  def segment_usage
    query("#{O::PREFIX}.all").fetch("building_segments").map { |row| row.fetch("usage") }
  end

  def manage_params
    options = query("#{O::PREFIX}.all")
    list = options.fetch("building_segments").map do |row|
      row.fetch("values").slice("name", "colour").merge("id" => row.fetch("id"))
    end
    { "collection" => "building_segment", "options" => PhComposer::DeepCopy.call(list), "expected_options" => list,
      "default_segment_id" => options.fetch("default_segment_id"),
      "expected_default_segment_id" => options.fetch("default_segment_id"), "replacements" => {} }
  end

  def request_engine
    PhComposer::HandlerRequest.for(@session, :owner => Z::FEATURE_ID, :name => "adoption").engine
  end

  def register_segment_extension
    extension = PhComposer::Records::Extension.new(:namespace => "test.segment.settings", :schema_version => 1,
                                                   :export_relevance => "local_only")
    fixture = Module.new do
      define_singleton_method(:install) do |registry|
        registry.feature("test.segment", :contract_version => 1).extension(extension)
      end
    end
    PhComposer::Registry.install([fixture])
    extension
  end
end
