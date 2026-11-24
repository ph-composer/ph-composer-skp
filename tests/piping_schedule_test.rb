# frozen_string_literal: true

require_relative "test_helper"

# The live piping schedule over a stub Model: one walk for Piping groups and their pipes, Zones' containment for the
# group paths, the Systems read, the used length on Pipe Types, and runs.locate. The arithmetic is the pure runs
# suite's; this proves what the scan hands it.
class PipingScheduleTest < PhComposerTestCase
  API = PhComposer::API
  P = PhComposer::Piping
  STORE = P::Assignment::STORE
  PREFIX = "ph_composer.piping"
  INCHES = 1 / 0.0254

  def setup
    super
    @model = Sketchup.active_model
    @session = PhComposer::Sessions.for(@model)
    @context = API.connect(:session_id => @session.id)
    @sequence = 0
    @next_id = 1000
    @hws = invoke("ph_composer.mechanical.hot_water_systems.create", "values" => { "name" => "HWS-1" })
           .dig("value", "id")
    @pt1 = invoke("#{PREFIX}.pipe_types.create", "values" => { "name" => "PT-1", "material" => 6,
                                                               "diameter_mm" => 19.05 }).dig("value", "id")
    @pt2 = invoke("#{PREFIX}.pipe_types.create", "values" => { "name" => "PT-2", "material" => 6,
                                                               "insulation_thickness_mm" => 0 }).dig("value", "id")
  end

  # The hot water piping case's riser, floor-one branch and its two twigs and the recirculation loop, in Piping group
  # PG-1 (500) inside wrapper 20 moved 2 m along x, with one unassigned line beside them.
  def the_case
    trunk = { "multiplier" => 12, "demand_recirculation" => false }
    @vertices = {}
    pipes = line(%w[trunk], @pt1, [[1, 1, 0], [1, 1, 3], [1, 1, 6], [1, 1, 9]], trunk) +
            line(%w[branch], @pt2, [[1, 1, 3], [3, 1, 3], [5, 1, 3]]) +
            line(%w[twig], @pt2, [[3, 1, 3], [3, 2, 3]]) + line(%w[twig], @pt2, [[5, 1, 3], [5, 2.5, 3]]) +
            line(%w[recirculation], @pt1, [[1.2, 1, 0], [1.2, 1, 9]], "water_temp_c" => 55.0, "daily_period" => 18) +
            line(%w[recirculation], @pt1, [[1.2, 1, 9], [1.2, 3, 9]], "water_temp_c" => 50.0, "daily_period" => 24)
    @group = piping_group(500, "ppg_PG1000000001", pipes + [Sketchup::Edge.new(next_id, point([0, 0, 0]),
                                                                               point([0, 0, 1]))])
    @wrapper = Sketchup::Group.new(20, Sketchup::Entities.new([@group]),
                                   :transformation => Geom::Transformation.translation([2 * INCHES, 0, 0]))
    @model.entities << @wrapper
    pipes
  end

  def line((role), type_id, points, values = {})
    vertices = points.map { |at| @vertices[at] ||= Sketchup::Vertex.new(point(at)) }
    vertices.each_cons(2).map do |from, to|
      edge = Sketchup::Edge.new(next_id, from, to)
      STORE.write(edge, { "id" => "ppe_#{format('%012d', edge.persistent_id)}", "schema_version" => 1,
                          "pipe_type_id" => type_id, "role" => role, "user_data" => {},
                          "extension_data" => {} }.merge(values))
      edge
    end
  end

  def point(at)
    Geom::Point3d.new(*at.map { |value| value * INCHES })
  end

  def piping_group(persistent_id, id, children)
    group = Sketchup::Group.new(persistent_id, Sketchup::Entities.new(children))
    P::Group::STORE.write(group, P::Group.new_record(id, @hws))
    group
  end

  def next_id
    @next_id += 1
  end

  def test_the_schedule_reads_the_case_in_world_metres_with_parents_systems_and_used_lengths
    the_case
    result = query("schedule")
    rows = result.fetch("runs")
    assert_equal %w[trunk branch twig twig recirculation recirculation], rows.map { |row| row.fetch("role") }
    trunk, branch = rows
    assert_equal [9.0, 3, "Trunk 1", "HWS-1"],
                 [trunk.fetch("length_m").round(3), *trunk.values_at("line_count", "display_name",
                                                                     "hot_water_system_name")]
    assert_equal({ "group_id" => "ppg_PG1000000001", "group_path" => [20, 500], "name" => "" }, trunk.fetch("group"))
    assert_equal trunk.fetch("identifier"), branch.fetch("parent")
    assert_equal [branch.fetch("identifier")] * 2, rows[2, 2].map { |row| row.fetch("parent") }
    assert(rows.all? { |row| row.fetch("edge_paths").all? { |path| path[0, 2] == [20, 500] } })
    assert_empty rows.flat_map { |row| row.fetch("findings") }
    assert_equal [6, 0, [], nil], result.values_at("total", "unreadable_total", "unreadable", "next_cursor")

    system = result.fetch("systems").first
    assert_equal [11.0, 19], [system.fetch("recirculation_length_m").round(3), system.fetch("recirculation_hours")]
    assert_in_delta 54.09, system.fetch("recirculation_temperature_c"), 0.005
    assert_equal result.fetch("systems"), query("systems").fetch("systems")
    assert_equal({ @pt1 => 20.0, @pt2 => 6.5 },
                 query("pipe_types.all").fetch("records").to_h { |row|
                   [row.fetch("id"), row.fetch("used_length_m").round(3)]
                 })

    locate = API.view(:context => @context, :name => "#{PREFIX}.runs.locate",
                      :params => { "edge_paths" => trunk.fetch("edge_paths") })
    assert_equal ["completed", [20, 500], 3], [locate["status"], *locate["value"].values_at("path", "selected")]
  end

  def test_the_scan_writes_nothing_opens_no_operation_and_reports_unreadable_records_as_rows
    pipes = the_case
    pipes[3].set_attribute(STORE.dictionary, STORE.key, "{not json")
    roleless = STORE.read(pipes[4]).reject { |key, _value| key == "role" }
    STORE.write(pipes[4], roleless)
    broken = piping_group(510, "ppg_BROKEN000001", line(%w[branch], @pt2, [[9, 9, 9], [9, 9, 10]]))
    broken.set_attribute(P::Group::STORE.dictionary, P::Group::STORE.key, "[]")
    @model.entities << broken
    revision = @session.revision
    starts = @model.operation_starts.length

    result = query("schedule")
    assert_equal [[20, 500, pipes[3].persistent_id], [20, 500, pipes[4].persistent_id], [510]],
                 result.fetch("unreadable").map { |row| row.fetch("path") }
    assert_equal ["record.unreadable"], result.fetch("unreadable").map { |row| row.fetch("code") }.uniq
    assert_equal 3, result.fetch("unreadable_total")
    assert_equal [revision, starts], [@session.revision, @model.operation_starts.length]
  end

  def test_a_group_a_zone_holds_and_a_pasted_copy_raise_their_findings
    the_case
    copy = Sketchup::Group.new(501, @group.entities)
    P::Group::STORE.write(copy, P::Group::STORE.read(@group))
    @wrapper.entities << copy
    rows = query("schedule").fetch("runs")
    assert_equal 12, rows.length
    assert_equal 6, rows.map { |row| row.fetch("identifier") }.uniq.length / 2
    assert(rows.all? { |row|
      row.fetch("findings").map { |finding|
        finding.fetch("code")
      } == ["piping.shared_definition"]
    })

    loop = line(%w[recirculation], @pt1, [[7, 7, 7], [8, 7, 7]], "water_temp_c" => 60.0, "daily_period" => 24)
    zone = Sketchup::Group.new(100, Sketchup::Entities.new([piping_group(520, "ppg_INZONE000001", loop)]))
    PhComposer::Zones::ZONE_STORE.write(zone, "id" => "zon_AAAAAAAAAAAA", "schema_version" => 1, "name" => "Zone A",
                                              "building_segment" => "Building", "level" => nil,
                                              "ground_depth_mm" => 0.0, "user_data" => {}, "extension_data" => {})
    @model.entities << zone
    held = query("schedule").fetch("runs").select { |row| row.dig("group", "group_path") == [100, 520] }
    assert_equal [["piping.group_in_zone"]], held.map { |row|
      row.fetch("findings").map { |finding|
        finding.fetch("code")
      }
    }
  end

  def test_locate_refuses_hidden_and_mixed_paths_and_moves_nothing
    the_case
    trunk = query("schedule").fetch("runs").first
    @wrapper.hidden = true
    hidden = API.view(:context => @context, :name => "#{PREFIX}.runs.locate",
                      :params => { "edge_paths" => trunk.fetch("edge_paths") })
    assert_equal %w[refused piping.hidden], hidden.values_at("status", "code")
    assert_equal [[], []], [Array(@model.active_path), @model.selection.to_a]
    @wrapper.hidden = false
    mixed = API.view(:context => @context, :name => "#{PREFIX}.runs.locate",
                     :params => { "edge_paths" => [trunk.dig("edge_paths", 0), [20, 999, 1]] })
    assert_equal %w[refused params.invalid], mixed.values_at("status", "code")
    loose = @group.entities.to_a.find { |entity| entity.is_a?(Sketchup::Edge) && !STORE.marks?(entity) }
    plain = Sketchup::Group.new(40,
                                Sketchup::Entities.new([Sketchup::Edge.new(41, point([0, 0, 0]), point([1, 0, 0]))]))
    @model.entities << plain
    [[20, 500, loose.persistent_id], [40, 41], [20, 500]].each do |path|
      wrong = API.view(:context => @context, :name => "#{PREFIX}.runs.locate", :params => { "edge_paths" => [path] })
      assert_equal %w[refused target.wrong_kind], wrong.values_at("status", "code"), path.inspect
    end
    assert_equal [[], []], [Array(@model.active_path), @model.selection.to_a]
  end

  def test_every_malformed_record_is_an_unreadable_row_and_never_refuses_the_read
    pipes = the_case
    good = STORE.read(pipes[0])
    bad = { "an array" => [], "a number" => 5, "null" => nil, "schema version 2" => good.merge("schema_version" => 2),
            "a number type id" => good.merge("pipe_type_id" => 7),
            "a text multiplier" => good.merge("multiplier" => "12"),
            "a temperature past 100 C" => STORE.read(pipes[7]).merge("water_temp_c" => 1e308) }
    edges = pipes.values_at(0, 1, 2, 3, 4, 5, 7)
    bad.values.zip(edges).each do |record, edge|
      edge.set_attribute(STORE.dictionary, STORE.key, JSON.generate(record))
    end
    broken = { "a text System id" => 5, "a number record" => nil }.keys.each_with_index.map do |_label, index|
      group = piping_group(530 + index, "ppg_BROKEN00000#{index}",
                           line(%w[twig], @pt2, [[9, 9, 9 + index], [9, 9, 10]]))
      stored = index.zero? ? P::Group::STORE.read(group).merge("hot_water_system_id" => 5) : 5
      group.set_attribute(P::Group::STORE.dictionary, P::Group::STORE.key, JSON.generate(stored))
      @model.entities << group
      group
    end

    result = query("schedule")
    expected = edges.map { |edge| [20, 500, edge.persistent_id] } + broken.map { |group| [group.persistent_id] }
    assert_equal expected.sort, result.fetch("unreadable").map { |row| row.fetch("path") }
    assert_equal [2.0, ["record.unreadable"]],
                 [result.dig("systems", 0, "recirculation_length_m"),
                  result.fetch("unreadable").map { |row| row.fetch("code") }.uniq]
    assert_equal "completed", API.query(:context => @context, :name => "#{PREFIX}.systems", :params => {})["status"]
  end

  def test_a_compact_page_counts_paths_and_members_pages_a_runs_pipes
    the_case
    compact = query("schedule", "compact" => true)
    trunk = compact.fetch("runs").first
    assert_equal [false, 3, 0], [trunk.key?("edge_paths"), trunk.fetch("edge_count"), trunk.fetch("index")]
    whole = query("schedule").fetch("runs").first.fetch("edge_paths")
    first = query("runs.members", "identifier" => trunk.fetch("identifier"), "limit" => 2)
    rest = query("runs.members", "identifier" => trunk.fetch("identifier"), "cursor" => first.fetch("next_cursor"))
    assert_equal whole, (first.fetch("members") + rest.fetch("members")).map { |row| row.fetch("path") }
    assert_equal [0, 1, 2], (first.fetch("members") + rest.fetch("members")).map { |row| row.fetch("index") }
    gone = API.query(:context => @context, :name => "#{PREFIX}.runs.members",
                     :params => { "identifier" => "pipe_gone" })
    assert_equal %w[refused target.not_found], gone.values_at("status", "code")

    # A long group name is cut in the row and named in truncated.
    @group.name = "G" * 400
    named = query("schedule").fetch("runs").first
    assert_equal [256, ["group.name"]], [named.dig("group", "name").length, named.fetch("truncated")]
  end

  # Every compact page and every details page fits one agent reply, whatever the names and however many unreadable
  # records there are.
  def test_compact_and_details_pages_fit_one_reply_with_long_names_and_many_unreadable_records
    the_case
    invoke("#{PREFIX}.pipe_types.update", "id" => @pt1, "values" => { "name" => "T" * 30_000 },
                                          "expected_values" => {})
    @group.name = "G" * 30_000
    stray = (0...60).map { |index| Sketchup::Edge.new(next_id, point([20, index, 0]), point([21, index, 0])) }
    stray.each { |edge| edge.set_attribute(STORE.dictionary, STORE.key, "{#{'x' * 2_000}") }
    @model.entities << piping_group(560, "ppg_STRAYSTRAY01", stray)
    budget = PhComposer::Pages::REPLY_BYTES
    compact = query("schedule", "compact" => true, "limit" => 1)
    assert_operator JSON.generate(compact).bytesize, :<, budget
    assert_equal [1, 2, 60],
                 [compact.fetch("system_count"), compact.fetch("type_count"), compact.fetch("unreadable_total")]
    refute(%w[systems types unreadable].any? { |key| compact.key?(key) })
    %w[systems types unreadable].each do |part|
      page = query("schedule.details", "part" => part)
      assert_operator JSON.generate(page).bytesize, :<, budget, part
    end
    types = query("schedule.details", "part" => "types").fetch("types")
    assert_equal [256, ["name"]], types.find { |row| row.fetch("pipe_type_id") == @pt1 }.values_at("name", "truncated")
                                       .then { |name, cut| [name.length, cut] }
    read = []
    cursor = nil
    loop do
      page = query("schedule.details",
                   { "part" => "unreadable", "limit" => 500 }.merge(cursor ? { "cursor" => cursor } : {}))
      read.concat(page.fetch("unreadable"))
      break unless (cursor = page["next_cursor"])
    end
    assert_equal 60, read.map { |row| row.fetch("path") }.uniq.length
  end

  def test_pipe_types_list_gives_used_length
    the_case
    rows = query("pipe_types.list").fetch("records")
    assert_equal({ @pt1 => 20.0, @pt2 => 6.5 }, rows.to_h { |row|
      [row.fetch("id"), row.fetch("used_length_m").round(3)]
    })
  end

  def test_a_page_of_runs_carries_the_totals_and_a_cursor
    the_case
    first = query("schedule", "limit" => 2)
    assert_equal [2, 6], [first.fetch("runs").length, first.fetch("total")]
    rest = query("schedule", "cursor" => first.fetch("next_cursor"))
    assert_equal query("schedule").fetch("runs"), first.fetch("runs") + rest.fetch("runs")
    assert_equal first.fetch("totals"), rest.fetch("totals")
  end

  def query(name, params = {})
    result = API.query(:context => @context, :name => "#{PREFIX}.#{name}", :params => params)
    assert_equal "completed", result["status"], result.inspect
    result.fetch("value")
  end

  def invoke(name, params)
    API.invoke(:context => @context, :name => name, :params => params,
               :request => { "sequence" => @sequence += 1, "expected_revision" => @session.revision })
  end
end
