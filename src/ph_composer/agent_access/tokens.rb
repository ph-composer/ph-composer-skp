# frozen_string_literal: true

require "digest"
require "json"
require "securerandom"
require "time"

module PhComposer
  module AgentAccess
    # The agent access tokens issued on this machine (context/AGENT_INTERFACE.md, "User-controlled
    # local access"). A token is the connection: a label, the capabilities chosen when it was issued
    # and a revoke control. The store keeps only the token's SHA-256; the token itself is returned once,
    # to the Agent Access dialog that issued it, and never stored, logged or offered through
    # PhComposer::API, so no grant lets an agent list, issue or revoke one.
    #
    # Machine state read on every call, like ApprovedLocations, whose storage shape this copies: base64
    # JSON in SketchUp's defaults, a byte cap, an unreadable store reported and never silently replaced.
    # A revoked token stays as a row with `revoked_at`, so the dialog can show when it was revoked.
    #
    # A token issued for "this Model only" also keeps the saved Model's file path, plaintext as approved
    # locations keep theirs, and serves only a session of a Model at that path; Save As moves it with the
    # Model (AgentAccess.saved). The path never leaves the
    # store and the ingress: a public row carries only its file name, as `model_name`.
    module Tokens
      SECTION = "ph_composer.agent_access"
      KEY = "tokens"
      MAX_LIVE = 8
      MAX_REVOKED = 32
      MAX_STORED_BYTES = 64 * 1024
      LABEL_LENGTH = 80
      DEFAULT_LABEL = "Agent token"
      # What a token may be issued with: every capability dispatch enforces, each with its consent copy
      # in the dialog. Every token holds `read`.
      OFFERED = CallerRegistry::CAPABILITIES
      PUBLIC_KEYS = %w[id label capabilities created_at last_used_at revoked_at].freeze
      ROW_KEYS = (PUBLIC_KEYS + ["token_sha256"]).freeze
      MODEL_FILE = "model_file"
      MAX_PATH = 4096
      UNREADABLE = "The agent tokens stored on this machine cannot be read. Reset them before issuing another; " \
                   "every agent must then be given a new token."

      module_function

      # "readable" (including nothing stored yet) or "unreadable".
      def state
        stored.fetch("state")
      end

      # Every token, live and revoked, without its digest: live ones newest issued first, then revoked ones
      # newest revoked first.
      def list
        live, revoked = rows.partition { |row| row["revoked_at"].nil? }
        (live.reverse + revoked.reverse).map { |row| public_row(row) }
      end

      # Issues a token and returns `{"token" => secret, "row" => public row}`. The secret is not kept.
      # `model_file`, a saved Model's path, binds the token to that Model only.
      def issue(label: nil, capabilities: %w[read], model_file: nil)
        current = writable
        granted = checked_capabilities(capabilities)
        checked_model_file(model_file) if model_file
        live = current.count { |row| row["revoked_at"].nil? }
        if live >= MAX_LIVE
          raise CodedError.new("agent_access.limit", "This machine already has #{MAX_LIVE} live agent tokens. " \
                                                     "Revoke one before issuing another.")
        end

        token = SecureRandom.hex(24)
        row = { "id" => Records::Identity.mint("token"), "label" => label ? checked_label(label) : next_label(current),
                "capabilities" => granted, "created_at" => now, "last_used_at" => nil, "revoked_at" => nil,
                "token_sha256" => digest(token) }
        row[MODEL_FILE] = model_file if model_file
        save(current + [row])
        { "token" => token, "row" => public_row(row) }
      end

      # Ends a token for good. Revoking an already revoked token changes nothing.
      def revoke(id)
        current = writable
        row = current.find { |item| item["id"] == id }
        unless row
          raise CodedError.new("agent_access.token_unknown", "There is no agent token #{id.to_s[0, 40].inspect}.")
        end
        return list if row["revoked_at"]

        # Moved to the end, so revoked rows are stored in the order they were revoked.
        save(current.reject { |item| item.equal?(row) } + [row.merge("revoked_at" => now)])
        list
      end

      # Moves every live token bound to `from` onto `to`: the Model saved there with Save As is the same
      # document. Writes only when a token moved, so a save at the same path changes nothing.
      def follow(from, to)
        current = writable
        moved = current.map do |row|
          row["revoked_at"].nil? && row[MODEL_FILE] == from ? row.merge(MODEL_FILE => to) : row
        end
        return if moved == current

        checked_model_file(to)
        save(moved)
      end

      # Replaces an unreadable store with an empty one; a readable store is left as it is.
      def reset
        save([]) if state == "unreadable"
        list
      end

      # Whether any token is live; the listener runs only while one is.
      def live?
        rows.any? { |row| row["revoked_at"].nil? }
      end

      # The live tokens by the hex SHA-256 of their secret, each with its public row and any Model file it
      # is bound to, frozen. The ingress compares a presented token's digest against these keys and touches
      # nothing else.
      def snapshot
        rows.select { |row| row["revoked_at"].nil? }
            .to_h { |row| [row.fetch("token_sha256"), public_row(row).merge(row.slice(MODEL_FILE))] }
            .then { |table| DeepCopy.frozen(table) }
      end

      # Whether a token (a snapshot row) may act on `session`: any session, or only one whose Model is
      # saved at the path the token was bound to.
      def serves?(token, session)
        bound = token[MODEL_FILE]
        bound.nil? || session.model.path.to_s == bound
      end

      def digest(token)
        Digest::SHA256.hexdigest(token.to_s)
      end

      def public_row(row)
        public = row.slice(*PUBLIC_KEYS)
        row[MODEL_FILE] ? public.merge("model_name" => File.basename(row[MODEL_FILE])) : public
      end

      def checked_capabilities(capabilities)
        granted = Array(capabilities).map(&:to_s).uniq
        unless granted.include?("read") && (granted - OFFERED).empty?
          raise CodedError.new("params.invalid", "A token holds read and may add only #{OFFERED.join(', ')}.")
        end

        CallerRegistry::CAPABILITIES.select { |name| granted.include?(name) }
      end

      def checked_model_file(path)
        return if path.is_a?(String) && !path.empty? && path.length <= MAX_PATH

        raise CodedError.new("agent_access.model_unsaved", "Save this Model first: a token can be bound only to " \
                                                           "a Model that has a file.")
      end

      def checked_label(label)
        text = label.to_s.strip
        return text if !text.empty? && text.length <= LABEL_LENGTH

        raise CodedError.new("params.invalid", "A token label is 1 to #{LABEL_LENGTH} characters.")
      end

      # "Agent token N", one past the highest such label still listed.
      def next_label(current)
        numbers = current.map { |row| row["label"].to_s[/\A#{DEFAULT_LABEL} (\d+)\z/, 1].to_i }
        "#{DEFAULT_LABEL} #{(numbers.max || 0) + 1}"
      end

      def now
        Time.now.utc.iso8601
      end

      def rows
        stored.fetch("tokens")
      end

      # The rows, refusing when the stored blob cannot be read: it is reported, never silently replaced.
      def writable
        store = stored
        raise CodedError.new("agent_access.store_unreadable", UNREADABLE) if store.fetch("state") == "unreadable"

        store.fetch("tokens")
      end

      # A store over the byte cap is unreadable rather than readable-but-unsavable, so Reset can recover it.
      def stored
        raw = Sketchup.read_default(SECTION, KEY, nil)
        return { "state" => "readable", "tokens" => [] } if raw.nil?
        return unreadable unless raw.is_a?(String) && raw.bytesize <= MAX_STORED_BYTES * 2

        text = raw.unpack1("m0")
        return unreadable if text.bytesize > MAX_STORED_BYTES

        document = JSON.parse(text)
        valid?(document) ? { "state" => "readable", "tokens" => document.fetch("tokens") } : unreadable
      rescue JSON::ParserError, ArgumentError, EncodingError
        unreadable
      end

      def unreadable
        { "state" => "unreadable", "tokens" => [] }
      end

      # Every row well formed, and no id or digest twice: a duplicate could leave a digest live that no
      # revoke reaches.
      def valid?(document)
        return false unless document.is_a?(Hash) && document["tokens"].is_a?(Array)

        tokens = document["tokens"]
        tokens.all? { |row| valid_row?(row) } && tokens.map { |row| row["id"] }.uniq.length == tokens.length &&
          tokens.map { |row| row["token_sha256"] }.uniq.length == tokens.length
      end

      # Exactly the stored keys, a Model file only when bound: a row missing `revoked_at` would otherwise
      # read as live.
      def valid_row?(row)
        row.is_a?(Hash) && (row.keys - [MODEL_FILE]).sort == ROW_KEYS.sort &&
          (!row.key?(MODEL_FILE) || row[MODEL_FILE].is_a?(String) && !row[MODEL_FILE].empty?) &&
          row["id"].to_s.match?(Records::Identity.pattern("token")) && row["label"].is_a?(String) &&
          row["label"].length.between?(1, LABEL_LENGTH) && row["token_sha256"].to_s.match?(/\A\h{64}\z/) &&
          row["capabilities"].is_a?(Array) && row["capabilities"].include?("read") &&
          (row["capabilities"] - CallerRegistry::CAPABILITIES).empty? && row["created_at"].is_a?(String) &&
          %w[last_used_at revoked_at].all? { |key| row[key].nil? || row[key].is_a?(String) }
      end

      # Keeps every live token and the MAX_REVOKED most recently revoked ones (revoke stores rows in the
      # order they were revoked), fewer when the bytes need it, so a revoke always fits; then tells the
      # listener.
      def save(current)
        live, revoked = current.partition { |row| row["revoked_at"].nil? }
        revoked = revoked.last(MAX_REVOKED)
        text = serialized(current, live + revoked)
        while text.bytesize > MAX_STORED_BYTES && !revoked.empty?
          revoked = revoked.drop(1)
          text = serialized(current, live + revoked)
        end
        write(text)
      end

      def serialized(current, kept)
        rows = current.select { |row| kept.include?(row) }.map { |row| row.slice(*ROW_KEYS, MODEL_FILE) }
        JSON.generate("tokens" => rows)
      end

      def write(text)
        if text.bytesize > MAX_STORED_BYTES
          raise CodedError.new("agent_access.store_unavailable", "Agent tokens exceed their storage limit. " \
                                                                 "Revoke some first.")
        end
        unless Sketchup.write_default(SECTION, KEY, [text].pack("m0"))
          raise CodedError.new("agent_access.store_unavailable", "Agent tokens could not be saved.")
        end

        AgentAccess.tokens_changed
      end
    end
  end
end
