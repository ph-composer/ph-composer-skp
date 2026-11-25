# frozen_string_literal: true

require_relative "test_helper"
require_relative "support/box_zone_fixtures"
require_relative "support/construction_export_fixtures"
require_relative "support/space_fixtures"
require_relative "support/zone_options"

# The piping export over ACCEPTANCE's reference model and its hot water piping case: Zones A and B, 3 m boxes in one
# Building Segment, each with its detailed Space, both served by HWS-1 with 8 tap points; Piping group PG-1 at the
# Model root, identity transform, linked to HWS-1, holding the case's riser (trunk, multiplier 12), three floor
# branches, six twigs and the two recirculation loop lines. The golden feeds the Python section and the PHX round trip
# (tests/python/test_piping_sections.py, test_piping_phx_round_trip.py).
class PipingExportTest < PhComposerTestCase
  include BoxZoneFixtures
  include ConstructionExportFixtures
  include FixtureFiles
  include SpaceFixtures
  include ZoneOptionsSupport

  API = PhComposer::API
  P = PhComposer::Piping
  X = P::ExportProjection
  STORE = P::Assignment::STORE
  SYSTEMS = "ph_composer.mechanical.hot_water_systems"
  SERVES = "ph_composer.mechanical.serves"
  FIXTURES = File.join(TESTS_ROOT, "fixtures", "piping")
  GOLDEN = File.join(FIXTURES, "extraction.json")
  # The result fields the contributor declares, for the Python section's test to hold its rows to.
  RESULT_FIELDS = File.join(FIXTURES, "result_fields.json")
  # Systems of recirculation runs with uneven lengths, each with the temperature and hours this Ruby works out, for the
  # Python test to hold equal to honeybee-ph's after a reload.
  VECTORS = File.join(FIXTURES, "recirculation_vectors.json")
  INCHES = 1 / 0.0254
  PT1 = "ppt_PT1000000001"
  PT2 = "ppt_PT2000000002"
  PG1 = "ppg_PG1000000001"
  TRUNK = { "multiplier" => 12, "demand_recirculation" => false }.freeze
  # Each pipe of the case by name: role, Pipe Type, points in metres and the role's values.
  CASE = {
    "riser" => ["trunk", PT1, [[1, 1, 0], [1, 1, 3], [1, 1, 6], [1, 1, 9]], TRUNK],
    "floor 1" => ["branch", PT2, [[1, 1, 3], [3, 1, 3], [5, 1, 3]], {}],
    "floor 2" => ["branch", PT2, [[1, 1, 6], [3, 1, 6], [5, 1, 6]], {}],
    "floor 3" => ["branch", PT2, [[1, 1, 9], [2.5, 1, 9], [4, 1, 9]], {}],
    "twig 1a" => ["twig", PT2, [[3, 1, 3], [3, 2, 3]], {}], "twig 1b" => ["twig", PT2, [[5, 1, 3], [5, 2.5, 3]], {}],
    "twig 2a" => ["twig", PT2, [[3, 1, 6], [3, 2, 6]], {}], "twig 2b" => ["twig", PT2, [[5, 1, 6], [5, 2.5, 6]], {}],
    "twig 3a" => ["twig", PT2, [[2.5, 1, 9], [2.5, 2, 9]], {}], "twig 3b" => ["twig", PT2, [[4, 1, 9], [4, 2, 9]], {}],
    "loop up" => ["recirculation", PT1, [[1.2, 1, 0], [1.2, 1, 9]], { "water_temp_c" => 55.0, "daily_period" => 18 }],
    "loop across" => ["recirculation", PT1, [[1.2, 1, 9], [1.2, 3, 9]],
                      { "water_temp_c" => 50.0, "daily_period" => 24 }]
  }.freeze

  CLAIMED = "test.piping_claims.tag"
  CLAIM_EXTENSION = PhComposer::Records::Extension.new(:namespace => CLAIMED, :schema_version => 1,
                                                       :export_relevance => "required", :validate => ->(_) { [] })

  def setup
    super
    @model = Sketchup.active_model
    @session = PhComposer::Sessions.for(@model)
    @context = API.connect(:session_id => @session.id)
    @sequence = 0
    @assembly_id = seed_export_construction
    @pipes = {}
    { PT1 => ["PT-1", 19.05, 12.7], PT2 => ["PT-2", 12.7, 0] }.each do |id, (name, diameter, thickness)|
      pipe_type(id, "name" => name, "diameter_mm" => diameter, "insulation_thickness_mm" => thickness)
    end
  end

  # ---------------------------------------------------------------- the records

  def test_the_case_exports_one_record_for_hws_1_with_the_schedules_tree_and_owns_the_golden
    reference
    extraction = extract
    assert_equal 1, piping(extraction).length
    record, = piping(extraction)
    runs = schedule_runs
    by_role = runs.group_by { |row| row.fetch("role") }
    assert_equal [hws, hws], record.values_at("id", "system_id")
    assert_equal 1, record.fetch("trunks").length
    trunk, = record.fetch("trunks")
    assert_equal [by_role.fetch("trunk").first.fetch("identifier"), "Trunk 1", 12, false],
                 trunk.values_at("identifier", "display_name", "multiplier", "demand_recirculation")
    assert_equal by_role.fetch("branch").map { |row| row.fetch("identifier") },
                 trunk.fetch("branches").map { |branch| branch.fetch("identifier") }
    assert_equal [2, 2, 2], trunk.fetch("branches").map { |branch| branch.fetch("twigs").length }
    assert_equal by_role.fetch("twig").map { |row| row.fetch("identifier") }.sort,
                 trunk.fetch("branches").flat_map { |branch| branch.fetch("twigs").map { |twig| twig["identifier"] } }
                      .sort
    assert_equal by_role.fetch("recirculation").map { |row| row.fetch("identifier") },
                 record.fetch("recirculation").map { |element| element.fetch("identifier") }
    assert_equal [3, 2, 1], [trunk, trunk.dig("branches", 0), trunk.dig("branches", 0, "twigs", 0)].map { |run|
      run.fetch("segments").length
    }

    assert_segment_values(record, trunk)

    assert_empty notes(extraction)
    assert_empty preflight_rows
    write_or_compare(GOLDEN, stable(extraction.document))
    write_or_compare(RESULT_FIELDS, X::RESULT_FIELDS)
  end

  # The case's segments carry their Pipe Type's values, distribution pipes 60 C and 24 h, the loop lines their own, and
  # the System the schedule's recirculation.
  def assert_segment_values(record, trunk)
    riser = trunk.fetch("segments").first
    assert_equal [6, 19.05, 12.7, 0.04, true, 1, 60.0, 24, {}],
                 riser.values_at("material", "diameter_mm", "insulation_thickness_mm", "insulation_conductivity",
                                 "insulation_reflective", "insulation_quality", "water_temp_c", "daily_period",
                                 "user_data")
    assert_equal riser.fetch("identifier"), riser.fetch("display_name"), "honeybee-ph's default, never a random one"
    assert_equal [[1.0, 1.0, 0.0], [1.0, 1.0, 3.0]], riser.fetch("points_m").map { |at| at.map { |v| v.round(6) } }
    assert_equal [12.7, 0], trunk.dig("branches", 0, "segments", 0).values_at("diameter_mm", "insulation_thickness_mm")
    assert_equal [[55.0, 18], [50.0, 24]], record.fetch("recirculation").map { |element|
      element.dig("segments", 0).values_at("water_temp_c", "daily_period")
    }
    assert_equal 19, record.fetch("recirculation_hours")
    assert_in_delta 54.09, record.fetch("recirculation_temperature_c"), 0.005
    assert_equal schedule.fetch("systems").first.values_at("recirculation_temperature_c", "recirculation_hours"),
                 record.values_at("recirculation_temperature_c", "recirculation_hours"), "the schedule's own values"
  end

  # Each blocking finding refuses the section, so no canonical pair is written, and the preflight lists it under the
  # same code and section, blocking, with the pipes it locates.
  BLOCKING = {
    "piping.type_missing" => ->(test) { test.rewrite("twig 1a", "pipe_type_id" => "ppt_DELETED00001") },
    "piping.group_unlinked" => ->(test) { test.relink(nil) },
    "piping.insulation_conductivity_missing" => lambda do |test|
      test.pipe_type(PT1, "name" => "PT-1", "diameter_mm" => 19.05, "insulation_thickness_mm" => 12.7,
                          "insulation_conductivity_w_mk" => nil)
    end,
    "piping.branch_unconnected" => lambda do |test|
      test.rewrite("riser", "role" => "recirculation", "multiplier" => nil, "demand_recirculation" => nil,
                            "water_temp_c" => 60.0, "daily_period" => 24)
    end,
    "piping.twig_unconnected" => lambda do |test|
      test.rewrite("floor 3", "role" => "recirculation", "water_temp_c" => 60.0, "daily_period" => 24)
    end,
    "piping.group_in_zone" => ->(test) { test.move_into_zone },
    "record.unreadable" => lambda do |test|
      edge = test.pipes_of("twig 2b").first
      edge.set_attribute(STORE.dictionary, STORE.key, "{\"id\":\"ppe_BROKEN000001\",\"schema_version\":1}")
    end
  }.freeze

  BLOCKING.each do |code, change|
    define_method("test_#{code.tr('.', '_')}_refuses_the_section_and_blocks_the_preflight") do
      reference
      change.call(self)
      error = assert_raises(PhComposer::Export::Blocked) { extract }
      assert_equal code, error.code
      rows = preflight_rows.select { |row| row.fetch("code") == code }
      refute_empty rows, "the preflight lists #{code}"
      assert(rows.all? { |row| row.fetch("blocks_export") && row.fetch("section") == X::SECTION })
      locates = rows.filter_map { |row| row.dig("locate", "params", "edge_paths") }
      refute_empty locates, "a #{code} row locates its pipes"
      objects = rows.map { |row| row.fetch("object_id") }
      if code == "record.unreadable"
        assert_equal [nil], objects.uniq, "an unreadable pipe is in no run"
      else
        assert_empty objects - schedule_runs.map { |row| row.fetch("identifier") }, "each row names its run"
      end
    end
  end

  # The warnings the export notes are the preflight's, code, object and message: a trunk changing multiplier is two
  # trunks, and Floor 2, touching both, takes the first with piping.parent_ambiguous; a lone trunk line has no branch.
  def test_the_exports_warnings_are_the_preflights_rows
    reference
    rewrite_edge(pipes_of("riser").last, "multiplier" => 6)
    lone = Sketchup::Edge.new(5900, Sketchup::Vertex.new(point([8, 8, 0])), Sketchup::Vertex.new(point([8, 8, 3])))
    STORE.write(lone, { "id" => "ppe_LONE00000001", "schema_version" => 1, "pipe_type_id" => PT1, "role" => "trunk",
                        "user_data" => {}, "extension_data" => {} }.merge(TRUNK))
    @group.entities << lone
    extraction = extract
    warnings = extraction.findings.select { |row| row.fetch("section") == X::SECTION }
                         .map { |row| row.values_at("code", "object_id", "message") }
    assert_equal %w[piping.parent_ambiguous piping.trunk_without_branches], warnings.map(&:first).sort
    assert_equal warnings.sort, preflight_rows.map { |row| row.values_at("code", "object_id", "message") }.sort
    refute(warnings.any? { |_code, _id, message| message.match?(/\A(\w+ \d+): \1 /) }, "each names its run once")
    assert_equal 3, piping(extraction).first.fetch("trunks").length
  end

  def test_a_system_whose_pipes_serve_no_exported_zone_is_noted_and_written_with_no_room
    reference
    two = completed(invoke("#{SYSTEMS}.create", "values" => { "name" => "HWS-2" })).fetch("id")
    relink(two)
    extraction = extract
    assert_equal [two], piping(extraction).map { |record| record.fetch("system_id") }
    assert_equal [["piping.system_unexported", two]], notes(extraction)
    assert_equal [["piping.system_unexported", two, false]],
                 preflight_rows.map { |row| row.values_at("code", "object_id", "blocks_export") }
    assert_equal({ "hot_water_system_ids" => [two] }, preflight_rows.first.dig("locate", "params"))
    assert_equal [hws, hws], hot_water(extraction).map { |row| row.fetch("item_id") }, "HWS-1's pairs carry no pipes"
  end

  # A bare Pipe Type needs no conductivity; its segments carry honeybee-ph's default, 0.04 W/(m K), never a null.
  def test_a_bare_pipe_type_with_no_conductivity_exports_honeybee_phs_default
    reference
    pipe_type(PT2, "name" => "PT-2", "diameter_mm" => 12.7, "insulation_thickness_mm" => 0,
                   "insulation_conductivity_w_mk" => nil)
    branch = piping(extract).first.fetch("trunks").first.fetch("branches").first
    assert_equal [0.04], (branch.fetch("segments") + branch.fetch("twigs").flat_map { |twig| twig["segments"] })
      .map { |segment| segment.fetch("insulation_conductivity") }.uniq
  end

  # A pipe's user_data rides on its segment; a Piping group's and a Pipe Type's are left out with a note; a reserved key
  # on a pipe refuses the section, in the export and the preflight alike.
  def test_a_pipes_user_data_rides_its_segment_and_a_groups_and_a_types_are_left_out
    reference
    rewrite("twig 1a", "user_data" => { "maker_ref" => "PX-1" })
    group = P::Group::STORE.read(@group)
    P::Group::STORE.write(@group, group.merge("user_data" => { "riser_tag" => "R-1" }))
    pipe_type(PT2, { "name" => "PT-2", "diameter_mm" => 12.7, "insulation_thickness_mm" => 0 }, { "sku" => "PEX-12" })
    extraction = extract
    twigs = piping(extraction).first.fetch("trunks").first.fetch("branches").flat_map { |branch| branch["twigs"] }
    data = twigs.flat_map { |twig| twig.fetch("segments") }.map { |segment| segment.fetch("user_data") }
    assert_equal [{ "maker_ref" => "PX-1" }], data.reject(&:empty?)
    omitted = extraction.findings.select { |row| row.fetch("code") == "export.metadata_omitted" }
    assert_equal [[X::SECTION, PG1], [X::SECTION, PT2]].sort,
                 omitted.map { |row| row.values_at("section", "object_id") }.sort

    rewrite("twig 1a", "user_data" => { "ph_composer" => { "x" => 1 } })
    assert_equal "export.blocked", assert_raises(PhComposer::Export::Blocked) { extract }.code
    assert_includes preflight_rows.map { |row| row.values_at("code", "blocks_export") }, ["export.blocked", true]
  end

  # A pasted Piping group shares its storage: each placement's runs export under their own identifiers, noted as shared,
  # and the preflight, reading the live Group's definition, notes the same runs.
  def test_a_pasted_piping_group_exports_both_placements_under_distinct_identifiers_noted_as_shared
    reference
    copy = Sketchup::Group.new(501, @group.entities,
                               :transformation => Geom::Transformation.translation([20 * INCHES, 0, 0]))
    P::Group::STORE.write(copy, P::Group::STORE.read(@group))
    @model.entities << copy
    extraction = extract
    trunks = piping(extraction).first.fetch("trunks")
    assert_equal 2, trunks.map { |trunk| trunk.fetch("identifier") }.uniq.length
    shared = notes(extraction).select { |code, _id| code == "piping.shared_definition" }
    refute_empty shared
    assert_equal shared.sort, preflight_rows.map { |row| row.values_at("code", "object_id") }
                                            .select { |code, _id| code == "piping.shared_definition" }.sort
  end

  # Recirculation systems of uneven runs: what this Ruby reads for each, for the Python test to hold equal to
  # honeybee-ph's recirc_temp and recirc_hours on the pinned wheel, before and after a reload. The last repeats the
  # twenty-first with every pipe at 100 C, whose mean comes out a float's width above 100.
  def test_recirculation_vectors_are_what_the_ruby_read_gives
    random = Random.new(20_261_124)
    types = { PT1 => P::PipeType::DEFAULTS.merge("id" => PT1, "name" => "PT-1") }
    facts = Array.new(24) { |index| vector_facts(random, "hws_VECTOR#{format('%06d', index)}") }
    hot = facts[20].map { |fact| fact.dup.tap { |copy| copy.values = copy.values.merge("water_temp_c" => 100.0) } }
    cases = (facts + [hot]).map do |pipes|
      system = pipes.first.group.fetch("hot_water_system_id")
      P::Runs::Extraction.records(P::Runs::Tree.call(pipes), :types => types,
                                                             :systems => { system => { "name" => "V" } }).first
    end
    assert_operator cases.last.fetch("recirculation_temperature_c"), :>, 100.0
    write_or_compare(VECTORS, { "cases" => cases })
  end

  def vector_facts(random, system)
    Array.new(random.rand(2..4)) do |run|
      group = { "group_id" => PG1, "group_path" => [900, run], "name" => "", "hot_water_system_id" => system,
                "in_zone" => false }
      values = { "water_temp_c" => [50.0, 55.0, 60.0].sample(:random => random),
                 "daily_period" => [18, 23.5, 24].sample(:random => random) }
      points = Array.new(random.rand(2..4)) { Array.new(3) { random.rand(1..997) / 113.0 } }
      points.each_cons(2).each_with_index.map do |(from, to), place|
        P::Runs::Fact.new(:path => [900, run, place], :group => group, :record_id => "ppe_#{system}_#{run}",
                          :pipe_type_id => PT1, :role => "recirculation", :values => values,
                          :points_m => [from, to], :vertex_ids => [place, place + 1], :shared => false)
      end
    end.flatten
  end

  # Another feature claiming extension data on pipes and Piping groups receives each occurrence's payload: this
  # section is the source of those claims.
  def test_a_claim_on_pipes_and_piping_groups_receives_each_occurrences_payload
    PhComposer::Registry.install([claim_feature])
    reference
    rewrite("twig 1a", "extension_data" => { CLAIMED => CLAIM_EXTENSION.envelope("tag" => "T-1") })
    P::Group::STORE.write(@group, P::Group::STORE.read(@group).merge(
      "extension_data" => { CLAIMED => CLAIM_EXTENSION.envelope("tag" => "G-1") }
    ))
    extraction = PhComposer::Export::Collection.build(@model, :run_id => "claims")
    rows = extraction.document.dig("sections", "test.piping_claims.export", "records")
    assert_equal [[[500], "G-1"], [[500, pipes_of("twig 1a").first.persistent_id], "T-1"]],
                 rows.map { |row| [row.fetch("path"), row.dig("payload", "tag")] }.sort_by(&:first)
  end

  def test_the_privacy_allowlist_admits_only_the_declared_rows
    rows = X::RESULT_FIELDS.transform_values { |keys| [keys.to_h { |key| [key, key == "twig_counts" ? [1] : "x"] }] }
    result = { "schema_version" => 1, "run_id" => "r", "state" => "complete",
               "summary" => { "objects" => 1, "unavailable" => 0, "findings" => 0, "publishable" => true },
               "sections" => [], "findings" => [], X::SECTION => rows }
    assert PhComposer::Export::Privacy.validate!(result)
    error = assert_raises(PhComposer::CodedError) do
      PhComposer::Export::Privacy.validate!(result.merge(X::SECTION => rows.merge("trunks" => [{ "points" => 1 }])))
    end
    assert_equal "export.privacy_undeclared", error.code
  end

  # ---------------------------------------------------------------- what the cases change

  # A feature claiming CLAIMED on pipes and Piping groups, whose section lists each claimed row it receives.
  def claim_feature
    Module.new do
      define_singleton_method(:install) do |registry|
        scope = registry.feature("test.piping_claims", :contract_version => 1, :requires => ["ph_composer.piping"])
        scope.extension(CLAIM_EXTENSION)
        claims = [P::PIPE_KIND, P::GROUP_KIND].map do |kind|
          { "namespace" => CLAIMED, "target_kind" => kind, "source_section" => X::SECTION, "fields" => ["tag"] }
        end
        scope.export_contributor("test.piping_claims.export", :section_version => 1, :requires => [X::SECTION],
                                                              :entity_projections => claims) do |reader|
          [P::PIPE_KIND, P::GROUP_KIND].flat_map { |kind| reader.entity_projection(CLAIMED, kind) }
                                       .map { |row| row.merge("id" => row.fetch("path").join("_")) }
        end
      end
    end
  end

  def pipe_type(id, values, user_data = {})
    P::PipeType::KIND.store.write(@model, P::PipeType::DEFAULTS.merge(
      "id" => id, "schema_version" => 1, "notes" => "", "datasheet_links" => [], "source" => { "kind" => "manual" },
      "material" => 6, "user_data" => user_data, "extension_data" => {}
    ).merge(values).compact)
  end

  # Rewrites every pipe of `name`, dropping each value set to nil.
  def rewrite(name, values)
    pipes_of(name).each { |edge| rewrite_edge(edge, values) }
  end

  def rewrite_edge(edge, values)
    STORE.write(edge, STORE.read(edge).merge(values).compact)
  end

  def relink(system_id)
    P::Group::STORE.write(@group, P::Group::STORE.read(@group).merge("hot_water_system_id" => system_id))
  end

  def move_into_zone
    box_group("Zone A").entities << @group
  end

  def pipes_of(name)
    @pipes.fetch(name)
  end

  private

  def reference
    @model.entities << box(1000, "A", "Zone A", "Main", [0, 5, 0, 4]) << box(2000, "B", "Zone B", "Main", [6, 10, 0, 4])
    adopt_zone_options
    @hws = completed(invoke("#{SYSTEMS}.create", "values" => { "name" => "HWS-1", "number_tap_points" => 8 }))
           .fetch("id")
    completed(invoke("#{SERVES}.assign", "zones" => %w[A B].map { |letter| target(letter) },
                                         "slot" => "hot_water_system_id", "item_id" => @hws))
    vertices = {}
    next_id = 5000
    edges = CASE.flat_map do |name, (role, type, points, values)|
      @pipes[name] = points.each_cons(2).map do |from, to|
        ends = [from, to].map { |at| vertices[at] ||= Sketchup::Vertex.new(point(at)) }
        edge = Sketchup::Edge.new(next_id += 1, *ends)
        STORE.write(edge, { "id" => "ppe_#{format('%012d', edge.persistent_id)}", "schema_version" => 1,
                            "pipe_type_id" => type, "role" => role, "user_data" => {},
                            "extension_data" => {} }.merge(values))
        edge
      end
    end
    @group = Sketchup::Group.new(500, Sketchup::Entities.new(edges), :name => "PG-1")
    P::Group::STORE.write(@group, P::Group.new_record(PG1, @hws))
    @model.entities << @group
  end

  def hws
    @hws
  end

  def point(at)
    Geom::Point3d.new(*at.map { |value| value * INCHES })
  end

  def target(letter)
    row = query("#{SERVES}.all").fetch("zones").find { |zone| zone.fetch("zone_id") == "zon_#{letter * 12}" }
    { "reference" => row.fetch("reference"), "expected_values" => row.fetch("slots") }
  end

  def extract
    PhComposer::Export::Collection.build(@model, :run_id => "piping-export")
  end

  def piping(extraction)
    extraction.document.dig("sections", X::SECTION, "records")
  end

  def hot_water(extraction)
    extraction.document.dig("sections", PhComposer::Mechanical::HotWaterExport::SECTION, "records")
  end

  # This section's notes, as `[code, object_id]`.
  def notes(extraction)
    extraction.findings.select { |row| row.fetch("section") == X::SECTION && row.fetch("code").start_with?("piping.") }
              .map { |row| row.values_at("code", "object_id") }
  end

  def preflight_rows
    completed(API.query(:context => @context, :name => X::PREFLIGHT, :params => {})).fetch("findings")
  end

  def schedule
    query("ph_composer.piping.schedule")
  end

  def schedule_runs
    schedule.fetch("runs")
  end

  # The document with the ids each run mints renumbered by name: Building Segments and the Hot Water System.
  def stable(document)
    segments = query("ph_composer.zones.options.all").fetch("building_segments").map { |row| row.fetch("id") }
    fixed = (segments + [@hws]).each_with_index.to_h do |id, index|
      [id, format("#{id[0, 3]}_FIXED%<number>07d", :number => index + 1)]
    end
    pattern = /(?<![A-Za-z0-9])(?:bsg|hws)_[A-Za-z0-9]{12}(?![A-Za-z0-9])/
    stable = JSON.parse(JSON.generate(document).gsub(pattern) { |id| fixed.fetch(id, id) })
    stable.fetch("sections").each_value { |section| section.fetch("records").sort_by! { |row| row.fetch("id").to_s } }
    stable
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
