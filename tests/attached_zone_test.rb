# frozen_string_literal: true

require_relative "test_helper"

# Attached zones: the record kind, its reference lifecycle on a Face, and the guarded delete that
# moves every referencing Face and removes the definition in one step.
class AttachedZoneTest < PhComposerTestCase
  API = PhComposer::API
  KIND = PhComposer::Zones::Faces::AttachedZone::KIND_ID

  def setup
    super
    @model = Sketchup.active_model
    # This fixture exercises hand classification; default-on Make/Suggest has its own settings tests.
    settings = PhComposer::Zones::Faces::Settings
    settings::STORE.write(@model, settings::DEFAULTS.merge("suggest_on_make" => false))
    @session = PhComposer::Sessions.for(@model)
    @context = API.connect(:session_id => @session.id)
    @sequence = 0
    make_box_zone(100, 3)
  end

  def test_a_new_record_takes_the_phius_default_factor_and_is_readable_through_the_shared_query
    result = invoke("#{KIND}.save", { "values" => { "name" => "Garage", "kind" => "garage" } })

    assert_equal "completed", result.fetch("status")
    record = records.first

    assert_equal "Garage", record.dig("values", "name")
    assert_in_delta 0.95, record.dig("values", "temperature_reduction_factor")
  end

  def test_a_factor_below_the_phius_floor_is_accepted_with_a_finding_naming_the_estimator
    result = invoke("#{KIND}.save", { "values" => { "name" => "Crawlspace", "kind" => "crawlspace",
                                                    "temperature_reduction_factor" => 0.7 } })

    assert_equal "completed", result.fetch("status")
    assert_equal ["attached_zone.factor_below_phius_floor"], result.fetch("findings").map { |row| row.fetch("code") }
  end

  def test_an_attached_zone_with_no_chosen_record_is_stored_as_an_incomplete_state
    face = faces.first

    invoke("ph_composer.zones.faces.classify", {
      "faces" => [face.fetch("reference")],
      "intent" => { "face_type" => { "mode" => "set", "value" => "Wall" },
                    "boundary_condition" => { "mode" => "set", "value" => "AttachedZone" } },
      "expected_values" => {}
    })

    assert_equal "absent", faces.first.fetch("attached_zone_state")
  end

  def test_a_face_naming_a_missing_record_reads_as_dangling_and_a_valid_one_as_resolved
    id = create_zone_record("Garage")
    assign(faces.first, id)

    assert_equal "resolved", faces.first.fetch("attached_zone_state")

    KIND_STORE.delete(@model, id)

    assert_equal "dangling", faces.first.fetch("attached_zone_state")
  end

  def test_changing_away_from_attached_zone_clears_the_reference
    id = create_zone_record("Garage")
    face = assign(faces.first, id)

    invoke("ph_composer.zones.faces.classify", {
      "faces" => [face.fetch("reference")],
      "intent" => { "boundary_condition" => { "mode" => "set", "value" => "Outdoors" } },
      "expected_values" => {}
    })

    values = faces.first.fetch("values")

    assert_equal "Outdoors", values.fetch("boundary_condition")
    refute values.key?("attached_zone_id")
    assert_nil faces.first.fetch("attached_zone_state")
  end

  def test_an_edit_that_does_not_name_the_factor_still_reports_the_low_factor_finding
    id = invoke("#{KIND}.save", { "values" => { "name" => "Crawlspace", "kind" => "crawlspace",
                                                "temperature_reduction_factor" => 0.7 } }).dig("value", "id")

    renamed = invoke("#{KIND}.save", { "id" => id, "values" => { "name" => "Vented crawlspace" } })

    assert_equal "completed", renamed.fetch("status")
    assert_equal ["attached_zone.factor_below_phius_floor"], renamed.fetch("findings").map { |row| row.fetch("code") }
  end

  def test_raising_the_factor_clears_the_finding
    id = invoke("#{KIND}.save", { "values" => { "name" => "Attic", "kind" => "attic",
                                                "temperature_reduction_factor" => 0.7 } }).dig("value", "id")

    raised = invoke("#{KIND}.save", { "id" => id, "values" => { "temperature_reduction_factor" => 0.95 } })

    assert_empty raised.fetch("findings")
  end

  def test_setting_the_reference_without_the_condition_refuses_instead_of_dropping_it
    id = create_zone_record("Garage")

    result = invoke("ph_composer.zones.faces.classify", {
      "faces" => [faces.first.fetch("reference")],
      "intent" => { "face_type" => { "mode" => "set", "value" => "Wall" },
                    "attached_zone_id" => { "mode" => "set", "value" => id } },
      "expected_values" => {}
    })

    assert_equal %w[refused params.invalid none], result.values_at("status", "code", "effect")
    assert_empty faces.first.fetch("values")
  end

  def test_delete_with_a_replacement_record_moves_every_referencing_face_in_one_step
    garage = create_zone_record("Garage")
    attic = create_zone_record("Attic", "attic")
    faces.first(2).each { |face| assign(face, garage) }

    result = invoke("#{KIND}.delete", { "id" => garage,
                                        "replacement" => { "mode" => "attached_zone",
                                                           "attached_zone_id" => attic } })

    assert_equal %w[completed committed], result.values_at("status", "effect")
    assert_equal 2, result.dig("value", "reassigned_faces")
    assert_equal [attic], records.map { |record| record.fetch("id") }
    assert_equal [attic, attic], faces.first(2).map { |face| face.dig("values", "attached_zone_id") }

    @model.undo

    assert_equal [garage, attic].sort, records.map { |record| record.fetch("id") }.sort
    assert_equal [garage, garage], faces.first(2).map { |face| face.dig("values", "attached_zone_id") }
  end

  def test_delete_with_a_replacement_boundary_condition_reclassifies_and_clears_the_reference
    garage = create_zone_record("Garage")
    assign(faces.first, garage)

    result = invoke("#{KIND}.delete", { "id" => garage,
                                        "replacement" => { "mode" => "boundary_condition",
                                                           "boundary_condition" => "Adiabatic" } })

    assert_equal "completed", result.fetch("status")
    assert_empty records
    values = faces.first.fetch("values")

    assert_equal "Adiabatic", values.fetch("boundary_condition")
    refute values.key?("attached_zone_id")
  end

  def test_delete_naming_a_missing_replacement_refuses_and_writes_nothing
    garage = create_zone_record("Garage")
    assign(faces.first, garage)

    result = invoke("#{KIND}.delete", { "id" => garage,
                                        "replacement" => { "mode" => "attached_zone",
                                                           "attached_zone_id" => "atz_MissingRecord" } })

    assert_equal %w[refused target.not_found none], result.values_at("status", "code", "effect")
    assert_equal [garage], records.map { |record| record.fetch("id") }
    assert_equal garage, faces.first.dig("values", "attached_zone_id")
  end

  # A Face moved or exploded out of every Zone keeps its assignment. Delete cannot reach it
  # through a normal operation, so it refuses the whole delete and names the recovery routes.
  def test_delete_refuses_while_a_face_outside_every_zone_names_the_record
    garage = create_zone_record("Garage")
    assign(faces.first, garage)
    assign(faces.last, garage)
    orphan = Sketchup::Face.new(900)
    FACE_STORE.write(orphan, FACE_STORE.read(zone_face(0)).merge("id" => "fac_000000000999"))
    @model.entities << orphan
    before = [records, faces, FACE_STORE.read(orphan)]
    operation_count = @model.operations.length

    [{ "mode" => "boundary_condition", "boundary_condition" => "Adiabatic" },
     { "mode" => "attached_zone", "attached_zone_id" => create_zone_record("Attic", "attic") }]
      .each do |replacement|
        result = invoke("#{KIND}.delete", { "id" => garage, "replacement" => replacement })

        assert_equal %w[refused reference.in_use none], result.values_at("status", "code", "effect")
        assert_match(/Restore its Zone/, result.fetch("message"))
        assert_equal [{ "id" => "fac_000000000999", "path" => [900], "reason" => "outside_zone" }],
                     result.dig("detail", "faces")
      end
    assert_equal before, [records.reject { |record| record.dig("values", "name") == "Attic" }, faces,
                          FACE_STORE.read(orphan)]
    assert_equal operation_count + 1, @model.operations.length
  end

  # A native explode leaves the Zone's Faces outside every Zone. After the refusal, Restore Zone
  # brings them back into scope and the same delete then moves every one.
  def test_delete_refused_by_an_exploded_zone_succeeds_after_restore
    garage = create_zone_record("Garage")
    assign(faces.first, garage)
    zone_id = faces.first.dig("reference", "zone_id")
    @model.entities.to_a.first.explode
    replacement = { "mode" => "boundary_condition", "boundary_condition" => "Outdoors" }

    refused = invoke("#{KIND}.delete", { "id" => garage, "replacement" => replacement })
    restored = invoke("ph_composer.zones.restore", { "parent_path" => [], "zone_id" => zone_id })
    deleted = invoke("#{KIND}.delete", { "id" => garage, "replacement" => replacement })

    assert_equal %w[refused reference.in_use none], refused.values_at("status", "code", "effect")
    assert_equal "committed", restored.fetch("effect")
    assert_equal %w[completed committed], deleted.values_at("status", "effect")
    assert_equal "Outdoors", faces.first.dig("values", "boundary_condition")
    assert_empty records
  end

  # A Face inside a live Zone but in a child Group shared with a copy cannot be rewritten either;
  # the refusal says to make the Group unique.
  def test_a_face_in_a_shared_child_group_inside_the_zone_also_refuses_the_delete
    garage = create_zone_record("Garage")
    record = FACE_STORE.read(zone_face(0)) || {}
    shared = Sketchup::Entities.new([Sketchup::Face.new(801)])
    zone = @model.entities.to_a.first
    zone.entities << Sketchup::Group.new(810, shared) << Sketchup::Group.new(820, shared)
    FACE_STORE.write(shared.to_a.first, record.merge(
      "id" => "fac_000000000801", "schema_version" => 1, "face_type" => "Wall",
      "boundary_condition" => "AttachedZone", "attached_zone_id" => garage
    ))

    result = invoke("#{KIND}.delete", { "id" => garage,
                                        "replacement" => { "mode" => "boundary_condition",
                                                           "boundary_condition" => "Outdoors" } })

    assert_equal %w[refused reference.in_use none], result.values_at("status", "code", "effect")
    assert_equal %w[target.shared_definition], result.dig("detail", "faces").map { |face| face["reason"] }.uniq
    assert_match(/open its shared Group with Edit Group/, result.fetch("message"))
    assert_equal [garage], records.map { |row| row.fetch("id") }
  end

  def test_the_engine_refuses_deleting_an_attached_zone_a_face_still_names
    garage = create_zone_record("Garage")
    assign(faces.first, garage)
    engine = PhComposer::Records::Engine.new(@model, PhComposer::Registry.current.catalog)

    error = assert_raises(PhComposer::CodedError) do
      engine.propose_delete(KIND, garage, PhComposer::Records::ChangeSet.new)
    end

    assert_equal "reference.in_use", error.code
    assert_match(/#{PhComposer::Zones::Faces::REFERENCE_KIND} fac_/, error.message)
  end

  def test_duplicate_creates_a_fresh_record_without_reassigning_any_face
    garage = create_zone_record("Garage")
    assign(faces.first, garage)

    result = invoke("#{KIND}.duplicate", { "ids" => [garage] })

    copy = result.dig("value", "ids").fetch(garage)

    refute_equal garage, copy
    assert_equal garage, faces.first.dig("values", "attached_zone_id")
    assert_equal "Garage", records.find { |record| record.fetch("id") == copy }.dig("values", "name")
  end

  def test_an_edit_preserves_user_data_and_refuses_a_stale_expected_value
    garage = create_zone_record("Garage")
    metadata = { "reference" => { "kind" => KIND, "id" => garage }, "user_data" => { "firm.note" => "keep" },
                 "expected_metadata" => { "user_data" => {}, "extension_data" => {} } }
    invoke("ph_composer.records.update_metadata", { "updates" => [metadata] })
    edited = invoke("#{KIND}.save", { "id" => garage, "values" => { "notes" => "Detached" },
                                      "user_data" => { "firm.note" => "replaced" } })
    assert_equal %w[refused params.invalid], edited.values_at("status", "code"), "an edit does not take user_data"
    invoke("#{KIND}.save", { "id" => garage, "values" => { "notes" => "Detached" } })

    stale = invoke("#{KIND}.save", { "id" => garage, "values" => { "name" => "Carport" },
                                     "expected_values" => { "name" => "Garage " } })

    assert_equal "refused", stale.fetch("status")
    record = records.first

    assert_equal "Garage", record.dig("values", "name")
    assert_equal({ "firm.note" => "keep" }, record.fetch("user_data"))
  end

  private

  KIND_STORE = PhComposer::Zones::Faces::AttachedZone::RECORD_KIND.store
  FACE_STORE = PhComposer::Zones::Faces::FACE_STORE

  def invoke(name, params)
    @sequence += 1
    API.invoke(:context => @context, :name => name, :params => params,
               :request => { "sequence" => @sequence, "expected_revision" => @session.revision })
  end

  def records
    API.query(:context => @context, :name => "ph_composer.records.list", :params => { "kind" => KIND })
       .dig("value", "records")
  end

  def faces
    API.query(:context => @context, :name => "ph_composer.zones.faces.list").dig("value", "faces")
  end

  def create_zone_record(name, kind = "garage")
    invoke("#{KIND}.save", { "values" => { "name" => name, "kind" => kind } }).dig("value", "id")
  end

  def assign(face, attached_zone_id)
    invoke("ph_composer.zones.faces.classify", {
      "faces" => [face.fetch("reference")],
      "intent" => { "face_type" => { "mode" => "set", "value" => "Wall" },
                    "boundary_condition" => { "mode" => "set", "value" => "AttachedZone" },
                    "attached_zone_id" => { "mode" => "set", "value" => attached_zone_id } },
      "expected_values" => {}
    })
    faces.find { |row| row.dig("reference", "entity_path") == face.dig("reference", "entity_path") }
  end

  def zone_face(index)
    @model.entities.to_a.first.entities.to_a.fetch(index)
  end

  def make_box_zone(base, face_count)
    entities = face_count.times.map do |index|
      Sketchup::Face.new(base + index + 1, {},
                         :points => [Geom::Point3d.new(0, 0, index), Geom::Point3d.new(2, 0, index),
                                     Geom::Point3d.new(2, 2, index)])
    end
    @model.entities << Sketchup::Group.new(base, Sketchup::Entities.new(entities))
    invoke("ph_composer.zones.make", { "parent_path" => [], "entity_ids" => [base] })
  end
end
