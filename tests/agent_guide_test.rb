# frozen_string_literal: true

require_relative "test_helper"

# docs/AGENT_GUIDE.md names operations and tools an agent will call as written: each must exist, so the
# guide cannot drift from what discovery answers. The recipes run elsewhere: the Spaces one, public calls
# only after native fixture setup, in tests/spaces_walkthrough_test.rb; the write and export ones in
# tests/agent_access_write_tools_test.rb and tests/api_client_test.rb.
class AgentGuideTest < PhComposerTestCase
  GUIDE = File.read(File.expand_path("../docs/AGENT_GUIDE.md", __dir__))
  SHIPPED = PhComposer::AgentAccess::Guide::PATH
  Guide = PhComposer::AgentAccess::Guide

  def setup
    super
    PhComposer.compose
  end

  def test_every_operation_the_guide_names_is_registered
    named = GUIDE.scan(/`(ph_composer\.[a-z_.]+)`/).flatten.uniq
    missing = named.reject { |name| PhComposer::API.describe(:name => name) }

    refute_empty named
    assert_empty missing
  end

  # The extension carries the guide as written, so it has one source: `make fixtures` copies it and every
  # other run compares the copy.
  def test_the_extension_ships_the_guide_as_written
    if FixtureFiles::WRITING
      File.write(SHIPPED, GUIDE) unless File.exist?(SHIPPED) && File.read(SHIPPED) == GUIDE
      assert true
    else
      assert_equal GUIDE, File.read(SHIPPED), "src/ph_composer/agent_access/guide.md is stale; run `make fixtures`"
    end
  end

  # Every topic is one section of the guide, all of it is in some topic, and each fits one reply.
  def test_the_guide_splits_into_unique_topics_that_each_fit_a_reply
    topics = Guide::TOPICS
    executor = PhComposer::AgentAccess::Executor.new(:tools => PhComposer::AgentAccess::Tools::TABLE)
    issued = PhComposer::AgentAccess::Tokens.issue(:capabilities => %w[read])
    row = PhComposer::AgentAccess::Tokens.snapshot.fetch(PhComposer::AgentAccess::Tokens.digest(issued.fetch("token")))

    assert_equal topics.map { |topic| topic.fetch("id") }.uniq, topics.map { |topic| topic.fetch("id") }
    assert_includes topics.map { |topic| topic.fetch("id") }, "recipes.thermal_bridge_types"
    assert_equal Guide::TEXT.scan(/^#+ .+$/).length, topics.sum { |topic| topic.fetch("text").scan(/^#+ .+$/).length }
    topics.each do |topic|
      found = executor.call(row, "discover", "section" => "guide", "topic" => topic.fetch("id"))
      refute found["isError"], topic.fetch("id")
      assert_equal topic.fetch("text"), found.dig("structuredContent", "text")
    end
  end

  def test_the_guide_names_its_version
    assert_equal({ "api" => "1.#{PhComposer::API::MINOR}", "extension" => PhComposer::VERSION,
                   "digest" => Digest::SHA256.hexdigest(Guide::TEXT) }, Guide.version)
  end

  def test_every_tool_the_guide_names_is_in_the_verb_table
    named = GUIDE.scan(/`([a-z_]+)`/).flatten.uniq & %w[discover describe query preview context invoke outcome view
                                                        setup export_file export_preflight start_export
                                                        export_status cancel_export latest_export]
    unknown = named - PhComposer::AgentAccess::Tools::TABLE.keys

    assert_includes named, "invoke"
    assert_empty unknown
  end
end
