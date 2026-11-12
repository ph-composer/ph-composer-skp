# frozen_string_literal: true

require_relative "test_helper"
require_relative "support/space_fixtures"

# A native copy of a Space Group is made independent in the copy's own Undo step (context/CONTRACTS.md,
# "Reconciliation"). Copies arrive as the host delivers them: the commit, then the added Group already
# carrying its instance dictionaries (context/SKETCHUP_HOST_BEHAVIOR.md, "Observers and edit contexts").
class SpacesCopyWatchTest < PhComposerTestCase
  include SpaceFixtures

  API = PhComposer::API

  def setup
    super
    @model = Sketchup.active_model
    @volume = volume_group(111, volume_record("A"), [floor_face(112, rectangle(0, 0, 2, 2), segment_record("A"))])
    @space = space_group(110, space_record("S", :number => "1"), [@volume])
    @zone = zone_group(100, "Z", [@space])
    @model.entities << @zone
    @session = PhComposer::Sessions.for(@model)
    @context = API.connect(:session_id => @session.id)
    @notices = []
    @unsubscribe = PhComposer::Sessions.on_notice { |_session, message, tone| @notices << [tone, message] }
  end

  def teardown
    @unsubscribe.call
    super
  end

  def watcher
    SPACES::CopyWatch.state(@session)
  end

  # What a native copy leaves: a new Group over the same entities with the original's dictionaries.
  def copy_natively(group, persistent_id, parent = @zone)
    copy = Sketchup::Group.new(persistent_id, group.entities, {}, :transformation => group.transformation)
    Array(group.attribute_dictionaries).each do |dictionary|
      dictionary.each { |key, value| copy.set_attribute(dictionary.name, key, value) }
    end
    @session.host_event(:transaction_committed)
    parent.entities << copy
    copy
  end

  def copy_in_operation(group, persistent_id)
    copy = Sketchup::Group.new(persistent_id, group.entities)
    SPACES::SPACE_STORE.write(copy, SPACES::SPACE_STORE.read(group))
    @model.start_operation("Copy")
    @zone.entities << copy
    @model.commit_operation
    copy
  end

  def invoke(name, params)
    API.invoke(:context => @context, :name => name, :params => params,
               :request => { "sequence" => 1, "expected_revision" => @session.revision })
  end

  def undo_warnings
    @notices.map(&:last).grep(/\AUndo also took back/)
  end

  def spaces
    API.query(:context => @context, :name => "ph_composer.spaces.all").dig("value", "spaces")
  end

  def test_a_native_copy_is_made_independent_in_the_copys_undo_step
    copy_natively(@space, 120)
    assert watcher.pending?
    UI.run_timers
    refute watcher.pending?
    original, copy = spaces
    assert_equal %w[spc_SSSSSSSSSSSS 1], [original["id"], original.dig("values", "number")]
    refute_equal "spc_SSSSSSSSSSSS", copy["id"]
    assert_equal "2", copy.dig("values", "number")
    refute_equal "vol_AAAAAAAAAAAA", copy.dig("volumes", 0, "id")
    assert_equal ["Make Independent", true, false, true], @model.operation_starts.last
    assert_equal [[:success, "Made the copied Space independent."]], @notices
  end

  # The follow-up cannot abort the copy it joined: a failure after the writes puts the records back
  # (HostFollowUp calls `restore`), and the notice says the copy's records are as copied.
  def test_a_failed_follow_up_restores_the_copy_and_says_so
    copy = copy_natively(@space, 120)
    SPACES::IdentityStep.class_eval do
      alias_method :real_apply, :apply
      define_method(:apply) do |model, slots|
        real_apply(model, slots)
        raise "injected"
      end
    end
    begin
      UI.run_timers
    ensure
      SPACES::IdentityStep.class_eval do
        alias_method :apply, :real_apply
        remove_method :real_apply
      end
    end
    assert_equal "spc_SSSSSSSSSSSS", SPACES::SPACE_STORE.read(copy)["id"]
    assert_equal :warning, @notices.last.first
    assert_includes @notices.last.last, "records are as copied"
  end

  # Restore puts back the Space first. When that write fails its Volume and Floor Segment are still put
  # back, and the notice says not everything could be.
  def test_a_failing_space_restore_still_restores_the_volume_and_floor_segment
    copy = copy_natively(@space, 120)
    SPACES::IdentityStep.class_eval do
      alias_method :real_apply, :apply
      define_method(:apply) do |model, slots|
        real_apply(model, slots)
        raise "injected"
      end
    end
    real_write = SPACES::SPACE_STORE.method(:write)
    SPACES::SPACE_STORE.define_singleton_method(:write) do |entity, record|
      raise IOError, "injected at restore" if record.fetch("id") == "spc_SSSSSSSSSSSS"

      real_write.call(entity, record)
    end
    begin
      UI.run_timers
    ensure
      SPACES::SPACE_STORE.singleton_class.send(:remove_method, :write)
      SPACES::IdentityStep.class_eval do
        alias_method :apply, :real_apply
        remove_method :real_apply
      end
    end
    volume = copy.entities.to_a.first
    assert_equal "vol_AAAAAAAAAAAA", SPACES::VOLUME_STORE.read(volume)["id"]
    assert_equal "fsg_AAAAAAAAAAAA", SPACES::FLOOR_SEGMENT_STORE.read(volume.entities.to_a.first)["id"]
    assert_equal :error, @notices.last.first
  end

  def test_an_array_of_copies_takes_the_next_free_numbers
    5.times { |index| copy_natively(@space, 120 + index) }
    UI.run_timers
    assert_equal %w[1 2 3 4 5 6], spaces.map { |row| row.dig("values", "number") }
    assert_equal 6, spaces.map { |row| row["id"] }.uniq.length
    assert_equal [[:success, "Made the 5 copied Spaces independent."]], @notices
  end

  # Copies in two Zones in one batch each take their own Zone's next number.
  def test_copies_in_two_zones_take_each_zones_next_number
    SPACES::SPACE_STORE.write(@space, SPACES::SPACE_STORE.read(@space).merge("number" => "100"))
    other = space_group(210, space_record("T", :number => "1"), [])
    @model.entities << zone_group(200, "Y", [other])
    treat_duplicates_as_existing(@model)
    copy_natively(@space, 120)
    copy_natively(other, 220, @model.entities.to_a.last)
    UI.run_timers
    numbers = spaces.to_h { |row| [row.dig("reference", "entity_path"), row.dig("values", "number")] }
    assert_equal "101", numbers.fetch([100, 120])
    assert_equal "2", numbers.fetch([200, 220])
  end

  # An unrelated operation committed between the copy and the deferred pass takes the repair with it on
  # Undo, and the copy stays: the watcher says so.
  def test_an_undo_that_takes_back_the_repair_but_not_the_copy_warns
    copy = Sketchup::Group.new(120, @space.entities)
    SPACES::SPACE_STORE.write(copy, SPACES::SPACE_STORE.read(@space))
    @model.start_operation("Copy")
    @zone.entities << copy
    @model.commit_operation
    @model.start_operation("Other")
    @model.commit_operation
    UI.run_timers
    @model.undo
    assert_equal %w[spc_SSSSSSSSSSSS spc_SSSSSSSSSSSS], spaces.map { |row| row["id"] }
    assert_equal :warning, @notices.last.first
    assert_includes @notices.last.last, "Undo also took back"
  end

  # A later batch does not forget an earlier repair: undoing back past it still warns.
  def test_an_undo_of_an_earlier_batch_still_warns
    copy_in_operation(@space, 120)
    @model.start_operation("Other")
    @model.commit_operation
    UI.run_timers
    copy_in_operation(@space, 130)
    UI.run_timers
    @model.undo
    assert_empty(@notices.select { |tone, _message| tone == :warning })
    @model.undo
    assert_includes @notices.last.last, "Undo also took back"
  end

  # A Space record that does not read at one Undo is no evidence the copies left: a later Undo that takes
  # back an earlier repair still warns.
  def test_an_unreadable_space_at_one_undo_keeps_the_remembered_repairs
    copy_in_operation(@space, 120)
    @model.start_operation("Other")
    @model.commit_operation
    UI.run_timers
    stray = Sketchup::Group.new(700, Sketchup::Entities.new([]))
    stray.set_attribute(SPACES::SPACE_STORE.dictionary, SPACES::SPACE_STORE.key, "{not json")
    @model.start_operation("Stray")
    @model.entities << stray
    @model.commit_operation
    @model.start_operation("Later")
    @model.commit_operation
    2.times { @model.undo }
    assert_empty undo_warnings, "the stray read nothing, then read again with the repair still in place"
    @model.undo
    assert_equal 1, undo_warnings.length
  end

  # A copy made independent again by the row's command is no longer a copy, so a later Undo of an unrelated
  # change does not say it is.
  def test_an_undo_after_the_explicit_repair_does_not_warn_again
    copy_in_operation(@space, 120)
    @model.start_operation("Other")
    @model.commit_operation
    UI.run_timers
    @model.undo
    reference = spaces.find { |row| row.dig("reference", "entity_path") == [100, 120] }.fetch("reference")
    result = invoke(SPACES::CopyWatch::ACTION, "reference" => reference)
    assert_equal "completed", result.fetch("status"), result.inspect
    @model.start_operation("Later")
    @model.commit_operation
    warned = undo_warnings.length
    @model.undo
    assert_equal warned, undo_warnings.length
  end

  def test_a_cut_and_paste_leaves_no_duplicate_and_nothing_is_queued
    @zone.entities.delete(@space)
    @session.host_event(:transaction_committed)
    @zone.entities << @space
    refute watcher.pending?
  end

  def test_undo_and_redo_drop_a_pending_pass
    copy_natively(@space, 120)
    @session.host_event(:transaction_undone)
    refute watcher.pending?
    UI.run_timers
    assert_equal %w[spc_SSSSSSSSSSSS spc_SSSSSSSSSSSS], spaces.map { |row| row["id"] }
  end

  # Two occurrences already sharing the id are both originals: a third copy of them is not guessed at.
  def test_two_pre_existing_holders_are_never_rewritten
    existing = Sketchup::Group.new(130, @space.entities)
    SPACES::SPACE_STORE.write(existing, SPACES::SPACE_STORE.read(@space))
    @zone.entities << existing
    treat_duplicates_as_existing(@model)
    copy_natively(@space, 120)
    UI.run_timers
    assert_equal ["spc_SSSSSSSSSSSS"] * 3, spaces.map { |row| row["id"] }
    assert_empty @notices
  end

  # A copy inside a component keeps the finding and gets one notice.
  def test_a_copy_inside_a_component_keeps_its_finding_with_one_notice
    @zone.entities.delete(@space)
    definition = Sketchup::ComponentDefinition.new(Sketchup::Entities.new([@space]))
    @zone.entities << Sketchup::ComponentInstance.new(140, definition)
    @session.host_event(:transaction_committed)
    @zone.entities << Sketchup::ComponentInstance.new(141, definition)
    UI.run_timers
    assert_equal ["spc_SSSSSSSSSSSS"] * 2, spaces.map { |row| row["id"] }
    notice = "Copied Space inside shared storage, such as a component, keeps the copy's identity. Draw the Space " \
             "directly."
    assert_equal [[:warning, notice]], @notices
  end
end
