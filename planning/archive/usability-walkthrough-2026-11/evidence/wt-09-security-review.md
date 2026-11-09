# WT-09 security review: Connect (#344, D5)

DATE: 2026-11-07
SCOPE: `agent_access/connections.rb`, `client_setup.rb`, `client_config.rb`, the `access.connect`
message in `dialog.rb`. The durable rules are in `context/AGENT_INTERFACE.md`, "Security posture".

## Per-client verification (before building)

Each client ran `discover` against the live listener from a process started with `env -i HOME PATH=/usr/bin:/bin USER`,
the environment a GUI-launched client has, reading the header from an owner-only file:

| Client | Mechanism | Result |
| --- | --- | --- |
| Claude Code 2.1.317 | `headersHelper: "/bin/cat <file>"`, via `--mcp-config` and via user scope (`claude mcp add-json --scope user`) | 1 session listed; `claude mcp get` Connected; no trust prompt |
| Codex 0.167.0 | `http_headers_helper = "/bin/cat <file>"` (a string; an array or table is refused) | 1 session listed; a single-quoted path with a space also worked, so the string is run in a shell |

The issue's premise that Codex reads only an environment variable or an inline token held for 0.163.0;
0.167.0 has `http_headers_helper`.

## What changed in the posture

1. **A plaintext token on disk.** Before, PH-Composer kept only digests. Now a connected token is also in
   `~/.ph-composer/<client>.json`: folder 0700, file 0600, created with `O_EXCL` and renamed into place
   (the temporary file removed in an `ensure`), refused when the folder is a symlink or not owned by the
   user. Every store write (revoke, reset) deletes any client file that does not hold a live token,
   unreadable ones included, through `AgentAccess.tokens_changed`; a failure there is logged and never
   stops the revoke. A same-user process racing the folder checks is accepted as outside the posture. Equivalent exposure to the inline
   forms, which keep the token in the client's settings file, and less than the old `export` line,
   which put it in shell history.
2. **The extension starts a program.** Only `claude`, only from a fixed list of absolute paths, only a
   regular executable file owned by the user or root and not world-writable, and only when
   `~/.claude.json` does not already hold the same entry (so rotating a token runs nothing).
   `Open3.popen2e` with an argv array (no shell), stdin closed, `unsetenv_others` with `HOME`, `USER`
   and a `PATH` of the binary's folder plus system folders, its own process group, one 20 s deadline
   for the whole Connect, then TERM to the group and, 2 s later, KILL to any member left even when the
   command itself has gone (a TERM-ignoring descendant is tested). The page supplies a client id from a fixed
   set and the token; neither reaches argv. The JSON argument holds the URL and the helper command only.
   Output is capped at 4 KiB of valid text, matched for "already exists" (the wording 2.1.317 prints,
   checked) and its first line (160 characters) shown in the dialog; it is not logged. `remove` runs
   only after "already exists", an entry of another form; if the add then fails the message says the
   earlier entry was removed and gives the command.
3. **The extension edits Codex's config.** Append only, after a blank line, existing bytes untouched;
   never when any non-comment line has `ph-composer` as a key in any TOML form (a duplicate would
   invalidate the whole file); project paths holding the name do not count; only when no key or header
   holds an escape and the root `mcp_servers` table is opened only by plain `[mcp_servers.<other>]`
   headers (an inline or dotted root `mcp_servers`, an `[mcp_servers]` table, or an escape such as
   `"mcp_\u0073ervers"` goes to the manual path: Codex gpt-6-astra review, PR #383, both passes);
   another table's own `mcp_servers` (a plugin's, as in the host machine's real config) does not block
   the append; never creates `~/.codex`.
5. **Platform.** Connect refuses on Windows (`/bin/cat` helper); Windows support has its own gate.
4. **The helper command** is `/bin/cat` plus `Shellwords.escape(path)`, built in Ruby from the folder
   constant; no page, agent or file content reaches it.

Not covered: a hostile process running as the same user can read the file, as it can the client's
settings and the SketchUp defaults; that is outside this posture, as before.
