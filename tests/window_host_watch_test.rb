# frozen_string_literal: true

require_relative "test_helper"
require_relative "support/window_record_fixtures"
require_relative "support/assembly_assignment_fixtures"

# A Window pasted or moved off its Face returns to the nearest Face of its Zone, joined to the gesture. A
# paste reports its addition after its commit and a Move reports the instance before its commit, the orders
# measured on the host (context/SKETCHUP_HOST_BEHAVIOR.md); the deferred pass runs on `UI.run_timers`.
class WindowHostWatchTest < PhComposerTestCase
  include WindowRecordFixtures
  include AssemblyAssignmentFixtures

  M = 1 / 0.0254

  def setup
    super
    assignment_setup
    PhComposer::Registry.install([W]) unless PhComposer::Registry.installed?(W::FEATURE_ID)
    points = [[0, 0, 0], [8, 0, 0], [8, 0, 6], [0, 0, 6]].map { |point| Geom::Point3d.new(*point.map { |v| v * M }) }
    @face = Sketchup::Face.new(1001, {}, :points => points)
    @group = Sketchup::Group.new(1000, Sketchup::Entities.new([@face]))
    @model.entities << @group
    assert_equal "completed", assignment_invoke("ph_composer.zones.make", "parent_path" => [],
                                                                          "entity_ids" => [1000]).fetch("status")
    @host = assignment_faces.first.fetch("reference")
    @type_id = assignment_invoke("ph_composer.windows.types.create",
                                 "values" => { "name" => "Watched", "rows_m" => [1.5],
                                               "columns_m" => [0.7] }).fetch("value").fetch("id")
    placed = assignment_invoke("ph_composer.windows.units.place",
                               "host" => @host, "type_id" => @type_id, "anchor" => "sill_center",
                               "offsets" => { "x_m" => 2.0, "y_m" => 1.0 })
    assert_equal "completed", placed.fetch("status"), placed.inspect
    @notices = []
    PhComposer::Sessions.on_notice { |session, message, tone| @notices << [message, tone] if session == @session }
    @session.feature_state(:windows_host_watch) { W::Units::HostWatch::State.new(@session) }
  end

  def unit(index = 0)
    W::Units::Occurrences.all(@model)[index]
  end

  def units
    assignment_query("ph_composer.windows.units.list").fetch("units")
  end

  def observer
    PhComposer::ContainerWatch::Observer.new(PhComposer::ContainerWatch.for(@session))
  end

  # A native paste: its commit first, then the addition, with the record already on the copy.
  def paste(matrix)
    PhComposer::ModelOperation.perform(@model, "Paste") { true }
    original = unit.entity
    copy = Sketchup::ComponentInstance.new(7000, original.definition, {},
                                           :transformation => Geom::Transformation.new(matrix))
    copy.set_attribute(W::Units::STORE.dictionary, W::Units::STORE.key,
                       original.get_attribute(W::Units::STORE.dictionary, W::Units::STORE.key))
    @group.entities << copy
    copy
  end

  # A native Move: the instance reported, then the commit.
  def move(entity, matrix)
    PhComposer::ModelOperation.perform(@model, "Move") do
      entity.transformation = Geom::Transformation.new(matrix)
      observer.onElementModified(@group.entities, entity)
      true
    end
  end

  def matrix_at(x_value, y_value, z_value)
    identity_axes + [x_value * M, y_value * M, z_value * M, 1]
  end

  # The placed Unit's own orientation: flat against the Face, seen from outside.
  def identity_axes
    unit.transform.to_a.take(12)
  end

  def findings(row)
    row.fetch("findings").map { |finding| finding.fetch("code") }
  end

  def test_a_paste_off_every_face_returns_to_the_nearest_face_in_the_pastes_undo_step
    copy = paste(matrix_at(0.2, 3, 5))
    assert W::Units::HostWatch.state(@session).pending?
    UI.run_timers
    assert_equal @face, copy.glued_to
    row = units.find { |candidate| candidate.fetch("reference").fetch("entity_path").last == 7000 }
    assert_empty findings(row) & W::Units::ReturnToHost::LEFT
    assert_equal "Return Window to its Face", @model.operation_starts.last.first
    assert_equal true, @model.operation_starts.last.last
    assert_includes @notices.last.first, "back to the nearest Face"
    assert_equal :info, @notices.last.last
    assert_includes UI.notifications.last.message, "back to the nearest Face"
    assert @model.undo
    UI.run_timers
    assert_equal 1, W::Units::Occurrences.all(@model).length, "one Undo takes back the paste and its return"
  end

  def test_a_window_moved_past_the_edge_returns_inside_it_and_lands_square_on_the_face
    entity = unit.entity
    move(entity, matrix_at(7.9, 0, 3))
    UI.run_timers
    assert_equal @face, entity.glued_to
    assert_empty findings(units.first) & W::Units::ReturnToHost::LEFT
    x_axis = entity.transformation.to_a.take(3)
    assert_in_delta 1.0, x_axis.first.abs, 1e-9
    origin_x = entity.transformation.to_a[12] / M
    assert_operator origin_x, :<=, 8.0
  end

  # Through the session's own observers the commit can come first (context/SKETCHUP_HOST_BEHAVIOR.md).
  def test_a_change_reported_after_its_commit_still_returns
    entity = unit.entity
    PhComposer::ModelOperation.perform(@model, "Move") do
      entity.transformation = Geom::Transformation.new(matrix_at(7.9, 0, 3))
      true
    end
    observer.onElementModified(@group.entities, entity)
    UI.run_timers
    assert_empty findings(units.first) & W::Units::ReturnToHost::LEFT
  end

  def test_a_change_with_no_commit_around_it_waits_for_one
    entity = unit.entity
    PhComposer::ModelOperation.perform(@model, "Paint") { true }
    UI.run_timers
    observer.onElementModified(@group.entities, entity)
    refute W::Units::HostWatch.state(@session).pending?, "a drag's change has no commit yet"
  end

  def test_a_window_still_on_its_face_writes_nothing_and_says_nothing
    entity = unit.entity
    starts = @model.operation_starts.length
    move(entity, entity.transformation.to_a.tap { |matrix| matrix[12] += 0.5 * M })
    UI.run_timers
    assert_equal starts + 1, @model.operation_starts.length, "only the Move"
    assert_empty @notices
  end

  def test_a_paste_with_a_window_in_the_way_lands_just_clear_of_it_on_the_same_face
    copy = paste(matrix_at(1.8, 3, 3))
    UI.run_timers
    assert_equal @face, copy.glued_to
    row = units.find { |candidate| candidate.fetch("reference").fetch("entity_path").last == 7000 }
    assert_empty findings(row) & (W::Units::ReturnToHost::LEFT + ["window.overlap"])
  end

  # A narrow Face has no room beside the other Window, only above it.
  def test_a_window_lands_above_another_when_no_room_is_beside_it
    plan = Struct.new(:width_m, :height_m, :outer_polygon_m, :panes)
                 .new(1.5, 1.5, [[0.0, -1.5, 0.0], [1.5, -1.5, 0.0], [1.5, 0.0, 0.0], [0.0, 0.0, 0.0]], [])
    loop_m = [[0.0, 0.0, 0.0], [2.0, 0.0, 0.0], [2.0, 0.0, 6.0], [0.0, 0.0, 6.0]]
    geometry = PhComposer::FaceGeometry::Snapshot.new(:loops_m => [loop_m], :normal => [0.0, -1.0, 0.0])
    other = [[0.25, 0.0, 1.25], [1.75, 0.0, 1.25], [1.75, 0.0, 2.75], [0.25, 0.0, 2.75]]
    away = [1.0, 0, 0, 0, 0, 0, 1.0, 0, 0, -1.0, 0, 0, 0.25 * M, 3.0 * M, 2.75 * M, 1]
    matrix = W::Placement::Snap.on_face(geometry, plan, away, [other])
    outline = W::Units::WorldGeometry.map(plan, matrix).outer_polygon_m
    assert W::Placement::Fit.check!(geometry, outline, :existing_polygons_m => [other])
    assert_operator outline.map(&:last).min, :>=, 2.75 - 1e-5
  end

  def test_a_window_lands_beside_a_hole_in_the_face
    plan = Struct.new(:width_m, :height_m, :outer_polygon_m, :panes)
                 .new(1.0, 1.0, [[0.0, -1.0, 0.0], [1.0, -1.0, 0.0], [1.0, 0.0, 0.0], [0.0, 0.0, 0.0]], [])
    outer = [[0.0, 0.0, 0.0], [8.0, 0.0, 0.0], [8.0, 0.0, 6.0], [0.0, 0.0, 6.0]]
    hole = [[3.0, 0.0, 2.0], [5.0, 0.0, 2.0], [5.0, 0.0, 4.0], [3.0, 0.0, 4.0]]
    geometry = PhComposer::FaceGeometry::Snapshot.new(:loops_m => [outer, hole], :normal => [0.0, -1.0, 0.0])
    away = [1.0, 0, 0, 0, 0, 0, 1.0, 0, 0, -1.0, 0, 0, 3.5 * M, 3.0 * M, 3.5 * M, 1]
    matrix = W::Placement::Snap.on_face(geometry, plan, away, [])
    assert W::Placement::Fit.check!(geometry, W::Units::WorldGeometry.map(plan, matrix).outer_polygon_m)
  end

  def test_redo_after_the_return_keeps_it_and_runs_nothing_more
    paste(matrix_at(0.2, 3, 5))
    UI.run_timers
    starts = @model.operation_starts.length
    assert @model.undo
    UI.run_timers
    assert @model.redo
    UI.run_timers
    assert_equal starts, @model.operation_starts.length, "Undo and Redo write nothing"
    assert_equal 2, W::Units::Occurrences.all(@model).length
  end

  def test_each_window_answers_for_itself_when_one_cannot_return
    copy = paste(matrix_at(0.2, 3, 5))
    entity = unit.entity
    move(entity, matrix_at(1, 3, 3))
    entity.locked = true
    UI.run_timers
    assert_equal @face, copy.glued_to, "the free Window still returned"
    assert_includes @notices.map(&:first).join(" "), "back to the nearest Face"
    assert_includes @notices.map(&:first).join(" "), "locked"
  end

  def test_a_paste_with_no_zone_beside_it_stays_put_and_says_so_in_sketchup
    PhComposer::ModelOperation.perform(@model, "Paste") { true }
    original = unit.entity
    copy = Sketchup::ComponentInstance.new(7000, original.definition, {},
                                           :transformation => Geom::Transformation.new(matrix_at(20, 20, 0)))
    copy.set_attribute(W::Units::STORE.dictionary, W::Units::STORE.key,
                       original.get_attribute(W::Units::STORE.dictionary, W::Units::STORE.key))
    @model.entities << copy
    UI.run_timers
    assert_nil copy.glued_to
    assert_equal :warning, @notices.last.last
    assert_includes @notices.last.first, "No Face of a Zone"
    assert_includes UI.notifications.last.message, "Schedule"
  end

  def test_no_face_with_room_refuses_and_leaves_the_window_where_it_was_moved
    entity = unit.entity
    move(entity, matrix_at(1, 3, 3))
    moved = entity.transformation.to_a
    W::Placement::Snap.stub(:on_face, nil) { UI.run_timers }
    assert_equal moved, entity.transformation.to_a
    assert_equal :warning, @notices.last.last
    assert_includes @notices.last.first, "stays there"
  end

  # An unclassified Face is open to Place, so it takes a Window back. A Floor is not somewhere one returns to.
  def test_a_window_does_not_return_to_a_floor
    records = W::Placement::Hosts.method(:context)
    floor = lambda do |request, paths|
      records.call(request, paths).transform_values do |row|
        row.merge("values" => { "face_type" => "Floor", "boundary_condition" => "Outdoors" })
      end
    end
    W::Placement::Hosts.stub(:context, floor) do
      move(unit.entity, matrix_at(1, 3, 3))
      UI.run_timers
    end
    assert_includes @notices.last.first, "No Face of a Zone"
  end

  def test_undo_redo_and_own_operations_never_return_a_window
    entity = unit.entity
    watch = W::Units::HostWatch.state(@session)
    starts = @model.operation_starts.length
    entity.transformation = Geom::Transformation.new(matrix_at(1, 3, 3))
    observer.onElementModified(@group.entities, entity)
    watch.reset
    watch.committed
    refute watch.pending?, "an Undo reports the instance first and then drops it"
    @session.mutate do
      observer.onElementModified(@group.entities, entity)
      true
    end
    watch.committed
    refute watch.pending?, "PH-Composer's own write is not a gesture"
    assert_equal starts, @model.operation_starts.length
  end

  def test_a_scaled_window_is_not_moved_and_says_why
    entity = unit.entity
    matrix = matrix_at(1, 3, 3)
    matrix[0] *= 1.5
    move(entity, matrix)
    UI.run_timers
    assert_equal :warning, @notices.last.last
    assert_includes @notices.last.first, "scaled"
  end

  def test_a_failed_write_is_put_back_and_the_gesture_commits
    entity = unit.entity
    before = entity.glued_to
    move(entity, matrix_at(1, 3, 3))
    moved = entity.transformation.to_a
    step = W::Units::ReturnStep
    original = step.instance_method(:apply)
    step.send(:define_method, :apply) do |model, slots|
      original.bind(self).call(model, slots)
      raise "Synthetic failure after the write"
    end
    begin
      UI.run_timers
    ensure
      step.send(:define_method, :apply, original)
    end
    assert_equal moved, entity.transformation.to_a
    assert_equal before, entity.glued_to
    assert_includes @notices.last.first, "stays there"
  end
end
