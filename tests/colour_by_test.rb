# frozen_string_literal: true

require_relative "test_helper"
require_relative "support/framing_camera"

# The shared Colour-by service. The registry seam, the mode projections the two shipping features
# register, what the overlay batches and what invalidates the cache.
class ColourByTest < PhComposerTestCase
  ColourBy = PhComposer::ColourBy
  Registry = PhComposer::Registry
  Palette = PhComposer::ColourBy::Palette

  def setup
    super
    @model = Sketchup.active_model
    @session = PhComposer::Sessions.for(@model)
  end

  # ------------------------------------------------------------------ the seam

  def test_an_outside_feature_registers_a_mode_without_touching_the_shared_service
    install_synthetic_mode

    service = activate("outside.probe.by_side")

    assert_equal %w[Inside Outside], service.rows.map(&:label), "rows come back in legend order"
    assert_equal [[40, 50, 60], [10, 20, 30]], service.rows.map(&:colour)
    assert_equal "side", Registry.current.colour_modes.fetch("outside.probe.by_side").entity_kind
  end

  def test_spread_gives_every_value_its_own_ramp_colour_up_to_the_ramp_length
    palette = PhComposer::ColourBy::Palette
    ids = (1..palette::RAMP.length).map { |n| format("spc_%012d", n) }
    assert_equal ids.length, palette.spread(ids).values.uniq.length
    assert_equal palette::RAMP.length, palette.spread(ids + ["spc_extra"]).values.uniq.length,
                 "past the ramp's length colours repeat"
  end

  def test_spread_entries_colours_the_uncoloured_and_keeps_an_entry_s_own
    palette = PhComposer::ColourBy::Palette
    entries = %w[spc_000000000001 spc_000000000003 spc_000000000005].map do |value|
      PhComposer::ColourBy::Entry.new(:value => value)
    end
    entries.last.colour = [1, 2, 3]
    entries << PhComposer::ColourBy::Entry.new(:value => nil)
    palette.spread_entries(entries)
    assert_equal palette.spread(%w[spc_000000000001 spc_000000000003]).values, entries.first(2).map(&:colour)
    assert_equal [1, 2, 3], entries[2].colour, "a managed option's own colour stays"
    assert_nil entries.last.colour, "an unclassified entry is painted as unclassified"
    managed = PhComposer::ColourBy::Entry.new(:value => "lvl_managed", :colour => palette::RAMP[7])
    legacy = PhComposer::ColourBy::Entry.new(:value => "g") # alone, "g" takes slot 7
    palette.spread_entries([managed, legacy])
    refute_equal palette::RAMP[7], legacy.colour, "a managed option's slot is not given to another value"
  end

  # Ids and names whose characters are the same in another order share a byte sum, so the ramp alone gave
  # them one colour.
  def test_every_zone_mode_gives_each_value_its_own_colour
    zone_group(70, ["Wall"], :level => "L12")
    zone_group(700, ["Wall"], :level => "L21")
    zone_group(7000, ["Wall"], :level => "L12")
    assert_equal 3, activate("ph_composer.zones.by_zone").rows.map(&:colour).uniq.length
    assert_equal 2, activate("ph_composer.zones.by_level").rows.map(&:colour).uniq.length
  end

  def test_spread_moves_the_later_of_two_clashing_values_to_the_next_free_slot
    palette = PhComposer::ColourBy::Palette
    # Both digests pick slot 8 of the ramp.
    colours = palette.spread(%w[spc_000000000003 spc_000000000001])
    assert_equal palette::RAMP[8], colours.fetch("spc_000000000001")
    assert_equal palette::RAMP[9], colours.fetch("spc_000000000003")
  end

  # The write channel for viewport state: a client turns a mode on and off through the view seam and
  # reads the legend back from the same answer. Nothing it does reaches the Model.
  def test_a_client_turns_a_mode_on_and_off_without_writing_to_the_model
    install_synthetic_mode
    context = PhComposer::API.connect(:session_id => @session.id)
    revision = @session.revision

    on = PhComposer::API.view(:context => context, :name => "ph_composer.colour_by.activate",
                              :params => { "mode" => "outside.probe.by_side" })

    assert_equal "outside.probe.by_side", on.dig("value", "mode")
    assert_equal %w[Inside Outside], on.dig("value", "rows").map { |row| row.fetch("label") }
    assert_equal revision, @session.revision
    refute @model.modified?

    off = PhComposer::API.view(:context => context, :name => "ph_composer.colour_by.activate",
                               :params => { "mode" => nil })

    assert_nil off.dig("value", "mode")
    assert_nil ColourBy.for(@session).mode_name
  end

  def test_a_mode_a_client_names_that_is_not_registered_is_refused_by_name
    context = PhComposer::API.connect(:session_id => @session.id)

    outcome = PhComposer::API.view(:context => context, :name => "ph_composer.colour_by.activate",
                                   :params => { "mode" => "outside.probe.missing" })

    assert_equal %w[refused validation.failed], outcome.values_at("status", "code")
    assert_includes outcome.fetch("message"), "outside.probe.missing"
  end

  # ------------------------------------------------------------------ the panel legend

  def test_a_legend_row_selects_and_zooms_to_exactly_what_it_counts
    zone_group(1_700, %w[Wall Floor Wall])
    activate("ph_composer.zones.faces.by_face_type")
    context = PhComposer::API.connect(:session_id => @session.id)

    outcome = PhComposer::API.view(:context => context, :name => "ph_composer.colour_by.select_row",
                                   :params => { "row" => { "value" => "Wall", "state" => "classified" } })

    assert_equal 2, outcome.dig("value", "selected")
    assert_equal 2, @model.selection.to_a.length
    refute @model.modified?
  end

  # The row is framed where its Faces are in the world: inside a Zone Group placed away from the origin,
  # not by the Group's own coordinates, which `View#zoom` would use.
  def test_a_legend_row_is_framed_by_its_faces_world_bounds
    group = zone_group(1_705, %w[Wall Wall])
    group.transformation = Geom::Transformation.translation([100, 0, 0])
    activate("ph_composer.zones.faces.by_face_type")
    view = FramingCamera.attach(@model.active_view)
    context = PhComposer::API.connect(:session_id => @session.id)

    PhComposer::API.view(:context => context, :name => "ph_composer.colour_by.select_row",
                         :params => { "row" => { "value" => "Wall", "state" => "classified" } })

    assert_in_delta 101.0, view.camera.target.x, 1e-6, "the centre of the Faces at x 100 to 102"
    assert_operator view.camera.eye.y, :<, view.camera.target.y, "looking along the camera's direction"
    assert_empty view.zoomed
  end

  def test_a_legend_row_that_is_no_longer_drawn_refuses_by_name
    zone_group(1_710, ["Wall"])
    activate("ph_composer.zones.faces.by_face_type")
    context = PhComposer::API.connect(:session_id => @session.id)

    outcome = PhComposer::API.view(:context => context, :name => "ph_composer.colour_by.select_row",
                                   :params => { "row" => { "value" => "Floor", "state" => "classified" } })

    assert_equal %w[refused validation.failed], outcome.values_at("status", "code")
    assert_empty @model.selection.to_a
  end

  # Show only this keeps every row in the legend, with its own colour, and mutes what the viewport
  # draws for the others: the legend still tells the truth about the Model.
  def test_showing_one_row_on_its_own_mutes_the_rest_and_is_released_by_asking_for_none
    zone_group(1_720, %w[Wall Floor])
    service = activate("ph_composer.zones.faces.by_face_type")
    context = PhComposer::API.connect(:session_id => @session.id)

    on = PhComposer::API.view(:context => context, :name => "ph_composer.colour_by.isolate",
                              :params => { "row" => { "value" => "Wall", "state" => "classified" } })

    assert_equal({ "value" => "Wall", "state" => "classified" }, on.dig("value", "isolated"))
    assert_equal [["Floor", false], ["Wall", true]],
                 on.dig("value", "rows").map { |row| row.values_at("label", "isolated") }
    refute_empty service.wash_triangles
    assert_includes service.fills.keys, [230, 180, 60]

    off = PhComposer::API.view(:context => context, :name => "ph_composer.colour_by.isolate", :params => {})

    assert_nil off.dig("value", "isolated")
    assert_empty service.wash_triangles
  end

  def test_turning_a_different_mode_on_shows_every_row_again
    zone_group(1_730, %w[Wall Floor])
    service = activate("ph_composer.zones.faces.by_face_type")
    service.isolate(["Wall", "classified"])

    activate("ph_composer.zones.by_zone")

    assert_nil service.isolated
    assert_empty service.wash_triangles
  end

  # A row the user set aside can stop existing. Keeping the isolation then mutes everything and
  # leaves no row offering to undo it, so the viewport stays grey with no way back.
  def test_an_isolated_row_that_stops_existing_releases_what_it_was_holding
    zone = zone_group(1_740, %w[Wall Floor])
    service = activate("ph_composer.zones.faces.by_face_type")
    service.isolate(["Wall", "classified"])
    refute_empty service.wash_triangles

    wall = zone.entities.grep(Sketchup::Face).find do |face|
      PhComposer::Zones::Faces::FACE_STORE.read(face)["face_type"] == "Wall"
    end
    record = PhComposer::Zones::Faces::FACE_STORE.read(wall)
    PhComposer::Zones::Faces::FACE_STORE.write(wall, record.merge("face_type" => "Floor"))
    service.invalidate!(:force => true)

    assert_nil service.isolated
    assert_empty service.wash_triangles
    assert_equal [false], service.legend.fetch("rows").map { |row| row.fetch("isolated") }
  end

  # The legend and the faces table have to mean the same thing by "unclassified", or the Zone row's
  # count and the legend's count are different numbers for one Model and the user is sent to
  # Suggest classification, which never touches a Face that already has a record.
  def test_a_record_missing_this_modes_field_is_incomplete_rather_than_unclassified
    zone_group(1_750, ["Wall"])
    face = Sketchup.active_model.entities.grep(Sketchup::Group).last.entities.grep(Sketchup::Face).first
    record = PhComposer::Zones::Faces::FACE_STORE.read(face)
    PhComposer::Zones::Faces::FACE_STORE.write(face, record.reject { |key, _| key == "boundary_condition" })

    service = activate("ph_composer.zones.faces.by_boundary_condition")

    assert_equal [%w[Unclassified incomplete]],
                 service.rows.map { |row| [row.label, row.state.to_s] }
  end

  def test_showing_one_row_on_its_own_while_colour_by_is_off_refuses
    context = PhComposer::API.connect(:session_id => @session.id)

    outcome = PhComposer::API.view(:context => context, :name => "ph_composer.colour_by.isolate",
                                   :params => { "row" => { "value" => "Wall", "state" => "classified" } })

    assert_equal %w[refused validation.failed], outcome.values_at("status", "code")
  end

  def test_a_client_can_set_an_occurrence_filter_while_off_without_writing_or_opening_undo
    context = PhComposer::API.connect(:session_id => @session.id)
    revision = @session.revision
    paths = [[101, 102], [201, 202]]

    outcome = PhComposer::API.view(:context => context, :name => "ph_composer.colour_by.filter",
                                   :params => { "paths" => paths })

    assert_equal "completed", outcome.fetch("status")
    assert_equal paths, outcome.dig("value", "filter_paths")
    assert_nil outcome.dig("value", "mode")
    query = PhComposer::API.query(:context => context, :name => ColourBy::STATE, :params => {})
    assert_equal paths, query.dig("value", "filter_paths")
    assert_equal revision, @session.revision
    refute @model.modified?
    assert_empty @model.operations
    assert_empty @model.overlays.to_a
  end

  def test_the_filter_command_validates_full_nonempty_positive_integer_paths
    context = PhComposer::API.connect(:session_id => @session.id)
    invalid = [{}, { "paths" => "all" }, { "paths" => [nil] }, { "paths" => [[]] },
               { "paths" => [[0]] }, { "paths" => [[-1]] }, { "paths" => [[1.5]] },
               { "paths" => [["1"]] }, { "paths" => nil, "extra" => true }]

    invalid.each do |params|
      outcome = PhComposer::API.view(:context => context, :name => "ph_composer.colour_by.filter", :params => params)

      assert_equal "refused", outcome.fetch("status"), params.inspect
      assert_nil ColourBy.for(@session).filter_paths
    end
  end

  def test_an_empty_occurrence_filter_mutes_all_and_null_restores_all
    zone_group(2_100, ["Wall", nil])
    service = activate("ph_composer.zones.faces.by_face_type")
    context = PhComposer::API.connect(:session_id => @session.id)

    outcome = PhComposer::API.view(:context => context, :name => "ph_composer.colour_by.filter",
                                   :params => { "paths" => [] })

    assert_equal [], outcome.dig("value", "filter_paths")
    assert_equal 2, service.rows.sum(&:count)
    assert_empty service.fills
    assert_empty service.outlines
    assert_empty service.unclassified_outlines
    assert_empty service.unclassified_hatch
    assert_equal 6, service.wash_triangles.length

    restored = PhComposer::API.view(:context => context, :name => "ph_composer.colour_by.filter",
                                    :params => { "paths" => nil })

    assert_nil restored.dig("value", "filter_paths")
    assert_equal 3, service.fills.values.flatten.length
    refute_empty service.unclassified_outlines
    assert_empty service.wash_triangles
  end

  def test_combined_face_paths_partition_nested_zone_geometry_in_every_zone_mode
    first = zone_group(2_200, %w[Wall Floor])
    nested = first.entities.add_group([first.entities.to_a.last])
    second = zone_group(2_210, %w[Wall Floor])
    paths = [[first.persistent_id, nested.persistent_id, nested.entities.to_a.first.persistent_id],
             [second.persistent_id, second.entities.to_a.first.persistent_id]]
    service = ColourBy.for(@session).filter(paths)

    %w[ph_composer.zones.faces.by_face_type ph_composer.zones.by_zone
       ph_composer.zones.by_level ph_composer.zones.by_building_segment].each do |name|
      service.activate(name)

      assert_equal 6, service.fills.values.flatten.length, name
      assert_equal 6, service.wash_triangles.length, name
      assert_equal paths, service.filter_paths, name
      assert_equal [0.0, 1.0], service.fills.values.flatten.map(&:z).uniq.sort, name
    end
  end

  def test_occurrence_filter_distinguishes_shared_faces_and_preserves_the_selected_transform
    group = zone_group(2_300, %w[Wall Floor])
    wrapper = @model.entities.add_group([group])
    @model.entities.delete(wrapper)
    first = Sketchup::ComponentInstance.new(2_310, wrapper.definition)
    second = Sketchup::ComponentInstance.new(2_320, wrapper.definition,
                                             :transformation => Geom::Transformation.translation([20, 0, 0]))
    @model.entities << first << second
    face = group.entities.to_a.first
    path = [second.persistent_id, group.persistent_id, face.persistent_id]
    service = ColourBy.for(@session).filter([path, path])

    %w[ph_composer.zones.faces.by_face_type ph_composer.zones.by_zone].each do |name|
      service.activate(name)

      assert_equal 3, service.fills.values.flatten.length, name
      assert_equal 9, service.wash_triangles.length, name
      assert service.fills.values.flatten.all? { |point| point.x >= 20 }, name
      assert_equal [path], service.filter_paths
    end
  end

  def test_ancestor_masks_include_descendant_faces_and_survive_off_on
    first = zone_group(2_400, %w[Wall Floor])
    zone_group(2_410, ["Wall"])
    outer = @model.entities.add_group([first])
    paths = [[outer.persistent_id]]
    service = ColourBy.for(@session).filter(paths)
    paths.first << 999
    service.activate("ph_composer.zones.faces.by_face_type")

    assert_equal 6, service.fills.values.flatten.length
    assert_equal 3, service.wash_triangles.length
    service.deactivate
    assert_equal [[outer.persistent_id]], service.legend.fetch("filter_paths")
    service.activate("ph_composer.zones.by_zone")
    assert_equal 6, service.fills.values.flatten.length
    assert_equal 3, service.wash_triangles.length
  end

  def test_a_filter_command_replaces_legacy_isolation_and_isolate_remains_available
    zone = zone_group(2_500, %w[Wall Floor])
    service = activate("ph_composer.zones.faces.by_face_type")
    service.isolate(["Wall", "classified"])
    floor_path = [zone.persistent_id, zone.entities.to_a.last.persistent_id]

    service.filter([floor_path])

    assert_nil service.isolated
    assert_equal [[128, 128, 128]], service.fills.keys, "only the selected Floor is coloured"
    service.isolate(["Wall", "classified"])
    assert_empty service.fills, "isolation still combines with an existing occurrence filter"
    assert_equal 6, service.wash_triangles.length
    service.filter(nil)
    assert_nil service.isolated
    assert_empty service.wash_triangles
    assert_equal 6, service.fills.values.flatten.length
  end

  def test_invalidation_rebuilds_filtered_geometry_without_repairing_or_clearing_the_mask
    zone = zone_group(2_600, %w[Wall Floor])
    face = zone.entities.to_a.first
    path = [zone.persistent_id, face.persistent_id]
    service = ColourBy.for(@session).filter([path]).activate("ph_composer.zones.faces.by_face_type")
    face.hidden = true
    PhComposer::Sessions.notify_host_event(@session, :tags_changed)

    assert_empty service.fills
    assert_equal 3, service.wash_triangles.length
    assert_equal [path], service.filter_paths
    rebuilds = service.rebuilds
    ColourBy.state(@session)
    assert_equal rebuilds, service.rebuilds, "a read does not rebuild the overlay"
    face.hidden = false
    @session.host_event(:transaction_committed)
    assert_equal 3, service.fills.values.flatten.length
    assert_equal [path], service.filter_paths
  end

  def test_entries_without_occurrence_paths_are_muted_only_when_an_explicit_mask_is_active
    install_synthetic_mode
    service = activate("outside.probe.by_side")
    refute_empty service.fills

    service.filter([[9001]])

    assert_empty service.fills, "shared occurrences cannot be guessed from a bare entity"
    service.filter(nil)
    refute_empty service.fills
  end

  def test_a_mode_missing_its_colour_function_refuses_the_whole_batch
    probe = Module.new do
      define_singleton_method(:name) { "Probe" }
      define_singleton_method(:install) do |registry|
        registry.feature("outside.probe", :contract_version => 1)
                .colour_mode("outside.probe.broken", :label => "Broken", :entity_kind => "side",
                                                     :colours => nil) { |_model| [] }
      end
    end

    error = assert_raises(PhComposer::RegistrationError) { Registry.install([probe]) }

    assert_includes error.diagnostics.map(&:code), "registration.schema_invalid"
    refute Registry.current.colour_modes.key?("outside.probe.broken")
  end

  def test_a_mode_group_must_be_a_name
    probe = Module.new do
      define_singleton_method(:name) { "Probe" }
      define_singleton_method(:install) do |registry|
        registry.feature("outside.probe", :contract_version => 1)
                .colour_mode("outside.probe.grouped", :label => "Grouped", :entity_kind => "side", :group => " ",
                                                      :colours => ColourBy::Palette.ramp) { |_model| [] }
      end
    end

    error = assert_raises(PhComposer::RegistrationError) { Registry.install([probe]) }

    assert_includes error.diagnostics.map(&:code), "registration.schema_invalid"
  end

  def test_activating_an_unregistered_mode_refuses_and_leaves_the_service_off
    service = ColourBy.for(@session)

    assert_raises(PhComposer::UserError) { service.activate("ph_composer.colour_by.nonexistent") }
    refute service.active?
  end

  # ------------------------------------------------------------------ the shipped modes

  def test_face_type_colours_every_face_and_counts_the_unclassified_ones
    zone_group(100, ["Wall", "Wall", nil])

    service = activate("ph_composer.zones.faces.by_face_type")

    wall, unclassified = service.rows
    assert_equal ["Wall", 2, "classified"], [wall.label, wall.count, wall.state.to_s]
    assert_equal ["Unclassified", 1, "unclassified"], [unclassified.label, unclassified.count,
                                                       unclassified.state.to_s]
    assert_equal [230, 180, 60], wall.colour, "honeybee's own Wall hue"
  end

  def test_an_attached_zone_with_no_chosen_record_reads_as_incomplete_rather_than_classified
    group = zone_group(200, ["Wall"])
    face = group.entities.to_a.first
    record = PhComposer::Zones::Faces::FACE_STORE.read(face)
    PhComposer::Zones::Faces::FACE_STORE.write(face, record.merge("boundary_condition" => "AttachedZone"))

    service = activate("ph_composer.zones.faces.by_boundary_condition")

    row = service.rows.first
    assert_equal "incomplete", row.state.to_s
    assert_equal Palette::INCOMPLETE, row.colour
  end

  def test_a_zone_mode_paints_the_zone_group_and_a_zone_with_no_level_is_unclassified
    zone_group(300, ["Wall"], :level => nil)
    zone_group(400, ["Wall"], :level => "L1", :name => "Upper")

    service = activate("ph_composer.zones.by_level")

    assert_equal %w[L1 Unclassified], service.rows.map(&:label)
    assert_equal [1, 1], service.rows.map(&:count)
  end

  # ------------------------------------------------------------------ what is drawn

  def test_fills_are_batched_one_draw_a_colour_rather_than_one_a_face
    zone_group(500, %w[Wall Wall Wall RoofCeiling])

    activate("ph_composer.zones.faces.by_face_type")
    overlay = @model.overlays.to_a.first
    overlay.draw(@model.active_view)

    fills = @model.active_view.draws.select { |(mode, _points, _colour, _width)| mode == GL_TRIANGLES }
    assert_equal 2, fills.length, "one batch a legend row, whatever the face count"
    assert_equal [9, 3], fills.map { |(_mode, points, _colour, _width)| points.length }
  end

  def test_an_unclassified_face_is_hatched_and_outlined_without_a_fill_or_model_write
    zone = zone_group(600, [nil])
    zone.transformation = Geom::Transformation.scaling(24)

    service = activate("ph_composer.zones.faces.by_face_type")
    refute_empty service.unclassified_hatch
    refute_empty service.unclassified_outlines
    assert_empty service.fills
    # Draw must consume the cache even if the geometry changes between a host event and repaint.
    zone.entities.grep(Sketchup::Face).first.define_singleton_method(:mesh) { |*_args| raise "mesh read in draw" }
    overlay = @model.overlays.to_a.first
    overlay.draw(@model.active_view)

    modes = @model.active_view.draws.map(&:first)
    refute_includes modes, GL_TRIANGLES
    assert_equal [GL_LINES, GL_LINES], modes
    assert_equal [2, 1], @model.active_view.draws.map(&:last)
    refute @model.modified?
  end

  def test_assembly_none_keeps_the_hatch_without_drawing_over_native_boundary_edges
    zone = zone_group(605, [nil, "Wall"])
    zone.transformation = Geom::Transformation.scaling(24)
    service = activate("ph_composer.zones.faces.by_assembly")

    assert_empty service.unclassified_outlines, "None leaves the native selection edges visible"
    refute_empty service.unclassified_hatch
    assert_empty service.fills
    @model.overlays.to_a.first.draw(@model.active_view)
    assert_equal [GL_LINES], @model.active_view.draws.map(&:first), "only the hatch is drawn"
    assert_equal [1], @model.active_view.draws.map(&:last), "no solid two-pixel boundary pass"
    refute @model.modified?

    service.activate("ph_composer.zones.faces.by_face_type")
    refute_empty service.unclassified_outlines, "other modes retain their unclassified treatment"
    refute_empty service.fills, "the classified colour fill still paints"
  end

  def test_unclassified_hatch_follows_isolation_and_visibility
    zone = zone_group(605, ["Wall", nil])
    zone.transformation = Geom::Transformation.scaling(24)
    service = activate("ph_composer.zones.faces.by_face_type")
    refute_empty service.unclassified_hatch

    service.isolate([nil, :unclassified])
    refute_empty service.unclassified_hatch
    refute_empty service.wash_triangles
    assert_empty service.fills

    zone.entities.grep(Sketchup::Face).last.hidden = true
    service.invalidate!(:force => true)
    assert_empty service.unclassified_hatch
    assert_empty service.unclassified_outlines
    assert_equal 1, service.rows.last.count, "hidden Faces still belong to the legend"
  end

  def test_the_hud_names_the_mode_and_lists_every_legend_row
    zone_group(700, ["Wall", nil])

    activate("ph_composer.zones.faces.by_face_type")
    @model.overlays.to_a.first.draw(@model.active_view)

    texts = @model.active_view.texts.map { |(_point, text, _options)| text }
    assert_equal ["Face type", "Wall (1)", "Unclassified (1)"], texts
  end

  def test_isolation_washes_geometry_without_a_mode_outline_and_names_its_scope_in_the_hud
    zone_group(710, ["Wall", nil])
    service = activate("ph_composer.zones.faces.by_face_type")
    service.isolate(["Wall", "classified"])

    @model.overlays.to_a.first.draw(@model.active_view)

    wash, fill = @model.active_view.draws
    assert_equal GL_TRIANGLES, wash.first
    assert_equal [255, 255, 255, Palette::ISOLATION_WASH_ALPHA], wash[2].to_a
    assert_equal Palette::FILL_ALPHA, fill[2].alpha
    assert_equal 2, @model.active_view.draws.length, "classification paints fills without replacing native edges"
    assert_empty service.unclassified_outlines, "the set-aside Face loses its unclassified styling"
    assert_empty service.unclassified_hatch
    assert_equal Palette::UNCLASSIFIED, service.rows.last.colour, "its legend keeps the original meaning"
    assert_equal ["Face type", "Showing only: Wall", "Wall (1)", "Unclassified (1)"],
                 @model.active_view.texts.map { |(_point, text, _options)| text }
  end

  def test_isolating_a_real_grey_value_keeps_its_fill_distinct_from_the_wash_without_painting_edges
    # Level "g" selects the real grey in the categorical ramp: alone, it takes its digest's slot, 7.
    zone_group(720, ["Wall"], :level => "g")
    zone_group(730, ["Wall"], :level => nil)
    service = activate("ph_composer.zones.by_level")
    service.isolate(["g", "classified"])

    @model.overlays.to_a.first.draw(@model.active_view)

    assert_equal [[127, 127, 127]], service.fills.keys
    assert_equal [[127, 127, 127]], service.outlines.keys
    refute_empty service.wash_triangles
    assert_equal [Palette::ISOLATION_WASH_ALPHA, Palette::FILL_ALPHA],
                 @model.active_view.draws.map { |_mode, _points, colour, _width| colour.alpha }
    assert @model.active_view.draws.all? { |mode, _points, _colour, _width| mode == GL_TRIANGLES }
  end

  def test_hidden_geometry_and_a_hidden_tag_are_not_painted
    group = zone_group(800, %w[Wall Wall Wall])
    faces = group.entities.to_a
    faces[0].hidden = true
    faces[1].layer = Sketchup::Tag.new("Roof", false)

    service = activate("ph_composer.zones.faces.by_face_type")

    assert_equal 3, service.rows.first.count, "the legend still counts every classified Face"
    assert_equal 3, service.fills.values.first.length, "only the visible Face is drawn"
  end

  def test_hidden_or_tagged_zone_ancestors_suppress_zone_modes_without_changing_legend_counts
    group = zone_group(810, ["Wall"])
    outer = @model.entities.add_group([group])
    @model.entities.add_group([outer])
    modes = ColourBy.modes.map { |mode| mode.fetch("name") }.select { |name| name.start_with?("ph_composer.zones.") }
    [:hidden, :tag].each do |visibility|
      outer.hidden = visibility == :hidden
      outer.layer = Sketchup::Tag.new("Container", visibility != :tag)
      modes.each do |mode|
        service = activate(mode)
        assert_equal 1, service.rows.sum(&:count), "#{mode} still counts the hidden occurrence"
        assert_empty service.fills, "#{mode} does not paint through an ancestor"
        assert_empty service.outlines
      end
    end
    outer.hidden = false
    outer.layer = Sketchup::Tag.new("Container", true)
    service = activate("ph_composer.zones.faces.by_face_type")
    assert_equal 3, service.fills.values.flatten.length
  end

  def test_hiding_the_zone_itself_suppresses_its_flattened_face_entries
    group = zone_group(815, %w[Wall Floor])
    group.hidden = true
    service = activate("ph_composer.zones.faces.by_face_type")
    assert_equal 2, service.rows.sum(&:count)
    assert_empty service.fills
    assert_empty service.outlines
    group.hidden = false
    service.invalidate!(:force => true)
    assert_equal 6, service.fills.values.flatten.length
  end

  def test_hidden_nested_groups_inside_a_zone_are_not_painted_by_face_or_zone_modes
    group = zone_group(820, %w[Wall Wall])
    nested = group.entities.add_group([group.entities.to_a.first])
    nested.hidden = true
    %w[ph_composer.zones.faces.by_face_type ph_composer.zones.by_zone].each do |mode|
      service = activate(mode)
      assert_equal 3, service.fills.values.flatten.length, "#{mode} paints only the visible Face"
    end
    nested.hidden = false
    nested.layer = Sketchup::Tag.new("Nested", false)
    service = activate("ph_composer.zones.faces.by_boundary_condition")
    assert_equal 3, service.fills.values.flatten.length
    assert_equal 2, service.rows.sum(&:count)
  end

  def test_a_hidden_shared_occurrence_does_not_hide_its_visible_twin
    group = zone_group(830, ["Wall"])
    wrapper = @model.entities.add_group([group])
    @model.entities.delete(wrapper)
    first = Sketchup::ComponentInstance.new(840, wrapper.definition)
    second = Sketchup::ComponentInstance.new(850, wrapper.definition,
                                             :transformation => Geom::Transformation.translation([20, 0, 0]))
    @model.entities << first << second
    [:hidden, :tag].each do |visibility|
      first.hidden = visibility == :hidden
      first.layer = Sketchup::Tag.new("First occurrence", visibility != :tag)
      %w[ph_composer.zones.faces.by_face_type ph_composer.zones.by_zone].each do |mode|
        service = activate(mode)
        assert_equal 2, service.rows.sum(&:count)
        points = service.fills.values.flatten
        assert_equal 3, points.length
        assert points.all? { |point| point.x >= 20 }, "the visible occurrence's transform survives"
      end
    end
  end

  def test_occurrence_visibility_rejects_missing_or_mismatched_paths
    group = zone_group(860, ["Wall"])
    face = group.entities.to_a.first
    visibility = ColourBy::OccurrenceVisibility.new(@model)
    assert visibility.visible?([group.persistent_id, face.persistent_id], face)
    refute visibility.visible?([999, face.persistent_id], face)
    refute visibility.visible?([group.persistent_id, 999], face)
    refute visibility.visible?([group.persistent_id], face)
    refute visibility.visible?([], face)
    refute visibility.visible?("invalid", face)
    assert visibility.visible?(nil, face), "legacy entries retain entity-only tessellation"
  end

  # A fill drawn exactly on the Face it colours z-fights with that Face and the host blinks between
  # the two, so every drawn point is lifted toward the camera. The stub's camera is high above the
  # fixtures at one model unit a pixel, so the lift reads as a clean +z of two units.
  def test_every_drawn_point_is_lifted_off_the_face_toward_the_camera
    zone_group(950, ["Wall"])
    activate("ph_composer.zones.faces.by_face_type")
    @model.overlays.to_a.first.draw(@model.active_view)

    drawn = @model.active_view.draws.flat_map { |_mode, points, _colour, _width| points }

    refute_empty drawn
    # The camera is not exactly overhead of every vertex, so the lift is two units along the line
    # to the eye rather than exactly two units of z.
    drawn.each { |point| assert_in_delta 2.0, point.z, 0.01, "the Face sits at z = 0, the drawing above it" }
  end

  # ------------------------------------------------------------------ lifecycle

  def test_turning_a_mode_on_adds_one_overlay_and_turning_it_off_removes_it
    zone_group(900, ["Wall"])

    service = activate("ph_composer.zones.faces.by_face_type")
    assert_equal 1, @model.overlays.to_a.length
    # An overlay the host accepts is not one the host draws: `add` leaves it disabled and `draw` is
    # never called until something enables it (context/SKETCHUP_HOST_BEHAVIOR.md).
    assert @model.overlays.to_a.first.enabled?, "an added overlay still has to be enabled to draw"

    service.deactivate
    assert_equal 0, @model.overlays.to_a.length
    refute service.active?
    assert_empty service.rows
  end

  def test_a_closed_model_takes_its_overlay_with_it
    zone_group(1000, ["Wall"])
    activate("ph_composer.zones.faces.by_face_type")

    @session.detach

    assert_equal 0, @model.overlays.to_a.length
  end

  # The close path reaches feature state after the Model is gone, and a closed Model still answers
  # `respond_to?(:overlays)` while reading them raises. Nothing may be read from it here.
  def test_tearing_down_a_model_that_has_already_closed_raises_nothing
    zone_group(1050, ["Wall"])
    activate("ph_composer.zones.faces.by_face_type")
    @model.close

    PhComposer::Sessions.detach(@model)

    refute ColourBy.for(@session).active?
  end

  def test_closing_a_model_takes_its_tag_observer_with_it
    PhComposer::Sessions.detach(@model)

    assert_empty @model.layers.observers
  end

  def test_turning_a_mode_on_writes_nothing_to_the_model
    group = zone_group(1100, ["Wall"])
    before = PhComposer::Zones::ZONE_STORE.read(group)

    activate("ph_composer.zones.faces.by_face_type")

    assert_equal before, PhComposer::Zones::ZONE_STORE.read(group)
    assert_empty @model.operations, "no native operation opens, so Undo history is unchanged"
    assert_equal 1, @session.revision
  end

  def test_a_committed_change_rebuilds_the_drawing_once_a_revision
    group = zone_group(1200, ["Wall"])
    service = activate("ph_composer.zones.faces.by_face_type")
    assert_equal 1, service.rows.length

    face = group.entities.to_a.first
    PhComposer::Zones::Faces::FACE_STORE.write(face, PhComposer::Zones::Faces::FACE_STORE.read(face)
      .merge("face_type" => "Floor"))
    @session.host_event(:transaction_committed)

    assert_equal "Floor", service.rows.first.label
    drawn = @model.active_view.invalidations
    @session.host_event(:transaction_committed) && @session.host_event(:active_path_changed)
    assert_operator @model.active_view.invalidations, :>, drawn, "a later revision redraws"
  end

  def test_public_make_zone_refreshes_an_active_overlay_after_the_revision_advances
    zone_group(1_250, [nil])
    context = PhComposer::API.connect(:session_id => @session.id)
    sources = PhComposer::API.query(:context => context, :name => "ph_composer.zones.options.adoption_preview")
                             .dig("value", "sources")
    adopted = PhComposer::API.invoke(:context => context, :name => "ph_composer.zones.options.adopt",
                                     :params => { "mappings" => sources.map { |source|
                                       { "source" => source.fetch("key"), "target_id" => nil,
                                         "name" => source.fetch("name"), "colour" => source.fetch("colour") }
                                     } }, :request => { "sequence" => 1, "expected_revision" => @session.revision })
    assert_equal "completed", adopted.fetch("status"), adopted.inspect
    loose_face = Sketchup::Face.new(1_261, {}, :points => [point(0, 0, 0), point(24, 0, 0),
                                                           point(24, 24, 0)])
    loose_group = Sketchup::Group.new(1_260, Sketchup::Entities.new([loose_face]))
    @model.entities << loose_group
    service = activate("ph_composer.zones.faces.by_face_type")
    assert_equal 1, service.rows.last.count
    assert_equal 1, service.rebuilds
    context = PhComposer::API.connect(:session_id => @session.id)

    made = PhComposer::API.invoke(
      :context => context, :name => "ph_composer.zones.make",
      :params => { "parent_path" => [], "entity_ids" => [loose_group.persistent_id] },
      :request => { "sequence" => 1, "expected_revision" => @session.revision }
    )

    assert_equal %w[completed committed], made.values_at("status", "effect")
    assert_equal 2, service.rows.sum(&:count)
    assert_equal 1, service.rows.find { |row| row.state == :unclassified }.count
    assert_equal 1, service.rows.find { |row| row.state == :classified }.count
    assert_equal 2, service.rebuilds, "the in-commit callback and action publication coalesce"
    refute_empty service.fills, "automatic Suggest projects the newly authored Face immediately"
    assert_equal 1, @model.overlays.to_a.length
  end

  def test_a_second_event_at_the_same_revision_does_not_rebuild
    zone_group(1300, ["Wall"])
    service = activate("ph_composer.zones.faces.by_face_type")
    PhComposer::Sessions.notify_host_event(@session, :transaction_committed)
    settled = @model.active_view.invalidations

    service.invalidate!

    assert_equal settled, @model.active_view.invalidations
  end

  # Hiding a tag changes what may be painted and advances no revision, so it is the one event that
  # rebuilds without one.
  def test_hiding_a_tag_rebuilds_although_the_revision_is_unchanged
    group = zone_group(1400, %w[Wall Wall])
    service = activate("ph_composer.zones.faces.by_face_type")
    assert_equal 6, service.fills.values.first.length

    group.entities.to_a.first.layer = Sketchup::Tag.new("Walls", false)
    PhComposer::HostObservers::LayersObserver.new.onLayerChanged(@model.layers, nil)

    assert_equal 3, service.fills.values.first.length
    assert_equal 2, service.rebuilds, "the tag event rebuilt once more"
    assert_equal 1, @session.revision, "a tag is not a Model change"
  end

  # A tag shows only while every tag folder holding it shows. Hiding a folder leaves the tag's own flag
  # alone, so the folder event is what rebuilds.
  def test_a_face_under_a_hidden_tag_folder_is_not_painted_and_a_folder_change_rebuilds
    group = zone_group(1410, %w[Wall Wall])
    outer = Sketchup::LayerFolder.new("Envelope", true)
    inner = Sketchup::LayerFolder.new("Walls", true, outer)
    group.entities.to_a.first.layer = Sketchup::Tag.new("North wall", true, inner)
    service = activate("ph_composer.zones.faces.by_face_type")
    assert_equal 6, service.fills.values.first.length

    outer.visible = false
    PhComposer::HostObservers::LayersObserver.new.onLayerFolderChanged(@model.layers, outer)

    assert_equal 3, service.fills.values.first.length
    assert_equal 2, service.rows.first.count, "the legend still counts the hidden Face"
    assert_equal 2, service.rebuilds
  end

  # ------------------------------------------------------------------ reads

  def test_a_projection_that_raises_turns_its_own_mode_off_rather_than_the_extension
    install_raising_mode

    service = ColourBy.for(@session).activate("outside.probe.broken")

    refute service.active?
    assert_equal 0, @model.overlays.to_a.length
  end

  def test_failed_tessellation_returns_off_warns_and_preserves_the_last_successful_preference
    group = zone_group(2010, ["Wall"])
    activate("ph_composer.zones.by_zone")
    group.entities.grep(Sketchup::Face).first.define_singleton_method(:mesh) { |*_args| raise "mesh failed" }
    notices = []
    PhComposer::Sessions.on_notice { |_session, message, tone| notices << [message, tone] }
    context = PhComposer::API.connect(:session_id => @session.id)

    outcome = PhComposer::API.view(:context => context, :name => "ph_composer.colour_by.activate",
                                   :params => { "mode" => "ph_composer.zones.faces.by_face_type" })

    assert_equal "completed", outcome.fetch("status"), "the panel receives the recovered Off snapshot"
    assert_nil outcome.dig("value", "mode")
    assert_empty outcome.dig("value", "rows")
    assert_empty @model.overlays.to_a
    assert_equal "ph_composer.zones.by_zone", ColourBy.remembered_mode
    assert_equal [["Face type could not be drawn, so Colour by is off.", :warning]], notices
    assert_empty @model.operations
  end

  def test_a_broken_preference_from_an_earlier_process_is_survivable_and_can_be_replaced
    install_raising_mode
    zone_group(2040, ["Wall"])
    PhComposer::Preferences.set("colour_by_mode", "outside.probe.broken")

    service = ColourBy::Service.new(@session).activate(ColourBy.remembered_mode)

    refute service.active?
    assert_empty @model.overlays.to_a
    service.activate("ph_composer.zones.by_zone")
    assert service.active?
    assert_equal "ph_composer.zones.by_zone", ColourBy.remembered_mode
  end

  def test_tessellation_failure_during_invalidation_clears_all_caches_and_allows_later_subscribers
    group = zone_group(2020, %w[Wall Floor])
    service = activate("ph_composer.zones.faces.by_face_type")
    service.isolate(["Wall", "classified"])
    group.entities.grep(Sketchup::Face).last.define_singleton_method(:mesh) { |*_args| raise "mesh failed" }
    reached = []
    PhComposer::Sessions.on_host_event(:transaction_committed) { |_session| reached << :ran }

    @session.host_event(:transaction_committed)

    assert_equal [:ran], reached
    refute service.active?
    assert_nil service.isolated
    assert_empty service.rows
    assert_empty service.fills
    assert_empty service.outlines
    assert_empty service.unclassified_outlines
    assert_empty service.unclassified_hatch
    assert_empty service.wash_triangles
    assert_empty @model.overlays.to_a
  end

  # One mode failing must not take the rest of the extension's host-event handling with it: the
  # session publishes to subscribers in install order and does not rescue for them.
  def test_a_failing_projection_does_not_stop_a_later_host_event_subscriber
    install_raising_mode
    reached = []
    PhComposer::Sessions.on_host_event(:transaction_committed) { |_session| reached << :ran }
    ColourBy.for(@session).activate("outside.probe.broken")
    ColourBy.for(@session).instance_variable_set(:@mode_name, "outside.probe.broken")

    @session.host_event(:transaction_committed)

    assert_equal [:ran], reached
  end

  def test_a_translated_zone_and_a_translated_nested_group_land_in_world_coordinates
    outer = zone_group(1900, [])
    outer.transformation = Geom::Transformation.translation([10, 0, 0])
    inner_face = Sketchup::Face.new(1999, {}, :points => [point(0, 0, 0), point(2, 0, 0), point(2, 2, 0)])
    # Real Groups contain Edges too; a fixture with Faces only once hid a host failure.
    edge = Sketchup::Edge.new(1998, point(0, 0, 0), point(2, 0, 0))
    inner = Sketchup::Group.new(1990, Sketchup::Entities.new([edge, inner_face]))
    inner.transformation = Geom::Transformation.translation([0, 5, 0])
    outer.entities << inner

    service = activate("ph_composer.zones.by_zone")

    corners = service.fills.values.first.map { |corner| [corner.x, corner.y, corner.z] }
    assert_includes corners, [10.0, 5.0, 0.0], "the Zone's own transform and the nested one compose once each"
  end

  def test_the_state_query_reports_the_active_mode_every_registered_mode_and_the_legend
    zone_group(1500, ["Wall", nil])
    activate("ph_composer.zones.faces.by_face_type")
    context = PhComposer::API.connect(:session_id => @session.id)

    value = PhComposer::API.query(:context => context, :name => "ph_composer.colour_by.state").fetch("value")

    assert_equal "ph_composer.zones.faces.by_face_type", value.fetch("mode")
    assert_equal "Face type", value.fetch("label")
    assert_equal [{ "value" => "Wall", "label" => "Wall", "colour" => [230, 180, 60], "count" => 1,
                    "state" => "classified", "isolated" => false },
                  { "value" => nil, "label" => "Unclassified", "colour" => Palette::UNCLASSIFIED,
                    "count" => 1, "state" => "unclassified", "isolated" => false }], value.fetch("rows")
    assert_nil value.fetch("isolated")
    assert_includes value.fetch("modes").map { |mode| mode.fetch("name") }, "ph_composer.zones.by_zone"
    groups = value.fetch("modes").to_h { |mode| [mode.fetch("name"), mode.fetch("group")] }
    assert_equal ["construction", nil], groups.values_at("ph_composer.zones.faces.by_assembly",
                                                         "ph_composer.zones.by_zone")
  end

  def test_the_mode_the_user_last_turned_on_is_remembered_after_it_is_turned_off
    zone_group(1600, ["Wall"])
    service = activate("ph_composer.zones.by_zone")
    service.deactivate

    assert_equal "ph_composer.zones.by_zone", ColourBy.remembered_mode
  end

  def test_a_mode_the_host_cannot_remember_still_turns_on
    zone_group(1650, ["Wall"])
    Sketchup.refuse_default_writes = true

    service = activate("ph_composer.zones.by_zone")

    assert service.active?
    assert_nil ColourBy.remembered_mode
  end

  def test_the_menu_turns_a_mode_on_and_off_and_checks_the_active_one
    zone_group(1700, ["Wall"])
    PhComposer::Commands.install
    menu = PhComposer::Commands.colour_by_menu
    by_zone = menu.entries.find { |entry| entry.is_a?(Array) && entry.first == "Zone" }
    off = menu.entries.find { |entry| entry.is_a?(Array) && entry.first == "Off" }

    by_zone.last.call

    assert_equal "ph_composer.zones.by_zone", ColourBy.for(@session).mode_name
    assert_equal MF_CHECKED, PhComposer::Commands.colour_by_check("ph_composer.zones.by_zone")
    assert_equal MF_UNCHECKED, PhComposer::Commands.colour_by_check(nil)

    off.last.call

    refute ColourBy.for(@session).active?
    assert_equal MF_CHECKED, PhComposer::Commands.colour_by_check(nil)
  end

  def test_a_zone_paints_the_faces_of_a_group_nested_inside_it
    outer = zone_group(1800, [])
    inner_face = Sketchup::Face.new(1899, {}, :points => [point(0, 0, 0), point(2, 0, 0), point(2, 2, 0)])
    outer.entities << Sketchup::Group.new(1890, Sketchup::Entities.new([inner_face]))

    service = activate("ph_composer.zones.by_zone")

    assert_equal 3, service.fills.values.first.length, "the nested Group's Face is reached and drawn"
  end

  def test_all_zone_modes_ignore_edges_alongside_faces_in_real_group_contents
    group = zone_group(2030, ["Wall"])
    group.entities << Sketchup::Edge.new(2032, point(0, 0, 0), point(2, 0, 0))

    %w[by_zone by_building_segment by_level].each do |name|
      service = activate("ph_composer.zones.#{name}")

      assert service.active?, "#{name} must survive a Group's Edge"
      assert_equal 3, service.fills.values.first.length
      assert_equal 1, service.rows.first.count
    end
  end

  def test_the_colour_by_menu_offers_every_registered_mode_and_an_off_entry
    PhComposer::Commands.install
    menu = PhComposer::Commands.colour_by_menu

    labels = menu.entries.map { |entry| entry.is_a?(Array) ? entry.first : entry }
    # The registered readouts follow the modes, after a separator.
    modes = labels.take_while { |label| label != :separator }

    assert_equal ColourBy.modes.map { |mode| mode.fetch("label") } + ["Off"], modes
  end

  private

  def activate(name)
    ColourBy.for(@session).activate(name)
  end

  def install_raising_mode
    probe = Module.new do
      define_singleton_method(:name) { "Probe" }
      define_singleton_method(:install) do |registry|
        registry.feature("outside.probe", :contract_version => 1)
                .colour_mode("outside.probe.broken", :label => "Broken", :entity_kind => "side",
                                                     :colours => PhComposer::ColourBy::Palette.ramp) do |_model|
          raise "the Model could not be read"
        end
      end
    end
    Registry.install([probe])
  end

  def install_synthetic_mode
    faces = [Sketchup::Face.new(9001, {}), Sketchup::Face.new(9002, {})]
    @model.entities << faces[0] << faces[1]
    probe = Module.new do
      define_singleton_method(:name) { "Probe" }
      define_singleton_method(:install) do |registry|
        colours = PhComposer::ColourBy::Palette.fixed("outside" => [10, 20, 30], "inside" => [40, 50, 60])
        registry.feature("outside.probe", :contract_version => 1)
                .colour_mode("outside.probe.by_side", :label => "Side", :entity_kind => "side",
                                                      :colours => colours) do |read|
          read.model.entities.to_a.select { |entity| entity.is_a?(Sketchup::Face) }.each_with_index.map do |face, index|
            PhComposer::ColourBy::Entry.new(:entity => face, :transform => Geom::Transformation.new,
                                            :value => index.zero? ? "outside" : "inside",
                                            :label => index.zero? ? "Outside" : "Inside")
          end
        end
      end
    end
    Registry.install([probe])
  end

  # One Zone Group with one Face per entry in `types`; a nil type leaves that Face unclassified.
  def zone_group(base, types, level: "L1", name: "Zone")
    faces = types.each_with_index.map do |face_type, index|
      face = Sketchup::Face.new(base + index + 1, {}, :points => [point(0, 0, index), point(2, 0, index),
                                                                  point(2, 2, index)])
      next face unless face_type

      PhComposer::Zones::Faces::FACE_STORE.write(face, {
        "id" => format("fac_%<base>d%<index>07d", :base => base, :index => index), "schema_version" => 1,
        "face_type" => face_type, "boundary_condition" => "Outdoors", "user_data" => {}, "extension_data" => {}
      })
      face
    end
    group = Sketchup::Group.new(base, Sketchup::Entities.new(faces))
    @model.entities << group
    PhComposer::Zones::ZONE_STORE.write(group, {
      "id" => format("zon_%<base>012d", :base => base), "schema_version" => 1, "name" => "#{name} #{base}",
      "building_segment" => "Main Building", "level" => level, "ground_depth_mm" => 0.0,
      "user_data" => {}, "extension_data" => {}
    })
    group
  end

  def point(x_value, y_value, z_value)
    Geom::Point3d.new(x_value, y_value, z_value)
  end
end
