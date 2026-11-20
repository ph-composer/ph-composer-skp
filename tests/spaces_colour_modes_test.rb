# frozen_string_literal: true

require_relative "test_helper"
require_relative "support/space_fixtures"

# The four Spaces Colour-by modes on the reference model: what each colours, its legend labels, counts and
# figures, the prisms they draw, a Volume with no height, colours that stay with a Space, and that none of
# it writes to the Model or names Spaces under colour_by/ (context/EXTENSIBILITY.md, "Colour-by modes").
class SpacesColourModesTest < PhComposerTestCase
  include SpaceFixtures

  MODES = PhComposer::Spaces::ColourModes
  PREFIX = "ph_composer.spaces"

  def setup
    super
    @model = Sketchup.active_model
    @session = PhComposer::Sessions.for(@model)
  end

  def test_by_space_colours_each_volume_by_its_space_and_sums_weighted_area
    reference_model
    rows = legend("by_space")
    assert_equal({ "101 Living" => [1, [12.0]], "102 Bath" => [1, [4.0]], "103 Hall" => [2, [4.0]],
                   "201 Loft" => [1, [12.0]] }, rows)
    living = MODES.by_space(MODES.views(read)).find { |entry| entry.label == "101 Living" }
    assert_kind_of Sketchup::Group, living.entity
    assert_equal 6, living.derived.polygons.length, "one prism: a base, a top and four sides"
  end

  def test_by_ventilation_names_what_each_space_supplies_and_counts_a_spaces_rate_once
    reference_model
    assert_equal({ "Supply only" => [1, [60.0]], "Extract only" => [1, [40.0]], "Transfer only" => [2, [20.0]],
                   "By Program" => [1, nil] }, legend("by_ventilation"))
    explicit = PhComposer::Spaces::ColourModes.ventilation({ "v_sup_m3h" => 0.0 }, "detailed")
    assert_equal "none", explicit, "a rate set to zero is no airflow, not the Program's"
    blank = PhComposer::Spaces::ColourModes.ventilation({}, "detailed")
    assert_equal "none", blank, "a blank Space in a detailed Zone exports 0"
    assert_equal "ventilation", registered("by_ventilation").group
  end

  def test_by_weighting_factor_colours_each_segment_with_its_own_prism_and_sums_floor_area
    reference_model
    assert_equal({ "1" => [4, [32.0]], "0" => [1, [2.0]] }, legend("by_weighting_factor"))
    entries = MODES.by_weighting_factor(MODES.views(read))
    assert(entries.all? { |entry| entry.entity.is_a?(Sketchup::Face) && entry.derived.polygons.length == 6 })
  end

  # "0.25" and "0.52" share a byte sum, so the ramp alone gave the two bands one colour.
  def test_weighting_factor_bands_draw_in_different_colours
    segments = [floor_face(1311, rectangle(0, 0, 2, 2), segment_record("A", :weighting_factor => 0.25)),
                floor_face(1312, rectangle(2, 0, 2, 2), segment_record("B", :weighting_factor => 0.52))]
    volume = volume_group(1310, volume_record("V"), segments)
    @model.entities << zone_group(1000, "Z", [space_group(1300, space_record("S", :number => "1"), [volume])])
    colours = activate("by_weighting_factor").rows.to_h { |row| [row.value, row.colour] }
    refute_equal colours.fetch("0.25"), colours.fetch("0.52")
  end

  def test_by_height_bands_volumes_to_a_tenth_of_a_metre_lowest_first_and_sums_net_volume
    reference_model
    service = activate("by_height")
    assert_equal [["2.4", 1, 9.6], ["2.5", 2, 40.0], ["3.0", 1, 36.0], ["5.0", 1, 10.0]],
                 service.rows.map { |row| [row.value, row.count, row.figure.first.last.round(6)] }
    assert_equal "2.5 m", service.legend.fetch("rows")[1].fetch("label")
  end

  def test_a_volume_with_no_height_has_no_prism_is_incomplete_and_still_counts
    hall = space_group(1300, space_record("H", :number => "103", :name => "Hall"),
                       [volume_group(1310, volume_record("H", :height => nil),
                                     [floor_face(1311, rectangle(0, 0, 2, 2), segment_record("H"))])])
    @model.entities << zone_group(1000, "A", [hall])
    entry = MODES.by_space(MODES.views(read)).first
    assert_empty entry.derived.polygons
    assert_equal :incomplete, entry.state
    assert_equal [[nil, :incomplete, 1]], activate("by_height").rows.map { |row| [row.value, row.state, row.count] }
  end

  def test_a_space_with_supply_and_extract_shows_both_sums
    both = space_group(1100, space_record("L", :number => "101", :name => "Living",
                                               :airflows => { "v_sup_m3h" => 60.0, "v_eta_m3h" => 40.0 }),
                       [volume_group(1110, volume_record("L"), [floor_face(1111, rectangle(0, 0, 3, 4),
                                                                           segment_record("L"))])])
    @model.entities << zone_group(1000, "A", [both])
    assert_equal({ "Supply and extract" => [1, [60.0, 40.0]] }, legend("by_ventilation"))
  end

  def test_a_volume_with_a_blocking_finding_is_incomplete_and_an_empty_one_still_counts
    nested = volume_group(1110, volume_record("L"), [floor_face(1111, rectangle(0, 0, 3, 4), segment_record("L"))])
    wrapper = Sketchup::Group.new(1105, Sketchup::Entities.new([nested]))
    empty = volume_group(1120, volume_record("M", :number => 2, :height => 2.5), [])
    @model.entities << zone_group(1000, "A", [space_group(1100, space_record("L", :number => "101"),
                                                          [wrapper, empty])])
    states = MODES.by_space(MODES.views(read)).to_h { |entry| [entry.path.last, entry.state] }
    assert_equal :incomplete, states.fetch(1110), "a nested Volume blocks export"
    assert_nil states.fetch(1120), "an empty Volume does not block export"
    rows = activate("by_weighting_factor").rows.map { |row| [row.label, row.state, row.count] }
    assert_includes rows, ["No Floor Segment", :incomplete, 1]
  end

  def test_a_misplaced_floor_segment_inside_a_volume_makes_it_incomplete
    stray = Sketchup::Group.new(1115, Sketchup::Entities.new([floor_face(1116, rectangle(0, 0, 1, 1),
                                                                         segment_record("S"))]))
    volume = volume_group(1110, volume_record("L"), [floor_face(1111, rectangle(1, 0, 2, 2), segment_record("L")),
                                                     stray])
    @model.entities << zone_group(1000, "A", [space_group(1100, space_record("L", :number => "101"), [volume])])
    assert_equal :incomplete, MODES.by_space(MODES.views(read)).first.state
  end

  def test_copied_space_occurrences_each_add_their_own_rates
    spaces = [1100, 1200].map do |id|
      space_group(id, space_record("L", :number => "101", :airflows => { "v_sup_m3h" => 60.0 }),
                  [volume_group(id + 10, volume_record("L"), [floor_face(id + 11, rectangle(0, 0, 1, 1),
                                                                         segment_record("L"))])])
    end
    @model.entities << zone_group(1000, "A", spaces)
    treat_duplicates_as_existing(@model)
    row = activate("by_ventilation").rows.first
    assert_equal [2, [["airflow", 120.0]]], [row.count, row.figure]
  end

  def test_height_bands_round_half_up_at_decimal_midpoints
    rooms = [[1100, 2.55], [1200, 2.65], [1300, 2.45]].map do |id, height|
      space_group(id, space_record(id.to_s[1], :number => id.to_s),
                  [volume_group(id + 10, volume_record(id.to_s[1], :height => height),
                                [floor_face(id + 11, rectangle(0, 0, 1, 1), segment_record(id.to_s[1]))])])
    end
    @model.entities << zone_group(1000, "A", rooms)
    assert_equal %w[2.5 2.6 2.7], activate("by_height").rows.map(&:value)
  end

  def test_a_space_keeps_its_colour_across_sessions_and_as_other_spaces_come_and_go
    reference_model
    before = colour_of("spc_LLLLLLLLLLLL")
    @model.entities.to_a.first.entities.delete(@model.entities.to_a.first.entities.to_a[1])
    PhComposer::Sessions.detach(@model)
    renewed = PhComposer::Sessions.for(@model)
    refute_same @session, renewed, "a new session"
    @session = renewed
    assert_equal before, colour_of("spc_LLLLLLLLLLLL")
  end

  def test_every_space_in_the_reference_model_has_its_own_colour
    reference_model
    rows = activate("by_space").rows
    assert_equal 4, rows.length
    assert_equal 4, rows.map(&:colour).uniq.length, "three of four Spaces shared one colour (#183)"
  end

  def test_switching_through_every_mode_writes_nothing
    reference_model
    operations = @model.operations.length
    revision = @session.revision
    service = PhComposer::ColourBy.for(@session)
    %w[by_space by_ventilation by_weighting_factor by_height].each do |mode|
      service.activate("#{PREFIX}.#{mode}")
      refute_empty service.rows, mode
    end
    service.deactivate
    assert_equal [operations, revision], [@model.operations.length, @session.revision]
  end

  def test_a_band_is_the_factors_shortest_exact_text_so_no_two_factors_share_one
    assert_equal %w[1 0 0.5 0.1234561 0.1234562 0.0078125],
                 [1.0, 0, 0.5, 0.1234561, 0.1234562, 0.0078125].map { |factor| MODES.band(factor) }
  end

  def test_nothing_under_colour_by_names_a_spaces_mode
    root = File.expand_path("../src/ph_composer/colour_by", __dir__)
    Dir.glob(File.join(root, "*.rb")).each do |path|
      source = File.read(path)
      refute_includes source, "spaces.by_", path
      refute_includes source, "Spaces::", path
    end
  end

  private

  def activate(mode)
    service = PhComposer::ColourBy.for(@session)
    service.activate("#{PREFIX}.#{mode}")
    service
  end

  # Label to [count, summed figure] for each legend row of the mode.
  def legend(mode)
    activate(mode).rows.to_h do |row|
      [row.label.to_s, [row.count, row.figure && row.figure.map { |_quantity, value| value.round(6) }]]
    end
  end

  def registered(mode)
    PhComposer::Registry.current.colour_modes.fetch("#{PREFIX}.#{mode}")
  end

  def read
    PhComposer::HandlerRequest.for(@session, :owner => "ph_composer.spaces", :name => "test")
  end

  def colour_of(value)
    activate("by_space").rows.find { |row| row.value == value }.colour
  end
end
