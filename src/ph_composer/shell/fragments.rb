# frozen_string_literal: true

require "digest"
require "json"
require_relative "pages"

module PhComposer
  # Exact retrieval of one value larger than a reply (context/AGENT_INTERFACE.md, "Focused reads"). A read
  # answers the value's canonical JSON text (CanonicalJson) in fragments a caller joins in order and parses:
  # each fragment is whole UTF-8 characters, at most MAX_TEXT_BYTES once escaped as a JSON string, so one
  # fragment and its envelope fit Pages::REPLY_BYTES. Every fragment carries the whole text's size and
  # SHA-256, so the joined text is checked, not trusted. The cursor is a Pages cursor: it binds the session,
  # the query, the filter and what the value was read at (`revision:`), and carries the text's digest, so a
  # fragment of a changed value refuses instead of joining two versions, even when what it was read at did
  # not change. Nothing is retained between fragments; each read recomputes the value.
  module Fragments
    MAX_TEXT_BYTES = 12 * 1024
    ENCODING = "json"

    FRAGMENT = SchemaShapes.object({
      "encoding" => { "type" => "string", "enum" => [ENCODING],
                      "description" => "The fragments joined in order are the value's canonical JSON text." },
      "offset" => { "type" => "integer", "minimum" => 0,
                    "description" => "Where this fragment starts, in UTF-8 bytes of the whole text." },
      "bytes" => { "type" => "integer", "minimum" => 0, "description" => "This fragment's length in UTF-8 bytes." },
      "total_bytes" => { "type" => "integer", "minimum" => 0, "description" => "The whole text's UTF-8 length." },
      "sha256" => { "type" => "string", "description" => "SHA-256 of the whole text's UTF-8 bytes, hex." },
      "text" => { "type" => "string", "description" => "This fragment: whole characters, never a split one." }
    }).freeze
    SUMMARY = SchemaShapes.object({ "bytes" => { "type" => "integer", "minimum" => 0 },
                                    "sha256" => { "type" => "string" } }).freeze
    MAX_PATH = 32
    TYPE = { "type" => "string", "enum" => %w[object array string number boolean null],
             "description" => "The JSON type of the value at path; a stored null or false is a value." }.freeze

    # A detail read's `path` param: keys and indexes into one public view, starting at one of `parts`.
    def self.path_param(parts, example)
      { "type" => "array", "minItems" => 1, "maxItems" => MAX_PATH, "items" => { "type" => %w[string integer] },
        "description" => "Keys and array indexes into the view, starting at #{parts.join(', ')}: #{example}." }
    end

    module_function

    # The canonical text's size and digest, which a compact row gives in place of the value.
    def summary(value)
      text = CanonicalJson.generate(value)
      { "bytes" => text.bytesize, "sha256" => Digest::SHA256.hexdigest(text) }
    end

    # [fragment, next_cursor] of `value` for `request`'s cursor: the first fragment without one.
    def read(request, query, value, revision: request.revision)
      text = CanonicalJson.generate(value)
      digest = Digest::SHA256.hexdigest(text)
      offset = start(Pages.position(request, query, revision), text, digest)
      piece = cut(text, offset)
      finish = offset + piece.bytesize
      next_cursor = finish < text.bytesize ? Pages.token(request, query, [finish, digest], revision) : nil
      [{ "encoding" => ENCODING, "offset" => offset, "bytes" => piece.bytesize, "total_bytes" => text.bytesize,
         "sha256" => digest, "text" => piece }, next_cursor]
    end

    # One detail answer: the JSON type of the value `path` names in `view` and its fragment for `request`'s
    # cursor. `parts` are the top-level keys a caller may start at; the path is not echoed, since a long key
    # would crowd the reply.
    def detail(request, query, view, path, parts:, revision: request.revision)
      raise CodedError.new("params.invalid", "A path starts at #{parts.join(', ')}.") unless parts.include?(path.first)

      value = at(view, path)
      fragment, next_cursor = read(request, query, value, :revision => revision)
      { "type" => json_type(value), "fragment" => fragment, "next_cursor" => next_cursor }
    end

    # The value `path` names in `view`; a key or index naming nothing refuses, so absent is never null.
    def at(view, path)
      path.each_with_index.reduce(view) do |value, (step, index)|
        found = value.is_a?(Hash) && step.is_a?(String) && value.key?(step)
        found ||= value.is_a?(Array) && step.is_a?(Integer) && step.between?(0, value.length - 1)
        unless found
          raise CodedError.new("target.not_found", "Nothing is stored at #{JSON.generate(path[0..index])[0, 200]}.")
        end

        value[step]
      end
    end

    def json_type(value)
      case value
      when Hash then "object"
      when Array then "array"
      when String then "string"
      when Numeric then "number"
      when true, false then "boolean"
      else "null"
      end
    end

    # A cursor's offset is one this text issued: inside it and on a character boundary. A cursor issued
    # for other text (a value that is computed afresh each time and came out different) has expired.
    def start(after, text, digest)
      return 0 if after.nil?

      offset, issued = after if after.is_a?(Array) && after.length == 2
      unless offset.is_a?(Integer) && offset.positive? && issued.is_a?(String)
        raise CodedError.new("params.invalid", "That cursor is not one this query issued.")
      end
      unless issued == digest
        raise CodedError.new("query.cursor_expired", "The value changed since the previous fragment; start " \
                                                     "again from the first fragment.")
      end
      unless offset < text.bytesize && text.byteslice(0, offset).valid_encoding?
        raise CodedError.new("params.invalid", "That cursor is not one this query issued.")
      end

      offset
    end

    # The longest run of whole characters from `offset` whose escaped form fits MAX_TEXT_BYTES. Escaping
    # only lengthens text, so it starts at the budget in raw bytes and shrinks in proportion until it fits.
    def cut(text, offset)
      length = [text.bytesize - offset, MAX_TEXT_BYTES].min
      loop do
        piece = whole_characters(text, offset, length)
        escaped = JSON.generate(piece).bytesize - 2
        return piece if escaped <= MAX_TEXT_BYTES

        length = [piece.bytesize * MAX_TEXT_BYTES / escaped, piece.bytesize - 1].min
      end
    end

    # The bytes from `offset`, shortened to end on a character boundary. A UTF-8 character is at most four
    # bytes, so at most three come off; one whole character always remains.
    def whole_characters(text, offset, length)
      length = [length, 1].max
      piece = text.byteslice(offset, length)
      piece = text.byteslice(offset, length -= 1) until piece.valid_encoding? || length <= 1
      piece = text.byteslice(offset, length += 1) until piece.valid_encoding?
      piece
    end
    private_class_method :start, :cut, :whole_characters
  end
end
