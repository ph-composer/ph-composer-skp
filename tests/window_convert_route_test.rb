# frozen_string_literal: true

require_relative "test_helper"
require_relative "support/window_record_fixtures"
require_relative "support/assembly_assignment_fixtures"
require_relative "support/window_convert_fixtures"

# Convert to Window Type from the menus: offered on a Face selection, refusing with the reason when there is
# none, and handing the panel a review the panel confirms with `convert`.
class WindowConvertRouteTest < PhComposerTestCase
  include WindowRecordFixtures
  include AssemblyAssignmentFixtures
  include WindowConvertFixtures

  ROUTE = PhComposer::Windows::Units::ConvertRoute
  API = PhComposer::API

  def setup
    super
    assignment_setup
    PhComposer::Registry.install([W]) unless PhComposer::Registry.installed?(W::FEATURE_ID)
    @next_id = 5000
    @session = PhComposer::Sessions.for(@model)
    @context = API.connect(:session_id => @session.id)
    @notices = []
    PhComposer::Sessions.on_notice { |_session, message, tone| @notices << [message, tone] }
  end

  def run_route
    opened = 0
    panel = Struct.new(:proc).new(-> { opened += 1 })
    result = PhComposer::Commands.stub(:open_panel, -> { panel }) { ROUTE.client(@session).run }
    [result, opened]
  end

  def dialog
    assignment_query("#{ROUTE::PREFIX}.state")
  end

  def menu_labels(menus)
    menus.values.flat_map { |menu| menu.entries.map { |entry| entry.is_a?(Array) ? entry.first : entry } }
  end

  def test_offered_on_a_face_selection_in_the_context_menu_and_not_otherwise
    face = zone_with([ring(2, 1, 1.2, 1.5)]).first
    refute ROUTE.available?(@session)
    @model.selection.add(face)
    assert ROUTE.available?(@session)
    menus = PhComposer::Commands.install_feature_menus(UI::Menu.new("Context"), :contextual => true)
    assert_includes menu_labels(menus), ROUTE::LABEL
  end

  def test_the_extensions_menu_always_lists_the_item
    menus = PhComposer::Commands.install_feature_menus(UI::Menu.new("Extensions"))
    assert_includes menu_labels(menus), ROUTE::LABEL
  end

  def test_a_selection_at_the_model_root_is_named_by_its_own_id
    face = Sketchup::Face.new(next_id)
    @model.entities << face
    @model.selection.add(face)
    run_route
    assert_equal [[[face.persistent_id]]], dialog.fetch("left_out").map { |row| row.fetch("paths") }
  end

  def test_without_a_face_selected_it_says_why_and_writes_nothing
    operations = @model.operations.length
    result, opened = run_route
    assert_nil result
    assert_equal 0, opened
    assert_equal operations, @model.operations.length
    assert_nil dialog.fetch("token")
    assert_equal [ROUTE::NO_FACES, :warning], @notices.last
  end

  def test_it_reviews_the_selection_in_the_open_context_and_convert_replaces_the_rectangle_in_one_undo_step
    face = zone_with([ring(2, 1, 1.2, 1.5)]).first
    @model.active_path = [@group]
    @model.selection.add(face)
    @model.selection.add(@host)
    operations = @model.operations.length

    result, opened = run_route

    assert_equal "completed", result.fetch("status"), result.inspect
    assert_equal 1, opened, "the panel opens on the review"
    pending = dialog
    assert_equal [[path(face)]],
                 pending.fetch("groups").map { |group| group.fetch("sources").map { |row| row.fetch("path") } }
    assert_equal [[[@group.persistent_id, @host.persistent_id]]],
                 pending.fetch("left_out").map { |row| row.fetch("paths") }
    assert_equal operations, @model.operations.length, "the review writes nothing"

    @model.active_path = []
    sources = pending.fetch("groups").first.fetch("sources").map { |row| row.slice("path", "digest") }
    converted = assignment_invoke("ph_composer.windows.units.convert", "groups" => [{ "sources" => sources }])
    assert_equal "completed", converted.fetch("status"), converted.inspect
  end

  def test_a_selection_in_a_nested_context_names_the_whole_path
    face = zone_with([ring(2, 1, 1.2, 1.5)]).first
    outer = Sketchup::Group.new(next_id, Sketchup::Entities.new([@group]))
    @model.entities.delete(@group)
    @model.entities << outer
    @model.active_path = [outer, @group]
    @model.selection.add(face)
    run_route
    listed = dialog.fetch("groups").flat_map { |group| group.fetch("sources").map { |row| row.fetch("path") } } +
             dialog.fetch("left_out").flat_map { |row| row.fetch("paths") }
    assert_equal [[outer.persistent_id, @group.persistent_id, face.persistent_id]], listed
  end

  def test_a_review_is_closed_only_by_its_own_token_and_a_new_one_replaces_it
    face = zone_with([ring(2, 1, 1.2, 1.5)]).first
    @model.active_path = [@group]
    @model.selection.add(face)
    run_route
    first = dialog.fetch("token")
    assert_equal first, API.view(:context => @context, :name => "#{ROUTE::PREFIX}.close",
                                 :params => { "token" => "another" }).dig("value", "token")
    run_route
    refute_equal first, dialog.fetch("token")
    closed = API.view(:context => @context, :name => "#{ROUTE::PREFIX}.close",
                      :params => { "token" => dialog.fetch("token") })
    assert_nil closed.dig("value", "token")
  end

  def test_more_faces_than_a_review_takes_are_refused_with_the_limit
    faces = Array.new(PhComposer::Pages::MAXIMUM_LIMIT + 1) { Sketchup::Face.new(next_id) }
    faces.each { |face| @model.selection.add(face) }
    result, opened = run_route
    assert_nil result
    assert_equal 0, opened
    assert_match(/at most #{PhComposer::Pages::MAXIMUM_LIMIT} Faces/, @notices.last.first)
    assert_nil dialog.fetch("token")
  end
end
