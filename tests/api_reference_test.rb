# frozen_string_literal: true

require_relative "test_helper"
require_relative "../tools/api_reference/api_reference"

# Discovery and description are enough to use the building operations. Every Zone and Face operation
# publishes specific input and output schemas and a worked example that validates, the entity kinds
# publish their descriptors, and docs/API_REFERENCE.md is generated from the same registrations rather
# than kept by hand.
class ApiReferenceTest < PhComposerTestCase
  include FixtureFiles

  API = PhComposer::API
  REFERENCE = File.expand_path("../docs/API_REFERENCE.md", __dir__)
  ANY_OBJECT = { "type" => "object" }.freeze

  def test_an_entity_kind_describes_its_values_references_and_occurrence
    zone = API.describe(:name => "ph_composer.zones.zone")
    face = API.describe(:name => "ph_composer.zones.faces.face")

    assert_equal ["reference_target", "ph_composer.zones", 2, "id"],
                 zone.values_at("kind", "owner", "schema_version", "identity_field")
    assert_equal "mm", zone.dig("values", "properties", "ground_depth_mm", "x-unit")
    assert_equal %w[zone_id zone_path], zone.dig("occurrence_reference", "required")
    assert_equal [{ "key" => "attached_zone_id", "target_kind" => "ph_composer.zones.faces.attached_zone",
                    "cardinality" => "one" },
                  { "key" => "assembly_id", "target_kind" => "ph_composer.assemblies.assembly",
                    "cardinality" => "one" }], face.fetch("references")
    assert_includes face.dig("values", "properties", "boundary_condition", "enum"), "AttachedZone"
    assert_equal %w[zone_id zone_path entity_path entity_id], face.dig("occurrence_reference", "required")
  end

  # Discovery is how an agent learns what to send (context/AGENT_INTERFACE.md, "Discover before
  # acting"), so every top-level param of every registered operation says what it means.
  def test_every_registered_operation_param_has_a_description
    found = API.discover
    names = %w[queries actions view_commands setup_commands file_exports].flat_map do |group|
      found.fetch(group).map { |operation| operation.fetch("name") }
    end
    missing = names.flat_map do |name|
      API.describe(:name => name).dig("params", "properties").filter_map do |param, schema|
        "#{name} #{param}" unless schema["description"].is_a?(String) && !schema["description"].strip.empty?
      end
    end
    assert_empty missing, "Describe each param at its declaration"
  end

  def test_every_building_operation_publishes_specific_schemas_and_a_valid_example
    names = building_operations
    assert_operator names.length, :>=, 22

    names.each do |name|
      description = API.describe(:name => name)
      [description.fetch("params"), description.fetch("result")].each do |schema|
        refute_equal ANY_OBJECT, schema, "#{name} publishes an unspecified object"
        assert_equal false, schema["additionalProperties"], "#{name} leaves its fields open"
      end
      refute_empty description.fetch("examples"), "#{name} has no worked example"
      description.fetch("examples").each do |example|
        assert_empty PhComposer::JsonSchema.validate(example, description.fetch("params")), "#{name} example"
      end
    end
  end

  # An agent learns what an operation can refuse with from two reads: its own codes from `describe`,
  # and the common sets it names from `discover`.
  def test_an_operation_describes_its_own_refusals_and_the_common_sets_it_answers
    type_update = API.describe(:name => "ph_composer.windows.types.update")
    file_export = API.describe(:name => PhComposer::Registry.current.file_exports.keys.first)

    assert_equal PhComposer::Refusals::COMMON, API.discover.fetch("common_refusals")
    assert_equal ["action"], type_update.fetch("common_refusal_sets")
    assert_equal %w[file_export approval location], file_export.fetch("common_refusal_sets")
    assert_includes type_update.fetch("refuses"),
                    { "code" => "window.overlap", "owner" => "ph_composer.windows",
                      "description" => PhComposer::Registry.current.codes.fetch("window.overlap").description }
    assert_includes type_update.fetch("refuses"),
                    { "code" => "target.changed", "owner" => "foundation", "description" => nil }
    refute_includes type_update.fetch("refuses").map { |row| row.fetch("code") }, "revision.stale"
  end

  def test_refusal_metadata_has_uniform_keys_and_discovery_points_to_the_foundation_authority
    found = API.discover
    pointer = found.fetch("refusal_documentation")
    assert_equal "https://github.com/ph-composer/ph-composer-skp/blob/main/context/CONTRACTS.md#outcomes-and-codes",
                 pointer
    assert_includes File.read(File.expand_path("../context/CONTRACTS.md", __dir__)), "## Outcomes and codes"
    seen_owners = []
    %w[queries actions view_commands setup_commands file_exports].each do |group|
      found.fetch(group).each do |operation|
        API.describe(:name => operation.fetch("name")).fetch("refuses").each do |refusal|
          assert_equal %w[code description owner], refusal.keys.sort
          seen_owners << refusal.fetch("owner")
          if refusal.fetch("owner") == "foundation"
            assert_nil refusal.fetch("description")
          else
            refute_empty refusal.fetch("description")
          end
        end
      end
    end
    assert_includes seen_owners, "foundation"
    assert_includes seen_owners, "ph_composer.windows"
    pointer.replace("changed by caller")
    refute_equal pointer, API.discover.fetch("refusal_documentation")
  end

  def test_quantities_carry_their_units
    zones = API.describe(:name => "ph_composer.zones.list").fetch("result")
    faces = API.describe(:name => "ph_composer.zones.faces.list").fetch("result")

    assert_equal "mm", zones.dig("properties", "zones", "items", "properties", "values", "properties",
                                 "ground_depth_mm", "x-unit")
    assert_equal "m2", faces.dig("properties", "faces", "items", "properties", "area_m2", "x-unit")
  end

  def test_the_api_reference_is_generated_from_the_registrations
    text = PhComposerTools::ApiReference.markdown(PhComposer::Registry.current)

    refute_match(/[–—]/, text, "docs/ is client-facing: no em or en dashes")
    PhComposerTools::ApiReference::GROUPS.each do |_title, key, _capability|
      PhComposer::Registry.current.public_send(key).each_key do |name|
        section = text[/^### `#{Regexp.escape(name)}`\n.*?(?=^#|\z)/m]
        assert_match(/^Refuses: /, section.to_s, "#{name} has no refusal line")
      end
    end
    PhComposer::Registry.current.file_exports.each_key do |name|
      assert_includes text, "### `#{name}`", "Registered file export missing from public reference"
      assert_equal "file_export", API.describe(:name => name).fetch("kind")
    end
    if FixtureFiles::WRITING
      write_text(REFERENCE, text)
    else
      assert_equal File.read(REFERENCE), text, "docs/API_REFERENCE.md is stale; run `make fixtures`"
    end
  end

  private

  def building_operations
    discovered = API.discover
    %w[queries actions view_commands].flat_map { |key| discovered.fetch(key) }
                                     .select { |row| row.fetch("owner") == "ph_composer.zones" }
                                     .map { |row| row.fetch("name") }
  end

  def write_text(path, text)
    File.write(path, text) unless File.exist?(path) && File.read(path) == text
    assert true
  end
end
