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
        "access.connect" => %w[client token]
      }.freeze
      OUTBOUND = {
        "access.state" => %w[state tokens offered server model],
        "access.issued" => %w[token row clients],
        "access.failure" => %w[message],
        "access.revoked" => %w[id summary],
        "access.connected" => %w[client state message]
      }.freeze

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

        # What the page shows: every token with its latest call since SketchUp started and the clients
        # connected with it, and the listener.
        def state
          calls = Listener.last_calls
          connected = connected_clients
          tokens = Tokens.list.map do |row|
            row.merge("last_call" => calls[row["id"]], "connected" => connected.fetch(row["id"], []))
          end
          { "state" => Tokens.state, "tokens" => tokens, "offered" => Tokens::OFFERED,
            "server" => AgentAccess.server_status, "model" => active_model }
        end

        # The Model a token issued now would be bound to for "this Model only": its file name and an opaque
        # key the page sends back, so a token is bound only to the Model the user saw; null when it has
        # never been saved. The path itself stays in Ruby.
        def active_model
          path = Sketchup.active_model&.path.to_s
          path.empty? ? nil : { "name" => File.basename(path), "key" => model_key(path) }
        end

        # The names of the clients whose saved token is each live token, by token id.
        def connected_clients
          ids = Tokens.snapshot.transform_values { |row| row.fetch("id") }
          Connections.digests.each_with_object({}) do |(client, digest), by_id|
            (by_id[ids[digest]] ||= []) << Connections::CLIENTS.fetch(client) if ids.key?(digest)
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
          when "access.connect" then connect(payload["client"], payload["token"])
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

        # Saves the token the page holds for one client and sets the client up to read it. The page sends the
        # token back because nothing in Ruby keeps it; only a live token is saved, and only while the
        # listener runs, so the setup names a port something listens on.
        def connect(client, token)
          name = Connections::CLIENTS.fetch(client) do
            raise UserError, "#{client.to_s[0, 40].inspect} is not a client."
          end
          unless token.is_a?(String) && Tokens.snapshot.key?(Tokens.digest(token))
            raise CodedError.new("agent_access.token_unknown", "This token is no longer live. Create another " \
                                                               "to connect #{name}.")
          end
          status = Listener.status
          unless status["state"] == "listening"
            raise CodedError.new("agent_access.not_listening", "PH-Composer is not listening, so #{name} could " \
                                                               "not connect. #{status['message']}".strip)
          end

          publish("access.connected", ClientSetup.connect(client, token, status["port"]).merge("client" => client))
          refresh
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
