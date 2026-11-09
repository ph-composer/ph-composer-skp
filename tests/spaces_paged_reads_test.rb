# frozen_string_literal: true

require_relative "test_helper"
require_relative "support/space_fixtures"

# The bounded Spaces reads (context/AGENT_INTERFACE.md, "Focused reads"): `list` answers summaries
# within the reply budget with sums no filter changes, and the scoped reads answer one Space's
# Volumes, one Space's or Volume's Floor Segments and the findings, each paged the same way.
class SpacesPagedReadsTest < PhComposerTestCase
  include SpaceFixtures

  API = PhComposer::API
  MODEL_SUMS = [34.0, 32.0, 95.6].freeze
  HALL = { "space_id" => "spc_HHHHHHHHHHHH", "entity_path" => [1000, 1300] }.freeze

  def setup
    super
    @model = Sketchup.active_model
    @session = PhComposer::Sessions.for(@model)
    @context = API.connect(:session_id => @session.id)
  end

  def test_the_model_sums_never_change_with_ids_limit_or_a_cursor_walk
    reference_model
    sums = [{}, { "ids" => ["spc_FFFFFFFFFFFF"] }, { "ids" => [] }, { "limit" => 1 }].map do |params|
      model_sums(read("list", params))
    end
    walked = walk("list", { "limit" => 1 }, "spaces")

    assert_equal [MODEL_SUMS] * 4, sums
    assert_equal [MODEL_SUMS] * 4, walked.map { |value| model_sums(value) }
    numbers = walked.flat_map { |value| value["spaces"].map { |row| row.dig("values", "number") } }
    assert_equal %w[101 102 103 201], numbers
  end

  def test_a_summary_counts_its_children_and_carries_only_the_fields_asked_for
    reference_model
    hall = read("list", { "ids" => ["spc_HHHHHHHHHHHH"] }).fetch("spaces").first
    projected = read("list", { "ids" => ["spc_HHHHHHHHHHHH"], "fields" => ["metrics"] }).fetch("spaces").first

    assert_equal [2, 2, "Main Building"], hall.values_at("volume_count", "floor_segment_count", "building_segment")
    refute(%w[volumes findings user_data extension_data extension_status].any? { |key| hall.key?(key) })
    assert_equal %w[id metrics reference schema_version], projected.keys.sort
  end

  def test_a_page_names_the_sums_of_its_own_zones_and_segments
    reference_model
    loft = read("list", { "ids" => ["spc_FFFFFFFFFFFF"] })

    assert_equal ["Zone B"], loft.fetch("zones").map { |zone| zone["name"] }
    assert_equal [12.0], loft.fetch("zones").map { |zone| zone["floor_area_m2"].round(6) }
    assert_equal ["Main Building"], loft.fetch("building_segments").map { |row| row["name"] }
  end

  def test_one_spaces_volumes_and_floor_segments_read_by_reference
    reference_model
    volumes = read("volumes.list", { "space" => HALL }).fetch("volumes")
    by_space = read("floor_segments.list", { "space" => HALL }).fetch("floor_segments")
    second = volumes.last.fetch("reference")
    by_volume = read("floor_segments.list", { "volume" => second }).fetch("floor_segments")

    assert_equal [1, 1], volumes.map { |volume| volume["floor_segment_count"] }
    assert_equal %w[fsg_HHHHHHHHHHHH fsg_IIIIIIIIIIII], by_space.map { |row| row["id"] }
    assert_equal %w[fsg_IIIIIIIIIIII], by_volume.map { |row| row["id"] }
  end

  def test_a_scope_must_name_one_parent_that_still_carries_its_id
    reference_model

    assert_equal "params.invalid", query("floor_segments.list", {})["code"]
    assert_equal "params.invalid", query("floor_segments.list", { "space" => HALL,
                                                                  "volume" => HALL.merge("volume_id" => "x") })["code"]
    assert_equal "target.changed",
                 query("volumes.list", { "space" => HALL.merge("space_id" => "spc_XXXXXXXXXXXX") })["code"]
    assert_equal "target.not_found",
                 query("volumes.list", { "space" => HALL.merge("entity_path" => [1000, 9]) })["code"]
  end

  def test_findings_read_for_the_model_or_one_space_and_by_code
    reference_model
    everything = read("findings.list", {}).fetch("findings")
    hall = read("findings.list", { "space" => HALL }).fetch("findings")
    codes = everything.map { |finding| finding["code"] }.uniq

    refute_empty everything
    assert(everything.all? { |finding| finding["reference"].is_a?(Hash) })
    assert(hall.all? { |finding| finding.dig("reference", "entity_path")&.first(2) == [1000, 1300] })
    chosen = read("findings.list", { "codes" => [codes.first] }).fetch("findings")
    assert_equal [codes.first], chosen.map { |finding| finding["code"] }.uniq
  end

  def test_a_projection_keeps_the_page_aggregates
    reference_model
    loft = read("list", { "ids" => ["spc_FFFFFFFFFFFF"], "fields" => ["metrics"] })

    assert_equal ["Zone B"], loft.fetch("zones").map { |zone| zone["name"] }
    assert_equal ["Main Building"], loft.fetch("building_segments").map { |row| row["name"] }
  end

  def test_small_pages_walk_every_finding_and_floor_segment_once
    reference_model
    nested = volume_group(1330, volume_record("N", :number => 3), [floor_face(1331, rectangle(0, 6, 1, 1),
                                                                              segment_record("N"))])
    hall = @model.entities.to_a.first.entities.to_a.last
    hall.entities.to_a.first.entities << nested
    hall.entities.to_a.first.entities << floor_face(1399, rectangle(1, 6, 1, 1), segment_record("O"))
    whole = read("findings.list", {})
    findings = walk("findings.list", { "limit" => 1 }, "findings").flat_map { |value| value["findings"] }
    segments = walk("floor_segments.list", { "space" => HALL, "limit" => 1 }, "floor_segments")

    assert_equal whole.fetch("total"), findings.length
    assert_equal whole.fetch("findings"), findings
    assert_equal 4, segments.first.fetch("total")
    assert_equal 4, segments.flat_map { |value| value["floor_segments"].map { |row| row["id"] } }.uniq.length
  end

  def test_a_space_scope_keeps_its_misplaced_records_and_an_orphan_volume_reads_by_reference
    reference_model
    hall = @model.entities.to_a.first.entities.to_a.last
    hall.entities << floor_face(1390, rectangle(0, 8, 1, 1), segment_record("M"))
    orphan = volume_group(2900, volume_record("O"), [floor_face(2901, rectangle(20, 0, 1, 1), segment_record("P"))])
    @model.entities.to_a.last.entities << orphan

    scoped = read("findings.list", { "space" => HALL }).fetch("findings").map { |finding| finding["code"] }
    reference = { "volume_id" => "vol_OOOOOOOOOOOO", "entity_path" => [2000, 2900] }
    segments = read("floor_segments.list", { "volume" => reference }).fetch("floor_segments")

    counted = read("list", { "ids" => ["spc_HHHHHHHHHHHH"] }).dig("spaces", 0, "finding_counts")

    assert_includes scoped, "space.segment_misplaced"
    assert_equal scoped.tally, counted
    assert_equal %w[fsg_PPPPPPPPPPPP], segments.map { |row| row["id"] }
  end

  def test_the_model_wide_findings_read_names_an_orphan_volumes_own_findings_once
    reference_model
    sloped = [[20, 0, 0], [21, 0, 0], [21, 1, 0.5], [20, 1, 0.5]]
    orphan = volume_group(2900, volume_record("O", :height => nil),
                          [floor_face(2901, sloped, segment_record("P"))])
    @model.entities.to_a.last.entities << orphan
    path = [2000, 2900]

    findings = read("findings.list", {}).fetch("findings")
    on_orphan = findings.select { |finding| finding.dig("reference", "entity_path") == path }.map { |row| row["code"] }
    on_segment = findings.select { |finding| finding.dig("reference", "entity_path") == path + [2901] }

    assert_equal %w[space.height_missing space.volume_orphan], on_orphan.sort,
                 "its own finding joins the stray one, and it is not called nested"
    assert_equal ["space.floor_projected"], on_segment.map { |row| row["code"] }
    assert_equal "fsg_PPPPPPPPPPPP", on_segment.first.dig("reference", "floor_segment_id")
    in_all = query("all", {}).dig("value", "findings").select { |row| row.dig("reference", "entity_path") == path }
    assert_equal ["space.volume_orphan"], in_all.map { |row| row["code"] }, "all still reports the stray alone"

    @model.entities.to_a.last.entities << volume_group(2950, volume_record("O", :height => nil), [])
    twice = read("findings.list", {}).fetch("findings").select { |row| row.dig("reference", "entity_path") == path }
    assert_equal 1, twice.count { |row| row["code"] == "space.duplicate_identity" }, "a duplicated id once"
  end

  def test_an_orphan_volume_that_cannot_be_measured_leaves_all_and_list_reading
    reference_model
    tiny = Sketchup::Group.new(2900, Sketchup::Entities.new([floor_face(2901, rectangle(20, 0, 1, 1),
                                                                        segment_record("P"))]),
                               :locked => true, :transformation => Geom::Transformation.scaling(1e-5))
    SPACES::VOLUME_STORE.write(tiny, volume_record("O"))
    @model.entities << tiny

    whole = query("all", {})
    listed = query("list", {})
    findings = query("findings.list", {})

    assert_equal %w[completed completed completed], [whole, listed, findings].map { |result| result["status"] },
                 whole.inspect
    assert_equal 4, whole.dig("value", "spaces").length
  end

  def test_floor_segment_loops_only_when_asked
    reference_model
    plain = read("floor_segments.list", { "space" => HALL }).fetch("floor_segments").first
    looped = read("floor_segments.list", { "space" => HALL, "fields" => ["loops_m"] }).fetch("floor_segments").first

    refute plain.key?("loops_m")
    assert_equal 4, looped.fetch("loops_m").first.length
    assert_equal %w[id loops_m reference schema_version], looped.keys.sort
  end

  def test_six_hundred_floor_segments_walk_whole
    faces = Array.new(600) { |index| floor_face(5000 + index, rectangle(index, 0, 1, 1), segment_record("S")) }
    space = space_group(1100, space_record("S", :number => "101"), [volume_group(1110, volume_record("S"), faces)])
    @model.entities << zone_group(1000, "A", [space])
    scope = { "space" => { "space_id" => "spc_SSSSSSSSSSSS", "entity_path" => [1000, 1100] }, "limit" => 500 }

    pages = walk("floor_segments.list", scope, "floor_segments")

    assert_operator pages.length, :>=, 2
    assert_equal 600, pages.sum { |value| value["floor_segments"].length }
  end

  def test_a_page_with_long_named_zones_fits_the_reply_limit
    zones = Array.new(20) do |index|
      space = space_group(100 + index, space_record("S", :number => index.to_s), [])
      zone = zone_group(1000 + index, "Z", [space])
      ZONES::ZONE_STORE.write(zone, { "id" => format("zon_%012d", index), "schema_version" => 1,
                                      "name" => "Zone #{'Z' * 1500} #{index}",
                                      "building_segment" => "Segment #{'B' * 1500} #{index}", "level" => "L1",
                                      "ground_depth_mm" => 0.0 })
      SPACES::SPACE_STORE.write(space, SPACES::SPACE_STORE.read(space).merge("zone_id" => format("zon_%012d", index)))
      zone
    end
    zones.each { |zone| @model.entities << zone }
    treat_duplicates_as_existing(@model)
    pages = walk("list", { "limit" => 500 }, "spaces")
    largest = pages.map { |value| JSON.generate(query("list", { "limit" => 500 }).merge("value" => value)).bytesize }

    assert_operator largest.max, :<=, PhComposer::AgentAccess::Executor::MAX_RESULT_BYTES
    assert_equal 20, pages.sum { |value| value["spaces"].length }
    assert_equal 20, pages.sum { |value| value["zones"].length }
  end

  def test_many_spaces_page_within_the_byte_budget_and_walk_whole
    many_spaces(300)
    first = read("list", { "limit" => 500 })
    walked = walk("list", { "limit" => 500 }, "spaces")

    assert_operator JSON.generate(first["spaces"]).bytesize, :<=, PhComposer::Pages::MAX_PAGE_BYTES
    refute_nil first["next_cursor"]
    assert_equal 300, walked.sum { |value| value["spaces"].length }
    assert_equal 300, walked.flat_map { |value| value["spaces"].map { |row| row["id"] } }.uniq.length
  end

  def test_a_cursor_answers_only_the_same_read_scope_and_fields
    many_spaces(60)
    cursor = read("list", { "fields" => ["values"] }).fetch("next_cursor")

    refute_nil cursor
    assert_equal "params.invalid", query("list", { "fields" => ["metrics"], "cursor" => cursor })["code"]
    @session.host_event(:transaction_committed)
    assert_equal "query.cursor_expired", query("list", { "fields" => ["values"], "cursor" => cursor })["code"]
  end

  private

  def query(read, params)
    API.query(:context => @context, :name => "ph_composer.spaces.#{read}", :params => params)
  end

  def read(read, params)
    result = query(read, params)
    assert_equal "completed", result["status"], result.inspect
    result.fetch("value")
  end

  def walk(read, params, key)
    pages = [read(read, params)]
    pages << read(read, params.merge("cursor" => pages.last["next_cursor"])) while pages.last["next_cursor"]
    assert(pages.all? { |value| value.key?(key) })
    pages
  end

  def model_sums(value)
    value.fetch("model").values_at("floor_area_m2", "weighted_area_m2", "net_volume_m3").map { |n| n.round(6) }
  end

  # `count` Spaces with long Unicode names in one Zone, each with one Volume and one Floor Segment.
  def many_spaces(count)
    spaces = Array.new(count) do |index|
      id = format("%012d", index)
      record = { "id" => "spc_#{id}", "schema_version" => 1, "name" => "Wohnzimmer Süd #{'é' * 40} #{index}",
                 "number" => index.to_s, "default_height_m" => 2.5, "next_volume_sequence" => 2 }
      volume = { "id" => "vol_#{id}", "schema_version" => 1, "number" => 1, "display_name" => "",
                 "floor_id" => "flr_#{id}", "avg_ceiling_height_m" => 2.5 }
      segment = { "id" => "fsg_#{id}", "schema_version" => 1, "display_name" => "", "weighting_factor" => 1.0,
                  "net_area_factor" => 1.0 }
      space_group(10_000 + (index * 10), record,
                  [volume_group(10_001 + (index * 10), volume,
                                [floor_face(10_002 + (index * 10), rectangle(index, 0, 1, 1), segment)])])
    end
    @model.entities << zone_group(1000, "A", spaces)
  end
end
