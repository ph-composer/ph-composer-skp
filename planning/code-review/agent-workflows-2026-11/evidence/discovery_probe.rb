# frozen_string_literal: true

# Review-only probe. Uses the existing offline host stub and scratch credentials, never SketchUp
# or a real client configuration. Run from the repository root with the pinned Ruby.
require_relative "../../../../tests/test_helper"

class AgentWorkflowDiscoveryProbe < PhComposerTestCase
  def test_discovery_and_description_delivery
    PhComposer::Sessions.for(Sketchup.active_model)
    issued = PhComposer::AgentAccess::Tokens.issue(:capabilities => %w[read view model_write setup export capture])
    token = PhComposer::AgentAccess::Tokens.snapshot.fetch(
      PhComposer::AgentAccess::Tokens.digest(issued.fetch("token"))
    )
    executor = PhComposer::AgentAccess::Executor.new(:tools => PhComposer::AgentAccess::Tools::TABLE)
    document = PhComposer::API.discover
    groups = %w[queries actions view_commands setup_commands file_exports participants]
    compact = executor.call(token, "discover", {})
    owners = document.fetch("features").map { |feature| feature.fetch("id") }
    descriptions = groups.flat_map { |group| document.fetch(group).map { |entry| entry.fetch("name") } }
    descriptions += %w[record_kinds reference_targets].flat_map do |group|
      document.fetch(group).map { |entry| entry.fetch("id") }
    end
    sizes = descriptions.map do |name|
      result = executor.call(token, "describe", "name" => name)
      { "name" => name, "bytes" => JSON.generate(PhComposer::API.describe(:name => name)).bytesize,
        "is_error" => result.fetch("isError"), "code" => result.dig("structuredContent", "code") }
    end
    owner_results = owners.map do |owner|
      raw = PhComposer::AgentAccess::Tools.discover({ "owner" => owner }, token)
      result = executor.call(token, "discover", "owner" => owner)
      { "owner" => owner, "bytes" => JSON.generate(raw).bytesize, "is_error" => result.fetch("isError"),
        "code" => result.dig("structuredContent", "code") }
    end
    report = {
      "baseline" => "f65ccee62b0a3994a46001d55f7aefd1a69f0faf", "ruby" => RUBY_VERSION,
      "api" => document.fetch("api"), "counts" => groups.to_h { |group| [group, document.fetch(group).length] },
      "by_owner" => groups.to_h do |group|
        [group, document.fetch(group).group_by { |entry| entry.fetch("owner") }.transform_values(&:length)]
      end,
      "in_process_keys" => document.keys, "external_keys" => compact.fetch("structuredContent").keys,
      "missing_external_keys" => document.keys - compact.fetch("structuredContent").keys,
      "record_kinds" => document.fetch("record_kinds"),
      "reference_targets" => document.fetch("reference_targets"),
      "operations" => groups.to_h do |group|
        [group, document.fetch(group).map { |entry| entry.slice("name", "owner", "description") }]
      end,
      "compact_discovery_bytes" => JSON.generate(compact.fetch("structuredContent")).bytesize,
      "owner_discovery" => owner_results, "descriptions" => sizes.sort_by { |entry| -entry.fetch("bytes") },
      "resources" => PhComposer::AgentAccess::MCP.answer({ "method" => "resources/list" }, token),
      "prompts" => PhComposer::AgentAccess::MCP.answer({ "method" => "prompts/list" }, token)
    }
    File.write(File.join(__dir__, "discovery.json"), JSON.pretty_generate(report) + "\n")
    puts JSON.pretty_generate(report.slice("api", "counts", "compact_discovery_bytes", "missing_external_keys",
                                           "owner_discovery").merge("failed_descriptions" => sizes.select { |r| r["is_error"] }))
    assert_equal false, compact.fetch("isError")
  end
end
