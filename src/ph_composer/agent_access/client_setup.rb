# frozen_string_literal: true

require "json"
require "open3"
require "securerandom"

module PhComposer
  module AgentAccess
    # Connect: saves a token for one client's connection profile (Connections) and sets that client up, once,
    # to read it from there (context/AGENT_INTERFACE.md, "Security posture"). Neither step puts the token on a
    # command line or in the client's settings, and a client already set up is left as it is, so connecting
    # again with a new token changes only the file. Repair reruns the setup for a saved profile whose token is
    # still live, against the current port, without the token.
    #
    # Claude Code is set up with its own `claude mcp add-json`, run without a shell from an absolute path
    # in a fixed list, unless its settings already hold the same entry. Codex has no command that sets a
    # header helper and its `codex mcp add` rewrites the whole file, so CodexConfig adds or edits the
    # profile's own table in ~/.codex/config.toml and nothing else. When a step cannot be done the token is
    # still saved and the answer carries the token-free setup to run or paste by hand. macOS only: the
    # helper is `/bin/cat`.
    module ClientSetup
      SERVER = ClientConfig::SERVER_NAME
      DEFAULT = Connections::DEFAULT_PROFILE
      # For the whole of one Connect, every command it runs together: SketchUp waits on it.
      TIMEOUT = 20
      MAX_OUTPUT = 4096
      MAX_SETTINGS = 64 * 1024 * 1024
      CLAUDE_CANDIDATES = ["~/.local/bin/claude", "/opt/homebrew/bin/claude", "/usr/local/bin/claude",
                           "~/.claude/local/claude"].freeze
      # The copy of Codex's config a Codex edit replaced, beside it.
      BACKUP_SUFFIX = ".ph-composer-backup"
      INLINE = /\ABearer (\h{48})\z/.freeze
      # Claude Code's settings could not be read as JSON within MAX_SETTINGS.
      class UnreadableSettings < InternalError; end

      class << self
        # The offline suite replaces the command runner, the time limit and the home the clients' files are
        # in; no test runs a client it did not write.
        attr_writer :runner, :home, :timeout

        # The home folder whose client settings are read and changed, and the HOME a client command runs with.
        def home
          @home || Dir.home
        end

        def codex_home
          File.join(home, ".codex")
        end

        def claude_settings
          File.join(home, ".claude.json")
        end

        def timeout
          @timeout || TIMEOUT
        end

        # Answers `{"state" => "configured" | "manual", "message" => ..., "setup" => ...}`; the token is
        # saved in both. `setup` is the token-free text to run or paste, present when the state is manual.
        def connect(client, token, port, profile: DEFAULT)
          macos_only!
          Connections.write(client, token, profile)
          set_up(client, port, profile)
        end

        # Sets the client up again for a saved profile whose file holds a live token: after a port change, an
        # entry edited by hand or an older setup. Raises `agent_access.token_unknown` otherwise.
        def repair(client, port, profile: DEFAULT)
          macos_only!
          unless Tokens.snapshot.key?(Connections.digest(client, profile))
            raise CodedError.new("agent_access.token_unknown", "This connection has no live token. Create a token " \
                                                               "and connect it to this profile.")
          end

          set_up(client, port, profile)
        end

        # What the client's own file says of a profile's entry, read and never written: `{"setup" => state,
        # "inline_digest" => the SHA-256 of a token the entry carries itself, or nil}`. The state is
        # `configured`, `absent`, `outdated` (PH-Composer's form with another url or file), `inline`,
        # `other`, `no_client` (Codex has no folder here) or `unreadable`.
        def entry(client, port, profile)
          client == "claude_code" ? claude_state(port, profile) : codex_state(port, profile)
        end

        # The PH-Composer entries the client's file has, by name: `ph-composer` and `ph-composer-<name>`.
        def server_names(client)
          if client == "claude_code"
            claude_servers.keys.select { |name| name.match?(/\A#{SERVER}(?:-[a-z0-9-]+)?\z/) }
          else
            File.file?(codex_config) ? CodexConfig.server_names(File.binread(codex_config)) : []
          end
        rescue SystemCallError, UnreadableSettings
          []
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

        def macos_only!
          return unless Gem.win_platform?

          raise CodedError.new("agent_access.connection_unavailable", "Connect works on macOS only. Use a " \
                                                                      "setup with the token below instead.")
        end

        def set_up(client, port, profile)
          client == "claude_code" ? claude_code(port, profile) : codex(port, profile)
        end

        # Adds the server unless Claude Code already has this entry; one of another form is replaced, by
        # its name only.
        def claude_code(port, profile)
          name = ClientConfig.server_name(profile)
          server = ClientConfig.claude_server(port, profile)
          return configured("Claude Code") if claude_state(port, profile)["setup"] == "configured"

          by_hand = ->(reason) { manual(reason, "Claude Code", ClientConfig.setup_text("claude_code", port, profile)) }
          binary = claude_binary
          unless binary
            return by_hand.call("PH-Composer could not find the claude command. Run the setup below in Terminal once.")
          end

          deadline = now + timeout
          add = [binary, "mcp", "add-json", "--scope", "user", name, JSON.generate(server)]
          done, output = run(add, deadline)
          return configured("Claude Code") if done
          unless output.include?("already exists")
            return by_hand.call("claude mcp add-json did not finish#{first_line(output)}. Run the setup below in " \
                                "Terminal once.")
          end

          removed, = run([binary, "mcp", "remove", "--scope", "user", name], deadline)
          done, output = run(add, deadline) if removed
          return configured("Claude Code") if done

          by_hand.call("Claude Code had an earlier #{name} entry#{removed ? ', now removed,' : ''} and the new one " \
                       "was not added#{first_line(output)}. Run the setup below in Terminal once.")
        end

        def claude_state(port, profile)
          entry = claude_servers[ClientConfig.server_name(profile)]
          return { "setup" => "absent", "inline_digest" => nil } if entry.nil?
          return { "setup" => "other", "inline_digest" => nil } unless entry.is_a?(Hash)

          server = ClientConfig.claude_server(port, profile)
          inline = entry["headers"].is_a?(Hash) ? entry["headers"]["Authorization"].to_s[INLINE, 1] : nil
          setup = if inline then "inline"
                  elsif entry.slice(*server.keys) == server && !entry.key?("headers") then "configured"
                  elsif entry["headersHelper"] == server["headersHelper"] then "outdated"
                  else "other"
                  end
          { "setup" => setup, "inline_digest" => inline && Tokens.digest(inline) }
        rescue UnreadableSettings
          { "setup" => "unreadable", "inline_digest" => nil }
        end

        # Claude Code's user `mcpServers`, read and never written, kept while the file is unchanged: the
        # dialog reads it at every refresh and the file can be large.
        def claude_servers
          stat = File.stat(claude_settings)
          raise UnreadableSettings if stat.size > MAX_SETTINGS

          key = [claude_settings, stat.mtime.to_r, stat.size]
          return @claude_cache.last if @claude_cache&.first == key

          servers = JSON.parse(File.read(claude_settings)).then { |settings|
            settings.is_a?(Hash) ? settings["mcpServers"] : nil
          }
          @claude_cache = [key, servers.is_a?(Hash) ? servers : {}]
          @claude_cache.last
        rescue Errno::ENOENT
          {}
        rescue JSON::ParserError, SystemCallError, EncodingError
          raise UnreadableSettings
        end

        def codex_config
          File.join(codex_home, "config.toml")
        end

        def codex_lines(port, profile)
          [ClientConfig.codex_url_line(port), ClientConfig.codex_helper_line(profile)]
        end

        def codex_state(port, profile)
          return { "setup" => "no_client", "inline_digest" => nil } unless File.directory?(codex_home)

          text = File.file?(codex_config) ? File.binread(codex_config) : +""
          name = ClientConfig.server_name(profile)
          inline = CodexConfig.inline_token(text, name)
          { "setup" => CodexConfig.state(text, name, *codex_lines(port, profile)),
            "inline_digest" => inline && Tokens.digest(inline) }
        rescue SystemCallError
          { "setup" => "unreadable", "inline_digest" => nil }
        end

        # Adds the profile's table, or corrects the url and token lines of the one there, keeping every other
        # byte of the file.
        def codex(port, profile)
          config = codex_config
          setup = ClientConfig.setup_text("codex", port, profile)
          unless File.directory?(codex_home)
            return manual("Codex is not set up on this computer: there is no #{codex_home} folder. Once it is, " \
                          "add the block below to its config.toml.", "Codex", setup)
          end

          text = File.file?(config) ? File.binread(config) : +""
          name = ClientConfig.server_name(profile)
          state = CodexConfig.state(text, name, *codex_lines(port, profile))
          return configured("Codex") if state == "configured"

          if state == "absent"
            updated = CodexConfig.append(text, name, setup)
            unless updated
              return manual("#{config} defines mcp_servers in a form PH-Composer does not add to. Add the block " \
                            "below to it by hand.", "Codex", setup)
            end
          else
            updated = CodexConfig.edit(text, name, *codex_lines(port, profile))
            unless updated
              return manual("#{config} gives the #{name} server in a form PH-Composer does not change. Set its " \
                            "url and http_headers_helper to the ones below and remove any other way it is given " \
                            "a token.", "Codex", setup)
            end
          end

          problem = write_codex(config, text, updated) || check_codex(config, text, updated, name, port, profile)
          return manual("#{problem} Add the block below to it by hand.", "Codex", setup) if problem

          replaced = state == "inline" ? " The token config.toml held is no longer used there: revoke it here if " \
            "nothing else uses it." : ""
          configured("Codex", replaced)
        rescue SystemCallError, EncodingError => error
          manual("PH-Composer could not read or change #{config} (#{error.class.name.split('::').last}). Add the " \
                 "block below to it.", "Codex", setup)
        end

        # Replaces the file with `updated`, refusing when it changed since it was read or cannot be written.
        # The bytes replaced are kept beside it, owner-only. The new file is written beside the one a link
        # points to and renamed onto it, so the link stays a link and a reader never sees half a file.
        # Answers why it wrote nothing, or nil.
        def write_codex(config, planned_from, updated, backup: true)
          # A dangling link raises here, so nothing replaces it.
          target = File.symlink?(config) || File.exist?(config) ? File.realpath(config) : config
          return "#{config} is read-only." if File.exist?(target) && !File.writable?(target)

          current = File.file?(target) ? File.binread(target) : +""
          # Compared as bytes: the plan may be text and the file is read as binary.
          unless current.b == planned_from.b
            return "#{config} changed while PH-Composer was reading it, so nothing was written."
          end

          mode = File.exist?(target) ? File.stat(target).mode & 0o777 : 0o600
          if backup && !planned_from.empty?
            copy = "#{target}#{BACKUP_SUFFIX}"
            return "#{copy} is a link, so PH-Composer does not write through it." if File.symlink?(copy)

            File.open(copy, File::WRONLY | File::CREAT | File::TRUNC, 0o600) { |file| file.write(planned_from) }
            File.chmod(0o600, copy)
          end
          temporary = "#{target}.#{SecureRandom.hex(6)}.tmp"
          File.open(temporary, File::WRONLY | File::CREAT | File::EXCL, 0o600) { |file| file.write(updated) }
          File.chmod(mode, temporary)
          File.rename(temporary, target)
          nil
        ensure
          File.unlink(temporary) if temporary && File.exist?(temporary)
        end

        # Reads the file back: the entry must now be the one asked for. When it is not and the file still holds
        # exactly what was written, the bytes it replaced are put back, so a failed edit never stays.
        def check_codex(config, before, written, name, port, profile)
          current = File.binread(config)
          return nil if CodexConfig.state(current, name, *codex_lines(port, profile)) == "configured"

          restored = current.b == written.b && write_codex(config, written, before, :backup => false).nil?
          "#{config} did not read back as set up#{restored ? ', so it was put back as it was' : ''}."
        end

        def configured(name, note = "")
          { "state" => "configured",
            "message" => "#{name} is set up to read its token from PH-Composer.#{note} #{next_step(name)}" }
        end

        def manual(reason, name, setup)
          { "state" => "manual", "message" => "The token is saved for #{name}. #{reason} #{next_step(name)}",
            "setup" => setup }
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

          environment = { "HOME" => home, "USER" => ENV.fetch("USER", ""),
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
