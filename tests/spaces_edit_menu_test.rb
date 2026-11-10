# frozen_string_literal: true

require_relative "test_helper"
require_relative "support/space_fixtures"

# Right-click editing for Spaces: Set Weighting Factor on Floor Segment Faces, Volumes and Spaces, and Move to
# Zone, Set Number…, Set Name… and Set Airflows… on selected Spaces. Each item is offered only on its selection,
# each change is one Undo step, and a dialog field left as shown writes nothing.
class SpacesEditMenuTest < PhComposerTestCase
  include SpaceFixtures

  API = PhComposer::API
  FACTOR = PhComposer::Spaces::WeightingFactorMenu
  EDIT = PhComposer::Spaces::SpaceEditMenu
  SPACE_ITEMS = [EDIT::MOVE_MENU, EDIT::NUMBER, EDIT::NAME, EDIT::AIRFLOWS_LABEL].freeze
  # 60 m3/h as IP shows it, and 40 cfm in m3/h.
  CFM_60_M3H = "35.3"
  M3H_40_CFM = 40 / PhComposer::Units::DEFINITIONS.fetch("airflow").fetch(:factor)

  def setup
    super
    @model = Sketchup.active_model
    @session = PhComposer::Sessions.for(@model)
    @notices = []
    PhComposer::Sessions.on_notice { |_session, message, tone| @notices << [message, tone] }
    reference_model
    @zone_a, @zone_b = @model.entities.to_a
    @living, @bath, @hall = @zone_a.entities.to_a
    @hall_volume, @hall_second = @hall.entities.to_a
    @operations = @model.operations.length
  end

  def test_each_item_is_offered_only_on_its_selection
    @model.active_path = [@zone_a]
    select(@living)
    assert_equal [EDIT::NUMBER, EDIT::NAME, EDIT::AIRFLOWS_LABEL, FACTOR::MENU, EDIT::MOVE_MENU], offered, "one Space"
    select(@living, @bath)
    assert_equal [EDIT::NAME, EDIT::AIRFLOWS_LABEL, FACTOR::MENU], offered, "several Spaces"
    @model.active_path = [@zone_a, @hall]
    select(@hall_volume)
    assert_equal [FACTOR::MENU], offered, "a Volume"
    @model.active_path = [@zone_a, @hall, @hall_volume]
    select(*@hall_volume.entities.to_a)
    assert_equal [FACTOR::MENU], offered, "a Floor Segment Face in the open Volume"
    unmarked = floor_face(1399, rectangle(9, 9, 1, 1))
    @hall_volume.entities << unmarked
    select(unmarked)
    assert_empty offered, "a Face not yet marked is Mark floor's"
    @model.active_path = []
    select(@zone_a)
    assert_equal [EDIT::NAME], offered, "a Zone: Zones' own Set Name… alone"
  end

  def test_move_to_zone_is_hidden_when_the_model_has_no_zones
    @model.entities.clear!
    space = space_group(3100, space_record("S", :number => "1"), [])
    @model.entities << space
    select(space)
    assert_equal [EDIT::NUMBER, EDIT::NAME, EDIT::AIRFLOWS_LABEL, FACTOR::MENU], offered
  end

  def test_weighting_factor_lists_one_then_the_factors_in_use_and_checks_only_a_shared_one
    @model.active_path = [@zone_a]
    select(@hall)
    assert_equal ["1", "0", FACTOR::OTHER], labels(FACTOR::MENU)
    assert_equal [MF_UNCHECKED, MF_UNCHECKED], checks(FACTOR::MENU), "Hall's Floor Segments differ"
    select(@living)
    assert_equal [MF_CHECKED, MF_UNCHECKED], checks(FACTOR::MENU)
  end

  def test_weighting_factor_at_space_scope_sets_every_floor_segment_in_one_undo_step
    @model.active_path = [@zone_a]
    select(@hall)
    choose(FACTOR::MENU, "1")
    assert_equal [1.0, 1.0], factors("103")
    select(@living)
    choose(FACTOR::MENU, "1")
    assert_equal ["The Floor Segment already had weighting factor 1. Nothing changed.", :success], @notices.last
    assert_equal @operations + 1, @model.operations.length
    assert @model.undo
    assert_equal [1.0, 0.0], factors("103")
  end

  def test_weighting_factor_at_volume_and_face_scope_sets_only_their_floor_segments
    @model.active_path = [@zone_a, @hall]
    select(@hall_volume)
    choose(FACTOR::MENU, "0")
    assert_equal [0.0, 0.0], factors("103"), "the Volume's one Floor Segment"
    @model.active_path = [@zone_a, @hall, @hall_second]
    select(*@hall_second.entities.to_a)
    choose(FACTOR::MENU, "1")
    assert_equal [0.0, 1.0], factors("103"), "the Face's own Floor Segment"
    assert_equal @operations + 2, @model.operations.length
  end

  def test_other_writes_a_typed_factor_and_writes_nothing_when_accepted_unchanged_or_invalid
    @model.active_path = [@zone_a]
    select(@hall)
    UI.inputbox_result = [""]
    choose(FACTOR::MENU, FACTOR::OTHER)
    assert_equal [[FACTOR::PROMPT], [""], FACTOR::MENU], UI.inputboxes.last, "Hall's factors differ"
    select(@living)
    UI.inputbox_result = ["1.0"]
    choose(FACTOR::MENU, FACTOR::OTHER)
    assert_equal [[FACTOR::PROMPT], ["1"], FACTOR::MENU], UI.inputboxes.last
    UI.inputbox_result = ["1.5"]
    choose(FACTOR::MENU, FACTOR::OTHER)
    assert_equal @operations, @model.operations.length
    assert_equal FACTOR::INVALID, @notices.last&.first
    UI.inputbox_result = ["0.6"]
    choose(FACTOR::MENU, FACTOR::OTHER)
    assert_equal [0.6], factors("101")
    assert_equal @operations + 1, @model.operations.length
  end

  def test_factors_that_round_alike_stay_distinct_choices_each_checked_on_its_own
    living_face, bath_face = [@living, @bath].map { |space| space.entities.to_a.first.entities.to_a.first }
    { living_face => 0.1234561, bath_face => 0.1234562 }.each do |face, factor|
      store = PhComposer::Spaces::FLOOR_SEGMENT_STORE
      store.write(face, store.read(face).merge("weighting_factor" => factor))
    end
    @model.active_path = [@zone_a]
    select(@living)
    assert_equal ["1", "0.1234562", "0.1234561", "0", FACTOR::OTHER], labels(FACTOR::MENU)
    assert_equal [MF_UNCHECKED, MF_UNCHECKED, MF_CHECKED, MF_UNCHECKED], checks(FACTOR::MENU)
  end

  def test_cancelling_any_dialog_writes_nothing
    @model.active_path = [@zone_a]
    select(@living)
    UI.inputbox_result = false
    dialogs = [[FACTOR::MENU, FACTOR::OTHER], [nil, EDIT::NUMBER], [nil, EDIT::NAME], [nil, EDIT::AIRFLOWS_LABEL]]
    dialogs.each { |menu, label| assert_nil choose(menu, label), label }
    assert_equal 4, UI.inputboxes.length
    assert_equal @operations, @model.operations.length
  end

  def test_move_to_zone_checks_the_current_zone_and_moves_the_space_in_one_step
    @model.active_path = [@zone_a]
    select(@living)
    assert_equal ["Zone A", "Zone B"], labels(EDIT::MOVE_MENU)
    assert_equal [MF_CHECKED, MF_UNCHECKED], checks(EDIT::MOVE_MENU)
    choose(EDIT::MOVE_MENU, "Zone A")
    assert_equal @operations, @model.operations.length, "its own Zone changes nothing"
    choose(EDIT::MOVE_MENU, "Zone B")
    assert_equal "zon_BBBBBBBBBBBB", space_record_of(@living).fetch("zone_id")
    assert_equal @operations + 1, @model.operations.length
  end

  def test_set_number_edits_one_space_and_set_name_edits_several_in_one_step
    @model.active_path = [@zone_a]
    select(@living)
    UI.inputbox_result = ["111"]
    choose(nil, EDIT::NUMBER)
    assert_equal [["Number"], ["101"], "Selected Space"], UI.inputboxes.last
    assert_equal "111", space_record_of(@living).fetch("number")
    select(@living, @bath)
    UI.inputbox_result = [""]
    choose(nil, EDIT::NAME)
    assert_equal [["Name"], [""], "Selected Spaces"], UI.inputboxes.last
    assert_equal @operations + 1, @model.operations.length, "a mixed name left blank clears nothing"
    UI.inputbox_result = ["Room"]
    choose(nil, EDIT::NAME)
    assert_equal %w[Room Room], [@living, @bath].map { |space| space_record_of(space).fetch("name") }
    assert_equal @operations + 2, @model.operations.length
  end

  def test_airflows_accepted_unchanged_in_ip_write_nothing
    PhComposer::Preferences.set("unit_system", "IP")
    @model.active_path = [@zone_a]
    select(@living)
    UI.inputbox_result = [CFM_60_M3H, "", ""]
    choose(nil, EDIT::AIRFLOWS_LABEL)
    prompts, defaults, title = UI.inputboxes.last
    assert_equal ["Supply (cfm)", "Extract (cfm)", "Transfer (cfm)"], prompts.map(&:strip)
    assert_equal [[CFM_60_M3H, "", ""], "Selected Space"], [defaults, title]
    UI.inputbox_result = ["#{CFM_60_M3H}0 ", "", ""]
    choose(nil, EDIT::AIRFLOWS_LABEL)
    assert_equal @operations, @model.operations.length, "the same number written another way"
    assert_equal 60.0, space_record_of(@living).fetch("v_sup_m3h"), "the shown rounding never drifts the value"
  end

  def test_airflows_round_trip_in_ip_and_si
    PhComposer::Preferences.set("unit_system", "IP")
    @model.active_path = [@zone_a]
    select(@living)
    UI.inputbox_result = [CFM_60_M3H, "40", ""]
    choose(nil, EDIT::AIRFLOWS_LABEL)
    assert_in_delta M3H_40_CFM, space_record_of(@living).fetch("v_eta_m3h"), 1e-9
    assert_equal 60.0, space_record_of(@living).fetch("v_sup_m3h")
    UI.inputbox_result = [CFM_60_M3H, "40", ""]
    choose(nil, EDIT::AIRFLOWS_LABEL)
    assert_equal [CFM_60_M3H, "40", ""], UI.inputboxes.last[1], "what was typed shows again"
    PhComposer::Preferences.set("unit_system", "SI")
    UI.inputbox_result = ["75", "68", "12.5"]
    choose(nil, EDIT::AIRFLOWS_LABEL)
    prompts, defaults, = UI.inputboxes.last
    assert_equal ["Supply (m³/h)", "Extract (m³/h)", "Transfer (m³/h)"], prompts.map(&:strip)
    assert_equal ["60", "68", ""], defaults
    assert_equal [75.0, M3H_40_CFM, 12.5], space_record_of(@living).values_at(*PhComposer::Spaces::AIRFLOWS)
    assert_equal @operations + 2, @model.operations.length
  end

  def test_a_mixed_airflow_shown_blank_is_kept_and_an_emptied_one_is_removed
    @model.active_path = [@zone_a]
    write_airflows(@bath, "v_sup_m3h" => 60.0, "v_eta_m3h" => 40.0)
    select(@living, @bath)
    UI.inputbox_result = ["", "", "15"]
    choose(nil, EDIT::AIRFLOWS_LABEL)
    assert_equal ["60", "", ""], UI.inputboxes.last[1], "only Supply is shared"
    assert_equal [nil, nil, 15.0], space_record_of(@living).values_at(*PhComposer::Spaces::AIRFLOWS)
    assert_equal [nil, 40.0, 15.0], space_record_of(@bath).values_at(*PhComposer::Spaces::AIRFLOWS)
    assert_equal @operations + 1, @model.operations.length
  end

  def test_all_three_airflows_emptied_return_the_space_to_its_zones_load
    @model.active_path = [@zone_a]
    write_airflows(@living, "v_sup_m3h" => 60.0, "v_eta_m3h" => 40.0, "v_tran_m3h" => 5.0)
    select(@living)
    UI.inputbox_result = ["", "", ""]
    choose(nil, EDIT::AIRFLOWS_LABEL)
    assert_equal "inheriting", space_row("101").fetch("airflow_mode")
    assert_empty space_record_of(@living).slice(*PhComposer::Spaces::AIRFLOWS)
  end

  def test_an_airflow_that_is_not_a_number_of_zero_or_more_writes_nothing
    @model.active_path = [@zone_a]
    select(@living)
    %w[abc -1].each do |text|
      UI.inputbox_result = [text, "", ""]
      choose(nil, EDIT::AIRFLOWS_LABEL)
      assert_equal EDIT::INVALID_AIRFLOW, @notices.last&.first
    end
    assert_equal @operations, @model.operations.length
  end

  private

  def select(*entities)
    @model.selection.clear
    entities.each { |entity| @model.selection.add(entity) }
  end

  def context_menu
    PhComposer::Commands.install_feature_menus(UI::Menu.new("Context"), :contextual => true)
  end

  # The Spaces edit items on the right-click, in its order: the items in the extension's own menu, then the submenus.
  def offered
    menus = context_menu
    own = menus.fetch(PhComposer::EXTENSION_NAME, UI::Menu.new("")).entries.grep(Array).map(&:first)
    (own + menus.keys).select { |label| [FACTOR::MENU, *SPACE_ITEMS].include?(label) }
  end

  # The menu the items sit in: a named submenu, or the extension's own menu when `menu` is nil.
  def menu_named(menu)
    context_menu.fetch(menu || PhComposer::EXTENSION_NAME)
  end

  def labels(menu)
    menu_named(menu).entries.select { |entry| entry.is_a?(Array) }.map(&:first)
  end

  # The check state of each item that shows one.
  def checks(menu)
    menu_named(menu).validation_procs.values.map(&:call)
  end

  def choose(menu, label)
    menu_named(menu).entries.find { |entry| entry.is_a?(Array) && entry.first == label }.last.call
  end

  def write_airflows(space, airflows)
    record = PhComposer::Spaces::SPACE_STORE.read(space).reject { |key, _| PhComposer::Spaces::AIRFLOWS.include?(key) }
    PhComposer::Spaces::SPACE_STORE.write(space, record.merge(airflows))
  end

  def space_record_of(space)
    PhComposer::Spaces::SPACE_STORE.read(space)
  end

  def space_row(number)
    context = API.connect(:session_id => @session.id)
    API.query(:context => context, :name => "ph_composer.spaces.all").dig("value", "spaces")
       .find { |row| row.dig("values", "number") == number }
  end

  # Each Floor Segment's weighting factor in the Space numbered `number`, in Volume order.
  def factors(number)
    space_row(number).fetch("volumes").flat_map do |volume|
      volume.fetch("floor_segments").map { |segment| segment.dig("values", "weighting_factor") }
    end
  end
end
