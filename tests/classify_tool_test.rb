# frozen_string_literal: true

require_relative "test_helper"
require_relative "support/framing_camera"

# The Classify tool, which is the gesture rather than the operation.
#
# face_gesture_test.rb tests what `ph_composer.zones.faces.classify` does with a set of references.
# What these tests hold is the half the pointer owns: which Faces a click, a drag and a Shift-click
# collect, that the palette is frozen when the button goes down, that every cancel route writes
# nothing, and that a paint choice shows its Colour-by mode until Stop puts back the one from before.
class ClassifyToolTest < PhComposerTestCase
  API = PhComposer::API
  ColourBy = PhComposer::ColourBy

  def setup
    super
    @model = Sketchup.active_model
    # This fixture exercises hand classification; default-on Make/Suggest has its own settings tests.
    settings = PhComposer::Zones::Faces::Settings
    settings::STORE.write(@model, settings::DEFAULTS.merge("suggest_on_make" => false))
    @session = PhComposer::Sessions.for(@model)
    @context = API.connect(:session_id => @session.id)
    @sequence = 0
    @notices = []
    PhComposer::Sessions.on_notice { |_session, message, tone| @notices << [message, tone] }
    @view = @model.active_view
  end

  def test_one_click_classifies_the_face_under_the_pointer_in_one_undo_step
    zone(100)
    tool.choose("face_type", "Wall")
    point_at([10, 10], @faces.fetch(0))

    click([10, 10])

    assert_equal ["Wall"], values("face_type").compact
    assert_equal "Classified 1 Face.", Sketchup.status_texts.last
    @model.undo

    assert_empty values("face_type").compact
  end

  def test_palette_guidance_reaches_the_status_bar_without_covering_panel_controls
    tool.choose("face_type", "Wall")
    tool.choose("boundary_condition", "Outdoors")

    assert tool.active?
    assert_empty @notices
    assert_includes Sketchup.status_texts.last, "Click or drag over Faces"
    assert_includes Sketchup.status_texts.last, "Outdoors"
  end

  def test_guidance_uses_the_glossarys_words_and_never_a_record_id
    guidance = PhComposer::Zones::Faces::ClassifyGuidance
    palette = { "face_type" => { "mode" => "set", "value" => "RoofCeiling" },
                "boundary_condition" => { "mode" => "set", "value" => "Adiabatic" },
                "assembly_id" => { "mode" => "set", "value" => "asm_Missing00001" } }

    assert_equal ["face type Roof or ceiling", "boundary To neighbour", "Assembly not found"],
                 guidance.describe(@context, palette)
  end

  def test_classify_cursor_is_loaded_once_and_reused_across_model_sessions
    # A fresh tool class gives this assertion its own cache without changing the production cache.
    tool_class = Class.new(PhComposer::Zones::Faces::ClassifyTool)
    first = tool_class.new(@session)
    second = tool_class.new(PhComposer::Sessions.for(Sketchup::Model.new))

    assert first.onSetCursor
    assert second.onSetCursor
    assert_equal 1, UI.created_cursors.length
    assert_equal 1, UI.last_cursor
    path, hot_x, hot_y = UI.created_cursors.first
    assert File.file?(path)
    assert_equal [1, 1], [hot_x, hot_y]
  end

  def test_native_tool_choices_and_deactivation_publish_current_state_without_model_operations
    states = []
    PhComposer::Sessions.on_refresh do |session|
      next unless session == @session

      states << [tool.active?, tool.chosen("face_type")]
    end
    UI.run_timers
    states.clear
    operations = @model.operations.dup

    tool.choose("face_type", "Wall")
    UI.run_timers
    assert_equal [[true, "Wall"]], states

    tool.choose("face_type", "Floor")
    UI.run_timers
    assert_equal [true, "Floor"], states.last

    tool.stop
    UI.run_timers
    assert_equal [false, "Floor"], states.last
    assert_equal 3, states.length
    assert_equal operations, @model.operations
  end

  # A drag is one gesture however many Faces it crosses: one invoke, so one Undo entry.
  def test_a_drag_over_several_faces_is_one_gesture_and_one_undo_step
    zone(200)
    tool.choose("face_type", "Wall")
    @faces.each_with_index { |face, index| point_at([index, 0], face) }

    press([0, 0])
    move([1, 0])
    move([2, 0])
    release

    assert_equal %w[Wall Wall Wall], values("face_type").compact
    assert_equal 1, @model.operations.count { |name, _ui, _state| name == "Classify Faces" },
                 "one gesture opens one native operation"
    @model.undo

    assert_empty values("face_type").compact
  end

  # Shift takes every connected coplanar Face in the same container. The third Face of the fixture
  # shares an Edge with the second but lies in another plane, so the flood stops at it.
  def test_shift_click_takes_the_connected_coplanar_faces_and_stops_at_the_plane
    zone_with_shared_edges(300)
    tool.choose("face_type", "Wall")
    point_at([10, 10], @faces.fetch(0))

    click([10, 10], CONSTRAIN_MODIFIER_MASK)

    assert_equal %w[Wall Wall], values("face_type").compact
  end

  def test_a_plain_click_takes_only_the_face_under_the_pointer
    zone_with_shared_edges(400)
    tool.choose("face_type", "Wall")
    point_at([10, 10], @faces.fetch(0))

    click([10, 10])

    assert_equal ["Wall"], values("face_type").compact
  end

  # Escape ends the tool and takes its pending gesture with it, which is the one-layer-at-a-time
  # rule. Nothing was written, because nothing is written until the button comes up.
  def test_escape_cancels_the_pending_gesture_and_ends_the_tool_without_writing
    zone(500)
    tool.choose("face_type", "Wall")
    point_at([10, 10], @faces.fetch(0))
    press([10, 10])

    tool.onCancel(0, @view)

    assert_empty values("face_type").compact
    assert_nil @model.active_tool
    assert_includes @notices.map(&:first), PhComposer::Zones::Faces::ClassifyTool::CANCELLED
  end

  def test_deactivating_the_tool_cancels_a_pending_gesture_without_writing
    zone(600)
    tool.choose("face_type", "Wall")
    point_at([10, 10], @faces.fetch(0))
    press([10, 10])

    tool.stop

    assert_empty values("face_type").compact
    assert_empty(@model.operations.select { |name, _ui, _state| name == "Classify Faces" })
  end

  # The edit context changing under a pending gesture invalidates every path it collected.
  def test_suspending_the_tool_cancels_a_pending_gesture
    zone(650)
    tool.choose("face_type", "Wall")
    point_at([10, 10], @faces.fetch(0))
    press([10, 10])

    tool.suspend(@view)
    tool.onLButtonUp(0, 10, 10, @view)

    assert_empty values("face_type").compact
  end

  def test_late_mouse_up_after_a_model_switch_cancels_without_a_suspend_callback
    zone(660)
    tool.choose("face_type", "Wall")
    point_at([10, 10], @faces.fetch(0))
    press([10, 10])
    Sketchup.active_model = Sketchup::Model.new

    tool.onLButtonUp(0, 10, 10, @view)

    assert_empty values("face_type").compact
    assert_empty(@model.operations.select { |name, _ui, _state| name == "Classify Faces" })
    refute tool.send(:collecting?)
  end

  def test_late_mouse_up_after_an_edit_path_change_cancels_without_a_suspend_callback
    zone(670)
    tool.choose("face_type", "Wall")
    point_at([10, 10], @faces.fetch(0))
    press([10, 10])
    @model.active_path = [@model.entities.grep(Sketchup::Group).first]
    invalidations = @view.invalidations

    tool.onLButtonUp(0, 10, 10, @view)

    assert_empty values("face_type").compact
    assert_empty(@model.operations.select { |name, _ui, _state| name == "Classify Faces" })
    refute tool.send(:collecting?)
    assert_operator @view.invalidations, :>, invalidations
  end

  # A Face in no Zone refuses the whole pending gesture rather than painting the rest of it.
  def test_a_face_outside_every_zone_refuses_the_whole_gesture
    zone(700)
    loose = Sketchup::Face.new(7_999, {}, :points => triangle(9))
    @model.entities << loose
    tool.choose("face_type", "Wall")
    point_at([10, 10], @faces.fetch(0))
    @view.picks[[20, 20]] = [loose]

    press([10, 10])
    move([20, 20])
    release

    assert_empty values("face_type").compact
    assert_includes @notices.map(&:first), PhComposer::Zones::Faces::ClassifyTool::OUTSIDE_ZONE
  end

  # A drag crosses empty space whenever the Zone has a window opening, a re-entrant corner or sky
  # past a gable. That is not the outside-a-Zone refusal, and the Faces at both ends are painted.
  def test_a_drag_across_empty_space_paints_the_faces_at_both_ends_of_it
    zone(720, 2)
    tool.choose("face_type", "Wall")
    point_at([0, 0], @faces.fetch(0))
    point_at([2, 0], @faces.fetch(1))

    press([0, 0])
    move([1, 0])
    move([2, 0])
    release

    assert_equal %w[Wall Wall], values("face_type").compact
    refute_includes @notices.map(&:first), PhComposer::Zones::Faces::ClassifyTool::OUTSIDE_ZONE
  end

  # A press whose release the host never delivered must not leave the tool collecting: otherwise
  # ordinary hovers pile into the pending gesture and the next release writes them.
  def test_a_pointer_move_after_a_cancelled_press_collects_nothing
    zone(740, 3)
    tool.choose("face_type", "Wall")
    @faces.each_with_index { |face, index| point_at([index, 0], face) }

    press([0, 0])
    tool.onCancel(1, @view)
    move([1, 0])
    move([2, 0])
    release

    assert_empty values("face_type").compact
  end

  def test_a_move_without_the_button_after_a_lost_release_cancels_the_gesture
    zone(760, 3)
    tool.choose("face_type", "Wall")
    @faces.each_with_index { |face, index| point_at([index, 0], face) }

    press([0, 0])
    move([1, 0], 0) # the button is up: its release never arrived
    move([2, 0], 0)
    release

    assert_empty values("face_type").compact
  end

  def test_a_draw_that_raises_cancels_the_pending_gesture
    zone(780, 3)
    tool.choose("face_type", "Wall")
    point_at([0, 0], @faces.first)
    press([0, 0])
    @view.define_singleton_method(:draw) { |*_args| raise "drawing failed" }
    tool.draw(@view)
    release

    assert_empty values("face_type").compact
  ensure
    @view.singleton_class.send(:remove_method, :draw) if @view.singleton_methods.include?(:draw)
  end

  def test_stop_leaves_another_tool_running
    tool.start
    tool.stop
    mark = PhComposer::Spaces.mark_tool(@session).start(1.0)
    tool.stop
    assert mark.active?
  end

  # The set stops one past the ceiling so the operation that owns the ceiling refuses the gesture,
  # rather than the tool quietly painting the first 250 of what the pointer crossed.
  def test_a_gesture_over_the_ceiling_is_refused_whole
    zone(800, 4)
    PhComposer::Zones::Faces.gesture_face_limit = 2
    tool.choose("face_type", "Wall")
    @faces.each_with_index { |face, index| point_at([index, 0], face) }

    press([0, 0])
    (1..3).each { |index| move([index, 0]) }
    release

    assert_empty values("face_type").compact
    assert_includes @notices.map(&:last), :warning
    assert(@notices.any? { |message, _tone| message.include?("at most 2 Faces") })
    # The panel is the only subscriber to a session notice, and a viewport tool is used with the
    # panel closed, so a refusal that went only there would be silent where it matters.
    assert(Sketchup.status_texts.any? { |text| text.include?("at most 2 Faces") },
           "a refusal reaches the status bar, which needs no panel")
  end

  # Nothing to paint is a refusal the user can act on, not a silent no-op.
  def test_a_gesture_with_nothing_chosen_writes_nothing_and_says_so
    zone(850)
    tool.start
    point_at([10, 10], @faces.fetch(0))

    click([10, 10])

    assert_empty values("face_type").compact
    assert_includes @notices.map(&:first), PhComposer::Zones::Faces::ClassifyTool::NOTHING_CHOSEN
  end

  # The palette is the Model's and the intent is the gesture's: changing the palette after the
  # button goes down cannot change what that drag writes.
  def test_the_palette_is_frozen_when_the_button_goes_down
    zone(900, 2)
    tool.choose("face_type", "Wall")
    point_at([0, 0], @faces.fetch(0))
    point_at([1, 0], @faces.fetch(1))

    press([0, 0])
    tool.choose("face_type", "Floor")
    move([1, 0])
    release

    assert_equal %w[Wall Wall], values("face_type").compact
  end

  def test_the_palette_survives_the_tool_ending
    zone(950)
    tool.choose("boundary_condition", "Ground")
    tool.stop

    assert_equal({ "mode" => "set", "value" => "Ground" },
                 PhComposer::Zones::Faces.classify_tool(@session).palette.fetch("boundary_condition"))
  end

  # The tool forces Colour-by on while it is active, and what it forced is not what the user chose, so
  # the remembered mode is left alone and the mode goes off again with the tool.
  def test_the_tool_forces_colour_by_on_and_off_again_without_remembering_it
    zone(1_000)
    Sketchup.clear_default_writes

    tool.start

    assert ColourBy.for(@session).active?
    assert_empty Sketchup.default_writes.select { |_section, key, _value| key == "colour_by_mode" }

    tool.stop

    refute ColourBy.for(@session).active?
  end

  def test_paint_choices_show_their_colour_mode_and_stop_puts_back_the_one_before
    fields = {
      "face_type" => ["Wall", PhComposer::Zones::Faces::ColourModes::BY_FACE_TYPE],
      "boundary_condition" => ["Ground", PhComposer::Zones::Faces::ColourModes::BY_BOUNDARY_CONDITION],
      "attached_zone_id" => ["atz_1", PhComposer::Zones::Faces::ColourModes::BY_BOUNDARY_CONDITION],
      "assembly_id" => ["asm_1", PhComposer::Zones::Faces::ColourModes::BY_ASSEMBLY]
    }
    fields.each do |field, (value, mode)|
      ColourBy.for(@session).activate(PhComposer::Zones::ColourModes::BY_ZONE)
      revision = @session.revision
      modified = @model.modified?
      operations = @model.operations.length

      tool.choose(field, value, :reset => true)

      assert_equal mode, ColourBy.for(@session).mode_name, field
      refute_equal mode, ColourBy.remembered_mode, field
      assert_equal revision, @session.revision
      assert_equal modified, @model.modified?
      assert_equal operations, @model.operations.length
      tool.stop
      assert_equal PhComposer::Zones::ColourModes::BY_ZONE, ColourBy.for(@session).mode_name,
                   "Stop puts back the mode from before #{field}'s"
    end
  end

  def test_a_paint_choice_made_with_no_mode_on_goes_off_with_the_tool
    tool.start
    tool.choose("boundary_condition", "Ground", :reset => true)
    tool.stop

    refute ColourBy.for(@session).active?
  end

  def test_changing_paint_field_switches_colour_by_while_the_tool_is_active
    tool.choose("face_type", "Wall", :reset => true)
    tool.choose("boundary_condition", "Ground", :reset => true)

    assert_equal PhComposer::Zones::Faces::ColourModes::BY_BOUNDARY_CONDITION, ColourBy.for(@session).mode_name
    assert_equal({ "boundary_condition" => { "mode" => "set", "value" => "Ground" } }, tool.palette)
  end

  # A user who picks a mode from the Colour by menu while the tool is running has chosen it, and
  # the tool has no business turning their choice off when it ends.
  def test_a_mode_chosen_while_the_tool_was_running_survives_the_tool
    zone(1_050)
    tool.start
    ColourBy.for(@session).activate(PhComposer::Zones::ColourModes::BY_ZONE)

    tool.stop

    assert_equal PhComposer::Zones::ColourModes::BY_ZONE, ColourBy.for(@session).mode_name
  end

  # A paint choice after the user picked a mode mid-run ends on the user's mode, not the one from before.
  def test_a_paint_choice_after_a_mode_picked_mid_run_ends_on_that_mode
    zone(1_055)
    tool.start
    ColourBy.for(@session).activate(PhComposer::Zones::ColourModes::BY_ZONE)
    tool.choose("boundary_condition", "Ground", :reset => true)

    tool.stop

    assert_equal PhComposer::Zones::ColourModes::BY_ZONE, ColourBy.for(@session).mode_name
  end

  # Picking the tool's own mode again is still the user's choice, and it stays after the tool.
  def test_the_tools_mode_picked_again_mid_run_survives_the_tool
    zone(1_057)
    ColourBy.for(@session).activate(PhComposer::Zones::ColourModes::BY_ZONE)
    tool.choose("face_type", "Wall", :reset => true)
    ColourBy.for(@session).activate(PhComposer::Zones::Faces::ColourModes::BY_BOUNDARY_CONDITION)
    ColourBy.for(@session).activate(PhComposer::Zones::Faces::ColourModes::BY_FACE_TYPE)

    tool.stop

    assert_equal PhComposer::Zones::Faces::ColourModes::BY_FACE_TYPE, ColourBy.for(@session).mode_name
  end

  # A reload detaches every session. The tool must not be left selected against one that is gone.
  def test_detaching_the_session_takes_the_tool_and_the_mode_it_forced_with_it
    zone(1_060)
    tool.start

    @session.detach

    assert_nil @model.active_tool
    refute ColourBy.for(@session).active?
  end

  # The service can detach before the tool does; the tool's end must not turn a mode back on in it.
  def test_detaching_restores_no_mode_into_a_colour_by_that_detached_first
    zone(1_065)
    service = ColourBy.for(@session)
    service.activate(PhComposer::Zones::ColourModes::BY_ZONE)
    tool.choose("face_type", "Wall", :reset => true)

    @session.detach

    assert_nil @model.active_tool
    refute service.active?
    assert_empty @model.overlays.to_a
  end

  def test_a_mode_the_user_already_turned_on_survives_the_tool
    zone(1_100)
    ColourBy.for(@session).activate(PhComposer::Zones::ColourModes::BY_ZONE)

    tool.start
    tool.stop

    assert_equal PhComposer::Zones::ColourModes::BY_ZONE, ColourBy.for(@session).mode_name
  end

  # The hover draws the Face under the pointer; a collected Face draws in the other highlight role.
  def test_the_pointer_draws_what_it_is_over_and_what_it_has_collected
    zone(1_200)
    tool.choose("face_type", "Wall")
    point_at([10, 10], @faces.fetch(0))

    move([10, 10])
    tool.draw(@view)

    assert_equal 1, @view.draws.count { |mode, _points, _colour, _width| mode == GL_TRIANGLES }
    assert_equal PhComposer::Zones::Faces::ClassifyTool::HOVER_COLOUR,
                 @view.draws.first.fetch(2).to_a.first(3)
  end

  # Native choices assign selected Faces immediately; the secondary palette remains independent.
  def test_the_menu_assigns_one_field_at_a_time_without_starting_the_tool
    zone(1_150)
    @model.active_path = [@zone_group]
    @model.selection.add(@faces.fetch(0))
    PhComposer::Commands.install
    home = extension_menu(UI.build_context_menu)
    types = submenu(home, PhComposer::Zones::Faces::ClassifyMenu::TYPE_MENU)
    boundaries = submenu(home, PhComposer::Zones::Faces::ClassifyMenu::BOUNDARY_MENU)

    item(types, "Wall").call
    item(boundaries, "Ground").call

    assert_equal "Wall", values("face_type").first
    assert_equal "Ground", values("boundary_condition").first
    assert_empty tool.palette
    refute tool.active?
    assert_nil @model.active_tool
    has_exit = home.entries.any? do |entry|
      entry.is_a?(Array) && entry.first == PhComposer::Zones::Faces::ClassifyMenu::OFF
    end
    refute has_exit
  end

  # The viewport context menu offers the palette only where it applies, and the feature decides
  # where that is: `shell/` builds from whatever declined or did not. With no tool running SketchUp
  # has selected what was right-clicked, so the selection is the signal.
  def test_the_context_menu_offers_the_palette_over_a_face_and_not_elsewhere
    zone(1_170)
    PhComposer::Commands.install

    assert_empty submenu_names(UI.build_context_menu), "nothing selected means nothing was clicked"

    # A right-click on a Zone at the Model root selects the Group, not a Face, and the palette is
    # not what the user is reaching for there.
    @model.selection.add(@zone_group)

    type_menu = PhComposer::Zones::Faces::ClassifyMenu::TYPE_MENU
    refute_includes submenu_names(extension_menu(UI.build_context_menu)), type_menu

    @model.selection.clear
    @model.active_path = [@zone_group]
    @model.selection.add(@faces.fetch(0))

    assert_includes submenu_names(extension_menu(UI.build_context_menu)), type_menu
  end

  # While the tool is running, Exit remains reachable regardless of what is under the pointer.
  def test_the_running_tool_offers_exit_without_a_selected_face
    zone(1_180)
    tool.start
    point_at([10, 10], @faces.fetch(0))
    over_face = UI::Menu.new("Context")
    over_nothing = UI::Menu.new("Context")

    tool.getMenu(over_face, 0, 10, 10, @view)
    tool.getMenu(over_nothing, 0, 99, 99, @view)

    assert_includes entry_labels(extension_menu(over_face)), PhComposer::Zones::Faces::ClassifyMenu::OFF
    assert_includes entry_labels(extension_menu(over_nothing)), PhComposer::Zones::Faces::ClassifyMenu::OFF
    item(extension_menu(over_nothing), PhComposer::Zones::Faces::ClassifyMenu::OFF).call
    refute tool.active?
  end

  # The words on the menu are the glossary's, and they come from the same tables the Colour-by
  # legend reads rather than a second copy inside `shell/`.
  def test_the_menu_shows_honeybee_values_by_their_glossary_words
    PhComposer::Commands.install
    menu_names = PhComposer::Zones::Faces::ClassifyMenu
    labels = [menu_names::TYPE_MENU, menu_names::BOUNDARY_MENU].flat_map do |name|
      PhComposer::Commands.feature_menus.fetch(name).entries.select { |entry| entry.is_a?(Array) }.map(&:first)
    end

    assert_includes labels, "Roof or ceiling"
    assert_includes labels, "To neighbour"
    refute_includes labels, "RoofCeiling"
    refute_includes labels, "Surface", "Surface is the solver's, never the palette's"
    refute labels.any? { |label| label.include?("Keep") }
  end

  # A tool callback that raises reaches the host, which has nowhere to put it, so the tool catches
  # its own failures. That path has to abandon the gesture and say so rather than leaving a pending
  # gesture that a later mouse-up would apply from a half-collected set.
  def test_an_unexpected_failure_inside_a_callback_abandons_the_gesture_and_says_so
    zone(1_250)
    tool.choose("face_type", "Wall")
    point_at([10, 10], @faces.fetch(0))
    def @view.pick_helper
      raise "the host refused the pick"
    end

    press([10, 10])
    release

    assert_nil tool.collected
    assert_empty values("face_type").compact
    assert_includes @notices.map(&:last), :error
  end

  # A hover that fails fails again on the next pointer move, so it is logged and not noticed. Only
  # a failure that abandoned a gesture is worth interrupting the user for.
  def test_a_failing_hover_is_not_noticed_once_per_pointer_move
    zone(1_260)
    tool.start
    def @view.pick_helper
      raise "the host refused the pick"
    end

    3.times { |index| move([index, 0]) }

    assert_empty @notices.select { |_message, tone| tone == :error }
  end

  # Locate answers with what it could resolve, frames and outlines exactly that, and leaves the
  # selection alone, skipping a reference the Model no longer has rather than refusing the rest.
  def test_locate_outlines_the_faces_it_resolves_leaves_the_selection_and_skips_one_that_is_gone
    zone(1_300, 2)
    references = list_faces.map { |face| face.fetch("reference") }
    stale = references.last.merge("entity_path" => [9_999])
    @model.selection.add(@faces.fetch(1))

    found = PhComposer::Zones::Faces::Locate.call(@session, [references.first, stale])

    assert_equal 1, found.length
    assert_equal [@faces.fetch(1)], @model.selection.to_a, "Locate never changes the selection"
    highlight = PhComposer::Zones::Faces.locate_highlight(@session)
    assert highlight.active?
    outline = PhComposer::Zones::Faces::LocateHighlight::Overlay
    assert_equal 1, @model.overlays.count { |overlay| overlay.is_a?(outline) }
  end

  # The outline lasts until the next selection change or an explicit clear, and a clear removes the
  # overlay with it.
  def test_the_locate_outline_clears_on_a_selection_change_and_on_clear_locate
    zone(1_305, 2)
    references = list_faces.map { |face| face.fetch("reference") }
    highlight = PhComposer::Zones::Faces.locate_highlight(@session)
    PhComposer::Zones::Faces::Locate.call(@session, references)
    @session.host_event(:selection_changed)
    refute highlight.active?

    PhComposer::Zones::Faces::Locate.call(@session, references)
    context = PhComposer::API.connect(:session_id => @session.id)
    outcome = PhComposer::API.view(:context => context, :name => "ph_composer.zones.faces.clear_locate",
                                   :params => {})

    assert_equal "completed", outcome.fetch("status")
    refute highlight.active?
    outline = PhComposer::Zones::Faces::LocateHighlight::Overlay
    assert_empty(@model.overlays.select { |overlay| overlay.is_a?(outline) })
  end

  # The next Locate replaces the outline rather than adding to it, and a closed session takes the
  # overlay with it.
  def test_the_next_locate_replaces_the_outline_and_session_detach_removes_it
    zone(1_307, 2)
    references = list_faces.map { |face| face.fetch("reference") }
    highlight = PhComposer::Zones::Faces.locate_highlight(@session)
    PhComposer::Zones::Faces::Locate.call(@session, references)
    both = highlight.segments.length
    PhComposer::Zones::Faces::Locate.call(@session, references.take(1))

    assert_operator highlight.segments.length, :<, both
    outline = PhComposer::Zones::Faces::LocateHighlight::Overlay
    assert_equal 1, @model.overlays.count { |overlay| overlay.is_a?(outline) }
    @session.detach
    assert_empty(@model.overlays.select { |overlay| overlay.is_a?(outline) })
  end

  # Locate frames a Face by its world bounds, so a Zone placed away from the origin is framed where it is,
  # looking along the camera's own direction and far enough back for the Face to fit.
  def test_locate_frames_the_faces_world_bounds_along_the_camera_direction
    zone(1_315, 2)
    references = list_faces.map { |face| face.fetch("reference") }
    view = FramingCamera.attach(@model.active_view)
    found = PhComposer::Zones::Faces::Locate.call(@session, references.take(1))

    box = Geom::BoundingBox.new
    found.first.entity.vertices.each { |vertex| box.add(vertex.position.transform(found.first.transform)) }
    target, eye = view.camera.target, view.camera.eye
    assert_in_delta box.center.x, target.x, 1e-6
    assert_in_delta box.center.y, target.y, 1e-6
    assert_in_delta box.center.x, eye.x, 1e-6, "the eye looks along the camera direction (+y)"
    assert_operator eye.y, :<, target.y
    assert_operator target.y - eye.y, :>, box.diagonal / 2.0, "far enough back to fit the Face"
    assert_empty view.zoomed, "a view with a camera is framed, not zoomed"
  end

  # The selection-change count advances on every native selection change, whatever it selects, and its
  # read never refuses, so the panel can tell a selection of a Group from no change at all.
  def test_the_selection_change_count_advances_on_every_selection_change_and_never_refuses
    zone(1_320, 2)
    context = PhComposer::API.connect(:session_id => @session.id)
    read = lambda do
      PhComposer::API.query(:context => context, :name => "ph_composer.zones.faces.selection_generation")
    end
    counts = [read.call.dig("value", "generation")]
    2.times do
      @session.host_event(:selection_changed)
      counts << read.call.dig("value", "generation")
    end

    assert_equal "completed", read.call.fetch("status")
    # Only that it moves is the contract; a suite that installs features more than once subscribes more than once.
    assert_equal counts.sort.uniq, counts, "the count advances on each selection change"
  end

  # Locate and Select are view commands, so they answer a client that has `view` access without
  # opening an operation, leaving an Undo entry or moving the revision. Select is the one that selects.
  def test_locate_and_select_are_reachable_from_a_client_and_write_nothing
    zone(1_310, 2)
    references = list_faces.map { |face| face.fetch("reference") }
    context = PhComposer::API.connect(:session_id => @session.id)
    revision = @session.revision

    located = PhComposer::API.view(:context => context, :name => "ph_composer.zones.faces.locate",
                                   :params => { "faces" => references })
    assert_equal({ "found" => 2, "missing" => 0 }, located.fetch("value"))
    assert_empty @model.selection.to_a
    selected = PhComposer::API.view(:context => context, :name => "ph_composer.zones.faces.select",
                                    :params => { "faces" => references })

    assert_equal "completed", selected.fetch("status")
    assert_equal @faces, @model.selection.to_a
    assert_equal revision, @session.revision
  end

  # The secondary panel palette sets a field and gives the tool the viewport without writing.
  def test_a_client_sets_one_palette_field_and_the_tool_takes_the_viewport
    context = PhComposer::API.connect(:session_id => @session.id)
    revision = @session.revision
    modified = @model.modified?

    outcome = PhComposer::API.view(:context => context, :name => "ph_composer.zones.faces.choose",
                                   :params => { "field" => "face_type", "value" => "RoofCeiling" })

    assert_equal true, outcome.dig("value", "active")
    assert_equal({ "face_type" => "RoofCeiling" }, outcome.dig("value", "palette"))
    assert_equal revision, @session.revision
    assert_equal modified, @model.modified?
    assert_empty @model.operations

    stopped = PhComposer::API.view(:context => context, :name => "ph_composer.zones.faces.stop_classifying",
                                   :params => {})

    assert_equal false, stopped.dig("value", "active")
    assert_equal({ "face_type" => "RoofCeiling" }, stopped.dig("value", "palette"), "the palette is kept")
  end

  # An Attached zone boundary naming no record is an incomplete Face, so the record and the boundary
  # condition are one choice however the palette is reached.
  def test_choosing_an_attached_zone_carries_its_boundary_condition_and_dropping_it_takes_it_back
    tool = PhComposer::Zones::Faces.classify_tool(@session)

    tool.choose("attached_zone_id", "atz_1")

    assert_equal "AttachedZone", tool.chosen("boundary_condition")

    tool.choose("attached_zone_id", nil)

    assert_nil tool.chosen("boundary_condition")
  end

  def test_choosing_another_boundary_condition_drops_the_attached_zone_it_replaces
    tool = PhComposer::Zones::Faces.classify_tool(@session)
    tool.choose("attached_zone_id", "atz_1")

    tool.choose("boundary_condition", "Outdoors")

    assert_nil tool.chosen("attached_zone_id")
    assert_equal "Outdoors", tool.chosen("boundary_condition")
  end

  # The palette lists Surface although nothing may set it: the panel shows it and says why, which a
  # missing row could not do.
  def test_the_palette_read_lists_the_boundary_condition_the_solver_owns
    context = PhComposer::API.connect(:session_id => @session.id)

    value = PhComposer::API.query(:context => context,
                                  :name => "ph_composer.zones.faces.classify_tool").fetch("value")

    assert_equal %w[Wall RoofCeiling Floor], value.fetch("face_types")
    assert_includes value.fetch("boundary_conditions"), "Surface"
    assert_equal false, value.fetch("active")
  end

  # The pick path and a Model walk have to agree, or the tool would paint one Face and the
  # operation resolve another.
  def test_an_occurrence_built_from_a_picked_path_matches_the_walked_one
    zone(1_400)
    nested = Sketchup::Group.new(1_450, Sketchup::Entities.new([Sketchup::Face.new(1_451, {},
                                                                                   :points => triangle(3))]))
    @zone_group.entities << nested
    face = nested.entities.to_a.first

    picked = PhComposer::Zones::Occurrences.occurrence_for_path([@zone_group, nested, face])
    walked = PhComposer::Zones::Occurrences.faces(
      PhComposer::Zones::Occurrences.zones(@model).first
    ).find { |occurrence| occurrence.entity.equal?(face) }

    assert_equal walked.path, picked.path
    assert_equal walked.reference, picked.reference
    assert_equal walked.zone.path, picked.zone.path
  end

  # The transform a picked path composes has to be the one a walk composes, or the tool would tint
  # one place and the suggestion read another. Identity transforms cannot show that, so both the
  # Zone and the Group inside it are moved.
  def test_a_picked_path_composes_the_same_world_transform_as_a_walk
    zone(1_450)
    @zone_group.transformation = Geom::Transformation.translation([100, 0, 0])
    nested = Sketchup::Group.new(1_460, Sketchup::Entities.new([Sketchup::Face.new(1_461, {},
                                                                                   :points => triangle(3))]))
    nested.transformation = Geom::Transformation.translation([0, 50, 0])
    @zone_group.entities << nested
    face = nested.entities.to_a.first

    picked = PhComposer::Zones::Occurrences.occurrence_for_path([@zone_group, nested, face])
    walked = PhComposer::Zones::Occurrences.faces(
      PhComposer::Zones::Occurrences.zones(@model).first
    ).find { |occurrence| occurrence.entity.equal?(face) }

    assert_equal walked.transform.to_a, picked.transform.to_a
    assert_equal walked.zone.transform.to_a, picked.zone.transform.to_a
    assert_equal PhComposer::Zones::Faces::Geometry.suggested_values(walked),
                 PhComposer::Zones::Faces::Geometry.suggested_values(picked)
  end

  # `PickHelper#path_at` answers relative to the open edit context, not from the Model root: inside
  # a Group, a Face's path is the Face alone. Without the active path prepended, every Face read as
  # being in no Zone while the user was inside the Zone, which is where they mostly are. Measured on
  # 26.1.188, 2026-09-20.
  def test_a_pick_inside_an_open_edit_context_still_names_the_zone
    zone(1_490)
    tool.choose("face_type", "Wall")
    @model.active_path = [@zone_group]
    # What the host returns inside the context: the Face, with no Group above it.
    @view.picks[[10, 10]] = [@faces.fetch(0)]

    assert_equal [@zone_group, @faces.fetch(0)], PhComposer::Pick.face_path(@view, 10, 10)

    click([10, 10])

    assert_equal ["Wall"], values("face_type").compact
  end

  # A Face inside a Zone nested in another Zone belongs to the inner one: a walk stops descending
  # at the inner Zone, so the outer one does not own it. Attributing it to the outer Zone builds a
  # reference the resolver accepts, because it descends a Group without checking for a Zone record,
  # and the gesture would stamp the Face with the wrong Zone.
  def test_a_face_inside_a_nested_zone_belongs_to_the_inner_zone_and_refuses_the_gesture
    zone(1_490)
    inner_face = Sketchup::Face.new(1_496, {}, :points => triangle(4))
    inner = Sketchup::Group.new(1_495, Sketchup::Entities.new([inner_face]))
    # Make Zone refuses this nesting, so the state is reached the way a user reaches it: by dragging
    # an authored Zone Group inside another one, which the host allows and no observer refuses.
    outer_record = PhComposer::Zones::ZONE_STORE.read(@zone_group)
    PhComposer::Zones::ZONE_STORE.write(inner, outer_record.merge("id" => "zon_000000000099",
                                                                  "name" => "Inner"))
    @zone_group.entities << inner

    picked = PhComposer::Zones::Occurrences.occurrence_for_path([@zone_group, inner, inner_face])

    assert_equal [1_490, 1_495], picked.zone.path
    assert picked.zone.nested
    tool.choose("face_type", "Wall")
    @view.picks[[10, 10]] = [@zone_group, inner, inner_face]

    click([10, 10])

    assert_empty values("face_type").compact
    assert(@notices.any? { |message, _tone| message.include?("nested inside another Zone") })
  end

  # A copied Zone is shared storage, and the picked occurrence has to say so, or a gesture would
  # pass the mutability check the walked one refuses.
  def test_a_picked_path_reports_shared_storage_the_way_a_walk_does
    zone(1_470)
    @model.entities << Sketchup::Group.new(1_480, @zone_group.entities)
    face = @faces.fetch(0)

    picked = PhComposer::Zones::Occurrences.occurrence_for_path([@zone_group, face])

    assert picked.zone.shared_definition
  end

  def test_a_picked_path_reaching_no_zone_resolves_to_nothing
    loose = Sketchup::Face.new(1_500, {}, :points => triangle(0))
    @model.entities << loose

    assert_nil PhComposer::Zones::Occurrences.occurrence_for_path([loose])
  end

  private

  def tool
    @tool ||= PhComposer::Zones::Faces.classify_tool(@session)
  end

  def item(menu, label)
    menu.entries.find { |entry| entry.is_a?(Array) && entry.first == label }.last
  end

  def submenu_names(menu)
    menu.entries.grep(UI::Menu).map(&:name)
  end

  def submenu(menu, name)
    menu.entries.grep(UI::Menu).find { |entry| entry.name == name }
  end

  def extension_menu(menu)
    submenu(menu, PhComposer::EXTENSION_NAME)
  end

  def entry_labels(menu)
    menu.entries.grep(Array).map(&:first)
  end

  def checked(menu, label)
    index = menu.entries.index { |entry| entry.is_a?(Array) && entry.first == label }
    menu.validation_procs.fetch(index).call
  end

  def point_at(coordinates, face)
    @view.picks[coordinates] = [@zone_group, face]
  end

  def press(coordinates)
    tool.onLButtonDown(0, coordinates.fetch(0), coordinates.fetch(1), @view)
  end

  # A move during a drag carries MK_LBUTTON, as the host sends it; a hover passes 0.
  def move(coordinates, flags = MK_LBUTTON)
    tool.onMouseMove(flags, coordinates.fetch(0), coordinates.fetch(1), @view)
  end

  def release
    tool.onLButtonUp(0, 0, 0, @view)
  end

  def click(coordinates, flags = 0)
    tool.onLButtonDown(flags, coordinates.fetch(0), coordinates.fetch(1), @view)
    release
  end

  def values(field)
    list_faces.map { |face| face.dig("values", field) }
  end

  def list_faces
    API.query(:context => @context, :name => "ph_composer.zones.faces.list").dig("value", "faces")
  end

  def invoke(name, params)
    @sequence += 1
    API.invoke(:context => @context, :name => name, :params => params,
               :request => { "sequence" => @sequence, "expected_revision" => @session.revision })
  end

  def zone(persistent_id, count = 3)
    @faces = count.times.map { |index| Sketchup::Face.new(persistent_id + index + 1, {}, :points => triangle(index)) }
    @zone_group = Sketchup::Group.new(persistent_id, Sketchup::Entities.new(@faces))
    @model.entities << @zone_group
    invoke("ph_composer.zones.make", { "parent_path" => [], "entity_ids" => [persistent_id] })
  end

  # Two coplanar Faces sharing an Edge, and a third sharing an Edge with the second but standing in
  # another plane, so a flood from the first reaches exactly two.
  def zone_with_shared_edges(persistent_id)
    shared = Sketchup::Edge.new(persistent_id + 90, Geom::Point3d.new(1, 0, 0), Geom::Point3d.new(1, 1, 0))
    corner = Sketchup::Edge.new(persistent_id + 91, Geom::Point3d.new(2, 0, 0), Geom::Point3d.new(2, 1, 0))
    first = Sketchup::Face.new(persistent_id + 1, {}, :points => flat(0), :edges => [shared])
    second = Sketchup::Face.new(persistent_id + 2, {}, :points => flat(1), :edges => [shared, corner])
    upright = Sketchup::Face.new(persistent_id + 3, {},
                                 :points => [Geom::Point3d.new(2, 0, 0), Geom::Point3d.new(2, 1, 0),
                                             Geom::Point3d.new(2, 1, 1)], :edges => [corner])
    @faces = [first, second, upright]
    @zone_group = Sketchup::Group.new(persistent_id, Sketchup::Entities.new(@faces))
    @model.entities << @zone_group
    invoke("ph_composer.zones.make", { "parent_path" => [], "entity_ids" => [persistent_id] })
  end

  def triangle(index)
    [Geom::Point3d.new(0, 0, index), Geom::Point3d.new(2, 0, index), Geom::Point3d.new(2, 2, index)]
  end

  # One square in the z = 0 plane, `offset` metres along x, so two of them are coplanar neighbours.
  def flat(offset)
    [Geom::Point3d.new(offset, 0, 0), Geom::Point3d.new(offset + 1, 0, 0),
     Geom::Point3d.new(offset + 1, 1, 0), Geom::Point3d.new(offset, 1, 0)]
  end
end
