# frozen_string_literal: true

require "json"
require "securerandom"
require "shellwords"

module PhComposer
  module AgentAccess
    # The token each supported client connects with, kept in one owner-only file per client
    # (context/AGENT_INTERFACE.md, "Security posture"). The client's own configuration names the file once,
    # through a header helper that prints it, so a new token for that client changes the file and never the
    # client's settings. Each file holds the request header, `{"Authorization": "Bearer <token>"}`.
    #
    # A file is the only copy of a token PH-Composer keeps outside the issuing dialog. It is written when the
    # user connects a client and deleted as soon as its token is no longer live, after a revoke or a reset.
    module Connections
      CLIENTS = { "claude_code" => "Claude Code", "codex" => "Codex" }.freeze
      FOLDER = ".ph-composer"
      MAX_BYTES = 1024

      class << self
        # Where the files live; the offline suite points it at a scratch folder.
        attr_writer :directory

        def directory
          @directory || File.join(Dir.home, FOLDER)
        end

        def path(client)
          File.join(directory, "#{checked(client)}.json")
        end

        # The shell command a client runs to read its header: `/bin/cat` and the file's path, escaped for the
        # shell both clients run it in (a path with nothing to escape, the usual case, is left as it is).
        def helper(client)
          "/bin/cat #{Shellwords.escape(path(client))}"
        end

        # Replaces the client's file with one holding `token`, written whole: a client reading it while it
        # changes sees the old file or the new one, never part of either.
        def write(client, token)
          created = renamed = false
          target = path(client)
          folder = owned_folder
          temporary = File.join(folder, ".#{checked(client)}.#{SecureRandom.hex(6)}.tmp")
          File.open(temporary, File::WRONLY | File::CREAT | File::EXCL, 0o600) do |file|
            created = true
            file.write(JSON.generate("Authorization" => "Bearer #{token}"))
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

        # The digest of the token each client's file holds, by client; a client without a readable file is
        # left out.
        def digests
          CLIENTS.keys.each_with_object({}) do |client, held|
            token = token_in(path(client))
            held[client] = Tokens.digest(token) if token
          end
        rescue StandardError
          {}
        end

        # Deletes every client file that does not hold a live token, one it cannot read included, so a revoked
        # token is never left on disk. Never raises: a revoke must not fail on a file it cannot delete.
        def prune(live_digests)
          held = digests
          CLIENTS.each_key do |client|
            file = path(client)
            next unless File.symlink?(file) || File.exist?(file)
            next if live_digests.include?(held[client])

            File.unlink(file)
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
          return nil unless File.file?(file) && !File.symlink?(file) && File.size(file) <= MAX_BYTES

          header = JSON.parse(File.read(file))
          header.is_a?(Hash) ? header["Authorization"].to_s[/\ABearer (\h{48})\z/, 1] : nil
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
