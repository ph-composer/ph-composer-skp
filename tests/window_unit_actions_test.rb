# frozen_string_literal: true

require_relative "test_helper"
require_relative "support/window_record_fixtures"
require_relative "support/assembly_assignment_fixtures"

class WindowUnitActionsTest < PhComposerTestCase
  include WindowRecordFixtures
  include AssemblyAssignmentFixtures

  U = PhComposer::Windows::Units
  PREFIX = "ph_composer.windows"

  def setup
    super
    assignment_setup
    PhComposer::Registry.install([W]) unless PhComposer::Registry.installed?(W::FEATURE_ID)
    points = [[0, 0, 0], [1000, 0, 0], [1000, 1000, 0], [0, 1000, 0]].map { |point| Geom::Point3d.new(*point) }
    face = Sketchup::Face.new(1001, {}, :points => points)
    @group = Sketchup::Group.new(1000, Sketchup::Entities.new([face]))
    @model.entities << @group
    result = assignment_invoke("ph_composer.zones.make", "parent_path" => [], "entity_ids" => [1000])
    assert_equal "completed", result.fetch("status"), result.inspect
    assignment_classify(assignment_faces, "face_type" => { "mode" => "set", "value" => "Wall" },
                                          "boundary_condition" => { "mode" => "set", "value" => "Outdoors" })
    @face_reference = assignment_faces.first.fetch("reference")
    result = assignment_invoke("#{PREFIX}.types.create", "values" => { "name" => "Synthetic placement" })
    assert_equal "completed", result.fetch("status"), result.inspect
    @type_id = result.fetch("value").fetch("id")
  end

  def params(x = 2.0, anchor = "sill_center")
    { "host" => @face_reference, "type_id" => @type_id, "anchor" => anchor,
      "offsets" => { "x_m" => x, "y_m" => 3.0 }, "user_data" => { "note" => ["retain"] } }
  end

  def place(x = 2.0, anchor = "sill_center")
    result = assignment_invoke("#{PREFIX}.units.place", params(x, anchor))
    assert_equal "completed", result.fetch("status"), result.inspect
    result
  end

  def units
    assignment_query("#{PREFIX}.units.list").fetch("units")
  end

  def codes(row)
    row.fetch("findings").map { |finding| finding.fetch("code") }
  end

  def type
    PhComposer::Records::Engine.new(@model, PhComposer::Registry.current.catalog).find(W::TYPE_KIND, @type_id)
  end

  def test_host_extent_gives_the_face_size_and_each_unit_in_the_offsets_frame
    extent = assignment_query("#{PREFIX}.units.host_extent", "host" => @face_reference)
    assert_in_delta 25.4, extent.fetch("width_m"), 1e-9
    assert_in_delta 25.4, extent.fetch("height_m"), 1e-9
    corners = extent.fetch("outline_m").transpose.map(&:minmax).transpose
    assert_equal [[0.0, 0.0], [25.4, 25.4]], corners.map { |pair| pair.map { |value| value.round(9) } }
    assert_empty extent.fetch("units")
    place(2.0)
    unit = assignment_query("#{PREFIX}.units.host_extent", "host" => @face_reference).fetch("units").first
    assert_equal units.first.fetch("reference"), unit.fetch("reference")
    assert_in_delta 3.0, unit.fetch("y_m"), 1e-6, "a sill anchor sits at the outline's bottom"
    assert_in_delta 2.0, unit.fetch("x_m") + (unit.fetch("width_m") / 2), 1e-6, "and a center anchor at its middle"
    assert_operator unit.fetch("width_m"), :>, 0
  end

  def test_host_extent_pages_its_units_and_gives_the_extent_on_every_page
    [2.0, 5.0, 8.0].each { |x| place(x) }
    first = assignment_query("#{PREFIX}.units.host_extent", "host" => @face_reference, "limit" => 2)
    assert_equal [2, 3], [first.fetch("units").length, first.fetch("total")]
    rest = assignment_query("#{PREFIX}.units.host_extent", "host" => @face_reference,
                                                           "cursor" => first.fetch("next_cursor"))
    assert_equal [1, nil], [rest.fetch("units").length, rest.fetch("next_cursor")]
    assert_in_delta 25.4, rest.fetch("width_m"), 1e-9, "the Face's extent comes on every page"
  end

  def test_outlines_give_each_placed_unit_in_world_metres_with_its_host_and_page
    [2.0, 5.0].each { |x| place(x) }
    first = assignment_query("#{PREFIX}.units.outlines", "limit" => 1)
    assert_equal [1, 2], [first.fetch("units").length, first.fetch("total")]
    rest = assignment_query("#{PREFIX}.units.outlines", "cursor" => first.fetch("next_cursor"))
    rows = first.fetch("units") + rest.fetch("units")
    assert_nil rest.fetch("next_cursor")
    assert_equal units.map { |row| row.fetch("reference") }.sort_by { |ref| ref.fetch("entity_path") },
                 rows.map { |row| row.fetch("reference") }
    assert(rows.all? { |row| row.fetch("host") == @face_reference })
    extent = assignment_query("#{PREFIX}.units.host_extent", "host" => @face_reference).fetch("units")
    rows.zip(extent.sort_by { |row| row.dig("reference", "entity_path") }).each do |row, box|
      outline = row.fetch("outline_m")
      assert(outline.all? { |point| point.length == 3 && point[2].abs < 1e-9 }, "on the Face's plane, in world")
      xs = outline.map(&:first)
      assert_in_delta box.fetch("width_m"), xs.max - xs.min, 1e-4
      assert_in_delta box.fetch("x_m"), xs.min, 1e-4
    end
  end

  def test_preview_changes_nothing_and_place_is_one_native_undo_with_public_readback
    before = U::MutationScope.new.capture(@model)
    preview = API.preview(:context => @context, :name => "#{PREFIX}.units.place", :params => params)
    assert_equal "ok", preview.fetch("code"), preview.inspect
    assert_equal before, U::MutationScope.new.capture(@model)
    operation_count = @model.operations.length
    result = place
    assert_equal operation_count + 1, @model.operations.length
    row = units.first
    assert_equal result.dig("value", "unit_id"), row.fetch("id")
    assert_empty row.fetch("findings")
    assert_equal @face_reference, row.fetch("host")
    assert_equal({ "note" => ["retain"] }, row.fetch("user_data"))
    @model.undo
    assert_empty units
    assert_equal before, U::MutationScope.new.capture(@model)
    @model.redo
    assert_equal row, units.first
  end

  def test_second_placement_shares_definition_and_positive_area_overlap_refuses_without_writes
    place
    before = U::MutationScope.new.capture(@model)
    refused = assignment_invoke("#{PREFIX}.units.place", params)
    assert_equal "window.overlap", refused.fetch("code"), refused.inspect
    assert_equal before, U::MutationScope.new.capture(@model)
    place(5.0)
    assert_equal 2, units.length
    assert_equal 1, U::Occurrences.all(@model).map { |item| item.entity.definition.persistent_id }.uniq.length
    assert_equal 1, @model.definitions.to_a.length
  end

  def test_used_type_resize_keeps_each_world_anchor_and_one_undo_restores_every_unit
    %w[sill_left center head_right].each_with_index { |anchor, index| place(3.0 + index * 5.0, anchor) }
    before_type = type
    before_plan = U::DefinitionPlan.build(before_type)
    points = U::Occurrences.all(@model).to_h do |item|
      [item.path, U::WorldGeometry.anchor(before_plan, item.record.fetch("anchor"), item.transform.to_a)]
    end
    scope = U::MutationScope.new(:definition_ids => U::Occurrences.all(@model).map { |item|
                                                      item.entity.definition.persistent_id
                                                    })
    before = scope.capture(@model)
    result = assignment_invoke("#{PREFIX}.types.update",
                               "id" => @type_id,
                               "values" => { "columns_m" => [1.2] },
                               "expected_values" => { "columns_m" => before_type.fetch("columns_m") })
    assert_equal "completed", result.fetch("status"), result.inspect
    assert_equal 3, result.dig("value", "unit_count")
    after_plan = U::DefinitionPlan.build(type)
    U::Occurrences.all(@model).each do |item|
      actual = U::WorldGeometry.anchor(after_plan, item.record.fetch("anchor"), item.transform.to_a)
      points.fetch(item.path).zip(actual).each { |expected, value| assert_in_delta expected, value, 1e-12 }
    end
    after = scope.capture(@model)
    @model.undo
    assert_equal before_type, type
    assert_equal before, scope.capture(@model)
    @model.redo
    assert_equal after, scope.capture(@model)
  end

  def test_copied_identity_read_is_pure_and_next_name_change_repairs_inside_the_same_undo
    place
    original = U::Occurrences.all(@model).first
    copy = @group.entities.add_instance(original.entity.definition,
                                        Geom::Transformation.translation([200, 0, 0]) * original.entity.transformation)
    copy.glued_to = original.entity.glued_to
    U.write(copy, original.record)
    assert(units.all? { |row| codes(row).include?("window.copy_id_pending") })
    assert_equal 1, U::Occurrences.all(@model).map { |item| item.record.fetch("id") }.uniq.length
    scope = U::MutationScope.new(:definition_ids => [original.entity.definition.persistent_id])
    before = scope.capture(@model)
    result = assignment_invoke("#{PREFIX}.types.update",
                               "id" => @type_id,
                               "values" => { "name" => "Renamed synthetic" },
                               "expected_values" => { "name" => type.fetch("name") })
    assert_equal "completed", result.fetch("status"), result.inspect
    assert_equal 2, U::Occurrences.all(@model).map { |item| item.record.fetch("id") }.uniq.length
    assert units.all? { |row| row.fetch("user_data") == { "note" => ["retain"] } }
    @model.undo
    assert_equal before, scope.capture(@model)
  end

  # One condition, one code: the Unit read and the export preflight name a copied identity alike.
  def test_unit_read_and_export_preflight_report_the_same_code
    place
    original = U::Occurrences.all(@model).first
    copy = @group.entities.add_instance(original.entity.definition,
                                        Geom::Transformation.translation([200, 0, 0]) * original.entity.transformation)
    copy.glued_to = original.entity.glued_to
    U.write(copy, original.record)
    listed = units.flat_map { |row| codes(row) }.uniq
    preflight = assignment_query("#{PREFIX}.export_preflight").fetch("findings").map { |row| row.fetch("code") }.uniq
    assert_equal ["window.copy_id_pending"], listed
    assert_includes preflight, "window.copy_id_pending"
  end

  # A Ground host is one condition with one code, in the Unit read and the export preflight alike.
  def test_unit_read_and_export_preflight_report_a_ground_host_alike
    place
    assignment_classify(assignment_faces, "boundary_condition" => { "mode" => "set", "value" => "Ground" })
    listed = units.flat_map { |row| codes(row) }.uniq
    preflight = assignment_query("#{PREFIX}.export_preflight").fetch("findings").map { |row| row.fetch("code") }.uniq
    assert_equal ["window.host_boundary_unsupported"], listed
    assert_includes preflight, "window.host_boundary_unsupported"
  end

  # The named repair: a preview lists the copy's old and new id, the invoke gives only the copy a new
  # identity in one Undo step, and a Window whose identity nobody shares is refused.
  def test_repair_copied_identities_renames_only_the_copy_in_one_undo
    place
    original = U::Occurrences.all(@model).first
    copy = @group.entities.add_instance(original.entity.definition,
                                        Geom::Transformation.translation([200, 0, 0]) * original.entity.transformation)
    copy.glued_to = original.entity.glued_to
    U.write(copy, original.record)
    copied = U::Occurrences.all(@model).find { |item| item.entity.equal?(copy) }
    name = "#{PREFIX}.units.repair_copied_identities"
    preview = API.preview(:context => @context, :name => name, :params => { "units" => [copied.reference] })
    assert_equal "completed", preview.fetch("status"), preview.inspect
    repairs = preview.dig("value", "repairs")
    assert_equal [[copied.path, original.record.fetch("id")]],
                 repairs.map { |row| row.values_at("entity_path", "old_unit_id") }
    assert_equal 1, U::Occurrences.all(@model).map { |item| item.record.fetch("id") }.uniq.length
    before = U::MutationScope.new.capture(@model)
    result = assignment_invoke(name, "units" => [original.reference])
    assert_equal "committed", result.fetch("effect"), result.inspect
    after = U::Occurrences.all(@model).to_h { |item| [item.path, item.record] }
    assert_equal original.record, after.fetch(original.path)
    new_id = result.dig("value", "repairs", 0, "new_unit_id")
    assert_equal original.record.merge("id" => new_id), after.fetch(copied.path)
    assert(units.none? { |row| codes(row).include?("window.copy_id_pending") })
    @model.undo
    assert_equal before, U::MutationScope.new.capture(@model)
    @model.redo
    refused = assignment_invoke(name, "units" => [original.reference])
    assert_equal "params.invalid", refused.fetch("code")
  end

  def test_read_works_under_locked_parent_but_placement_refuses
    place
    @group.locked = true
    assert_empty units.first.fetch("findings")
    refused = assignment_invoke("#{PREFIX}.units.place", params(7.0))
    assert_equal "target.locked", refused.fetch("code")
    assert_equal 1, units.length
  end

  def test_paged_reads_bind_to_revision_and_preserve_occurrence_identity
    place
    place(7.0)
    first = assignment_query("#{PREFIX}.units.list", "limit" => 1)
    assert_equal 2, first.fetch("total")
    cursor = first.fetch("next_cursor")
    refute_nil cursor
    second = assignment_query("#{PREFIX}.units.list", "limit" => 1, "cursor" => cursor)
    refute_equal first.fetch("units").first.fetch("reference"), second.fetch("units").first.fetch("reference")
    assert_nil second.fetch("next_cursor")
    place(12.0)
    expired = API.query(:context => @context, :name => "#{PREFIX}.units.list",
                        :params => { "limit" => 1, "cursor" => cursor })
    assert_equal "query.cursor_expired", expired.fetch("code")
  end

  def test_resizing_past_host_refuses_preview_without_changing_type_or_native_geometry
    place(1.0, "sill_right")
    before_type = type
    scope = U::MutationScope.new(:definition_ids => [U::Occurrences.all(@model).first.entity.definition.persistent_id])
    before = scope.capture(@model)
    result = API.preview(:context => @context, :name => "#{PREFIX}.types.update",
                         :params => { "id" => @type_id, "values" => { "columns_m" => [2.0] },
                                      "expected_values" => { "columns_m" => before_type.fetch("columns_m") } })
    assert_equal "window.overhang", result.fetch("code"), result.inspect
    assert_equal 1, result.dig("detail", "unit_count")
    blocked = result.dig("detail", "blocked_units").map { |row| row.fetch("reference") }
    assert_equal [units.first.fetch("reference")], blocked
    assert_equal before_type, type
    assert_equal before, scope.capture(@model)
  end

  def test_resize_refuses_overlap_with_unglued_canonical_neighbor
    place(2.0, "sill_left")
    place(5.0, "sill_left")
    U::Occurrences.all(@model).last.entity.glued_to = nil
    before = U::MutationScope.new.capture(@model)
    result = assignment_invoke("#{PREFIX}.types.update",
                               "id" => @type_id,
                               "values" => { "columns_m" => [4.0] }, "expected_values" => { "columns_m" => [1.0] })
    assert_equal "window.overlap", result.fetch("code"), result.inspect
    assert_equal before, U::MutationScope.new.capture(@model)
  end

  def test_preview_names_units_whose_edited_primary_geometry_will_be_replaced
    place
    item = U::Occurrences.all(@model).first
    item.entity.definition.entities.grep(Sketchup::Face).first.reverse!
    before = U::MutationScope.new(:definition_ids => [item.entity.definition.persistent_id]).capture(@model)
    result = API.preview(:context => @context, :name => "#{PREFIX}.types.update",
                         :params => { "id" => @type_id, "values" => { "columns_m" => [1.2] }, "expected_values" => {} })
    assert_equal "ok", result.fetch("code"), result.inspect
    warning = result.fetch("findings").find { |finding| finding.fetch("code") == "window.edited_geometry_replaced" }
    refute_nil warning
    assert_equal [item.reference], warning.fetch("references")
    assert_equal before, U::MutationScope.new(:definition_ids => [item.entity.definition.persistent_id]).capture(@model)
  end

  def test_read_keeps_each_occurrence_under_a_copied_shared_zone
    place
    copy = Sketchup::Group.new(3000, @group.entities)
    PhComposer::Zones::ZONE_STORE.write(copy, PhComposer::Zones::ZONE_STORE.read(@group))
    @model.entities << copy
    treat_duplicates_as_existing(@model)
    rows = units
    assert_equal 2, rows.length
    assert_equal [[1000], [3000]], rows.map { |row| row.fetch("reference").fetch("entity_path")[0...-1] }.sort
    assert(rows.all? { |row| codes(row).include?("window.copy_id_pending") })
    assert(rows.all? { |row| codes(row).include?("window.host_zone_unresolved") })
  end

  def test_public_rehost_preserves_geometry_and_one_undo_restores_absent_glue
    place
    item = U::Occurrences.all(@model).first
    item.entity.glued_to = nil
    before = U::MutationScope.new.capture(@model)
    result = assignment_invoke("#{PREFIX}.units.rehost", "unit" => item.reference, "host" => @face_reference)
    assert_equal "completed", result.fetch("status"), result.inspect
    assert_empty units.first.fetch("findings")
    @model.undo
    assert_equal before, U::MutationScope.new.capture(@model)
    @model.redo
    assert_empty units.first.fetch("findings")
  end

  def test_remove_copied_occurrence_is_path_scoped_and_undo_restores_pending_identity
    place
    original = U::Occurrences.all(@model).first
    copy = @group.entities.add_instance(original.entity.definition,
                                        Geom::Transformation.translation([200, 0, 0]) * original.entity.transformation)
    copy.glued_to = original.entity.glued_to
    U.write(copy, original.record)
    before = U::MutationScope.new.capture(@model)
    reference = U::Occurrences.all(@model).last.reference
    result = assignment_invoke("#{PREFIX}.units.remove", "units" => [reference])
    assert_equal "completed", result.fetch("status"), result.inspect
    assert_equal [original.path], U::Occurrences.all(@model).map(&:path)
    assert_equal 1, @model.definitions.to_a.length
    @model.undo
    assert_equal before, U::MutationScope.new.capture(@model)
    @model.redo
    assert_equal [original.path], U::Occurrences.all(@model).map(&:path)
  end

  def test_remove_refuses_live_typed_incoming_reference_without_writes
    place
    item = U::Occurrences.all(@model).first
    kind = PhComposer::Records::RecordKind.new(
      :id => "probe.unit_link.record", :label => "Synthetic Unit link", :schema_version => 1, :id_prefix => "wpr",
      :fields => [PhComposer::Records::AuthoringFields.field("unit_id", { "type" => "string" }, :required => true)],
      :references => [PhComposer::Records::Reference.new(:key => "unit_id", :target_kind => U::REFERENCE_KIND,
                                                         :cardinality => "one")]
    )
    contribution = Module.new do
      define_singleton_method(:install) do |registry|
        registry.feature("probe.unit_link", :contract_version => 1,
                                            :requires => ["ph_composer.windows"]).record_kind(kind)
      end
    end
    PhComposer::Registry.install([contribution])
    kind.store.write(@model, "id" => "wpr_AAAAAAAAAAAA", "schema_version" => 1,
                             "unit_id" => item.record.fetch("id"))
    before = U::MutationScope.new.capture(@model)
    result = assignment_invoke("#{PREFIX}.units.remove", "units" => [item.reference])
    assert_equal "reference.in_use", result.fetch("code"), result.inspect
    assert_equal before, U::MutationScope.new.capture(@model)
    assert_equal item.reference, units.first.fetch("reference")
  end

  def test_public_batch_swap_keeps_metadata_and_anchors_and_is_one_undo
    place(2.0, "sill_left")
    place(7.0, "head_right")
    before_plan = U::DefinitionPlan.build(type)
    rows = U::Occurrences.all(@model)
    points = rows.to_h { |item|
      [item.path,
       U::WorldGeometry.anchor(before_plan, item.record.fetch("anchor"), item.transform.to_a)]
    }
    created = assignment_invoke("#{PREFIX}.types.create", "values" => { "name" => "Swap target" })
    target = created.dig("value", "id")
    scope = U::MutationScope.new(:definition_ids => rows.map { |item| item.entity.definition.persistent_id })
    before = scope.capture(@model)
    result = assignment_invoke("#{PREFIX}.units.swap_type", "units" => rows.map(&:reference), "type_id" => target)
    assert_equal "completed", result.fetch("status"), result.inspect
    assert_equal 2, result.dig("value", "unit_ids").length
    assert_equal [target], units.map { |row| row.dig("values", "window_type_id") }.uniq
    U::Occurrences.all(@model).each do |item|
      assert_equal points.fetch(item.path), U::WorldGeometry.anchor(before_plan,
                                                                    item.record.fetch("anchor"), item.transform.to_a)
      assert_equal({ "note" => ["retain"] }, item.record.fetch("user_data"))
    end
    after = scope.capture(@model)
    @model.undo
    assert_equal before, scope.capture(@model)
    @model.redo
    assert_equal after, scope.capture(@model)
  end

  def test_public_reset_reports_shared_definition_and_restores_geometry_in_one_undo
    place(2.0)
    place(7.0)
    rows = U::Occurrences.all(@model)
    rows.first.entity.definition.entities.grep(Sketchup::Face).first.reverse!
    scope = U::MutationScope.new(:definition_ids => [rows.first.entity.definition.persistent_id])
    before = scope.capture(@model)
    preview = API.preview(:context => @context, :name => "#{PREFIX}.units.reset_to_type",
                          :params => { "units" => [rows.first.reference] })
    assert_equal "ok", preview.fetch("code"), preview.inspect
    assert_equal 2, preview.fetch("findings").first.fetch("unit_count")
    assert_equal before, scope.capture(@model)
    result = assignment_invoke("#{PREFIX}.units.reset_to_type", "units" => [rows.first.reference])
    assert_equal "completed", result.fetch("status"), result.inspect
    assert units.all? { |row| row.fetch("findings").empty? }
    after = scope.capture(@model)
    @model.undo
    assert_equal before, scope.capture(@model)
    @model.redo
    assert_equal after, scope.capture(@model)
  end

  def test_reset_does_not_require_writable_host_for_unselected_detached_unit
    place(2.0)
    selected = U::Occurrences.all(@model).first
    face = Sketchup::Face.new(2001, {},
                              :points => [[0, 0, 0], [1000, 0, 0],
                                          [1000, 1000, 0], [0, 1000, 0]].map { |point| Geom::Point3d.new(*point) })
    other = Sketchup::Group.new(2000, Sketchup::Entities.new([face]),
                                :transformation => Geom::Transformation.translation([0, 0, 100]))
    @model.entities << other
    assignment_invoke("ph_composer.zones.make", "parent_path" => [], "entity_ids" => [2000])
    detached = U::DefinitionWriter.create(:model => @model, :type => type, :plan => U::DefinitionPlan.build(type))
    entity = other.entities.add_instance(detached, selected.entity.transformation)
    entity.glued_to = face
    U.write(entity, selected.record.merge("id" => "wun_AAAAAAAAAAAA"))
    other.locked = true
    selected.entity.definition.entities.grep(Sketchup::Face).first.reverse!
    before = U::DefinitionGeometry.capture(detached)
    result = assignment_invoke("#{PREFIX}.units.reset_to_type", "units" => [selected.reference])
    assert_equal "completed", result.fetch("status"), result.inspect
    assert_equal before, U::DefinitionGeometry.capture(detached)
    assert_equal detached, entity.definition
    assert other.locked?
  end

  def test_removal_and_replacement_refuse_nested_authored_units_without_writes
    place
    parent = U::Occurrences.all(@model).first
    definition = U::DefinitionWriter.create(:model => @model, :type => type, :plan => U::DefinitionPlan.build(type))
    child = parent.entity.definition.entities.add_instance(definition, Geom::Transformation.new)
    U.write(child, parent.record.merge("id" => "wun_AAAAAAAAAAAA"))
    replacement = assignment_invoke("#{PREFIX}.types.create", "values" => { "name" => "Nested guard target" })
    scope = U::MutationScope.new(:definition_ids => @model.definitions.map(&:persistent_id))
    before = scope.capture(@model)
    [
      ["units.remove", { "units" => [parent.reference] }],
      ["units.swap_type", { "units" => [parent.reference], "type_id" => replacement.dig("value", "id") }],
      ["types.delete", { "id" => @type_id, "replacement_id" => nil }],
      ["types.update", { "id" => @type_id, "values" => { "columns_m" => [1.1] }, "expected_values" => {} }]
    ].each do |name, params|
      result = assignment_invoke("#{PREFIX}.#{name}", params)
      refute_equal "committed", result.fetch("effect"), result.inspect
      assert_equal before, scope.capture(@model)
      assert_equal 2, U::Occurrences.all(@model).length
    end
  end

  def test_public_new_flipped_type_preserves_panes_and_is_one_undo
    place(3.0, "head_left")
    item = U::Occurrences.all(@model).first
    item.entity.transformation *= Geom::Transformation.scaling(-1, 1, 1)
    item = U::Occurrences.all(@model).first
    pane = U::WorldGeometry.map(U::DefinitionPlan.build(type), item.transform.to_a).panes.first.polygon_m
    scope = U::MutationScope.new(:definition_ids => [item.entity.definition.persistent_id])
    before = scope.capture(@model)
    result = assignment_invoke("#{PREFIX}.units.new_flipped_type", "unit" => item.reference)
    assert_equal "completed", result.fetch("status"), result.inspect
    refute_equal @type_id, result.dig("value", "type_id")
    changed = U::Occurrences.all(@model).first
    target = PhComposer::Records::Engine.new(@model, PhComposer::Registry.current.catalog).find(
      W::TYPE_KIND, changed.record.fetch("window_type_id")
    )
    actual = U::WorldGeometry.map(U::DefinitionPlan.build(target), changed.transform.to_a).panes.first.polygon_m
    pane.each do |expected|
      assert actual.any? { |point| expected.zip(point).all? { |a, b| (a - b).abs < 1e-12 } },
             "A physical pane vertex moved."
    end
    assert_equal "head_right", changed.record.fetch("anchor")
    assert_equal({ "note" => ["retain"] }, changed.record.fetch("user_data"))
    assert_empty units.first.fetch("findings")
    after = scope.capture(@model)
    @model.undo
    assert_equal before, scope.capture(@model)
    @model.redo
    assert_equal after, scope.capture(@model)
  end

  def test_public_restore_replaces_exact_loose_panes_with_new_default_anchor_unit
    place(3.0, "head_left")
    original = U::Occurrences.all(@model).first
    pane = U::WorldGeometry.map(U::DefinitionPlan.build(type), original.transform.to_a).panes.first
    points = pane.polygon_m.map { |point| Geom::Point3d.new(*point.map { |value| value / 0.0254 }) }
    edges = points.each_with_index.map do |point, index|
      edge = Sketchup::Edge.new(Sketchup::Entities.allocate_persistent_id, point, points[(index + 1) % 4])
      @group.entities << edge
      edge
    end
    face = Sketchup::Face.new(Sketchup::Entities.allocate_persistent_id, {}, :points => points, :edges => edges)
    @group.entities << face
    face.material = @model.materials[U::DefinitionWriter::GLASS_NAME]
    face.back_material = face.material
    U::PANE_STORE.write(face, "window_type_id" => @type_id, "element_id" => pane.element_id)
    @group.entities.erase_entities(original.entity)
    scope = U::RestorePaneScope.new([@group.persistent_id], [face.persistent_id], type)
    before = scope.capture(@model)
    result = assignment_invoke("#{PREFIX}.units.restore",
                               "host" => @face_reference,
                               "type_id" => @type_id, "pane_paths" => [[@group.persistent_id, face.persistent_id]])
    assert_equal "completed", result.fetch("status"), result.inspect
    refute_equal original.record.fetch("id"), result.dig("value", "unit_id")
    assert_equal "sill_center", units.first.dig("values", "anchor")
    assert_equal({}, units.first.fetch("user_data"))
    refute_includes @group.entities.to_a, face
    @model.undo
    assert_equal before, scope.capture(@model)
    assert_empty units
    @model.redo
    assert_equal result.dig("value", "unit_id"), units.first.fetch("id")
  end

  def test_reset_can_discard_selected_geometry_beyond_the_generated_footprint
    place
    item = U::Occurrences.all(@model).first
    item.entity.definition.entities.grep(Sketchup::Face).first.transform!(Geom::Transformation.scaling(2, 1, 1))
    scope = U::MutationScope.new(:definition_ids => [item.entity.definition.persistent_id])
    before = scope.capture(@model)
    result = assignment_invoke("#{PREFIX}.units.reset_to_type", "units" => [item.reference])
    assert_equal "completed", result.fetch("status"), result.inspect
    assert_empty units.first.fetch("findings")
    @model.undo
    assert_equal before, scope.capture(@model)
  end

  def test_reset_refuses_uncertain_untouched_outsider_geometry
    place(2.0)
    place(7.0)
    selected, outsider = U::Occurrences.all(@model)
    detached = U::DefinitionWriter.create(:model => @model, :type => type, :plan => U::DefinitionPlan.build(type))
    outsider.entity.definition = detached
    detached.entities.grep(Sketchup::Face).first.transform!(Geom::Transformation.scaling(2, 1, 1))
    selected.entity.definition.entities.grep(Sketchup::Face).first.reverse!
    scope = U::MutationScope.new(:definition_ids => @model.definitions.map(&:persistent_id))
    before = scope.capture(@model)
    result = assignment_invoke("#{PREFIX}.units.reset_to_type", "units" => [selected.reference])
    assert_equal "window.type_geometry_unknown", result.fetch("code"), result.inspect
    assert_equal before, scope.capture(@model)
  end
end
