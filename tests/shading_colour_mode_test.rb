# frozen_string_literal: true

require_relative "test_helper"

# The Shading Colour-by mode over a stub Model: one entry per Shading Face occurrence, direct, inherited,
# nested and repeated, keyed by the component name it exports under, and nothing for an unmarked Face; the
# legend's rows agree with shading.list and sum area in the display units; a mark set or cleared through its
# actions redraws; a hidden tag hides the drawing and keeps the count; a flattened placement is amber.
class ShadingColourModeTest < PhComposerTestCase
  API = PhComposer::API
  ColourBy = PhComposer::ColourBy
  SH = PhComposer::Shading
  STORE = SH::Mark::STORE
  MODE = "ph_composer.shading.by_component"
  INCHES = 1 / 0.0254

  def setup
    super
    PhComposer.compose unless PhComposer::Registry.installed?(SH::FEATURE_ID)
    @model = Sketchup.active_model
    @session = PhComposer::Sessions.for(@model)
    @context = API.connect(:session_id => @session.id)
    @sequence = 0
    fixture
  end

  # Zone A (100) holds a marked overhang Face 101 (1 m2), an unmarked wall Face 102 and a marked Group "Fin"
  # (110) of Faces 111 and 112 (2 m2 each). At the root: marked loose Faces 5 and 6 (1 m2), an unmarked Face 8;
  # a marked Group "Neighbour" (20) of Face 21 (3 m2) and an unnamed Group (22) of Face 23 (1 m2); three marked
  # placements (40, 42, 43) of a component "Louvre" of Face 41 (0.5 m2), 2 m apart along y.
  def fixture
    @fin = Sketchup::Group.new(110, Sketchup::Entities.new([square(111, 2), square(112, 2)]), :name => "Fin")
    @zone = zone(100, "Zone A", [square(101, 1), square(102, 1), @fin])
    unnamed = Sketchup::Group.new(22, Sketchup::Entities.new([square(23, 1)]))
    @neighbour = Sketchup::Group.new(20, Sketchup::Entities.new([square(21, 3), unnamed]), :name => "Neighbour")
    louvre = Sketchup::ComponentDefinition.new(Sketchup::Entities.new([square(41, 0.5)]), :name => "Louvre")
    @louvres = [40, 42, 43].each_with_index.map do |id, index|
      Sketchup::ComponentInstance.new(id, louvre, :transformation => Geom::Transformation.translation(
        [0, 2 * index * INCHES, 0]
      ))
    end
    @loose = [square(5, 1), square(6, 1)]
    [@zone, *@loose, square(8, 1), @neighbour, *@louvres].each { |entity| @model.entities << entity }
    [live(100, 101), @fin, *@loose, @neighbour, *@louvres].each { |entity| STORE.write(entity, SH::Mark::RECORD) }
  end

  def test_one_entry_per_shading_face_occurrence_and_none_for_an_unmarked_face
    entries = SH::ColourModes.entries(@model)
    assert_equal [[5], [6], [20, 21], [20, 22, 23], [40, 41], [42, 41], [43, 41], [100, 101], [100, 110, 111],
                  [100, 110, 112]], entries.map(&:path).sort
    louvres = entries.select { |entry| entry.value == "Louvre" }
    assert_equal [0.0, 2.0, 4.0], louvres.map { |entry| (entry.transform.to_a[13] / INCHES).round(9) }.sort,
                 "each placement carries its own transform"
    mode = PhComposer::Registry.current.colour_modes.fetch(MODE)
    assert_equal ["Shading", "face", SH::FEATURE_ID], [mode.label, mode.entity_kind, mode.owner]
  end

  # A classified Zone Face under the marked Fin stays envelope: no entry, as shading.list does not count it.
  def test_a_classified_zone_face_under_a_marked_group_has_no_entry
    @fin.entities << square(113, 2)
    STORE.delete(@fin)
    classify([100, 110, 113])
    STORE.write(@fin, SH::Mark::RECORD)
    paths = SH::ColourModes.entries(@model).map(&:path)
    assert_includes paths, [100, 110, 111]
    refute_includes paths, [100, 110, 113]
    assert_equal 2, list.fetch("components").find { |row| row["display_name"] == "Fin" }.fetch("face_count")
  end

  def test_the_legend_rows_are_shading_lists_components_each_in_its_own_colour
    service = activate
    rows = service.rows.map { |row| [row.label, row.count, row.figure.first.last.round(9)] }.sort
    listed = list.fetch("components").map { |row| [row["display_name"], row["face_count"], row["area_m2"].round(9)] }
    assert_equal [["Fin", 2, 4.0], ["Louvre", 3, 1.5], ["Neighbour", 2, 4.0], ["Shading", 2, 2.0],
                  ["Zone A Shading", 1, 1.0]], rows
    assert_equal listed, rows
    assert_equal 5, service.rows.map(&:colour).uniq.length, "palette by name"
    assert(service.rows.all? { |row| row.state == :classified })
  end

  def test_the_legend_and_the_hud_read_count_and_area_in_the_display_units
    service = activate
    louvre = service.legend.fetch("rows").find { |row| row.fetch("label") == "Louvre" }
    assert_equal [3, "1.5 m²"], louvre.values_at("count", "figure")
    @model.overlays.to_a.first.draw(@model.active_view)
    assert_includes @model.active_view.texts.map { |(_point, text, _options)| text }, "Louvre (3) 1.5 m²"

    PhComposer::Preferences.set("unit_system", "IP")
    assert_match(/ft²\z/, service.legend.fetch("rows").first.fetch("figure"))
  ensure
    PhComposer::Preferences.set("unit_system", "SI")
  end

  # Through the registered actions, as the menu and a script reach them: the drawing rebuilds on the commit.
  def test_a_mark_set_or_cleared_through_its_actions_redraws_the_mode
    service = activate
    rebuilds = service.rebuilds
    assert_equal "committed", invoke("assign", [8])["effect"]
    assert_equal 3, count(service, "Shading")
    assert_equal "committed", invoke("clear", [20])["effect"]
    assert_nil count(service, "Neighbour")
    assert_operator service.rebuilds, :>=, rebuilds + 2
  end

  def test_a_hidden_tag_hides_the_drawing_and_keeps_the_count
    service = activate
    drawn = service.fills.values.flatten.length
    @louvres[1].layer = Sketchup::Tag.new("Hidden", false)
    service.invalidate!(:force => true)
    assert_equal 3, count(service, "Louvre")
    assert_operator service.fills.values.flatten.length, :<, drawn
  end

  # A placement scaled flat has no world area: its row is amber with none, and the mode stays on.
  def test_a_flattened_placement_is_amber_and_the_mode_stays_on
    @louvres[2].transformation = Geom::Transformation.scaling(0, 1, 1)
    service = activate
    flat = service.rows.find { |row| row.state == :incomplete }
    assert_equal ["Louvre", 1, nil, ColourBy::Palette::INCOMPLETE], [flat.label, flat.count, flat.figure, flat.colour]
    assert_equal 2, service.rows.find { |row| row.label == "Louvre" && row.state == :classified }.count
  end

  # The area comes from Face#area(transform), which must give the loops' figure under every placement
  # export meets: scaled, mirrored, rotated and with a hole. The stub's Face#area sums the same loops, so this
  # pins the routing and the unit conversion; the host's agreement is the measured row in
  # context/SKETCHUP_HOST_BEHAVIOR.md.
  def test_the_area_figure_is_the_faces_world_loop_area_under_scaled_and_mirrored_placements
    side = 2 * INCHES
    holed = Sketchup::Face.new(70, :points => [[0, 0, 0], [side, 0, 0], [side, side, 0], [0, side, 0]].map do |point|
      Geom::Point3d.new(*point)
    end, :holes => [[[0.5, 0.5, 0], [1, 0.5, 0], [1, 1, 0], [0.5, 1, 0]].map do |point|
      Geom::Point3d.new(*point.map { |metres| metres * INCHES })
    end])
    # A quarter turn about x, column-major, so the Face stands up out of its plane.
    rotation = Geom::Transformation.new([1, 0, 0, 0, 0, 0, 1, 0, 0, -1, 0, 0, 0, 0, 0, 1])
    scalings = [[1, 1, 1], [2, 3, 1], [-1, 1, 1], [-2, 0.5, 4]].map { |xyz| Geom::Transformation.scaling(*xyz) }
    transforms = scalings + [rotation * Geom::Transformation.scaling(1.5, 1, 1)]
    [square(71, 1), holed].product(transforms).each do |face, transform|
      assert_in_delta PhComposer::FaceCapture.call(face, transform).area_m2, SH::Inventory.area_m2(face, transform),
                      1e-9, transform.to_a.inspect
    end
  end

  # SketchUp's Face#area subtracts a glued cutting component's opening; the loops, and export, keep it.
  def test_a_face_with_a_glued_component_is_measured_from_its_loops
    face = @loose.first
    window = Sketchup::ComponentDefinition.new(Sketchup::Entities.new([]), :name => "Window")
    @model.entities << Sketchup::ComponentInstance.new(90, window, :glued_to => face)
    face.define_singleton_method(:area) { |*_| raise "Face#area is net of the glued opening" }
    assert_in_delta 1.0, SH::Inventory.area_m2(face, Geom::Transformation.new), 1e-9
  end

  private

  def activate
    service = ColourBy.for(@session)
    service.activate(MODE)
    assert service.active?, @session.inspect
    service
  end

  def count(service, label)
    service.rows.find { |row| row.label == label }&.count
  end

  # A square Face of `side` metres squared in area, in the xy plane at the origin.
  def square(persistent_id, area)
    side = Math.sqrt(area) * INCHES
    Sketchup::Face.new(persistent_id, :points => [[0, 0, 0], [side, 0, 0], [side, side, 0], [0, side, 0]].map do |point|
      Geom::Point3d.new(*point)
    end)
  end

  def zone(persistent_id, name, children)
    group = Sketchup::Group.new(persistent_id, Sketchup::Entities.new(children))
    PhComposer::Zones::ZONE_STORE.write(group,
                                        "id" => "zon_#{persistent_id.to_s.rjust(12, 'A')}", "schema_version" => 1,
                                        "name" => name, "building_segment" => "Building", "level" => nil,
                                        "ground_depth_mm" => 0.0, "user_data" => {}, "extension_data" => {})
    group
  end

  def live(*path)
    path.reduce(nil) do |parent, id|
      entities = parent.nil? ? @model.entities : parent.entities
      entities.to_a.find { |entity| entity.persistent_id == id }
    end
  end

  # Classifies a Zone Face as a Wall through Zones' own action, as a user would.
  def classify(path)
    host = API.query(:context => @context, :name => "ph_composer.zones.faces.host_context",
                     :params => { "paths" => [path] })
    reference = host.dig("value", "faces", 0, "reference")
    result = API.invoke(:context => @context, :name => "ph_composer.zones.faces.classify",
                        :params => { "faces" => [reference],
                                     "intent" => { "face_type" => { "mode" => "set", "value" => "Wall" } } },
                        :request => { "sequence" => (@sequence += 1), "expected_revision" => @session.revision })
    assert_equal "committed", result["effect"], result.inspect
  end

  def list
    result = API.query(:context => @context, :name => "#{SH::FEATURE_ID}.list", :params => {})
    assert_equal "completed", result["status"], result.inspect
    result.fetch("value")
  end

  def invoke(name, *paths)
    @sequence += 1
    API.invoke(:context => @context, :name => "#{SH::FEATURE_ID}.#{name}",
               :params => { "targets" => paths.map { |path| { "entity_path" => path } } },
               :request => { "sequence" => @sequence, "expected_revision" => @session.revision })
  end
end
