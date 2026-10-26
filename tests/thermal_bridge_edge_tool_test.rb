# frozen_string_literal: true

require_relative "test_helper"

# The edge tool, the gesture rather than the operation: what a click and a drag assign, the type and quantity
# frozen at button-down, every cancel route writing nothing, the gesture limit, the refusals a pick meets, the
# Colour-by mode it holds while it runs, and its view commands and menu items.
class ThermalBridgeEdgeToolTest < PhComposerTestCase
  API = PhComposer::API
  TB = PhComposer::ThermalBridges
  STORE = TB::Assignment::STORE
  TOOL = "#{TB::FEATURE_ID}.edge_tool".freeze

  def setup
    super
    PhComposer.compose unless PhComposer::Registry.installed?(TB::FEATURE_ID)
    @model = Sketchup.active_model
    @session = PhComposer::Sessions.for(@model)
    @context = API.connect(:session_id => @session.id)
    @notices = []
    PhComposer::Sessions.on_notice { |_session, message, tone| @notices << [message, tone] }
    @view = @model.active_view
    @sequence = 0
    fixture
    @parapet = create_type("Parapet")
    @slab = create_type("Slab edge")
  end

  # Zone A (100) holds Edges 101 to 103 and a component placement (140), as a Window Unit is, whose definition
  # holds Edge 141. Zone B (200) holds Edge 201. Edge 5 is at the Model root.
  def fixture
    @edges = [101, 102, 103].map { |id| edge(id) }
    definition = Sketchup::ComponentDefinition.new(Sketchup::Entities.new([@unit_edge = edge(141)]))
    @unit = Sketchup::ComponentInstance.new(140, definition)
    @zone_a = zone("zon_AAAAAAAAAAAA", 100, @edges + [@unit])
    @zone_b = zone("zon_BBBBBBBBBBBB", 200, [@b_edge = edge(201)])
    @model.entities << @zone_a << @zone_b << (@loose = edge(5))
  end

  def test_one_drag_assigns_every_edge_it_crossed_in_one_step_with_the_type_frozen_at_button_down
    tool.choose(@parapet, :quantity => 2)
    point(:a, [@zone_a, @edges[0]])
    point(:b, [@zone_a, @edges[1]])
    point(:c, [@zone_b, @b_edge])
    operations = @model.operations.length
    press(:a)
    tool.choose(@slab, :quantity => 1) # a new type mid-drag
    move(:b)
    move(:c)
    move(:b) # crossing an Edge twice takes it once
    release

    assert_equal [[@parapet, 2]] * 3, (@edges[0, 2] + [@b_edge]).map { |entity| values(entity) }
    assert_equal operations + 1, @model.operations.length, "one gesture, one Undo step"
    assert_equal "Assigned Parapet to 3 Edges.", Sketchup.status_texts.last
    assert_equal ["Assigned Parapet to 3 Edges.", :success], @notices.last
    assert tool.active?, "the tool stays armed with the new type for the next gesture"
    assert_equal({ "active" => true, "thermal_bridge_type_id" => @slab, "quantity" => 1 }, tool.state)
  end

  def test_a_click_reassigns_an_assigned_edge
    tool.choose(@parapet)
    point(:a, [@zone_a, @edges[0]])
    click(:a)
    tool.choose(@slab)
    click(:a)
    assert_equal [@slab, 1], values(@edges[0])
    assert_equal "Assigned Slab edge to 1 Edge.", Sketchup.status_texts.last
  end

  def test_escape_deactivation_suspension_and_a_raised_callback_each_write_nothing
    point(:a, [@zone_a, @edges[0]])
    tool.choose(@parapet)
    operations = @model.operations.length
    [-> { tool.onCancel(0, @view) }, -> { tool.deactivate(@view) }, -> { tool.suspend(@view) }].each do |cancel|
      tool.choose(@parapet)
      press(:a)
      cancel.call
      release
    end
    assert_match(/cancelled\. Nothing was written\.\z/, Sketchup.status_texts.last)
    tool.choose(@parapet)
    press(:a)
    @view.picks[[99, 99]] = :raise
    tool.onMouseMove(MK_LBUTTON, 99, 99, @view)
    release
    assert_equal operations, @model.operations.length
    assert_nil STORE.read(@edges[0])
    assert_match(/could not complete that\. Nothing was written\.\z/, Sketchup.status_texts.last)
  end

  def test_escape_stops_the_tool_and_any_other_cancel_takes_only_the_gesture
    tool.choose(@parapet)
    point(:a, [@zone_a, @edges[0]])
    press(:a)
    tool.onCancel(2, @view)
    release
    assert tool.active?
    assert_nil STORE.read(@edges[0])
    tool.onCancel(0, @view)
    refute tool.active?
    assert_nil @model.active_tool
  end

  def test_a_release_after_the_edit_path_changed_writes_nothing
    tool.choose(@parapet)
    point(:a, [@zone_a, @edges[0]])
    press(:a)
    @model.active_path = [@zone_a]
    release
    assert_nil STORE.read(@edges[0])
    refute tool.send(:collecting?)
  end

  def test_the_collected_edges_keep_the_colour_of_the_type_the_drag_will_write
    updated = invoke("types.update", "id" => @slab, "values" => { "color" => "#112233" }, "expected_values" => {})
    assert_equal "completed", updated.fetch("status"), updated.inspect
    tool.choose(@parapet)
    point(:a, [@zone_a, @edges[0]])
    press(:a)
    tool.choose(@slab)
    @view.draws.clear
    tool.draw(@view)
    drawn = @view.draws.last[2]
    assert_equal TB::ColourModes.rgb(type_row(@parapet).dig("display", "color")), [drawn.red, drawn.green, drawn.blue]
    release
    assert_equal [@parapet, 1], values(@edges[0])
  end

  def test_a_move_over_nothing_clears_the_tooltip
    tool.choose(@parapet)
    tool.onMouseMove(0, 5, 5, @view)
    assert_equal "", @view.tooltip
  end

  def test_a_move_without_the_button_after_a_lost_release_stops_collecting
    tool.choose(@parapet)
    point(:a, [@zone_a, @edges[0]])
    point(:b, [@zone_a, @edges[1]])
    operations = @model.operations.length
    press(:a)
    tool.onMouseMove(0, *@coordinates.fetch(:b), @view) # the button is up: its release never arrived
    move(:b)
    release
    assert_equal operations, @model.operations.length
    assert_equal [nil, nil], @edges[0, 2].map { |entity| STORE.read(entity) }
  end

  def test_one_edge_more_than_the_limit_refuses_the_whole_gesture
    TB::Assignment.gesture_edge_limit = 2
    tool.choose(@parapet)
    @edges.each_with_index { |entity, index| point(index, [@zone_a, entity]) }
    operations = @model.operations.length
    press(0)
    move(1)
    move(2)
    release
    assert_equal operations, @model.operations.length
    assert_equal [nil] * 3, @edges.map { |entity| STORE.read(entity) }
    assert_match(/at most 2 Edges/, Sketchup.status_texts.last)
    assert_equal :warning, @notices.last.last

    TB::Assignment.gesture_edge_limit = 3
    press(0)
    move(1)
    move(2)
    release
    assert_equal [[@parapet, 1]] * 3, @edges.map { |entity| values(entity) }
  end

  def test_an_edge_at_the_model_root_and_one_in_a_window_unit_refuse_at_the_status_bar_and_the_notice
    tool.choose(@parapet)
    point(:root, [@loose])
    point(:unit, [@zone_a, @unit, @unit_edge])
    point(:a, [@zone_a, @edges[0]])
    operations = @model.operations.length
    click(:root)
    assert_equal "That Edge cannot take a thermal bridge: it is not inside a Zone. Nothing was written.",
                 Sketchup.status_texts.last
    assert_equal :warning, @notices.last.last
    click(:unit)
    assert_equal "That Edge is inside shared component storage. Nothing was written.", @notices.last.first

    # A drag that crosses one refuses whole.
    press(:a)
    move(:unit)
    release
    assert_equal operations, @model.operations.length
    assert_nil STORE.read(@edges[0])
  end

  def test_a_commit_between_press_and_release_refuses_the_gesture_as_stale
    tool.choose(@parapet)
    point(:a, [@zone_a, @edges[0]])
    press(:a)
    create_type("Corner")
    operations = @model.operations.length
    release
    assert_equal operations, @model.operations.length
    assert_nil STORE.read(@edges[0])
    assert_match(/changed|stale/i, Sketchup.status_texts.last)
  end

  def test_a_release_after_a_model_switch_writes_nothing
    tool.choose(@parapet)
    point(:a, [@zone_a, @edges[0]])
    press(:a)
    Sketchup.active_model = Sketchup::Model.new
    tool.onLButtonUp(0, 0, 0, @view)
    assert_nil STORE.read(@edges[0])
    refute tool.send(:collecting?)
  ensure
    Sketchup.active_model = @model
  end

  def test_a_deleted_type_refuses_at_button_down
    tool.choose(@parapet)
    invoke("types.delete", "id" => @parapet, "replacement_id" => nil)
    point(:a, [@zone_a, @edges[0]])
    click(:a)
    assert_nil STORE.read(@edges[0])
    assert_match(/no longer exists.*Nothing was written\.\z/, Sketchup.status_texts.last)
  end

  def test_hovering_reads_each_pick_from_its_path_without_walking_the_model
    walks = 0
    original = TB::Scan.method(:walk)
    TB::Scan.define_singleton_method(:walk) do |*args, **options|
      walks += 1
      original.call(*args, **options)
    end
    tool.choose(@parapet) # its Colour-by mode reads the Model once
    walks = 0
    point(:a, [@zone_a, @edges[0]])
    3.times { tool.onMouseMove(0, *@coordinates.fetch(:a), @view) }
    assert_equal 0, walks
    assert_equal "Assign Parapet", @view.tooltip
  ensure
    TB::Scan.define_singleton_method(:walk, original)
  end

  def test_the_hovered_edge_draws_heavy_in_the_type_colour_and_a_refused_one_in_red
    tool.choose(@parapet)
    colour = TB::ColourModes.rgb(type_row(@parapet).dig("display", "color"))
    point(:a, [@zone_a, @edges[0]])
    point(:root, [@loose])
    tool.onMouseMove(0, *@coordinates.fetch(:a), @view)
    @view.draws.clear
    tool.draw(@view)
    mode, points, drawn, width = @view.draws.last
    assert_equal [GL_LINES, 2, TB::EdgeTool::WIDTH], [mode, points.length, width]
    assert_equal colour, [drawn.red, drawn.green, drawn.blue]

    tool.onMouseMove(0, *@coordinates.fetch(:root), @view)
    @view.draws.clear
    tool.draw(@view)
    drawn = @view.draws.last[2]
    assert_equal TB::EdgeTool::REFUSED_COLOUR, [drawn.red, drawn.green, drawn.blue]
    assert_match(/not inside a Zone/, @view.tooltip)
  end

  def test_choosing_turns_the_type_mode_on_and_stopping_puts_back_the_mode_before
    service = PhComposer::ColourBy.for(@session)
    service.activate(PhComposer::Zones::ColourModes::BY_ZONE)
    result = API.view(:context => @context, :name => "#{TOOL}.choose",
                      :params => { "thermal_bridge_type_id" => @parapet, "quantity" => 2 })
    assert_equal "completed", result.fetch("status"), result.inspect
    assert_equal({ "active" => true, "thermal_bridge_type_id" => @parapet, "quantity" => 2, "gesture_limit" => 250 },
                 result.fetch("value"))
    assert_equal TB::ColourModes::BY_TYPE, service.mode_name
    assert_equal result.fetch("value"),
                 API.query(:context => @context, :name => "#{TOOL}.state").fetch("value")

    API.view(:context => @context, :name => "#{TOOL}.stop", :params => {})
    refute tool.active?
    assert_equal PhComposer::Zones::ColourModes::BY_ZONE, service.mode_name
  end

  def test_choosing_a_missing_type_refuses_and_leaves_the_tool_unarmed
    result = API.view(:context => @context, :name => "#{TOOL}.choose",
                      :params => { "thermal_bridge_type_id" => "tbt_ZZZZZZZZZZZZ" })
    assert_equal ["refused", "target.not_found"], result.values_at("status", "code")
    refute tool.active?
    assert_nil tool.thermal_bridge_type_id
  end

  def test_stop_leaves_another_tool_running
    tool.choose(@parapet)
    classify = PhComposer::Zones::Faces.classify_tool(@session).start
    API.view(:context => @context, :name => "#{TOOL}.stop", :params => {})
    assert classify.active?
  end

  def test_the_menu_offers_arming_with_a_type_and_stop_only_while_the_tool_runs
    items = PhComposer::Registry.current.menu_items
    arm = items.fetch("#{TOOL}.arm_menu")
    stop = items.fetch("#{TOOL}.stop_menu")
    assert_equal [TB::MenuRegistration::MENU] * 2, [arm.menu, stop.menu]
    refute arm.available.call(read(arm)), "not on a right-click with no assignable Edge selected"
    @model.active_path = [@zone_a]
    @model.selection.add([@edges[0]])
    assert arm.available.call(read(arm))
    refute stop.available.call(read(stop))
    entries = items.fetch("#{TB::FEATURE_ID}.assign_menu").entries.call(read(arm))
    assert entries.last.separator_after, "the types are set apart from Assign by clicking"
    @model.selection.clear
    @model.active_path = nil

    UI.inputbox_result = ["Slab edge", "2"]
    arm.handler.call(@session)
    assert_equal({ "active" => true, "thermal_bridge_type_id" => @slab, "quantity" => 2.0 }, tool.state)
    assert stop.available.call(read(stop))
    stop.handler.call(@session)
    refute tool.active?

    piped = create_type("Wall | Roof")
    UI.inputbox_result = ["Wall / Roof", "1"]
    arm.handler.call(@session)
    assert_equal piped, tool.thermal_bridge_type_id, "a name holding the choice separator stays selectable"
    stop.handler.call(@session)

    ["none", "0x1A", "1e999"].each do |typed|
      UI.inputbox_result = ["Slab edge", typed]
      arm.handler.call(@session)
      refute tool.active?, typed
      assert_equal :warning, @notices.last.last
    end
  end

  def test_detach_with_the_tool_active_leaves_no_tool
    tool.choose(@parapet)
    @session.detach
    refute tool.active?
    assert_nil @model.active_tool
  end

  private

  def tool
    TB.edge_tool(@session)
  end

  def point(name, entities)
    @coordinates ||= {}
    @coordinates[name] ||= [100 + @coordinates.length, 100]
    @view.picks[@coordinates[name]] = entities
  end

  def press(name)
    tool.onLButtonDown(0, *@coordinates.fetch(name), @view)
  end

  def move(name)
    tool.onMouseMove(MK_LBUTTON, *@coordinates.fetch(name), @view)
  end

  def release
    tool.onLButtonUp(0, 0, 0, @view)
  end

  def click(name)
    press(name)
    release
  end

  def values(entity)
    STORE.read(entity)&.values_at("thermal_bridge_type_id", "quantity")
  end

  def type_row(id)
    API.query(:context => @context, :name => "#{TB::FEATURE_ID}.types.list", :params => { "ids" => [id] })
       .dig("value", "records").first
  end

  def read(declaration)
    PhComposer::HandlerRequest.for(@session, :owner => declaration.owner, :name => declaration.name)
  end

  def create_type(name)
    invoke("types.create", "values" => { "name" => name, "psi_w_mk" => 0.1 }).dig("value", "id")
  end

  def invoke(name, params)
    @sequence += 1
    API.invoke(:context => @context, :name => "#{TB::FEATURE_ID}.#{name}", :params => params,
               :request => { "sequence" => 1000 + @sequence, "expected_revision" => @session.revision })
  end

  def edge(id)
    Sketchup::Edge.new(id, Geom::Point3d.new(0, 0, 0), Geom::Point3d.new(100, id, 0))
  end

  def zone(id, persistent_id, children)
    group = Sketchup::Group.new(persistent_id, Sketchup::Entities.new(children))
    PhComposer::Zones::ZONE_STORE.write(group,
                                        "id" => id, "schema_version" => 1, "name" => "Zone #{persistent_id}",
                                        "building_segment" => "Building", "level" => nil, "ground_depth_mm" => 0.0,
                                        "user_data" => {}, "extension_data" => {})
    group
  end
end
