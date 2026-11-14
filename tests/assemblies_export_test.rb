# frozen_string_literal: true

require_relative "test_helper"

class AssembliesExportTest < PhComposerTestCase
  ROOT = File.join(TESTS_ROOT, "fixtures", "assemblies")
  SECTION = "ph_composer.assemblies.export.constructions"
  ASSEMBLY = "ph_composer.assemblies.assembly"
  Assemblies = PhComposer::Assemblies

  def setup
    super
    @model = Sketchup.active_model
    @fixture = JSON.parse(File.read(File.join(ROOT, "authoring.json")))
    @fixture.fetch("materials").each { |row| Assemblies::Materials::Schema::KIND.store.write(@model, row) }
    @fixture.fetch("assemblies").each { |row| Assemblies::Assembly::Schema::KIND.store.write(@model, row) }
    session = PhComposer::Sessions.for(@model)
    @context = PhComposer::API.connect(:session_id => session.id)
  end

  # Assemblies pass their user_data through to the Construction; Materials still leave theirs out.
  def test_shared_extraction_contract_contains_only_declared_fields_and_passes_assembly_user_data
    expected = JSON.parse(File.read(File.join(ROOT, "extraction.json")))
    extracted = PhComposer::Export::Collection.build(@model, :run_id => expected.fetch("run_id"),
                                                             :contributors => [SECTION])
    assert_equal expected, extracted.document
    assert(extracted.findings.all? { |finding| finding.fetch("code") == "export.metadata_omitted" })
    assert_operator extracted.findings.length, :>=, 1
    wire = JSON.generate(extracted.document)
    %w[air_barrier photo_collections ventilated_cladding exterior_condition notes source].each do |key|
      refute_includes wire, "\"#{key}\""
    end
    materials = extracted.document.dig("sections", SECTION, "records").flat_map { |row| row.fetch("materials") }
    assert(materials.none? { |row| row.key?("user_data") })
  end

  # A Layer's map leaves with its own material and a Layer-Segment's with its cell when the Layer is divided
  # (more than one Layer-Segment, or a steel stud spacing). A membrane Layer and an undivided Layer's
  # Layer-Segment have no material of their own: each map stays local with one finding.
  def test_layer_and_divided_segment_maps_leave_and_the_rest_stay_local_with_one_finding_each
    note = { "firm" => { "check" => "ok" } }
    assemblies = @fixture.fetch("assemblies").to_h { |row| [row.fetch("id"), row] }
    single = assemblies.fetch("asm_Single000001")
    single["layers"][0]["user_data"] = note
    single["layers"][0]["segments"][0]["user_data"] = note
    assemblies.fetch("asm_Mixed0000001")["layers"][0]["segments"][1]["user_data"] = note
    assemblies.fetch("asm_Membrane0001")["layers"][1]["user_data"] = note
    studded = assemblies.fetch("asm_Default00001")["layers"][0]
    studded["segments"][0].merge!("steel_stud_spacing_mm" => 600.0, "user_data" => note)
    assemblies.each_value { |row| Assemblies::Assembly::Schema::KIND.store.write(@model, row) }

    extracted = PhComposer::Export::Collection.build(@model, :run_id => "parts", :contributors => [SECTION])
    rows = extracted.document.dig("sections", SECTION, "records").to_h { |row| [row.fetch("id"), row] }
    layer = rows.fetch("asm_Single000001").fetch("layers").first
    assert_equal note, layer.fetch("user_data")
    refute layer.fetch("segments").first.key?("user_data")
    assert_equal [nil, note], rows.fetch("asm_Mixed0000001").fetch("layers").first.fetch("segments")
                                  .map { |segment| segment["user_data"] }
    refute rows.fetch("asm_Membrane0001").fetch("layers")[1].key?("user_data")
    assert_equal note, rows.fetch("asm_Default00001").dig("layers", 0, "segments", 0, "user_data")
    findings = extracted.findings.select { |row| row.fetch("code") == "export.metadata_omitted" }
    omitted = findings.map { |row| row.fetch("object_id") }
    assert_equal 1, omitted.count("seg_000000000010")
    assert_equal 1, omitted.count("lyr_000000000007")
    assert_empty omitted & %w[lyr_000000000001 seg_000000000031 seg_000000000100]
    # Each part's finding names its Assembly and id path, the reference records.update_metadata takes.
    layer = single.dig("layers", 0)
    assert_equal({ "kind" => ASSEMBLY, "id" => "asm_Single000001",
                   "part_ids" => [layer.fetch("id"), "seg_000000000010"] },
                 findings.find { |row| row.fetch("object_id") == "seg_000000000010" }.fetch("reference"))
    assert_equal({ "kind" => ASSEMBLY, "id" => "asm_Membrane0001", "part_ids" => ["lyr_000000000007"] },
                 findings.find { |row| row.fetch("object_id") == "lyr_000000000007" }.fetch("reference"))
  end

  # A membrane Layer becomes no material even with a steel stud spacing, so its one Layer-Segment's map stays
  # in the Model with a finding, and a reserved key in it blocks neither the extraction nor the preflight.
  def test_a_membrane_segment_with_a_stud_spacing_keeps_its_map_local
    assembly = @fixture.fetch("assemblies").find { |row| row.fetch("id") == "asm_Membrane0001" }
    layer = assembly.dig("layers", 1)
    layer.dig("segments", 0).merge!("steel_stud_spacing_mm" => 600.0, "user_data" => { "ph_composer" => 1 })
    Assemblies::Assembly::Schema::KIND.store.write(@model, assembly)

    extracted = PhComposer::Export::Collection.build(@model, :run_id => "membrane", :contributors => [SECTION])
    row = extracted.document.dig("sections", SECTION, "records").find { |found| found.fetch("id") == assembly["id"] }
    refute row.dig("layers", 1, "segments", 0).key?("user_data")
    references = extracted.findings.select { |finding| finding.fetch("object_id") == "seg_000000000070" }
                          .map { |finding| finding.values_at("code", "reference") }
    part = { "kind" => ASSEMBLY, "id" => assembly["id"], "part_ids" => [layer["id"], "seg_000000000070"] }
    assert_equal [["export.metadata_omitted", part]], references
    assert(preflight_findings.none? { |finding| finding.fetch("blocks_export") })
  end

  # A reader that does not ask for parts takes every part map out, at any depth, with the part's write reference.
  def test_a_reader_without_parts_omits_nested_maps_with_their_reference
    assembly = @fixture.fetch("assemblies").find { |row| row.fetch("id") == "asm_Mixed0000001" }
    layer = assembly.dig("layers", 0)
    segment = layer.dig("segments", 1)
    segment["user_data"] = { "firm" => { "check" => "ok" } }
    Assemblies::Assembly::Schema::KIND.store.write(@model, assembly)
    catalog = PhComposer::Registry.current.catalog
    reader = PhComposer::Export::RecordReader.new(PhComposer::Records::Engine.new(@model, catalog), catalog)

    row = reader.within(SECTION) { reader.records(ASSEMBLY) }.find { |found| found.fetch("id") == assembly["id"] }
    refute row.dig("layers", 0, "segments", 1).key?("user_data")
    assert_equal [{ "kind" => ASSEMBLY, "id" => assembly["id"], "part_ids" => [layer["id"], segment["id"]] }],
                 reader.findings.map(&:to_h).filter_map { |finding| finding["reference"] }
  end

  def test_a_reserved_key_blocks_only_a_carried_part_map_and_the_preflight_names_it
    assemblies = @fixture.fetch("assemblies").to_h { |row| [row.fetch("id"), row] }
    assemblies.fetch("asm_Membrane0001")["layers"][1]["user_data"] = { "ph_composer" => 1 }
    Assemblies::Assembly::Schema::KIND.store.write(@model, assemblies.fetch("asm_Membrane0001"))
    PhComposer::Export::Collection.build(@model, :run_id => "local", :contributors => [SECTION])
    assert(preflight_findings.none? { |row| row.fetch("blocks_export") })

    assemblies.fetch("asm_Mixed0000001")["layers"][0]["segments"][0]["user_data"] = { "ph_composer" => 1 }
    Assemblies::Assembly::Schema::KIND.store.write(@model, assemblies.fetch("asm_Mixed0000001"))
    error = assert_raises(PhComposer::Export::Blocked) do
      PhComposer::Export::Collection.build(@model, :run_id => "reserved", :contributors => [SECTION])
    end
    assert_equal "export.blocked", error.code
    blocking = preflight_findings.select { |row| row.fetch("blocks_export") }
    assert_equal [%w[export.blocked seg_000000000030]], blocking.map { |row| row.values_at("code", "object_id") }

    assemblies.fetch("asm_Single000001")["layers"][1]["user_data"] = { "ph_composer" => 1 }
    Assemblies::Assembly::Schema::KIND.store.write(@model, assemblies.fetch("asm_Single000001"))
    blocking = preflight_findings.select { |row| row.fetch("blocks_export") }.map { |row| row.fetch("object_id") }
    assert_equal %w[lyr_000000000002 seg_000000000030], blocking.sort
  end

  def test_record_preflight_is_nonblocking_for_unused_incomplete_and_names_mass_defaults
    result = PhComposer::API.query(:context => @context, :name => "ph_composer.assemblies.export_preflight")
    assert_equal "completed", result.fetch("status"), result.inspect
    findings = result.fetch("value").fetch("findings")
    assert findings.none? { |finding| finding.fetch("blocks_export") }
    assert_includes findings.map { |finding| finding.fetch("code") }, "assembly.no_thermal_layers"
    assert_includes findings.map { |finding| finding.fetch("code") }, "assembly.membrane_in_mixed_layer"
    defaults = findings.find { |finding| finding.fetch("code") == "material.thermal_mass_defaulted" }
    assert_includes defaults.fetch("message"), "600"
    assert_includes defaults.fetch("message"), "1000"
    assert_includes defaults.fetch("message"), "Synthetic defaults"
    refute_includes defaults.fetch("message"), "mat_"
    assert_empty result.fetch("value").fetch("repairs")
    expected = JSON.parse(File.read(File.join(ROOT, "expected.json")))
    unavailable = findings.select do |finding|
      %w[assembly.no_thermal_layers assembly.membrane_in_mixed_layer].include?(finding.fetch("code"))
    end.map { |finding| finding.fetch("object_id") }
    assert_equal expected.fetch("unavailable").sort, unavailable.sort
  end

  def preflight_findings
    result = PhComposer::API.query(:context => @context, :name => "ph_composer.assemblies.export_preflight")
    assert_equal "completed", result.fetch("status"), result.inspect
    result.dig("value", "findings")
  end

  def test_unreadable_record_blocks_even_when_unused
    kind = Assemblies::Materials::Schema::KIND
    kind.store.write(@model, @fixture.fetch("materials").first.merge("density_kg_m3" => "not numeric"))
    result = PhComposer::API.query(:context => @context, :name => "ph_composer.assemblies.export_preflight")
    assert_equal "completed", result.fetch("status"), result.inspect
    assert result.dig("value", "findings").any? { |finding| finding["blocks_export"] }
  end

  def test_construction_metadata_guard_declares_exact_two_keys
    keys = PhComposer::Registry.current.export_contributors.fetch(SECTION).user_data_keys
    assert_equal %w[ph_composer.assembly_id ph_composer.membrane_layers], keys
    allowed = JSON.generate("type" => "OpaqueConstruction", "user_data" => {
      "ph_composer" => { "assembly_id" => "asm_Single000001", "membrane_layers" => [] }
    })
    assert PhComposer::Export::Privacy.validate!(translation_result(allowed))
    foreign = JSON.parse(allowed)
    foreign["user_data"]["ph_composer"]["private_note"] = "must stay local"
    assert_raises(PhComposer::CodedError) do
      PhComposer::Export::Privacy.validate!(translation_result(JSON.generate(foreign)))
    end
  end

  def test_report_lists_each_definition_and_discloses_defaults_membranes_and_local_fields_once
    row = { "assembly_id" => "asm_Single000001", "name" => "<Synthetic>", "thermal_layer_count" => 2,
            "membrane_names" => ["Film"], "defaulted_material_ids" => ["mat_Wool00000001"] }
    plain = row.merge("assembly_id" => "asm_Plain0000001", "name" => "Plain", "membrane_names" => [],
                      "defaulted_material_ids" => [])
    second = row.merge("assembly_id" => "asm_Second000001", "name" => "Second membrane")
    html = Assemblies::ExportProjection.report(view("construction_definitions" => [row, second, plain]), "si").join
    assert_includes html, "&lt;Synthetic&gt;"
    assert_includes html, "<td>Plain</td><td></td>"
    assert_includes html, "Membranes: Film."
    assert_includes html, "600 kg/m3"
    assert_includes html, "1000 J/kgK"
    assert_equal 1, html.scan("Membranes of a used Assembly are carried in HBJSON").length
    assert_includes html, "Only Assemblies that a Face uses are written to the HBJSON"
    assert_equal 1, html.scan("Air barrier, photos").length
    assert_equal 1, html.scan("Honeybee defaults:").length
    assert_includes html, "roughness MediumRough"
    assert_includes html, "thermal absorptance 0.9 when emissivity is absent"
    assert_includes html, "solar and visible absorptance 0.7"
    assert_includes html, "Authored emissivity supplies thermal absorptance when present"
    assert_empty Assemblies::ExportProjection.report(view({}), "si")
  end

  private

  def view(fields)
    contributor = PhComposer::Registry.current.export_contributors.fetch(SECTION)
    PhComposer::Export::ResultView.new({ SECTION => fields }, contributor)
  end

  def translation_result(hbjson)
    { "schema_version" => 1, "run_id" => "run", "state" => "complete",
      "summary" => { "objects" => 1, "unavailable" => 0, "findings" => 0, "publishable" => true },
      "sections" => [], "findings" => [], "failure" => nil,
      "canonical_model" => { "hbjson" => hbjson, "rooms" => 0, "faces" => 0, "surface_pairs" => 0 } }
  end
end
