# frozen_string_literal: true

require "socket"

module PhComposer
  module AgentAccess
    # Whether the loopback Server runs, and on which port. It runs while at least one agent token is
    # live: the first issued token starts it, the last revoke stops it, and every token store write hands
    # it the new snapshot. Main thread only.
    module Listener
      PORT_KEY = "agent_access.port"
      PORTS = (1024..65_535).freeze

      # Builds the Server for a port. The offline suite replaces it so no test binds the agent port.
      DEFAULT_FACTORY = lambda do |port|
        Server.new(:port => port, :protocol => MCP, :executor => Executor.new(:tools => Tools::TABLE),
                   :on_calls => ->(rows) { Listener.calls_made(rows) })
      end

      class << self
        attr_writer :server_factory

        # A revoke answers the token's waiting calls first; when it ended the last live token, the listener
        # stops on its next tick, once those answers are written.
        def refresh
          @server = nil if @server&.stopped?
          snapshot = Tokens.snapshot
          live = snapshot.values.map { |row| row.fetch("id") }
          answered = @server ? @server.refuse_revoked(live) : {}
          AgentAccess.drop_bindings(live)
          if snapshot.empty?
            running = !@server.nil?
            answered.empty? ? stop : @server.stop_soon
            Diagnostics.log("agent_access_stopped", "status" => "no_live_token") if running
            return answered
          end

          start unless @server
          @server&.tokens = snapshot
          answered
        end

        def stop
          @server&.stop
          @server = nil
          @failure = nil
        end

        # Stops the listener and forgets every token's latest call: a fresh process.
        def reset
          stop
          @last_calls = {}
        end

        # The dialog's status line: listening on a port, stopped with no live token, or unable to bind,
        # which a stopped listener checks too so a taken port shows before the first token is issued.
        def status
          @server = nil if @server&.stopped?
          return { "state" => "listening", "port" => @server.port } if @server

          failure = @failure || (port_free? ? nil : in_use)
          return { "state" => "unavailable", "port" => port, "message" => failure } if failure

          { "state" => "stopped", "port" => port }
        end

        # The port from SketchUp's defaults, or the default port when none valid is stored.
        def port
          stored = Sketchup.read_default(Preferences::SECTION, PORT_KEY, Server::DEFAULT_PORT)
          stored.is_a?(Integer) && PORTS.cover?(stored) ? stored : Server::DEFAULT_PORT
        end

        def server
          @server
        end

        # Stores a new port and moves a running or failed listener onto it. Raises CodedError for a port
        # outside 1024 to 65535.
        def port=(value)
          unless value.is_a?(Integer) && PORTS.cover?(value)
            raise CodedError.new("params.invalid", "A port is a whole number from #{PORTS.min} to #{PORTS.max}.")
          end

          Sketchup.write_default(Preferences::SECTION, PORT_KEY, value)
          stop
          refresh
        end

        # Each token's latest call since SketchUp started, by token id: its time and how it ended. Kept
        # here rather than read from the server's recent-call ring, so neither another token's calls nor a
        # port change loses it.
        def last_calls
          (@last_calls ||= {}).dup
        end

        # Called by the server on the main thread with the calls its pump just finished.
        def calls_made(rows)
          calls = (@last_calls ||= {})
          rows.each do |row|
            calls.delete(row["token"])
            calls[row["token"]] = { "at" => row["at"], "status" => row["error"] ? "error" : row["status"] }
          end
          # Kept for every token the store still lists (at most its live and revoked rows), however many
          # other tokens called since.
          listed = Tokens.list.map { |row| row["id"] }
          calls.select! { |token, _call| listed.include?(token) }
          Dialog.refresh
        end

        private

        def port_free?
          TCPServer.new("127.0.0.1", port).close
          true
        rescue SystemCallError
          false
        end

        def in_use
          "Port #{port} is in use by another program. Choose another port below."
        end

        def start
          @failure = nil
          @server = (@server_factory || DEFAULT_FACTORY).call(port).start
          Diagnostics.log("agent_access_listening", "status" => "ok")
        rescue SystemCallError => error
          @server = nil
          @failure = error.is_a?(Errno::EADDRINUSE) ? in_use : error.message
          Diagnostics.log("agent_access_listening", "status" => "failed", "error_class" => error.class.name)
        end
      end
    end
  end
end
