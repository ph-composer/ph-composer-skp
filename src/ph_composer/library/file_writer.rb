# frozen_string_literal: true

require "digest"
require "securerandom"

module PhComposer
  module Library
    # One file, one rename commit. The destination and stage remain private to this object. Every
    # pre-commit failure leaves prior destination bytes intact and removes only this writer's stage.
    class FileWriter
      # What `destination` holds now, as export_preview reports it and a replacement consent names it:
      # the SHA-256 of its bytes, or nil when nothing is there.
      def self.state(destination)
        path = destination.to_s
        return nil unless File.exist?(path) || File.symlink?(path)
        unless File.file?(path) && !File.symlink?(path)
          raise Error.new("library.destination_invalid", "Choose a regular library file destination.")
        end

        Digest::SHA256.file(path).hexdigest
      rescue SystemCallError, IOError
        raise Error.new("library.export_write_failed", "The library destination could not be inspected."), :cause => nil
      end

      def initialize(destination)
        @destination = destination.to_s.dup.freeze
        @prior = self.class.state(@destination)
      end

      def inspect
        "#<#{self.class.name}>"
      end

      # Whether the destination held a file when this writer was made.
      def replaces?
        !@prior.nil?
      end

      # The destination's state when this writer was made (FileWriter.state).
      def prior_state
        @prior
      end

      def prior_bytes
        return nil if @prior.nil?
        if File.size(@destination) > LibraryFile::MAX_BYTES
          raise Error.new("library.file_too_large", "The destination exceeds the 32 MiB library file limit.")
        end

        bytes = File.binread(@destination)
        verify_unchanged!
        bytes
      end

      def write(bytes)
        owned = false
        stage = File.join(File.dirname(@destination), ".ph-composer-library-#{SecureRandom.hex(16)}.tmp")
        File.open(stage, File::WRONLY | File::CREAT | File::EXCL, 0o600) do |file|
          owned = true
          file.binmode
          file.write(bytes)
          file.flush
          file.fsync
        end
        # binread answers binary text, so the comparison is of bytes, whatever `bytes`' encoding.
        unless File.binread(stage) == bytes.b
          raise Error.new("library.export_write_failed", "The staged library file could not be verified.")
        end

        yield if block_given?
        verify_unchanged!
        File.rename(stage, @destination)
        stage = nil
        true
      rescue SystemCallError, IOError
        raise Error.new("library.export_write_failed", "The library file could not be written."), :cause => nil
      ensure
        begin
          File.delete(stage) if owned && stage && File.exist?(stage)
        rescue SystemCallError, IOError
          # A successful rename has committed. A cleanup error must not misreport that commit.
        end
      end

      def verify_unchanged!
        return if self.class.state(@destination) == @prior

        raise Error.new("library.destination_changed", "The destination changed after review. Try again.")
      end
    end
  end
end
