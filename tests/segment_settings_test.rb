# frozen_string_literal: true

require_relative "test_helper"

# The Building Segment settings dialog's Save (ph_composer.zones.save_segment_settings) and New Building
# Segment (ph_composer.zones.create_segment): a development feature registers two settings namespaces and a
# contributor to the save transition, as Programs will. Save writes the General values and every namespace in
# one Undo step, refuses a payload its validator refuses without writing anything, is not blocked by a locked
# member Zone, and the transition reaches the contributor inside the same step.
class SegmentSettingsTest < PhComposerTestCase
  API = PhComposer::API
  Z = PhComposer::Zones
  O = Z::Options
  S = O::SegmentSettings
  NOTE = "test.segment.note"
  RATING = "test.segment.rating"
  LOG = "test.segment.log"

  def setup
    super
    @model = Sketchup.active_model
    Z::Faces::Settings::STORE.write(@model, Z::Faces::Settings::DEFAULTS.merge("suggest_on_make" => false))
    @session = PhComposer::Sessions.for(@model)
    @context = API.connect(:session_id => @session.id)
    @sequence = 0
    install_development_feature
  end

  def test_save_writes_general_values_and_two_namespaces_as_one_undo_step
    make_zone(100)
    segment = segment_row
    operations = @model.operations.length

    result = completed(save(segment, :values => { "name" => "House", "colour" => "#5588BB" },
                                     :payloads => { NOTE => { "text" => "north wing" },
                                                    RATING => { "stars" => 4 } }))

    assert_equal [NOTE, RATING], result.fetch("namespaces")
    assert_equal operations + 1, @model.operations.length
    saved = O::SEGMENTS.store.read(@model, segment.fetch("id"))
    assert_equal %w[House #5588BB], saved.values_at("name", "colour")
    assert_equal({ "text" => "north wing" }, saved.dig("extension_data", NOTE, "payload"))
    assert_equal({ "stars" => 4 }, saved.dig("extension_data", RATING, "payload"))
    assert_equal "House", zone_record.dig("choice_evidence", "building_segment", "name"), "a rename reaches members"
    @model.undo
    restored = O::SEGMENTS.store.read(@model, segment.fetch("id"))
    assert_equal segment.dig("values", "name"), restored.fetch("name")
    assert_empty restored.fetch("extension_data", {})
    @model.redo
    assert_equal({ "stars" => 4 }, O::SEGMENTS.store.read(@model, segment.fetch("id"))
                                             .dig("extension_data", RATING, "payload"))
  end

  def test_a_payload_its_validator_refuses_blocks_save_and_writes_nothing
    make_zone(100)
    segment = segment_row
    revision = @session.revision
    outcome = save(segment, :values => { "name" => "Renamed", "colour" => "#5588BB" },
                            :payloads => { NOTE => { "text" => "fine" }, RATING => { "stars" => 9 } })
    assert_equal %w[refused validation.failed none], outcome.values_at("status", "code", "effect"), outcome.inspect
    assert_equal revision, @session.revision
    stored = O::SEGMENTS.store.read(@model, segment.fetch("id"))
    assert_equal segment.dig("values", "name"), stored.fetch("name")
    assert_empty stored.fetch("extension_data", {})
    assert_empty logs
  end

  def test_a_locked_member_zone_does_not_block_a_settings_save
    group = make_zone(100)
    segment = segment_row
    before = zone_record
    group.locked = true
    completed(save(segment, :payloads => { NOTE => { "text" => "locked members" } }))
    assert_equal before, zone_record
    assert_equal({ "text" => "locked members" },
                 O::SEGMENTS.store.read(@model, segment.fetch("id")).dig("extension_data", NOTE, "payload"))
  end

  # A rename rewrites each member Zone's evidence, so a locked member refuses it as any option edit does.
  def test_a_rename_with_a_locked_member_zone_refuses_and_writes_nothing
    group = make_zone(100)
    segment = segment_row
    group.locked = true
    outcome = save(segment, :values => { "name" => "Renamed", "colour" => segment.dig("values", "colour") },
                            :payloads => { NOTE => { "text" => "with a rename" } })
    assert_equal %w[refused target.locked none], outcome.values_at("status", "code", "effect"), outcome.inspect
    stored = O::SEGMENTS.store.read(@model, segment.fetch("id"))
    assert_equal segment.dig("values", "name"), stored.fetch("name")
    assert_empty stored.fetch("extension_data", {})
  end

  def test_the_transition_reaches_a_contributor_inside_the_same_undo_step
    make_zone(100)
    segment = segment_row
    completed(save(segment, :payloads => { NOTE => { "text" => "a" }, RATING => {} }))
    assert_equal [[segment.fetch("id"), [NOTE, RATING]]], logs.map { |row| row.values_at("segment", "namespaces") }
    # A second save that changes one payload names that namespace alone.
    completed(save(segment_row, :payloads => { NOTE => { "text" => "b" }, RATING => {} }))
    assert_equal [[NOTE], [NOTE, RATING]], logs.map { |row| row.fetch("namespaces") }.sort
    @model.undo
    assert_equal 1, logs.length, "the contributor's record leaves with the save it joined"
  end

  def test_stale_values_or_settings_refuse_and_write_nothing
    make_zone(100)
    segment = segment_row
    stale = save(segment, :expected_values => { "name" => "Elsewhere", "colour" => segment.dig("values", "colour") })
    assert_equal %w[refused target.changed], stale.values_at("status", "code")
    completed(save(segment, :payloads => { NOTE => { "text" => "first" } }))
    late = save(segment, :payloads => { NOTE => { "text" => "second" } })
    assert_equal %w[refused target.changed], late.values_at("status", "code"), "the dialog read no settings"
    all = query("#{O::PREFIX}.all")
    other = completed(invoke(S::CREATE, "colour" => "#9977AA"))
    values = { "name" => other.fetch("name"), "colour" => "#9977AA" }
    stale_default = invoke(S::SAVE, "id" => other.fetch("id"), "values" => values, "expected_values" => values,
                                    "default" => false, "expected_default_segment_id" => other.fetch("id"),
                                    "extension_payloads" => {}, "expected_extension_data" => {})
    assert_equal %w[refused target.changed], stale_default.values_at("status", "code"),
                 "the default the dialog read was #{all.fetch('default_segment_id')}"
  end

  # The development example (tools/examples/zones/example_segment_note*.rb) is a working settings namespace.
  def test_the_development_example_namespace_saves_and_its_validator_refuses_a_blank_note
    load File.expand_path("../tools/examples/zones/example_segment_note_load.rb", __dir__)
    make_zone(100)
    segment = segment_row
    blank = save(segment, :payloads => { ExampleSegmentNote::NAMESPACE => { "text" => " " } })
    assert_equal %w[refused validation.failed], blank.values_at("status", "code")
    completed(save(segment, :payloads => { ExampleSegmentNote::NAMESPACE => { "text" => "north" } }))
    assert_equal({ "text" => "north" }, O::SEGMENTS.store.read(@model, segment.fetch("id"))
                                                 .dig("extension_data", ExampleSegmentNote::NAMESPACE, "payload"))
  end

  def test_new_zones_join_another_segment_once_saved_as_default_and_the_default_cannot_be_unset
    make_zone(100)
    annex = completed(invoke(S::CREATE, "colour" => "#9977AA"))
    assert_equal "Building Segment 2", annex.fetch("name")
    annex_row = segment_row(annex.fetch("id"))
    completed(save(annex_row, :default => true))
    assert_equal annex.fetch("id"), query("#{O::PREFIX}.all").fetch("default_segment_id")
    refused = save(segment_row(annex.fetch("id")), :default => false)
    assert_equal %w[refused params.invalid], refused.values_at("status", "code")
  end

  def test_create_segment_with_a_stale_zone_refuses_and_makes_no_segment
    make_zone(100)
    row = query("#{Z::FEATURE_ID}.all").fetch("zones").first
    stale = row.fetch("values").merge("name" => "Elsewhere")
    outcome = invoke(S::CREATE, "colour" => "#9977AA",
                                "targets" => [{ "reference" => row.fetch("reference"), "expected_values" => stale }])
    assert_equal %w[refused target.changed none], outcome.values_at("status", "code", "effect"), outcome.inspect
    assert_equal 1, query("#{O::PREFIX}.all").fetch("building_segments").length
  end

  # The Zones and Spaces reads publish each Segment's sums the heading rows show, keyed by the Segment's id, or ""
  # for Zones in no Segment.
  def test_the_zones_read_sums_each_segment_and_no_segment_by_key
    make_zone(100)
    make_zone(200)
    rows = query("#{Z::FEATURE_ID}.all").fetch("zones")
    target = { "reference" => rows.last.fetch("reference"), "expected_values" => rows.last.fetch("values") }
    completed(invoke("#{Z::FEATURE_ID}.update_field", "field" => "building_segment", "value" => nil,
                                                      "targets" => [target]))
    read = query("#{Z::FEATURE_ID}.all")
    sums = read.fetch("building_segments").to_h { |row| [row.fetch("key"), row] }
    assert_equal [segment_row.fetch("id"), ""].sort, sums.keys.sort
    read.fetch("zones").each do |zone|
      key = zone.dig("values", "building_segment_id") || ""
      assert_in_delta zone.fetch("face_area_m2"), sums.fetch(key).fetch("face_area_m2"), 1e-9
      assert_equal 1, sums.fetch(key).fetch("zone_count")
    end
  end

  def test_create_segment_moves_the_named_zones_in_one_undo_step
    make_zone(100)
    make_zone(200)
    default_id = segment_row.fetch("id")
    rows = query("#{Z::FEATURE_ID}.all").fetch("zones")
    operations = @model.operations.length
    created = completed(invoke(S::CREATE, "colour" => "#9977AA", "targets" => rows.first(1).map do |row|
      { "reference" => row.fetch("reference"), "expected_values" => row.fetch("values") }
    end))
    assert_equal operations + 1, @model.operations.length
    moved = query("#{Z::FEATURE_ID}.all").fetch("zones").map { |row| row.dig("values", "building_segment_id") }
    assert_equal [created.fetch("id"), default_id].sort, moved.sort
    @model.undo
    refute_includes query("#{O::PREFIX}.all").fetch("building_segments").map { |row| row.fetch("id") },
                    created.fetch("id")
  end

  private

  def install_development_feature
    note = PhComposer::Records::Extension.new(
      :namespace => NOTE, :schema_version => 1, :export_relevance => "local_only",
      :validate => ->(payload) { payload["text"].is_a?(String) ? [] : ["text must be a string"] }
    )
    rating = PhComposer::Records::Extension.new(
      :namespace => RATING, :schema_version => 1, :export_relevance => "local_only",
      :validate => lambda { |payload|
        stars = payload.fetch("stars", 0)
        stars.is_a?(Integer) && stars.between?(0, 5) ? [] : ["stars must be 0 to 5"]
      }
    )
    log = PhComposer::Records::RecordKind.new(
      :id => LOG, :label => "Settings log", :schema_version => 1, :id_prefix => "tsl",
      :fields => [PhComposer::Records::Field.new(:key => "segment", :required => true,
                                                 :schema => { "type" => "string" }),
                  PhComposer::Records::Field.new(:key => "namespaces", :required => true,
                                                 :schema => { "type" => "array" })]
    )
    fixture = Module.new do
      define_singleton_method(:install) do |registry|
        feature = registry.feature("test.segment", :contract_version => 1, :requires => [Z::FEATURE_ID])
        feature.extension(note)
        feature.extension(rating)
        feature.record_kind(log)
        feature.transition_contributor("test.segment.follow_save", :transition => S::TRANSITION) do |request, proposal,
                                                                                                    description|
          id = request.engine.propose_create(LOG, proposal,
                                             :values => { "segment" => description.fetch("building_segment_id"),
                                                          "namespaces" => description.fetch("namespaces") })
          [{ "kind" => LOG, "id" => id }]
        end
      end
    end
    PhComposer::Registry.install([fixture])
  end

  def logs
    query("ph_composer.records.list", "kind" => LOG).fetch("records").map { |row| row.fetch("values") }
  end

  def save(segment, values: nil, expected_values: nil, default: nil, payloads: {})
    stored = segment.fetch("values").slice("name", "colour")
    all = query("#{O::PREFIX}.all")
    invoke(S::SAVE, "id" => segment.fetch("id"), "values" => values || stored,
                    "expected_values" => expected_values || stored,
                    "default" => default.nil? ? all.fetch("default_segment_id") == segment.fetch("id") : default,
                    "expected_default_segment_id" => all.fetch("default_segment_id"),
                    "extension_payloads" => payloads,
                    "expected_extension_data" => segment.fetch("extension_data", {}))
  end

  def segment_row(id = nil)
    rows = query("#{O::PREFIX}.all").fetch("building_segments")
    id ? rows.find { |row| row.fetch("id") == id } : rows.first
  end

  def zone_record
    Z::ZONE_STORE.read(@model.entities.grep(Sketchup::Group).first)
  end

  def make_zone(id)
    faces = 3.times.map do |index|
      Sketchup::Face.new(id + index + 1, {}, :points => [Geom::Point3d.new(0, 0, index),
                                                         Geom::Point3d.new(2, 0, index),
                                                         Geom::Point3d.new(2, 2, index)])
    end
    group = Sketchup::Group.new(id, Sketchup::Entities.new(faces))
    @model.entities << group
    completed(invoke("#{Z::FEATURE_ID}.make", "parent_path" => [], "entity_ids" => [id]))
    group
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
end
