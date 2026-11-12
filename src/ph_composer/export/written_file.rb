# frozen_string_literal: true

require "digest"

module PhComposer
  module Export
    # The HBJSON a completed run wrote, read back for the caller that started it: `export_status` with
    # `part: "file"` (context/AGENT_INTERFACE.md, "Implemented export task contract"). The path is the run's own
    # receipt's, never a caller's. Nothing is kept between fragments, so each read takes and hashes the whole
    # file again and refuses unless it still matches the receipt: a replaced file is never read as this run's.
    module WrittenFile
      QUERY = "export_status.file"

      module_function

      # One fragment of the file's text as a JSON string (Fragments), beside the receipt's hash and size, which
      # the parsed string's UTF-8 bytes match. `receipt` is the run's `artifacts.hbjson`, nil when it wrote none.
      def part(request, receipt)
        raise Blocked.new("artifact.none", "This export wrote no file; only a completed export has one.") unless receipt

        fragment, next_cursor = Fragments.read(request, QUERY, verified_text(receipt))
        { "file" => receipt.slice("sha256", "bytes"), "fragment" => fragment, "next_cursor" => next_cursor }
      end

      # The file's text when its bytes still hash to the receipt and read as UTF-8. Only a regular file is
      # read, so something put in its place that never ends, such as a pipe, is refused rather than waited on.
      def verified_text(receipt)
        path = receipt.fetch("path")
        text = File.file?(path) ? File.binread(path) : nil
        return text if text && Digest::SHA256.hexdigest(text) == receipt.fetch("sha256") &&
                       text.force_encoding(Encoding::UTF_8).valid_encoding?

        raise Blocked.new("artifact.changed", "The file this export wrote has changed or gone since; export again " \
                                              "to read it.")
      rescue SystemCallError
        raise Blocked.new("artifact.changed", "The file this export wrote can no longer be read; export again to " \
                                              "read it.")
      end
    end
  end
end
