# frozen_string_literal: true

require_relative "test_helper"

class ZoneSplitIdentityMenuTest < PhComposerTestCase
  API = PhComposer::API
  MENU = PhComposer::Zones::SplitIdentityMenu

  def setup
    super
    @model = Sketchup.active_model
    @first = Sketchup::Face.new(101)
    @selected = Sketchup::Face.new(102)
    @zone = Sketchup::Group.new(100, Sketchup::Entities.new([@first, @selected]))
    @model.entities << @zone
    @model.active_path = [@zone]
    @model.selection.add(@selected)
    @session = PhComposer::Sessions.for(@model)
    @client = MENU::Client.new(@session)
    @previews = []
    @invocations = []
    @rows = [row(101), row(102)]
  end

  def test_offered_on_one_selected_face_but_not_on_a_floor_segment_face_inside_a_space
    assert MENU.available?(@session)

    segment = Sketchup::Face.new(401)
    PhComposer::Spaces::FLOOR_SEGMENT_STORE.write(segment, "id" => "fsg_AAAAAAAAAAAA")
    volume = Sketchup::Group.new(400, Sketchup::Entities.new([segment]))
    PhComposer::Spaces::VOLUME_STORE.write(volume, "id" => "vol_AAAAAAAAAAAA")
    @model.entities << volume
    @model.active_path = [volume]
    @model.selection.clear
    @model.selection.add(segment)
    refute MENU.available?(@session)
  end

  def test_missing_proof_uses_selected_piece_and_preserves_preview_revision
    calls = 0
    previewer = lambda do |**args|
      @previews << PhComposer::DeepCopy.call(args.fetch(:params))
      calls += 1
      calls == 1 ? { "status" => "refused", "code" => "identity.choice_required" } : completed("user_choice")
    end

    run_with(previewer)

    refute @previews.first.key?("retaining_entity_path")
    assert_equal [102], @previews.last.fetch("retaining_entity_path")
    assert_equal [102], @invocations.first.dig(:params, "retaining_entity_path")
    assert_equal 37, @invocations.first.dig(:request, "expected_revision")
    assert_equal "sha256:preview", @invocations.first.dig(:request, "proposal_digest")
    assert UI.messages.any? { |message| message.include?("selected Face will keep") }
  end

  def test_stored_endpoint_proof_is_not_overridden_by_selected_piece
    run_with(lambda do |**args|
      @previews << args.fetch(:params)
      completed("stored_endpoint")
    end)

    assert_equal 1, @previews.length
    refute @invocations.first.fetch(:params).key?("retaining_entity_path")
    assert UI.messages.any? { |message| message.include?("stored original path") }
    assert UI.messages.any? { |message| message.include?("cleared on 3 Face") }
  end

  def test_cancelling_review_never_invokes
    UI.messagebox_result = IDNO

    run_with(->(**_args) { completed("user_choice") })

    assert_empty @invocations
  end

  def test_refused_preview_is_shown_without_invoke_or_confirmation
    run_with(->(**_args) {
               { "status" => "refused", "code" => "copy.rule_missing",
                 "message" => "The unavailable payload prevents safe repair." }
             })

    assert_empty @invocations
    assert_equal ["The unavailable payload prevents safe repair."], UI.messages
  end

  def test_model_switch_during_confirmation_never_invokes_old_model
    responses = 0
    dialog = lambda do |_message, *_flags|
      responses += 1
      Sketchup.active_model = Sketchup::Model.new if responses == 1
      IDYES
    end
    UI.stub(:messagebox, dialog) { run_with(->(**_args) { completed("user_choice") }) }

    assert_empty @invocations
    assert_equal 2, responses
  end

  def test_scope_includes_the_reciprocal_zone_and_review_names_it
    @rows.each { |face| face["values"]["adjacency"] = { "counterpart" => reference(201, 200, "zon_000000000002") } }
    @rows << row(201, 200, "zon_000000000002", "East")

    run_with(->(**_args) { completed("stored_endpoint") })

    assert_equal [[100], [200]], @invocations.first.dig(:params, "zones").map { |zone| zone.fetch("zone_path") }
    assert UI.messages.any? { |message| message.include?("West, East") }
  end

  def test_selection_is_matched_by_complete_occurrence_path
    @model.active_path = nil

    run_with(->(**_args) { flunk "A Face outside the current edit context must not preview." })

    assert_empty @invocations
    assert UI.messages.any? { |message| message.include?("no recorded Zone identity") }
  end

  # The selected Face and every copy of its identity may be anywhere in the Model, so the menu reads
  # the complete Faces projection rather than one page of the paged list.
  def test_the_menu_reads_every_face_not_one_page
    names = []
    queried = lambda do |**args|
      names << args.fetch(:name)
      { "status" => "completed", "revision" => 0, "value" => { "faces" => @rows } }
    end
    API.stub(:query, queried) { API.stub(:preview, ->(**_args) { completed("user_choice") }) { @client.run } }

    assert_equal ["ph_composer.zones.faces.all"], names.uniq
  end

  def test_query_failure_is_reported_before_preview
    failed = { "status" => "refused", "message" => "The Model is closed." }
    API.stub(:query, failed) do
      API.stub(:preview, ->(**_args) { flunk "Must not preview after a failed read." }) { @client.run }
    end

    assert_equal ["The Model is closed."], UI.messages
  end

  private

  def run_with(previewer)
    queried = { "status" => "completed", "revision" => 0, "value" => { "faces" => @rows } }
    invoke = lambda do |**args|
      @invocations << args
      { "status" => "completed", "message" => "Done." }
    end
    API.stub(:query, queried) do
      API.stub(:preview, previewer) do
        API.stub(:invoke, invoke) { @client.run }
      end
    end
  end

  def reference(id, zone_id = 100, assigned_zone = "zon_000000000001")
    { "zone_id" => assigned_zone, "zone_path" => [zone_id], "entity_path" => [id],
      "entity_id" => "fac_000000000001" }
  end

  def row(id, zone_id = 100, assigned_zone = "zon_000000000001", name = "West")
    { "reference" => reference(id, zone_id, assigned_zone), "zone_name" => name, "values" => {} }
  end

  def completed(basis)
    { "status" => "completed", "code" => "ok", "revision" => 37, "proposal_digest" => "sha256:preview",
      "value" => { "face_id" => "fac_000000000001", "retention_basis" => basis,
                   "pieces" => [{ "after" => reference(101) },
                                { "after" => reference(102).merge("entity_id" => "fac_000000000009") }],
                   "retired" => [reference(101), reference(102), reference(201)] } }
  end
end
