# frozen_string_literal: true

require_relative "test_helper"
require_relative "support/space_fixtures"

# Add New Volume to Space from SketchUp's context menu: offered only for loose Faces at an open Space's root, where
# Create Space is not offered, and making one Volume per set of joined Faces through volumes.create in one Undo step.
class SpacesAddVolumeMenuTest < PhComposerTestCase
  include SpaceFixtures

  API = PhComposer::API
  MENU = PhComposer::Spaces::AddVolumeMenu
  CREATE = PhComposer::Spaces::CreateRoute

  def setup
    super
    @model = Sketchup.active_model
    @session = PhComposer::Sessions.for(@model)
    @notices = []
    PhComposer::Sessions.on_notice { |_session, message, tone| @notices << [message, tone] }
    @inside = floor_face(1111, rectangle(0, 0, 2, 2), segment_record("L"))
    @volume = volume_group(1110, volume_record("L"), [@inside])
    @near = floor_face(1120, rectangle(0, 5, 1, 1))
    @far = floor_face(1121, rectangle(5, 5, 1, 1))
    @wall = floor_face(1130, [[0, 9, 0], [1, 9, 0], [1, 9, 1], [0, 9, 1]])
    @space = space_group(1100, space_record("L", :number => "101").merge("default_height_m" => 3.1),
                         [@volume, @near, @far, @wall])
    @loose = floor_face(1200, rectangle(20, 0, 2, 2))
    @model.entities << zone_group(1000, "A", [@space, @loose])
  end

  def test_offered_for_a_loose_floor_at_an_open_spaces_root_in_place_of_create_space
    @model.active_path = [@model.entities.to_a.first, @space]
    @model.selection.add(@near)
    labels = context_menu
    assert_includes labels, MENU::LABEL
    refute_includes labels, CREATE::LABEL
    @model.selection.add(@wall)
    assert_includes context_menu, MENU::LABEL, "a wall beside a floor reaches the operation's refusal"
  end

  def test_not_offered_outside_a_space_root_or_on_a_wall_alone
    @model.selection.add(@loose)
    assert_equal [true, false], [CREATE::LABEL, MENU::LABEL].map { |label| context_menu.include?(label) },
                 "a loose Face outside every Space is Create Space's"
    @model.selection.clear
    @model.active_path = [@model.entities.to_a.first, @space]
    @model.selection.add(@wall)
    refute_includes context_menu, MENU::LABEL, "a wall alone"
    @model.selection.clear
    @model.active_path = [@model.entities.to_a.first, @space, @volume]
    @model.selection.add(@inside)
    labels = context_menu
    refute_includes labels, MENU::LABEL, "inside a Volume Mark floor applies"
    refute_includes labels, CREATE::LABEL, "and no Space is made inside a Space"
  end

  def test_separate_loose_faces_become_a_volume_each_in_one_undo_step
    @model.active_path = [@model.entities.to_a.first, @space]
    [@near, @far].each { |face| @model.selection.add(face) }
    operations = @model.operations.length

    outcome = client.run

    assert_equal "completed", outcome.fetch("status"), outcome.inspect
    assert_equal operations + 1, @model.operations.length
    assert_equal ["Added 2 Volumes to the Space with 2 Floor Segments.", :success], @notices.last
    volumes = space_row.fetch("volumes")
    assert_equal [1, 2, 3], volumes.map { |volume| volume.dig("values", "number") }
    assert_equal [3.1, 3.1], volumes.drop(1).map { |volume| volume.dig("values", "avg_ceiling_height_m") }
    factors = volumes.drop(1).map { |volume| volume.dig("floor_segments", 0, "values", "weighting_factor") }
    assert_equal [1.0, 1.0], factors
    assert @model.undo
    assert_equal 1, space_row.fetch("volumes").length, "one Undo takes both Volumes back"
  end

  def test_a_wall_in_the_selection_refuses_with_its_reason_and_writes_nothing
    @model.active_path = [@model.entities.to_a.first, @space]
    [@near, @wall].each { |face| @model.selection.add(face) }
    operations = @model.operations.length

    outcome = client.run

    assert_equal %w[refused target.wrong_kind], outcome.values_at("status", "code")
    assert_equal operations, @model.operations.length
    assert_equal ["#{PhComposer::Spaces::Eligibility::WALL} Nothing was written.", :warning], @notices.last
  end

  def test_outside_an_open_space_it_says_where_to_work_and_writes_nothing
    @model.selection.add(@loose)
    operations = @model.operations.length
    assert_nil client.run
    assert_equal [MENU::NOT_IN_SPACE, :warning], @notices.last
    assert_equal operations, @model.operations.length
  end

  private

  def client
    @session.feature_state(:spaces_add_volume_menu) { MENU::Client.new(@session) }
  end

  def context_menu
    menus = PhComposer::Commands.install_feature_menus(UI::Menu.new("Context"), :contextual => true)
    menus.values.flat_map { |menu| menu.entries.map { |entry| entry.is_a?(Array) ? entry.first : entry } }
  end

  def space_row
    context = API.connect(:session_id => @session.id)
    API.query(:context => context, :name => "ph_composer.spaces.all").dig("value", "spaces").first
  end
end
