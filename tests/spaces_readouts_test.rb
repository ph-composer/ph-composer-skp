# frozen_string_literal: true

require_relative "test_helper"
require_relative "support/space_fixtures"

# The Spaces readouts on the reference model: Show Spaces with its default and optional lines, and the
# selection totals, each Space counted once (context/EXTENSIBILITY.md, "Colour-by readouts").
class SpacesReadoutsTest < PhComposerTestCase
  include SpaceFixtures

  API = PhComposer::API
  LABELS = "ph_composer.spaces.show"
  TOTALS = "ph_composer.spaces.selection_totals"
  INCHES = 1.0 / 0.0254

  def setup
    super
    @model = Sketchup.active_model
    @session = PhComposer::Sessions.for(@model)
    @context = API.connect(:session_id => @session.id)
    reference_model
    @service = PhComposer::ColourBy.for(@session)
  end

  # W-046: labels and prisms show in a new session, with no Colour-by mode on and no one turning them on.
  def test_show_spaces_is_on_in_a_new_session_and_draws_labels_and_prisms_with_no_mode
    model = Sketchup.active_model
    PhComposer::Sessions.detach(model)
    service = PhComposer::ColourBy.for(PhComposer::Sessions.for(model))
    assert_includes service.readouts_on, LABELS
    refute service.active?
    assert_equal 1, model.overlays.count { |overlay| overlay.is_a?(PhComposer::ColourBy::Overlay) }
    view = model.active_view
    model.overlays.to_a.first.draw(view)
    assert_includes view.texts.map { |_point, text, _options| text }, "101 Living"
    assert_operator view.draws.count { |mode, *| mode == GL_LINES }, :>=, 1
  end

  def test_show_spaces_draws_the_floor_ring_at_the_floor_and_at_height_and_the_verticals
    @service.invalidate!(:force => true)
    anchors, lines = @service.readout_drawings.fetch(LABELS)
    refute_empty anchors
    zs = lines.map { |point| (point.z / INCHES).round(6) }.uniq.sort
    assert_includes zs, 0.0, "the floor ring"
    assert_includes zs, 2.5, "the ring at the Volume's height"
    verticals = lines.each_slice(2).count { |first, last| first.x == last.x && first.y == last.y && first.z != last.z }
    assert_operator verticals, :>, 0
  end

  def test_a_volume_with_no_height_keeps_its_label_and_draws_no_outline
    @model.entities.to_a.first.entities << space_group(
      1500, space_record("N", :number => "105", :name => "Attic"),
      [volume_group(1510, volume_record("N", :height => nil),
                    [floor_face(1511, rectangle(20, 20, 2, 2), segment_record("N"))])]
    )
    @service.invalidate!(:force => true)
    anchors, lines = @service.readout_drawings.fetch(LABELS)
    assert(anchors.any? { |anchor| anchor.parts.first == "105 Attic" })
    refute(lines.any? { |point| (point.x / INCHES) >= 20 }, "no height, no prism to outline")
  end

  def test_turning_show_spaces_off_takes_its_outlines_and_labels_away
    @service.invalidate!(:force => true)
    @service.readout(LABELS, :on => false)
    refute @service.readout_drawings.key?(LABELS)
  end

  def test_labels_name_each_space_at_its_largest_segments_centroid
    @service.readout(LABELS, :on => true)
    anchors = @service.readout_drawings.fetch(LABELS).first
    assert_equal ["101 Living", "102 Bath", "103 Hall", "201 Loft"], anchors.map { |anchor| anchor.parts.first }.sort
    living = anchors.find { |anchor| anchor.parts.first == "101 Living" }
    assert_equal [1.5, 2.0, 0.0], [living.point.x, living.point.y, living.point.z].map { |value|
      (value / INCHES).round(9)
    }
    loft = anchors.find { |anchor| anchor.parts.first == "201 Loft" }
    assert_in_delta 1.0, loft.point.z / INCHES, 1e-9, "a sloped segment's label sits at its mean height"
  end

  def test_each_option_adds_its_line_and_the_view_command_redraws_them
    @service.readout(LABELS, :on => true)
    result = API.view(:context => @context, :name => "ph_composer.spaces.labels.set_options",
                      :params => { "weighted_area" => true, "net_volume" => true, "airflows" => true })
    assert_equal "completed", result.fetch("status"), result.inspect
    living = @service.readout_drawings.fetch(LABELS).first.find { |anchor| anchor.parts.first == "101 Living" }
    assert_equal ["101 Living", "  ", ["area", 12.0], "  ", ["volume", 30.0], "  ", ["airflow", 60.0], " / ",
                  ["airflow", 0.0]], living.parts
    loft = @service.readout_drawings.fetch(LABELS).first.find { |anchor| anchor.parts.first == "201 Loft" }
    refute_includes loft.parts.flatten, "airflow", "an inheriting Space has no rates to show"
  end

  def test_a_space_with_no_floor_segment_has_no_label
    @model.entities.to_a.first.entities << space_group(1400, space_record("E", :number => "104"), [])
    @service.readout(LABELS, :on => true)
    refute(@service.readout_drawings.fetch(LABELS).first.any? { |anchor| anchor.parts.first.start_with?("104") })
  end

  def test_selection_totals_sum_two_spaces_and_count_a_space_and_its_own_volume_once
    @service.readout(TOTALS, :on => true)
    assert_equal [], @service.readout_drawings.fetch(TOTALS).last, "nothing selected, no lines"
    zone = @model.entities.to_a.first
    living, bath = zone.entities.to_a[0, 2]
    @model.active_path = [zone] # Spaces are selected inside their Zone's edit context
    @model.selection.add(living)
    @model.selection.add(bath)
    @service.selection_changed
    hud = @service.readout_drawings.fetch(TOTALS).last
    assert_equal ["2 Spaces selected"], hud[0]
    assert_in_delta 16.0, hud[1].last.last, 1e-9
    assert_in_delta 39.6, hud[2].last.last, 1e-9
    @model.selection.clear
    @model.selection.add(living)
    @model.selection.add(living.entities.to_a.first)
    @service.selection_changed
    assert_equal ["1 Space selected"], @service.readout_drawings.fetch(TOTALS).last.first
  end

  def test_a_label_sits_at_the_centroid_of_the_floor_less_its_opening_even_far_from_the_origin
    points = ->(corners) { corners.map { |x, y| Geom::Point3d.new(x * INCHES, y * INCHES, 0) } }
    holed = Sketchup::Face.new(3111, {}, :points => points.call(rectangle(0, 0, 10, 10)),
                                         :holes => [points.call(rectangle(6, 2, 3, 6))])
    SpaceFixtures::SPACES::FLOOR_SEGMENT_STORE.write(holed, segment_record("P"))
    far = floor_face(3211, rectangle(1_000_000.1, 1_000_000.1, 3.1, 4.1), segment_record("Q"))
    @model.entities << zone_group(3000, "C", [
      space_group(3100, space_record("P", :number => "301"), [volume_group(3110, volume_record("P"), [holed])]),
      space_group(3200, space_record("Q", :number => "302"), [volume_group(3210, volume_record("Q"), [far])])
    ])
    @service.readout(LABELS, :on => true)
    anchors = @service.readout_drawings.fetch(LABELS).first.to_h { |anchor| [anchor.parts.first, anchor.point] }
    assert_in_delta 4.4512195, anchors.fetch("301").x / INCHES, 1e-6
    assert_in_delta 5.0, anchors.fetch("301").y / INCHES, 1e-6
    assert_in_delta 1_000_001.65, anchors.fetch("302").x / INCHES, 1e-6
    assert_in_delta 1_000_002.15, anchors.fetch("302").y / INCHES, 1e-6
  end

  def test_selection_totals_count_a_space_with_no_volume_and_say_when_airflow_is_inherited
    zone = @model.entities.to_a.first
    empty = space_group(1400, space_record("E", :number => "104", :airflows => { "v_sup_m3h" => 15.0 }), [])
    zone.entities << empty
    @model.active_path = [zone]
    living = zone.entities.to_a.first
    [living, empty].each { |space| @model.selection.add(space) }
    @service.readout(TOTALS, :on => true)
    hud = @service.readout_drawings.fetch(TOTALS).last
    assert_equal ["2 Spaces selected"], hud[0]
    assert_equal ["Supply ", ["airflow", 75.0], "  Extract ", ["airflow", 0.0]], hud[3]
    @model.selection.clear
    loft_zone = @model.entities.to_a.last
    @model.active_path = [loft_zone]
    @model.selection.add(loft_zone.entities.to_a.first)
    @service.selection_changed
    assert_equal ["Supply and extract: 1 of 1 inherit the Zone's airflow"],
                 @service.readout_drawings.fetch(TOTALS).last[3]
  end

  def test_the_label_options_are_offered_on_a_space_volume_or_floor_segment_only
    menu = PhComposer::Registry.current.menu_items.fetch("ph_composer.spaces.labels_net_volume_menu")
    read = PhComposer::HandlerRequest.for(@session, :owner => menu.owner, :name => menu.name)
    @service.readout(LABELS, :on => true)
    segment = floor_face(9111, rectangle(0, 0, 1, 1), segment_record("Q"))
    volume = volume_group(9110, volume_record("Q"), [segment])
    [space_group(9100, space_record("Q", :number => "1", :name => "Q"), [volume]), volume, segment].each do |entity|
      @model.selection.clear
      @model.selection.add(entity)
      assert menu.available.call(read), entity.class.name
    end
    zone = zone_group(9001, "Z", [Sketchup::Face.new(9002)])
    [zone, zone.entities.to_a.first, Sketchup::Group.new(9003, Sketchup::Entities.new([]))].each do |entity|
      @model.selection.clear
      @model.selection.add(entity)
      refute menu.available.call(read), entity.class.name
    end
  end

  def test_turning_the_readouts_and_options_on_writes_nothing
    operations = @model.operations.length
    revision = @session.revision
    @service.readout(LABELS, :on => true)
    @service.readout(TOTALS, :on => true)
    API.view(:context => @context, :name => "ph_composer.spaces.labels.set_options",
             :params => { "net_volume" => true })
    assert_equal [operations, revision], [@model.operations.length, @session.revision]
  end
end
