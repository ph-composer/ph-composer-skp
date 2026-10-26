# frozen_string_literal: true

require_relative "test_helper"

# The thermal-bridge Colour-by mode over a stub Model: each assigned Edge occurrence draws its world segment
# in its type's colour at the mode's stroke, the legend sums each type's length in the display units, and
# hidden occurrences keep their count. Nothing under colour_by/ names thermal bridges.
class ThermalBridgeColourModeTest < PhComposerTestCase
  API = PhComposer::API
  ColourBy = PhComposer::ColourBy
  TB = PhComposer::ThermalBridges
  STORE = TB::Assignment::STORE
  MODE = "ph_composer.thermal_bridges.by_type"
  INCHES = 1 / 0.0254
  PARAPET = [17, 34, 51].freeze

  def setup
    super
    PhComposer.compose unless PhComposer::Registry.installed?(TB::FEATURE_ID)
    @model = Sketchup.active_model
    @session = PhComposer::Sessions.for(@model)
    @context = API.connect(:session_id => @session.id)
    @sequence = 0
    @next_id = 1000
    @parapet = create_type("Parapet", "color" => "#112233")
    @balcony = create_type("Balcony")
  end

  # Zone A's group (100) holds a Parapet chain of 5, 4 and 5 m and an unassigned Edge; a wrapper (20), turned
  # a quarter about z and moved 10 m along x, holds Zone B's group (200), moved 1 m along its own y, with one
  # 4 m Balcony Edge.
  def reference
    @roof = chain([[5, 0, 3], [0, 0, 3], [0, 4, 3], [5, 4, 3]], @parapet)
    @loose = Sketchup::Edge.new(next_id, point_m(0, 0, 0), point_m(5, 0, 0))
    @zone_a = Sketchup::Group.new(100, Sketchup::Entities.new(@roof + [@loose]))
    @line = chain([[0, 0, 1.5], [4, 0, 1.5]], @balcony).first
    @zone_b = Sketchup::Group.new(200, Sketchup::Entities.new([@line]),
                                  :transformation => Geom::Transformation.translation([0, 1 * INCHES, 0]))
    @turn = Geom::Transformation.new([0, 1, 0, 0, -1, 0, 0, 0, 0, 0, 1, 0, 10 * INCHES, 0, 0, 1])
    @wrapper = Sketchup::Group.new(20, Sketchup::Entities.new([@zone_b]), :transformation => @turn)
    @model.entities << @zone_a << @wrapper
  end

  def test_each_assigned_edge_draws_once_as_its_world_segment_in_its_types_colour_at_the_modes_stroke
    reference
    service = activate
    assert_equal [["Parapet", 3, 14.0], ["Balcony", 1, 4.0]],
                 service.rows.map { |row| [row.label, row.count, row.figure.first.last.round(9)] }
    assert_empty service.fills, "an Edge has no Face geometry"
    assert_equal 6, service.lines.fetch(PARAPET).length, "three Edges, two points each"
    balcony = service.rows.find { |row| row.label == "Balcony" }.colour
    drawn = service.lines.fetch(balcony).map do |point|
      [point.x, point.y, point.z].map { |inches| (inches / INCHES).round(9) }
    end
    assert_equal [[9.0, 0.0, 1.5], [9.0, 4.0, 1.5]], drawn, "Zone B's move, then the wrapper's turn and move"
    assert_equal 8, service.lines.values.sum(&:length), "the unassigned Edge draws nothing"

    mode = PhComposer::Registry.current.colour_modes.fetch(MODE)
    assert_equal ["Thermal bridges", "edge"], [mode.label, mode.entity_kind]
    assert_operator mode.stroke, :>, ColourBy::Overlay::LINE_WIDTH, "thick, so it reads over SketchUp's own Edges"
    view = @model.active_view
    @model.overlays.to_a.first.draw(view)
    widths = view.draws.select { |kind, *| kind == GL_LINES }.map(&:last).uniq
    assert_equal [mode.stroke], widths, "every segment at the mode's stroke"
  end

  # A shared definition's Edge is one occurrence per placement: counted and drawn once for each placement.
  def test_an_edge_in_a_component_placed_twice_counts_and_draws_once_a_placement
    edge = chain([[0, 0, 0], [2, 0, 0]], @parapet).first
    definition = Sketchup::ComponentDefinition.new(Sketchup::Entities.new([edge]))
    [Geom::Transformation.new, Geom::Transformation.translation([0, 3 * INCHES, 0])].each_with_index do |place, index|
      @model.entities << Sketchup::ComponentInstance.new(300 + index, definition, :transformation => place)
    end
    service = activate
    rows = service.rows.map { |row| [row.label, row.count, row.figure.first.last.round(9)] }
    assert_equal [["Parapet", 2, 4.0]], rows
    drawn = service.lines.fetch(PARAPET).map { |point| (point.y / INCHES).round(9) }
    assert_equal [0.0, 0.0, 3.0, 3.0], drawn
  end

  def test_the_legend_and_the_hud_read_type_count_and_length_in_the_display_units
    reference
    service = activate
    rows = service.legend.fetch("rows").map { |row| row.values_at("label", "count", "figure") }
    assert_equal [["Parapet", 3, "14 m"], ["Balcony", 1, "4 m"]], rows
    @model.overlays.to_a.first.draw(@model.active_view)
    texts = @model.active_view.texts.map { |(_point, text, _options)| text }
    assert_equal ["Thermal bridges", "Parapet (3) 14 m", "Balcony (1) 4 m"], texts

    PhComposer::Preferences.set("unit_system", "IP")
    panel = service.legend.fetch("rows").first.fetch("figure")
    view = Sketchup::View.new(@model)
    @model.overlays.to_a.first.draw(view)
    assert_match(/ft\z/, panel)
    assert_equal "Parapet (3) #{panel}", view.texts[1][1], "the HUD and the panel show the same number"
  ensure
    PhComposer::Preferences.set("unit_system", "SI")
  end

  def test_an_edge_naming_a_missing_type_is_incomplete_and_an_invalid_assignment_draws_nothing
    reference
    missing = "tbt_ZZZZZZZZZZZZ"
    tag(@roof.first, missing)
    STORE.write(@roof.last, "id" => "tbe_broken", "schema_version" => 1)
    service = activate
    rows = service.rows.map { |row| [row.value, row.label, row.state, row.count] }
    assert_includes rows, [missing, "Missing type", :incomplete, 1]
    assert_includes rows, [@parapet, "Parapet", :classified, 1], "the invalid assignment is not counted"
    assert_equal 6, service.lines.values.sum(&:length), "the missing type, Parapet and Balcony; not the invalid one"
    assert_equal ColourBy::Palette::INCOMPLETE, service.rows.find { |row| row.value == missing }.colour
  end

  def test_a_hidden_tag_a_hidden_tag_folder_or_a_hidden_ancestor_hides_the_drawing_and_keeps_the_count
    reference
    in_folder = Sketchup::Tag.new("Roof edges", true, Sketchup::LayerFolder.new("Hidden folder", false))
    @roof[0].layer = Sketchup::Tag.new("Hidden", false)
    @roof[1].layer = in_folder
    @wrapper.hidden = true
    service = activate
    assert_equal [3, 1], service.rows.map(&:count)
    assert_equal 2, service.lines.values.sum(&:length), "only the third Parapet Edge draws"
  end

  def test_a_legend_row_selects_its_edges_and_show_only_this_drops_the_other_segments
    reference
    service = activate
    assert_equal 3, service.select_row(@parapet, "classified")
    assert_equal @roof, @model.selection.to_a
    service.isolate([@balcony, "classified"])
    assert_equal 2, service.lines.values.sum(&:length)
  end

  def test_turning_the_mode_on_and_off_writes_nothing_and_opens_no_operation
    reference
    before = [@model.operations.length, @session.revision, STORE.read(@line)]
    service = activate
    service.deactivate
    assert_equal before, [@model.operations.length, @session.revision, STORE.read(@line)]
  end

  def test_nothing_under_colour_by_names_thermal_bridges
    root = File.expand_path("../src/ph_composer/colour_by", __dir__)
    Dir.glob(File.join(root, "**", "*.rb")).each do |path|
      source = File.read(path)
      refute_includes source, "thermal_bridges", path
      refute_includes source, "ThermalBridges", path
    end
  end

  private

  def activate
    service = ColourBy.for(@session)
    service.activate(MODE)
    assert service.active?, @session.inspect
    service
  end

  def point_m(*metres)
    Geom::Point3d.new(*metres.map { |value| value * INCHES })
  end

  def chain(points, type_id)
    vertices = points.map { |point| Sketchup::Vertex.new(point_m(*point)) }
    vertices.each_cons(2).map { |from, to| tag(Sketchup::Edge.new(next_id, from, to), type_id) }
  end

  def tag(edge, type_id)
    STORE.write(edge, "id" => "tbe_#{format('%012d', edge.persistent_id)}", "schema_version" => 1,
                      "thermal_bridge_type_id" => type_id, "quantity" => 1, "user_data" => {},
                      "extension_data" => {})
    edge
  end

  def next_id
    @next_id += 1
  end

  def create_type(name, values = {})
    @sequence += 1
    API.invoke(:context => @context, :name => "#{TB::FEATURE_ID}.types.create",
               :params => { "values" => { "name" => name, "psi_w_mk" => 0.05 }.merge(values) },
               :request => { "sequence" => @sequence, "expected_revision" => @session.revision }).dig("value", "id")
  end
end
