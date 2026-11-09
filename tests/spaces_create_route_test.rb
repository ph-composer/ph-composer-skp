# frozen_string_literal: true

require_relative "test_helper"
require_relative "support/space_fixtures"

# Create Space from SketchUp's context menu: offered on a Face selection or on Mark floor's offer, in any edit
# context, and handing the panel a review of what `create_preview` accepts and leaves out and which Zone it
# preselects, which the panel confirms with `create` at the review's revision.
class SpacesCreateRouteTest < PhComposerTestCase
  include SpaceFixtures

  API = PhComposer::API
  ROUTE = PhComposer::Spaces::CreateRoute
  ZONE = { "zone_id" => "zon_AAAAAAAAAAAA", "zone_path" => [1000] }.freeze

  def setup
    super
    @model = Sketchup.active_model
    @session = PhComposer::Sessions.for(@model)
    @context = API.connect(:session_id => @session.id)
    @notices = []
    PhComposer::Sessions.on_notice { |_session, message, tone| @notices << [message, tone] }
    @loose = floor_face(1200, rectangle(0, 0, 2, 2))
    @other = floor_face(1210, rectangle(5, 0, 2, 2))
    @wall = floor_face(1300, rectangle(9, 0, 1, 1))
    @zone = zone_group(1000, "A", [@loose, @other, @wall])
    @model.entities << @zone
    classify(@wall)
  end

  def test_offered_on_a_face_selection_or_mark_floors_offer_and_not_otherwise
    refute ROUTE.available?(@session)
    @model.selection.add(@loose)
    assert ROUTE.available?(@session)
    @model.selection.clear
    tool = PhComposer::Spaces.mark_tool(@session)
    tool.start(1.0)
    @model.active_path = [@zone]
    @model.active_view.picks[[100, 100]] = [@loose]
    tool.onLButtonDown(0, 100, 100, @model.active_view)
    tool.onLButtonUp(0, 100, 100, @model.active_view)
    assert ROUTE.available?(@session), "the tool's offer"
    menus = PhComposer::Commands.install_feature_menus(UI::Menu.new("Context"), :contextual => true)
    assert_includes menu_labels(menus), ROUTE::LABEL
    tool.onLButtonDown(0, 200, 200, @model.active_view)
    assert_empty tool.offered, "the next gesture drops the offer"
  end

  def test_with_no_faces_it_says_a_space_is_a_floor_surface_and_writes_nothing
    operations = @model.operations.length

    assert_nil ROUTE.client(@session).run

    assert_equal operations, @model.operations.length
    assert_nil review.fetch("token")
    assert_equal [ROUTE::NO_FACES, :warning], @notices.last
    assert_match(/floor surface plus a height: select the floor surface as Faces/, Sketchup.status_texts.last)
    assert_equal [ROUTE::NO_FACES], UI.notifications.map(&:message), "the refusal shows in SketchUp"
  end

  def test_at_the_root_it_reviews_a_loose_outline_preselecting_the_zone_that_holds_it
    outline = floor_face(1500, rectangle(0.5, 0.5, 1, 1))
    @model.entities << outline
    @model.selection.add(outline)
    panel = Struct.new(:proc).new(-> {})

    result = PhComposer::Commands.stub(:open_panel, -> { panel }) { ROUTE.client(@session).run }

    assert_equal "completed", result.fetch("status"), result.inspect
    pending = review
    assert_equal [[1500]], pending.fetch("accepted")
    assert_equal ZONE, pending.fetch("zone")
    assert_equal [ZONE.merge("name" => "Zone A")], pending.fetch("zones")
    assert_in_delta 2.5, pending.fetch("height_m"), 1e-9
  end

  def test_inside_a_zone_it_reviews_the_selection_and_create_makes_the_space_in_one_undo_step
    @model.active_path = [@zone]
    [@loose, @wall].each { |face| @model.selection.add(face) }
    operations = @model.operations.length
    opened = 0
    panel = Struct.new(:proc).new(-> { opened += 1 })

    result = PhComposer::Commands.stub(:open_panel, -> { panel }) { ROUTE.client(@session).run }

    assert_equal "completed", result.fetch("status"), result.inspect
    assert_equal 1, opened, "the panel opens on the review"
    pending = review
    assert_equal ZONE, pending.fetch("zone")
    assert_equal [[1000, 1200]], pending.fetch("accepted")
    assert_equal [[1000, 1300]], pending.fetch("left_out").map { |row| row.fetch("path") }
    assert_equal operations, @model.operations.length, "the review writes nothing"

    created = API.invoke(:context => @context, :name => "ph_composer.spaces.create",
                         :params => { "zone" => pending.fetch("zone"), "faces" => pending.fetch("accepted"),
                                      "name" => "Living" },
                         :request => { "sequence" => 2, "expected_revision" => pending.fetch("revision") })
    assert_equal "completed", created.fetch("status"), created.inspect
    assert_equal operations + 1, @model.operations.length
  end

  def test_a_stale_revision_refuses_and_only_the_reviews_own_token_closes_it
    @model.active_path = [@zone]
    faces = [[1000, 1200]]
    stale = view("open", "faces" => faces, "revision" => @session.revision - 1)
    assert_equal %w[refused revision.stale], stale.values_at("status", "code")

    token = view("open", "faces" => faces, "revision" => @session.revision).dig("value", "token")
    refute_nil view("close", "token" => "another").dig("value", "token")
    assert_nil view("close", "token" => token).dig("value", "token")
  end

  def test_a_new_review_replaces_one_still_open
    @model.active_path = [@zone]
    faces = [[1000, 1200]]
    first = view("open", "faces" => faces, "revision" => @session.revision).dig("value", "token")
    second = view("open", "faces" => faces, "revision" => @session.revision).dig("value", "token")
    refute_equal first, second
    assert_equal second, review.fetch("token")
  end

  private

  def classify(face)
    result = API.invoke(:context => @context, :name => "ph_composer.zones.faces.classify",
                        :params => { "faces" => [ZONE.merge("entity_path" => [face.persistent_id], "entity_id" => nil)],
                                     "intent" => { "face_type" => { "mode" => "set", "value" => "Wall" } },
                                     "expected_values" => {} },
                        :request => { "sequence" => 1, "expected_revision" => @session.revision })
    assert_equal "completed", result.fetch("status"), result.inspect
  end

  def view(command, params)
    API.view(:context => @context, :name => "ph_composer.spaces.create_review.#{command}", :params => params)
  end

  def review
    API.query(:context => @context, :name => "ph_composer.spaces.create_review.state").fetch("value")
  end

  def menu_labels(menus)
    menus.values.flat_map { |menu| menu.entries.map { |entry| entry.is_a?(Array) ? entry.first : entry } }
  end
end
