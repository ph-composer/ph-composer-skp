# frozen_string_literal: true

require_relative "test_helper"
require_relative "support/space_fixtures"

# The Mark floor tool, the gesture rather than the operation: what a click and a drag collect, the factor
# frozen at button-down, every cancel route writing nothing, the gesture limit, what each pick means, and
# the Colour-by mode it turns on until it stops.
class SpacesMarkToolTest < PhComposerTestCase
  include SpaceFixtures

  API = PhComposer::API
  MODE = "ph_composer.spaces.by_weighting_factor"

  def setup
    super
    @model = Sketchup.active_model
    @session = PhComposer::Sessions.for(@model)
    @context = API.connect(:session_id => @session.id)
    @notices = []
    PhComposer::Sessions.on_notice { |_session, message, tone| @notices << [message, tone] }
    @view = @model.active_view
    build
  end

  # Zone A holds one Space: a Volume with three unmarked Faces and one marked, two loose Faces at the Space's
  # root, a loose Face in the Zone outside the Space, and a Zone Face classified in the Faces view.
  def build
    @inside = [floor_face(1111, rectangle(0, 0, 1, 1)), floor_face(1112, rectangle(1, 0, 1, 1)),
               floor_face(1113, rectangle(2, 0, 1, 1))]
    @marked = floor_face(1114, rectangle(3, 0, 1, 1), segment_record("M"))
    @volume = volume_group(1110, volume_record("V"), @inside + [@marked])
    @root_face = floor_face(1120, rectangle(0, 2, 2, 2))
    @root_face2 = floor_face(1121, rectangle(2, 2, 2, 2))
    @space = space_group(1100, space_record("S", :number => "101", :name => "Living"),
                         [@volume, @root_face, @root_face2])
    @loose = floor_face(1200, rectangle(5, 0, 2, 2))
    @wall = floor_face(1300, rectangle(9, 0, 1, 1))
    @zone = zone_group(1000, "A", [@space, @loose, @wall])
    @stray = floor_face(9000, rectangle(20, 0, 1, 1))
    @model.entities << @zone << @stray
    # The wall is classified through the Faces feature's own operation, as a user would in the Faces view.
    result = API.invoke(:context => @context, :name => "ph_composer.zones.faces.classify",
                        :params => { "faces" => [{ "zone_id" => "zon_AAAAAAAAAAAA", "zone_path" => [1000],
                                                   "entity_path" => [1300], "entity_id" => nil }],
                                     "intent" => { "face_type" => { "mode" => "set", "value" => "Wall" } },
                                     "expected_values" => {} },
                        :request => { "sequence" => 1, "expected_revision" => @session.revision })
    assert_equal "completed", result.fetch("status"), result.inspect
  end

  def test_one_drag_marks_every_face_it_crossed_in_one_step_with_the_factor_frozen_at_button_down
    tool.start(0.5)
    point(:a, [@zone, @space, @volume, @inside[0]])
    point(:b, [@zone, @space, @volume, @inside[1]])
    operations = @model.operations.length
    press(:a)
    tool.start(1.0) # a new factor mid-drag
    move(:b)
    release

    assert_equal [0.5, 0.5], segments_on(@inside[0, 2]).map { |record| record.fetch("weighting_factor") }
    assert_equal operations + 1, @model.operations.length, "one gesture, one Undo step"
    assert_match(/Marked 2 Floor Segments at 0.5/, Sketchup.status_texts.last)
  end

  def test_escape_deactivation_suspension_and_a_raised_callback_each_write_nothing
    tool.start(1.0)
    point(:a, [@zone, @space, @volume, @inside[0]])
    operations = @model.operations.length
    [-> { tool.onCancel(0, @view) }, -> { tool.deactivate(@view) }, -> { tool.suspend(@view) }].each do |cancel|
      tool.start(1.0)
      press(:a)
      cancel.call
      release
    end
    tool.start(1.0)
    press(:a)
    @view.picks[[99, 99]] = :raise
    tool.onMouseMove(0, 99, 99, @view)
    release
    assert_equal operations, @model.operations.length
    assert_nil segments_on([@inside[0]]).first
  end

  def test_a_drag_across_one_more_face_than_the_limit_refuses_whole
    PhComposer::Spaces.floor_gesture_limit = 2
    tool.start(1.0)
    @inside.each_with_index { |face, index| point(index, [@zone, @space, @volume, face]) }
    operations = @model.operations.length
    press(0)
    move(1)
    move(2)
    release
    assert_equal operations, @model.operations.length
    assert_empty segments_on(@inside).compact
    assert_match(/at most 2/, Sketchup.status_texts.last)
  end

  def test_a_face_at_a_space_root_becomes_its_next_volume
    # Working at a Space's root means its edit context is open; a pick is then relative to it.
    @model.active_path = [@zone, @space]
    tool.start(1.0)
    point(:root, [@root_face])
    click(:root)
    assert_match(/Added a Volume/, Sketchup.status_texts.last)
    volumes = space_row.fetch("volumes")
    assert_equal 2, volumes.length
  end

  # The two root Faces share no Edge, so one drag across them makes two Volumes, in one Undo step.
  def test_a_drag_across_separate_faces_at_a_space_root_makes_a_volume_each
    @model.active_path = [@zone, @space]
    tool.start(1.0)
    point(:a, [@root_face])
    point(:b, [@root_face2])
    operations = @model.operations.length
    press(:a)
    move(:b)
    release
    assert_equal operations + 1, @model.operations.length
    assert_equal "Added 2 Volumes to the Space with 2 Floor Segments.", Sketchup.status_texts.last
    assert_equal 3, space_row.fetch("volumes").length
  end

  def test_a_face_in_a_zone_outside_any_space_is_offered_create_space_and_nothing_is_written
    @model.active_path = [@zone]
    tool.start(1.0)
    point(:loose, [@loose])
    operations = @model.operations.length
    click(:loose)
    assert_equal operations, @model.operations.length
    assert_match(/Create Space/, Sketchup.status_texts.last)
    assert_equal [[1000, 1200]], tool.offered
  end

  def test_a_classified_zone_face_and_a_face_in_a_closed_group_refuse_at_the_status_bar_and_the_notice
    closed = Sketchup::Group.new(9100, Sketchup::Entities.new([floor_face(9101, rectangle(30, 0, 1, 1))]))
    @model.entities << closed
    tool.start(1.0)
    point(:wall, [@zone, @wall])
    point(:closed, [closed, closed.entities.to_a.first])
    operations = @model.operations.length
    click(:wall)
    assert_match(/Geometry view.*Nothing was written\.\z/, Sketchup.status_texts.last)
    click(:closed)
    assert_match(/closed Group.*Nothing was written\.\z/, Sketchup.status_texts.last)
    assert_match(/Nothing was written\.\z/, @notices.last.first)
    assert_equal operations, @model.operations.length
    assert_equal :warning, @notices.last.last
  end

  def test_a_drag_mixing_places_refuses_whole
    tool.start(1.0)
    point(:in, [@zone, @space, @volume, @inside[0]])
    point(:root, [@zone, @space, @root_face])
    operations = @model.operations.length
    press(:in)
    move(:root)
    release
    assert_equal operations, @model.operations.length
    assert_match(/one place/, Sketchup.status_texts.last)
  end

  def test_a_commit_between_press_and_release_refuses_the_gesture_as_stale
    tool.start(1.0)
    point(:a, [@zone, @space, @volume, @inside[0]])
    press(:a)
    result = API.invoke(:context => @context, :name => "ph_composer.zones.faces.classify",
                        :params => { "faces" => [{ "zone_id" => "zon_AAAAAAAAAAAA", "zone_path" => [1000],
                                                   "entity_path" => [1200], "entity_id" => nil }],
                                     "intent" => { "face_type" => { "mode" => "set", "value" => "Wall" } },
                                     "expected_values" => {} },
                        :request => { "sequence" => 2, "expected_revision" => @session.revision })
    assert_equal "completed", result.fetch("status"), result.inspect
    operations = @model.operations.length
    release
    assert_equal operations, @model.operations.length
    assert_nil segments_on([@inside[0]]).first
    assert_match(/changed|stale/i, Sketchup.status_texts.last)
  end

  def test_a_face_inside_a_plain_group_in_a_zone_is_not_offered_create_space
    face = floor_face(1401, rectangle(12, 0, 1, 1))
    group = Sketchup::Group.new(1400, Sketchup::Entities.new([face]))
    @zone.entities << group
    tool.start(1.0)
    point(:nested, [@zone, group, face])
    click(:nested)
    assert_empty tool.offered
    assert_match(/inside a Group/, Sketchup.status_texts.last)
  end

  def test_a_context_menu_that_raises_cancels_the_pending_gesture
    tool.start(1.0)
    point(:a, [@zone, @space, @volume, @inside[0]])
    operations = @model.operations.length
    press(:a)
    original = PhComposer::Commands.method(:install_feature_menus)
    PhComposer::Commands.define_singleton_method(:install_feature_menus) { |*_args, **_options| raise "menu failed" }
    tool.getMenu(Object.new, 0, 0, 0, @view)
    release
    assert_equal operations, @model.operations.length
    assert_nil segments_on([@inside[0]]).first
  ensure
    PhComposer::Commands.define_singleton_method(:install_feature_menus, original) if original
  end

  def test_a_drag_across_more_space_root_faces_than_the_limit_refuses_whole
    PhComposer::Spaces.floor_gesture_limit = 1
    @model.active_path = [@zone, @space]
    tool.start(1.0)
    point(:a, [@root_face])
    point(:b, [@root_face2])
    operations = @model.operations.length
    press(:a)
    move(:b)
    release
    assert_equal operations, @model.operations.length
    assert_equal 1, space_row.fetch("volumes").length
    assert_match(/at most 1 Faces/, Sketchup.status_texts.last)
  end

  def test_a_move_without_the_button_after_a_lost_release_cancels_the_gesture
    tool.start(1.0)
    point(:a, [@zone, @space, @volume, @inside[0]])
    point(:b, [@zone, @space, @volume, @inside[1]])
    operations = @model.operations.length
    press(:a)
    xy = @coordinates.fetch(:b)
    tool.onMouseMove(0, xy[0], xy[1], @view) # the button is up: its release never arrived
    release
    assert_equal operations, @model.operations.length
    assert_empty segments_on(@inside[0, 2]).compact
  end

  # No Zone is a choice in Create Space's review, so a Space hosted in none takes floors like any other.
  def test_a_face_in_a_space_hosted_in_no_zone_is_marked
    @zone.entities.delete(@space)
    @model.entities << @space
    SPACES::SPACE_STORE.write(@space, SPACES::SPACE_STORE.read(@space).reject { |key, _value| key == "zone_id" })
    tool.start(1.0)
    point(:in, [@space, @volume, @inside[0]])
    operations = @model.operations.length
    click(:in)
    assert_equal operations + 1, @model.operations.length
  end

  def test_a_face_in_a_closed_zone_is_not_offered
    tool.start(1.0)
    point(:loose, [@zone, @loose])
    click(:loose)
    assert_empty tool.offered
    assert_match(/closed Group or Zone/, Sketchup.status_texts.last)
  end

  def test_a_loose_face_in_no_zone_is_offered_create_space
    tool.start(1.0)
    point(:stray, [@stray])
    click(:stray)
    assert_equal [[9000]], tool.offered
    assert_match(/Create Space/, Sketchup.status_texts.last)
  end

  def test_hovering_places_each_pick_from_its_path_without_walking_the_model
    scans = 0
    original = PhComposer::Spaces::Occurrences.method(:scan)
    PhComposer::Spaces::Occurrences.define_singleton_method(:scan) do |*args, **options|
      scans += 1
      original.call(*args, **options)
    end
    tool.start(1.0) # its Colour-by mode reads the Model once
    scans = 0
    point(:in, [@zone, @space, @volume, @inside[0]])
    3.times { tool.onMouseMove(0, *@coordinates.fetch(:in), @view) }
    assert_equal 0, scans
  ensure
    PhComposer::Spaces::Occurrences.define_singleton_method(:scan, original)
  end

  def test_a_loose_face_in_shared_zone_storage_refuses_instead_of_being_offered
    @model.entities.delete(@zone)
    holder = Sketchup::ComponentInstance.new(5000, Sketchup::ComponentDefinition.new(Sketchup::Entities.new([@zone])))
    @model.entities << holder
    tool.start(1.0)
    point(:loose, [holder, @zone, @loose])
    click(:loose)
    assert_empty tool.offered
    refute_match(/Create Space/, Sketchup.status_texts.last)
    assert_equal :warning, @notices.last.last
  end

  def test_an_unreadable_face_record_refuses_rather_than_offering
    @wall.set_attribute("ph_composer.face_assignment", "record", "{not json")
    tool.start(1.0)
    point(:wall, [@zone, @wall])
    click(:wall)
    assert_empty tool.offered
    assert_match(/not valid JSON/, Sketchup.status_texts.last)
  end

  def test_a_draw_that_raises_cancels_the_pending_gesture
    tool.start(1.0)
    point(:a, [@zone, @space, @volume, @inside[0]])
    operations = @model.operations.length
    press(:a)
    @view.define_singleton_method(:draw) { |*_args| raise "drawing failed" }
    tool.draw(@view)
    release
    assert_equal operations, @model.operations.length
    assert_nil segments_on([@inside[0]]).first
  ensure
    @view.singleton_class.send(:remove_method, :draw) if @view.singleton_methods.include?(:draw)
  end

  def test_stop_leaves_another_tool_running
    tool.start(1.0)
    classify = PhComposer::Zones::Faces.classify_tool(@session).start
    API.view(:context => @context, :name => "ph_composer.spaces.mark_tool.stop", :params => {})
    assert classify.active?
  end

  def test_starting_after_a_tool_that_forced_the_same_mode_keeps_that_mode_on
    service = PhComposer::ColourBy.for(@session)
    tool.start(1.0)
    tool.stop
    service.deactivate
    PhComposer::Zones::Faces.classify_tool(@session).start # forces the remembered weighting-factor mode
    tool.start(1.0)
    assert tool.active?
    assert_equal MODE, service.mode_name
  end

  # Classify replacing Mark floor puts back the mode from before either tool, not Mark floor's.
  def test_a_classify_paint_choice_replacing_the_tool_ends_on_the_mode_before_both
    service = PhComposer::ColourBy.for(@session)
    service.activate(PhComposer::Zones::ColourModes::BY_ZONE)
    tool.start(1.0)
    classify = PhComposer::Zones::Faces.classify_tool(@session)
    classify.choose("face_type", "Wall", :reset => true)
    refute tool.active?
    assert_equal PhComposer::Zones::Faces::ColourModes::BY_FACE_TYPE, service.mode_name
    classify.stop
    assert_equal PhComposer::Zones::ColourModes::BY_ZONE, service.mode_name
  end

  def test_starting_turns_colour_by_weighting_factor_on_and_stopping_puts_back_the_mode_before
    service = PhComposer::ColourBy.for(@session)
    service.activate(PhComposer::Zones::ColourModes::BY_ZONE)
    result = API.view(:context => @context, :name => "ph_composer.spaces.mark_tool.start",
                      :params => { "weighting_factor" => 0.6 })
    assert_equal "completed", result.fetch("status"), result.inspect
    assert_equal({ "active" => true, "weighting_factor" => 0.6, "gesture_limit" => 250 }, result.fetch("value"))
    assert_equal MODE, service.mode_name
    API.view(:context => @context, :name => "ph_composer.spaces.mark_tool.stop", :params => {})
    refute tool.active?
    assert_equal PhComposer::Zones::ColourModes::BY_ZONE, service.mode_name
  end

  # The service can detach before the tool does; the tool's end must not turn a mode back on in it.
  def test_detaching_restores_no_mode_into_a_colour_by_that_detached_first
    service = PhComposer::ColourBy.for(@session)
    service.activate(PhComposer::Zones::ColourModes::BY_ZONE)
    tool.start(1.0)
    @session.detach
    assert_nil @model.active_tool
    refute service.active?
    assert_empty @model.overlays.to_a
  end

  def test_detach_with_the_tool_active_leaves_no_tool
    tool.start(1.0)
    assert tool.active?
    tool.detach
    refute tool.active?
    assert_nil @model.tools.active_tool if @model.respond_to?(:tools) && @model.tools.respond_to?(:active_tool)
  end

  private

  def tool
    PhComposer::Spaces.mark_tool(@session)
  end

  def point(name, entities)
    @coordinates ||= {}
    @coordinates[name] ||= [100 + @coordinates.length, 100]
    @view.picks[@coordinates[name]] = entities
  end

  def press(name)
    xy = @coordinates.fetch(name)
    tool.onLButtonDown(0, xy[0], xy[1], @view)
  end

  def move(name)
    xy = @coordinates.fetch(name)
    tool.onMouseMove(MK_LBUTTON, xy[0], xy[1], @view)
  end

  def release
    tool.onLButtonUp(0, 0, 0, @view)
  end

  def click(name)
    press(name)
    release
  end

  def segments_on(faces)
    faces.map { |face| PhComposer::Spaces::FLOOR_SEGMENT_STORE.read(face) }
  end

  def space_row
    API.query(:context => @context, :name => "ph_composer.spaces.all").dig("value", "spaces").first
  end
end
