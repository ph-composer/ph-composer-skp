# frozen_string_literal: true

require_relative "test_helper"

# Piping groups through their registered actions (context/CONTRACTS.md, "Hot water piping"): create opens a new
# group at the root in one Undo step, link and unlink are guarded, a group inside a Zone or another Piping group
# refuses, a pasted copy reads copied, and a Hot Water System delete moves or refuses the groups naming it.
class PipingGroupTest < PhComposerTestCase
  API = PhComposer::API
  P = PhComposer::Piping
  STORE = P::Group::STORE
  PREFIX = "ph_composer.piping.groups"
  SYSTEMS = "ph_composer.mechanical.hot_water_systems"

  def setup
    super
    @model = Sketchup.active_model
    @session = PhComposer::Sessions.for(@model)
    @context = API.connect(:session_id => @session.id)
    @sequence = 0
    @hws1 = invoke("#{SYSTEMS}.create", "values" => { "name" => "HWS-1" }).dig("value", "id")
    @hws2 = invoke("#{SYSTEMS}.create", "values" => { "name" => "HWS-2" }).dig("value", "id")
  end

  def test_create_adds_one_open_group_at_the_root_linked_to_the_system_in_one_undo_step
    result = invoke("#{PREFIX}.create", "hot_water_system_id" => @hws1)
    assert_equal "committed", result["effect"], result.inspect
    id = result.dig("value", "group_id")
    assert_match(/\Appg_[A-Za-z0-9]{12}\z/, id)
    groups = @model.entities.to_a.select { |entity| STORE.marks?(entity) }
    assert_equal 1, groups.length
    assert_equal({ "id" => id, "schema_version" => 1, "hot_water_system_id" => @hws1, "user_data" => {},
                   "extension_data" => {} }, STORE.read(groups.first))
    assert_equal [groups.first], Array(@model.active_path)
    row = all.first
    assert_equal [{ "group_id" => id, "group_path" => [groups.first.persistent_id] }, 0, false, [], nil],
                 row.values_at("reference", "pipe_count", "copied", "findings", "write_refusal")
    assert_equal %w[refused target.not_found], invoke("#{PREFIX}.create", "hot_water_system_id" => "hws_ZZZZZZZZZZZZ")
      .values_at("status", "code")
    @model.undo
    assert(@model.entities.to_a.none? { |entity| STORE.marks?(entity) })
  end

  def test_link_and_unlink_are_guarded_and_each_one_undo_step
    group = piping_group(500, "ppg_AAAAAAAAAAAA", @hws1)
    @model.entities << group
    stale = target(group).merge("expected_values" => { "hot_water_system_id" => @hws2 })
    assert_equal %w[refused target.changed none],
                 invoke("#{PREFIX}.link", "targets" => [stale], "hot_water_system_id" => @hws2)
                   .values_at("status", "code", "effect")
    assert_equal "committed", invoke("#{PREFIX}.link", "targets" => [target(group)],
                                                       "hot_water_system_id" => @hws2)["effect"]
    assert_equal @hws2, system_of(500)
    assert_equal "committed", invoke("#{PREFIX}.unlink", "targets" => [target(live(500))])["effect"]
    assert_nil system_of(500)
    @model.undo
    assert_equal @hws2, system_of(500)
  end

  def test_a_group_inside_a_zone_or_another_piping_group_refuses
    in_zone = piping_group(510, "ppg_BBBBBBBBBBBB", @hws1)
    zone = Sketchup::Group.new(100, Sketchup::Entities.new([in_zone]))
    PhComposer::Zones::ZONE_STORE.write(zone, "id" => "zon_AAAAAAAAAAAA", "schema_version" => 1, "name" => "Zone A",
                                              "building_segment" => "Building", "level" => nil,
                                              "ground_depth_mm" => 0.0, "user_data" => {}, "extension_data" => {})
    inner = piping_group(521, "ppg_DDDDDDDDDDDD", @hws1)
    outer = piping_group(520, "ppg_CCCCCCCCCCCC", @hws1, [inner])
    @model.entities << zone << outer
    { [100, 510] => ["ppg_BBBBBBBBBBBB", "piping.group_in_zone"],
      [520, 521] => ["ppg_DDDDDDDDDDDD", "piping.group_nested"] }.each do |path, (id, code)|
      reference = { "group_id" => id, "group_path" => path }
      assert_equal ["refused", code], invoke("#{PREFIX}.link", "targets" => [{ "reference" => reference }],
                                                               "hot_water_system_id" => @hws2)
        .values_at("status", "code")
      assert_equal [code], all.find { |row| row.fetch("path") == path }.fetch("findings")
    end
    assert_equal @hws1, STORE.read(in_zone).fetch("hot_water_system_id")
  end

  def test_a_pasted_copy_reads_copied_and_refuses_a_write_through_its_shared_storage
    group = piping_group(530, "ppg_EEEEEEEEEEEE", @hws1)
    copy = Sketchup::Group.new(531, group.entities)
    STORE.write(copy, STORE.read(group))
    @model.entities << group << copy
    rows = all
    assert_equal [true, true], rows.map { |row| row.fetch("copied") }
    assert_equal ["target.shared_definition"] * 2, rows.map { |row| row.dig("write_refusal", "code") }
    assert_equal %w[refused target.shared_definition],
                 invoke("#{PREFIX}.link", "targets" => [target(copy)], "hot_water_system_id" => @hws2)
                   .values_at("status", "code")
  end

  def test_deleting_a_system_a_group_names_refuses_and_a_replacement_retargets_it_in_one_undo_step
    @model.entities << piping_group(540, "ppg_FFFFFFFFFFFF", @hws1)
    assert_equal %w[refused reference.in_use], invoke("#{SYSTEMS}.delete", "id" => @hws1).values_at("status", "code")
    assert_equal "committed", invoke("#{SYSTEMS}.delete", "id" => @hws1, "replacement_id" => @hws2)["effect"]
    assert_equal @hws2, system_of(540)
    @model.undo
    assert_equal @hws1, system_of(540)
    assert_equal "committed", invoke("#{SYSTEMS}.delete", "id" => @hws1, "replacement_id" => nil)["effect"]
    assert_nil system_of(540)
  end

  def test_a_locked_group_strands_the_system_delete
    @model.entities << piping_group(550, "ppg_GGGGGGGGGGGG", @hws1).tap { |group| group.locked = true }
    refusal = invoke("#{SYSTEMS}.delete", "id" => @hws1, "replacement_id" => @hws2)
    assert_equal %w[refused reference.in_use none], refusal.values_at("status", "code", "effect")
    assert_equal @hws1, system_of(550)
  end

  private

  def piping_group(persistent_id, id, system_id, children = [])
    group = Sketchup::Group.new(persistent_id, Sketchup::Entities.new(children))
    STORE.write(group, P::Group.new_record(id, system_id))
    group
  end

  def target(group)
    record = STORE.read(group)
    { "reference" => { "group_id" => record.fetch("id"), "group_path" => [group.persistent_id] },
      "expected_values" => P::Group.values(record) }
  end

  def live(persistent_id)
    @model.entities.to_a.find { |entity| entity.persistent_id == persistent_id }
  end

  def system_of(persistent_id)
    STORE.read(live(persistent_id)).fetch("hot_water_system_id")
  end

  def all
    result = API.query(:context => @context, :name => "#{PREFIX}.all")
    assert_equal "completed", result["status"], result.inspect
    result.dig("value", "groups")
  end

  def invoke(name, params)
    API.invoke(:context => @context, :name => name, :params => params,
               :request => { "sequence" => @sequence += 1, "expected_revision" => @session.revision })
  end
end
