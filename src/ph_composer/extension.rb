# frozen_string_literal: true

require "fileutils"
require "json"
require "sketchup.rb"
require "time"
require "tmpdir"

# The composition root: what loads, in what order, and which features install.
module PhComposer
  # A module holding process state registers how to clear it; the offline suite clears all of it
  # before each test. The name makes a reload re-register in place.
  def self.on_reset(name, &block)
    resettables[name] = block
  end

  def self.reset_for_test
    resettables.each_value(&:call)
  end

  def self.resettables
    @resettables ||= {}
  end
  private_class_method :resettables

  # A failure loading or composing the extension leaves a record before SketchUp reports the load error,
  # and composition never continues past it as if the extension had loaded. The logger loads first; when
  # it is the logger that failed, `bootstrap_record` writes the error's class alone to the same file.
  def self.record_load_failure(error)
    return Diagnostics.exception("extension_load_failed", error) if defined?(Diagnostics.exception)

    plugins = Sketchup.respond_to?(:find_support_file) ? Sketchup.find_support_file("Plugins").to_s : ""
    folder = plugins.empty? ? File.join(Dir.tmpdir, EXTENSION_ID) : File.join(File.dirname(plugins), EXTENSION_NAME)
    bootstrap_record(error, File.join(folder, "logs", "ph-composer.log"))
  rescue StandardError
    nil
  end

  # Kept in step with Diagnostics' file and its base fields; nothing from the error but its class.
  def self.bootstrap_record(error, log_path)
    FileUtils.mkdir_p(File.dirname(log_path))
    line = { "timestamp" => Time.now.utc.iso8601, "schema" => 1, "event" => "extension_load_failed",
             "extension_version" => VERSION, "severity" => "error", "status" => "failed",
             "error_class" => error.class.name.to_s[/\A[A-Z][A-Za-z0-9_:]{0,95}\z/] || "Exception" }
    File.open(log_path, "ab") { |file| file.write(JSON.generate(line) + "\n") }
  end

  begin
    require_relative "core/diagnostics"
    # The shared foundation, which names no feature. Directories load in dependency order and files
    # alphabetically within each. A file whose body names a later file's constant at load names that
    # file with `require_relative`.
    unless const_defined?(:FOUNDATION_DIRECTORIES)
      FOUNDATION_DIRECTORIES = %w[core session shell runtime export colour_by library agent_access].freeze
    end
    FOUNDATION_DIRECTORIES.each do |directory|
      Dir[File.join(__dir__, directory, "**", "*.rb")].sort.each { |path| require path }
    end

    # Features are listed here by hand and never found by walking `features/`, so every feature this
    # build carries is visible in one place. A feature adds its entry file's `require_relative` and its
    # module to this list; nothing else in the foundation changes.
    require_relative "features/assemblies/install"
    require_relative "features/zones/install"
    require_relative "features/windows/install"
    require_relative "features/spaces/install"
    require_relative "features/thermal_bridges/install"
    FEATURES = [Assemblies, Zones, Windows, Spaces, ThermalBridges].freeze unless const_defined?(:FEATURES)

    # Capabilities the foundation itself provides, registered through the same interface as a feature.
    unless const_defined?(:FOUNDATION_FEATURES)
      FOUNDATION_FEATURES = [RecordQueries, ContextCommands, CaptureCommand, ColourBy, Library, LocationCommands,
                             AgentAccess].freeze
    end

    # Registers the foundation and every listed feature. A registration problem fails loading here,
    # with every diagnostic in the message, rather than leaving a partly available extension.
    def self.compose
      Registry.reset
      Registry.install(FOUNDATION_FEATURES + FEATURES)
    end

    unless file_loaded?(__FILE__)
      Sessions.install
      compose
      on_reset("composition") { compose }
      Sessions.open_active
      Panel.install
      Commands.install
      # Serves agent tokens issued before this launch; issuing the first one starts it otherwise.
      AgentAccess::Listener.refresh
      Diagnostics.prune
      Diagnostics.log("extension_loaded", "severity" => "info", "manifest" => BuildIdentity.manifest,
                                          "sketchup_version" => Sketchup.version.to_s)
      file_loaded(__FILE__)
    end
  # A SyntaxError or LoadError must be recorded too, so this is wider than StandardError.
  rescue Exception => error # rubocop:disable Lint/RescueException
    record_load_failure(error)
    raise
  end
end
