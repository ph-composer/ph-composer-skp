# frozen_string_literal: true

require_relative "test_helper"
require_relative "support/zone_child_fixture"
require_relative "support/space_fixtures"

# Window Units follow their Zone when it becomes independent: the copy's Units get new ids in the
# Zone's own proposal, by the explicit action and by the copy watcher, alongside a second child
# feature. The copy is made as the host makes one (a second Group over the same contents carrying the
# Zone record), and Make Unique gives every member a new entity, as measured (ZC-01).
class WindowZoneCopyTest < PhComposerTestCase
  include SpaceFixtures

  API = PhComposer::API
  U = PhComposer::Windows::Units
  ZONE_STORE = PhComposer::Zones::ZONE_STORE
  FACE_STORE = PhComposer::Zones::Faces::FACE_STORE
  MAKE_INDEPENDENT = "ph_composer.zones.make_independent"

  def setup
    super
    @model = Sketchup.active_model
    @session = PhComposer::Sessions.for(@model)
    @context = API.connect(:session_id => @session.id)
    @sequence = 0
    @notices = []
    PhComposer::Sessions.on_notice { |_session, message, tone| @notices << [message, tone] }
    @original = zone(300)
    # The fixture builds its Units through the observed entities; that is no paste for HostWatch to answer.
    U::HostWatch.state(@session).reset
  end

  def teardown
    ZoneChildFixture.fail_restore = false
    super
  end

  def test_make_independent_gives_the_copied_units_new_ids_and_keeps_types_anchors_and_originals
    copy = shared_copy(@original, 400)
    before = units_under(@original)

    result = invoke(MAKE_INDEPENDENT, { "zone_path" => [copy.persistent_id] })

    assert_equal %w[completed committed], result.values_at("status", "effect"), result.inspect
    assert_equal before, units_under(@original)
    copied = units_under(copy)
    assert_equal 2, copied.length
    assert_empty copied.map { |row| row.fetch("id") } & before.map { |row| row.fetch("id") }
    assert_equal(before.map { |row| row.slice("window_type_id", "anchor", "user_data") },
                 copied.map { |row| row.slice("window_type_id", "anchor", "user_data") })
    repaired = result.fetch("affected").select { |row| row["kind"] == U::REFERENCE_KIND }
    assert_equal copied.map { |row| row.fetch("id") }.sort, repaired.map { |row| row.fetch("id") }.sort
  end

  def test_the_copy_watcher_makes_both_children_follow_in_one_follow_up
    PhComposer::Registry.install([ZoneChildFixture])
    tag(@original, "tag_000000000001")
    copy = native_copy(@original, 400)

    UI.run_timers

    independent = @model.operation_starts.select { |start| start.first == "Make Zone Independent" }
    assert_equal [["Make Zone Independent", true, false, true]], independent, "one transparent follow-up"
    assert_empty units_under(copy).map { |row| row["id"] } & units_under(@original).map { |row| row["id"] }
    refute_equal tags_under(@original), tags_under(copy)
    assert_equal ["tag_000000000001"], tags_under(@original)
    assert_equal [["Made the copied Zone independent.", :success]], @notices
  end

  def test_a_fault_after_every_child_wrote_restores_the_zone_and_both_children
    PhComposer::Registry.install([ZoneChildFixture, fault_feature])
    tag(@original, "tag_000000000001")
    native_copy(@original, 400)

    UI.run_timers

    copy = zone_groups.last
    assert_equal ZONE_STORE.read(@original).fetch("id"), ZONE_STORE.read(copy).fetch("id"), "the Zone restored"
    assert_equal units_under(@original).map { |row| row["id"] }, units_under(copy).map { |row| row["id"] }
    assert_equal ["tag_000000000001"], tags_under(copy), "the child that wrote is restored"
    assert_equal :warning, @notices.last.last
    refute(@model.operations.any? { |_name, _disable, result| result == :aborted })
  end

  def test_a_child_restore_failure_still_restores_the_others_and_reports_unrestored
    PhComposer::Registry.install([ZoneChildFixture, fault_feature])
    tag(@original, "tag_000000000001")
    native_copy(@original, 400)
    ZoneChildFixture.fail_restore = true

    UI.run_timers

    copy = zone_groups.last
    assert_equal ZONE_STORE.read(@original).fetch("id"), ZONE_STORE.read(copy).fetch("id"), "the Zone restored"
    assert_equal units_under(@original).map { |row| row["id"] }, units_under(copy).map { |row| row["id"] }
    assert_equal :error, @notices.last.last, "the failed child restore is reported"
  end

  # Spaces and Window Units follow one copied Zone in its one step: each child's ids are new in the copy,
  # the Units keep their Types, the Space keeps its number, and the
  # original keeps everything. One Undo takes back all of it and Redo repeats it.
  def test_spaces_and_units_follow_one_copied_zone_together
    space_in(@original)
    copy = shared_copy(@original, 400)
    units = units_under(@original)
    result = invoke(MAKE_INDEPENDENT, { "zone_path" => [copy.persistent_id] })
    assert_equal %w[completed committed], result.values_at("status", "effect"), result.inspect
    assert_equal units, units_under(@original)
    assert_equal space_ids(@original), %w[spc_SSSSSSSSSSSS vol_AAAAAAAAAAAA fsg_AAAAAAAAAAAA]
    assert_empty space_ids(copy) & space_ids(@original)
    assert_empty units_under(copy).map { |row| row["id"] } & units.map { |row| row["id"] }
    assert_equal(units.map { |row| row["window_type_id"] }, units_under(copy).map { |row| row["window_type_id"] })
    repaired = space_ids(copy)
    assert @model.undo
    assert_equal space_ids(@original), space_ids(zone_groups.last)
    assert @model.redo
    assert_equal repaired, space_ids(zone_groups.last)
  end

  # A contributor failing after Spaces and Windows wrote, in the copy watcher's follow-up, restores the
  # Zone, its stamps, the Space records and the Unit records.
  def test_a_fault_after_spaces_and_units_wrote_restores_all_of_them
    PhComposer::Registry.install([fault_feature])
    space_in(@original)
    native_copy(@original, 400)
    UI.run_timers
    copy = zone_groups.last
    zone_id = ZONE_STORE.read(@original).fetch("id")
    assert_equal zone_id, ZONE_STORE.read(copy).fetch("id")
    assert_equal space_ids(@original), space_ids(copy)
    assert_equal units_under(@original).map { |row| row["id"] }, units_under(copy).map { |row| row["id"] }
    assert_equal :warning, @notices.last.last
  end

  def test_copied_extension_references_follow_their_sibling_unit_and_zone_and_keep_the_type
    extension = register_unit_extension
    first, second = @original.entities.to_a.grep(Sketchup::ComponentInstance)
    zone_id = ZONE_STORE.read(@original).fetch("id")
    type_id = invoke("ph_composer.windows.types.create", { "values" => { "name" => "Shared" } }).dig("value", "id")
    payload = { "sibling" => U.read(second).fetch("id"), "zone" => zone_id, "type" => type_id }
    U.write(first, U.read(first).merge("extension_data" => { extension.namespace => extension.envelope(payload) }))
    copy = shared_copy(@original, 400)

    result = invoke(MAKE_INDEPENDENT, { "zone_path" => [copy.persistent_id] })

    assert_equal %w[completed committed], result.values_at("status", "effect"), result.inspect
    copied = units_under(copy)
    remapped = copied.first.dig("extension_data", extension.namespace, "payload")
    assert_equal({ "sibling" => copied.last.fetch("id"), "zone" => ZONE_STORE.read(copy).fetch("id"),
                   "type" => type_id }, remapped)
    assert_equal payload, units_under(@original).first.dig("extension_data", extension.namespace, "payload")
  end

  def test_two_copied_units_sharing_an_id_each_keep_a_self_reference_to_themselves
    extension = register_unit_extension
    first, second = @original.entities.to_a.grep(Sketchup::ComponentInstance)
    record = U.read(first)
    payload = { "sibling" => record.fetch("id"), "zone" => ZONE_STORE.read(@original).fetch("id") }
    shared = record.merge("extension_data" => { extension.namespace => extension.envelope(payload) })
    [first, second].each { |unit| U.write(unit, shared) }
    copy = shared_copy(@original, 400)

    result = invoke(MAKE_INDEPENDENT, { "zone_path" => [copy.persistent_id] })

    assert_equal %w[completed committed], result.values_at("status", "effect"), result.inspect
    units_under(copy).each do |unit|
      assert_equal unit.fetch("id"), unit.dig("extension_data", extension.namespace, "payload", "sibling")
    end
  end

  def test_a_copied_unit_whose_id_is_already_unique_still_follows_its_zone
    extension = register_unit_extension
    first, second = @original.entities.to_a.grep(Sketchup::ComponentInstance)
    payload = { "sibling" => U.read(second).fetch("id"), "zone" => ZONE_STORE.read(@original).fetch("id") }
    U.write(first, U.read(first).merge("extension_data" => { extension.namespace => extension.envelope(payload) }))
    copy = shared_copy(@original, 400)
    copy.make_unique
    @original.entities.erase_entities(@original.entities.to_a.grep(Sketchup::ComponentInstance).first)

    result = invoke(MAKE_INDEPENDENT, { "zone_path" => [copy.persistent_id] })

    assert_equal %w[completed committed], result.values_at("status", "effect"), result.inspect
    copied_first, copied_second = units_under(copy)
    assert_equal({ "sibling" => copied_second.fetch("id"), "zone" => ZONE_STORE.read(copy).fetch("id") },
                 copied_first.dig("extension_data", extension.namespace, "payload"))
  end

  # Two copied Units share an id and a third copied Unit's payload names it, so the payload cannot say
  # which copy it meant. With one holder left outside, keeping the id would point the copy at that Unit.
  def test_a_payload_naming_an_id_two_copied_units_share_refuses_with_one_holder_outside
    payload_naming_a_shared_sibling
    copy = shared_copy(@original, 400)
    copy.make_unique
    @original.entities.erase_entities(@original.entities.to_a.grep(Sketchup::ComponentInstance).first)
    assert_equal 1, units_under(@original).count { |row| row.fetch("id") == "wun_000000000001" }

    assert_refused_as_ambiguous(copy)
  end

  def test_a_payload_naming_an_id_two_copied_units_share_refuses_with_two_holders_outside
    payload_naming_a_shared_sibling
    copy = shared_copy(@original, 400)

    assert_refused_as_ambiguous(copy)
  end

  # Make Zone independent renames only what is held outside the copy. Two copied Units sharing an id
  # nobody outside holds both keep it, still read as a copied identity, and the next Windows repair
  # renames the second by path.
  def test_two_copied_units_sharing_an_id_held_only_inside_both_keep_it_until_the_windows_repair
    copy = shared_copy(@original, 400)
    copy.make_unique
    inside = copy.entities.to_a.grep(Sketchup::ComponentInstance)
    inside.each { |unit| U.write(unit, U.read(inside.first).merge("id" => "wun_000000000009")) }

    result = invoke(MAKE_INDEPENDENT, { "zone_path" => [copy.persistent_id] })

    assert_equal %w[completed committed], result.values_at("status", "effect"), result.inspect
    assert_equal %w[wun_000000000009 wun_000000000009], units_under(copy).map { |row| row.fetch("id") }
    pending = listed_units.select { |row| row.fetch("findings").any? { |f| f["code"] == "window.copy_id_pending" } }
    assert_equal [[copy.persistent_id]] * 2, pending.map { |row| row.dig("reference", "entity_path").first(1) }

    repair = invoke("ph_composer.windows.units.repair_copied_identities",
                    { "units" => pending.map { |row| row.fetch("reference") } })

    assert_equal "committed", repair.fetch("effect"), repair.inspect
    first, second = units_under(copy).map { |row| row.fetch("id") }
    assert_equal "wun_000000000009", first
    refute_equal first, second
  end

  def test_a_failing_unit_restore_still_attempts_every_other_unit
    PhComposer::Registry.install([fault_feature])
    native_copy(@original, 400)
    attempts = []
    original_ids = units_under(@original).map { |row| row["id"] }
    U.singleton_class.send(:alias_method, :__restore_write, :write)
    U.define_singleton_method(:write) do |entity, record|
      if original_ids.include?(record["id"])
        attempts << record["id"]
        raise IOError, "injected" if attempts.length == 1
      end
      __restore_write(entity, record)
    end

    UI.run_timers

    assert_equal original_ids.sort, attempts.sort, "both Units were attempted"
    assert_equal :error, @notices.last.last
  ensure
    U.singleton_class.send(:remove_method, :write)
    U.singleton_class.send(:alias_method, :write, :__restore_write)
    U.singleton_class.send(:remove_method, :__restore_write)
  end

  def test_an_unreadable_unit_outside_the_copy_does_not_block_it
    stray = Sketchup::ComponentInstance.new(900, @model.definitions.add("Stray"), {})
    stray.set_attribute(U::STORE.dictionary, U::STORE.key, "{not json")
    @model.entities << stray
    copy = shared_copy(@original, 400)

    result = invoke(MAKE_INDEPENDENT, { "zone_path" => [copy.persistent_id] })

    assert_equal %w[completed committed], result.values_at("status", "effect"), result.inspect
    assert_empty units_under(copy).map { |row| row["id"] } & units_under(@original).map { |row| row["id"] }
  end

  def test_an_unsupported_extension_payload_on_a_copied_unit_refuses_the_whole_transition
    unit = @original.entities.to_a.grep(Sketchup::ComponentInstance).first
    U.write(unit, U.read(unit).merge("extension_data" => { "outside.vendor" => { "schema_version" => 1,
                                                                                 "payload" => { "x" => 1 } } }))
    copy = shared_copy(@original, 400)
    zone_before = ZONE_STORE.read(copy)

    result = invoke(MAKE_INDEPENDENT, { "zone_path" => [copy.persistent_id] })

    refute_equal "completed", result.fetch("status")
    assert_equal "none", result.fetch("effect")
    assert_equal zone_before, ZONE_STORE.read(copy)
    assert_equal 2, @original.definition.instances.length, "storage is still shared"
  end

  def test_undo_removes_the_unit_ids_with_the_zone_and_redo_repeats_them
    copy = shared_copy(@original, 400)
    invoke(MAKE_INDEPENDENT, { "zone_path" => [copy.persistent_id] })
    repaired = units_in_model.map { |row| row["id"] }

    assert @model.undo
    assert_equal 2, units_in_model.map { |row| row["id"] }.uniq.length, "the copy shares its Unit ids again"
    assert @model.redo
    assert_equal repaired, units_in_model.map { |row| row["id"] }
  end

  private

  # A contributor whose step fails at apply, after every contributor named before it has written.
  class FaultStep
    attr_reader :affected

    def initialize
      @affected = []
    end

    def descriptor
      { "name" => "fault" }
    end

    def apply(_model, _slots)
      raise IOError, "injected after the children wrote"
    end

    def restore; end
  end

  def fault_feature
    Module.new do
      define_singleton_method(:install) do |registry|
        registry.feature("test.zz_fault", :contract_version => 1, :requires => ["ph_composer.zones"])
                .transition_contributor("test.zz_fault.follow", :transition => PhComposer::Zones::TRANSITION) do |
                  _request, proposal, _description|
          proposal.add_step(FaultStep.new, :scopes => [])
          []
        end
      end
    end
  end

  def register_unit_extension
    references = [{ "path" => "$.sibling", "target_kind" => U::REFERENCE_KIND, "cardinality" => "one" },
                  { "path" => "$.zone", "target_kind" => PhComposer::Zones::REFERENCE_KIND, "cardinality" => "one" },
                  { "path" => "$.type", "target_kind" => PhComposer::Windows::TYPE_KIND, "cardinality" => "one" }]
    extension = PhComposer::Records::Extension.new(:namespace => "test.window_copy.links", :schema_version => 1,
                                                   :references => references)
    PhComposer::Registry.install([Module.new do
      define_singleton_method(:install) do |registry|
        registry.feature("test.window_copy", :contract_version => 1, :requires => ["ph_composer.windows"])
                .extension(extension)
      end
    end])
    extension
  end

  # The Zone's two Units share one id, and a third Unit on its last Face carries a payload naming it.
  def payload_naming_a_shared_sibling
    extension = register_unit_extension
    first, second = @original.entities.to_a.grep(Sketchup::ComponentInstance)
    record = U.read(first)
    U.write(second, record)
    third = Sketchup::ComponentInstance.new(@original.persistent_id + 22, first.definition, {},
                                            :glued_to => @original.entities.to_a.grep(Sketchup::Face).last)
    payload = { "sibling" => record.fetch("id") }
    U.write(third, record.merge("id" => "wun_000000000003",
                                "extension_data" => { extension.namespace => extension.envelope(payload) }))
    @original.entities << third
    U::HostWatch.state(@session).reset
  end

  def assert_refused_as_ambiguous(copy)
    zone_before = ZONE_STORE.read(copy)
    units_before = units_under(copy)

    result = invoke(MAKE_INDEPENDENT, { "zone_path" => [copy.persistent_id] })

    assert_equal %w[refused reference.invalid none], result.values_at("status", "code", "effect"), result.inspect
    assert_equal zone_before, ZONE_STORE.read(copy)
    assert_equal units_before, units_under(copy)
  end

  def listed_units
    API.query(:context => @context, :name => "ph_composer.windows.units.list").dig("value", "units")
  end

  def invoke(name, params)
    @sequence += 1
    API.invoke(:context => @context, :name => name, :params => params,
               :request => { "sequence" => @sequence, "expected_revision" => @session.revision })
  end

  # A classified box Zone with two glued Units of two Types on two of its Faces.
  def zone(base)
    faces = 3.times.map do |index|
      Sketchup::Face.new(base + index + 1, {}, :points => [Geom::Point3d.new(0, 0, index),
                                                           Geom::Point3d.new(2, 0, index),
                                                           Geom::Point3d.new(2, 2, index)])
    end
    group = Sketchup::Group.new(base, Sketchup::Entities.new(faces))
    @model.entities << group
    invoke("ph_composer.zones.make", { "parent_path" => [], "entity_ids" => [base] })
    definition = @model.definitions.add("Synthetic window")
    faces.first(2).each_with_index do |face, index|
      unit = Sketchup::ComponentInstance.new(base + 20 + index, definition, {}, :glued_to => face)
      U.write(unit, { "id" => "wun_00000000000#{index + 1}", "schema_version" => 1,
                      "window_type_id" => "wnt_00000000000#{index + 1}", "anchor" => "sill_center",
                      "user_data" => { "note" => ["kept"] } })
      group.entities << unit
    end
    group
  end

  # A Space with one Volume and one Floor Segment, put inside the Zone Group natively.
  def space_in(group)
    volume = volume_group(group.persistent_id + 40, volume_record("A"),
                          [floor_face(group.persistent_id + 41, rectangle(0, 0, 1, 1), segment_record("A"))])
    space = space_group(group.persistent_id + 42, space_record("S", :number => "1"), [volume])
    group.entities << space
    treat_duplicates_as_existing(@model)
  end

  def space_of(group)
    group.entities.to_a.find { |entity| PhComposer::Spaces::SPACE_STORE.read(entity) }
  end

  def space_ids(group)
    space = space_of(group)
    volume = space.entities.to_a.first
    [PhComposer::Spaces::SPACE_STORE.read(space)["id"], PhComposer::Spaces::VOLUME_STORE.read(volume)["id"],
     PhComposer::Spaces::FLOOR_SEGMENT_STORE.read(volume.entities.to_a.first)["id"]]
  end

  def tag(group, id)
    child = Sketchup::Group.new(group.persistent_id + 30, Sketchup::Entities.new([]))
    ZoneChildFixture::STORE.write(child, { "id" => id })
    group.entities << child
  end

  # A copy already in the Model, which the watcher leaves for the explicit command.
  def shared_copy(group, base)
    copy = Sketchup::Group.new(base, group.entities)
    copy.set_attribute("ph_composer.zone", "record", group.get_attribute("ph_composer.zone", "record"))
    @model.entities << copy
    treat_duplicates_as_existing(@model)
    copy
  end

  # A native copy made during the session, which the watcher repairs on its deferred pass.
  def native_copy(group, base)
    PhComposer::ModelOperation.perform(@model, "Paste") { true }
    copy = Sketchup::Group.new(base, group.entities)
    copy.set_attribute("ph_composer.zone", "record", group.get_attribute("ph_composer.zone", "record"))
    @model.entities << copy
    copy
  end

  def units_under(group)
    group.entities.to_a.grep(Sketchup::ComponentInstance).map { |entity| U.read(entity) }.compact
  end

  def units_in_model
    U::Occurrences.all(@model).map(&:record)
  end

  def tags_under(group)
    group.entities.to_a.grep(Sketchup::Group).map { |entity| ZoneChildFixture::STORE.read(entity)&.fetch("id") }.compact
  end

  def zone_groups
    @model.entities.to_a.select { |entity| entity.is_a?(Sketchup::Group) && ZONE_STORE.read(entity) }
  end
end
