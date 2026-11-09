# frozen_string_literal: true

require_relative "test_helper"
require_relative "support/space_fixtures"

# The collection-copy contract (context/CONTRACTS.md, "Space membership"; W6-10): a plain Group copied
# whole with Zones and Spaces gives every copied Space a new id, and a copied Space's Zone reference
# follows to the copied Zone only when that Zone came in the same copy.
class SpacesCollectionCopyTest < PhComposerTestCase
  include SpaceFixtures

  API = PhComposer::API

  def setup
    super
    @model = Sketchup.active_model
    @session = PhComposer::Sessions.for(@model)
    @context = API.connect(:session_id => @session.id)
    @session.notices = @notices = [] if @session.respond_to?(:notices=)
    @zone_a = zone_group(1100, "A", [wall(1110, 0)])
    @zone_b = zone_group(1200, "B", [wall(1210, 10)])
    @zone_stay = zone_group(9000, "C", [wall(9010, 20)])
    @hall = space("H", 1300, "zon_AAAAAAAAAAAA", :name => "Hall")
    @bath = space("B", 1400, "zon_BBBBBBBBBBBB", :name => "Bath")
    @stayed = space("K", 1500, "zon_CCCCCCCCCCCC", :name => "Kitchen")
    @storey = Sketchup::Group.new(1000, Sketchup::Entities.new([@zone_a, @zone_b, @hall, @bath, @stayed]))
    @model.entities << @storey << @zone_stay
    treat_duplicates_as_existing(@model)
  end

  def wall(id, offset)
    floor_face(id, rectangle(offset, 0, 2, 3))
  end

  def space(letter, persistent_id, zone_id, name: "")
    record = space_record(letter, :number => "1", :name => name).merge("zone_id" => zone_id)
    volume = volume_group(persistent_id + 1, volume_record(letter),
                          [floor_face(persistent_id + 2, rectangle(0, 0, 2, 2), segment_record(letter))])
    space_group(persistent_id, record, [volume])
  end

  def copy_natively(group, persistent_id)
    copy = Sketchup::Group.new(persistent_id, group.entities, {}, :transformation => group.transformation)
    Array(group.attribute_dictionaries).each do |dictionary|
      dictionary.each { |key, value| copy.set_attribute(dictionary.name, key, value) }
    end
    @model.start_operation("Copy")
    @model.entities << copy
    @model.commit_operation
    copy
  end

  def spaces_under(group_id)
    API.query(:context => @context, :name => "ph_composer.spaces.all").dig("value", "spaces")
       .select { |row| row.dig("reference", "entity_path").first == group_id }
  end

  def zone_id_at(storey, index)
    ZONES::ZONE_STORE.read(storey.entities.to_a.select { |entity| ZONES::ZONE_STORE.read(entity) }[index])["id"]
  end

  def test_a_copied_storey_gives_spaces_new_ids_hosted_in_the_copied_zones
    copy = copy_natively(@storey, 5000)
    UI.run_timers

    originals = spaces_under(1000).sort_by { |row| row["id"] }
    copied = spaces_under(5000).sort_by { |row| row.dig("reference", "entity_path") }
    assert_equal 3, copied.length
    assert_empty copied.map { |row| row["id"] } & originals.map { |row| row["id"] }
    assert_equal %w[found found found], copied.map { |row| row["state"] }
    new_a = zone_id_at(copy, 0)
    new_b = zone_id_at(copy, 1)
    refute_equal "zon_AAAAAAAAAAAA", new_a
    by_name = copied.to_h { |row| [row.dig("values", "name"), row.dig("values", "zone_id")] }
    assert_equal({ "Hall" => new_a, "Bath" => new_b, "Kitchen" => "zon_CCCCCCCCCCCC" }, by_name,
                 "each copied Space follows its own copied Zone; the one whose Zone stayed keeps its reference")
    assert_equal({ "zone_id" => new_a, "zone_path" => [5000, copy.entities.to_a.first.persistent_id] },
                 copied.find { |row| row.dig("values", "name") == "Hall" }["zone"])
    assert_equal %w[zon_AAAAAAAAAAAA zon_BBBBBBBBBBBB zon_CCCCCCCCCCCC],
                 originals.map { |row| row.dig("values", "zone_id") }.sort
    assert_equal %w[found found found], originals.map { |row| row["state"] }
  end

  def test_an_array_copy_hosts_each_copys_spaces_in_its_own_zone
    first = copy_natively(@storey, 5000)
    second = copy_natively(@storey, 6000)
    UI.run_timers

    [first, second].each do |copy|
      new_a = zone_id_at(copy, 0)
      hosted = spaces_under(copy.persistent_id).find { |row| row.dig("values", "name") == "Hall" }
      assert_equal new_a, hosted.dig("values", "zone_id")
    end
    refute_equal zone_id_at(first, 0), zone_id_at(second, 0)
  end

  def test_a_zone_copied_alone_inside_a_storey_copies_no_space_and_retargets_none
    @session.host_event(:transaction_committed)
    copy = Sketchup::Group.new(5100, @zone_a.entities)
    ZONES::ZONE_STORE.write(copy, ZONES::ZONE_STORE.read(@zone_a))
    @storey.entities << copy
    UI.run_timers

    refute_equal "zon_AAAAAAAAAAAA", ZONES::ZONE_STORE.read(copy)["id"]
    assert_equal %w[zon_AAAAAAAAAAAA zon_BBBBBBBBBBBB zon_CCCCCCCCCCCC],
                 spaces_under(1000).map { |row| row.dig("values", "zone_id") }.sort
    assert_equal 3, spaces_under(1000).length, "a copied Zone copies no Space outside it"
  end

  def test_a_space_in_a_component_in_the_copy_keeps_its_reference_and_the_original_is_untouched
    definition = Sketchup::ComponentDefinition.new(Sketchup::Entities.new([space("Q", 1600, "zon_AAAAAAAAAAAA")]))
    @storey.entities << Sketchup::ComponentInstance.new(1650, definition)
    treat_duplicates_as_existing(@model)
    copy_natively(@storey, 5000)
    UI.run_timers

    held = spaces_under(5000).select { |row| row["id"] == "spc_QQQQQQQQQQQQ" }
    assert_equal ["zon_AAAAAAAAAAAA"], held.map { |row| row.dig("values", "zone_id") }
    original = spaces_under(1000).find { |row| row["id"] == "spc_QQQQQQQQQQQQ" }
    assert_equal "zon_AAAAAAAAAAAA", original.dig("values", "zone_id")
  end

  def test_a_space_inside_one_copied_zone_naming_another_does_not_stop_the_batch
    nested = space("N", 1120, "zon_BBBBBBBBBBBB", :name => "Nested")
    @zone_a.entities << nested
    ZONES::STAMP_STORE.write(nested, ZONES::Schema.stamp(ZONES::ZONE_STORE.read(@zone_a)))
    treat_duplicates_as_existing(@model)
    copy = copy_natively(@storey, 5000)
    UI.run_timers

    refute_equal "zon_AAAAAAAAAAAA", zone_id_at(copy, 0)
    refute_equal "zon_BBBBBBBBBBBB", zone_id_at(copy, 1)
    hall = spaces_under(5000).find { |row| row.dig("values", "name") == "Hall" }
    assert_equal zone_id_at(copy, 0), hall.dig("values", "zone_id")
  end

  def test_a_copied_plain_group_of_spaces_alone_keeps_each_reference
    plain = Sketchup::Group.new(2000, Sketchup::Entities.new([space("N", 2100, "zon_AAAAAAAAAAAA")]))
    @model.entities << plain
    treat_duplicates_as_existing(@model)
    copy = copy_natively(plain, 6000)
    UI.run_timers

    row = spaces_under(6000).first
    refute_equal "spc_NNNNNNNNNNNN", row["id"]
    assert_equal "found", row["state"]
    assert_equal "zon_AAAAAAAAAAAA", row.dig("values", "zone_id")
    assert_equal "spc_NNNNNNNNNNNN", spaces_under(2000).first["id"]
    assert_equal copy.persistent_id, row.dig("reference", "entity_path").first
  end

  def test_one_undo_removes_the_copy_and_its_repairs
    copy_natively(@storey, 5000)
    UI.run_timers

    @model.undo
    UI.run_timers
    assert_empty spaces_under(5000)
    assert_equal %w[spc_BBBBBBBBBBBB spc_HHHHHHHHHHHH spc_KKKKKKKKKKKK],
                 spaces_under(1000).map { |row| row["id"] }.sort
  end
end
