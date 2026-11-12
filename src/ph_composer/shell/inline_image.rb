# frozen_string_literal: true

require "base64"

module PhComposer
  # An image a completed result carries for an agent to look at, beside its JSON (context/AGENT_INTERFACE.md,
  # "Focused reads and visual context"). A view command declared under the `capture` grant offers one by
  # declaring KEY in its result schema with SCHEMA and putting `InlineImage.of(bytes)` there. A Ruby caller
  # reads it as base64 in the value. The agent connection always moves it out of `structuredContent`, and sends
  # it as an MCP `image` content block, outside the 24 KiB reply budget, only for such a command and up to
  # MAX_BYTES; otherwise it is left out and named in the outcome's `detail.omitted`.
  module InlineImage
    KEY = "inline_image"
    MIME_TYPES = ["image/png"].freeze
    # The decoded size one result may carry. Claude Code 2.1.317 and Codex 0.167.1 each showed their model PNG
    # image blocks up to 2 MB over stdio and up to 5 MB over HTTP, the route PH-Composer serves (issue #458,
    # 2026-11-12), so this keeps a margin over two.
    MAX_BYTES = 2 * 1024 * 1024
    SCHEMA = {
      "type" => "object", "additionalProperties" => false, "required" => %w[mime_type data],
      "description" => "The image itself, base64. An agent connection sends it as an image content block " \
                       "beside this result instead of inside it.",
      "properties" => { "mime_type" => { "type" => "string", "enum" => MIME_TYPES },
                        "data" => { "type" => "string", "description" => "The image's bytes, base64." } }
    }.freeze

    module_function

    def of(bytes, mime_type: "image/png")
      { "mime_type" => mime_type, "data" => Base64.strict_encode64(bytes) }
    end

    # The decoded size of padded base64 `data`, from its length alone: three bytes per four characters, less
    # one per trailing `=`.
    def decoded_bytes(data)
      (data.bytesize / 4 * 3) - data[-2, 2].to_s.count("=")
    end
  end
end
