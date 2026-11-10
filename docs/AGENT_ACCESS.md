# Using PH-Composer with your agent

DATE: 2026-11-10
STATUS: Agent tokens, the local connection, client setup and the agent scenarios are implemented and
checked with Claude Code 2.1.300 and Codex 0.163.0 on SketchUp 2026 for macOS; Connect with Claude
Code 2.1.317 and Codex 0.167.0. On 2026-11-10, fresh sessions of both (Claude Code 2.1.317 with
Sonnet, codex-cli 0.167.0) used only the connection to build Zones, Spaces, Materials, an Assembly, a
Window and Thermal Bridges on drawn geometry, then exported the model. This is a development build,
not a released or supported product.

PH-Composer lets users' agents inspect and edit building models through documented public
operations. Users choose their agent. No built-in LLM, model-provider account or AI subscription is
required by PH-Composer, and ordinary hand authoring remains complete.

The intended workflow is to discover the installed capabilities and target model, read relevant
records or visual context, propose changes where appropriate, apply validated operations, and
read back the result. Writes use the same domain rules and native Undo as the application UI.
The interface reports conflicts when the model changed after the agent inspected it.

Agent access is explicit and revocable. The user controls which model and file operations the
connection may perform. The public interface returns structured results and diagnostics without
requiring access to private implementation code.

## Available now

The public interface an agent will use already exists inside SketchUp, as `PhComposer::API`. A
Ruby script running in SketchUp can discover the registered operations, describe each one's
parameters and results, read Zones and Faces in bounded pages, preview a change and apply it with a
conflict check, and run, poll and cancel an export, all with the panel closed. The
[API quickstart](API_QUICKSTART.md) walks one session from discovery to a verified edit and runs as
an automated test; the [API reference](API_REFERENCE.md) is generated from the registered
operations. A caller connects with only the grants it needs: `read`, `view`, `model_write`, `setup`
and `export`. Exporting a library file or an HBJSON model and adding a library file or folder need
a location only the user can choose. The user approves it once in the Libraries dialog or the
Libraries menu, or, for an export destination, with Allow agents to export here in the Export tab,
and a script then names it by id; a path never passes through the interface. A destination name that
does not end in `.hbjson` or `.json` gets `.hbjson` added; a library export's `.json` name is kept. The user sees, renames and revokes approved
locations, including ones no longer there, in the Libraries dialog. A script that names no approved
location is refused with `access.user_required`, and the refusal says where the user approves one.

### Agent tokens

An agent connects with a token you issue in SketchUp. The gear at the right end of the panel's tab
row opens Setup, which says whether agents can connect and how many tokens are live; its Agent Access…
button, or Extensions > PH-Composer > Agent Access, opens the Agent Access window, separate from the
panel, so a change you are making there is left alone. The window leads with New token; the tokens
already issued are folded under one line, grouped by when they were issued, with revoked ones shown
only when asked for. New token asks for a name and the access the token holds. Read is always included: it reads the
open Models, their Zones, Spaces, Assemblies and Window Types and the values PH-Composer calculates,
and changes nothing. The rest start unchecked, each with what it allows: View changes what SketchUp
shows (the camera, the selection and the open Group, never authored data; leaving a Volume can lock
it again), Edit the Model runs PH-Composer's actions with one Undo step each, Setup changes this
computer's libraries and settings for every Model, Export writes to the folders you approved, and
Capture the view writes an image of the current view, geometry only, to a temporary file the agent
reads. The agent also learns the open Model's file path from what it reads and, for an export it
started, the paths of the files written; what the agent does with them is up to its client.
This Model only limits the token to the Model open now, which must be saved: the agent then sees
and reaches no other Model, not even one with the same file name in another folder. Save As keeps the token on the renamed file, so saving stage copies does not cut the agent off; a copy made with Save a Copy As, or in Finder, is not reached. When the token's Model is not open, the agent is told so, with the file names of the Models that are open, and nothing more about them. The list shows
each token's access and, for such a token, the Model's file name. The token is shown once; copy it then, because it is not shown again. The
token is the only secret: anyone holding it has its access until you revoke it in the same window.
Revoking keeps the token in the list with the date it was revoked. Up to eight tokens can be live
at once.

While a token is live, PH-Composer listens for agents on this computer only, on port 46110, and the
Agent Access window says so. If another program holds that port, the window says so, offers a field
to choose another and holds New token until one is free, so a token's setup never names a port
nothing listens on. An agent connects over MCP with the token as a bearer header and can read:
list the open Models, describe and run the read operations, and preview a change without making it.
A token holding more can also apply changes (each one Undo step, refused with nothing written if the
Model changed since the agent read it), move the camera, selection and open Group, change library
setup, and run exports to folders you approved. An agent can name each change it sends; if a reply
is lost, sending the same name again returns the first result and never applies the change twice.
Each token's latest call since SketchUp started shows beside it.

### Connect your client

When a token is created, the window shows one client at a time, each on its own tab, with Connect as
its setup; the other ways to set it up are folded under Other ways to connect. Checked with Claude
Code 2.1.317 and Codex 0.167.0 on macOS, including clients not started from a terminal:

- Connect Claude Code saves the token in a file only your account can read and runs Claude Code's
  own `claude mcp add-json --scope user ph-composer ...` once, which tells Claude Code to read the token
  from that file each time it connects. If PH-Composer cannot find the `claude` command, the window
  shows that command for you to run in Terminal once. Check it with `claude mcp get ph-composer`,
  which should say Connected.
