# frozen_string_literal: true

require_relative "test_helper"
require_relative "support/space_fixtures"

# Deleting a Volume: volumes.delete erases it with its floor Faces in one Undo step, Delete Volume reaches it from
# SketchUp's context menu on one Volume in an open Space, and a Space's only Volume offers Delete Space instead.
class SpacesDeleteVolumeTest < PhComposerTestCase
  include SpaceFixtures

  API = PhComposer::API
  MENU = PhComposer::Spaces::DeleteVolumeMenu
  SPACES = PhComposer::Spaces

  def setup
    super
    @model = Sketchup.active_model
    @session = PhComposer::Sessions.for(@model)
    @notices = []
    PhComposer::Sessions.on_notice { |_session, message, tone| @notices << [message, tone] }
    reference_model
    @zone_a = @model.entities.to_a.first
    @living, _bath, @hall = @zone_a.entities.to_a
    @hall_volume, @hall_second = @hall.entities.to_a
  end

  def test_offered_only_on_one_volume_in_an_open_space
    @model.active_path = [@zone_a, @hall]
    select(@hall_second)
    assert offered?, "one Volume"
    select(@hall_volume, @hall_second)
    refute offered?, "two Volumes"
    select
    refute offered?, "nothing selected"
    @model.active_path = [@zone_a]
    select(@hall)
    refute offered?, "a Space"
    @model.active_path = [@zone_a, @hall, @hall_volume]
    select(*@hall_volume.entities.to_a)
    refute offered?, "a Floor Segment Face in the open Volume"
  end

  def test_the_menu_erases_the_volume_and_its_faces_in_one_undo_step
    @model.active_path = [@zone_a, @hall]
    select(@hall_second)
    operations = @model.operations.length

    outcome = client.run

    assert_equal "completed", outcome.fetch("status"), outcome.inspect
    assert_equal operations + 1, @model.operations.length
    assert_equal :success, @notices.last.last
    assert_equal [1310], @hall.entities.to_a.map(&:persistent_id), "the Volume Group and its Faces are gone"
    kinds = outcome.fetch("affected").map { |row| SPACES::KINDS.fetch(row["kind"]).label }
    assert_equal ["Volume", "Floor Segment"], kinds, "the Volume and its Floor Segment are reported deleted"
    assert_empty UI.messages, "a Volume beside another goes without a question"
    assert @model.undo
    restored = group(1000, 1300, 1320)
    assert restored.locked?, "one Undo brings it back protected"
    assert_equal 1321, restored.entities.to_a.first.persistent_id
    assert_equal 2, hall_row.fetch("volumes").length
    assert_equal [0.0], hall_row.dig("volumes", 1, "floor_segments").map { |row| row.dig("values", "weighting_factor") }
  end

  def test_the_only_volume_offers_delete_space_and_answering_no_writes_nothing
    @model.active_path = [@zone_a, @living]
    select(@living.entities.to_a.first)
    UI.messagebox_result = IDNO
    operations = @model.operations.length

    assert_nil client.run
    assert_equal "Volume 1 is the only Volume of 101 Living. Delete the Space instead?\n\n101 Living and " \
                 "everything in it will be erased. One Undo brings it back.", UI.messages.last
    assert_equal operations, @model.operations.length

    UI.messagebox_result = IDYES
    outcome = client.run
    assert_equal %w[completed ok], outcome.values_at("status", "code"), outcome.inspect
    assert_equal operations + 1, @model.operations.length
    assert_equal [1200, 1300], @zone_a.entities.to_a.map(&:persistent_id), "the Space goes, not just its Volume"
    assert @model.undo
    assert_equal [1100, 1200, 1300], group(1000).entities.to_a.map(&:persistent_id)
  end

  # A script may empty a Space; the Space then reads space.empty until it is fixed.
  def test_the_operation_works_from_inside_the_volume_and_volumes_remove_still_keeps_the_faces
    @model.active_path = [@zone_a, @hall, @hall_second]
    deleted = invoke("volumes.delete", "volume" => volume_reference(1320))
    assert_equal "completed", deleted["status"], deleted.inspect
    assert_equal [1000, 1300], Array(@model.active_path).map(&:persistent_id), "the open Volume closes to its Space"
    assert_equal [1310], @hall.entities.to_a.map(&:persistent_id)
    assert_empty hall_row.fetch("findings")

    removed = invoke("volumes.remove", "volume" => volume_reference(1310))
    assert_equal "completed", removed["status"], removed.inspect
    assert_equal [1311], @hall.entities.to_a.map(&:persistent_id), "remove explodes the Volume and keeps its Face"
    assert_equal ["space.empty"], hall_row.fetch("findings").map { |finding| finding["code"] }

    @model.active_path = [@zone_a, @living]
    living = { "volume_id" => SPACES::VOLUME_STORE.read(@living.entities.to_a.first).fetch("id"),
               "entity_path" => [1000, 1100, 1110] }
    assert_equal "completed", invoke("volumes.delete", "volume" => living)["status"]
    assert_equal ["space.empty"], row("101").fetch("findings").map { |finding| finding["code"] }
  end

  private

  def select(*entities)
    @model.selection.clear
    entities.each { |entity| @model.selection.add(entity) }
  end

  def offered?
    menus = PhComposer::Commands.install_feature_menus(UI::Menu.new("Context"), :contextual => true)
    menus.fetch(PhComposer::EXTENSION_NAME, UI::Menu.new("")).entries.grep(Array).map(&:first).include?(MENU::LABEL)
  end

  # The Group at a persistent-id path, found again: an Undo restores the Model's entities as new objects.
  def group(*ids)
    ids.reduce(@model) { |parent, id| parent.entities.to_a.find { |entity| entity.persistent_id == id } }
  end

  def client
    MENU.client(@session)
  end

  def volume_reference(id)
    { "volume_id" => SPACES::VOLUME_STORE.read(@hall.entities.to_a.find { |entity| entity.persistent_id == id })
                                         .fetch("id"),
      "entity_path" => [1000, 1300, id] }
  end

  def invoke(name, params)
    context = API.connect(:session_id => @session.id)
    API.invoke(:context => context, :name => "ph_composer.spaces.#{name}", :params => params,
               :request => { "sequence" => 1, "expected_revision" => @session.revision })
  end

  def hall_row
    row("103")
  end

  def row(number)
    context = API.connect(:session_id => @session.id)
    API.query(:context => context, :name => "ph_composer.spaces.all").dig("value", "spaces")
       .find { |found| found.dig("values", "number") == number }
  end
end
