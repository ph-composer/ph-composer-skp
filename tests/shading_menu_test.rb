# frozen_string_literal: true

require_relative "test_helper"

# Set as Shading and Clear Shading: when each is offered for a selection shape, that the handler goes through
# the public assign and clear actions in one Undo step, what the notice and status bar say, the refusal path,
# and that a raising availability test leaves the rest of the menu built.
class ShadingMenuTest < PhComposerTestCase
  SH = PhComposer::Shading
  STORE = SH::Mark::STORE
  ASSIGN = "ph_composer.shading.assign_menu"
  CLEAR = "ph_composer.shading.clear_menu"

  def setup
    super
    PhComposer.compose unless PhComposer::Registry.installed?(SH::FEATURE_ID)
    @model = Sketchup.active_model
    @session = PhComposer::Sessions.for(@model)
    @face = Sketchup::Face.new(5)
    @edge = Sketchup::Edge.new(6, Geom::Point3d.new(0, 0, 0), Geom::Point3d.new(1, 0, 0))
    @inner = Sketchup::Face.new(21)
    @group = Sketchup::Group.new(20, Sketchup::Entities.new([@inner]))
    @zone = zone(100, [Sketchup::Face.new(101)])
    pane = Sketchup::ComponentDefinition.new(Sketchup::Entities.new([Sketchup::Face.new(91)]))
    pane.behavior.cuts_opening = true
    @unit = Sketchup::ComponentInstance.new(90, pane)
    [@face, Sketchup::Face.new(8), @edge, @group, @zone, @unit].each { |entity| @model.entities << entity }
  end

  def test_each_selection_shape_offers_the_right_items
    assert_equal [true, false], offered(@face, @model.entities.to_a[1]), "loose Faces"
    assert_equal [true, false], offered(@group), "closed Group"
    @model.active_path = [@group]
    assert_equal [true, false], offered(@inner), "Face in an open Group"
    @model.active_path = nil
    assert_equal [false, false], offered(@edge), "Edges only"
    assert_equal [false, false], offered(@zone), "Zone Group"
    @model.active_path = [@unit]
    assert_equal [false, false], offered(@unit.definition.entities.to_a.first), "pane Face"
    @model.active_path = nil

    STORE.write(@group, "schema_version" => 1)
    assert_equal [false, true], offered(@group), "marked Group"
    assert_equal [true, true], offered(@group, @face), "marked Group and an unmarked Face"
    assert_empty @model.operations
  end

  def test_offered_items_sit_directly_in_the_ph_composer_context_menu
    select(@face)
    menus = PhComposer::Commands.install_feature_menus(UI::Menu.new("Context"), :contextual => true)
    labels = menus.fetch(PhComposer::EXTENSION_NAME).entries.map { |entry| entry.is_a?(Array) ? entry.first : entry }

    assert_includes labels, "Set as Shading"
    refute_includes labels, "Clear Shading"
  end

  def test_both_items_sit_in_the_extensions_menu_whatever_is_selected
    select(@edge)
    menus = PhComposer::Commands.install_feature_menus(UI::Menu.new("Extensions"))
    labels = menus.fetch(PhComposer::EXTENSION_NAME).entries.map { |entry| entry.is_a?(Array) ? entry.first : entry }

    assert_includes labels, "Set as Shading"
    assert_includes labels, "Clear Shading"
  end

  def test_a_marked_selection_offers_clear_shading_in_the_context_menu
    STORE.write(@face, "schema_version" => 1)
    select(@face)
    menus = PhComposer::Commands.install_feature_menus(UI::Menu.new("Context"), :contextual => true)
    labels = menus.fetch(PhComposer::EXTENSION_NAME).entries.map { |entry| entry.is_a?(Array) ? entry.first : entry }

    assert_includes labels, "Clear Shading"
    refute_includes labels, "Set as Shading"
  end

  # Over the target limit the read refuses; the items stay offered so the handler can say why.
  def test_a_selection_over_the_limit_is_offered_and_explained_without_writing
    faces = Array.new(SH::Mark::TARGET_LIMIT + 1) { |index| Sketchup::Face.new(1000 + index) }
    faces.each { |face| @model.entities << face }
    select(*faces)

    assert_equal [true, true], offered(*faces)
    handler(ASSIGN).call(@session)
    assert_match(/at most #{SH::Mark::TARGET_LIMIT} entities/, Sketchup.status_texts.last)
    assert_empty @model.operations
  end

  def test_set_then_clear_from_the_menu_is_one_undo_step_each_and_says_what_was_ignored
    select(@face, @group, @edge)
    result = handler(ASSIGN).call(@session)

    assert_equal "completed", result.fetch("status")
    assert STORE.marks?(@face)
    assert STORE.marks?(@group)
    assert_equal [["Set as Shading", true, :committed]], @model.operations
    assert_equal "Set as Shading: Tagged 2 entities as shading. 1 other selected entity was ignored.",
                 Sketchup.status_texts.last
    refute PhComposer::Panel.open?

    handler(CLEAR).call(@session)
    refute STORE.marks?(@face)
    assert_equal 2, @model.operations.length
    assert @model.undo
    assert STORE.marks?(@model.entities.to_a.find { |entity| entity.persistent_id == 5 })
  end

  def test_clearing_a_face_that_stays_shading_through_its_group_names_the_group
    @group.name = "Fin"
    STORE.write(@group, "schema_version" => 1)
    STORE.write(@inner, "schema_version" => 1)
    @model.active_path = [@group]
    select(@inner)
    notices = capture_notices { handler(CLEAR).call(@session) }

    assert_equal 1, @model.operations.length
    message = Sketchup.status_texts.last
    assert_match(/\AClear Shading: Cleared shading from 1 entity\. Still shading: The entity is shading through "Fin"/,
                 message)
    assert_equal [[message, :warning]], notices
  end

  def test_a_mixed_selection_tags_what_it_can_and_names_what_it_left_out
    STORE.write(@face, "schema_version" => 1)
    select(@face, @group, @zone)
    notices = capture_notices { handler(ASSIGN).call(@session) }

    assert STORE.marks?(@group)
    refute STORE.marks?(@zone)
    assert_equal 1, @model.operations.length
    message = Sketchup.status_texts.last
    assert_equal [[message, :warning]], notices
    assert_match(/Tagged 1 entity as shading\. 1 entity was already shading\./, message)
    assert_match(/Left out 1 entity\. The Group is a Zone or holds one/, message)
  end

  def test_a_selection_nothing_can_take_refuses_through_the_action_and_writes_nothing
    select(@zone)
    result = handler(ASSIGN).call(@session)

    assert_equal %w[refused shading.zone_target none], result.values_at("status", "code", "effect")
    assert_equal "Set as Shading: Nothing was written. Left out 1 entity. The Group is a Zone or holds one. A " \
                 "whole Zone as shading is not supported.", Sketchup.status_texts.last

    locked = Sketchup::Group.new(30, Sketchup::Entities.new([Sketchup::Face.new(31)]), :locked => true)
    @model.entities << locked
    select(@zone, locked, @edge)
    handler(ASSIGN).call(@session)
    message = Sketchup.status_texts.last
    assert message.start_with?("Set as Shading: Nothing was written. Left out 2 entities. ")
    assert_match(/The Group is a Zone or holds one/, message)
    assert_match(/The Group or a Group above it is locked/, message)
    assert message.end_with?("1 other selected entity was ignored.")
    assert_empty @model.operations
    assert_empty @model.operations
    refute STORE.marks?(@zone)
  end

  # Extensions > PH-Composer offers both items whatever is selected, so the handler explains an empty choice.
  def test_nothing_usable_selected_is_reported_without_invoking
    select(@edge)
    PhComposer::API.stub(:invoke, ->(**_args) { flunk "An empty selection must not invoke an action." }) do
      assert_equal "refused", handler(CLEAR).call(@session).fetch("status")
    end

    assert_equal "Select Faces, Groups or components first. Nothing was written.", Sketchup.status_texts.last
    assert_empty @model.operations
  end

  def test_the_read_revision_goes_to_the_action
    select(@face)
    invocation = nil
    invoke = lambda do |**args|
      invocation = args
      { "status" => "completed", "message" => "Done.",
        "value" => { "assigned" => [{ "entity_path" => [5] }], "unchanged" => [], "left_out" => [] } }
    end
    PhComposer::API.stub(:invoke, invoke) { handler(ASSIGN).call(@session) }

    assert_equal "ph_composer.shading.assign", invocation.fetch(:name)
    assert_equal({ "targets" => [{ "entity_path" => [5] }] }, invocation.fetch(:params))
    assert_equal({ "sequence" => 1, "expected_revision" => @session.revision }, invocation.fetch(:request))
  end

  def test_a_raising_availability_test_leaves_the_rest_of_the_menu_built
    select(@group)
    raising = ->(*_args) { raise "selection read failed" }
    menus = SH::Menu.stub(:offered?, raising) do
      PhComposer::Commands.install_feature_menus(UI::Menu.new("Context"), :contextual => true)
    end
    labels = menus.fetch(PhComposer::EXTENSION_NAME).entries.map { |entry| entry.is_a?(Array) ? entry.first : entry }

    refute_includes labels, "Set as Shading"
    assert_includes labels, "Make Zone"
  end

  private

  def zone(persistent_id, children)
    group = Sketchup::Group.new(persistent_id, Sketchup::Entities.new(children))
    PhComposer::Zones::ZONE_STORE.write(group,
                                        "id" => "zon_#{persistent_id.to_s.rjust(12, 'A')}", "schema_version" => 1,
                                        "name" => "Zone A", "building_segment" => "Building", "level" => nil,
                                        "ground_depth_mm" => 0.0, "user_data" => {}, "extension_data" => {})
    group
  end

  def select(*entities)
    @model.selection.clear
    entities.each { |entity| @model.selection.add(entity) }
  end

  def offered(*entities)
    select(*entities)
    [ASSIGN, CLEAR].map { |name| declaration(name).available.call(read(declaration(name))) }
  end

  def declaration(name)
    PhComposer::Registry.current.menu_items.fetch(name)
  end

  def handler(name)
    declaration(name).handler
  end

  def read(item)
    PhComposer::HandlerRequest.for(@session, :owner => item.owner, :name => item.name)
  end

  def capture_notices
    notices = []
    @session.stub(:notice, ->(message, tone:) { notices << [message, tone] }) { yield }
    notices
  end
end
