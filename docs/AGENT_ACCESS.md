# Connect an agent to PH-Composer

Agent Access lets an MCP client read and edit an open SketchUp model through PH-Composer's public
operations. PH-Composer listens on this computer while a token is live. The default port is 46110.
If another program is using it, choose a free port in Agent Access before creating a token.

## Issue a token

1. Open **Extensions > PH-Composer > Agent Access**, or choose **Agent Access** from the panel's
   Setup menu.
2. Choose **New token** and give it a name. Read is included. Select the additional grants needed
   for the task.
3. For access to one saved model, select **This Model only**. Save As keeps the token with the
   renamed file. A separate file copy needs its own token.

| Grant | What the agent can do |
| --- | --- |
| Read | Discover reachable models and public operations, query data and preview edits |
| View | Change the camera, selection or open Group. Leaving a Volume can restore its protection |
| Edit the Model | Apply validated changes through PH-Composer with native Undo |
| Setup | Change libraries and settings on this computer |
| Export | Write files to approved destinations and retrieve artifacts from its own tasks |
| Capture the view | Get a PNG of the model geometry in the current viewport |

Approve library files, folders and export destinations in **Libraries**. You can also use
**Allow agents to export here** in the Export tab. Review and revoke locations in Libraries.
An agent sees the file path of any saved model it can reach.

## Connect your client

In the token window, choose the client tab, choose a profile and press **Connect**. Start a new
client session to load the connection. The setup has been checked on macOS with Claude Code
2.1.317 and Codex CLI 0.167.0.

- **Claude Code** registers the server in user scope. Check the Default profile with
  `claude mcp get ph-composer`. If Agent Access cannot find the CLI, run the setup command
  it shows in Terminal.
- **Codex** adds or updates the server entry in `~/.codex/config.toml`. Check the Default
  profile with `codex mcp get ph-composer`. Before writing the file, Connect saves
  `config.toml.ph-composer-backup` beside it. Connect sets
  `default_tools_approval_mode = "approve"` unless you already set an approval mode. This lets
  the client call PH-Composer tools without prompting for each call. The token grants still
  determine what SketchUp allows.

The Default profile uses the name `ph-composer`. Named profiles use `ph-composer-<name>`.
Use a separate profile and a model-limited token for each project. When you replace a profile's
token, revoke the old token if you are finished with it.

The client profiles list shows configuration, recent contact and verified access separately.
Start a fresh client session and run discovery to verify access. Use **Repair** after a port
change or to update older settings. **Other ways to connect** shows manual setup for the selected
client.

## Work with a connected agent

Name the model and the task. The agent can find eligible geometry through public queries or
work from your selection. It can inspect records, preview edits and read back the changes.
If you edit the model while it works, the agent must read again before applying a stale request.

Ask the agent to read its [operating guide](AGENT_GUIDE.md) through discovery. For a script
running inside SketchUp, start with the [Ruby API quickstart](API_QUICKSTART.md).

## Manage tokens

Connect stores a token in an account-readable file under `~/.ph-composer/`. The token window
shows the secret once. Up to eight tokens can be live at a time. Manual setup can put it directly in client settings or shell history.
Anyone holding the secret has its grants until you revoke it. On shared computers, revoke
tokens when you finish.

Revoke a token in Agent Access to end its access. PH-Composer removes the token files created by
Connect. To remove the client entry too, run `claude mcp remove --scope user ph-composer` or remove the corresponding
Codex server entry. Substitute the named profile's entry when applicable.
