# frozen_string_literal: true

require_relative "test_helper"
require_relative "support/assembly_assignment_fixtures"
require_relative "support/space_fixtures"
require_relative "support/window_convert_fixtures"
require_relative "support/agent_reads"

# Large occurrence, geometry and schedule data read completely through the agent connection (AW-05, contract
# C03, acceptance A07b): every reply goes through the real executor and fits its budget, and what the pages
# and fragments carry joins back to exactly what the whole read answers in process.
class OccurrenceDetailTest < PhComposerTestCase
  include AssemblyAssignmentFixtures
  include SpaceFixtures
  include WindowConvertFixtures
  include AgentReads

  A = PhComposer::AgentAccess
  P = "ph_composer"
  TB = PhComposer::ThermalBridges
  TEXT = "Wärme \"Brücke\"\n漢字 🙂 tab\t\\ ".freeze

  def setup
    super
    assignment_setup
    @executor = A::Executor.new(:tools => A::Tools::TABLE)
    issued = A::Tokens.issue(:capabilities => %w[read model_write])
    @token = A::Tokens.snapshot.fetch(A::Tokens.digest(issued.fetch("token")))
    @next_id = 60_000
  end

  def test_a_unit_with_30_kb_metadata_and_a_long_name_is_listed_compactly_and_read_exactly
    big, _small, large = large_units
    list = { "ids" => [big] }

    assert_equal "request.response_too_large", query("#{P}.windows.units.list", list).fetch("code")
    summary = completed(query("#{P}.windows.units.list", list.merge("fields" => [], "metadata" => "summary")))
    row = summary.dig("units", 0)
    refute row.key?("user_data")
    assert_equal({}, row.fetch("values"))
    assert_equal [{ "keys" => 2 }.merge(PhComposer::Fragments.summary(large)), ["name"], 256],
                 [row.dig("metadata", "user_data"), row.fetch("truncated"), row.fetch("name").length]
    whole = API.query(:context => @context, :name => "#{P}.windows.units.list", :params => list)
    whole = whole.dig("value", "units", 0)
    reference = row.fetch("reference")
    parts = PhComposer::Windows::Units::Actions::DETAIL_PARTS.to_h { |part| [part, unit_detail(reference, [part])] }
    assert_equal whole, parts.merge(whole.slice("reference", "id", "schema_version"))
    assert_equal "N" * 400, unit_detail(reference, ["name"])
    absent = query("#{P}.windows.units.detail", "unit" => reference, "path" => %w[user_data absent])
    assert_equal "target.not_found", absent.fetch("code")
    moved = reference.merge("unit_id" => "wun_#{'Z' * 12}")
    assert_equal "target.changed",
                 query("#{P}.windows.units.detail", "unit" => moved, "path" => ["values"]).fetch("code")
  end

  def test_reconstructed_unit_metadata_guards_an_update_and_a_later_edit_refuses_the_whole_write
    big, small, large = large_units
    targets = [unit_reference(big), unit_reference(small)]
    updates = targets.map do |target|
      user_data = unit_detail(target, ["user_data"])
      expected = { "user_data" => user_data, "extension_data" => unit_detail(target, ["extension_data"]) }
      { "reference" => target, "user_data" => user_data.merge("edited" => "yes"), "expected_metadata" => expected }
    end
    applied = agent("invoke", "name" => "#{P}.windows.units.update_metadata", "params" => { "updates" => updates },
                              "expected_revision" => @session.revision)
    assert_equal %w[completed committed], applied.values_at("status", "effect"), applied.inspect
    assert_equal large.merge("edited" => "yes"), unit_detail(targets.first, ["user_data"])

    # A metadata edit made after the read refuses the whole write: the other Unit keeps its metadata too.
    stale = targets.map do |target|
      { "reference" => target, "user_data" => { "agent" => true },
        "expected_metadata" => { "user_data" => unit_detail(target, ["user_data"]), "extension_data" => {} } }
    end
    other = assignment_invoke("#{P}.windows.units.update_metadata",
                              "updates" => [stale.last.merge("user_data" => { "person" => true })])
    assert_equal "committed", other.fetch("effect"), other.inspect
    refused = agent("invoke", "name" => "#{P}.windows.units.update_metadata", "params" => { "updates" => stale },
                              "expected_revision" => @session.revision)
    assert_equal %w[refused target.changed none], refused.values_at("status", "code", "effect"), refused.inspect
    assert_match(/metadata changed/, refused.fetch("message"))
    assert_equal [large.merge("edited" => "yes"), { "person" => true }],
                 targets.map { |target| unit_detail(target, ["user_data"]) }
  end

  def test_a_host_with_450_holes_reads_its_extent_holes_and_loops_in_pages
    outer = [[0, 0, 0], [1000, 0, 0], [1000, 1000, 0], [0, 1000, 0]].map { |xyz| Geom::Point3d.new(*xyz) }
    holes = Array.new(450) do |index|
      x = 25 + (30 * (index % 30))
      y = 25 + (30 * (index / 30))
      [[x, y, 0], [x, y + 10, 0], [x + 10, y + 10, 0], [x + 10, y, 0]].map { |xyz| Geom::Point3d.new(*xyz) }
    end
    face = Sketchup::Face.new(1001, {}, :points => outer, :holes => holes)
    @model.entities << Sketchup::Group.new(1000, Sketchup::Entities.new([face]))
    assert_equal "completed", assignment_invoke("#{P}.zones.make", "parent_path" => [], "entity_ids" => [1000])
      .fetch("status")
    host = assignment_faces.first.fetch("reference")
    whole = API.query(:context => @context, :name => "#{P}.windows.units.host_extent", :params => { "host" => host })
               .fetch("value")

    assert_equal "request.response_too_large", query("#{P}.windows.units.host_extent", "host" => host).fetch("code")
    summary = completed(query("#{P}.windows.units.host_extent", "host" => host, "geometry" => "summary"))
    assert_equal [4, 450, 0], summary.values_at("outline_points", "hole_count", "total")
    assert_equal whole.slice("width_m", "height_m"), summary.slice("width_m", "height_m")
    assert_in_delta 1000 * 0.0254, summary.fetch("width_m"), 1e-9

    read = rows_of("#{P}.windows.units.host_extent.holes", { "host" => host }, "holes", :pages => 2)
    assert_equal whole.fetch("holes"), read.map { |row| row.slice("x_m", "y_m", "width_m", "height_m") }
    assert_equal (0...450).to_a, read.map { |row| row.fetch("index") }
    assert_equal [4], read.map { |row| row.fetch("point_count") }.uniq
    outline = rows_of("#{P}.windows.units.host_extent.points", { "host" => host }, "points")
    assert_equal whole.fetch("outline_m"), outline.map { |point| point.values_at("x_m", "y_m") }
    last = rows_of("#{P}.windows.units.host_extent.points", { "host" => host, "hole" => 449 }, "points")
    assert_equal whole.dig("holes", 449).values_at("x_m", "y_m"),
                 [last.map { |point| point.fetch("x_m") }.min, last.map { |point| point.fetch("y_m") }.min]
    assert_equal "target.not_found",
                 query("#{P}.windows.units.host_extent.points", "host" => host, "hole" => 450).fetch("code")
  end

  def test_a_page_of_500_far_apart_loop_points_fits_a_reply
    radius = 100_000 / 0.0254
    outer = Array.new(1000) do |index|
      angle = 2 * Math::PI * index / 1000
      Geom::Point3d.new(radius * Math.cos(angle), radius * Math.sin(angle), 0)
    end
    @model.entities << Sketchup::Group.new(1000, Sketchup::Entities.new([Sketchup::Face.new(1001, {},
                                                                                            :points => outer)]))
    assert_equal "completed", assignment_invoke("#{P}.zones.make", "parent_path" => [], "entity_ids" => [1000])
      .fetch("status")
    host = assignment_faces.first.fetch("reference")
    points = rows_of("#{P}.windows.units.host_extent.points", { "host" => host, "limit" => 500 }, "points",
                     :pages => 3)
    assert_equal (0...1000).to_a, points.map { |point| point.fetch("index") }
  end

  def test_the_zone_list_leaves_450_restore_offers_and_80_findings_to_their_own_pages
    450.times { |index| stamp(2000 + index, format("zon_%012d", index), "Segment #{index}", "Level 1") }
    80.times do |index|
      component = Sketchup::ComponentInstance.new(9000 + index,
                                                  Sketchup::ComponentDefinition.new(Sketchup::Entities.new))
      PhComposer::Zones::ZONE_STORE.write(component, "id" => format("zon_C%011d", index), "schema_version" => 1,
                                                     "name" => "Component #{index}", "level" => "L1",
                                                     "building_segment" => "Main Building", "ground_depth_mm" => 0.0)
      @model.entities << component
    end
    whole = API.query(:context => @context, :name => "#{P}.zones.list").fetch("value")
    assert_equal [450, 80], [whole.fetch("restorable").length, whole.fetch("findings").length]

    assert_equal "request.response_too_large", query("#{P}.zones.list", "limit" => 1, "fields" => []).fetch("code")
    summary = completed(query("#{P}.zones.list", "limit" => 1, "fields" => [], "overview" => "summary"))
    assert_equal [450, 80], summary.values_at("restorable_total", "finding_total")
    refute summary.key?("restorable")

    offers = rows_of("#{P}.zones.restorable.list", {}, "restorable", :pages => 2)
    expected = whole.fetch("restorable").sort_by { |offer| offer.fetch("zone_id") }
    assert_equal expected.map { |offer| offer.reject { |key, _value| key == "entity_ids" } }, offers
    assert_equal expected.first.fetch("entity_ids"),
                 fragments_of("#{P}.zones.restorable.detail", "zone_id" => offers.first.fetch("zone_id"),
                                                              "path" => ["entity_ids"])
    missing = query("#{P}.zones.restorable.detail", "zone_id" => "zon_#{'Q' * 12}", "path" => ["entity_ids"])
    assert_equal "target.not_found", missing.fetch("code")
    assert_equal whole.fetch("findings"), rows_of("#{P}.zones.findings.list", { "limit" => 30 }, "findings",
                                                  :pages => 3)
  end

  def test_a_new_read_refuses_a_cursor_from_before_a_change_or_from_another_filter
    450.times { |index| stamp(2000 + index, format("zon_%012d", index), "Segment #{index}", "Level 1") }
    first = completed(query("#{P}.zones.restorable.list", "limit" => 10))
    cursor = first.fetch("next_cursor")
    assert_equal "params.invalid", query("#{P}.zones.findings.list", "cursor" => cursor).fetch("code")
    assignment_assembly("A change")
    assert_equal "query.cursor_expired",
                 query("#{P}.zones.restorable.list", "limit" => 10, "cursor" => cursor).fetch("code")
  end

  def test_450_adoption_sources_page_with_their_collision_clusters
    450.times { |index| stamp(5000 + index, format("zon_X%011d", index), "Copied #{index}", "Level #{index}") }
    segment = { "id" => "bsg_#{'F' * 12}", "schema_version" => 1, "name" => "Copied 0", "colour" => "#123456",
                "export_identifier" => PhComposer::Zones::Options.export_identifier("Copied 0") }
    face = floor_face(4999, rectangle(0, 0, 3, 4))
    PhComposer::Zones::STAMP_STORE.write(face, "schema_version" => 2, "zone_id" => "zon_#{'F' * 12}",
                                               "building_segment_id" => segment.fetch("id"), "level_id" => nil,
                                               "choice_evidence" => { "source_model_id" => "foreign",
                                                                      "building_segment" => segment, "level" => nil })
    @model.entities << face
    preview = API.query(:context => @context, :name => "#{P}.zones.options.adoption_preview").fetch("value")
    assert_operator JSON.generate(preview).bytesize, :>, BUDGET
    refute_empty preview.fetch("collision_clusters")

    sources = rows_of("#{P}.zones.options.adoption_sources.list", {}, "sources", :pages => 2)
    assert_equal preview.fetch("sources").sort_by { |source| source.fetch("key") },
                 sources.map { |source| source.reject { |key, _value| key == "cluster" } }
    clustered = sources.reject { |source| source.fetch("cluster").nil? }.map { |source| source.fetch("key") }
    assert_equal preview.fetch("collision_clusters").flatten.sort, clustered.sort
  end

  def test_a_799_edge_run_and_its_finding_page_their_edges_with_compact_schedule_rows
    type_id = created("#{P}.thermal_bridges.types.create", "values" => { "name" => "Long", "group" => "15-Ambient" })
              .fetch("id")
    vertices = Array.new(800) { |index| Sketchup::Vertex.new(Geom::Point3d.new(index * 0.33, 0, 0)) }
    edges = vertices.each_cons(2).with_index.map do |(from, to), index|
      edge = Sketchup::Edge.new(1000 + index, from, to)
      assign(edge, format("tbe_%012d", index), type_id)
      edge
    end
    @model.entities << zone_group(100, "Z", edges, :transformation => Geom::Transformation.translation([100, 0, 0]))
    whole = API.query(:context => @context, :name => "#{P}.thermal_bridges.schedule.all").fetch("value")
    run = whole.dig("runs", 0)
    assert_equal 799, run.fetch("edge_paths").length

    assert_equal "request.response_too_large", query("#{P}.thermal_bridges.schedule.list", "limit" => 1).fetch("code")
    page = completed(query("#{P}.thermal_bridges.schedule.list", "compact" => true))
    row = page.dig("runs", 0)
    totals = whole.fetch("totals")
    assert_equal [799, 800, 0], row.values_at("edge_count", "point_count", "index")
    assert_equal totals.reject { |key, _value| key == "by_type" }.merge("type_count" => 1), page.fetch("totals")
    assert_equal totals.fetch("by_type"), rows_of("#{P}.thermal_bridges.schedule.by_type.list", {}, "by_type")
    refute row.key?("edge_paths")
    assert_equal run.fetch("findings").map { |finding|
      [finding.fetch("code"), finding.dig("locate", "edge_paths").length]
    },
                 row.fetch("findings").map { |finding| finding.values_at("code", "edge_count") }
    assert_equal "thermal_bridge.psi_missing", row.dig("findings", 0, "code")

    members = rows_of("#{P}.thermal_bridges.runs.members.list", { "identifier" => row.fetch("identifier") }, "members",
                      :pages => 2)
    assert_equal run.fetch("edge_paths"), members.map { |member| member.fetch("path") }
    assert_equal run.fetch("points_m").each_cons(2).to_a, members.map { |member| member.fetch("points_m") }
    assert_in_delta (100 + 0.33) * 0.0254, members.first.dig("points_m", 1, 0), 1e-9
    named = rows_of("#{P}.thermal_bridges.runs.members.list", { "identifier" => row.fetch("identifier"),
                                                                "finding" => 0 }, "members")
    assert_equal run.dig("findings", 0, "locate", "edge_paths"), named.map { |member| member.fetch("path") }
    assert_equal "target.not_found", query("#{P}.thermal_bridges.runs.members.list",
                                           "identifier" => "tb_gone").fetch("code")
    assert_equal "target.not_found", query("#{P}.thermal_bridges.runs.members.list",
                                           "identifier" => row.fetch("identifier"), "finding" => 9).fetch("code")
  end

  def test_runs_sharing_an_identifier_and_long_type_names_stay_readable
    name = "T" * 30_000
    type_id = created("#{P}.thermal_bridges.types.create", "values" => { "name" => name, "group" => "15-Ambient" })
              .fetch("id")
    edges = Array.new(2) do |copy|
      edge = Sketchup::Edge.new(7000 + copy, Sketchup::Vertex.new(Geom::Point3d.new(0, 0, 0)),
                                Sketchup::Vertex.new(Geom::Point3d.new(40, 0, 0)))
      assign(edge, format("tbe_%012d", copy), type_id)
      edge
    end
    @model.entities << zone_group(100, "Z", edges)
    whole = API.query(:context => @context, :name => "#{P}.thermal_bridges.schedule.all").fetch("value")
    runs = completed(query("#{P}.thermal_bridges.schedule.list", "compact" => true)).fetch("runs")
    assert_equal whole.fetch("runs").length, runs.length
    assert_includes runs.first.fetch("truncated"), "type_name"
    assert_includes runs.first.fetch("truncated"), "findings.0.message"
    assert_equal [name[0, 256]], rows_of("#{P}.thermal_bridges.schedule.by_type.list", {}, "by_type")
      .map { |row| row.fetch("type_name") }
    shared = runs.group_by { |run| run.fetch("identifier") }.values.find { |group| group.length > 1 }
    skip "the stub gives these runs distinct identifiers" unless shared

    named = { "identifier" => shared.first.fetch("identifier") }
    assert_equal "target.ambiguous", query("#{P}.thermal_bridges.runs.members.list", named).fetch("code")
    members = shared.map do |run|
      rows_of("#{P}.thermal_bridges.runs.members.list", named.merge("index" => run.fetch("index")), "members")
    end
    assert_equal shared.map { |run| whole.dig("runs", run.fetch("index"), "edge_paths") },
                 members.map { |rows| rows.map { |member| member.fetch("path") } }
  end

  def test_more_than_50_orphan_and_unreadable_assignments_are_each_listed_once
    type_id = created("#{P}.thermal_bridges.types.create", "values" => { "name" => "Loose", "psi_w_mk" => 0.05,
                                                                         "group" => "15-Ambient" }).fetch("id")
    120.times do |index|
      edge = Sketchup::Edge.new(3000 + index, Sketchup::Vertex.new(Geom::Point3d.new(index, 0, 0)),
                                Sketchup::Vertex.new(Geom::Point3d.new(index, 5, 0)))
      assign(edge, format("tbe_%012d", index), type_id)
      @model.entities << edge
    end
    60.times do |index|
      edge = Sketchup::Edge.new(4000 + index, Sketchup::Vertex.new(Geom::Point3d.new(index, 10, 0)),
                                Sketchup::Vertex.new(Geom::Point3d.new(index, 15, 0)))
      edge.set_attribute(TB::Assignment::STORE.dictionary, TB::Assignment::STORE.key, "{not json #{'x' * 2000}")
      @model.entities << edge
    end
    whole = API.query(:context => @context, :name => "#{P}.thermal_bridges.schedule.all").fetch("value")
    assert_equal [120, 60], whole.values_at("edge_finding_total", "unreadable_total")

    page = completed(query("#{P}.thermal_bridges.schedule.list", "compact" => true))
    assert_equal [120, 60], page.values_at("edge_finding_total", "unreadable_total")
    refute page.key?("edge_findings")
    orphans = rows_of("#{P}.thermal_bridges.schedule.edge_findings.list", {}, "edge_findings", :pages => 2)
    assert_equal whole.fetch("edge_findings").sort_by { |row| row.fetch("path") }, orphans
    unreadable = rows_of("#{P}.thermal_bridges.schedule.unreadable.list", { "limit" => 25 }, "unreadable", :pages => 3)
    assert_equal whole.fetch("unreadable").map { |row| row.fetch("path") }.sort, unreadable.map { |row| row["path"] }
    assert_operator unreadable.map { |row| row.fetch("message").length }.max, :<=, TB::Scan::MAX_MESSAGE
  end

  def test_a_180_face_area_table_and_its_assembly_usage_read_in_scoped_pages
    assignment_zone(1000, 180)
    assignment_zone(2000, 3)
    assembly = assignment_assembly("Wall")
    faces = assignment_faces
    assert_equal "committed", assignment_invoke("#{P}.zones.faces.assign_assembly", assignment_params(faces, assembly))
      .fetch("effect")
    host = wall_host
    type = created("#{P}.windows.types.create", "values" => { "name" => "Glazed" }).fetch("id")
    hosted = place(host, type, 3.0, 3.0, {})
    loose = place(host, type, 12.0, 3.0, {})
    instance(loose).glued_to = nil
    whole = API.query(:context => @context, :name => "#{P}.windows.units.glazed_area_by_face").fetch("value")
    assert_operator JSON.generate(whole).bytesize, :>, BUDGET

    key = ->(row) { row.fetch("reference").values_at("zone_path", "entity_path").flatten }
    read = pages_of("#{P}.windows.units.face_areas.list", {}, "faces")
    assert_operator read.length, :>, 1
    assert_equal whole.fetch("faces").sort_by(&key), read.flat_map { |page| page.fetch("faces") }
    assert_equal [1], read.map { |page| page.fetch("unhosted_unit_total") }.uniq
    assert_equal whole.fetch("unhosted_units"), rows_of("#{P}.windows.units.unhosted.list", {}, "units")
    assert_equal [unit_reference(loose)], whole.fetch("unhosted_units")
    refute_nil unit_reference(hosted)
    zone = faces.find { |face| face.dig("reference", "zone_path") == [2000] }.dig("reference", "zone_id")
    scoped = rows_of("#{P}.windows.units.face_areas.list", { "zone_ids" => [zone] }, "faces")
    assert_equal whole.fetch("faces").select { |row| row.dig("reference", "zone_id") == zone }.sort_by(&key), scoped
    assert_equal scoped, rows_of("#{P}.windows.units.face_areas.list", { "zone_paths" => [[2000]] }, "faces")
    assert_equal "target.not_found", query("#{P}.zones.faces.assembly_usage.faces",
                                           "assembly_id" => "asm_#{'Q' * 12}").fetch("code")

    usage = API.query(:context => @context, :name => "#{P}.zones.faces.assembly_usage").dig("value", "assemblies")
    summary = rows_of("#{P}.zones.faces.assembly_usage.list", {}, "assemblies")
    assert_equal usage.map { |row| row.reject { |name, _value| name == "faces" } }, summary
    used = pages_of("#{P}.zones.faces.assembly_usage.faces", { "assembly_id" => assembly }, "faces")
    assert_operator used.length, :>, 1
    assert_equal usage.find { |row| row.fetch("assembly_id") == assembly }.fetch("faces"),
                 used.flat_map { |page| page.fetch("faces") }
    assert_equal [183], used.map { |page| page.fetch("face_count") }.uniq
  end

  def test_one_large_connected_convert_group_is_reviewed_compactly_read_whole_and_converted_whole
    PhComposer::Registry.install([PhComposer::Windows]) unless PhComposer::Registry.installed?("ph_composer.windows")
    rings = (0...14).flat_map { |i| (0...14).map { |j| ring(0.5 + (i * 0.5), 0.5 + (j * 0.25), 0.5, 0.25) } }
    faces = zone_with(rings, :outer => [[0, 0], [20, 0], [20, 20], [0, 20]], :holes => [ring(0.5, 0.5, 7, 3.5)])
    paths = faces.map { |face| [@group.persistent_id, face.persistent_id] }
    whole = API.query(:context => @context, :name => "#{P}.windows.units.convert_review",
                      :params => { "paths" => paths })
               .fetch("value")
    group = whole.dig("groups", 0)
    assert_equal [1, 196], [whole.fetch("groups").length, group.fetch("sources").length]

    assert_equal "request.response_too_large",
                 query("#{P}.windows.units.convert_review", "paths" => paths).fetch("code")
    compact = completed(query("#{P}.windows.units.convert_review", "paths" => paths, "compact" => true))
    row = compact.dig("groups", 0)
    assert_equal [196, group.reject { |name, _value| name == "sources" }],
                 [row.fetch("source_count"), row.reject { |name, _value|
                   %w[source_count sources_digest].include?(name)
                 }]
    sources = fragments_of("#{P}.windows.units.convert_review.detail", { "paths" => paths,
                                                                         "path" => ["groups", 0, "sources"] },
                           row.fetch("sources_digest"))
    assert_equal group.fetch("sources"), sources

    revision = @session.revision
    params = { "groups" => [{ "sources" => sources.map { |source| source.slice("path", "digest") } }] }
    converted = agent("invoke", "name" => "#{P}.windows.units.convert", "params" => params,
                                "expected_revision" => revision)
    assert_equal %w[completed committed], converted.values_at("status", "effect"), converted.inspect
  end

  def test_a_floor_segment_with_450_holes_reads_its_loops_exactly
    outer = rectangle(0, 0, 30, 30)
    holes = Array.new(450) { |index| rectangle(0.5 + (index % 25), 0.5 + (index / 25), 0.2, 0.2) }
    inches = ->(corners) { corners.map { |x, y, z| Geom::Point3d.new(x * INCHES, y * INCHES, z * INCHES) } }
    face = Sketchup::Face.new(1111, {}, :points => inches.call(outer), :holes => holes.map(&inches))
    SPACES::FLOOR_SEGMENT_STORE.write(face, segment_record("S"))
    space = space_group(1100, space_record("S", :number => "101"), [volume_group(1110, volume_record("S"), [face])])
    @model.entities << zone_group(1000, "A", [space], :transformation => Geom::Transformation.translation([0, 0, 120]))
    scope = { "space" => { "space_id" => "spc_#{'S' * 12}", "entity_path" => [1000, 1100] } }
    list = scope.merge("fields" => ["loops_m"], "limit" => 1)
    whole = API.query(:context => @context, :name => "#{P}.spaces.floor_segments.list", :params => list)
               .dig("value", "floor_segments", 0)

    assert_equal "request.response_too_large", query("#{P}.spaces.floor_segments.list", list).fetch("code")
    reference = completed(query("#{P}.spaces.floor_segments.list", scope)).dig("floor_segments", 0, "reference")
    loops = fragments_of("#{P}.spaces.detail", "floor_segment" => reference, "path" => ["loops_m"])
    assert_equal [451, whole.fetch("loops_m")], [loops.length, loops]
    assert_in_delta 120 * 0.0254, loops.dig(0, 0, 2), 1e-9
    stale = reference.merge("floor_segment_id" => "fsg_#{'Z' * 12}")
    assert_equal "target.changed", query("#{P}.spaces.detail", "floor_segment" => stale, "path" => ["loops_m"])
      .fetch("code")
    volume = completed(query("#{P}.spaces.volumes.list", scope)).dig("volumes", 0, "reference")
    values = API.query(:context => @context, :name => "#{P}.spaces.floor_segments.list",
                       :params => scope.merge("fields" => ["values"])).dig("value", "floor_segments", 0, "values")
    assert_equal values, fragments_of("#{P}.spaces.detail", "volume" => volume,
                                                            "path" => ["floor_segments", 0, "values"])
    assert_equal "101", fragments_of("#{P}.spaces.detail", scope.merge("path" => %w[values number]))
    assert_equal "params.invalid", query("#{P}.spaces.detail", "path" => ["values"]).fetch("code")
    assert_equal "params.invalid", query("#{P}.spaces.detail", scope.merge("floor_segment" => reference,
                                                                           "path" => ["values"])).fetch("code")
  end

  def test_the_new_reads_change_nothing
    host = wall_host
    type = created("#{P}.windows.types.create", "values" => { "name" => "Still" }).fetch("id")
    unit = unit_reference(place(host, type, 3.0, 3.0, { "notes" => TEXT * 100 }))
    assembly = assignment_assembly("Unused")
    revision = @session.revision
    before = [@model.operations.length, @model.modified?, @model.selection.to_a, @model.active_path]
    reads = [["windows.units.list", { "metadata" => "summary" }],
             ["windows.units.detail", { "unit" => unit, "path" => ["user_data"] }],
             ["windows.units.host_extent", { "host" => host, "geometry" => "summary" }],
             ["windows.units.host_extent.holes", { "host" => host }],
             ["windows.units.host_extent.points", { "host" => host }],
             ["windows.units.face_areas.list", {}], ["windows.units.unhosted.list", {}],
             ["zones.list", { "overview" => "summary" }], ["zones.restorable.list", {}], ["zones.findings.list", {}],
             ["zones.options.adoption_sources.list", {}], ["zones.faces.assembly_usage.list", {}],
             ["zones.faces.assembly_usage.faces", { "assembly_id" => assembly }],
             ["thermal_bridges.schedule.list", { "compact" => true }],
             ["thermal_bridges.schedule.edge_findings.list", {}], ["thermal_bridges.schedule.unreadable.list", {}]]
    reads.each { |name, params| completed(query("#{P}.#{name}", params)) }
    assert_equal [revision, before], [@session.revision, [@model.operations.length, @model.modified?,
                                                          @model.selection.to_a, @model.active_path]]
  end

  private

  def created(name, params)
    result = assignment_invoke(name, params)
    assert_equal "committed", result.fetch("effect"), result.inspect
    result.fetch("value")
  end

  # A classified Zone wall a Window can be placed on.
  def wall_host
    points = [[0, 0, 0], [1000, 0, 0], [1000, 1000, 0], [0, 1000, 0]].map { |xyz| Geom::Point3d.new(*xyz) }
    group = Sketchup::Group.new(@next_id += 1, Sketchup::Entities.new([Sketchup::Face.new(@next_id += 1, {},
                                                                                          :points => points)]))
    @model.entities << group
    assert_equal "completed", assignment_invoke("#{P}.zones.make", "parent_path" => [],
                                                                   "entity_ids" => [group.persistent_id])
      .fetch("status")
    wall = ->(row) { row.dig("reference", "zone_path") == [group.persistent_id] }
    intent = { "face_type" => { "mode" => "set", "value" => "Wall" },
               "boundary_condition" => { "mode" => "set", "value" => "Outdoors" } }
    assignment_classify([assignment_faces.find(&wall)], intent)
    assignment_faces.find(&wall).fetch("reference")
  end

  def place(host, type, x_m, y_m, user_data)
    placed = assignment_invoke("#{P}.windows.units.place", "host" => host, "type_id" => type, "anchor" => "sill_center",
                                                           "offsets" => { "x_m" => x_m, "y_m" => y_m },
                                                           "user_data" => user_data)
    assert_equal "committed", placed.fetch("effect"), placed.inspect
    placed.dig("value", "unit_id")
  end

  def unit_reference(id)
    API.query(:context => @context, :name => "#{P}.windows.units.list", :params => { "ids" => [id] })
       .dig("value", "units", 0, "reference")
  end

  def instance(id)
    path = unit_reference(id).fetch("entity_path")
    path.drop(1).reduce(@model.entities.to_a.find { |entity| entity.persistent_id == path.first }) do |parent, step|
      parent.entities.to_a.find { |entity| entity.persistent_id == step }
    end
  end

  # Two placed Units, one with 30 KB of user_data and a 400-character native name: [big, small, its user_data].
  def large_units
    host = wall_host
    type = created("#{P}.windows.types.create", "values" => { "name" => "Synthetic placement" }).fetch("id")
    large = { "notes" => (TEXT * 1200)[0, 30_000], "nothing" => nil }
    big = place(host, type, 3.0, 3.0, large)
    small = place(host, type, 12.0, 3.0, { "tag" => "small" })
    instance(big).name = "N" * 400
    [big, small, large]
  end

  # A legacy membership stamp on a loose Face, as an exploded Zone leaves it.
  def stamp(id, zone_id, segment, level)
    face = floor_face(id, rectangle(0, 0, 3, 4))
    PhComposer::Zones::STAMP_STORE.write(face, "schema_version" => 1, "zone_id" => zone_id,
                                               "building_segment" => segment, "level" => level)
    @model.entities << face
  end

  def unit_detail(reference, path)
    fragments_of("#{P}.windows.units.detail", "unit" => reference, "path" => path)
  end

  def assign(edge, id, type_id)
    TB::Assignment::STORE.write(edge, "id" => id, "schema_version" => 1, "thermal_bridge_type_id" => type_id,
                                      "quantity" => 1, "user_data" => {}, "extension_data" => {})
  end
end
