# frozen_string_literal: true

require "digest"
require "securerandom"
require_relative "export_projection"
require_relative "file_writer"

module PhComposer
  module Library
    # The destination is the one the user chose in the native save dialog (Declarations::Approval),
    # with their consent to replace an existing file; it never enters params or the result. Writing is
    # not a Model operation and creates no Undo entry.
    module ExportWorkflow
      APPROVAL = Declarations::Approval.new(:kind => "save_file", :title => "Export Library File",
                                            :default_name => "model-library.json").freeze

      module_function

      # What can refuse before a destination is chosen (Declarations::FileExport): dispatch runs it
      # before the native save dialog opens and again before `run`.
      def precondition(request)
        if request.params.key?("expected_revision") && request.params["expected_revision"] != request.session.revision
          raise Error.new("revision.stale", "The Model changed since the library export was requested.")
        end
        return unless request.params.key?("library_name") && request.params.fetch("library_name").strip.empty?

        raise Error.new("params.invalid", "The library name must not be blank.")
      end

      def run(request)
        before = ExportProjection.build(request)
        reviewed = request.params["projection_digest"]
        if reviewed && reviewed != before.fetch("projection_digest")
          raise Error.new("revision.stale", "What export_preview reviewed is not what would be written. Preview again.")
        end

        # Both routes can name any file; a library is only ever written to a .json one.
        unless File.extname(request.approval.path.to_s).casecmp?(".json")
          raise Error.new("library.destination_invalid", "Choose a .json library file destination.")
        end

        writer = FileWriter.new(request.approval.path)
        consent!(writer, request)

        identity = request.params.fetch("identity", "new")
        library = if identity == "update"
                    existing(writer, request)
                  else
                    { "id" => SecureRandom.uuid, "name" => "Model library" }
                  end
        library["name"] = request.params["library_name"] if request.params.key?("library_name")
        document = { "format" => LibraryFile::FORMAT, "schema_version" => 1, "library" => library,
                     "exported_at" => Time.now.utc.iso8601(6) }.merge(before.slice("kind_schema_versions", "kinds"))
        document["record_origins"] = before.fetch("record_origins") unless before.fetch("record_origins").empty?
        bytes = JSON.pretty_generate(document) + "\n"
        if bytes.bytesize > LibraryFile::MAX_BYTES
          raise Error.new("library.file_too_large", "The library export exceeds the 32 MiB file limit.")
        end

        writer.write(bytes)
        value = ExportProjection.summary(before, request.registry)
                                .merge("library_id" => library.fetch("id"), "library_name" => library.fetch("name"),
                                       "identity" => identity, "written" => true,
                                       "destination_state" => Digest::SHA256.hexdigest(bytes))
        return value unless request.params["compact"]

        ExportRegistration.compact(value).merge("projection_digest" => before.fetch("projection_digest"),
                                                "revision" => request.session.revision)
      rescue SystemCallError, IOError, EncodingError
        raise Error.new("library.export_write_failed", "The library file could not be written."), :cause => nil
      end

      # Replacing a file needs consent. The native Save sheet gives it against the file as it is now; an
      # approved location gives it against the destination state and projection export_preview reported,
      # so a file or a Model that changed since the caller's review is refused.
      def consent!(writer, request)
        approval = request.approval
        return unless writer.replaces?
        unless approval.replace
          raise Error.new("export.replace_required", "The destination exists and was not approved for replacement.")
        end
        return unless approval.location_id

        unless approval.state && request.params.key?("projection_digest")
          raise Error.new("export.replace_required", "Replacing an approved destination needs the " \
                                                     "expected_destination and projection_digest export_preview " \
                                                     "reported.")
        end
        return if approval.state == writer.prior_state

        raise Error.new("library.destination_changed", "The destination changed after review. Preview again.")
      end

      def existing(writer, request)
        bytes = writer.prior_bytes
        unless bytes
          raise Error.new("library.update_destination_required", "Update identity needs an existing library file.")
        end

        adapters = request.registry.library_kinds.values.to_h { |row| [row.adapter.wire_kind, row.adapter] }
        lookup = ->(kind) { adapters[kind] }
        parsed = LibraryFile.parse(bytes, :adapters => lookup, :max_rows => FileProvider::MAX_ROWS)
        allowed = %w[library.row_optional_absent library.row_fields_omitted]
        warnings_valid = parsed.fetch("warnings").all? { |row| allowed.include?(row["code"]) }
        unless parsed.fetch("unavailable").empty? && warnings_valid && valid_rows?(parsed, adapters)
          raise Error.new("library.update_destination_invalid", "Update identity needs valid rows and supported kinds.")
        end

        DeepCopy.call(parsed.fetch("library"))
      end

      def valid_rows?(parsed, adapters)
        parsed.fetch("rows").all? do |kind, rows|
          adapter = adapters.fetch(kind)
          rows.all? do |row|
            mapped = adapter.map.call(DeepCopy.call(row.fetch("snapshot")))
            JsonValue.problems(mapped).empty? && JsonSchema.validate(mapped, adapter.mapped_schema).empty?
          end
        end
      rescue CodedError
        false
      end

      private_class_method :consent!, :existing, :valid_rows?
    end
  end
end
