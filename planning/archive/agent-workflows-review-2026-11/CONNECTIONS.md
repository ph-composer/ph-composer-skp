# Connection, operating guidance and collaboration

Baseline and evidence limits are in [README](README.md). Source paths below are relative to the
repository root; line numbers refer to the review baseline. Recommendations are not shipped behavior.

## What a user does today

1. Opens Agent Access from the panel's Setup or the Extensions menu.
2. Creates a named token. Read is included; View, Model write, Setup, Export and Capture are optional.
   A saved-file binding can restrict it to one Model. Unsaved Models cannot use that binding.
3. Uses Connect for Claude Code or Codex. Each client's token goes into one owner-only file, and
   its configuration calls a header helper. This automated route is macOS-only.
4. Starts a new client session, then separately supplies `docs/AGENT_GUIDE.md`.
5. Approves file/folder inputs or export destinations in a different UI when those are needed.

The UI communicates grant reach clearly and does not impose repeated confirmations on granted
ordinary writes. Browser checks passed at the tested widths, including 360 x 520 for the issued-token
dialog; the New token and issued-token screenshots were inspected. This was Chrome with synthetic
state, not native HtmlDialog or a real connection test.

## Setup friction and recommendations

| Observation and source | User consequence | Recommended next step |
| --- | --- | --- |
| `agent_access/connections.rb:19-33,39-50` stores one header file per client; `client_config.rb:12` fixes one server name | Connecting another Model-only token for Codex replaces the credential all sessions of that configured entry will read on reconnect; the old token can remain live. Two independently scoped projects have no normal profile setup | Show which binding a Connect replaces; support named connection profiles and an explicit default. Preserve existing configuration on migration. Do not silently combine grants |
| `client_setup.rb:50-57,112-139` saves a token before setup, and preserves an existing Codex entry if it is not an exact match | A safe refusal is good, but the user must edit TOML after a port change or older setup. Ordinary extra settings can also force manual handling | Offer reviewable targeted repair of an owned entry, with a backup, conflict checks and a manual fallback for unrecognized forms. Never rewrite unrelated settings |
| `dialog.rb:171-205`; `client_setup.rb:15-20,76-102` | Reconnect is attached to the one-time secret dialog, and Claude setup can block the SketchUp thread for its 20-second command budget | Make reconnect/repair accessible from a saved connection; reuse only a live saved credential without displaying it. Move only CLI/file setup work off the host thread if measurement warrants it; keep UI/SketchUp work on the host thread |
| `html/agent_access/page.js:160-178`; `Listener.last_calls`; `CallLog` | “Used by” means a saved header file references that token, not a proven current connection. The UI shows the last call but no guided end-to-end check | Distinguish configured, contacted and verified. A harmless discovery/context check should establish client, session and grant reach without a model write |
| `client_setup.rb:51-53`; `client_config.rb`; `docs/AGENT_ACCESS.md:82-108` | Automatic setup names only two macOS clients; Windows and arbitrary local MCP clients require manual configuration | Keep a neutral endpoint/auth guide and exact tested-client matrix. Windows implementation and native proof belong to the existing platform gate; remote/browser clients remain an explicit product decision |

These are workflow limitations, not evidence of credential theft or an authorization bypass. The
documented fixed-port impersonation risk on multi-account machines remains an accepted security
tradeoff, not a new discovery. Do not silently change that posture in a convenience refactor.

## A connection should teach the agent how to operate

`agent_access/mcp.rb:13-28` supplies a short initialize instruction and empty resources/prompts.
It does not deliver the operating guide. `docs/AGENT_ACCESS.md:112-114` asks the user to do that
separately. An agent with only the MCP connection cannot discover the full recipes, trust boundary,
lost-reply policy or raw-geometry limitation from a self-contained onboarding route.

Supply one versioned, bounded guide through the connection, generated or packaged from the same
guide the repository tests. A small topic read is sufficient; MCP resources are an alternative when
both supported clients demonstrably retrieve them. No vendor-specific agent framework is needed.
Include recipe prerequisites, operation names, SI units, explicit references, stale/retry recovery,
host cooperation, artifact verification and treating Model/library prose as data.

Fix contradictory availability prose at the same time. `docs/AGENT_ACCESS.md:125-126` says Face
extents are unavailable, while `docs/AGENT_GUIDE.md` and `windows.units.host_extent` describe and
implement them. The header and delivery sections of `context/AGENT_INTERFACE.md` still mix planned
transport language with implemented MCP, write and capture contracts. `docs/.index.md` describes
the connection as planned and omits the operating guide. The generated reference is current; these
handwritten routes are not consistently current.

The current guide test checks that named operations exist, not that every recipe is self-contained
or that an asserted absence remains true (`tests/agent_guide_test.rb:20-39`). Test a fresh connection
without a repository checkout or a preloaded private skill, using only surfaced guidance.

## Working alongside a person

The existing whole-Model revision is deliberately conservative and protects against completed
concurrent edits. Keep it until measurements justify a narrower conflict contract. There is no
need for an agent-specific lock on the whole app or a transaction held across LLM turns.

There is a narrower unverified boundary: `ModelSession#busy_reason` checks an exclusive operation
and deferred work (`session/model_session.rb:58-63`), while `context.read` reports the active tool
separately (`shell/context_commands.rb:159-163`). Context navigation explicitly refuses non-idle
tools (`:128-134`); ordinary mutation dispatch has no equivalent general native-gesture check
(`shell/dispatch.rb:185-201,322-325`). The source therefore does not establish that “not busy” means
a safe moment to interrupt a person's in-progress Move, drawing or custom-tool gesture. No lost
geometry or Undo interference is claimed here; native reproduction is required before choosing
a guard. Native modal dialogs are a separate known case: Ruby pauses and the client may time out.

The 64-call diagnostic ring records tool, operation, session, status and time, but not affected
references, outcome revision or replay identity (`agent_access/call_log.rb:12-26`). There is no public
bounded change/incident reader. Recommend a small caller/session-scoped operation history for
“what changed?” and troubleshooting, with no parameters, credential values or other Models' data.
This is a follow-up usability capability, not a prerequisite for current atomic edits.

## Visual and artifact context

Colour-by modes, legend selection/isolation and readouts have public commands and state. Capture
returns only SketchUp geometry, explicitly excluding overlays and panels. An agent can verify
semantic records and ordinary geometry, but cannot use that image to confirm what a Colour-by
overlay or Space label actually looks like. Keep this limitation visible in every capture result.
An overlay-capable route needs a separate host experiment and truthful provenance; it is not
just a flag to turn on in the current image writer.

Capture and exported files are returned as local paths with hashes and sizes. This works for the
historically tested clients with local filesystem tools. A generic MCP-only client or filesystem
sandbox cannot necessarily retrieve those bytes. A bounded caller-owned artifact reader and native
MCP image/resource delivery would remove that dependency. It must read only artifacts created for
that caller, never arbitrary user-supplied paths. Keep the current path receipt for compatible clients.

## Deliberate boundaries

- No built-in LLM, hosted agent, model-provider keys or AI subscription belongs in this program.
- Tokens and new approved locations are user-controlled, not agent-creatable. Hosted provider
  sign-in also remains a user step; setup access does not confer authority to obtain credentials.
- Raw SketchUp geometry creation, transformation, file save/open and general Undo/Redo are not
  public authoring tools. Existing PH operations manage geometry they own. Agents can build PH
  records around existing drawn geometry; complete CAD authorship needs a separate bounded product
  decision. Do not solve missing candidate reads by exposing arbitrary Ruby evaluation.
- Current macOS development evidence is not a release, Windows or SketchUp 2023 support claim.
