# frozen_string_literal: true

require_relative "test_helper"
require_relative "support/space_fixtures"

# The duct direction and Duct Type Colour-by modes over the ERV ducting case on a stub Model: each duct occurrence
# draws its world segment at the modes' stroke, in its direction's fixed colour or its type's own; the legend's lengths,
# quantity applied, are the panel schedule's totals and the used lengths; a line with no assignment draws nothing.
class DuctingColourModeTest < PhComposerTestCase
  include SpaceFixtures

  API = PhComposer::API
  ColourBy = PhComposer::ColourBy
  D = PhComposer::Ducting
  STORE = D::Assignment::STORE
  PREFIX = "ph_composer.ducting"

  def setup
    super
    @model = Sketchup.active_model
    @session = PhComposer::Sessions.for(@model)
    @context = API.connect(:session_id => @session.id)
    @sequence = 0
    @next_id = 1000
    @erv1 = create("ph_composer.mechanical.ventilators.create", "name" => "ERV-1")
    @erv2 = create("ph_composer.mechanical.ventilators.create", "name" => "ERV-2")
    @dt1 = create("#{PREFIX}.duct_types.create", "name" => "DT-1", "color" => "#112233")
    @dt2 = create("#{PREFIX}.duct_types.create", "name" => "DT-2", "shape" => "rectangular", "width_mm" => 200.0,
                                                 "height_mm" => 100.0)
  end

  # DG-1 (600) moved 2 m along x holds ERV-1's two runs and one unassigned line; DG-2 (700) holds ERV-2's, its Exhaust
  # air at quantity 2.
  def the_case
    @vertices = {}
    @outdoor = line("outdoor_air", @dt1, [[1, 0.5, 2.8], [1, 2, 2.8], [2, 2, 2.8]])
    @exhaust = line("exhaust_air", @dt1, [[1.5, 0.5, 2.8], [1.5, 1.5, 2.8], [2.3, 1.5, 2.8]])
    loose = Sketchup::Edge.new(next_id, point([0, 0, 0]), point([0, 0, 1]))
    @model.entities << ducting_group(600, "dcg_DG1000000001", @erv1, @outdoor + @exhaust + [loose],
                                     Geom::Transformation.translation([2 * INCHES, 0, 0]))
    @rectangular = line("outdoor_air", @dt2, [[6, 0.5, 2.8], [6, 3, 2.8]]) +
                   line("exhaust_air", @dt2, [[7, 0.5, 2.8], [7, 2, 2.8]], 2)
    @model.entities << ducting_group(700, "dcg_DG2000000002", @erv2, @rectangular)
  end

  def test_by_direction_draws_each_duct_once_and_its_lengths_with_quantity_are_the_schedules_totals
    the_case
    service = activate(D::ColourModes::BY_DIRECTION)
    rows = service.rows.map { |row| [row.value, row.label, row.count, row.figure.first.last.round(9)] }
    assert_equal [["outdoor_air", "Outdoor air", 3, 5.0], ["exhaust_air", "Exhaust air", 3, 4.8]], rows
    totals = query("schedule.all").dig("totals", "by_direction")
                                  .to_h { |row| [row.fetch("direction"), row.fetch("length_m").round(9)] }
    assert_equal totals, service.rows.to_h { |row| [row.value, row.figure.first.last.round(9)] }
    assert_equal D::ColourModes::DIRECTION_COLOURS.fetch("outdoor_air"), service.rows.first.colour
    drawn = service.lines.fetch(D::ColourModes::DIRECTION_COLOURS.fetch("outdoor_air")).first(2).map do |at|
      [at.x, at.y, at.z].map { |inches| (inches / INCHES).round(9) }
    end
    assert_equal [[3.0, 0.5, 2.8], [3.0, 2.0, 2.8]], drawn, "the group's move applied"
    assert_equal 12, service.lines.values.sum(&:length), "six ducts, two points each; the loose line draws nothing"
    mode = PhComposer::Registry.current.colour_modes.fetch(D::ColourModes::BY_DIRECTION)
    assert_equal ["Duct direction", "edge", PhComposer::LineGroups::ColourModes::STROKE],
                 [mode.label, mode.entity_kind, mode.stroke]
  end

  def test_by_type_colours_each_duct_by_its_types_colour_equals_used_length_and_a_missing_type_is_incomplete
    the_case
    used = query("duct_types.all").fetch("records")
                                  .to_h { |row| [row.fetch("id"), row.fetch("used_length_m").round(9)] }
    service = activate(D::ColourModes::BY_TYPE)
    assert_equal used, service.rows.to_h { |row| [row.value, row.figure.first.last.round(9)] }
    assert_equal({ @dt1 => 4.3, @dt2 => 5.5 }, used)
    assert_equal [17, 34, 51], service.rows.find { |row| row.value == @dt1 }.colour
    STORE.write(@exhaust.last, STORE.read(@exhaust.last).merge("duct_type_id" => nil))
    rows = activate(D::ColourModes::BY_TYPE).rows.map { |row| [row.label, row.state, row.count] }
    assert_includes rows, ["Missing type", :incomplete, 1]
    assert_equal 2, activate(D::ColourModes::BY_TYPE).select_row(@dt2, "classified")
    assert_equal @rectangular, @model.selection.to_a
  end

  def test_turning_a_mode_on_and_off_writes_nothing
    the_case
    before = [@model.operations.length, @session.revision, STORE.read(@outdoor.first)]
    activate(D::ColourModes::BY_DIRECTION).deactivate
    assert_equal before, [@model.operations.length, @session.revision, STORE.read(@outdoor.first)]
  end

  private

  def activate(mode)
    service = ColourBy.for(@session)
    service.activate(mode)
    assert service.active?, @session.inspect
    service
  end

  def line(direction, type_id, points, quantity = 1)
    vertices = points.map { |at| @vertices[at] ||= Sketchup::Vertex.new(point(at)) }
    vertices.each_cons(2).map do |from, to|
      edge = Sketchup::Edge.new(next_id, from, to)
      STORE.write(edge, { "id" => "dce_#{format('%012d', edge.persistent_id)}", "schema_version" => 1,
                          "duct_type_id" => type_id, "direction" => direction, "quantity" => quantity,
                          "user_data" => {}, "extension_data" => {} })
      edge
    end
  end

  def point(at)
    Geom::Point3d.new(*at.map { |value| value * INCHES })
  end

  def ducting_group(persistent_id, id, ventilator_id, children, transformation = Geom::Transformation.new)
    group = Sketchup::Group.new(persistent_id, Sketchup::Entities.new(children), :transformation => transformation)
    D::Group::STORE.write(group, D::Group.new_record(id, ventilator_id))
    group
  end

  def next_id
    @next_id += 1
  end

  def query(name, params = {})
    result = API.query(:context => @context, :name => "#{PREFIX}.#{name}", :params => params)
    assert_equal "completed", result["status"], result.inspect
    result.fetch("value")
  end

  def create(name, values)
    invoke(name, "values" => values).dig("value", "id")
  end

  def invoke(name, params)
    API.invoke(:context => @context, :name => name, :params => params,
               :request => { "sequence" => @sequence += 1, "expected_revision" => @session.revision })
  end
end
