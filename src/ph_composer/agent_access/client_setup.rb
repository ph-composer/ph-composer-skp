# frozen_string_literal: true

require "json"
require "open3"

module PhComposer
  module AgentAccess
    # Connect: saves a token for one client (Connections) and sets that client up, once, to read it from
    # there (context/AGENT_INTERFACE.md, "Security posture"). Neither step puts the token on a command
    # line or in the client's settings, and a client already set up is left as it is, so connecting again
    # with a new token changes only the file.
    #
    # Claude Code is set up with its own `claude mcp add-json`, run without a shell from an absolute path
    # in a fixed list, unless its settings already hold the same entry. Codex has no command that sets a
    # header helper and its `codex mcp add` rewrites the whole file, so the block is appended to
    # ~/.codex/config.toml, which is left untouched when it names the server anywhere. When a step cannot
    # be done the token is still saved and the answer says what to run or paste by hand; the dialog shows
    # that text. macOS only: the helper is `/bin/cat`.
    module ClientSetup
      SERVER = ClientConfig::SERVER_NAME
      # For the whole of one Connect, every command it runs together: SketchUp waits on it.
      TIMEOUT = 20
      MAX_OUTPUT = 4096
      MAX_SETTINGS = 64 * 1024 * 1024
      CLAUDE_CANDIDATES = ["~/.local/bin/claude", "/opt/homebrew/bin/claude", "/usr/local/bin/claude",
                           "~/.claude/local/claude"].freeze
      # The server's own table or one below it, such as its tool settings.
      SERVER_KEY = /(?:\A|[\s.\[{,])["']?ph-composer["']?\s*[.=\]]/.freeze
      SERVER_TABLE_HEADER = /\A\s*\[\s*mcp_servers\s*\.[^\[\]]+\]\s*(?:#.*)?\z/.freeze
      CODEX_TABLE = /\A\s*\[\s*mcp_servers\s*\.\s*(?:ph-composer|"ph-composer"|'ph-composer')\s*[\].]/.freeze

      class << self
        # The offline suite replaces the command runner, the time limit and the clients' files; no test runs
        # a client it did not write.
        attr_writer :runner, :codex_home, :claude_settings, :timeout

        def codex_home
          @codex_home || File.join(Dir.home, ".codex")
        end

        def claude_settings
          @claude_settings || File.join(Dir.home, ".claude.json")
        end

        def timeout
          @timeout || TIMEOUT
        end

        # Answers `{"state" => "configured" | "manual", "message" => ...}`; the token is saved in both.
        def connect(client, token, port)
          if Gem.win_platform?
            raise CodedError.new("agent_access.connection_unavailable", "Connect works on macOS only. Use a " \
                                                                        "setup with the token below instead.")
          end

          Connections.write(client, token)
          client == "claude_code" ? claude_code(port) : codex(port)
        end

        # The first candidate that is a regular executable file this account or the system owns and nobody
        # else can change.
        def claude_binary
          CLAUDE_CANDIDATES.map { |path| File.expand_path(path) }.find do |path|
            stat = File.stat(path)
            stat.file? && stat.executable? && !stat.world_writable? && (stat.owned? || stat.uid.zero?)
          rescue SystemCallError
            false
          end
        end

        private

        # Adds the server unless Claude Code already has this entry; one of another form is replaced.
        def claude_code(port)
          server = ClientConfig.claude_server(port)
          return configured("Claude Code") if claude_entry?(server)

          binary = claude_binary
          unless binary
            return manual("PH-Composer could not find the claude command. Run the first command below in " \
                          "Terminal once.", "Claude Code")
          end

          deadline = now + timeout
          add = [binary, "mcp", "add-json", "--scope", "user", SERVER, JSON.generate(server)]
          done, output = run(add, deadline)
          return configured("Claude Code") if done
          unless output.include?("already exists")
            return manual("claude mcp add-json did not finish#{first_line(output)}. Run the first command " \
                          "below in Terminal once.", "Claude Code")
          end

          removed, = run([binary, "mcp", "remove", "--scope", "user", SERVER], deadline)
          done, output = run(add, deadline) if removed
          return configured("Claude Code") if done

          manual("Claude Code had an earlier ph-composer entry#{removed ? ', now removed,' : ''} and the new one " \
                 "was not added#{first_line(output)}. Run the first command below in Terminal once.", "Claude Code")
        end

        # Whether Claude Code's user settings already hold this entry, read and never written.
        def claude_entry?(server)
          return false unless File.file?(claude_settings) && File.size(claude_settings) <= MAX_SETTINGS

          entry = JSON.parse(File.read(claude_settings)).dig("mcpServers", SERVER)
          entry.is_a?(Hash) && entry.slice(*server.keys) == server && !entry.key?("headers")
        rescue StandardError
          false
        end

        def codex(port)
          unless File.directory?(codex_home)
            return manual("Codex is not set up on this computer: there is no #{codex_home} folder. Once it is, " \
                          "add the first block below to its config.toml.", "Codex")
          end

          config = File.join(codex_home, "config.toml")
          text = File.file?(config) ? File.binread(config) : +""
          block = ClientConfig.codex_block(port)
          lines = text.dup.force_encoding(Encoding::UTF_8).scrub.lines
          unless names_server?(lines)
            return append(config, text, block) if appendable?(lines)

            return manual("#{config} defines mcp_servers in a form PH-Composer does not add to. Add the first " \
                          "block below to it by hand.", "Codex")
          end
          return configured("Codex") if codex_table(lines) == block.lines.map(&:strip)

          manual("#{config} already names the #{SERVER} server. Set its url and http_headers_helper to the ones " \
                 "in the first block below and remove any other way it is given a token.", "Codex")
        rescue SystemCallError => error
          manual("PH-Composer could not read #{config} (#{error.class.name.split('::').last}). Add the first " \
                 "block below to it.", "Codex")
        end

        # Whether any line that is not a comment has the server's name as a key, in whatever TOML form: a
        # table, a dotted key or an inline table. A config that does is never appended to, since a second
        # definition would make the whole file invalid for Codex. A path that merely contains the name, such
        # as a project folder, is not a key.
        def names_server?(lines)
          lines.any? { |line| !line.lstrip.start_with?("#") && line.match?(SERVER_KEY) }
        end

        # Whether a new `[mcp_servers.ph-composer]` table can follow what the file has: every line that
        # mentions mcp_servers is a plain header of another server's table. An inline or dotted mcp_servers,
        # an `[mcp_servers]` table or an escaped key cannot be extended this way, or could hide the name, so
        # the user adds the block instead.
        def appendable?(lines)
          lines.none? do |line|
            !line.lstrip.start_with?("#") && line.include?("mcp_servers") &&
              (line.include?("\\") || !line.match?(SERVER_TABLE_HEADER))
          end
        end

        # The settings lines of the server's tables, without blank lines and comments; nil when it has none.
        def codex_table(lines)
          start = lines.index { |line| line.match?(CODEX_TABLE) }
          return nil unless start

          table = lines.drop(start + 1).take_while { |line| !line.lstrip.start_with?("[") || line.match?(CODEX_TABLE) }
          ([lines[start]] + table).map(&:strip).reject { |line| line.empty? || line.start_with?("#") }
        end

        # Adds the block after a blank line, leaving every byte already in the file as it was.
        def append(config, text, block)
          separator = text.empty? ? "" : (text.end_with?("\n") ? "\n" : "\n\n")
          File.open(config, "ab", 0o600) { |file| file.write("#{separator}#{block}\n") }
          configured("Codex")
        rescue SystemCallError => error
          manual("PH-Composer could not add to #{config} (#{error.class.name.split('::').last}). Add the first " \
                 "block below to it.", "Codex")
        end

        def configured(name)
          { "state" => "configured",
            "message" => "#{name} is set up to read its token from PH-Composer. #{next_step(name)}" }
        end

        def manual(reason, name)
          { "state" => "manual", "message" => "The token is saved for #{name}. #{reason} #{next_step(name)}" }
        end

        def next_step(name)
          "Then start a new #{name} session to connect: a session already open does not see a new server. " \
            "SketchUp does not need a restart."
        end

        def first_line(output)
          line = output.to_s.lines.first.to_s.strip[0, 160]
          line.empty? ? "" : " (#{line})"
        end

        def now
          Process.clock_gettime(Process::CLOCK_MONOTONIC)
        end

        # Runs one command without a shell, with only the environment a client needs, closed input and what
        # is left of Connect's time. Answers whether it succeeded and the start of what it printed. Never
        # raises: a failure is an answer the user can act on.
        def run(argv, deadline)
          return @runner.call(argv) if @runner

          left = deadline - now
          return [false, "Connect ran out of time"] unless left.positive?

          environment = { "HOME" => Dir.home, "USER" => ENV.fetch("USER", ""),
                          "PATH" => [File.dirname(argv.first), "/usr/bin", "/bin", "/usr/sbin", "/sbin"].join(":") }
          Open3.popen2e(environment, *argv, :unsetenv_others => true, :pgroup => true) do |input, output, waiter|
            input.close
            reader = Thread.new { kept(output) }
            reader.report_on_exception = false
            finished = waiter.join(left)
            stop(waiter) unless finished
            # A process it started may hold the output open after it exits; what was printed by then is enough.
            printed = reader.join(2) ? reader.value : ""
            reader.kill
            return [false, "it did not answer within #{timeout} s"] unless finished

            [waiter.value.success?, printed]
          end
        rescue StandardError => error
          [false, error.class.name.split("::").last]
        end

        # The first MAX_OUTPUT bytes printed, as valid text; the rest is read and dropped so the process
        # never blocks on a full pipe.
        def kept(output)
          text = +""
          loop do
            chunk = output.readpartial(MAX_OUTPUT)
            text << chunk if text.bytesize < MAX_OUTPUT
          end
        rescue EOFError, IOError
          text.byteslice(0, MAX_OUTPUT).force_encoding(Encoding::UTF_8).scrub
        end

        # Asks the command and anything it started to stop, then, 2 s later, ends whatever of the group is
        # left, whether or not the command itself has gone.
        def stop(waiter)
          signal("TERM", waiter.pid)
          waiter.join(2)
          signal("KILL", waiter.pid)
        end

        def signal(name, group)
          Process.kill(name, -group)
        rescue SystemCallError
          nil
        end
      end
    end
  end
end
