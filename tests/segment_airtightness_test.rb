# frozen_string_literal: true

require_relative "test_helper"
require_relative "support/construction_export_fixtures"
require_relative "support/space_fixtures"
require_relative "support/zone_options"

# Building Segment airtightness, over a synthetic two-Segment model whose envelope tells PHX's area rules apart:
# Living and Kitchen in House share an interior Surface pair, the ADU's west wall is two Faces paired across the
# Segment boundary, every floor is on the Ground and the Kitchen's and ADU's north walls are Adiabatic. Each Zone
# holds one Space on its floor, Living's counting 90 % of its area as net.
# The settings are the programs feature's extension on each Segment record, saved through Zones' settings Save. At
# export the feature converts the test result into each Room's Infiltration, over the gross envelope area PHX's
# merged Room keeps and the Spaces' net volume. The golden feeds the PHX round trip
# (tests/python/test_airtightness_phx_round_trip.py).
class SegmentAirtightnessTest < PhComposerTestCase
  include ConstructionExportFixtures
  include FixtureFiles
  include SpaceFixtures
  include ZoneOptionsSupport

  API = PhComposer::API
  Z = PhComposer::Zones
  O = Z::Options
  P = PhComposer::Programs
  A = P::Airtightness
  NAMESPACE = A::NAMESPACE
  SECTION = P::AirtightnessExport::SECTION
  FIXTURE = File.join(TESTS_ROOT, "fixtures", "segments", "airtightness_extraction.json")
  CHOICES = File.join(TESTS_ROOT, "fixtures", "segments", "airtightness_choices.json")
  HOUSE = { "basis" => "n50", "value" => 2.0, "wind_exposure" => "one_side_moderate_screening" }.freeze
  ADU = { "basis" => "q50", "value" => 0.6, "wind_exposure" => "several_sides_high_screening" }.freeze
  # House keeps every Face but the interior pair: floor and roof 20 m² each, west 12, east 12 (to the ADU, across
  # the boundary), and Living's south or Kitchen's Adiabatic north 15, per Zone; the ADU keeps all six: 32, 32, two
  # west halves of 12, east 24, south 12 and the Adiabatic north 12. Outdoors and Ground only, House is 119 m².
  # House's Spaces hold 20 × 0.9 × 2.5 and 20 × 2.5 m³.
  HOUSE_GROSS_M2 = 158.0
  HOUSE_VOLUME_M3 = 95.0

  def setup
    super
    @model = Sketchup.active_model
    @session = PhComposer::Sessions.for(@model)
    @context = API.connect(:session_id => @session.id)
    @sequence = 0
    @assembly_id = seed_export_construction
  end

  # ---------------------------------------------------------------- the feature and the extension

  # The library joins Programs' own assign_library_program action to a library copy.
  def test_the_feature_requires_zones_spaces_certification_and_the_library_and_writes_the_choices
    feature = PhComposer::Registry.current.features.fetch(P::FEATURE_ID)
    assert_equal %w[ph_composer.certification ph_composer.library ph_composer.spaces ph_composer.zones],
                 feature.requires.sort
    write_or_compare(CHOICES, { "bases" => A::BASES, "wind_exposures" => A::WIND_EXPOSURES,
                                "defaults" => A::DEFAULTS })
  end

  def test_a_segment_reads_the_defaults_until_saved_then_its_values_in_one_undo_step
    reference
    house = segment_id("House")
    assert_equal({ "id" => house, "values" => A::DEFAULTS, "stored" => false, "extension_status" => nil },
                 query(P::READ, "id" => house))
    operations = @model.operations.length

    assert_equal [NAMESPACE], completed(save(house, HOUSE)).fetch("namespaces")

    assert_equal operations + 1, @model.operations.length
    assert_equal({ "id" => house, "values" => HOUSE, "stored" => true, "extension_status" => "understood" },
                 query(P::READ, "id" => house))
    completed(save(house, HOUSE.merge("value" => nil)))
    assert_nil query(P::READ, "id" => house).dig("values", "value"), "a blank result saves as no test result"
    @model.undo
    @model.undo
    assert_equal false, query(P::READ, "id" => house).fetch("stored")
  end

  def test_a_zero_negative_or_partial_payload_refuses_and_writes_nothing
    reference
    house = segment_id("House")
    revision = @session.revision
    [HOUSE.merge("value" => 0), HOUSE.merge("value" => -1.5), HOUSE.merge("value" => "2"),
     HOUSE.merge("basis" => "ach50"), HOUSE.merge("wind_exposure" => "sheltered"),
     HOUSE.reject { |field, _| field == "value" }, HOUSE.merge("note" => "x")].each do |payload|
      outcome = save(house, payload)
      assert_equal %w[refused validation.failed], outcome.values_at("status", "code"), payload.inspect
    end
    assert_equal revision, @session.revision
    assert_equal false, query(P::READ, "id" => house).fetch("stored")
  end

  def test_the_settings_go_with_a_deleted_segment
    reference
    spare = create_zone_option("building_segment", "Spare").then { segment_id("Spare") }
    completed(save(spare, HOUSE))

    removed = completed(invoke("#{O::PREFIX}.remove", "collection" => "building_segment", "id" => spare))
    assert_equal [{ "id" => spare, "namespaces" => [NAMESPACE] }], removed.fetch("removed_extensions")
    @model.undo
    assert_equal HOUSE, query(P::READ, "id" => spare).fetch("values"), "Undo restores them"
  end

  # ---------------------------------------------------------------- the conversion

  # PHX: C = flow × 1 / 4^0.65, q50 = C × 50^0.65 × 3600, n50 = q50 × gross envelope area / net volume.
  def phx_q50(flow)
    flow / (4.0**0.65) * (50.0**0.65) * 3600
  end

  def test_the_conversion_inverts_phxs_for_both_bases
    flow = P::Conversion.flow_per_exterior_area(P::Conversion.q50("q50", 0.6))
    assert_in_delta 0.6, phx_q50(flow), 1e-12
    assert_in_delta 0.6, P::Conversion.q50_from_flow(flow), 1e-12

    q50 = P::Conversion.q50("n50", 2.0, :envelope_area_m2 => HOUSE_GROSS_M2, :net_volume_m3 => HOUSE_VOLUME_M3)
    assert_in_delta 2.0 * HOUSE_VOLUME_M3 / HOUSE_GROSS_M2, q50, 1e-12
    n50 = phx_q50(P::Conversion.flow_per_exterior_area(q50)) * HOUSE_GROSS_M2 / HOUSE_VOLUME_M3
    assert_in_delta 2.0, n50, 1e-12
    assert_in_delta 2.0, P::Conversion.n50_from_q50(q50, :envelope_area_m2 => HOUSE_GROSS_M2,
                                                         :net_volume_m3 => HOUSE_VOLUME_M3), 1e-12
    assert_raises(ArgumentError) { P::Conversion.q50("ach50", 1.0) }
  end

  # ---------------------------------------------------------------- export

  def test_export_converts_each_segments_result_over_the_envelope_phx_keeps
    reference
    completed(save(segment_id("House"), HOUSE))
    completed(save(segment_id("ADU"), ADU))

    assert_empty preflight.select { |row| row.fetch("blocks_export") }
    records = extract.document.dig("sections", SECTION, "records")
    by_zone = records.to_h { |row| [zone_name(row.fetch("id")), row] }
    assert_equal %w[ADU Kitchen Living], by_zone.keys.sort

    house = P::Conversion.flow_per_exterior_area(2.0 * HOUSE_VOLUME_M3 / HOUSE_GROSS_M2)
    %w[Living Kitchen].each do |name|
      assert_in_delta house, by_zone.fetch(name).fetch("flow_per_exterior_area"), 1e-15, name
      assert_equal HOUSE, by_zone.fetch(name).slice(*A::FIELDS)
    end
    assert_in_delta P::Conversion.flow_per_exterior_area(0.6), by_zone.fetch("ADU").fetch("flow_per_exterior_area"),
                    1e-15
    assert_equal ADU.fetch("wind_exposure"), by_zone.fetch("ADU").fetch("wind_exposure")
    write_or_compare(FIXTURE, stable(extract.document))
  end

  # Occupancy payloads are local_only until the Program export claims them: a house's counts on its
  # Segment and a Zone's assignment leave the export unblocked.
  def test_occupancy_payloads_on_exported_zones_and_segments_never_block_export
    reference
    occupancy = P::Occupancy::SEGMENT_NAMESPACE
    switched_off = P::Occupancy::SEGMENT_DEFAULTS.merge("single_dwelling" => false)
    all = query("#{O::PREFIX}.all")
    row = all.fetch("building_segments").find { |candidate| candidate.dig("values", "name") == "ADU" }
    values = row.fetch("values").slice("name", "colour")
    completed(invoke(O::SegmentSettings::SAVE,
                     "id" => row.fetch("id"), "values" => values, "expected_values" => values,
                     "default" => all.fetch("default_segment_id") == row.fetch("id"),
                     "expected_default_segment_id" => all.fetch("default_segment_id"),
                     "extension_payloads" => { occupancy => switched_off },
                     "expected_extension_data" => row.fetch("extension_data", {})))
    completed(save(segment_id("House"), HOUSE))
    adu = zone_rows.find { |zone| zone.dig("values", "name") == "ADU" }
    assert_equal P::Occupancy::ZONE_NAMESPACE,
                 adu.fetch("extension_data").keys.find { |key| key == P::Occupancy::ZONE_NAMESPACE },
                 "switching the ADU off wrote its Zone's assignment"

    assert_empty preflight.select { |finding| finding.fetch("blocks_export") }
    records = extract.document.dig("sections", SECTION, "records")
    assert_equal %w[Kitchen Living], records.map { |record| zone_name(record.fetch("id")) }.sort,
                 "the export runs; the ADU has no airtightness settings"
  end

  def test_no_result_writes_the_wind_exposure_alone_and_no_settings_write_no_record
    reference
    completed(save(segment_id("House"), HOUSE.merge("value" => nil)))

    records = extract.document.dig("sections", SECTION, "records")
    assert_equal %w[Kitchen Living], records.map { |row| zone_name(row.fetch("id")) }.sort, "ADU has no settings"
    assert(records.all? { |row| row["flow_per_exterior_area"].nil? })
    assert(records.all? { |row| row.fetch("wind_exposure") == HOUSE.fetch("wind_exposure") })
  end

  def test_an_n50_result_with_no_net_volume_refuses_and_q50_does_not_need_one
    reference(:spaces => false)
    completed(save(segment_id("House"), HOUSE))
    error = assert_raises(PhComposer::Export::Blocked) { extract }
    assert_equal "airtightness.no_net_volume", error.code
    assert_match(/House/, error.message)

    completed(save(segment_id("House"), ADU))
    refute_empty extract.document.dig("sections", SECTION, "records")
  end

  def test_a_result_on_a_segment_with_no_outdoors_or_ground_face_refuses
    reference
    adu = Z::ZONE_STORE.read(zone_group("ADU"))
    zone_faces("ADU").each do |face|
      record = Z::Faces::FACE_STORE.read(face)
      next if record.fetch("boundary_condition") == "Surface"

      Z::Faces::FACE_STORE.write(face, record.merge("boundary_condition" => "Adiabatic"))
    end
    completed(save(adu.fetch("building_segment_id"), ADU))

    assert_equal "airtightness.no_exposed_face", assert_raises(PhComposer::Export::Blocked) { extract }.code
  end

  private

  # Living (x 0 to 5 m, y 0 to 4 m) and Kitchen (y 4 to 8 m) in House, ADU (x 5 to 9 m, y 0 to 8 m) in ADU, each
  # 3 m high with a ground floor, adjacencies solved and each interior pair's Assembly assigned from its first
  # side; the Kitchen's and ADU's north walls are Adiabatic. Each Zone holds one Space whose Floor Segment is the
  # Zone's floor Face, 2.5 m high, Living's at a net area factor of 0.9: 45, 50 and 80 m³. Segment names hold no
  # space, which PHX's merge refuses.
  def reference(spaces: true)
    @model.entities << box(1000, "L", "Living", "House", [0, 5, 0, 4], :space => spaces, :net_area_factor => 0.9) <<
      box(2000, "K", "Kitchen", "House", [0, 5, 4, 8], :adiabatic_north => true, :space => spaces) <<
      box(3000, "A", "ADU", "ADU", [5, 9, 0, 8], :split_west => true, :adiabatic_north => true, :space => spaces)
    adopt_zone_options
    completed(invoke("ph_composer.zones.solve_adjacency", "zones" => zone_rows.map { |row| row.fetch("reference") }))
    assign_pair_assemblies
  end

  def box(base, letter, name, segment, (x_min, x_max, y_min, y_max), space: true, split_west: false,
          adiabatic_north: false, net_area_factor: 1.0)
    children = box_faces(x_min, x_max, y_min, y_max, split_west).each_with_index.map do |(type, normal, loop), index|
      face = Sketchup::Face.new(base + index + 1, {}, :points => loop.map { |xyz| metres(xyz) },
                                                      :normal => Geom::Vector3d.new(*normal))
      boundary = if type == "Floor" then "Ground"
                 elsif adiabatic_north && normal == [0, 1, 0] then "Adiabatic"
                 else "Outdoors"
                 end
      Z::Faces::FACE_STORE.write(face, "id" => format("fac_%<letter>s%<number>011d", :letter => letter,
                                                                                     :number => index + 1),
                                       "schema_version" => 1, "face_type" => type, "boundary_condition" => boundary,
                                       "assembly_id" => @assembly_id, "user_data" => {}, "extension_data" => {})
      face
    end
    faces = children.dup
    if space
      # The Zone's floor Face is its Space's Floor Segment, as Create Space leaves it.
      floor = children.shift
      SPACES::FLOOR_SEGMENT_STORE.write(floor, segment_record(letter, :net_area_factor => net_area_factor))
      children << space_group(base + 50, space_record(letter, :number => "1", :name => name),
                              [volume_group(base + 60, volume_record(letter), [floor], :locked => false)])
    end
    group = Sketchup::Group.new(base, Sketchup::Entities.new(children), :name => name)
    zone = { "id" => "zon_#{letter * 12}", "schema_version" => 1, "name" => name, "building_segment" => segment,
             "level" => "L1", "ground_depth_mm" => 0.0, "user_data" => {}, "extension_data" => {} }
    Z::ZONE_STORE.write(group, zone)
    stamp = Z::Schema.stamp(zone)
    faces.each { |face| Z::STAMP_STORE.write(face, stamp) }
    host_children(children, zone.fetch("id"))
    group
  end

  # Floor, roof, then the walls west, east, south and north, outward normals; with `split_west` the west wall
  # is two Faces, split at y = 4 m.
  def box_faces(x0, x1, y0, y1, split_west)
    west = if split_west
             [[[x0, y0, 0], [x0, y0, 3], [x0, 4, 3], [x0, 4, 0]], [[x0, 4, 0], [x0, 4, 3], [x0, y1, 3], [x0, y1, 0]]]
           else
             [[[x0, y0, 0], [x0, y0, 3], [x0, y1, 3], [x0, y1, 0]]]
           end
    [["Floor", [0, 0, -1], [[x0, y0, 0], [x0, y1, 0], [x1, y1, 0], [x1, y0, 0]]],
     ["RoofCeiling", [0, 0, 1], [[x0, y0, 3], [x1, y0, 3], [x1, y1, 3], [x0, y1, 3]]]] +
      west.map { |loop| ["Wall", [-1, 0, 0], loop] } +
      [["Wall", [1, 0, 0], [[x1, y0, 0], [x1, y1, 0], [x1, y1, 3], [x1, y0, 3]]],
       ["Wall", [0, -1, 0], [[x0, y0, 0], [x1, y0, 0], [x1, y0, 3], [x0, y0, 3]]],
       ["Wall", [0, 1, 0], [[x0, y1, 0], [x0, y1, 3], [x1, y1, 3], [x1, y1, 0]]]]
  end

  def metres(xyz)
    Geom::Point3d.new(*xyz.map { |value| value * INCHES })
  end

  # Each Surface pair's Assembly from its first side by id, so the other side holds it reversed.
  def assign_pair_assemblies
    rows = query("ph_composer.zones.faces.all").fetch("faces")
    pairs = rows.select { |row| row.dig("values", "boundary_condition") == "Surface" }
    pairs.group_by { |row|
      [row.dig("reference", "entity_id"), row.dig("values", "adjacency", "counterpart", "entity_id")].sort
    }.each_value do |sides|
      side = sides.min_by { |row| row.dig("reference", "entity_id") }
      completed(invoke("ph_composer.zones.faces.assign_assembly",
                       "assembly_id" => @assembly_id,
                       "targets" => [{ "reference" => side.fetch("reference"),
                                       "expected_values" => side.fetch("values") }]))
    end
  end

  def zone_group(name)
    @model.entities.to_a.find { |entity| entity.is_a?(Sketchup::Group) && entity.name == name }
  end

  # Every classified Face in the Zone, its Space's floor among them.
  def zone_faces(name, entities = zone_group(name).entities.to_a)
    entities.flat_map do |entity|
      next zone_faces(name, entity.entities.to_a) if entity.is_a?(Sketchup::Group)

      entity.is_a?(Sketchup::Face) && Z::Faces::FACE_STORE.read(entity) ? [entity] : []
    end
  end

  # The document with the Building Segment ids adoption mints, which differ each run, renumbered by Segment name,
  # and the certification records, which follow those ids, in the renumbered order, so the golden compares.
  def stable(document)
    names = query("#{O::PREFIX}.all").fetch("building_segments").map do |row|
      [row.dig("values", "name"), row.fetch("id")]
    end
    fixed = names.sort.each_with_index.to_h do |(_name, id), index|
      [id, format("bsg_FIXED%<number>07d", :number => index + 1)]
    end
    stable = JSON.parse(JSON.generate(document).gsub(/\bbsg_[A-Za-z0-9]{12}\b/) { |id| fixed.fetch(id) })
    certification = PhComposer::Certification::SegmentExport::SECTION
    stable.dig("sections", certification, "records").sort_by! { |row| row.fetch("id") }
    stable
  end

  def save(id, payload)
    all = query("#{O::PREFIX}.all")
    row = all.fetch("building_segments").find { |candidate| candidate.fetch("id") == id }
    default_id = all.fetch("default_segment_id")
    values = row.fetch("values").slice("name", "colour")
    invoke(O::SegmentSettings::SAVE, "id" => id, "values" => values, "expected_values" => values,
                                     "default" => default_id == id, "expected_default_segment_id" => default_id,
                                     "extension_payloads" => { NAMESPACE => payload },
                                     "expected_extension_data" => row.fetch("extension_data", {}))
  end

  def zone_rows
    query("ph_composer.zones.all").fetch("zones")
  end

  def zone_name(zone_id)
    zone_rows.find { |row| row.dig("reference", "zone_id") == zone_id }.dig("values", "name")
  end

  def segment_id(name)
    query("#{O::PREFIX}.all").fetch("building_segments").find { |row| row.dig("values", "name") == name }.fetch("id")
  end

  def preflight
    completed(API.export_preflight(:context => @context)).fetch("findings")
  end

  def extract
    PhComposer::Export::Collection.build(@model, :run_id => "segment-airtightness")
  end

  def query(name, params = {})
    completed(API.query(:context => @context, :name => name, :params => params))
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
