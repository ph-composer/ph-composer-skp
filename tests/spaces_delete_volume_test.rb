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

  # Only Volumes left outside the selected one count: a nested sibling keeps the Space, a Volume nested inside the
  # selected one goes with it.
  def test_the_only_volume_question_counts_nested_volumes_by_whether_they_survive
    sibling = volume_group(1160, volume_record("N", :number => 2), [floor_face(1161, rectangle(0, 6, 1, 1))])
    @living.entities << Sketchup::Group.new(1150, Sketchup::Entities.new([sibling]))
    @model.active_path = [@zone_a, @living]
    select(@living.entities.to_a.first)
    refute MENU.selected(@model).only, "a sibling Volume in a plain Group stays"

    bath_volume = @zone_a.entities.to_a[1].entities.to_a.first
    inner = floor_face(1261, rectangle(4, 4, 1, 1))
    bath_volume.entities << volume_group(1260, volume_record("C", :number => 2), [inner])
    @model.active_path = [@zone_a, @zone_a.entities.to_a[1]]
    select(bath_volume)
    assert MENU.selected(@model).only, "a Volume nested in the selected one goes with it"

    inner = space_group(1170, space_record("P", :number => "9"),
                        [volume_group(1180, volume_record("P"), [floor_face(1181, rectangle(0, 8, 1, 1))])])
    @living.entities.to_a.last.entities.clear!
    @living.entities << inner
    @model.active_path = [@zone_a, @living]
    select(@living.entities.to_a.first)
    assert MENU.selected(@model).only, "a nested Space's Volume is not the outer Space's"
  end

  # Every Spaces record below the Volume is erased with it, so each is reported and checked for references.
  def test_a_record_nested_below_the_volume_is_reported_deleted
    nested = floor_face(1331, rectangle(9, 9, 1, 1), segment_record("K"))
    @hall_second.entities << Sketchup::Group.new(1330, Sketchup::Entities.new([nested]))
    @model.active_path = [@zone_a, @hall]
    deleted = invoke("volumes.delete", "volume" => volume_reference(1320))
    assert_equal "completed", deleted["status"], deleted.inspect
    assert_includes deleted.fetch("affected").map { |row| row["id"] }, "fsg_#{'K' * 12}"
  end

  # A surviving record that names a record below the Volume refuses the delete, and nothing is erased.
  def test_a_reference_to_a_record_below_the_volume_refuses_and_writes_nothing
    nested = floor_face(1331, rectangle(9, 9, 1, 1), segment_record("K"))
    @hall_second.entities << Sketchup::Group.new(1330, Sketchup::Entities.new([nested]))
    links = PhComposer::Records::Extension.new(
      :namespace => "test.spaces.links", :schema_version => 1,
      :references => [{ "path" => "$.floor", "target_kind" => SPACES::FLOOR_SEGMENT_KIND, "cardinality" => "one" }]
    )
    envelope = links.envelope("floor" => "fsg_#{'K' * 12}")
    SPACES::SPACE_STORE.write(@living, SPACES::SPACE_STORE.read(@living)
                                             .merge("extension_data" => { "outside.unavailable" => envelope }))
    @model.active_path = [@zone_a, @hall]
    operations = @model.operations.length

    refused = invoke("volumes.delete", "volume" => volume_reference(1320))

    assert_equal %w[refused reference.in_use none], refused.values_at("status", "code", "effect")
    assert_equal operations, @model.operations.length
    assert_equal [1310, 1320], @hall.entities.to_a.map(&:persistent_id)
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
