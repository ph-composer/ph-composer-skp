# frozen_string_literal: true

require_relative "test_helper"
require_relative "support/zone_options"

class SelectionTest < PhComposerTestCase
  include ZoneOptionsSupport

  API = PhComposer::API
  ZONES = PhComposer::Zones
  FACES = ZONES::Faces

  def setup
    super
    @model = Sketchup.active_model
    FACES::Settings::STORE.write(@model, FACES::Settings::DEFAULTS.merge("suggest_on_make" => false))
    @session = PhComposer::Sessions.for(@model)
    @context = API.connect(:session_id => @session.id)
    @sequence = 0
    @level_id = create_zone_option("level", "L2")
    create_zone_option("level", "L3")
    @groups = [make_zone(100), make_zone(200)]
    select(*@groups)
    @operation_count = @model.operations.length
  end

  def test_zone_query_is_detached_and_batch_changes_one_attribute_with_one_undo
    read = query("ph_composer.zones.selection")
    rows = read.dig("value", "zones")
    assert_equal [[100], [200]], rows.map { |row| row.dig("reference", "zone_path") }
    assert_equal %w[Zone\ 1 Zone\ 2], rows.map { |row| row.dig("values", "name") }
    before = @groups.map { |group| ZONES::ZONE_STORE.read(group) }
    before.first["user_data"] = { "test.note" => "retain" }
    ZONES::ZONE_STORE.write(@groups.first, before.first)

    result = update(rows, "level", "L2", read.fetch("revision"))

    assert_equal %w[completed committed], result.values_at("status", "effect")
    assert_equal [@level_id, @level_id], @groups.map { |group| ZONES::ZONE_STORE.read(group).fetch("level_id") }
    assert_equal before.first.fetch("user_data"), ZONES::ZONE_STORE.read(@groups.first).fetch("user_data")
    assert_equal ["Edit Selected Zones", true, :committed], @model.operations.last
    assert_equal @operation_count + 1, @model.operations.length
    assert @model.undo
    assert @model.entities.grep(Sketchup::Group).all? { |group| ZONES::ZONE_STORE.read(group).fetch("level_id").nil? }
    assert @model.redo
    assert @model.entities.grep(Sketchup::Group).all? { |group|
             ZONES::ZONE_STORE.read(group).fetch("level_id") == @level_id
           }
    rows.first.fetch("values")["name"] = "detached"
    refute_equal "detached", ZONES::ZONE_STORE.read(@model.entities.grep(Sketchup::Group).first).fetch("name")
  end

  def test_empty_selection_chooses_the_secondary_paint_tool_without_a_model_write
    @model.selection.clear
    before = @session.revision
    operations = @model.operations.length

    result = FACES::Selection.client(@session).classify("face_type", "Wall")

    assert_equal %w[completed none], result.values_at("status", "effect")
    assert FACES.classify_tool(@session).active?
    assert_equal({ "mode" => "set", "value" => "Wall" }, FACES.classify_tool(@session).palette.fetch("face_type"))
    assert_equal before, @session.revision
    assert_equal operations, @model.operations.length
  end

  def test_batch_checks_every_expected_value_before_composing_any_writes
    rows = query("ph_composer.zones.selection").dig("value", "zones")
    rows.last.fetch("values")["level"] = "stale"
    result = update(rows, "level", "L2", @session.revision)

    assert_equal %w[refused target.changed none], result.values_at("status", "code", "effect")
    assert_equal [nil, nil], @groups.map { |group| ZONES::ZONE_STORE.read(group).fetch("level_id") }
    assert_equal @operation_count, @model.operations.length
  end

  def test_duplicate_or_invalid_field_value_refuses_the_entire_batch
    rows = query("ph_composer.zones.selection").dig("value", "zones")
    duplicate = update([rows.first, rows.first], "level", "L2", @session.revision)
    invalid = update(rows, "ground_depth_mm", "bad", @session.revision)

    assert_equal %w[refused params.invalid none], duplicate.values_at("status", "code", "effect")
    assert_equal %w[refused validation.failed none], invalid.values_at("status", "code", "effect")
    assert_equal @operation_count, @model.operations.length
  end

  def test_mixed_locked_shared_and_ambiguous_selected_zone_sets_refuse
    select(@groups.first, @groups.last.entities.to_a.first)
    assert_equal "selection.invalid", query("ph_composer.zones.selection").fetch("code")
    select(*@groups)
    @groups.last.locked = true
    assert_equal "target.locked", query("ph_composer.zones.selection").fetch("code")
    @groups.last.locked = false
    duplicate = ZONES::ZONE_STORE.read(@groups.first)
    ZONES::ZONE_STORE.write(@groups.last, duplicate)
    assert_equal "target.ambiguous", query("ph_composer.zones.selection").fetch("code")

    ZONES::ZONE_STORE.write(@groups.last, duplicate.merge("id" => "zon_123456789abc"))
    definition = Sketchup::ComponentDefinition.new(Sketchup::Entities.new([@groups.first]))
    instances = [Sketchup::ComponentInstance.new(800, definition), Sketchup::ComponentInstance.new(900, definition)]
    instances.each { |instance| @model.entities << instance }
    treat_duplicates_as_existing(@model)
    @model.active_path = [instances.first]
    select(@groups.first)
    assert_equal "target.ambiguous", query("ph_composer.zones.selection").fetch("code")
    assert_equal @operation_count, @model.operations.length
  end

  def test_inputbox_cancel_writes_nothing_and_stale_revision_refuses
    client = ZONES::Selection.client(@session)
    assert_nil client.edit("level")
    assert_equal [["Level"], [""], ["L2|L3"], "Selected Zones"], UI.inputboxes.last
    assert_equal @operation_count, @model.operations.length
    UI.inputbox_result = ["L3"]
    read = query("ph_composer.zones.selection")
    @session.host_event(:transaction_committed)
    original_query = API.method(:query)
    stale_query = lambda do |**args|
      args.fetch(:name).end_with?("options.all") ? original_query.call(**args) : read
    end
    result = API.stub(:query, stale_query) { client.edit("level") }
    assert_equal "revision.stale", result.fetch("code")
    assert_equal @operation_count, @model.operations.length
  end

  def test_inputbox_captures_all_values_and_revision_before_dialog
    client = ZONES::Selection.client(@session)
    UI.inputbox_result = ["-250"]
    result = client.edit("ground_depth_mm")
    assert_equal "completed", result.fetch("status")
    assert_equal [-250.0, -250.0], @groups.map { |group| ZONES::ZONE_STORE.read(group).fetch("ground_depth_mm") }
    UI.inputbox_result = ["bad"]
    assert_equal "refused", client.edit("ground_depth_mm").fetch("status")
    assert_equal @operation_count + 1, @model.operations.length
  end

  def test_solve_client_passes_selected_occurrences_and_captured_revision
    read = query("ph_composer.zones.selection")
    invocation = nil
    API.stub(:invoke, lambda { |**args|
      invocation = args
      { "status" => "completed", "message" => "Solved.", "value" => { "pair_ids" => [], "already_paired" => 0 } }
    }) { ZONES::Selection.client(@session).solve }
    assert_equal "ph_composer.zones.solve_adjacency", invocation.fetch(:name)
    assert_equal read.dig("value", "zones").map { |row| row.fetch("reference") }, invocation.dig(:params, "zones")
    assert_equal read.fetch("revision"), invocation.dig(:request, "expected_revision")
  end

  def test_solve_from_the_menu_says_in_sketchup_what_changed
    solved = lambda do |pairs, affected, already = 0|
      outcome = { "status" => "completed", "message" => "Done: Solve Zone Adjacency.",
                  "value" => { "pair_ids" => pairs, "already_paired" => already }, "affected" => affected }
      API.stub(:invoke, ->(**_args) { outcome }) { ZONES::Selection.client(@session).solve }
      UI.notifications.last.message
    end
    retired = [{ "kind" => "face", "id" => "fac_1", "change" => "retired" }]

    assert_equal "Solve adjacencies: 2 Faces paired as Surface.", solved.call(%w[pair_1], [])
    assert_equal "Solve adjacencies: 4 Faces paired as Surface. 1 Face retired from out-of-date pairs.",
                 solved.call(%w[pair_1 pair_2], retired)
    assert_equal "Solve adjacencies: no Faces to pair. Nothing changed.", solved.call([], [])
    assert_equal "Solve adjacencies: nothing to change. 2 Faces already paired.",
                 solved.call(%w[pair_1], [], 1), "a second Solve must not claim it paired them"
    assert_equal "Solve adjacencies: 2 Faces paired as Surface. 2 Faces already paired.",
                 solved.call(%w[pair_1 pair_2], [], 1), "only the pair this Solve wrote counts as paired"
  end

  def test_solve_refused_from_the_menu_shows_the_reason_in_sketchup
    refused = { "status" => "refused", "message" => "The Model changed. Nothing was written." }
    API.stub(:invoke, ->(**_args) { refused }) { ZONES::Selection.client(@session).solve }

    assert_equal ["The Model changed. Nothing was written."], UI.notifications.map(&:message)
  end

  def test_a_solve_whose_selection_read_fails_shows_it_in_sketchup
    failed = { "status" => "failed", "message" => "The request could not be answered.",
               "detail" => { "incident" => "PHC-AAAAAA", "error_class" => "TypeError" } }
    API.stub(:query, ->(**_args) { failed }) { ZONES::Selection.client(@session).solve }

    assert_equal ["The request could not be answered. Error: TypeError. Incident PHC-AAAAAA."],
                 UI.notifications.map(&:message)
  end

  def test_a_solve_that_fails_from_the_menu_names_the_error_and_incident_in_sketchup
    failed = { "status" => "failed", "message" => "The change could not be completed.",
               "detail" => { "incident" => "PHC-7CDF84", "error_class" => "ArgumentError" } }
    notices = []
    PhComposer::Sessions.on_notice { |_session, message, tone| notices << [message, tone] }
    API.stub(:invoke, ->(**_args) { failed }) { ZONES::Selection.client(@session).solve }

    words = "The change could not be completed. Error: ArgumentError. Incident PHC-7CDF84."
    assert_equal [words], UI.notifications.map(&:message)
    assert_equal [words, :error], notices.last
  end

  def test_selected_faces_immediately_classify_one_attribute_without_starting_tool
    inside_zone
    selected = @groups.first.entities.to_a.first(2)
    select(*selected)
    result = FACES::Selection.client(@session).classify("face_type", "Wall")

    assert_equal "completed", result.fetch("status")
    assert_equal %w[Wall Wall], selected.map { |face| FACES::FACE_STORE.read(face).fetch("face_type") }
    assert_nil FACES::FACE_STORE.read(@groups.first.entities.to_a.last)
    refute FACES.classify_tool(@session).active?
    assert_nil @model.active_tool
    assert_equal @operation_count + 1, @model.operations.length
    assert @model.undo
    assert @model.entities.grep(Sketchup::Group).first.entities.all? { |face| FACES::FACE_STORE.read(face).nil? }
    assert @model.redo
    assert_equal 2, @model.entities.grep(Sketchup::Group).first.entities.count { |face| FACES::FACE_STORE.read(face) }
  end

  def test_face_selection_rejects_over_limit_mixed_root_locked_and_shared
    inside_zone
    faces = 251.times.map { |index| Sketchup::Face.new(1000 + index) }
    faces.each { |face| @groups.first.entities << face }
    select(*faces)
    assert_equal "gesture.too_large", query("ph_composer.zones.faces.selection").fetch("code")
    edge = Sketchup::Edge.new(2000, Geom::Point3d.new(0, 0, 0), Geom::Point3d.new(1, 0, 0))
    @groups.first.entities << edge
    select(faces.first, edge)
    assert_equal "selection.invalid", query("ph_composer.zones.faces.selection").fetch("code")
    @model.active_path = nil
    select(@groups.first.entities.to_a.first)
    assert_equal "target.wrong_zone", query("ph_composer.zones.faces.selection").fetch("code")
    inside_zone
    @groups.first.locked = true
    assert_equal "target.locked", query("ph_composer.zones.faces.selection").fetch("code")
    assert_equal @operation_count, @model.operations.length
  end

  def test_dynamic_attached_menu_uses_current_records_and_exit_only_while_active
    inside_zone
    select(@groups.first.entities.to_a.first)
    PhComposer::Commands.install
    menus = context_menus
    labels = labels(menus.fetch(FACES::ClassifyMenu::BOUNDARY_MENU))
    assert_includes labels, "New attached zone…"
    refute labels.any? { |label| label.include?("Keep") || label == FACES::ClassifyMenu::OFF }
    created = invoke("#{FACES::AttachedZone::KIND_ID}.save", { "values" => { "name" => "Garage", "kind" => "garage" } })
    assert_equal "completed", created.fetch("status")
    menu = context_menus.fetch(FACES::ClassifyMenu::BOUNDARY_MENU)
    entry = menu.entries.find { |row| row.is_a?(Array) && row.first == "Attached zone: Garage" }
    assert entry
    entry.last.call
    face = FACES::FACE_STORE.read(@groups.first.entities.to_a.first)
    assert_equal created.dig("value", "id"), face.fetch("attached_zone_id")
    assert_equal "AttachedZone", face.fetch("boundary_condition")
    FACES.classify_tool(@session).start
    select
    assert_includes labels(context_menus.fetch(PhComposer::EXTENSION_NAME)), FACES::ClassifyMenu::OFF
    FACES.classify_tool(@session).stop
    refute context_menus.key?(PhComposer::EXTENSION_NAME)
  end

  def test_the_right_click_menu_is_one_extension_submenu_with_one_list_per_attribute
    inside_zone
    select(@groups.first.entities.to_a.first)
    PhComposer::Commands.install

    built = UI.build_context_menu
    assert_equal [PhComposer::EXTENSION_NAME], built.entries.grep(UI::Menu).map(&:name)
    home = built.entries.grep(UI::Menu).first
    assert_includes home.entries.grep(UI::Menu).map(&:name), FACES::ClassifyMenu::TYPE_MENU
    assert_includes home.entries.grep(UI::Menu).map(&:name), FACES::ClassifyMenu::BOUNDARY_MENU
    assert_includes home.entries.grep(UI::Menu).map(&:name), FACES::ClassifyMenu::ASSEMBLY_MENU
    refute_includes home.entries.grep(UI::Menu).map(&:name), PhComposer::EXTENSION_NAME
  end

  def test_the_extensions_menu_holds_the_extensions_own_items_directly
    PhComposer::Commands.install
    extension = UI.menu("Extensions").entries.grep(UI::Menu).find { |menu| menu.name == PhComposer::EXTENSION_NAME }

    assert_includes labels(extension), "Make Zone"
    refute_includes extension.entries.grep(UI::Menu).map(&:name), PhComposer::EXTENSION_NAME
  end

  def test_each_list_marks_the_value_every_selected_face_shares_and_marks_nothing_when_mixed
    inside_zone
    faces = @groups.first.entities.to_a.first(2)
    select(*faces)
    FACES::Selection.client(@session).classify("face_type", "Wall")
    FACES::Selection.client(@session).classify("boundary_condition", "Outdoors")
    menus = context_menus
    assert_equal MF_CHECKED, mark(menus.fetch(FACES::ClassifyMenu::TYPE_MENU), "Wall")
    assert_equal MF_UNCHECKED, mark(menus.fetch(FACES::ClassifyMenu::TYPE_MENU), "Floor")
    assert_equal MF_CHECKED, mark(menus.fetch(FACES::ClassifyMenu::BOUNDARY_MENU), "Outdoors")

    select(faces.first)
    FACES::Selection.client(@session).classify("boundary_condition", "Ground")
    select(*faces)
    menus = context_menus
    assert_equal MF_CHECKED, mark(menus.fetch(FACES::ClassifyMenu::TYPE_MENU), "Wall"), "both Faces are still Walls"
    assert_equal MF_UNCHECKED, mark(menus.fetch(FACES::ClassifyMenu::BOUNDARY_MENU), "Outdoors")
    assert_equal MF_UNCHECKED, mark(menus.fetch(FACES::ClassifyMenu::BOUNDARY_MENU), "Ground")
  end

  def test_assignment_handoff_is_detached_revision_guarded_and_token_scoped
    inside_zone
    select(*@groups.first.entities.to_a.first(2))
    read = query("ph_composer.zones.faces.selection")
    params = { "faces" => read.dig("value", "faces"), "revision" => read.fetch("revision") }
    result = API.view(:context => @context, :name => "ph_composer.zones.faces.open_attached_assignment",
                      :params => params)
    assert_equal "completed", result.fetch("status")
    token = result.dig("value", "token")
    params.fetch("faces").first["entity_path"] = [999]
    assert_equal 2, query("ph_composer.zones.faces.attached_assignment").dig("value", "faces").length
    close = ->(value) {
      API.view(:context => @context, :name => "ph_composer.zones.faces.close_attached_assignment",
               :params => { "token" => value })
    }
    assert_equal token, close.call("wrong").dig("value", "token")
    assert_nil close.call(token).dig("value", "token")
    stale = API.view(:context => @context, :name => "ph_composer.zones.faces.open_attached_assignment",
                     :params => { "faces" => read.dig("value", "faces"), "revision" => -1 })
    assert_equal "revision.stale", stale.fetch("code")
    assert_equal @operation_count, @model.operations.length
  end

  private

  def make_zone(id)
    faces = 3.times.map do |index|
      Sketchup::Face.new(id + index + 1, {},
                         :points => [Geom::Point3d.new(0, 0, index),
                                     Geom::Point3d.new(2, 0, index), Geom::Point3d.new(2, 2, index)])
    end
    group = Sketchup::Group.new(id, Sketchup::Entities.new(faces))
    @model.entities << group
    result = invoke("ph_composer.zones.make", { "parent_path" => [], "entity_ids" => [id] })
    assert_equal "completed", result.fetch("status")
    group
  end

  def query(name)
    API.query(:context => @context, :name => name)
  end

  def invoke(name, params, revision = @session.revision)
    @sequence += 1
    API.invoke(:context => @context, :name => name, :params => params,
               :request => { "sequence" => @sequence, "expected_revision" => revision })
  end

  def update(rows, field, value, revision)
    invoke("ph_composer.zones.update_field", { "field" => field, "value" => value,
                                               "targets" => rows.map do |row|
                                                              { "reference" => row.fetch("reference"),
                                                                "expected_values" => row.fetch("values") }
                                                            end },
           revision)
  end

  def select(*entities)
    @model.selection.clear
    entities.each { |entity| @model.selection.add(entity) }
  end

  def inside_zone
    @model.active_path = [@groups.first]
  end

  def context_menus
    PhComposer::Commands.install_feature_menus(UI::Menu.new("Context"), :contextual => true)
  end

  def labels(menu)
    menu.entries.select { |entry| entry.is_a?(Array) }.map(&:first)
  end

  def mark(menu, label)
    index = menu.entries.index { |entry| entry.is_a?(Array) && entry.first == label }
    menu.validation_procs.fetch(index).call
  end
end
