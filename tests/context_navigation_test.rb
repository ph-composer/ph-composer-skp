# frozen_string_literal: true

require_relative "test_helper"
require_relative "support/space_fixtures"

# The foundation's edit-path commands (context/AGENT_INTERFACE.md, "Model context"): `context.open` and
# `context.root` move the path through EditContext with only the `view` capability, so every feature's
# boundary runs; each refuses before anything moves.
class ContextNavigationTest < PhComposerTestCase
  include SpaceFixtures

  API = PhComposer::API
  SPACES = PhComposer::Spaces
  OPEN = PhComposer::ContextCommands::OPEN
  # A tool the user has chosen, which may hold a gesture.
  class UserTool
    def activate; end

    def deactivate(_view); end
  end

  ROOT = PhComposer::ContextCommands::ROOT

  def setup
    super
    @model = Sketchup.active_model
    @session = PhComposer::Sessions.for(@model)
    @viewer = API.connect(:session_id => @session.id, :capabilities => %w[read view])
    @volume = volume_group(111, volume_record("A"), [floor_face(112, rectangle(0, 0, 2, 2), segment_record("A"))])
    @space = space_group(110, space_record("S", :number => "1"), [@volume])
    @zone = zone_group(100, "Z", [@space])
    @model.entities << @zone
  end

  def view(name, params = {})
    API.view(:context => @viewer, :name => name, :params => params)
  end

  def moved(name, params = {})
    result = view(name, params)
    assert_equal "completed", result["status"], result.inspect
    result.fetch("value")
  end

  def test_open_enters_a_zone_and_reopening_it_changes_nothing
    revision = @session.revision

    assert_equal({ "path" => [100, 110], "changed" => true }, moved(OPEN, "path" => [100, 110]))
    assert_equal [@zone, @space], @model.active_path
    assert_operator @session.revision, :>, revision
    revision = @session.revision
    assert_equal({ "path" => [100, 110], "changed" => false },
                 moved(OPEN, "path" => [100, 110], "expected_path" => [100, 110]))
    assert_equal revision, @session.revision
  end

  def test_root_from_an_unprotected_volume_protects_it_and_adds_no_undo_step_of_its_own
    @volume.locked = false
    @model.active_path = [@zone, @space, @volume]
    before = @model.operation_starts.length

    assert_equal({ "path" => [], "changed" => true }, moved(ROOT, "expected_path" => [100, 110, 111]))
    assert_nil @model.active_path
    assert @volume.locked?
    assert_equal [["Protect Volume", true]], @model.operation_starts[before..].map { |start| start.values_at(0, 3) }
  end

  def test_a_locked_or_missing_step_or_a_stale_path_moves_nothing
    @model.active_path = [@zone]
    revision = @session.revision

    refusals = [view(OPEN, "path" => [100, 110, 111]), view(OPEN, "path" => [100, 999]),
                view(OPEN, "path" => [100, 110], "expected_path" => []), view(ROOT, "expected_path" => [100, 110])]

    assert_equal %w[target.locked target.not_found target.edit_path_changed target.edit_path_changed],
                 refusals.map { |result| result["code"] }
    assert_equal [@zone], @model.active_path
    assert_equal revision, @session.revision
  end

  def test_a_busy_session_refuses_and_nothing_moves
    @session.feature_state(:probe_deferred) { Struct.new(:pending?).new(true) }

    assert_equal "session.busy", view(OPEN, "path" => [100])["code"]
    assert_equal "session.busy", view(ROOT)["code"]
    assert_nil @model.active_path
  end

  def test_a_locked_copy_or_a_users_tool_refuses_before_any_boundary_runs
    @volume.locked = false
    @model.active_path = [@zone, @space, @volume]
    copy = Sketchup::Group.new(120, @space.entities)
    copy.locked = true
    @model.entities << copy
    revision = @session.revision
    sibling = view(OPEN, "path" => [120])
    @model.select_tool(UserTool.new)
    busy = view(ROOT)

    assert_equal %w[target.locked session.busy], [sibling["code"], busy["code"]]
    refute @volume.locked?, "no boundary ran"
    assert_equal [@zone, @space, @volume], @model.active_path
    assert_equal revision, @session.revision
  end

  def test_the_current_path_reopens_as_unchanged_even_when_a_step_is_locked
    @model.active_path = [@zone, @space, @volume]

    assert_equal({ "path" => [100, 110, 111], "changed" => false }, moved(OPEN, "path" => [100, 110, 111]))
  end

  def test_a_volume_reached_through_another_copy_of_its_space_refuses_with_nothing_locked
    @volume.locked = false
    @zone.entities << Sketchup::Group.new(130, @space.entities)
    @model.active_path = [@zone, @space, @volume]

    assert_equal "target.shared_definition", view(OPEN, "path" => [100, 130, 111])["code"]
    refute @volume.locked?, "no boundary ran"
    assert_equal [@zone, @space, @volume], @model.active_path
  end

  def test_a_copy_of_the_open_volume_beside_it_refuses_with_nothing_locked
    @volume.locked = false
    copy = Sketchup::Group.new(113, @volume.entities)
    @space.entities << copy
    @model.active_path = [@zone, @space, @volume]

    assert_equal "target.shared_definition", view(OPEN, "path" => [100, 110, 113])["code"]
    refute @volume.locked?, "no boundary ran"
    assert_equal({ "path" => [100], "changed" => true }, moved(OPEN, "path" => [100]))
  end

  def test_a_live_component_refuses_before_leaving_an_unprotected_volume
    @volume.locked = false
    live = Sketchup::Group.new(140, Sketchup::Entities.new([]))
    definition = live.definition
    definition.define_singleton_method(:live_component?) { true }
    live.define_singleton_method(:definition) { definition }
    @model.entities << live
    @model.active_path = [@zone, @space, @volume]

    assert_equal "target.wrong_kind", view(OPEN, "path" => [140])["code"]
    refute @volume.locked?, "no boundary ran"
  end

  # SketchUp ignores a return to the root on a Model it is not showing, and honors a deeper path there but
  # reports the change to the shown Model's observers, so every move refuses before the open Volume is
  # protected; Spaces navigation refuses alike. A path equal to the current one still changes nothing.
  def test_moving_the_path_of_a_model_not_shown_refuses_with_nothing_locked
    @volume.locked = false
    @model.active_path = [@zone, @space, @volume]
    other = Sketchup::Model.new
    Sketchup.active_model = other
    revision = @session.revision
    starts = @model.operation_starts.length

    refused = [view(ROOT), view(OPEN, "path" => []), view(OPEN, "path" => [100]),
               view("ph_composer.spaces.context.close")].map { |result| result["code"] }

    assert_equal %w[session.inactive] * 4, refused
    refute @volume.locked?, "no boundary ran"
    assert_equal [@zone, @space, @volume], @model.active_path
    assert_equal revision, @session.revision
    assert_equal starts, @model.operation_starts.length
    assert_equal({ "path" => [100, 110, 111], "changed" => false }, moved(OPEN, "path" => [100, 110, 111]))
  ensure
    Sketchup.active_model = @model
  end

  def test_navigation_declares_the_lock_it_may_trigger
    names = [OPEN, ROOT, "ph_composer.spaces.context.open", "ph_composer.spaces.context.close",
             "ph_composer.spaces.locate"]

    names.each do |name|
      described = API.describe(:name => name)
      assert_equal "view", described.fetch("capability"), name
      assert_match(/protects it again/, described.fetch("side_effects").to_s, name)
    end
    assert_match(/edit path.*unchanged/, API.describe(:name => "ph_composer.zones.faces.locate")["side_effects"])
  end
end
