# frozen_string_literal: true

require_relative "test_helper"

# The pipe role and Pipe Type Colour-by modes over a stub Model: each pipe occurrence draws its world segment at the
# modes' stroke, in its role's fixed colour or its type's own, the legend's lengths are the schedule's totals, and a
# line with no assignment draws nothing.
class PipingColourModeTest < PhComposerTestCase
  API = PhComposer::API
  ColourBy = PhComposer::ColourBy
  P = PhComposer::Piping
  STORE = P::Assignment::STORE
  PREFIX = "ph_composer.piping"
  INCHES = 1 / 0.0254

  def setup
    super
    @model = Sketchup.active_model
    @session = PhComposer::Sessions.for(@model)
    @context = API.connect(:session_id => @session.id)
    @sequence = 0
    @next_id = 1000
    @hws = invoke("ph_composer.mechanical.hot_water_systems.create", "values" => { "name" => "HWS-1" })
           .dig("value", "id")
    @pex = invoke("#{PREFIX}.pipe_types.create", "values" => { "name" => "PEX", "color" => "#112233" })
           .dig("value", "id")
    @copper = invoke("#{PREFIX}.pipe_types.create", "values" => { "name" => "Copper" }).dig("value", "id")
  end

  # Piping group 500, moved 2 m along x, holds a 6 m PEX trunk of two lines, a 3 m Copper branch, a 1 m Copper twig, a
  # 2 m PEX recirculation line and one 1 m line with no assignment.
  def the_case
    @vertices = {}
    @trunk = line("trunk", @pex, [[0, 0, 0], [0, 0, 3], [0, 0, 6]], "multiplier" => 2, "demand_recirculation" => false)
    @branch = line("branch", @copper, [[0, 0, 3], [3, 0, 3]])
    @twig = line("twig", @copper, [[3, 0, 3], [3, 1, 3]])
    @loop = line("recirculation", @pex, [[0.5, 0, 0], [0.5, 0, 2]], "water_temp_c" => 55.0, "daily_period" => 18)
    @loose = Sketchup::Edge.new(next_id, point([5, 0, 0]), point([6, 0, 0]))
    group = Sketchup::Group.new(500, Sketchup::Entities.new(@trunk + @branch + @twig + @loop + [@loose]),
                                :transformation => Geom::Transformation.translation([2 * INCHES, 0, 0]))
    P::Group::STORE.write(group, P::Group.new_record("ppg_PG1000000001", @hws))
    @model.entities << group
  end

  def test_by_role_draws_each_pipe_once_in_its_roles_colour_and_its_lengths_are_the_schedules_totals
    the_case
    service = activate(P::ColourModes::BY_ROLE)
    rows = service.rows.map { |row| [row.value, row.label, row.count, row.figure.first.last.round(9)] }
    assert_equal [["trunk", "Trunk", 2, 6.0], ["branch", "Branch", 1, 3.0], ["twig", "Twig", 1, 1.0],
                  ["recirculation", "Recirculation", 1, 2.0]], rows
    totals = query("schedule.all").dig("totals", "by_role").to_h { |row| [row.fetch("role"), row.fetch("length_m")] }
    assert_equal(totals.transform_values { |length| length.round(9) },
                 service.rows.to_h { |row| [row.value, row.figure.first.last.round(9)] })
    assert_equal P::ColourModes::ROLE_COLOURS.fetch("trunk"), service.rows.first.colour
    drawn = service.lines.fetch(P::ColourModes::ROLE_COLOURS.fetch("branch")).map do |at|
      [at.x, at.y, at.z].map { |inches| (inches / INCHES).round(9) }
    end
    assert_equal [[2.0, 0.0, 3.0], [5.0, 0.0, 3.0]], drawn, "the group's move applied"
    assert_equal 10, service.lines.values.sum(&:length), "five pipes, two points each; the loose line draws nothing"
    assert_empty service.fills
    mode = PhComposer::Registry.current.colour_modes.fetch(P::ColourModes::BY_ROLE)
    assert_equal ["Pipe role", "edge", P::ColourModes::STROKE], [mode.label, mode.entity_kind, mode.stroke]
  end

  def test_by_type_colours_each_pipe_by_its_types_colour_and_a_missing_type_is_incomplete
    the_case
    missing = "ppt_ZZZZZZZZZZZZ"
    tag(@twig.first, missing, "twig")
    service = activate(P::ColourModes::BY_TYPE)
    rows = service.rows.map { |row| [row.label, row.state, row.count, row.figure.first.last.round(9)] }
    assert_equal [["PEX", :classified, 3, 8.0], ["Copper", :classified, 1, 3.0], ["Missing type", :incomplete, 1, 1.0]],
                 rows.sort_by { |row| -row[3] }
    assert_equal [17, 34, 51], service.rows.find { |row| row.value == @pex }.colour
    copper = query("pipe_types.list", "ids" => [@copper]).dig("records", 0, "display", "color")
    assert_equal P::ColourModes.rgb(copper), service.rows.find { |row| row.value == @copper }.colour
    assert_equal 3, service.select_row(@pex, "classified")
    assert_equal @trunk + @loop, @model.selection.to_a
  end

  def test_turning_a_mode_on_and_off_writes_nothing
    the_case
    before = [@model.operations.length, @session.revision, STORE.read(@branch.first)]
    activate(P::ColourModes::BY_TYPE).deactivate
    assert_equal before, [@model.operations.length, @session.revision, STORE.read(@branch.first)]
  end

  private

  def activate(mode)
    service = ColourBy.for(@session)
    service.activate(mode)
    assert service.active?, @session.inspect
    service
  end

  def line(role, type_id, points, values = {})
    vertices = points.map { |at| @vertices[at] ||= Sketchup::Vertex.new(point(at)) }
    vertices.each_cons(2).map { |from, to| tag(Sketchup::Edge.new(next_id, from, to), type_id, role, values) }
  end

  def tag(edge, type_id, role, values = {})
    STORE.write(edge, { "id" => "ppe_#{format('%012d', edge.persistent_id)}", "schema_version" => 1,
                        "pipe_type_id" => type_id, "role" => role, "user_data" => {},
                        "extension_data" => {} }.merge(values))
    edge
  end

  def point(at)
    Geom::Point3d.new(*at.map { |value| value * INCHES })
  end

  def next_id
    @next_id += 1
  end

  def query(name, params = {})
    result = API.query(:context => @context, :name => "#{PREFIX}.#{name}", :params => params)
    assert_equal "completed", result["status"], result.inspect
    result.fetch("value")
  end

  def invoke(name, params)
    @sequence += 1
    API.invoke(:context => @context, :name => name, :params => params,
               :request => { "sequence" => @sequence, "expected_revision" => @session.revision })
  end
end
