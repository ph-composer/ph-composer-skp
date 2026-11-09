# frozen_string_literal: true

require_relative "test_helper"
require_relative "support/space_fixtures"

# The Set height tool, the gesture rather than the operation: what a drag and a typed value write, one Undo step
# each, every ending that writes nothing, and what the pointer can pick. Then Edit outline, the menu item.
class SpacesSetHeightToolTest < PhComposerTestCase
  include SpaceFixtures

  API = PhComposer::API
  KEY = "avg_ceiling_height_m"
  TOOL = PhComposer::Spaces::SetHeightTool
  PICK = PhComposer::Spaces::PrismPick
  # The Living Volume: a 3 m by 4 m floor at the origin, 2.5 m high.
  FROM_ABOVE = [[1.0, 1.0, 20.0], [0.0, 0.0, -1.0]].freeze

  def setup
    super
    @model = Sketchup.active_model
    @session = PhComposer::Sessions.for(@model)
    @context = API.connect(:session_id => @session.id)
    @view = @model.active_view
    @rays = {}
    rays = @rays
    @view.define_singleton_method(:pickray) { |x, y| rays.fetch([x, y]) }
    reference_model
    tool.start
  end

  def tool
    PhComposer::Spaces.set_height_tool(@session)
  end

  def zone
    @model.entities.to_a.first
  end

  def space
    zone.entities.to_a.first
  end

  def volume
    space.entities.to_a.first
  end

  def height
    PhComposer::Spaces::VOLUME_STORE.read(volume)[KEY]
  end

  # Aims the pointer at (x, y): a ray in metres, handed over in inches as the host does.
  def aim(x, y, origin, direction)
    @rays[[x, y]] = [Geom::Point3d.new(*origin.map { |value| value * INCHES }), Geom::Vector3d.new(*direction)]
    [x, y]
  end

  # A horizontal look at the south side of the prism, at `z` metres.
  def side_on(x, z)
    aim(x, 0, [1.0, -10.0, z], [0.0, 1.0, 0.0])
  end

  def press(point)
    tool.onLButtonDown(0, point[0], point[1], @view)
  end

  def drag_to(point)
    tool.onMouseMove(MK_LBUTTON, point[0], point[1], @view)
  end

  def release
    tool.onLButtonUp(0, 0, 0, @view)
  end

  def typed(values, text)
    Sketchup.define_singleton_method(:parse_length) { |entry| values.fetch(entry, nil) }
    tool.onUserText(text, @view)
  ensure
    Sketchup.singleton_class.remove_method(:parse_length)
  end

  def test_a_drag_sets_the_height_the_pointer_shows_in_one_undo_step_with_the_last_height
    press(side_on(0, 1.0))
    operations = @model.operations.length
    drag_to(side_on(100, 1.5))
    release

    assert_in_delta 3.0, height, 1e-9
    assert_equal operations + 1, @model.operations.length
    assert_in_delta 3.0, PhComposer::Spaces::Settings.read(@model).fetch("last_height_m"), 1e-9, "in the same step"
    assert_match(/Height set to/, Sketchup.status_texts.last)
  end

  def test_the_top_follows_the_pointer_from_where_it_was_grabbed
    press(side_on(0, 2.0))
    drag_to(side_on(100, 0.25))
    release
    assert_in_delta 0.75, height, 1e-9, "1.75 m down from a 2.5 m top"
  end

  def test_a_drag_lands_on_the_millimetre
    press(side_on(0, 1.0))
    drag_to(side_on(100, 1.23456))
    release
    assert_in_delta 2.735, height, 1e-12
  end

  def test_a_press_released_in_place_writes_nothing_and_a_typed_height_is_one_undo_step
    press(aim(0, 0, *FROM_ABOVE))
    operations = @model.operations.length
    release
    assert_equal operations, @model.operations.length, "a click only picks"

    typed({ "3.2m" => 3.2 * INCHES }, "3.2m")
    assert_in_delta 3.2, height, 1e-9
    assert_equal operations + 1, @model.operations.length

    typed({ "2.8m" => 2.8 * INCHES }, "2.8m")
    assert_in_delta 2.8, height, 1e-9, "the Volume stays picked, against its own new value"
  end

  def test_typing_refuses_with_nothing_picked_or_an_entry_that_is_no_height
    operations = @model.operations.length
    typed({ "3m" => 3 * INCHES }, "3m")
    assert_match(/Click a Space's prism first/, Sketchup.status_texts.last)

    press(aim(0, 0, *FROM_ABOVE))
    release
    typed({}, "tall")
    assert_match(/Type a height above zero/, Sketchup.status_texts.last)
    typed({ "0" => 0.0 }, "0")
    assert_match(/Type a height above zero/, Sketchup.status_texts.last)
    assert_equal operations, @model.operations.length
    assert_in_delta 2.5, height, 1e-9
  end

  def test_every_cancel_route_writes_nothing
    start = side_on(0, 1.0)
    away = side_on(100, 2.0)
    operations = @model.operations.length
    [-> { tool.onCancel(0, @view) }, -> { tool.deactivate(@view) }, -> { tool.suspend(@view) },
     -> { tool.onMouseMove(0, away[0], away[1], @view) }].each do |cancel|
      tool.start
      press(start)
      drag_to(away)
      cancel.call
      release
    end
    tool.start
    press(start)
    @rays.delete(away)
    assert_raises_nothing_and_writes_nothing { drag_to(away) }
    release
    assert_equal operations, @model.operations.length
    assert_in_delta 2.5, height, 1e-9
  end

  def assert_raises_nothing_and_writes_nothing
    yield
    assert_match(/could not complete that/, Sketchup.status_texts.last)
  end

  def test_a_drag_refuses_against_a_change_made_under_it
    press(side_on(0, 1.0))
    drag_to(side_on(100, 1.5))
    edited = API.invoke(:context => @context, :name => "ph_composer.spaces.update",
                        :params => { "reference" => { "volume_id" => "vol_BBBBBBBBBBBB",
                                                      "entity_path" => [1000, 1200, 1210] },
                                     "values" => { KEY => 2.6 }, "expected_values" => { KEY => 2.4 } },
                        :request => { "sequence" => 1, "expected_revision" => @session.revision })
    assert_equal "completed", edited.fetch("status")
    operations = @model.operations.length
    release
    assert_in_delta 2.5, height, 1e-9, "another Volume's edit moved the revision the drag froze"
    assert_equal operations, @model.operations.length
    refute_match(/Height set/, Sketchup.status_texts.last)
  end

  def test_the_measurements_box_shows_the_height_in_model_units_as_it_drags
    shown = []
    Sketchup.define_singleton_method(:vcb_label=) { |_text| nil }
    Sketchup.define_singleton_method(:vcb_value=) { |text| shown << text }
    Sketchup.define_singleton_method(:format_length) { |inches| format("%.1fin", inches) }
    press(side_on(0, 1.0))
    drag_to(side_on(100, 1.5))
    assert_equal ["#{(2.5 * INCHES).round(1)}in", "#{(3.0 * INCHES).round(1)}in"], shown
  ensure
    %i[vcb_label= vcb_value= format_length].each { |name| Sketchup.singleton_class.remove_method(name) }
  end

  def test_a_drag_to_the_floor_or_below_refuses
    press(side_on(0, 1.0))
    operations = @model.operations.length
    drag_to(side_on(100, -3.0))
    release
    assert_equal operations, @model.operations.length
    assert_match(/above its floor/, Sketchup.status_texts.last)
  end

  def test_a_press_on_nothing_picks_nothing
    press(aim(0, 0, [50.0, 50.0, 20.0], [0.0, 0.0, -1.0]))
    release
    typed({ "3m" => 3 * INCHES }, "3m")
    assert_match(/Click a Space's prism first/, Sketchup.status_texts.last)
  end

  def test_a_volume_with_no_height_is_picked_on_its_floor_and_given_one
    store = PhComposer::Spaces::VOLUME_STORE
    store.write(volume, store.read(volume).reject { |key, _| key == KEY })
    press(aim(0, 0, *FROM_ABOVE))
    release
    typed({ "2.4m" => 2.4 * INCHES }, "2.4m")
    assert_in_delta 2.4, height, 1e-9
  end

  def test_a_hidden_volume_cannot_be_picked
    space.hidden = true
    press(aim(0, 0, *FROM_ABOVE))
    release
    typed({ "3m" => 3 * INCHES }, "3m")
    assert_match(/Click a Space's prism first/, Sketchup.status_texts.last)
  end

  # A Volume above Living, then a section plane keeping what is below `z` metres.
  def upper_storey_and_section_below(z_value)
    floor = floor_face(1191, rectangle(0, 0, 3, 4, 3), segment_record("U"))
    zone.entities << space_group(1180, space_record("U", :number => "201"),
                                 [volume_group(1190, volume_record("U"), [floor])])
    @model.entities.active_section_plane = Sketchup::SectionPlane.new([0.0, 0.0, -1.0, z_value * INCHES])
  end

  def test_a_section_cut_passes_over_a_volume_it_has_cut_away
    upper_storey_and_section_below(2.9)
    press(aim(0, 0, *FROM_ABOVE))
    release
    typed({ "3m" => 3 * INCHES }, "3m")
    assert_in_delta 3.0, height, 1e-9, "the storey the section leaves showing"
  end

  def test_a_prism_cut_part_way_is_picked_below_the_cut_and_drawn_clipped
    upper_storey_and_section_below(1.0)
    press(aim(0, 0, *FROM_ABOVE))
    release
    @view.draws.clear
    tool.draw(@view)
    _mode, points = @view.draws.last
    assert_operator points.map(&:z).max, :<=, (1.0 * INCHES) + 3.1, "the 2.5 m top is cut away; 3 inches of lift"
    typed({ "3m" => 3 * INCHES }, "3m")
    assert_in_delta 3.0, height, 1e-9
  end

  def test_the_nearest_prism_face_answers_and_a_ray_missing_every_face_does_not
    floor = [[0.0, 0.0, 0.0], [3.0, 0.0, 0.0], [3.0, 4.0, 0.0], [0.0, 4.0, 0.0]]
    shapes = PhComposer::Spaces::Prism.call([[floor]], 2.5)
    assert_in_delta 17.5, PICK.distances(shapes, [1.0, 1.0, 20.0], [0.0, 0.0, -1.0]).first, 1e-9, "the top first"
    assert_in_delta 10.0, PICK.distances(shapes, [1.0, -10.0, 1.0], [0.0, 1.0, 0.0]).first, 1e-9, "the near side"
    assert_empty PICK.distances(shapes, [9.0, 9.0, 20.0], [0.0, 0.0, -1.0])
    assert_empty PICK.distances(shapes, [1.0, 1.0, 20.0], [0.0, 0.0, 1.0]), "behind the eye"
  end

  def test_a_ray_down_the_vertical_line_says_nothing_about_a_height
    assert_nil PICK.rise([1.0, 1.0, 0.0], [1.0, 1.0, 20.0], [0.0, 0.0, -1.0])
    assert_nil PICK.rise([1.0, 1.0, 0.0], [1.0, 1.0, 20.0], [0.05, 0.0, -0.9987492])
    assert_in_delta 3.0, PICK.rise([1.0, 0.0, 1.0], [1.0, -10.0, 4.0], [0.0, 1.0, 0.0]), 1e-9
    assert_nil PICK.rise([1.0, 0.0, 1.0], [1.0, -10.0, 4.0], [0.0, -1.0, 0.0]), "behind the eye"
  end

  def test_bounds_reject_a_ray_that_misses_and_pass_one_that_reaches_the_prism
    bounds = [[0.0, 3.0], [0.0, 4.0], [0.0, 2.5]]
    assert PICK.crosses?(bounds, [1.0, 1.0, 20.0], [0.0, 0.0, -1.0])
    refute PICK.crosses?(bounds, [9.0, 1.0, 20.0], [0.0, 0.0, -1.0])
    refute PICK.crosses?(bounds, [1.0, 1.0, 20.0], [0.0, 0.0, 1.0]), "behind the eye"
  end

  # Edit outline, the menu item.

  def menu
    PhComposer::Spaces::EditOutlineMenu
  end

  def run_menu
    menu::Client.new(@session).run
  end

  def test_the_menu_offers_itself_on_one_space_or_one_volume
    assert_nil menu.selected(@session), "nothing selected"
    @model.selection.add(space)
    refute_nil menu.selected(@session)
    @model.selection.clear
    @model.active_path = [zone, space]
    @model.selection.add(volume)
    refute_nil menu.selected(@session)
    @model.selection.clear
    @model.active_path = [zone]
    @model.selection.add(zone.entities.to_a.first(2))
    assert_nil menu.selected(@session), "two Spaces"
  end

  def test_a_space_opens_its_one_volume_unprotected_as_one_undo_step
    @model.active_path = [zone]
    @model.selection.add(space)
    operations = @model.operations.length
    assert_equal true, volume.locked?
    assert_equal "completed", run_menu.fetch("status")
    assert_equal false, volume.locked?
    assert_equal [1000, 1100, 1110], @model.active_path.map(&:persistent_id)
    assert_equal operations + 1, @model.operations.length, "the Unprotect; opening writes nothing"
  end

  def test_a_selected_volume_already_unprotected_only_opens
    @model.active_path = [zone, space]
    volume.locked = false
    @model.selection.add(volume)
    operations = @model.operations.length
    assert_equal "completed", run_menu.fetch("status")
    assert_equal [1000, 1100, 1110], @model.active_path.map(&:persistent_id)
    assert_equal operations, @model.operations.length
  end

  def test_the_menu_says_what_to_select
    operations = @model.operations.length
    run_menu
    assert_equal menu::SELECT_ONE, UI.messages.last
    @model.active_path = [zone]
    @model.selection.add(space)
    floor = floor_face(1191, rectangle(0, 5, 1, 1), segment_record("Z"))
    space.entities << volume_group(1190, volume_record("Z", :number => 2), [floor])
    run_menu
    assert_equal menu::SEVERAL_VOLUMES, UI.messages.last
    assert_equal operations, @model.operations.length
    assert_equal [1000], @model.active_path.map(&:persistent_id)
  end

  def test_a_space_locked_by_the_user_refuses_with_the_reason
    @model.active_path = [zone]
    @model.selection.add(space)
    space.locked = true
    operations = @model.operations.length
    assert_equal "refused", run_menu.fetch("status")
    assert_match(/locked/, UI.messages.last)
    assert_equal operations, @model.operations.length
  end
end
