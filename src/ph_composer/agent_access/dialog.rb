# frozen_string_literal: true

require "digest"
require "json"

module PhComposer
  module AgentAccess
    # The Agent Access dialog: the native place where the user issues, reads and revokes agent tokens.
    # It is its own HtmlDialog, separate from the panel, so issuing or revoking never touches a draft
    # open there, and it needs no open panel. Its callbacks run on the main thread and reach Tokens
    # directly; nothing here is registered with PhComposer::API.
    #
    # Every message is `{"type": ..., "payload": {...}}`, as the panel's are, on its own callback.
    module Dialog
      PAGE = File.join(__dir__, "..", "html", "agent_access", "index.html")
      CALLBACK = "ph_composer_agent_access"
      TITLE = "#{EXTENSION_NAME} Agent Access".freeze
      INBOUND = {
        "access.ready" => [],
        "access.issue" => %w[label capabilities model_only],
        "access.revoke" => %w[id],
        "access.reset" => [],
        "access.port" => %w[port],
        "access.connect" => %w[client token profile replace],
        "access.repair" => %w[client profile]
      }.freeze
      OUTBOUND = {
        "access.state" => %w[state tokens offered server model connections],
        "access.issued" => %w[token row clients],
        "access.failure" => %w[message],
        "access.revoked" => %w[id summary],
        "access.connected" => %w[client profile state message setup],
        "access.replacement" => %w[client profile token]
      }.freeze
      DEFAULT_PROFILE = Connections::DEFAULT_PROFILE

      class << self
        def show
          if @dialog
            @dialog.bring_to_front
          else
            @dialog = build_dialog
            @dialog.show
          end
          @dialog
        end

        def open?
          !@dialog.nil?
        end

        # Republishes the token list to an open dialog; Tokens calls this through
        # AgentAccess.tokens_changed after every write.
        def refresh
          publish("access.state", state) if @dialog
        end

        def reset_for_test
          @dialog&.close
          @dialog = nil
        end

        # The type and payload of one message from the page; raises UserError when it is not one.
        def parse(raw)
          message = JSON.parse(raw.to_s)
          raise UserError, "The Agent Access message is not an object." unless message.is_a?(Hash)

          type = message["type"]
          payload = message.fetch("payload", {})
          raise UserError, "The Agent Access message type #{type.inspect} is not accepted." unless INBOUND.key?(type)
          raise UserError, "The #{type} payload must be an object." unless payload.is_a?(Hash)

          stray = payload.keys - INBOUND.fetch(type)
          raise UserError, "The #{type} payload carries #{stray.join(', ')}." unless stray.empty?

          [type, payload]
        rescue JSON::ParserError
          raise UserError, "The Agent Access message is not JSON."
        end

        # The script that delivers one message to the page.
        def script(type, payload)
          declared = OUTBOUND.fetch(type) { raise ArgumentError, "#{type} is not an outbound Agent Access message." }
          stray = payload.keys - declared
          raise ArgumentError, "#{type} does not declare #{stray.join(', ')}." unless stray.empty?

          "PhComposerUI.get(\"agent_access/page\").receive(#{JSON.generate('type' => type, 'payload' => payload)})"
        end

        # What the page shows: every token with its latest call since SketchUp started and the connections
        # that use it, the saved connections, and the listener.
        def state
          calls = Listener.last_calls
          server = AgentAccess.server_status
          rows = connections(server["port"])
          tokens = Tokens.list.map do |row|
            row.merge("last_call" => calls[row["id"]], "connected" => connection_names(rows, row["id"]))
          end
          { "state" => Tokens.state, "tokens" => tokens, "offered" => Tokens::OFFERED, "server" => server,
            "model" => active_model, "connections" => rows }
        end

        # Every connection profile a saved file or a client entry names (Connections), each with the live
        # token bound to it and where that binding is kept, what the client's file says of the entry, whether
        # a client has contacted and verified with that token since SketchUp started, and the token-free
        # setup to run or paste. Never a token (context/AGENT_INTERFACE.md, "User-controlled local access").
        def connections(port)
          live = Tokens.snapshot
          contacts = Listener.contacts
          verified = Listener.verified
          profiles.map do |client, profile|
            entry, source, digest = bound(client, profile, port, live)
            token = digest && live.fetch(digest)
            saved = live[Connections.digest(client, profile)]
            { "client" => client, "client_name" => Connections::CLIENTS.fetch(client), "profile" => profile,
              "server" => ClientConfig.server_name(profile), "token" => token && bound_token(token),
              "source" => source, "saved_token" => saved && bound_token(saved), "entry" => entry["setup"],
              "contacted" => token && contacts[token["id"]], "verified_at" => token && verified[token["id"]],
              "setup" => ClientConfig.setup_text(client, port, profile) }
          end
        end

        # The profiles of saved files and of the clients' own entries, by client, the default first.
        def profiles
          saved = Connections.saved.map { |row| row.values_at("client", "profile") }
          named = Connections::CLIENTS.keys.flat_map do |client|
            ClientSetup.server_names(client).filter_map do |name|
              profile = name == ClientConfig::SERVER_NAME ? DEFAULT_PROFILE : name.delete_prefix("ph-composer-")
              [client, profile] if profile == DEFAULT_PROFILE || profile.match?(Connections::PROFILE)
            end
          end
          (saved | named).sort_by { |client, profile| [client, profile == DEFAULT_PROFILE ? 0 : 1, profile] }
        end

        # A bound token as a connection row shows it: its public facts and, for a Model-only token, whether
        # its Model is open, so a row can say why the client reaches nothing.
        def bound_token(token)
          row = token.slice("id", "label", "capabilities", "model_name")
          return row unless token["model_name"]

          row.merge("model_open" => Sessions.all.any? { |session| Tokens.serves?(token, session) })
        end

        # The Model a token issued now would be bound to for "this Model only": its file name and an opaque
        # key the page sends back, so a token is bound only to the Model the user saw; null when it has
        # never been saved. The path itself stays in Ruby.
        def active_model
          path = Sketchup.active_model&.path.to_s
          path.empty? ? nil : { "name" => File.basename(path), "key" => model_key(path) }
        end

        # The connections bound to one token, as the token list names them: the client, and the profile
        # when it is not the default.
        def connection_names(rows, token_id)
          rows.select { |row| row.dig("token", "id") == token_id }.map do |row|
            row["profile"] == DEFAULT_PROFILE ? row["client_name"] : "#{row['client_name']} (#{row['profile']})"
          end
        end

        def model_key(path)
          Digest::SHA256.hexdigest("ph_composer.agent_access.model:#{path}")[0, 24]
        end

        private

        def build_dialog
          dialog = UI::HtmlDialog.new(
            :dialog_title => TITLE, :preferences_key => "#{EXTENSION_ID}.agent_access", :scrollable => true,
            :resizable => true, :width => 560, :height => 600, :min_width => 360, :min_height => 420,
            :style => UI::HtmlDialog::STYLE_DIALOG
          )
          dialog.set_file(PAGE)
          # Bound to this dialog: a message from a page that has since closed is ignored.
          dialog.add_action_callback(CALLBACK) { |_context, raw| receive(dialog, raw) }
          dialog.set_on_closed { @dialog = nil if @dialog.equal?(dialog) }
          dialog
        end

        def receive(dialog, raw)
          return unless @dialog.equal?(dialog)

          handle(*parse(raw))
        rescue UserError => error
          # A CodedError is a refusal the user can act on; anything else is a malformed page message.
          publish("access.failure", "message" => error.message)
          refresh
        rescue StandardError => error
          Diagnostics.exception("agent_access_message", error)
          publish("access.failure", "message" => "Agent Access could not complete that request.")
        end

        def handle(type, payload)
          case type
          when "access.ready" then refresh
          when "access.issue" then issue(payload)
          when "access.revoke" then revoke(payload["id"])
          when "access.reset" then Tokens.reset
          when "access.port"
            Listener.port = payload["port"]
            refresh
          when "access.connect" then connect(payload)
          when "access.repair" then repair(payload["client"], payload.fetch("profile", DEFAULT_PROFILE))
          end
        end

        # A token is shown only with setup for a port that is listening. If the port was taken in the
        # moment between the form and the issue, the token is revoked at once and the user is told to
        # choose another port, rather than handed setup for a port nothing listens on.
        def issue(payload)
          model_file = payload["model_only"] ? shown_model(payload["model_only"]) : nil
          issued = Tokens.issue(:label => payload["label"], :capabilities => payload.fetch("capabilities", []),
                                :model_file => model_file)
          status = Listener.status
          unless status["state"] == "listening"
            Tokens.revoke(issued.dig("row", "id"))
            return publish("access.failure", "message" => "#{status['message'] || 'PH-Composer could not listen.'} " \
                                                          "The token was not kept; create it again once the " \
                                                          "connection is listening.")
          end

          clients = ClientConfig.for(:port => status["port"], :token => issued.fetch("token"))
          publish("access.issued", issued.merge("clients" => clients))
        end

        # The active Model's path when it is still the one the form showed, whose key the page sent back.
        def shown_model(key)
          path = Sketchup.active_model&.path.to_s
          return path if path.empty? || key == model_key(path)

          refresh
          raise CodedError.new("agent_access.model_changed", "The open Model changed since this form showed it. " \
                                                             "Check This Model only again and create the token.")
        end

        # Saves the token the page holds for one client's profile and sets the client up to read it. The page
        # sends the token back because nothing in Ruby keeps it; only a live token is saved, and only while the
        # listener runs, so the setup names a port something listens on. A profile another live token holds is
        # changed only when `replace` names that token, the one the page showed: otherwise nothing is
        # written and the page is told which token Connect would replace.
        def connect(payload)
          client = payload["client"]
          profile = Connections.checked_profile(payload.fetch("profile", DEFAULT_PROFILE))
          name = client_name(client)
          token = payload["token"]
          unless token.is_a?(String) && Tokens.snapshot.key?(Tokens.digest(token))
            raise CodedError.new("agent_access.token_unknown", "This token is no longer live. Create another " \
                                                               "to connect #{name}.")
          end
          port = listening_port(name)
          held = binding(client, profile, port)
          if replacing?(held, token, payload["replace"])
            if payload["replace"].nil?
              return publish("access.replacement", "client" => client, "profile" => profile, "token" => held)
            end

            refresh
            raise CodedError.new("agent_access.connection_changed", "This connection changed since it was shown: " \
                                                                    "it now uses #{held['label']}. Check it and " \
                                                                    "connect again.")
          end

          answer = ClientSetup.connect(client, token, port, :profile => profile)
          publish("access.connected",
                  answer.merge("client" => client, "profile" => profile, "setup" => answer["setup"]))
          refresh
        end

        # Whether Connect would replace another live token the page did not name.
        def replacing?(held, token, replace)
          !held.nil? && held["id"] != Tokens.snapshot.dig(Tokens.digest(token), "id") && held["id"] != replace
        end

        # Sets a saved connection's client up again with the token its file already holds, which never leaves
        # Ruby or the file.
        def repair(client, profile)
          name = client_name(client)
          answer = ClientSetup.repair(client, listening_port(name), :profile => Connections.checked_profile(profile))
          publish("access.connected",
                  answer.merge("client" => client, "profile" => profile, "setup" => answer["setup"]))
          refresh
        end

        # The live token a profile is bound to, by its saved file or by a token its client entry carries
        # itself, as its public row; nil when none is live.
        def binding(client, profile, port)
          live = Tokens.snapshot
          digest = bound(client, profile, port, live).last
          digest && Tokens.public_row(live.fetch(digest))
        end

        # The client entry's state, and the live token the client uses for the profile: the one its entry
        # carries inline while it does, since a token saved for the profile is then only waiting for its
        # setup; otherwise the saved file's. Answers `[entry, source, digest]`, source and digest nil when
        # no live token is bound.
        def bound(client, profile, port, live)
          entry = ClientSetup.entry(client, port, profile)
          inline = entry["inline_digest"]
          return [entry, "inline", inline] if entry["setup"] == "inline" && live.key?(inline)

          file = Connections.digest(client, profile)
          live.key?(file) ? [entry, "file", file] : [entry, nil, nil]
        end

        def client_name(client)
          Connections::CLIENTS.fetch(client) { raise UserError, "#{client.to_s[0, 40].inspect} is not a client." }
        end

        def listening_port(name)
          status = Listener.status
          return status["port"] if status["state"] == "listening"

          raise CodedError.new("agent_access.not_listening", "PH-Composer is not listening, so #{name} could " \
                                                             "not connect. #{status['message']}".strip)
        end

        # The revoke takes effect here, on the main thread, before the next call is run; the page shows
        # what the token's exports had done.
        def revoke(id)
          Tokens.revoke(id)
          publish("access.revoked", "id" => id, "summary" => AgentAccess.acknowledgment(id))
        end

        def publish(type, payload)
          @dialog&.execute_script(script(type, payload))
        end
      end
    end
  end
end
