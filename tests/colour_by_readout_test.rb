# frozen_string_literal: true

require_relative "test_helper"

# Colour-by readouts: separately registered viewport text, on or off per Model session, shown with any
# mode and with none (context/EXTENSIBILITY.md, "Colour-by readouts"). The readouts here are an outside
# feature's; nothing under colour_by/ names them.
class ColourByReadoutTest < PhComposerTestCase
  ColourBy = PhComposer::ColourBy
  Registry = PhComposer::Registry
  READOUT = "outside.readout.labels"
  SELECTED = "outside.readout.selected"

  def setup
    super
    @model = Sketchup.active_model
    @session = PhComposer::Sessions.for(@model)
    @context = PhComposer::API.connect(:session_id => @session.id)
    @calls = Hash.new(0)
    @notices = []
    @unsubscribe = PhComposer::Sessions.on_notice { |_session, message, tone| @notices << [tone, message] }
  end

  def teardown
    @unsubscribe.call
    super
  end

  def install_readouts(anchors: nil, raising: false)
    calls = @calls
    anchors ||= [ColourBy::Anchor.new(:point => Geom::Point3d.new(1, 2, 3), :parts => ["Area ", ["area", 12.5]])]
    probe = Module.new do
      define_singleton_method(:install) do |registry|
        feature = registry.feature("outside.readout", :contract_version => 1)
        feature.colour_readout(READOUT, :label => "Labels") do |_read|
          calls[READOUT] += 1
          raise "the Model could not be read" if raising

          ColourBy::Readout.new(:anchors => anchors, :hud => [["Total ", ["area", 30.0]]])
        end
        feature.colour_readout(SELECTED, :label => "Selected", :selection => true) do |read|
          calls[SELECTED] += 1
          ColourBy::Readout.new(:anchors => [], :hud => [["#{read.selection.length} selected"]])
        end
      end
    end
    Registry.install([probe])
  end

  def toggle(name, on)
    PhComposer::API.view(:context => @context, :name => "ph_composer.colour_by.readout",
                         :params => { "readout" => name, "on" => on })
  end

  def drawn_texts
    view = @model.active_view
    view.texts.clear
    @model.overlays.to_a.each { |overlay| overlay.draw(view) }
    view.texts.map { |_point, text, _options| text }
  end

  def test_a_readout_toggles_and_draws_with_no_mode_and_with_one
    install_readouts
    on = toggle(READOUT, true)
    assert_equal [{ "name" => READOUT, "label" => "Labels", "selection" => false, "on" => true }],
                 on.dig("value", "readouts").select { |row| row["name"] == READOUT }
    assert_nil on.dig("value", "mode")
    assert_equal ["Area 12.5 m²", "Total 30 m²"], drawn_texts
    @model.entities << Sketchup::Face.new(9001, {})
    ColourBy.for(@session).activate("ph_composer.zones.faces.by_face_type")
    assert_includes drawn_texts, "Total 30 m²"
    off = toggle(READOUT, false)
    refute(off.dig("value", "readouts").any? { |row| row["name"] == READOUT && row["on"] })
    refute_includes drawn_texts, "Total 30 m²"
  end

  def test_the_display_units_format_the_quantities
    install_readouts
    PhComposer::Preferences.set("unit_system", "IP")
    toggle(READOUT, true)
    assert_includes drawn_texts, "Area 134.55 ft²"
  end

  def install_default_readout(outlines)
    probe = Module.new do
      define_singleton_method(:install) do |registry|
        registry.feature("outside.default", :contract_version => 1)
                .colour_readout("outside.default.show", :label => "Show", :on_by_default => true) do |_read|
          ColourBy::Readout.new(:anchors => [], :hud => [], :outlines => outlines)
        end
      end
    end
    Registry.install([probe])
  end

  def new_session_service
    model = Sketchup::Model.new
    [model, ColourBy.for(PhComposer::Sessions.for(model))]
  end

  def line_points(overlay_model)
    view = overlay_model.active_view
    overlay_model.overlays.to_a.each { |overlay| overlay.draw(view) }
    view.draws.select { |mode, *| mode == GL_LINES }.map { |_mode, points, *| points }
  end

  def test_a_readout_on_by_default_starts_on_in_a_new_session_and_draws_its_outline_with_no_mode
    from = Geom::Point3d.new(0, 0, 0)
    to = Geom::Point3d.new(10, 0, 0)
    install_default_readout([ColourBy::Outline.new(:points => [from, to])])
    model, service = new_session_service
    assert_includes service.readouts_on, "outside.default.show"
    refute service.active?
    assert_equal 1, model.overlays.to_a.length, "an outline to draw needs the overlay, with no mode on"
    assert model.overlays.to_a.first.enabled?
    assert_equal 1, line_points(model).length
  end

  # A tag hiding every Space empties the drawing and takes the overlay away; showing it again must not
  # undo the user's untick in SketchUp's Overlays panel. Turning a readout on is a choice to see it.
  def test_an_unticked_overlay_stays_unticked_when_the_drawing_empties_and_refills
    outlines = [ColourBy::Outline.new(:points => [Geom::Point3d.new(0, 0, 0), Geom::Point3d.new(1, 0, 0)])]
    install_default_readout(outlines)
    model, service = new_session_service
    model.overlays.to_a.first.enabled = false
    held = outlines.dup
    outlines.clear
    service.invalidate!(:force => true)
    assert_empty model.overlays.to_a
    outlines.concat(held)
    service.invalidate!(:force => true)
    refute model.overlays.to_a.first.enabled?, "a rebuild is not the user's choice"
    service.readout("outside.default.show", :on => true)
    assert model.overlays.to_a.first.enabled?, "turning the readout on is"
  end

  def test_a_readout_on_by_default_with_nothing_to_draw_adds_no_overlay
    install_default_readout([])
    model, service = new_session_service
    assert_includes service.readouts_on, "outside.default.show"
    assert_empty model.overlays.to_a
  end

  def test_an_outline_on_a_hidden_occurrence_is_not_drawn
    hidden = Sketchup::Group.new(110, Sketchup::Entities.new([]))
    hidden.hidden = true
    points = [Geom::Point3d.new(0, 0, 0), Geom::Point3d.new(1, 0, 0)]
    install_default_readout([ColourBy::Outline.new(:points => points, :path => [110])])
    @model.entities << hidden
    service = ColourBy.for(@session)
    service.readout("outside.default.show", :on => true)
    assert_equal [], service.readout_drawings.fetch("outside.default.show")[1]
  end

  def test_an_outline_with_an_odd_point_count_turns_the_readout_off
    install_default_readout([ColourBy::Outline.new(:points => [Geom::Point3d.new(0, 0, 0)])])
    service = ColourBy.for(@session)
    service.readout("outside.default.show", :on => true)
    refute_includes service.readouts_on, "outside.default.show"
  end

  def test_turning_the_last_readout_off_with_no_mode_removes_the_overlay
    install_readouts
    toggle(READOUT, true)
    assert_equal 1, @model.overlays.to_a.length
    toggle(READOUT, false)
    assert_empty @model.overlays.to_a
  end

  def test_a_selection_change_rebuilds_a_selection_readout_and_no_other
    install_readouts
    toggle(READOUT, true)
    toggle(SELECTED, true)
    before = @calls.dup
    @model.entities << Sketchup::Face.new(9002, {})
    @model.selection.add(@model.entities.to_a.last)
    assert_equal before[READOUT], @calls[READOUT]
    assert_operator @calls[SELECTED], :>, before[SELECTED]
    assert_includes drawn_texts, "1 selected"
  end

  def test_an_anchor_on_a_hidden_occurrence_is_not_drawn
    hidden = Sketchup::Group.new(100, Sketchup::Entities.new([]))
    hidden.hidden = true
    @model.entities << hidden
    install_readouts(:anchors => [ColourBy::Anchor.new(:point => Geom::Point3d.new(0, 0, 0), :parts => ["Hidden"],
                                                       :path => [100])])
    toggle(READOUT, true)
    refute_includes drawn_texts, "Hidden"
  end

  def test_applying_and_clearing_the_occurrence_mask_refreshes_the_anchors
    @model.entities << Sketchup::Group.new(42, Sketchup::Entities.new([]))
    install_readouts(:anchors => [ColourBy::Anchor.new(:point => Geom::Point3d.new(0, 0, 0), :parts => ["Masked"],
                                                       :path => [42])])
    toggle(READOUT, true)
    assert_includes drawn_texts, "Masked"
    ColourBy.for(@session).filter([])
    refute_includes drawn_texts, "Masked"
    ColourBy.for(@session).filter(nil)
    assert_includes drawn_texts, "Masked"
  end

  # Malformed output is caught where the readout is built: that readout goes off with a notice and the
  # others keep drawing; nothing raises inside draw.
  def test_malformed_output_turns_only_that_readout_off
    install_readouts(:anchors => [ColourBy::Anchor.new(:point => Geom::Point3d.new(0, 0, 0),
                                                       :parts => [["unknown_quantity", 1]])])
    toggle(SELECTED, true)
    toggle(READOUT, true)
    refute ColourBy.for(@session).readouts_on.include?(READOUT)
    assert_equal :warning, @notices.last.first
    assert_includes drawn_texts, "0 selected"
  end

  def test_an_anchor_with_a_non_numeric_coordinate_turns_its_readout_off
    point = Struct.new(:x, :y, :z).new("bad", 0, 0)
    install_readouts(:anchors => [ColourBy::Anchor.new(:point => point, :parts => ["Bad"])])
    toggle(READOUT, true)
    refute ColourBy.for(@session).readouts_on.include?(READOUT)
    refute_includes drawn_texts, "Bad"
  end

  def test_the_overlay_goes_when_the_last_readout_fails_on_a_later_rebuild
    failing = [false]
    calls = @calls
    probe = Module.new do
      define_singleton_method(:install) do |registry|
        registry.feature("outside.later", :contract_version => 1).colour_readout("outside.later.text",
                                                                                 :label => "Later") do |_read|
          calls["later"] += 1
          raise "the Model could not be read" if failing.first

          ColourBy::Readout.new(:anchors => [], :hud => [["ok"]])
        end
      end
    end
    Registry.install([probe])
    toggle("outside.later.text", true)
    assert_equal 1, @model.overlays.to_a.length
    failing[0] = true
    ColourBy.for(@session).invalidate!(:force => true)
    refute_includes ColourBy.for(@session).readouts_on, "outside.later.text"
    assert_empty @model.overlays.to_a
  end

  def test_a_readout_that_raises_is_turned_off_with_a_notice
    install_readouts(:raising => true)
    toggle(READOUT, true)
    refute ColourBy.for(@session).readouts_on.include?(READOUT)
    assert_equal :warning, @notices.last.first
  end

  def test_a_readout_is_dropped_on_detach
    install_readouts
    toggle(READOUT, true)
    service = ColourBy.for(@session)
    PhComposer::Sessions.detach(@model)
    assert_empty service.readouts_on
  end

  def test_registration_refuses_a_duplicate_name_and_a_name_outside_its_owner
    install_readouts
    duplicate = Module.new do
      define_singleton_method(:install) do |registry|
        registry.feature("outside.other", :contract_version => 1)
                .colour_readout(READOUT, :label => "Again") { |_read| nil }
      end
    end
    error = assert_raises(PhComposer::RegistrationError) { Registry.install([duplicate]) }
    assert_match(/registration\.(duplicate_id|schema_invalid)/, error.message)
    unlabelled = Module.new do
      define_singleton_method(:install) do |registry|
        registry.feature("outside.blank", :contract_version => 1).colour_readout("outside.blank.text", :label => "") do
          nil
        end
      end
    end
    assert_raises(PhComposer::RegistrationError) { Registry.install([unlabelled]) }
  end

  def test_the_menu_lists_readouts_under_the_modes_and_checks_those_on
    install_readouts
    PhComposer::Commands.install
    menu = PhComposer::Commands.colour_by_menu
    labels = menu.entries.select { |entry| entry.is_a?(Array) }.map(&:first)
    assert_operator labels.index("Labels"), :>, labels.index("Off")
    menu.entries.find { |entry| entry.is_a?(Array) && entry.first == "Labels" }.last.call
    assert_equal MF_CHECKED, PhComposer::Commands.readout_check(READOUT)
    assert_nil ColourBy.for(@session).mode_name, "a readout turns no mode on"
  end
end
