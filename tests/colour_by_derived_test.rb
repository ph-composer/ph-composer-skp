# frozen_string_literal: true

require_relative "test_helper"

# Derived geometry on a Colour-by entry: world-space polygons and segments the service draws in the
# entry's colour, with or without an entity (context/EXTENSIBILITY.md, "Colour-by derived geometry").
# Every mode here is an outside feature's; nothing under colour_by/ names it.
class ColourByDerivedTest < PhComposerTestCase
  ColourBy = PhComposer::ColourBy
  Registry = PhComposer::Registry
  COLOUR = [10, 20, 30].freeze

  def setup
    super
    @model = Sketchup.active_model
    @session = PhComposer::Sessions.for(@model)
    @notices = []
    @unsubscribe = PhComposer::Sessions.on_notice { |_session, message, tone| @notices << [tone, message] }
  end

  def teardown
    @unsubscribe.call
    super
  end

  def point(x, y, z = 0)
    Geom::Point3d.new(x, y, z)
  end

  def square(size = 10, z = 0)
    [point(0, 0, z), point(size, 0, z), point(size, size, z), point(0, size, z)]
  end

  # One mode whose projection answers `entries.call(read)`.
  def install_mode(stroke: nil, &entries)
    probe = Module.new do
      define_singleton_method(:install) do |registry|
        registry.feature("outside.derived", :contract_version => 1)
                .colour_mode("outside.derived.by_shape", :label => "Shape", :entity_kind => "shape", :stroke => stroke,
                                                         :colours => ColourBy::Palette.fixed("a" => COLOUR)) do |read|
          entries.call(read)
        end
      end
    end
    Registry.install([probe])
    ColourBy.for(@session).activate("outside.derived.by_shape")
  end

  def entry(**fields)
    ColourBy::Entry.new(:value => "a", :label => "A", **fields)
  end

  def test_a_derived_only_entry_fills_outlines_and_counts_in_the_legend
    service = install_mode do
      segment = [point(0, 0, 5), point(10, 0, 5)]
      [entry(:derived => ColourBy::Derived.new(:polygons => [square], :segments => [segment]))]
    end
    assert_equal 6, service.fills.fetch(COLOUR).length, "two triangles"
    assert_equal 10, service.lines.fetch(COLOUR).length, "four outline segments and the segment"
    assert_equal [["A", 1]], service.rows.map { |row| [row.label, row.count] }
  end

  def test_an_entry_with_an_entity_and_shapes_draws_both
    face = Sketchup::Face.new(9001, {}, :points => square(4))
    @model.entities << face
    service = install_mode do
      [entry(:entity => face, :transform => Geom::Transformation.new, :path => [9001],
             :derived => ColourBy::Derived.new(:polygons => [square(10, 20)], :segments => []))]
    end
    assert_equal 12, service.fills.fetch(COLOUR).length, "the Face's two triangles and the shape's two"
    assert_equal 1, service.rows.first.count
  end

  def test_shapes_under_a_hidden_ancestor_or_tag_are_not_drawn_and_still_count
    tag = Sketchup::Tag.new("Hidden", false)
    hidden = Sketchup::Group.new(100, Sketchup::Entities.new([]))
    hidden.hidden = true
    tagged = Sketchup::Group.new(200, Sketchup::Entities.new([]))
    tagged.layer = tag
    @model.entities << hidden << tagged
    service = install_mode do
      [100, 200].map { |id|
        entry(:path => [id], :derived => ColourBy::Derived.new(:polygons => [square], :segments => []))
      }
    end
    assert_empty service.fills
    assert_equal 2, service.rows.first.count
  end

  def test_a_concave_polygon_triangulates_to_its_own_area
    l_shape = [point(0, 0), point(20, 0), point(20, 10), point(10, 10), point(10, 20), point(0, 20)]
    service = install_mode { [entry(:derived => ColourBy::Derived.new(:polygons => [l_shape], :segments => []))] }
    triangles = service.fills.fetch(COLOUR).each_slice(3).to_a
    area = triangles.sum do |a, b, c|
      (((b.x - a.x) * (c.y - a.y)) - ((b.y - a.y) * (c.x - a.x))).abs / 2.0
    end
    assert_equal 4, triangles.length
    assert_in_delta 300.0, area, 1e-9
  end

  def test_a_degenerate_polygon_draws_nothing_and_raises_nothing
    collinear = [point(0, 0), point(5, 0), point(10, 0)]
    warped = [point(0, 0, 0), point(10, 0, 0), point(10, 10, 5), point(0, 10, 0)]
    repeated = [point(0, 0), point(0, 0), point(0, 0)]
    service = install_mode do
      [entry(:derived => ColourBy::Derived.new(:polygons => [collinear, warped, repeated], :segments => []))]
    end
    assert service.active?
    assert_empty service.fills
    assert_equal 1, service.rows.first.count
  end

  def test_a_non_finite_vertex_anywhere_makes_the_polygon_degenerate
    nan = Float::NAN
    polygons = [0, 2, 4].map { |index| square.insert(index, point(nan, 0)) }
    service = install_mode { [entry(:derived => ColourBy::Derived.new(:polygons => polygons, :segments => []))] }
    assert_empty service.fills
    assert_empty service.lines
  end

  # An entry with an entity keeps the identity check: shapes are not drawn when the path names another
  # entity, just as the entity is not.
  def test_shapes_on_an_entity_entry_whose_path_names_another_entity_are_not_drawn
    face = Sketchup::Face.new(9001, {}, :points => square(4))
    other = Sketchup::Face.new(9002, {}, :points => square(4))
    @model.entities << face << other
    service = install_mode do
      [entry(:entity => face, :transform => Geom::Transformation.new, :path => [9002],
             :derived => ColourBy::Derived.new(:polygons => [square(10, 20)], :segments => []))]
    end
    assert_empty service.fills
  end

  def test_shapes_on_a_hidden_or_tagged_entity_without_a_path_are_not_drawn
    hidden = Sketchup::Face.new(9001, {}, :points => square(4))
    hidden.hidden = true
    tagged = Sketchup::Face.new(9002, {}, :points => square(4))
    tagged.layer = Sketchup::Tag.new("Hidden", false)
    @model.entities << hidden << tagged
    service = install_mode do
      [hidden, tagged].map do |face|
        entry(:entity => face, :transform => Geom::Transformation.new,
              :derived => ColourBy::Derived.new(:polygons => [square(10, 20)], :segments => []))
      end
    end
    assert_empty service.fills
    assert_equal 2, service.rows.first.count
  end

  def test_a_point_repeated_anywhere_in_the_loop_makes_it_degenerate
    loop = [point(0, 0), point(10, 0), point(10, 10), point(0, 10), point(10, 0)]
    service = install_mode { [entry(:derived => ColourBy::Derived.new(:polygons => [loop], :segments => []))] }
    assert_empty service.fills
  end

  def test_a_malformed_shape_turns_the_mode_off_with_a_warning
    service = install_mode { [entry(:derived => ColourBy::Derived.new(:polygons => ["not points"], :segments => []))] }
    refute service.active?
    assert_equal :warning, @notices.last.first
  end

  # The mask and Show only this apply to the entry's path as a whole: polygons join the wash, segments go.
  def test_a_masked_or_set_aside_entry_washes_its_polygons_and_drops_its_segments
    shapes = ColourBy::Derived.new(:polygons => [square], :segments => [[point(0, 0), point(1, 1)]])
    service = install_mode { [entry(:path => [42], :derived => shapes)] }
    @model.entities << Sketchup::Group.new(42, Sketchup::Entities.new([]))
    service.invalidate!(:force => true)
    service.filter([[7]])
    assert_empty service.fills
    assert_empty service.lines
    assert_equal 6, service.wash_triangles.length
  end

  # An Edge contributes no Face geometry, so an entry carrying one draws only its derived
  # segment, as its projection placed it in the world, and its row still selects the Edge.
  def test_an_edge_entry_draws_only_its_world_segment_and_its_row_selects_the_edge
    edge = Sketchup::Edge.new(9101, point(0, 0), point(10, 0))
    # A quarter turn about z, then 100 inches along x.
    turn = Geom::Transformation.new([0, 1, 0, 0, -1, 0, 0, 0, 0, 0, 1, 0, 100, 0, 0, 1])
    @model.entities << Sketchup::Group.new(9100, Sketchup::Entities.new([edge]), :transformation => turn)
    world = [edge.start.position, edge.end.position].map { |position| position.transform(turn) }
    service = install_mode do
      [entry(:entity => edge, :transform => turn, :path => [9100, 9101],
             :derived => ColourBy::Derived.new(:polygons => [], :segments => [world]))]
    end
    assert_empty service.fills
    assert_empty service.unclassified_outlines
    drawn = service.lines.fetch(COLOUR).map { |each| [each.x, each.y, each.z] }
    assert_equal [[100.0, 0.0, 0.0], [100.0, 10.0, 0.0]], drawn
    assert_equal 1, service.select_row("a", "classified")
    assert_equal [edge], @model.selection.to_a
  end

  # A mode's stroke is the width of its derived lines; the unclassified outline keeps the overlay's own.
  def test_a_modes_stroke_sets_the_width_of_its_derived_lines_only
    segment = [point(0, 0), point(10, 0)]
    install_mode(:stroke => 6) do
      [entry(:derived => ColourBy::Derived.new(:polygons => [], :segments => [segment])),
       ColourBy::Entry.new(:value => nil, :derived => ColourBy::Derived.new(:polygons => [], :segments => [segment]))]
    end
    view = @model.active_view
    @model.overlays.to_a.first.draw(view)
    lines = view.draws.select { |mode, *| mode == GL_LINES }
    widths = lines.map { |_mode, _points, colour, width| [colour.red, width] }
    assert_includes widths, [COLOUR.first, 6], "the mode's coloured segment"
    assert_includes widths, [ColourBy::Palette::UNCLASSIFIED.first, ColourBy::Overlay::LINE_WIDTH]
  end

  def test_a_mode_without_a_stroke_draws_its_lines_at_the_outline_weight
    segment = [point(0, 0), point(1, 0)]
    install_mode { [entry(:derived => ColourBy::Derived.new(:polygons => [], :segments => [segment]))] }
    view = @model.active_view
    @model.overlays.to_a.first.draw(view)
    assert_equal [ColourBy::Overlay::LINE_WIDTH], view.draws.select { |mode, *| mode == GL_LINES }.map(&:last).uniq
  end

  def test_a_stroke_outside_one_to_ten_pixels_refuses_registration
    [0, 11, 2.5, "4"].each do |stroke|
      probe = Module.new do
        define_singleton_method(:name) { "Probe" }
        define_singleton_method(:install) do |registry|
          registry.feature("outside.derived", :contract_version => 1)
                  .colour_mode("outside.derived.thick", :label => "Thick", :entity_kind => "shape", :stroke => stroke,
                                                        :colours => ColourBy::Palette.ramp) { |_read| [] }
        end
      end
      error = assert_raises(PhComposer::RegistrationError, stroke.inspect) { Registry.install([probe]) }
      assert_includes error.diagnostics.map(&:code), "registration.schema_invalid"
    end
  end

  # A tag shows only while every tag folder holding it shows, so shapes under a hidden folder are not drawn.
  def test_shapes_under_a_tag_in_a_hidden_tag_folder_are_not_drawn_and_still_count
    tag = Sketchup::Tag.new("Shown", true, Sketchup::LayerFolder.new("Hidden folder", false))
    group = Sketchup::Group.new(300, Sketchup::Entities.new([]))
    group.layer = tag
    @model.entities << group
    service = install_mode do
      [entry(:path => [300], :derived => ColourBy::Derived.new(:polygons => [square], :segments => []))]
    end
    assert_empty service.fills
    assert_equal 1, service.rows.first.count
  end

  # A row of shapes alone is framed, and nothing is selected, rather than refused.
  def test_a_row_of_shapes_alone_frames_and_selects_nothing
    service = install_mode { [entry(:derived => ColourBy::Derived.new(:polygons => [square], :segments => []))] }
    assert_equal 0, service.select_row("a", "classified")
    assert_empty @model.selection.to_a
  end
end
