# frozen_string_literal: true

require_relative "test_helper"
require_relative "support/space_fixtures"

# Create Space from SketchUp's context menu: offered on a Face selection or on Mark floor's offer, refusing
# with the reason outside a Zone's edit context, and handing the panel a review of what `create_preview`
# accepts and leaves out, which the panel confirms with `create` at the review's revision.
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
    @model.active_view.picks[[100, 100]] = [@zone, @loose]
    tool.onLButtonDown(0, 100, 100, @model.active_view)
    tool.onLButtonUp(0, 100, 100, @model.active_view)
    assert ROUTE.available?(@session), "the tool's offer"
    menus = PhComposer::Commands.install_feature_menus(UI::Menu.new("Context"), :contextual => true)
    assert_includes menu_labels(menus), ROUTE::LABEL
    tool.onLButtonDown(0, 200, 200, @model.active_view)
    assert_empty tool.offered, "the next gesture drops the offer"
  end

  def test_outside_a_zones_edit_context_it_says_why_and_writes_nothing
    @model.selection.add(@loose)
    operations = @model.operations.length

    assert_nil ROUTE.client(@session).run

    assert_equal operations, @model.operations.length
    assert_nil review.fetch("token")
    assert_equal [ROUTE::NO_ZONE, :warning], @notices.last
    assert_match(/open the Zone's edit context/, Sketchup.status_texts.last)
    assert_equal [ROUTE::NO_ZONE], UI.notifications.map(&:message), "the refusal shows in SketchUp"
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
    assert_equal "Zone A", pending.fetch("zone_name")
    assert_equal [[1200]], pending.fetch("accepted").map { |face| face.fetch("entity_path") }
    assert_equal [[1300]], pending.fetch("left_out").map { |row| row.dig("reference", "entity_path") }
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
    faces = [ZONE.merge("entity_path" => [1200], "entity_id" => nil)]
    stale = view("open", "zone" => ZONE, "faces" => faces, "revision" => @session.revision - 1)
    assert_equal %w[refused revision.stale], stale.values_at("status", "code")

    token = view("open", "zone" => ZONE, "faces" => faces, "revision" => @session.revision).dig("value", "token")
    refute_nil view("close", "token" => "another").dig("value", "token")
    assert_nil view("close", "token" => token).dig("value", "token")
  end

  def test_a_new_review_replaces_one_still_open
    @model.active_path = [@zone]
    faces = [ZONE.merge("entity_path" => [1200], "entity_id" => nil)]
    first = view("open", "zone" => ZONE, "faces" => faces, "revision" => @session.revision).dig("value", "token")
    second = view("open", "zone" => ZONE, "faces" => faces, "revision" => @session.revision).dig("value", "token")
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
