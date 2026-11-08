# frozen_string_literal: true

# Source-scanning tests File.read UTF-8 files. Without this, Ruby takes the external encoding from the
# locale, which is US-ASCII in a shell with none, and matching on what they read raises.
Encoding.default_external = Encoding::UTF_8

require "fileutils"
require "json"
require "minitest/autorun"
require "tmpdir"
require_relative "support/sketchup_stub"
require_relative "support/fixture_files"
require_relative "support/hosted_library_fixtures"

# SketchUp 2023, the support floor, embeds Ruby 2.7.2; the current proving host embeds 3.2.2. A
# loop running outside that span cannot see what either host will do, in either direction.
SUPPORTED_RUBY = (Gem::Version.new("2.7")...Gem::Version.new("3.3")).freeze
unless SUPPORTED_RUBY.cover?(Gem::Version.new(RUBY_VERSION[/\A\d+\.\d+/]))
  raise "The offline suite runs on Ruby 2.7 to 3.2; this is #{RUBY_VERSION}. " \
        "See docs/DEVELOPMENT.md \"Ruby versions\"."
end

# See the note in support/sketchup/host.rb: this must outlive every test, so it is not an at_exit.
Minitest.after_run { FileUtils.rm_rf(STUB_LOAD_DIR) }

SOURCE_ROOT = File.expand_path("../src", __dir__)
TESTS_ROOT = __dir__
load File.join(SOURCE_ROOT, "ph_composer.rb")
load File.join(SOURCE_ROOT, "ph_composer", "extension.rb")

# Stands in for the agent listener's loopback server: it records the token snapshot and binds nothing.
StubAgentServer = Struct.new(:port, :tokens) do
  def start
    self
  end

  def stop
    true
  end

  def snapshot
    { "recent" => [] }
  end

  def stopped?
    false
  end

  def refuse_revoked(_live_ids)
    {}
  end
end

class PhComposerTestCase < Minitest::Test
  def setup
    Sketchup.reset
    PhComposer.reset_for_test
    PhComposer::Diagnostics.strict = true
    # Issuing a token starts the agent listener; no test binds its port unless it supplies a server.
    PhComposer::AgentAccess::Listener.server_factory = ->(port) { StubAgentServer.new(port) }
    # Hermetic: a client's saved token and Codex's config go to a scratch folder, and no test runs a client.
    @agent_home = Dir.mktmpdir("ph_composer_agent_home")
    PhComposer::AgentAccess::Connections.directory = File.join(@agent_home, ".ph-composer")
    PhComposer::AgentAccess::ClientSetup.codex_home = File.join(@agent_home, ".codex")
    PhComposer::AgentAccess::ClientSetup.claude_settings = File.join(@agent_home, ".claude.json")
    PhComposer::AgentAccess::ClientSetup.timeout = nil
    PhComposer::AgentAccess::ClientSetup.runner = ->(argv) { raise "a test ran #{argv.first} without a runner" }
    # Hermetic: the real reader asks macOS `defaults`, which a test must not depend on.
    PhComposer::Preferences.apple_locale_reader = -> {}
    # Hermetic: no test reads or writes this machine's keychain or Credential Manager.
    PhComposer::Library::Connection::CredentialStore.backend = HostedLibraryFixtures::MemoryCredentials.new
    HostedLibraryFixtures.reset
    @undeclared_refusals = []
    PhComposer::Refusals.audit = lambda do |declaration, code|
      next if (PhComposer::Refusals.declared(declaration) + PhComposer::Refusals.common(declaration)).include?(code)

      @undeclared_refusals << "#{declaration.name} refused with #{code}"
    end
    # Last, so a test measuring host timers measures its own and none that setup started.
    UI.reset
  end

  # A duplicate Zone or Space a fixture builds stands for one already in the Model, which the copy
  # watchers leave for the explicit command; only a native copy made during the session is repaired
  # automatically.
  def treat_duplicates_as_existing(model = Sketchup.active_model)
    session = PhComposer::Sessions.for(model)
    PhComposer::Zones::CopyWatch.state(session).reset
    PhComposer::Spaces::CopyWatch.state(session).reset
  end

  # An operation that refuses with a code outside its `refuses` and its common sets publishes an
  # incomplete list (context/CONTRACTS.md, "Outcomes and codes"). Declare the code; never suppress this.
  def after_teardown
    super
    FileUtils.rm_rf(@agent_home) if @agent_home
    assert_empty Array(@undeclared_refusals), "Add each code to the operation's refuses:"
  end
end
