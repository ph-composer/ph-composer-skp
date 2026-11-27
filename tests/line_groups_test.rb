# frozen_string_literal: true

require_relative "test_helper"

# The shared line-group layer (src/ph_composer/line_groups/) over a probe spec no feature registers: the walk finds
# each placement, the resolvers take and refuse paths, the steps make a group from loose lines, write and clear in
# one Undo step, the schedule pages and Locate selects. Nothing under the package names a feature
# (context/EXTENSIBILITY.md, "Line groups").
class LineGroupsTest < PhComposerTestCase
  L = PhComposer::LineGroups
  R = PhComposer::Records
  GROUP_STORE = R::EntityStore.new("ph_composer.test_line_groups.group", :claims_entity => true)
  EDGE_STORE = R::EntityStore.new("ph_composer.test_line_groups")
  SPEC = L::Spec.new(
    :label => "Probe group", :edge_noun => "probe", :group_kind => "test.line_groups.probe.group",
    :edge_kind => "test.line_groups.probe.line", :group_store => GROUP_STORE, :edge_store => EDGE_STORE,
    :group_record_kind => R::RecordKind.new(
      :id => "test.line_groups.probe.group", :label => "Probe group", :schema_version => 1, :id_prefix => "prg",
      :fields => [R::AuthoringFields.field("owner_id", { "type" => %w[string null] }, :required => true)]
    ),
    :edge_record_kind => R::RecordKind.new(
      :id => "test.line_groups.probe.line", :label => "Probe line", :schema_version => 1, :id_prefix => "prl",
      :fields => [R::AuthoringFields.field("size", { "type" => "integer" }, :required => true)]
    ),
    :link_key => "owner_id",
    :codes => { :outside_group => "probe.outside_group", :group_nested => "probe.group_nested",
                :group_in_zone => "probe.group_in_zone", :hidden => "probe.hidden" },
    :child_lookup => -> { PhComposer::Zones::ChildLookup.new }
  ).freeze
  QUERY = "test.line_groups.probe.schedule"
  ROOT = File.join(SOURCE_ROOT, "ph_composer", "line_groups")

  def setup
    super
    @model = Sketchup.active_model
    @session = PhComposer::Sessions.for(@model)
    # Probe group 700 at the root holds Edges 701 and 702; Group 710, a second placement of its storage, shares
    # them. Plain Group 730 holds Edge 731, assigned but in no probe group.
    @lines = [701, 702].map { |id| line(id) }
    @group = probe_group(700, "prg_AAAAAAAAAAAA", @lines)
    @copy = Sketchup::Group.new(710, @group.entities)
    GROUP_STORE.write(@copy, GROUP_STORE.read(@group))
    @stray = line(731)
    @model.entities << @group << @copy << Sketchup::Group.new(730, Sketchup::Entities.new([@stray]))
  end

  def test_two_placements_of_one_group_are_two_occurrences
    groups, unreadable = L::Scan.walk(SPEC, @model)
    assert_empty unreadable
    assert_equal [[[700], true, 2], [[710], true, 2]],
                 groups.map { |occurrence| [occurrence.path, occurrence.shared, occurrence.edges.length] }
    assert_equal [[700], [710]], L::GroupTarget.entries(SPEC, @model).map(&:key)
    assert_equal [[700, 701], [700, 702], [710, 701], [710, 702], [730, 731]],
                 L::EdgeTarget.entries(SPEC, @model).map(&:key)
  end

  def test_the_scan_detaches_each_placements_edges_and_reports_an_unreadable_record_as_a_row
    @lines.first.set_attribute(EDGE_STORE.dictionary, EDGE_STORE.key, JSON.generate("size" => "big"))
    edges, unreadable = L::Scan.edges(SPEC, request("test.line_groups.scan"), :zones => false)
    assert_equal [[[700, 702], true], [[710, 702], true]], edges.map { |edge| [edge.path, edge.shared] }
    assert_equal({ "group_id" => "prg_AAAAAAAAAAAA", "group_path" => [710], "name" => "", "owner_id" => "own_1",
                   "in_zone" => false }, edges.last.group)
    assert_equal [[0.0, 0.0, 0.0], [2.54, 17.8308, 0.0]],
                 edges.first.points_m.map { |point| point.map { |value| value.round(4) } }
    assert_equal [[[700, 701], "record.unreadable"], [[710, 701], "record.unreadable"]],
                 unreadable.map { |row| row.values_at("path", "code") }
  end

  def test_group_and_edge_paths_resolve_and_an_edge_outside_a_group_refuses
    group = { "group_id" => "prg_AAAAAAAAAAAA", "group_path" => [700] }
    assert_same @group, L::GroupTarget.locate(SPEC, @model, group, :mutable => false).entity
    edge = { "group_path" => [700], "entity_path" => [700, 701], "entity_id" => "prl_AAAAAAAAAAAA" }
    assert_same @lines.first, L::EdgeTarget.locate(SPEC, @model, edge, :mutable => false).entity
    assert_refused("target.shared_definition") { L::EdgeTarget.locate(SPEC, @model, edge, :mutable => true) }
    stray = { "group_path" => [730], "entity_path" => [730, 731], "entity_id" => "prl_AAAAAAAAAAAA" }
    error = assert_refused("probe.outside_group") { L::EdgeTarget.locate(SPEC, @model, stray, :mutable => false) }
    assert_equal "The Edge is not directly inside a Probe group.", error.message
  end

  # The host deletes a Group left empty at commit, so the layer makes no empty one: it wraps lines already drawn, in
  # their own collection, and leaves the edit path where it is.
  def test_make_wraps_loose_lines_in_a_new_group_keeping_their_ids_and_records_in_one_undo_step
    loose = [801, 802].map { |id| line(id) }
    loose.each { |edge| @model.entities << edge }
    record = { "id" => "prg_BBBBBBBBBBBB", "schema_version" => 1, "owner_id" => nil, "user_data" => {},
               "extension_data" => {} }
    step = L::MakeStep.new(:spec => SPEC, :record => record, :name => "Probe group 1", :parent_path => [],
                           :edge_ids => [801, 802])
    operate { step.apply(@model, nil) }
    made = @model.entities.to_a.find { |entity| GROUP_STORE.read(entity) == record }
    assert_equal [loose, nil, "Probe group 1"], [made.entities.to_a, @model.active_path, made.name]
    assert_equal [[801, 802], [EDGE_STORE.read(loose.first)] * 2],
                 [made.entities.map(&:persistent_id), made.entities.map { |edge| EDGE_STORE.read(edge) }]
    assert_equal ["probe_group", "make_probe_group", [made.persistent_id]],
                 [step.affected.first.fetch("kind"), step.descriptor["name"],
                  step.affected.first.dig("reference", "group_path")]
    @model.undo
    assert_equal [700, 710, 730, 801, 802], @model.entities.map(&:persistent_id)
    assert_nil GROUP_STORE.read(@model.entities.to_a.last)
  end

  # The plan is checked again at apply: the open context moved, or a line gone or no longer loose, writes nothing.
  def test_make_refuses_at_apply_when_the_context_or_a_line_changed
    @model.entities << line(801)
    record = { "id" => "prg_BBBBBBBBBBBB", "schema_version" => 1, "owner_id" => nil, "user_data" => {},
               "extension_data" => {} }
    make = lambda do |ids|
      L::MakeStep.new(:spec => SPEC, :record => record, :name => "Probe group 1", :parent_path => [], :edge_ids => ids)
    end
    @model.active_path = [@group]
    assert_refused("target.edit_path_changed") { make.call([801]).apply(@model, nil) }
    @model.active_path = nil
    assert_refused("target.changed") { make.call([801, 899]).apply(@model, nil) }
    assert_refused("target.changed") { make.call([700]).apply(@model, nil) }
    assert_equal [700, 710, 730, 801], @model.entities.map(&:persistent_id)
  end

  def test_an_edge_record_is_written_and_cleared
    @model.entities.erase_entities(@copy)
    reference = { "group_path" => [700], "entity_path" => [700, 702], "entity_id" => nil }
    before = EDGE_STORE.read(@lines.last)
    after = before.merge("id" => "prl_BBBBBBBBBBBB", "size" => 5)
    write = { "reference" => reference.merge("entity_id" => "prl_AAAAAAAAAAAA"), "before" => before,
              "after" => after, "change" => "updated" }
    operate { L::EdgeWriteStep.new(:spec => SPEC, :updates => [write]).apply(@model, nil) }
    assert_equal after, EDGE_STORE.read(@lines.last)
    clear = { "reference" => reference.merge("entity_id" => "prl_BBBBBBBBBBBB"), "before" => after,
              "change" => "removed" }
    operate { L::EdgeWriteStep.new(:spec => SPEC, :updates => [clear]).apply(@model, nil) }
    assert_nil EDGE_STORE.read(@lines.last)
    stale = write.merge("reference" => reference)
    assert_refused("target.changed") { L::EdgeWriteStep.new(:spec => SPEC, :updates => [stale]).apply(@model, nil) }
  end

  def test_a_probe_schedule_pages_its_runs_members_and_details
    pages = L::SchedulePages.new(:page => QUERY, :members => "#{QUERY}.members", :details => "#{QUERY}.details",
                                 :parts => { "owners" => "owner_id", "unreadable" => "path" },
                                 :counts => { "owners" => "owner_count" }, :names => %w[display_name],
                                 :run_label => "probe run", :schedule => ->(_request) { schedule })
    first = pages.page(request(QUERY, "limit" => 1, "compact" => true))
    assert_equal [["a"], 1, 2, false], [first.fetch("runs").map { |row| row.fetch("identifier") },
                                        first.fetch("owner_count"), first.fetch("total"), first.key?("owners")]
    rest = pages.page(request(QUERY, "limit" => 1, "compact" => true, "cursor" => first.fetch("next_cursor")))
    assert_equal [["b"], nil], [rest.fetch("runs").map { |row| row.fetch("identifier") }, rest.fetch("next_cursor")]
    members = pages.members(request("#{QUERY}.members", "identifier" => "b"))
    assert_equal [[1, 2], [1, 3]], members.fetch("members").map { |row| row.fetch("path") }
    assert_equal [{ "owner_id" => "own_1", "name" => "Owner" }],
                 pages.details(request("#{QUERY}.details", "part" => "owners")).fetch("owners")
    error = assert_refused("target.not_found") { pages.members(request("#{QUERY}.members", "identifier" => "c")) }
    assert_equal "No probe run is c now.", error.message
  end

  def test_locate_selects_two_edges_and_opens_their_group
    @model.entities.erase_entities(@copy)
    located = L::Locate.call(SPEC, request("test.line_groups.locate"), :edge_paths => [[700, 701], [700, 702]])
    assert_equal({ "path" => [700], "selected" => 2 }, located)
    assert_equal @lines, @model.selection.to_a
    error = assert_refused("target.wrong_kind") do
      L::Locate.call(SPEC, request("test.line_groups.locate"), :edge_paths => [[730, 731]])
    end
    assert_equal "The path does not end at a probe in a Probe group.", error.message
  end

  def test_the_selection_reads_each_edge_in_the_open_group_with_the_refusal_a_write_meets
    @model.entities.erase_entities(@copy)
    PhComposer::EditContext.enter(@model, [@group])
    face = Sketchup::Face.new(709)
    @group.entities << face
    @model.selection.add([@lines.first, face])
    held = ->(_paths) { [{ "path" => [700], "zone" => { "name" => "Zone A" } }] }
    read = L::Selection.all(SPEC, request("test.line_groups.selection"), :limit => 250, :contained => held)
    row = read.fetch("edges").first
    assert_equal [[700, 701], { "group_id" => "prg_AAAAAAAAAAAA", "group_path" => [700], "owner_id" => "own_1" },
                  { "size" => 1 }, 1],
                 [row.dig("reference", "entity_path"), row.fetch("group"), row.fetch("values"), read["ignored_total"]]
    assert_equal({ "code" => "probe.group_in_zone",
                   "message" => "The Probe group sits inside Zone “Zone A”; move it out first." }, row["write_refusal"])
    free = L::Selection.all(SPEC, request("test.line_groups.selection"), :limit => 250, :contained => ->(_paths) { [] })
    assert L::Selection.assignable?(free.fetch("edges").first)
    assert_refused("gesture.too_large") do
      L::Selection.all(SPEC, request("test.line_groups.selection"), :limit => 0, :contained => held)
    end
  end

  def test_a_nested_group_and_a_hidden_edge_refuse_with_the_features_codes
    inner = probe_group(741, "prg_CCCCCCCCCCCC", [line(742)])
    @model.entities << probe_group(740, "prg_DDDDDDDDDDDD", [inner])
    nested = { "group_id" => "prg_CCCCCCCCCCCC", "group_path" => [740, 741] }
    error = assert_refused("probe.group_nested") { L::GroupTarget.locate(SPEC, @model, nested, :mutable => false) }
    assert_equal "The Probe group sits inside another Probe group; move it out first.", error.message
    @model.entities.erase_entities(@copy)
    @lines.last.hidden = true
    assert_refused("probe.hidden") do
      L::Locate.call(SPEC, request("test.line_groups.locate"), :edge_paths => [[700, 701], [700, 702]])
    end
    assert_empty @model.selection.to_a
  end

  # The foundation's own ph_composer.context.open is allowed; nothing else of a feature is. The panel's line-group
  # screens (html/line_groups/) are held to the same rule.
  def test_nothing_under_line_groups_names_a_feature
    names = %r{ph_composer\.(piping|ducting|zones|mechanical)\b|\b(Piping|Ducting|Mechanical)\b|\bZones::|features/}
    panel = File.join(SOURCE_ROOT, "ph_composer", "html", "line_groups")
    files = Dir[File.join(ROOT, "**", "*.rb")] + Dir[File.join(panel, "*.{js,css}")]
    assert_operator files.length, :>=, 13
    ["ph_composer.piping.group", "Piping::Group", "Zones::ChildLookup", "Mechanical"].each do |text|
      assert_match names, text
    end
    refute_match names, "ph_composer.context.open"
    offenders = files.select { |path| File.read(path, :encoding => "UTF-8").match?(names) }
    assert_empty offenders.map { |path| path.delete_prefix("#{ROOT}/") }
  end

  private

  def line(id)
    edge = Sketchup::Edge.new(id, Geom::Point3d.new(0, 0, 0), Geom::Point3d.new(100, id, 0))
    EDGE_STORE.write(edge, "id" => "prl_AAAAAAAAAAAA", "schema_version" => 1, "size" => 1, "user_data" => {},
                           "extension_data" => {})
    edge
  end

  def probe_group(persistent_id, id, children)
    group = Sketchup::Group.new(persistent_id, Sketchup::Entities.new(children))
    GROUP_STORE.write(group, "id" => id, "schema_version" => 1, "owner_id" => "own_1", "user_data" => {},
                             "extension_data" => {})
    group
  end

  def schedule
    run = lambda do |identifier, paths|
      { "identifier" => identifier, "display_name" => identifier, "group" => { "name" => "G" },
        "edge_paths" => paths, "findings" => [] }
    end
    { "runs" => [run.call("a", [[1, 1]]), run.call("b", [[1, 2], [1, 3]])],
      "owners" => [{ "owner_id" => "own_1", "name" => "Owner" }], "unreadable" => [], "unreadable_total" => 0 }
  end

  def request(name, params = {})
    PhComposer::HandlerRequest.for(@session, :owner => "test.line_groups", :name => name, :params => params)
  end

  def operate
    @model.start_operation("probe", true)
    yield
    @model.commit_operation
  end

  def assert_refused(code)
    error = assert_raises(PhComposer::CodedError) { yield }
    assert_equal code, error.code, error.message
    error
  end
end
