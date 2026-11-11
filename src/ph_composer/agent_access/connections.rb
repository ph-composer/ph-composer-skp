# frozen_string_literal: true

require "json"
require "securerandom"
require "shellwords"

module PhComposer
  module AgentAccess
    # The token each connection profile uses, kept in one owner-only file per client and profile
    # (context/AGENT_INTERFACE.md, "Security posture"). The client's own configuration names the file once,
    # through a header helper that prints it, so a new token for that profile changes the file and never the
    # client's settings. Each file holds the request headers: `{"Authorization": "Bearer <token>",
    # "PH-Composer-Profile": "<client>.<profile>"}`. The second names the profile, so when two profiles share
    # a token the listener can tell their calls apart; it is a label, never a credential.
    #
    # A client profile is one client entry (context/AGENT_INTERFACE.md, "User-controlled local access"). The
    # default is the entry named `ph-composer` with the file `<client>.json`, as Connect always wrote it, so an
    # existing setup is the default unchanged; another is `ph-composer-<name>` with `<client>.<name>.json`.
    # Nothing else records a profile: the files here and the clients' own entries are the list.
    #
    # A file is the only copy of a token PH-Composer keeps outside the issuing dialog. It is written when the
    # user connects a client and deleted as soon as its token is no longer live, after a revoke or a reset.
    module Connections
      CLIENTS = { "claude_code" => "Claude Code", "codex" => "Codex" }.freeze
      FOLDER = ".ph-composer"
      MAX_BYTES = 1024
      DEFAULT_PROFILE = "default"
      # A bare TOML key and a Claude Code server name: lowercase letters, digits and inner hyphens.
      PROFILE = /\A[a-z0-9](?:[a-z0-9-]{0,30}[a-z0-9])?\z/.freeze
      FILE = /\A(#{CLIENTS.keys.join('|')})(?:\.([a-z0-9-]+))?\.json\z/.freeze
      PROFILE_HEADER = "PH-Composer-Profile"

      class << self
        # Where the files live; the offline suite points it at a scratch folder.
        attr_writer :directory

        def directory
          @directory || File.join(Dir.home, FOLDER)
        end

        def path(client, profile = DEFAULT_PROFILE)
          name = checked_profile(profile) == DEFAULT_PROFILE ? checked(client) : "#{checked(client)}.#{profile}"
          File.join(directory, "#{name}.json")
        end

        # The shell command a client runs to read its header: `/bin/cat` and the file's path, escaped for the
        # shell both clients run it in (a path with nothing to escape, the usual case, is left as it is).
        def helper(client, profile = DEFAULT_PROFILE)
          "/bin/cat #{Shellwords.escape(path(client, profile))}"
        end

        # The label a profile's file sends in PROFILE_HEADER: `<client>.<profile>`.
        def label(client, profile = DEFAULT_PROFILE)
          "#{checked(client)}.#{checked_profile(profile)}"
        end

        # The label a request presented, or nil unless it names a supported client and a valid profile: the
        # header is the client's text, so nothing else of it is kept.
        def presented(value)
          client, profile = value.to_s.split(".", 2)
          valid = CLIENTS.key?(client) && (profile == DEFAULT_PROFILE || profile.to_s.match?(PROFILE))
          valid ? "#{client}.#{profile}" : nil
        end

        # Whether the profile's file sends its label, as every file Connect writes does.
        def labelled?(client, profile)
          header_in(path(client, profile))&.fetch(PROFILE_HEADER, nil) == label(client, profile)
        rescue StandardError
          false
        end

        # The profile name, refused as `params.invalid` unless it is the default or a valid name.
        def checked_profile(profile)
          return profile if profile == DEFAULT_PROFILE || profile.is_a?(String) && profile.match?(PROFILE)

          raise CodedError.new("params.invalid", "A profile name is 1 to 32 lowercase letters, digits and hyphens, " \
                                                 "starting and ending with a letter or digit.")
        end

        # Replaces the client's file with one holding `token`, written whole: a client reading it while it
        # changes sees the old file or the new one, never part of either.
        def write(client, token, profile = DEFAULT_PROFILE)
          created = renamed = false
          target = path(client, profile)
          folder = owned_folder
          temporary = File.join(folder, ".#{checked(client)}.#{SecureRandom.hex(6)}.tmp")
          File.open(temporary, File::WRONLY | File::CREAT | File::EXCL, 0o600) do |file|
            created = true
            file.write(JSON.generate("Authorization" => "Bearer #{token}", PROFILE_HEADER => label(client, profile)))
          end
          File.rename(temporary, target)
          renamed = true
        rescue SystemCallError => error
          raise CodedError.new("agent_access.connection_unavailable",
                               "PH-Composer could not save the token for #{CLIENTS.fetch(client)} in " \
                               "#{directory} (#{error.class.name.split('::').last}).")
        ensure
          # Whatever stopped the write, no copy of the token is left beside the file.
          File.unlink(temporary) if created && !renamed && File.exist?(temporary)
        end

        # Every saved file by client and profile, with the digest of the token it holds, or nil when it cannot
        # be read: `[{"client", "profile", "path", "digest"}]`, the default profile first.
        def saved
          entries = Dir.exist?(directory) ? Dir.children(directory) : []
          rows = entries.filter_map do |entry|
            client, profile = entry.match(FILE)&.captures
            next unless client && (profile.nil? || profile.match?(PROFILE) && profile != DEFAULT_PROFILE)

            file = File.join(directory, entry)
            { "client" => client, "profile" => profile || DEFAULT_PROFILE, "path" => file,
              "digest" => token_in(file)&.then { |token| Tokens.digest(token) } }
          end
          rows.sort_by { |row| [row["client"], row["profile"] == DEFAULT_PROFILE ? 0 : 1, row["profile"]] }
        rescue SystemCallError
          []
        end

        # The digest of the token one profile's file holds, or nil.
        def digest(client, profile)
          token_in(path(client, profile))&.then { |token| Tokens.digest(token) }
        end

        # Deletes every saved file that does not hold a live token, one it cannot read included, so a revoked
        # token is never left on disk. Never raises: a revoke must not fail on a file it cannot delete.
        def prune(live_digests)
          saved.each do |row|
            next if live_digests.include?(row["digest"])

            File.unlink(row["path"])
          rescue StandardError => error
            Diagnostics.exception("agent_access_connection_prune", error)
          end
        end

        private

        def checked(client)
          raise ArgumentError, "#{client.inspect} is not a supported client." unless CLIENTS.key?(client)

          client
        end

        def token_in(file)
          header_in(file)&.fetch("Authorization", nil).to_s[/\ABearer (\h{48})\z/, 1]
        rescue StandardError
          nil
        end

        # The headers a file holds, or nil when it is not a small regular file holding a JSON object.
        def header_in(file)
          return nil unless File.file?(file) && !File.symlink?(file) && File.size(file) <= MAX_BYTES

          header = JSON.parse(File.read(file))
          header.is_a?(Hash) ? header : nil
        rescue StandardError
          nil
        end

        # The folder, created owner-only, and refused when it is a link or another account's: a token
        # written there could otherwise be read by someone else.
        def owned_folder
          folder = directory
          Dir.mkdir(folder, 0o700) unless File.exist?(folder) || File.symlink?(folder)
          stat = File.lstat(folder)
          unless stat.directory? && stat.owned?
            raise CodedError.new("agent_access.connection_unavailable",
                                 "#{folder} is not a folder this account owns, so no token is saved there.")
          end

          File.chmod(0o700, folder)
          folder
        end
      end
    end
  end
end
