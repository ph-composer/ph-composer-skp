# frozen_string_literal: true

require "fileutils"
require "json"
require "securerandom"

module PhComposer
  # PH-Composer's own settings on this computer: one JSON file, `{"schema_version": 1, "sections": {...}}`,
  # with one section per feature id. It sits in a PH-Composer folder in the user's application-support
  # folder, outside SketchUp's versioned folders, so every SketchUp version and every reinstall of the
  # extension reads the same file (context/TECH_STACK.md, "This computer's settings file"). macOS only:
  # on any other platform the service is unavailable. Names no feature; the feature that owns a section
  # maps a Refused reason to its own code.
  #
  # A write holds a lock on a sibling file while it re-reads the file, changes one section, writes a sibling
  # file and renames it into place, so two SketchUp processes writing different sections lose neither and a
  # write cut short leaves the old file. A file this build cannot read, or one a later schema version wrote,
  # is left as stored: reads report it and writes refuse. Nothing here ever puts the file's path in a message.
  module ComputerSettings
    FOLDER = "PH-Composer"
    FILE_NAME = "settings.json"
    LOCK_NAME = "settings.lock"
    SCHEMA_VERSION = 1
    MAX_BYTES = 256 * 1024
    # How long a write waits for another process's write to finish before it refuses.
    LOCK_WAIT_SECONDS = 2.0
    REASONS = %i[unavailable unreadable later_version too_large unwritable].freeze

    # Why a read or a write could not be made. `reason` is one of REASONS; the message never holds a path.
    class Refused < UserError
      attr_reader :reason

      def initialize(reason, message)
        raise ArgumentError, "Unknown reason #{reason.inspect}." unless REASONS.include?(reason)

        @reason = reason
        super(message)
      end
    end

    class << self
      # The offline suite points the folder at a scratch one; the platform rule still applies.
      attr_writer :directory

      def available?
        Sketchup.platform == :platform_osx
      end

      def directory
        @directory || File.join(Dir.home, "Library", "Application Support", FOLDER)
      end

      # "readable" (including no file yet), "unreadable", "later_version" or "unavailable". Never raises for a
      # file that cannot be read, and never creates the folder or the file.
      def state
        read_document
        "readable"
      rescue Refused => error
        error.reason.to_s
      end

      # One section's values, `{}` when the section or the file is absent. Raises Refused when the service is
      # unavailable or the file cannot be read. Never creates the folder or the file.
      def read(section)
        read_document.fetch("sections").fetch(checked(section), {})
      end

      # Changes one section: the block receives the section's current values and returns its new ones, which
      # must be a JSON object. Other sections are written back as they were read under the lock. Answers the
      # new values, or raises Refused and leaves the file as it was.
      def write(section)
        checked(section)
        with_lock do
          document = read_document
          values = yield(document.fetch("sections").fetch(section, {}))
          raise ArgumentError, "A settings section must be a JSON object." unless values.is_a?(Hash)

          replace(document.merge("sections" => document.fetch("sections").merge(section => values)))
          values
        end
      end

      private

      def path
        File.join(directory, FILE_NAME)
      end

      def checked(section)
        return section if section.is_a?(String) && Registry::ID_PATTERN.match?(section)

        raise ArgumentError, "A settings section is named by a feature id."
      end

      def unavailable!
        return if available?

        raise Refused.new(:unavailable, "PH-Composer keeps its settings on this computer only on macOS for now.")
      end

      # The whole document; an absent file reads as an empty one at this schema version.
      def read_document
        unavailable!
        return { "schema_version" => SCHEMA_VERSION, "sections" => {} } unless File.exist?(path)

        parse(File.open(path, "rb") { |file| file.read(MAX_BYTES + 1) })
      rescue SystemCallError, IOError
        raise Refused.new(:unreadable, "PH-Composer's settings file on this computer could not be read."),
              :cause => nil
      end

      def parse(text)
        unreadable = "PH-Composer's settings file on this computer could not be read. It was left as stored."
        raise Refused.new(:unreadable, unreadable) if text.nil? || text.bytesize > MAX_BYTES

        text = text.dup.force_encoding(Encoding::UTF_8)
        raise Refused.new(:unreadable, unreadable) unless text.valid_encoding?

        document = JSON.parse(text)
        # JSON decodes an escaped lone surrogate to a string that is not valid UTF-8; no reader may meet one.
        raise Refused.new(:unreadable, unreadable) unless valid_strings?(document)

        version = document.is_a?(Hash) && document["schema_version"]
        raise Refused.new(:unreadable, unreadable) unless version.is_a?(Integer)
        if version > SCHEMA_VERSION
          raise Refused.new(:later_version, "PH-Composer's settings file on this computer was written by a later " \
                                            "version of PH-Composer. It was left as stored.")
        end
        raise Refused.new(:unreadable, unreadable) unless version == SCHEMA_VERSION && document["sections"].is_a?(Hash)

        document
      rescue JSON::ParserError, EncodingError, ArgumentError
        raise Refused.new(:unreadable, unreadable), :cause => nil
      end

      def valid_strings?(value)
        case value
        when String then value.valid_encoding?
        when Hash then value.all? { |key, item| valid_strings?(key) && valid_strings?(item) }
        when Array then value.all? { |item| valid_strings?(item) }
        else true
        end
      end

      # Writes the document beside the file and renames it into place, so a reader sees the old file or the
      # new one, never part of either. Runs under the lock, so it also clears any copy a crashed write left.
      def replace(document)
        text = JSON.pretty_generate(document)
        if text.bytesize > MAX_BYTES
          raise Refused.new(:too_large, "PH-Composer's settings would exceed their size limit. Nothing was written.")
        end

        Dir.glob(File.join(directory, ".#{FILE_NAME}.*.tmp")).each { |stale| File.unlink(stale) }
        temporary = File.join(directory, ".#{FILE_NAME}.#{SecureRandom.hex(6)}.tmp")
        begin
          File.open(temporary, File::WRONLY | File::CREAT | File::EXCL, 0o600) do |file|
            file.write(text)
            file.flush
            file.fsync
          end
          File.rename(temporary, path)
        ensure
          File.unlink(temporary) if File.exist?(temporary)
        end
      rescue SystemCallError, IOError
        raise unwritable, :cause => nil
      end

      # Runs the block holding an exclusive lock on the sibling lock file, creating the folder first. Waits up
      # to LOCK_WAIT_SECONDS for another process's write, never longer, so SketchUp is not held on a lock. The
      # block's own errors pass through unchanged.
      def with_lock
        unavailable!
        lock = open_lock
        begin
          acquire(lock)
          yield
        ensure
          lock.close
        end
      end

      def open_lock
        FileUtils.mkdir_p(directory, :mode => 0o700)
        File.open(File.join(directory, LOCK_NAME), File::RDWR | File::CREAT, 0o600)
      rescue SystemCallError, IOError
        raise unwritable, :cause => nil
      end

      def acquire(lock)
        deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + LOCK_WAIT_SECONDS
        until lock.flock(File::LOCK_EX | File::LOCK_NB)
          if Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline
            raise Refused.new(:unwritable, "Another SketchUp is saving PH-Composer's settings. Nothing was " \
                                           "written; try again.")
          end

          sleep(0.02)
        end
      rescue SystemCallError, IOError
        raise unwritable, :cause => nil
      end

      def unwritable
        Refused.new(:unwritable, "PH-Composer's settings file on this computer could not be saved. Nothing was " \
                                 "written.")
      end
    end
  end

  on_reset("computer_settings") { ComputerSettings.directory = nil }
end
