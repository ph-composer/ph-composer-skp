# frozen_string_literal: true

require_relative "test_helper"
require_relative "support/space_fixtures"
require_relative "support/zone_options"
require_relative "../tools/examples/authoring/ventilators_walkthrough"

class VentilatorsWalkthroughTest < PhComposerTestCase
  include SpaceFixtures
  include ZoneOptionsSupport

  def setup
    super
    PhComposer.compose unless PhComposer::Registry.installed?("ph_composer.mechanical")
  end

  def test_the_walkthrough_authors_ventilators_through_public_calls_and_undo_steps_back_through_it
    result = VentilatorsWalkthrough.run
    assert result.fetch("passed"), result.inspect
    assert_equal 5, result.fetch("steps").count { |step| %w[create update duplicate delete].include?(step["step"]) }
    model = Sketchup.active_model
    model.undo
    restored = VentilatorsWalkthrough.state
    erv2 = VentilatorsWalkthrough::ERV_1.merge("name" => "ERV-2", "quantity" => 1, "sensible_heat_recovery" => 0.75,
                                               "latent_heat_recovery" => 0.0, "electric_efficiency_wh_m3" => 0.55,
                                               "subsoil_heat_exchange_efficiency" => 0.2)
    assert_equal VentilatorsWalkthrough::EXPECTED + [[erv2, {}]], restored
    4.times { model.undo }
    assert_empty VentilatorsWalkthrough.state
    5.times { model.redo }
    assert VentilatorsWalkthrough.verify.fetch("passed")
    kind = "ph_composer.mechanical.ventilator"
    engine = PhComposer::Records::Engine.new(model, PhComposer::Registry.current.catalog)
    store = engine.kind(kind).store
    copy = engine.find(kind, engine.ids(kind).min)
    store.write(model, copy.merge("temperature_below_defrost_used_c" => -18.0))
    refute VentilatorsWalkthrough.verify.fetch("passed"), "a changed stored value fails the read-back"
    store.write(model, copy)
    store.write(model, copy.merge("id" => "vnt_ZZZZZZZZZZZZ"))
    refute VentilatorsWalkthrough.verify.fetch("passed"), "an extra record fails the read-back, even an equal one"
    store.write(model, copy.merge("rated_flow_m3h" => 120))
    assert_raises(RuntimeError) { VentilatorsWalkthrough.verify }
    text = File.read(File.expand_path("../tools/examples/authoring/ventilators_walkthrough.rb", __dir__))
    refute_match(/PhComposer::Mechanical|PhComposer::Zones/, text)
  end

  # Zone A at the root, Zone B in a turned Group, and a copy of Zone B made independent: the Serves steps reach
  # every occurrence, step back one Undo step at a time and forward again.
  def test_the_serves_steps_assign_replace_clear_and_move_in_nested_and_copied_zones
    model = Sketchup.active_model
    session = PhComposer::Sessions.for(model)
    @context = PhComposer::API.connect(:session_id => session.id)
    @sequence = 0
    # A quarter turn about the vertical, then 400 inches along x.
    turned = Geom::Transformation.new([0, 1, 0, 0, -1, 0, 0, 0, 0, 0, 1, 0, 400, 0, 0, 1])
    model.entities << zone(1000, "A", "Zone A") <<
      Sketchup::Group.new(8000, Sketchup::Entities.new([zone(2000, "B", "Zone B")]), :transformation => turned)
    adopt_zone_options
    original = model.entities.to_a.last.entities.to_a.first
    copy = Sketchup::Group.new(9000, original.entities, :name => "Zone B")
    Array(original.attribute_dictionaries).each do |dictionary|
      dictionary.each { |key, value| copy.set_attribute(dictionary.name, key, value) }
    end
    model.entities << copy
    treat_duplicates_as_existing(model)
    made = invoke("ph_composer.zones.make_independent", "zone_path" => [9000])
    assert_equal "completed", made.fetch("status"), made.inspect

    assert VentilatorsWalkthrough.run.fetch("passed")
    result = VentilatorsWalkthrough.serve
    assert result.fetch("passed"), result.inspect
    assert_equal [["Zone A", [1000]], ["Zone B", [8000, 2000]], ["Zone B", [9000]]],
                 VentilatorsWalkthrough.serve_state.fetch("zones").map { |row| row.first(2) }

    # Each Undo step back, newest first: the delete, Zone B's assign, its clear, Zone A's replace, Zone B's and
    # Zone A's first assigns.
    expected = [%w[ERV-2 ERV-1 ERV-1], ["ERV-2", nil, nil], %w[ERV-2 ERV-2 ERV-2], %w[ERV-1 ERV-2 ERV-2],
                ["ERV-1", nil, nil], [nil, nil, nil]]
    stepped = expected.map do
      model.undo
      items
    end
    assert_equal expected, stepped
    model.undo
    assert_equal ["ERV-1", "ERV-1 (copy)"], VentilatorsWalkthrough.serve_state.fetch("ventilators"),
                 "the seventh step back removes the recreated ERV-2"
    VentilatorsWalkthrough::SERVE_STEPS.times { model.redo }
    assert VentilatorsWalkthrough.serve_verify.fetch("passed")
  end

  private

  def items
    VentilatorsWalkthrough.serve_state.fetch("zones").map(&:last)
  end

  def zone(base, letter, name)
    space = space_group(base + 10, space_record(letter, :number => "1", :name => name),
                        [volume_group(base + 20, volume_record(letter),
                                      [floor_face(base + 30, rectangle(0, 0, 5, 4), segment_record(letter))])])
    group = Sketchup::Group.new(base, Sketchup::Entities.new([space]), :name => name)
    ZONES::ZONE_STORE.write(group, { "id" => "zon_#{letter * 12}", "schema_version" => 1, "name" => name,
                                     "building_segment" => "Reference", "level" => "L1", "ground_depth_mm" => 0.0 })
    host_children([space], "zon_#{letter * 12}")
    group
  end

  def invoke(name, params)
    PhComposer::API.invoke(:context => @context, :name => name, :params => params,
                           :request => { "sequence" => @sequence += 1,
                                         "expected_revision" => PhComposer::Sessions.find(@context.session_id)
                                                                                    .revision })
  end
end
