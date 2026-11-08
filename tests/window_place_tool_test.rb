# frozen_string_literal: true

require_relative "test_helper"
require_relative "support/window_record_fixtures"
require_relative "support/assembly_assignment_fixtures"

class WindowPlaceToolTest < PhComposerTestCase
  include WindowRecordFixtures
  include AssemblyAssignmentFixtures

  PREFIX = "ph_composer.windows.place_tool"

  def setup
    super
    assignment_setup
    PhComposer::Registry.install([W]) unless PhComposer::Registry.installed?(W::FEATURE_ID)
    points = [[0, 0, 0], [8, 0, 0], [8, 0, 6], [0, 0, 6]].map do |point|
      Geom::Point3d.new(*point.map { |coordinate| coordinate / 0.0254 })
    end
    @face = Sketchup::Face.new(1001, {}, :points => points)
    @group = Sketchup::Group.new(1000, Sketchup::Entities.new([@face]))
    @model.entities << @group
    made = assignment_invoke("ph_composer.zones.make", "parent_path" => [], "entity_ids" => [1000])
    assert_equal "completed", made.fetch("status"), made.inspect
    @host = assignment_faces.first.fetch("reference")
    created = assignment_invoke("ph_composer.windows.types.create",
                                "values" => { "name" => "Place test", "rows_m" => [1.5], "columns_m" => [0.7] })
    assert_equal "completed", created.fetch("status"), created.inspect
    @type_id = created.fetch("value").fetch("id")
    @tool = W.place_tool(@session)
    @view = @model.active_view
    @notices = []
    PhComposer::Sessions.on_notice { |session, message, tone| @notices << [message, tone] if session == @session }
    @picked = { :path => [@group, @face], :point => Geom::Point3d.new(2 / 0.0254, 0, 1 / 0.0254) }
  end

  def choose(params = {})
    result = API.view(:context => @context, :name => "#{PREFIX}.choose",
                      :params => { "type_id" => @type_id }.merge(params))
    assert_equal "completed", result.fetch("status"), result.inspect
    result.fetch("value")
  end

  def picked
    PhComposer::Pick.stub(:face_point, ->(*_args) { @picked }) { yield }
  end

  # Pointer moves may read only Zones' walk-free host context, once per newly picked Face. Returns
  # those reads.
  def host_reads(message)
    reads = []
    query = API.method(:query)
    API.stub(:query, lambda do |**args|
      flunk message unless args.fetch(:name) == W::Placement::Hosts::CONTEXT
      reads << args.fetch(:params)
      query.call(**args)
    end) { yield }
    reads
  end

  def down
    picked { @tool.onLButtonDown(0, 10, 10, @view) }
  end

  def up
    @tool.onLButtonUp(0, 10, 10, @view)
  end

  def units
    assignment_query("ph_composer.windows.units.list").fetch("units")
  end

  def type
    PhComposer::Records::Engine.new(@model, PhComposer::Registry.current.catalog).find(W::TYPE_KIND, @type_id)
  end

  def anchor_point(row)
    unit = W::Units::Occurrences.resolve(@model, row.fetch("reference"))
    plan = W::Units::DefinitionPlan.build(type)
    W::Units::WorldGeometry.anchor(plan, row.fetch("values").fetch("anchor"), unit.transform.to_a)
  end

  def parser(values)
    existed = Sketchup.respond_to?(:parse_length)
    original = Sketchup.method(:parse_length) if existed
    Sketchup.define_singleton_method(:parse_length) { |text| values.fetch(text, nil) }
    yield
  ensure
    if existed
      Sketchup.define_singleton_method(:parse_length, original)
    else
      Sketchup.singleton_class.remove_method(:parse_length)
    end
  end

  def test_choose_stop_get_are_view_state_only_with_default_anchor_and_detached_host
    before = @model.operations.length
    revision = @session.revision
    state = choose("host" => @host)
    assert_equal "sill_center", state.fetch("anchor")
    assert state.fetch("active")
    assert_equal @host, state.fetch("host")
    state.fetch("host")["zone_path"] << 999
    read = assignment_query("#{PREFIX}.get")
    assert_equal @host, read.fetch("host")
    stopped = API.view(:context => @context, :name => "#{PREFIX}.stop").fetch("value")
    refute stopped.fetch("active")
    assert_equal @type_id, stopped.fetch("type_id")
    assert_equal before, @model.operations.length
    assert_equal revision, @session.revision
  end

  def test_each_click_invokes_one_public_place_and_tool_remains_for_next_click
    choose
    before = @model.operations.length
    down
    up
    up
    assert_equal 1, units.length
    assert_equal before + 1, @model.operations.length
    assert @tool.active?
    @picked[:point] = Geom::Point3d.new(4 / 0.0254, 0, 1 / 0.0254)
    down
    up
    assert_equal 2, units.length
    assert_equal before + 2, @model.operations.length
    assert_includes Sketchup.status_texts.last, "Placed Window"
    assert_equal "Placed Window.", @notices.last.first
  end

  def test_palette_and_measurement_changes_mid_gesture_do_not_change_frozen_intent
    choose("anchor" => "sill_left")
    down
    choose("anchor" => "head_right")
    parser("1m" => 1 / 0.0254) { @tool.onUserText("sill=1m", @view) }
    up
    assert_equal "sill_left", units.first.fetch("values").fetch("anchor")
    assert_in_delta 1, anchor_point(units.first).last, 1e-12
  end

  def test_revision_changed_after_down_refuses_and_next_click_refreshes_semantics
    choose
    down
    changed = assignment_invoke("ph_composer.windows.types.update",
                                "id" => @type_id,
                                "values" => { "notes" => "Changed" },
                                "expected_values" => { "notes" => type.fetch("notes") })
    assert_equal "completed", changed.fetch("status"), changed.inspect
    before = @model.operations.length
    up
    assert_empty units
    assert_equal before, @model.operations.length
    assert_includes @notices.last.first, "changed"
    down
    up
    assert_equal 1, units.length
  end

  def test_escape_deactivation_suspend_and_model_switch_abandon_pending_without_operations
    choose
    before = @model.operations.length
    down
    @tool.onCancel(0, @view)
    up
    refute @tool.active?
    choose
    down
    @tool.suspend(@view)
    up
    @tool.resume(@view)
    down
    @model.select_tool(nil)
    up
    choose
    down
    Sketchup.active_model = Sketchup::Model.new
    up
    Sketchup.active_model = @model
    assert_empty units
    assert_equal before, @model.operations.length
  end

  def test_callback_exception_cancels_pending_gesture_and_reports_both_channels
    choose
    down
    PhComposer::Pick.stub(:face_point, ->(*_args) { raise "Synthetic pick failure" }) do
      @tool.onMouseMove(MK_LBUTTON, 20, 20, @view)
    end
    before = @model.operations.length
    up
    assert_empty units
    assert_equal before, @model.operations.length
    assert_includes Sketchup.status_texts.last, "Nothing was written"
    assert_includes @notices.last.first, "Nothing was written"
  end

  def test_si_and_ip_native_lengths_set_actual_sill_for_every_vertical_anchor
    %w[sill_center center head_center].each_with_index do |anchor, index|
      choose("anchor" => anchor)
      text = index.even? ? "900mm" : "3'"
      height = index.even? ? 0.9 : 0.9144
      parser("900mm" => 900 / 25.4, "3'" => 36) { @tool.onUserText("sill=#{text}", @view) }
      @picked[:point] = Geom::Point3d.new((2 + index * 2) / 0.0254, 0, 2 / 0.0254)
      down
      up
      row = units.find { |unit| unit.fetch("values").fetch("anchor") == anchor }
      vertical = 1 - W::Units::Anchors::FRACTIONS.fetch(anchor).last
      assert_in_delta height, anchor_point(row).last - 1.5 * vertical, 1e-12
    end
  end

  def test_nearest_edge_offset_uses_anchor_perpendicular_inset_in_si_and_ip
    choose("anchor" => "sill_left")
    parser("300mm" => 300 / 25.4) { @tool.onUserText("offset=300mm", @view) }
    @picked[:point] = Geom::Point3d.new(0.1 / 0.0254, 0, 2 / 0.0254)
    down
    up
    assert_in_delta 0.3, anchor_point(units.first).first, 1e-12
    choose("anchor" => "sill_right")
    parser('12"' => 12) { @tool.onUserText('offset=12"', @view) }
    @picked[:point] = Geom::Point3d.new(7.9 / 0.0254, 0, 2 / 0.0254)
    down
    up
    row = units.find { |unit| unit.fetch("values").fetch("anchor") == "sill_right" }
    assert_in_delta 8 - 0.3048, anchor_point(row).first, 1e-12
  end

  def test_hover_reads_one_host_context_per_face_never_walks_units_and_draws_world_outline
    choose
    reads = host_reads("Hover queried more than the host Face") do
      W::Units::Occurrences.stub(:all, ->(_model) { flunk "Hover walked Units" }) do
        picked { @tool.onMouseMove(0, 10, 10, @view) }
        @tool.draw(@view)
      end
    end
    assert_equal 1, reads.length
    assert_empty(host_reads("A second hover over the same Face read again") do
      picked { @tool.onMouseMove(0, 10, 10, @view) }
    end)
    assert_equal GL_LINES, @view.draws.last.first
    assert_equal 8, @view.draws.last[1].length
    before = @view.draws.length
    Sketchup.active_model = Sketchup::Model.new
    @tool.draw(@view)
    assert_equal before, @view.draws.length
    Sketchup.active_model = @model
  end

  def test_overhang_and_outside_zone_refusals_reach_status_and_notice_without_undo
    choose
    before = @model.operations.length
    @picked[:point] = Geom::Point3d.new(0, 0, 1 / 0.0254)
    down
    up
    assert_empty units
    assert_includes @notices.last.first, "leaves its host"
    assert_includes UI.notifications.last.message, "leaves its host", "the refused placement shows in SketchUp"
    @picked[:path] = [Sketchup::Face.new(9999)]
    down
    up
    assert_includes @notices.last.first, "no Zone"
    assert_equal before, @model.operations.length
  end

  # The host read carries Zones' write refusal from the Face's path, so locked storage refuses on hover.
  def test_hover_over_a_locked_zone_refuses_with_zones_code_and_draws_no_preview
    choose
    @group.locked = true
    draws = @view.draws.length
    picked { @tool.onMouseMove(0, 10, 10, @view) }
    @tool.draw(@view)
    assert_equal draws, @view.draws.length
    assert_includes Sketchup.status_texts.last, "locked"
    before = @model.operations.length
    down
    up
    assert_empty units
    assert_equal before, @model.operations.length
  end

  def test_invalid_measurement_cancels_gesture_and_locate_changes_only_view
    choose
    down
    parser({}) { @tool.onUserText("sill=bad", @view) }
    up
    assert_empty units
    down
    up
    before = @model.operations.length
    revision = @session.revision
    reference = units.first.fetch("reference")
    result = API.view(:context => @context, :name => "ph_composer.windows.units.locate",
                      :params => { "units" => [reference, reference.merge("unit_id" => "wun_missing")] })
    assert_equal "completed", result.fetch("status"), result.inspect
    assert_equal [reference], result.fetch("value").fetch("units")
    assert_equal 1, @model.selection.to_a.length
    assert_equal before, @model.operations.length
    assert_equal revision, @session.revision
  end

  def test_selected_face_context_menu_routes_through_public_choose
    @model.active_path = [@group]
    @model.selection.add(@face)
    read = PhComposer::HandlerRequest.for(@session, :owner => W::FEATURE_ID,
                                                    :name => "#{W::FEATURE_ID}.place_tool.face_menu")
    entries = W::ViewportRegistration.type_rows(read.engine)
    assert_equal [@type_id], entries.map { |row| row.fetch("id") }
    assert_equal @host, W::ViewportRegistration.selected_face(read)
    UI.stub(:inputbox, ->(*_args) { ["Place test"] }) { W::ViewportRegistration.choose_from_menu(@session) }
    assert_equal @host, @tool.state.fetch("host")
    assert @tool.active?
    @session.detach
    refute @tool.active?
    up
    assert_empty W::Units::Occurrences.all(@model)
  end

  def test_different_type_mid_gesture_keeps_frozen_type_and_next_hover_uses_new_type
    created = assignment_invoke("ph_composer.windows.types.create",
                                "values" => { "name" => "Other Type", "rows_m" => [1.0], "columns_m" => [0.9] })
    assert_equal "completed", created.fetch("status"), created.inspect
    choose
    down
    choose("type_id" => created.dig("value", "id"), "anchor" => "sill_right")
    up
    assert_equal @type_id, units.first.dig("values", "window_type_id")
    assert_equal "sill_center", units.first.dig("values", "anchor")
    reads = host_reads("Pointer move refreshed semantic reads") do
      picked { @tool.onMouseMove(0, 10, 10, @view) }
      @tool.draw(@view)
    end
    assert_equal 1, reads.length
    assert_equal 8, @view.draws.last[1].length
    assert_equal created.dig("value", "id"), @tool.state.fetch("type_id")
  end

  def test_model_switch_pointer_callback_cancels_gesture_even_when_original_model_returns
    choose
    down
    Sketchup.active_model = Sketchup::Model.new
    picked { @tool.onMouseMove(0, 10, 10, @view) }
    Sketchup.active_model = @model
    before = @model.operations.length
    up
    assert_empty units
    assert_equal before, @model.operations.length
  end

  def test_callback_exception_at_release_notifies_without_creating_operation
    choose
    down
    before = @model.operations.length
    API.stub(:invoke, ->(**_args) { raise "Synthetic dispatch failure" }) { up }
    assert_empty units
    assert_equal before, @model.operations.length
    assert_includes @notices.last.first, "Nothing was written"
    assert_match(/Error: RuntimeError\. Incident PHC-\h{6}\.\z/, UI.notifications.last.message)
    assert_equal :error, @notices.last.last
    refute_includes @notices.last.first, "Synthetic"
  end

  def test_post_commit_refresh_failure_reports_actual_placement
    choose
    down
    API.stub(:query, ->(**_args) { raise "Synthetic read failure" }) { up }
    assert_equal 1, units.length
    assert_includes @notices.last.first, "Placed Window"
    refute_includes @notices.last.first, "Nothing was written"
  end

  def test_stale_hover_withholds_outline_until_next_down_refreshes_faces
    choose
    picked { @tool.onMouseMove(0, 10, 10, @view) }
    @tool.draw(@view)
    before = @view.draws.length
    changed = assignment_invoke("ph_composer.windows.types.update",
                                "id" => @type_id,
                                "values" => { "notes" => "New revision" },
                                "expected_values" => { "notes" => type.fetch("notes") })
    assert_equal "completed", changed.fetch("status"), changed.inspect
    picked { @tool.onMouseMove(0, 10, 10, @view) }
    @tool.draw(@view)
    assert_equal before, @view.draws.length
    down
    up
    assert_equal 1, units.length
  end

  def test_native_menu_refusal_is_visible_and_closed_tool_cannot_restart
    result = W::ViewportRegistration.invoke_choice(@session, "type_id" => "wnt_missing")
    refute_equal "completed", result.fetch("status")
    assert_equal result.fetch("message"), @notices.last.first
    assert_equal result.fetch("message"), Sketchup.status_texts.last
    @session.detach
    assert_raises(PhComposer::CodedError) { @tool.choose(@type_id) }
    assert_empty W::Units::Occurrences.all(@model)
  end

  def test_unreadable_type_refuses_with_its_own_code_not_as_missing
    dictionary = "ph_composer.records.#{W::TYPE_KIND}"
    record = JSON.parse(@model.get_attribute(dictionary, @type_id)).merge("rows_m" => "broken")
    @model.set_attribute(dictionary, @type_id, JSON.generate(record))
    result = API.view(:context => @context, :name => "#{PREFIX}.choose", :params => { "type_id" => @type_id })
    assert_equal %w[refused record.unreadable], result.values_at("status", "code")
  end

  def test_an_unreadable_type_is_skipped_and_leaves_place_window_in_the_context_menu
    readable = assignment_invoke("ph_composer.windows.types.create",
                                 "values" => { "name" => "Readable", "rows_m" => [1.5],
                                               "columns_m" => [0.7] }).fetch("value").fetch("id")
    dictionary = "ph_composer.records.#{W::TYPE_KIND}"
    record = JSON.parse(@model.get_attribute(dictionary, @type_id)).merge("rows_m" => "broken")
    @model.set_attribute(dictionary, @type_id, JSON.generate(record))
    @model.active_path = [@group]
    @model.selection.add(@face)
    menus = PhComposer::Commands.install_feature_menus(UI::Menu.new("Context"), :contextual => true)
    labels = menus.fetch(W::ViewportRegistration::MENU).entries.map(&:first)
    assert_equal ["Place Window…", "Place Readable"], labels
    read = PhComposer::HandlerRequest.for(@session, :owner => W::FEATURE_ID, :name => W::ColourModes::BY_TYPE)
    assert_empty W::ColourModes.entries(read), "the Colour-by mode reads the same Types without raising"
    assert_equal [readable], W::ViewportRegistration.type_rows(read.engine).map { |row| row.fetch("id") }
  end

  def test_the_place_window_chooser_reads_every_page_of_types
    pages = { nil => [{ "id" => "wnt_first", "name" => "First" }, "next"],
              "next" => [{ "id" => "wnt_second", "name" => "Second" }, nil] }
    cursors = []
    page = lambda do |_session, _name, params|
      cursors << params["cursor"]
      row, cursor = pages.fetch(params["cursor"])
      record = { "id" => row.fetch("id"), "values" => { "name" => row.fetch("name") } }
      { "records" => [record], "next_cursor" => cursor }
    end
    choices = W::ViewportRegistration.stub(:query, page) { W::ViewportRegistration.type_choices(@session) }
    assert_equal [[nil, "next"], %w[wnt_first wnt_second]], [cursors, choices.map { |row| row.fetch("id") }]
  end

  def test_native_menu_read_refusal_is_visible_instead_of_doing_nothing
    refused = PhComposer::Outcome.refused("session.busy", "PH-Composer is busy.", :revision => @session.revision)
    API.stub(:query, refused) { W::ViewportRegistration.choose_from_menu(@session) }
    assert_equal ["PH-Composer is busy.", :warning], @notices.last
    refute @tool.active?
  end

  def test_place_snapshot_get_never_issues_a_native_tool_caller
    before = @session.callers.count
    2.times do
      state = assignment_query("#{PREFIX}.get")
      refute state.fetch("active")
      assert_nil state.fetch("type_id")
      assert_equal before, @session.callers.count
    end
    choose
    assert_equal before + 1, @session.callers.count
    choose
    assert_equal before + 1, @session.callers.count
  end

  def test_suspended_stop_then_choose_reactivates_and_places
    choose
    down
    @tool.suspend(@view)
    @tool.stop
    choose
    down
    up
    assert_equal 1, units.length
    assert @tool.active?
  end

  def test_stop_and_fresh_activation_clear_measurements_but_active_choose_keeps_them
    choose
    parser("1m" => 1 / 0.0254) { @tool.onUserText("sill=1m", @view) }
    choose("anchor" => "sill_left")
    @picked[:point] = Geom::Point3d.new(2 / 0.0254, 0, 3 / 0.0254)
    down
    up
    assert_in_delta 1, anchor_point(units.first).last, 1e-12
    @tool.stop
    choose("anchor" => "sill_right")
    @picked[:point] = Geom::Point3d.new(5 / 0.0254, 0, 3 / 0.0254)
    down
    up
    row = units.find { |unit| unit.dig("values", "anchor") == "sill_right" }
    assert_in_delta 3, anchor_point(row).last, 1e-12
  end

  def test_lost_release_detected_by_unpressed_move_prevents_orphan_mouse_up
    choose
    down
    picked { @tool.onMouseMove(0, 20, 20, @view) }
    before = @model.operations.length
    up
    assert_empty units
    assert_equal before, @model.operations.length
  end

  def test_shared_nested_leaf_locate_selects_and_zooms_the_requested_root_occurrence
    choose
    down
    up
    first = units.first.fetch("reference")
    shared_group = Sketchup::Group.new(3000, @group.entities)
    shared_group.transformation = Geom::Transformation.translation([1000, 200, 0])
    @model.entities << shared_group
    second = first.merge("entity_path" => [3000, first.fetch("entity_path").last])
    all = W::Units::Occurrences.all(@model)
    assert_same all[0].entity, all[1].entity
    refute_equal all[0].transform.to_a, all[1].transform.to_a
    before = @model.operations.length
    revision = @session.revision
    [first, second].zip([@group, shared_group]).each do |reference, ancestor|
      result = API.view(:context => @context, :name => "ph_composer.windows.units.locate",
                        :params => { "units" => [reference] })
      assert_equal "completed", result.fetch("status"), result.inspect
      assert_equal [reference], result.dig("value", "units")
      assert_equal [ancestor], @model.selection.to_a
      assert_equal [ancestor], @view.zoomed.last
    end
    assert_nil @model.active_path
    assert_equal before, @model.operations.length
    assert_equal revision, @session.revision
  end

  def test_locate_uses_unit_in_matching_edit_context_and_root_ancestor_for_other_branch
    choose
    down
    up
    reference = units.first.fetch("reference")
    unit = W::Units::Occurrences.resolve(@model, reference).entity
    shared_group = Sketchup::Group.new(3000, @group.entities)
    shared_group.transformation = Geom::Transformation.translation([1000, 0, 0])
    @model.entities << shared_group
    @model.active_path = [@group]
    own = W::Units::Locate.call(@model, [reference])
    assert_equal [reference], own.fetch("units")
    assert_equal [unit], @model.selection.to_a
    assert_equal [unit], @view.zoomed.last
    other = reference.merge("entity_path" => [3000, reference.fetch("entity_path").last])
    result = W::Units::Locate.call(@model, [other])
    assert_equal [other], result.fetch("units")
    assert_empty @model.selection.to_a
    assert_equal [shared_group], @view.zoomed.last
    assert_equal [@group], @model.active_path
  end
end
