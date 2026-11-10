# frozen_string_literal: true

require_relative "test_helper"
require_relative "support/assembly_record_fixtures"
require "tmpdir"

class LibraryExportTest < PhComposerTestCase
  include AssemblyRecordFixtures

  API = PhComposer::API
  LIBRARY = PhComposer::Library
  MATERIAL_KIND = "ph_composer.assemblies.material"
  NAME = "ph_composer.library.export_file"

  def setup
    super
    @directory = Dir.mktmpdir("library-export")
    @path = File.join(@directory, "synthetic.json")
    @session = PhComposer::Sessions.for(Sketchup.active_model)
    @context = API.connect(:session_id => @session.id, :capabilities => %w[read export model_write view])
    @records = fixture_materials.values.first(2)
    @records.each { |row| Assemblies::Materials::Schema::KIND.store.write(Sketchup.active_model, row) }
  end

  def teardown
    FileUtils.rm_rf(@directory)
    super
  end

  def preview(params = {})
    API.query(:context => @context, :name => "ph_composer.library.export_preview", :params => params)
  end

  # The export as a native client runs it, once the user has chosen @path and, unless `replace` is
  # false, agreed to replace it. Positional, because the params' string keys would read as keywords.
  def export(params = {}, replace = true)
    approval = PhComposer::NativeApproval::Granted.new(:path => @path, :replace => replace)
    PhComposer::Dispatch.new.file_export(@context, NAME, params, :approval => approval)
  end

  def test_allowlist_projection_metadata_omissions_and_origin_privacy
    row = @records.first
    row["user_data"] = { "secret" => "PRIVATE SECRET" }
    row["extension_data"] =
      { "outside.vendor" => { "schema_version" => 9, "payload" => { "key" => "PRIVATE SECRET" } } }
    row["source"] = { "kind" => "library", "provider_kind" => "ph_composer.library.file",
                      "library_id" => "public.library", "record_kind" => "materials", "record_id" => "public.row",
                      "copied_at" => "2026-01-01T00:00:00Z", "fingerprint_version" => 1,
                      "fingerprint" => "a" * 64, "snapshot" => row.slice(*Assemblies::MaterialsLibrary::FIELDS) }
    Assemblies::Materials::Schema::KIND.store.write(Sketchup.active_model, row)
    read = preview
    assert_equal "completed", read["status"], read.inspect
    assert_equal [%w[frames Frame 0], %w[glazings Glazing 0], %w[materials Material 2],
                  ["psi_install_types", "Psi-Install Type", "0"]],
                 read.dig("value", "kinds").map { |row|
                   row.values_at("kind", "record_kind_label", "count").map(&:to_s)
                 }
    # The recorded origin carries the source attribution, so `source` is not reported omitted.
    assert_equal %w[extension_data user_data], read.dig("value", "omissions").first.fetch("fields")
    before = [@session.revision, Sketchup.active_model.operations.length, Sketchup.active_model.modified?]
    result = export
    assert_equal "completed", result["status"], result.inspect
    json = File.read(@path)
    refute_includes json, "PRIVATE SECRET"
    refute_includes JSON.generate(result), @directory
    document = JSON.parse(json)
    assert_equal %w[format schema_version library exported_at kind_schema_versions kinds record_origins], document.keys
    assert_equal @records.map { |item| item["id"] }.sort, document.dig("kinds", "materials").map { |item|
                                                            item["id"]
                                                          }.sort
    assert_equal "ph_composer.library.file", document.dig("record_origins", "materials", row["id"], "label")
    refute document.dig("kinds", "materials").first.key?("schema_version")
    assert_equal before, [@session.revision, Sketchup.active_model.operations.length, Sketchup.active_model.modified?]
  end

  def test_selected_scope_new_uuid_and_update_existing_identity
    selected = { "scope" => "selected", "records" => [{ "record_kind" => MATERIAL_KIND, "id" => @records.last["id"] }] }
    result = export(selected)
    assert_equal "completed", result["status"], result.inspect
    first = JSON.parse(File.read(@path))
    assert_match(/\A[0-9a-f-]{36}\z/, first.dig("library", "id"))
    assert_equal [@records.last["id"]], first.dig("kinds", "materials").map { |row| row["id"] }
    updated = export(selected.merge("identity" => "update"))
    assert_equal first.dig("library", "id"), updated.dig("value", "library_id")
    fresh = export(selected)
    refute_equal first.dig("library", "id"), fresh.dig("value", "library_id")
    assert_equal "params.invalid", export("scope" => "selected")["code"]
    assert_equal "params.invalid", export(selected.merge("scope" => "all"))["code"]
  end

  # The staged bytes are checked as bytes: text outside ASCII in a name or a note is written, not refused.
  def test_non_ascii_text_is_written_and_read_back
    row = @records.first.merge("name" => "W\u00e4rme \u6f22\u5b57 \u{1F642}", "notes" => "\u00e9" * 10)
    Assemblies::Materials::Schema::KIND.store.write(Sketchup.active_model, row)
    result = export("library_name" => "Biblioth\u00e8que")
    assert_equal "completed", result["status"], result.inspect
    written = JSON.parse(File.read(@path, :encoding => "UTF-8"))
    assert_equal "Biblioth\u00e8que", written.dig("library", "name")
    assert_includes written.dig("kinds", "materials").map { |material| material["name"] }, row["name"]
  end

  def test_unapproved_replacement_and_stale_revision_preserve_destination
    File.write(@path, "original bytes")
    assert_equal "export.replace_required", export({}, false)["code"]
    stale = export("expected_revision" => @session.revision + 1)
    assert_equal "revision.stale", stale["code"]
    assert_equal "original bytes", File.read(@path)
    assert_empty Dir.children(@directory) - ["synthetic.json"]
  end

  def test_destination_guard_and_writer_failure_preserve_prior_bytes
    File.write(@path, "original")
    writer = LIBRARY::FileWriter.new(@path)
    File.write(@path, "external change")
    error = assert_raises(LIBRARY::Error) { writer.write("replacement") }
    assert_equal "library.destination_changed", error.code
    assert_equal "external change", File.read(@path)
    File.stub(:rename, ->(*) { raise IOError, "PRIVATE PATH SECRET" }) do
      error = assert_raises(LIBRARY::Error) { LIBRARY::FileWriter.new(@path).write("replacement") }
      assert_equal "library.export_write_failed", error.code
      refute_includes error.message, "PRIVATE"
    end
    assert_equal "external change", File.read(@path)
    assert_equal ["synthetic.json"], Dir.children(@directory)
  end

  def test_stage_collision_is_not_deleted_and_staged_destination_change_is_refused
    File.write(@path, "original")
    stage = File.join(@directory, ".ph-composer-library-occupied.tmp")
    File.write(stage, "unrelated stage")
    SecureRandom.stub(:hex, "occupied") do
      assert_raises(LIBRARY::Error) { LIBRARY::FileWriter.new(@path).write("replacement") }
    end
    assert_equal "unrelated stage", File.read(stage)
    assert_equal "original", File.read(@path)
    writer = LIBRARY::FileWriter.new(@path)
    error = assert_raises(LIBRARY::Error) do
      writer.write("replacement") { File.write(@path, "external change") }
    end
    assert_equal "library.destination_changed", error.code
    assert_equal "external change", File.read(@path)
    assert_equal %w[.ph-composer-library-occupied.tmp synthetic.json], Dir.children(@directory).sort
  end

  def test_unsupported_definitions_and_unsafe_origins_are_disclosed_without_payloads
    assembly = fixture_assembly(reference_layers)
    Assemblies::Assembly::Schema::KIND.store.write(Sketchup.active_model, assembly)
    row = @records.first
    row["source"] = { "kind" => "library", "provider_kind" => "ph_composer.library.file",
                      "library_id" => "/PRIVATE SECRET/path", "record_kind" => "materials", "record_id" => "public.row",
                      "copied_at" => "2026-01-01T00:00:00Z", "fingerprint_version" => 1, "fingerprint" => "a" * 64,
                      "snapshot" => row.slice(*Assemblies::MaterialsLibrary::FIELDS) }
    row["user_data"] = { "/PRIVATE SECRET/path" => "SECRET VALUE" }
    Assemblies::Materials::Schema::KIND.store.write(Sketchup.active_model, row)
    result = export
    assert_equal "completed", result["status"], result.inspect
    assert_includes result.dig("value", "omissions").map { |item| item["reason"] }, "unsupported_kind"
    assert_includes result.dig("value", "omissions").map { |item| item["reason"] }, "origin_identity_unavailable"
    refute_includes JSON.generate(result), "PRIVATE"
    refute_includes File.read(@path), "PRIVATE"
    refute JSON.parse(File.read(@path)).key?("record_origins")
  end

  def test_preview_names_unsupported_kind_and_omitted_fields_without_values
    assembly = fixture_assembly(reference_layers)
    Assemblies::Assembly::Schema::KIND.store.write(Sketchup.active_model, assembly)
    material = @records.first.merge("user_data" => { "firm.private" => "PRIVATE PAYLOAD" })
    Assemblies::Materials::Schema::KIND.store.write(Sketchup.active_model, material)
    omissions = preview.dig("value", "omissions")
    assert_includes omissions.map { |row| row.values_at("record_kind", "reason") },
                    ["ph_composer.assemblies.assembly", "unsupported_kind"]
    assert_includes omissions.map { |row| row.values_at("record_kind", "fields") },
                    [MATERIAL_KIND, %w[source user_data]]
    labels = omissions.to_h { |row| [row.fetch("record_kind"), row.fetch("record_kind_label")] }
    assert_equal PhComposer::Registry.current.record_kinds.fetch("ph_composer.assemblies.assembly").label,
                 labels.fetch("ph_composer.assemblies.assembly")
    assert_equal "Material", labels.fetch(MATERIAL_KIND)
    refute_includes JSON.generate(omissions), "PRIVATE PAYLOAD"
  end

  def test_update_admits_missing_optional_fields_but_refuses_invalid_rows_and_versions
    export
    document = JSON.parse(File.read(@path))
    document["library"]["id"] = "historical.accepted.id"
    document.dig("kinds", "materials").first.delete("notes")
    File.write(@path, JSON.generate(document))
    assert_equal "historical.accepted.id", export("identity" => "update").dig("value", "library_id")
    document.dig("kinds", "materials").first["conductivity_w_mk"] = "invalid"
    bytes = JSON.generate(document)
    File.write(@path, bytes)
    assert_equal "library.update_destination_invalid", export("identity" => "update")["code"]
    assert_equal bytes, File.read(@path)
    document["kind_schema_versions"]["materials"] = 99
    bytes = JSON.generate(document)
    File.write(@path, bytes)
    assert_equal "library.update_destination_invalid", export("identity" => "update")["code"]
    assert_equal bytes, File.read(@path)
  end

  def test_update_refuses_semantically_invalid_destination_without_replacing_it
    export
    document = JSON.parse(File.read(@path))
    document.dig("kinds", "materials").first["color"] = "unreadable color"
    bytes = JSON.generate(document)
    File.write(@path, bytes)
    assert_equal "library.update_destination_invalid", export("identity" => "update")["code"]
    assert_equal bytes, File.read(@path)
  end

  def test_reverse_adapter_identity_or_extra_payload_refuses_without_writing
    adapter = PhComposer::Registry.current.library_kinds.values.first.adapter
    original = adapter.reverse
    detached_callback = Assemblies::MaterialsLibrary.method(:reverse)
    replacement = lambda do |input|
      detached_callback.call(input).merge("id" => "foreign", "transport" => "/PRIVATE SECRET/path")
    end
    original.stub(:call, replacement) do
      result = export
      assert_equal "library.adapter_invalid", result["code"]
      refute_includes JSON.generate(result), "PRIVATE"
    end
    refute File.exist?(@path)
  end

  def test_registered_reverse_adapter_cannot_change_schema_valid_authored_semantics
    kind = PhComposer::Records::RecordKind.new(:id => "test.export.material", :label => "Probe Material",
                                               :schema_version => 1, :id_prefix => "pmt",
                                               :fields => Assemblies::Materials::Schema::KIND.fields)
    row = @records.first.merge("id" => "pmt_AAAAAAAAAAAA")
    kind.store.write(Sketchup.active_model, row)
    adapter = PhComposer::Registry.current.library_kinds.values.first.adapter.dup
    adapter.wire_kind = "probe_materials"
    normal_reverse = adapter.reverse
    adapter.reverse = ->(values) { normal_reverse.call(values).merge("conductivity_w_mk" => 0.123) }
    feature = Module.new do
      define_singleton_method(:name) { "ExportAdapterProbe" }
      define_singleton_method(:install) do |registry|
        scope = registry.feature("test.export", :contract_version => 1)
        scope.record_kind(kind)
        scope.library_kind("test.export.library_material", :contract_version => 1,
                                                           :record_kind => kind.id, :adapter => adapter)
      end
    end
    PhComposer::Registry.install([feature])
    params = { "scope" => "selected", "kinds" => ["probe_materials"],
               "records" => [{ "record_kind" => kind.id, "id" => row.fetch("id") }] }
    revision = @session.revision
    result = export(params)
    assert_equal "library.adapter_invalid", result["code"], result.inspect
    assert_equal "none", result["effect"]
    assert_equal row, kind.store.read(Sketchup.active_model, row.fetch("id"))
    assert_equal revision, @session.revision
    refute File.exist?(@path)
  end

  def test_adapter_errors_and_unavailable_selected_ids_do_not_disclose_private_strings
    adapter = PhComposer::Registry.current.library_kinds.values.first.adapter
    failure = ->(*) { raise PhComposer::CodedError.new("outside.bad", "/PRIVATE SECRET/path") }
    adapter.map.stub(:call, failure) do
      result = export
      assert_equal "library.adapter_invalid", result["code"]
      refute_includes JSON.generate(result), "PRIVATE"
    end
    params = { "scope" => "selected", "records" => [
      { "record_kind" => MATERIAL_KIND, "id" => "/PRIVATE SECRET/path" }
    ] }
    result = preview(params)
    assert_equal "target.not_found", result["code"]
    refute_includes JSON.generate(result), "PRIVATE"
    refute File.exist?(@path)
  end

  # A scripted caller cannot answer a save dialog, so it is refused before anything runs and no dialog
  # opens; the panel's native path asks first, and a dismissed dialog writes nothing. On macOS the Save
  # sheet's own question is the consent to replace, so declining it is dismissing the sheet.
  def test_a_scripted_export_is_refused_without_a_dialog_and_a_native_cancel_writes_nothing
    File.write(@path, "original")
    UI.stub(:savepanel, ->(*) { flunk "A scripted export must not open a dialog." }) do
      UI.stub(:messagebox, ->(*) { flunk "A scripted export must not ask for consent." }) do
        refused = API.export_file(:context => @context, :name => NAME)
        assert_equal %w[refused access.user_required none], refused.values_at("status", "code", "effect")
      end
    end
    assert_equal({ "kind" => "save_file", "title" => "Export Library File", "default_name" => "model-library.json" },
                 API.describe(:name => NAME).fetch("approval"))
    UI.stub(:savepanel, nil) do
      cancelled = PhComposer::NativeApproval.file_export(@context, NAME, {})
      assert_equal %w[cancelled request.cancelled none], cancelled.values_at("status", "code", "effect")
    end
    assert_equal "original", File.read(@path)
    UI.stub(:savepanel, @path) do
      UI.stub(:messagebox, ->(*) { flunk "The Save sheet already asked." }) do
        assert_equal "completed", PhComposer::NativeApproval.file_export(@context, NAME, {})["status"]
      end
    end
    refute_equal "original", File.read(@path)
  end

  def test_export_file_provider_and_copy_into_fresh_model_round_trip
    result = export
    assert_equal "completed", result["status"], result.inspect
    adapter = PhComposer::Registry.current.library_kinds.values.first.adapter
    provider = LIBRARY::FileProvider.new(:id => "exported", :label => "Exported", :path => @path,
                                         :kinds => ["materials"], :adapters => ->(_) { adapter })
    batch = provider.list("materials")
    assert_empty batch.warnings
    assert_empty batch.unavailable
    assert_equal 2, batch.rows.length
    LIBRARY::Setup.add_file(:id => "exported", :label => "Exported", :path => @path)
    Sketchup.active_model = Sketchup::Model.new
    session = PhComposer::Sessions.for(Sketchup.active_model)
    context = API.connect(:session_id => session.id, :capabilities => %w[read model_write setup])
    loaded = API.setup(:context => context, :name => "ph_composer.library.load",
                       :params => { "provider_id" => "exported", "kind" => "materials" })
    assert_equal "completed", loaded["status"], loaded.inspect
    row = batch.rows.first
    copied = API.invoke(:context => context, :name => "ph_composer.library.copy", :params => {
      "provider_id" => "exported", "kind" => "materials", "generation" => loaded.dig("value", "generation"),
      "library_id" => row["library_id"], "record_id" => row["record_id"], "choice" => "create"
    }, :request => { "sequence" => 1, "expected_revision" => session.revision })
    assert_equal "completed", copied["status"], copied.inspect
    id = copied.dig("value", "local_id")
    refute_equal row["record_id"], id
    stored = Assemblies::Materials::Schema::KIND.store.read(Sketchup.active_model, id)
    assert_equal adapter.map.call(row["snapshot"]), adapter.map.call(stored)
    assert_equal row["record_id"], stored.dig("source", "record_id")
  end
end
