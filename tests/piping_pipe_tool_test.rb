# frozen_string_literal: true

require_relative "test_helper"

# The pipe tool, the gesture rather than the operation: what a click and a drag assign, the type, role and values
# frozen at button-down, every cancel route writing nothing, the gesture limit, the refusals a pick meets, the
# Colour-by mode it holds while it runs, and its view commands and menu items.
class PipingPipeToolTest < PhComposerTestCase
  API = PhComposer::API
  P = PhComposer::Piping
  STORE = P::Assignment::STORE
  PREFIX = "ph_composer.piping"
  TOOL = "#{PREFIX}.pipe_tool".freeze

  def setup
    super
    @model = Sketchup.active_model
    @session = PhComposer::Sessions.for(@model)
    @context = API.connect(:session_id => @session.id)
    @notices = []
    PhComposer::Sessions.on_notice { |_session, message, tone| @notices << [message, tone] }
    @view = @model.active_view
    @sequence = 0
    @hws = invoke("ph_composer.mechanical.hot_water_systems.create", "values" => { "name" => "HWS-1" })
           .dig("value", "id")
    @pex = invoke("#{PREFIX}.pipe_types.create", "values" => { "name" => "PEX" }).dig("value", "id")
    @copper = invoke("#{PREFIX}.pipe_types.create", "values" => { "name" => "Copper" }).dig("value", "id")
    fixture
  end

  # Piping group 600 at the root holds Edges 601 to 603; Edge 5 is at the Model root.
  def fixture
    @edges = [601, 602, 603].map { |id| edge(id) }
    @group = Sketchup::Group.new(600, Sketchup::Entities.new(@edges))
    P::Group::STORE.write(@group, P::Group.new_record("ppg_AAAAAAAAAAAA", @hws))
    @model.entities << @group << (@loose = edge(5))
  end

  def test_one_drag_assigns_every_edge_it_crossed_in_one_step_with_the_values_frozen_at_button_down
    tool.choose(@pex, "trunk", "multiplier" => 12)
    @edges.each_with_index { |entity, index| point(index, [@group, entity]) }
    operations = @model.operations.length
    press(0)
    tool.choose(@copper, "branch") # a new choice mid-drag
    move(1)
    move(2)
    move(1) # crossing an Edge twice takes it once
    release

    assert_equal [[@pex, "trunk", 12]] * 3, @edges.map { |entity| values(entity) }
    assert_equal operations + 1, @model.operations.length, "one gesture, one Undo step"
    assert_equal "Assigned PEX as trunk to 3 Edges.", Sketchup.status_texts.last
    assert_equal ["Assigned PEX as trunk to 3 Edges.", :success], @notices.last
    assert tool.active?, "the tool stays armed with the new choice for the next gesture"
    assert_equal({ "active" => true, "pipe_type_id" => @copper, "role" => "branch", "values" => {} }, tool.state)
    click(0)
    assert_equal [@copper, "branch", nil], values(@edges[0]), "a click reassigns, dropping the trunk's values"
  end

  # The tool picks with the wider line aperture, on hover and on press; the stub only records what it asked for.
  def test_the_tool_picks_lines_with_the_line_aperture
    tool.choose(@pex, "trunk")
    point(0, [@group, @edges[0]])
    @view.apertures = []
    move(0)
    click(0)
    assert_equal [PhComposer::Pick::LINE_APERTURE], @view.apertures.uniq
    assert_equal [@pex, "trunk"], values(@edges[0]).first(2)
  end

  def test_the_armed_values_are_the_tools_own_copy
    chosen = { "multiplier" => 12 }
    tool.choose(@pex, "trunk", chosen)
    chosen["multiplier"] = 3
    tool.state.fetch("values")["multiplier"] = 4
    point(:a, [@group, @edges[0]])
    click(:a)
    assert_equal [@pex, "trunk", 12], values(@edges[0])
  end

  def test_escape_suspension_and_a_move_without_the_button_each_write_nothing
    @edges.each_with_index { |entity, index| point(index, [@group, entity]) }
    tool.choose(@pex, "twig")
    operations = @model.operations.length
    [-> { tool.onCancel(0, @view) }, -> { tool.suspend(@view) },
     -> { tool.onMouseMove(0, *@coordinates.fetch(1), @view) }].each do |cancel|
      tool.choose(@pex, "twig")
      press(0)
      cancel.call
      move(1)
      release
    end
    assert_equal operations, @model.operations.length
    assert_equal [nil] * 3, @edges.map { |entity| STORE.read(entity) }
    assert_match(/cancelled\. Nothing was written\.\z/, Sketchup.status_texts.last)
    tool.onCancel(0, @view)
    refute tool.active?, "Escape ends the tool"
  end

  def test_any_other_cancel_deactivation_and_an_edit_path_change_take_only_the_gesture
    point(:a, [@group, @edges[0]])
    tool.choose(@pex, "branch")
    [-> { tool.onCancel(2, @view) }, -> { @model.active_path = [@group] }].each do |cancel|
      press(:a)
      cancel.call
      release
      assert tool.active?, "the tool stays armed"
      assert_nil STORE.read(@edges[0])
      @model.active_path = nil
    end
    press(:a)
    tool.deactivate(@view)
    release
    assert_nil STORE.read(@edges[0])
    assert_match(/cancelled\. Nothing was written\.\z/, Sketchup.status_texts.last)
  end

  def test_choosing_a_missing_type_refuses_and_stop_leaves_another_tool_running
    result = API.view(:context => @context, :name => "#{TOOL}.choose",
                      :params => { "pipe_type_id" => "ppt_ZZZZZZZZZZZZ", "role" => "twig" })
    assert_equal %w[refused target.not_found], result.values_at("status", "code")
    refute tool.active?
    assert_nil tool.pipe_type_id
    tool.choose(@pex, "twig")
    classify = PhComposer::Zones::Faces.classify_tool(@session).start
    API.view(:context => @context, :name => "#{TOOL}.stop", :params => {})
    assert classify.active?
  end

  def test_one_edge_more_than_the_limit_refuses_the_whole_gesture
    P::Assignment.gesture_edge_limit = 2
    tool.choose(@pex, "branch")
    @edges.each_with_index { |entity, index| point(index, [@group, entity]) }
    operations = @model.operations.length
    press(0)
    move(1)
    move(2)
    release
    assert_equal operations, @model.operations.length
    assert_equal [nil] * 3, @edges.map { |entity| STORE.read(entity) }
    assert_match(/at most 2 Edges/, Sketchup.status_texts.last)
    assert_equal :warning, @notices.last.last
  end

  def test_an_edge_outside_a_piping_group_refuses_at_the_pointer_and_the_whole_gesture
    tool.choose(@pex, "branch")
    point(:root, [@loose])
    point(:a, [@group, @edges[0]])
    tool.onMouseMove(0, *@coordinates.fetch(:root), @view)
    assert_equal P::PipeTool::OUTSIDE, @view.tooltip
    press(:a)
    move(:root)
    release
    assert_nil STORE.read(@edges[0])
    assert_equal "#{P::PipeTool::OUTSIDE} #{PhComposer::Outcome::NOTHING_WRITTEN}", Sketchup.status_texts.last
  end

  def test_a_recirculation_choice_writes_its_values_and_a_deleted_type_refuses_at_button_down
    tool.choose(@copper, "recirculation", "water_temp_c" => 55.0, "daily_period" => 18)
    point(:a, [@group, @edges[0]])
    click(:a)
    assert_equal({ "water_temp_c" => 55.0, "daily_period" => 18 },
                 STORE.read(@edges[0]).slice("water_temp_c", "daily_period"))
    invoke("#{PREFIX}.pipe_types.delete", "id" => @pex)
    tool.choose(@copper, "twig")
    tool.instance_variable_set(:@pipe_type_id, @pex)
    point(:b, [@group, @edges[1]])
    click(:b)
    assert_nil STORE.read(@edges[1])
    assert_match(/no longer exists/, Sketchup.status_texts.last)
  end

  def test_choose_and_stop_through_the_view_commands_hold_colour_by_pipe_role_and_refuse_another_roles_values
    service = PhComposer::ColourBy.for(@session)
    result = API.view(:context => @context, :name => "#{TOOL}.choose",
                      :params => { "pipe_type_id" => @pex, "role" => "trunk", "multiplier" => 4 })
    assert_equal "completed", result.fetch("status"), result.inspect
    assert_equal({ "active" => true, "pipe_type_id" => @pex, "role" => "trunk", "values" => { "multiplier" => 4 },
                   "gesture_limit" => 250 }, result.fetch("value"))
    assert_equal P::ColourModes::BY_ROLE, service.mode_name
    assert_equal result.fetch("value"), API.query(:context => @context, :name => "#{TOOL}.state").fetch("value")
    refused = API.view(:context => @context, :name => "#{TOOL}.choose",
                       :params => { "pipe_type_id" => @pex, "role" => "branch", "multiplier" => 4 })
    assert_equal %w[refused params.invalid], refused.values_at("status", "code")
    API.view(:context => @context, :name => "#{TOOL}.stop", :params => {})
    refute tool.active?
    refute service.active?, "the mode from before the tool, none, is back"
    service.activate(PhComposer::Zones::ColourModes::BY_ZONE)
    tool.choose(@pex, "twig")
    tool.stop
    assert_equal PhComposer::Zones::ColourModes::BY_ZONE, service.mode_name, "a mode chosen before comes back"
  end

  def test_the_menu_rearms_with_the_last_choice_and_stops_only_while_the_tool_runs
    items = PhComposer::Registry.current.menu_items
    arm = items.fetch("#{TOOL}.arm_menu")
    stop = items.fetch("#{TOOL}.stop_menu")
    refute arm.available.call(read(arm)), "nothing to arm with before the bar has armed it"
    tool.choose(@copper, "twig")
    assert stop.available.call(read(stop))
    stop.handler.call(@session)
    refute tool.active?
    assert arm.available.call(read(arm))
    arm.handler.call(@session)
    assert_equal({ "active" => true, "pipe_type_id" => @copper, "role" => "twig", "values" => {} }, tool.state)
  end

  def test_detach_with_the_tool_active_leaves_no_tool
    tool.choose(@pex, "branch")
    @session.detach
    refute tool.active?
    assert_nil @model.active_tool
  end

  private

  def tool
    P.pipe_tool(@session)
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
    STORE.read(entity)&.values_at("pipe_type_id", "role", "multiplier")
  end

  def read(declaration)
    PhComposer::HandlerRequest.for(@session, :owner => declaration.owner, :name => declaration.name)
  end

  def invoke(name, params)
    @sequence += 1
    API.invoke(:context => @context, :name => name, :params => params,
               :request => { "sequence" => 1000 + @sequence, "expected_revision" => @session.revision })
  end

  def edge(id)
    Sketchup::Edge.new(id, Geom::Point3d.new(0, 0, 0), Geom::Point3d.new(100, id, 0))
  end
end
