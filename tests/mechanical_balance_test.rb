# frozen_string_literal: true

require_relative "test_helper"
require_relative "support/space_fixtures"
require_relative "support/zone_options"

# The airflow balance by ventilator and the By ventilator Colour-by mode (context/CONTRACTS.md, "Mechanical
# equipment"). Zone A's Space gives 60 m³/h supply and 50 extract; Zone B, inside a Group moved 400 in, gives 40 and
# 40; both are in one Building Segment. ERV-1, ERV-2 and ERV-3 are Ventilators.
class MechanicalBalanceTest < PhComposerTestCase
  include SpaceFixtures
  include ZoneOptionsSupport

  API = PhComposer::API
  BALANCE = PhComposer::Mechanical::Serves::Balance
  BY_VENTILATOR = PhComposer::Mechanical::ColourModes::BY_VENTILATOR
  SERVES = "ph_composer.mechanical.serves"
  VENTILATORS = "ph_composer.mechanical.ventilators"

  def setup
    super
    @model = Sketchup.active_model
    @session = PhComposer::Sessions.for(@model)
    @context = API.connect(:session_id => @session.id)
    @sequence = 0
    wrapper = Sketchup::Group.new(8000, Sketchup::Entities.new([zone(2000, "B", "Zone B", 40.0, 40.0)]),
                                  :transformation => Geom::Transformation.translation([400, 0, 0]))
    @model.entities << zone(1000, "A", "Zone A", 60.0, 50.0) << wrapper
    adopt_zone_options
    @erv = %w[ERV-1 ERV-2 ERV-3].to_h do |name|
      [name, completed(invoke("#{VENTILATORS}.create", "values" => { "name" => name })).fetch("id")]
    end
  end

  # ---------------------------------------------------------------- the pure rule

  def test_more_than_a_tenth_of_the_larger_is_imbalanced_and_a_tenth_exactly_is_not
    assert_equal [60.0, 50.0, true], sums(BALANCE.call([detailed(60.0, 50.0)]))
    assert_equal [40.0, 40.0, false], sums(BALANCE.call([detailed(40.0, 40.0)]))
    assert_equal [100.0, 90.0, false], sums(BALANCE.call([detailed(60.0, 50.0), detailed(40.0, 40.0)]))
    assert_equal [0.0, 0.0, false], sums(BALANCE.call([detailed(0.0, 0.0)]))
  end

  def test_a_by_program_zone_counts_its_program_flow_as_both_and_none_known_makes_a_dash
    by_program = by_program(20.0)
    assert_equal [20.0, 20.0, false], sums(BALANCE.call([by_program]))
    assert_equal [60.0, 60.0, false], sums(BALANCE.call([by_program, detailed(40.0, 40.0)]))
    unknown = BALANCE.call([by_program(nil), detailed(40.0, 40.0)])
    assert_equal [nil, nil, false], sums(unknown)
    assert_match(/Zone Q is By Program/, unknown.fetch("missing"))
    assert_match(/serves no Zone/, BALANCE.call([]).fetch("missing"))
  end

  def test_a_zone_with_no_spaces_adds_nothing
    empty = BALANCE::Zone.new(:name => "Empty", :spaces => { "space_count" => 0, "airflow_mode" => "by_program" },
                              :programs => { "ventilation_m3h" => nil })
    assert_equal [40.0, 40.0, false], sums(BALANCE.call([empty, detailed(40.0, 40.0)]))
  end

  # ---------------------------------------------------------------- the read

  def test_the_ventilator_rows_carry_the_balance_over_the_zones_each_serves
    completed(assign(["Zone A"], "ERV-1"))
    completed(assign(["Zone B"], "ERV-2"))
    rows = ventilator_rows
    assert_equal [60.0, 50.0, true], sums(rows.fetch("ERV-1").fetch("balance"))
    assert_equal [40.0, 40.0, false], sums(rows.fetch("ERV-2").fetch("balance"))
    assert_equal [nil, nil, false], sums(rows.fetch("ERV-3").fetch("balance"))

    completed(assign(["Zone B"], "ERV-1", :replace => true))
    assert_equal [100.0, 90.0, false], sums(ventilator_rows.fetch("ERV-1").fetch("balance")), "the shared case"
    listed = completed(query("#{VENTILATORS}.list")).fetch("records").find { |row| row.fetch("id") == @erv["ERV-1"] }
    assert_equal [100.0, 90.0, false], sums(listed.fetch("balance")), "the bounded list answers the same"
  end

  def test_a_by_program_zone_reads_its_program_flow_from_programs
    completed(assign(["Zone A", "Zone B"], "ERV-1"))
    space = SPACES::SPACE_STORE.read(space_group_named("Zone A"))
    SPACES::SPACE_STORE.write(space_group_named("Zone A"), space.reject { |key, _value| key.start_with?("v_") })
    flow = completed(query("ph_composer.programs.zones")).fetch("zones")
                                                         .find { |row| row.fetch("name") == "Zone A" }
                                                         .fetch("ventilation_m3h")
    refute_nil flow
    assert_equal [flow + 40.0, flow + 40.0, false], sums(ventilator_rows.fetch("ERV-1").fetch("balance"))
  end

  # A served Zone in no Building Segment is left out of the export, and so of the balance.
  def test_the_balance_counts_the_zones_the_export_writes
    completed(assign(["Zone A", "Zone B"], "ERV-1"))
    assert_equal [100.0, 90.0, false], sums(ventilator_rows.fetch("ERV-1").fetch("balance"))
    row = completed(query("ph_composer.zones.all")).fetch("zones").find { |zone|
      zone.dig("values", "name") == "Zone B"
    }
    completed(invoke("ph_composer.zones.update_field", "field" => "building_segment", "value" => nil,
                                                       "targets" => [{ "reference" => row.fetch("reference"),
                                                                       "expected_values" => row.fetch("values") }]))
    assert_equal [60.0, 50.0, true], sums(ventilator_rows.fetch("ERV-1").fetch("balance"))
  end

  # ---------------------------------------------------------------- By ventilator

  def test_by_ventilator_colours_each_served_occurrence_by_its_item_and_leaves_an_unserved_zone_out
    completed(assign(["Zone A"], "ERV-1"))
    entries = project(BY_VENTILATOR)
    assert_equal [[[1000], @erv["ERV-1"], "ERV-1"]], entries.map { |entry| [entry.path, entry.value, entry.label] }
    zones = project(PhComposer::Zones::ColourModes::BY_ZONE).to_h { |entry| [entry.path, entry] }
    assert_equal zones.fetch([1000]).entity, entries.first.entity
    assert_equal zones.fetch([1000]).transform.to_a, entries.first.transform.to_a

    completed(assign(["Zone B"], "ERV-2"))
    copy_of("Zone A")
    entries = project(BY_VENTILATOR).sort_by(&:path)
    assert_equal [[1000], [8000, 2000], [9000]], entries.map(&:path), "one entry per occurrence"
    assert_in_delta 400, entries[1].transform.to_a[12], 1e-9, "the nested Zone's parent offset is composed"
    refute_equal entries[0].colour, entries[1].colour, "each item its own colour"
    service = PhComposer::ColourBy.for(@session).activate(BY_VENTILATOR)
    assert_equal({ "ERV-1" => 2, "ERV-2" => 1 }, service.rows.to_h { |row| [row.label, row.count] },
                 "the legend counts Zones, and an unserved Zone has no row")
  end

  # Zones' occurrence read leaves Faces out, so a Face record no read can validate does not turn the mode off.
  def test_by_ventilator_stands_beside_an_unreadable_face
    completed(assign(["Zone A"], "ERV-1"))
    face = Sketchup::Face.new(1900, {}, :points => [[0, 0, 0], [10, 0, 0], [10, 10, 0]].map do |x, y, z|
      Geom::Point3d.new(x, y, z)
    end)
    zone_group_named("Zone A").entities << face
    ZONES::Faces::FACE_STORE.write(face, { "id" => "fac_broken", "schema_version" => 99 })
    refute_equal "completed", query("ph_composer.zones.all").fetch("status"), "the whole Zone read refuses it"
    rows = completed(query("ph_composer.zones.occurrences")).fetch("zones")
    assert_equal [[1000], [8000, 2000]], rows.map { |row| row.dig("reference", "zone_path") }.sort
    assert_equal %w[extension_data id reference state values], rows.first.keys.sort, "no Face totals"
    assert_equal [[1000]], project(BY_VENTILATOR).map(&:path)
  end

  private

  def sums(balance)
    balance.values_at("supply_m3h", "extract_m3h", "imbalanced")
  end

  def detailed(supply, extract)
    BALANCE::Zone.new(:name => "Zone D", :spaces => { "space_count" => 1, "airflow_mode" => "detailed",
                                                      "airflows" => { "v_sup_m3h" => supply,
                                                                      "v_eta_m3h" => extract } },
                      :programs => { "ventilation_m3h" => supply })
  end

  def by_program(flow)
    BALANCE::Zone.new(:name => "Zone Q", :spaces => { "space_count" => 1, "airflow_mode" => "by_program",
                                                      "airflows" => { "v_sup_m3h" => nil, "v_eta_m3h" => nil } },
                      :programs => { "ventilation_m3h" => flow })
  end

  def zone(base, letter, name, supply, extract)
    airflows = { "v_sup_m3h" => supply, "v_eta_m3h" => extract }
    space = space_group(base + 10, space_record(letter, :number => "1", :name => name, :airflows => airflows),
                        [volume_group(base + 20, volume_record(letter),
                                      [floor_face(base + 30, rectangle(0, 0, 5, 4), segment_record(letter))])])
    group = Sketchup::Group.new(base, Sketchup::Entities.new([space]), :name => name)
    ZONES::ZONE_STORE.write(group, { "id" => "zon_#{letter * 12}", "schema_version" => 1, "name" => name,
                                     "building_segment" => "Apartments", "level" => "L1", "ground_depth_mm" => 0.0 })
    host_children([space], "zon_#{letter * 12}")
    group
  end

  # A Group copied with its attribute dictionaries, as a native copy leaves it before Zones makes it independent.
  def copy_of(name)
    original = zone_group_named(name)
    copy = Sketchup::Group.new(9000, original.entities, :name => name)
    Array(original.attribute_dictionaries).each do |dictionary|
      dictionary.each { |key, value| copy.set_attribute(dictionary.name, key, value) }
    end
    @model.entities << copy
    treat_duplicates_as_existing(@model)
    copy
  end

  def project(mode)
    declaration = PhComposer::Registry.current.colour_modes.fetch(mode)
    read = PhComposer::HandlerRequest.for(@session, :owner => declaration.owner, :name => declaration.name)
    Array(declaration.projection.call(read))
  end

  def assign(names, item, replace: nil)
    rows = completed(query("#{SERVES}.all")).fetch("zones")
    targets = names.map do |name|
      row = rows.find { |candidate| candidate.fetch("name") == name }
      { "reference" => row.fetch("reference"), "expected_values" => row.fetch("slots") }
    end
    params = { "zones" => targets, "slot" => "ventilator_id", "item_id" => @erv.fetch(item) }
    params["replace"] = replace unless replace.nil?
    invoke("#{SERVES}.assign", params)
  end

  def ventilator_rows
    completed(query("#{VENTILATORS}.all")).fetch("records").to_h { |row| [row.dig("values", "name"), row] }
  end

  def zone_group_named(name)
    groups = @model.entities.to_a.grep(Sketchup::Group)
    groups.find { |group| group.name == name } ||
      groups.flat_map { |group| group.entities.to_a.grep(Sketchup::Group) }.find { |group| group.name == name }
  end

  def space_group_named(zone_name)
    zone_group_named(zone_name).entities.to_a.grep(Sketchup::Group).first
  end

  def query(name, params = {})
    API.query(:context => @context, :name => name, :params => params)
  end

  def completed(outcome)
    assert_equal "completed", outcome.fetch("status"), outcome.inspect
    outcome.fetch("value")
  end

  def invoke(name, params)
    API.invoke(:context => @context, :name => name, :params => params,
               :request => { "sequence" => @sequence += 1, "expected_revision" => @session.revision })
  end
end
