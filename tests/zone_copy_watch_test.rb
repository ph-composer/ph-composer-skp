# frozen_string_literal: true

require_relative "test_helper"

# A native copy of a Zone becomes independent automatically, joined to the user's copy. The copy here
# is a second Group over the same definition carrying the Zone record, added just after its operation
# commits, the order measured on the host; the deferred pass runs on `UI.run_timers`.
class ZoneCopyWatchTest < PhComposerTestCase
  API = PhComposer::API
  ZONE_STORE = PhComposer::Zones::ZONE_STORE
  FACE_STORE = PhComposer::Zones::Faces::FACE_STORE
  UNREGISTERED = PhComposer::Records::Extension.new(
    :namespace => "test.fixture.watch", :schema_version => 1,
    :references => [{ "path" => "$.external_id", "target_kind" => "ph_composer.zones.faces.attached_zone",
                      "cardinality" => "one" }]
  )

  def setup
    super
    @model = Sketchup.active_model
    @session = PhComposer::Sessions.for(@model)
    @context = API.connect(:session_id => @session.id)
    @sequence = 0
    @notices = []
    PhComposer::Sessions.on_notice { |_session, message, tone| @notices << [message, tone] }
    @original = zone(300)
  end

  def test_a_native_copy_is_made_independent_after_the_copy_and_the_original_is_untouched
    before = [ZONE_STORE.read(@original), @original.entities.to_a, faces(@original)]
    copy = native_copy(@original, 400)

    assert watcher.pending?, "the copy is waiting for its deferred pass"
    UI.run_timers

    refute watcher.pending?
    assert_equal before, [ZONE_STORE.read(@original), @original.entities.to_a, faces(@original)]
    refute_equal ZONE_STORE.read(@original).fetch("id"), ZONE_STORE.read(copy).fetch("id")
    refute_equal @original.definition.persistent_id, copy.definition.persistent_id
    assert_equal %w[found found], states
    assert_equal ["Make Zone Independent", true, false, true], @model.operation_starts.last
    assert_equal [["Made the copied Zone independent.", :success]], @notices
  end

  def test_one_undo_removes_the_copy_and_its_repair_and_redo_repeats_no_repair
    native_copy(@original, 400)
    UI.run_timers
    starts = @model.operation_starts.length

    assert @model.undo
    UI.run_timers
    assert_equal 1, zone_groups.length, "one Undo removes the copy with its repair"
    assert @model.redo
    UI.run_timers

    assert_equal %w[found found], states
    assert_equal starts, @model.operation_starts.length, "Undo and Redo only rebaseline"
    assert_equal 1, @notices.length
  end

  # An unrelated operation committed before the deferred pass is the transaction the repair joins, so
  # undoing it takes the repair back too. The copy is left consistent and recoverable, and is told so.
  def test_undoing_a_change_the_repair_joined_says_the_copy_is_read_only_again
    copy = native_copy(@original, 400)
    PhComposer::ModelOperation.perform(@model, "Move") do
      @original.transformation = Geom::Transformation.translation([10, 0, 0])
    end
    UI.run_timers
    assert_equal %w[found found], states

    assert @model.undo
    UI.run_timers

    live = @model.entities.to_a.find { |entity| entity.persistent_id == copy.persistent_id }
    assert live, "the copied Group stays"
    assert_equal %w[shared_definition shared_definition], states
    assert_match(/^Undo also took back making the copied Zone independent/, @notices.last.first)
    assert_equal :warning, @notices.last.last
    result = invoke("ph_composer.zones.make_independent", { "zone_path" => [copy.persistent_id] })
    assert_equal "completed", result.fetch("status"), "and the row's command still makes it independent"
  end

  # A later batch does not forget an earlier repair: undoing back past it still warns.
  def test_an_undo_of_an_earlier_batch_still_warns
    earlier = native_copy(@original, 400)
    PhComposer::ModelOperation.perform(@model, "Move") do
      @original.transformation = Geom::Transformation.translation([10, 0, 0])
    end
    UI.run_timers
    native_copy(@original, 500)
    UI.run_timers

    assert @model.undo
    UI.run_timers
    assert_empty(@notices.select { |_message, tone| tone == :warning }, "the later copy left with its repair")
    assert @model.undo
    UI.run_timers

    assert(@model.entities.to_a.any? { |entity| entity.persistent_id == earlier.persistent_id }, "the copy stays")
    assert_match(/^Undo also took back making the copied Zone independent/, @notices.last.first)
  end

  # Undo past the copy, then Redo it and the change its repair joined: a repair whose copy left through
  # Undo comes back with Redo, so undoing that change again still warns.
  def test_an_undo_after_redoing_a_copy_that_left_through_undo_still_warns
    native_copy(@original, 400)
    PhComposer::ModelOperation.perform(@model, "Move") do
      @original.transformation = Geom::Transformation.translation([10, 0, 0])
    end
    UI.run_timers
    assert @model.undo
    assert @model.undo
    assert_equal 1, zone_groups.length, "the second Undo takes the copy away"
    assert @model.redo
    assert @model.redo
    assert_equal %w[found found], states

    assert @model.undo
    UI.run_timers

    assert_equal %w[shared_definition shared_definition], states
    assert_equal 2, @notices.count { |message, _tone| message.start_with?("Undo also took back") }
  end

  # A copy made independent again by the row's command is no longer read only, so a later Undo of an
  # unrelated change does not say it is.
  def test_an_undo_after_the_explicit_repair_does_not_warn_again
    copy = native_copy(@original, 400)
    PhComposer::ModelOperation.perform(@model, "Move") do
      @original.transformation = Geom::Transformation.translation([10, 0, 0])
    end
    UI.run_timers
    assert @model.undo
    UI.run_timers
    result = invoke("ph_composer.zones.make_independent", { "zone_path" => [copy.persistent_id] })
    assert_equal "completed", result.fetch("status"), result.inspect
    PhComposer::ModelOperation.perform(@model, "Move") do
      @original.transformation = Geom::Transformation.translation([20, 0, 0])
    end
    warnings = @notices.count { |_message, tone| tone == :warning }

    assert @model.undo
    UI.run_timers

    assert_equal warnings, @notices.count { |_message, tone| tone == :warning }
  end

  def test_a_copy_whose_faces_sit_in_a_child_group_is_made_independent_with_its_child
    faces = 3.times.map do |index|
      Sketchup::Face.new(1001 + index, {}, :points => [Geom::Point3d.new(0, 0, index), Geom::Point3d.new(2, 0, index),
                                                       Geom::Point3d.new(2, 2, index)])
    end
    child = Sketchup::Group.new(1010, Sketchup::Entities.new(faces))
    parent = Sketchup::Group.new(1000, Sketchup::Entities.new([child]))
    @model.entities << parent
    invoke("ph_composer.zones.make", { "parent_path" => [], "entity_ids" => [1000] })
    copy = native_copy(parent, 1050)
    UI.run_timers

    refute_equal child.definition.persistent_id, copy.entities.to_a.first.definition.persistent_id
    assert_equal %w[found found found], states
    assert_equal ["Made the copied Zone independent.", :success], @notices.last
  end

  def test_one_undo_of_a_copy_and_its_repair_posts_no_extra_notice
    native_copy(@original, 400)
    UI.run_timers

    assert @model.undo
    UI.run_timers

    assert_equal [["Made the copied Zone independent.", :success]], @notices
  end

  def test_an_array_copy_is_made_independent_as_one_batch_with_one_notice
    copies = native_copies(@original, [400, 500, 600, 700, 800])
    UI.run_timers

    ids = ([@original] + copies).map { |group| ZONE_STORE.read(group).fetch("id") }
    assert_equal 6, ids.uniq.length
    assert_equal 1, @model.operation_starts.count { |start| start.first == "Make Zone Independent" }
    assert_equal [["Made the 5 copied Zones independent.", :success]], @notices
  end

  def test_an_array_with_a_member_whose_data_cannot_be_copied_stays_shared_whole
    copies = native_copies(@original, [400, 500, 600]) do |copy, index|
      next unless index == 1

      ZONE_STORE.write(copy, ZONE_STORE.read(copy).merge("extension_data" => {
        UNREGISTERED.namespace => UNREGISTERED.envelope("external_id" => "atz_000000000001")
      }))
    end
    UI.run_timers

    assert(copies.all? { |copy| copy.definition.persistent_id == @original.definition.persistent_id })
    refute(@model.operation_starts.any? { |start| start.first == "Make Zone Independent" })
    assert_equal 1, @notices.length
    assert_match(/^The 3 copied Zones stay shared: /, @notices.first.first)
    assert_equal :warning, @notices.first.last
  end

  def test_a_failure_partway_restores_what_was_written_commits_and_never_aborts
    copies = native_copies(@original, [400, 500])
    copied_id = ZONE_STORE.read(@original).fetch("id")
    writes = 0
    FACE_STORE.singleton_class.send(:alias_method, :__watch_write, :write)
    FACE_STORE.define_singleton_method(:write) do |entity, record|
      writes += 1
      raise IOError, "injected" if writes == 5 && record["id"] != copied_id

      __watch_write(entity, record)
    end

    UI.run_timers

    refute(@model.operations.any? { |_name, _disable, result| result == :aborted })
    copies.each do |copy|
      refute_equal @original.definition.persistent_id, copy.definition.persistent_id, "storage isolation remains"
      assert_equal copied_id, ZONE_STORE.read(copy).fetch("id"), "every record is as it was copied"
      assert(faces(copy).all? { |record| faces(@original).include?(record) })
    end
    assert_equal ["The 2 copied Zones could not be made independent; their records are as copied. All of them " \
                  "now have Faces of their own. Use Make Zone independent on their rows.", :warning], @notices.last
  ensure
    FACE_STORE.singleton_class.send(:remove_method, :write)
    FACE_STORE.singleton_class.send(:alias_method, :write, :__watch_write)
    FACE_STORE.singleton_class.send(:remove_method, :__watch_write)
  end

  # Restore puts back the Zone first. When that write fails the Faces are still put back, and the notice
  # says not everything could be.
  def test_a_failing_zone_restore_still_restores_every_face
    copy = native_copy(@original, 400)
    copied_id = ZONE_STORE.read(@original).fetch("id")
    face_writes = 0
    fail_apply = lambda do |write, entity, record|
      raise IOError, "injected at apply" if (face_writes += 1) == 3

      write.call(entity, record)
    end
    fail_restore = lambda do |write, entity, record|
      raise IOError, "injected at restore" if record.fetch("id") == copied_id

      write.call(entity, record)
    end

    with_write(FACE_STORE, fail_apply) { with_write(ZONE_STORE, fail_restore) { UI.run_timers } }

    assert(faces(copy).all? { |record| faces(@original).include?(record) }, "every Face is as copied")
    assert_equal :error, @notices.last.last
  end

  def test_a_duplicate_that_was_already_there_is_left_for_the_explicit_command
    twin = Sketchup::Group.new(400, @original.entities)
    twin.set_attribute("ph_composer.zone", "record", @original.get_attribute("ph_composer.zone", "record"))
    @model.entities << twin
    treat_duplicates_as_existing(@model)
    zone(900)
    UI.run_timers

    assert_equal %w[shared_definition shared_definition found], states
    assert_empty @notices
  end

  def test_moving_a_zone_and_copying_a_component_with_a_zone_inside_change_nothing
    PhComposer::ModelOperation.perform(@model, "Move") do
      @original.transformation = Geom::Transformation.translation([10, 0, 0])
    end
    @model.entities.delete(@original)
    definition = Sketchup::ComponentDefinition.new(Sketchup::Entities.new([@original]), :name => "unit")
    place = -> { @model.entities.add_instance(definition, Geom::Transformation.new) }
    PhComposer::ModelOperation.perform(@model, "Place", &place)
    treat_duplicates_as_existing(@model)
    PhComposer::ModelOperation.perform(@model, "Copy", &place)
    UI.run_timers

    refute(@model.operation_starts.any? { |start| start.first == "Make Zone Independent" })
    assert_empty @notices
  end

  def test_a_failure_in_the_first_copy_says_the_second_still_shares_its_faces
    copies = native_copies(@original, [400, 500])
    writes = 0
    FACE_STORE.singleton_class.send(:alias_method, :__watch_write, :write)
    FACE_STORE.define_singleton_method(:write) do |entity, record|
      writes += 1
      raise IOError, "injected" if writes == 2

      __watch_write(entity, record)
    end

    UI.run_timers

    assert_equal [false, true], copies.map { |copy|
      copy.definition.persistent_id == @original.definition.persistent_id
    }
    assert_match(/records are as copied\. 1 of them now has Faces of their own\./, @notices.last.first)
  ensure
    FACE_STORE.singleton_class.send(:remove_method, :write)
    FACE_STORE.singleton_class.send(:alias_method, :write, :__watch_write)
    FACE_STORE.singleton_class.send(:remove_method, :__watch_write)
  end

  def test_settling_the_session_runs_a_pending_copy_pass_and_detaching_cancels_one
    copy = native_copy(@original, 400)
    @session.settle
    refute watcher.pending?
    refute_equal ZONE_STORE.read(@original).fetch("id"), ZONE_STORE.read(copy).fetch("id")

    native_copy(@original, 500)
    assert watcher.pending?
    watcher.detach
    refute watcher.pending?
  end

  private

  def watcher
    PhComposer::Zones::CopyWatch.state(@session)
  end

  # Runs the block with `store.write` answered by `fake`, which is handed the real write to call.
  def with_write(store, fake)
    real = store.method(:write)
    store.define_singleton_method(:write) { |entity, record| fake.call(real, entity, record) }
    yield
  ensure
    store.singleton_class.send(:remove_method, :write)
  end

  def native_copy(group, base)
    native_copies(group, [base]).first
  end

  def native_copies(group, bases)
    PhComposer::ModelOperation.perform(@model, "Paste") { true }
    bases.each_with_index.map do |base, index|
      copy = Sketchup::Group.new(base, group.entities)
      copy.set_attribute("ph_composer.zone", "record", group.get_attribute("ph_composer.zone", "record"))
      yield copy, index if block_given?
      @model.entities << copy
      copy
    end
  end

  def zone(base)
    faces = 3.times.map do |index|
      Sketchup::Face.new(base + index + 1, {}, :points => [Geom::Point3d.new(0, 0, index),
                                                           Geom::Point3d.new(2, 0, index),
                                                           Geom::Point3d.new(2, 2, index)])
    end
    group = Sketchup::Group.new(base, Sketchup::Entities.new(faces))
    @model.entities << group
    invoke("ph_composer.zones.make", { "parent_path" => [], "entity_ids" => [base] })
    rows = API.query(:context => @context, :name => "ph_composer.zones.faces.list").dig("value", "faces")
    references = rows.select { |face| face.dig("reference", "zone_path") == [base] }.map { |face| face["reference"] }
    invoke("ph_composer.zones.faces.classify", {
      "faces" => references, "expected_values" => {},
      "intent" => { "face_type" => { "mode" => "set", "value" => "Wall" },
                    "boundary_condition" => { "mode" => "set", "value" => "Outdoors" } }
    })
    group
  end

  def invoke(name, params)
    @sequence += 1
    API.invoke(:context => @context, :name => name, :params => params,
               :request => { "sequence" => @sequence, "expected_revision" => @session.revision })
  end

  def faces(group)
    group.entities.to_a.map { |face| FACE_STORE.read(face) }
  end

  def zone_groups
    @model.entities.to_a.select { |entity| entity.is_a?(Sketchup::Group) && ZONE_STORE.read(entity) }
  end

  def states
    API.query(:context => @context, :name => "ph_composer.zones.list").dig("value", "zones").map { |row| row["state"] }
  end
end