- Connect Codex saves the token the same way and adds a `[mcp_servers.ph-composer]` block to
  `~/.codex/config.toml`, leaving the rest of the file as it was. If the file already has a
  `[mcp_servers.ph-composer]` block from an earlier setup, it is left alone and the window shows the
  block to put in its place. Check it with `codex mcp get ph-composer`.
- A Codex session that cannot ask for approval, such as `codex exec`, refuses PH-Composer's tools that
  change the Model or start an export ("requires approval, but approval policy is never"), so it can
  only read. To let such a session write, add
  `default_tools_approval_mode = "approve"` to the `[mcp_servers.ph-composer]` block, or pass
  `-c 'mcp_servers.ph-composer.default_tools_approval_mode="approve"'` for one run. The token's
  grants still limit what it can do.

Then start a new session of your client: a session already open does not see a newly added server.
SketchUp does not need a restart. A new token later only needs Connect in its window; the client's
settings stay as they are. Connect works on macOS.

**Profiles.** Each client can hold several PH-Composer entries, one per profile, so two projects can
each have their own token in the same client. Connect asks which profile to set up: Default, the entry
named `ph-composer` that earlier setups made, a profile you named before, or a new one. A new profile's
name uses lowercase letters, digits and hyphens, and becomes the entry `ph-composer-<name>`, with its
own saved token. Give each project a token limited to its Model with This Model only, connect each to
its own profile, and a session of that client reaches both Models, each through its own entry. If the
profile you chose already uses another token, the window names that token before anything changes, and
the button reads Replace and connect. The replaced token stays live until you revoke it.

**Client profiles.** Below the tokens, the window lists each profile it finds, for both clients, with
the token it uses and three separate facts: whether the client's settings are set up for it, whether a
client has contacted PH-Composer with that token since SketchUp started (and which client said so), and
whether a session has verified the connection by reading what the token reaches, which changes nothing in
your Models. To verify, start a new session of the client and let it run discover. When a profile's
settings are out of date, after a port change or an older setup, press Repair: PH-Composer sets the
client up again with the token it already saved, which it never shows. A profile that is not set up
also shows the setup to copy and run or paste by hand. Codex settings that PH-Composer cannot change
for certain, such as a token read from an environment variable, are left as they are. Before it
changes `~/.codex/config.toml`, PH-Composer keeps the previous file beside it as
`config.toml.ph-composer-backup`, and it writes nothing if the file changed meanwhile or is read-only.

**Where the token is kept.** Connect keeps the token in `~/.ph-composer/`, one file per client profile,
which only your account can read; it is never typed on a command line, so it is not in your shell history.
Revoking the token deletes its file. Each client's Other ways to connect also shows a setup with the token itself,
which keeps it in the client's settings file (`~/.claude.json` or `~/.codex/config.toml`) and, for
the command, in your shell history; a new token then means setting the client up again. Anyone who
can read those files has the token until you revoke it.

**Shared computers.** PH-Composer listens on one port on this computer. On a computer with several
user accounts, another account could run a program on that port while SketchUp is not listening
and receive the token from an agent that connects then. On such a computer, revoke your tokens when
you finish and issue a new one when you start.

To disconnect an agent, revoke its token in the Agent Access window; the confirmation names the client
profiles that lose access. To remove the entry from a client as well, run `claude mcp remove --scope
user ph-composer`, or delete the `[mcp_servers.ph-composer]` block from `~/.codex/config.toml`; a named
profile's entry is `ph-composer-<name>`. PH-Composer itself is removed with SketchUp's Extension Manager.

## Working with an agent

The connection carries the operating guide, [AGENT_GUIDE.md](AGENT_GUIDE.md): from finding the Model
to reading back what changed, with recipes and what to do when a request is refused or a reply is
lost. The extension ships it, and an agent reads it through `discover`, a topic at a time, with no
copy of this repository; the connection's first instructions tell it so. You can still give your
agent the file before it starts. The same `discover` pages through everything installed: operations,
record kinds, entity kinds, extensions, library kinds and the refusals every operation can answer.
Both clients above completed the guide's scenarios against
SketchUp 2026 on macOS: reading, a change with a replayed key, recovery from a stale revision and
from a change you made meanwhile, Spaces built from loose Faces, an Assembly assignment, a library
copy, a Window placed at a position you gave, an image of the view, and an export whose file they
read and checked.

An agent granted Capture the view can take an image of the Model SketchUp is showing, at the
viewport's size or one it asks for. The image leaves out PH-Composer's own overlays. Like an export,
the image is a file on this computer: the agent receives its path, hash and size, and reads it with
its client's own file tools. A client that cannot read local files cannot open it.

## Not yet available

An agent cannot yet find the first floor Faces or Groups to build on by itself: it works from the
selection, the open Group or paths you give it, so select or name them. Once a Face is known,
`ph_composer.windows.units.host_extent` gives its outline and size, so an agent can place a Window
on it at a position it works out. The connection serves agents on this computer only; a remote or
hosted connector is not planned. Arbitrary Ruby evaluation bridges remain development tools. The engineering requirements
and acceptance checks are in [AGENT_INTERFACE.md](../context/AGENT_INTERFACE.md).
