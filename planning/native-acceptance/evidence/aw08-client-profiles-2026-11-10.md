# AW08 client profiles, 2026-11-10

Case `AW08` (planning/native-acceptance/cases.json), agent-workflows AW-08, acceptance A11. Branch head
`8b85272d` (PR #448), installed RBZ from that head, SketchUp 26.1.188 (Ruby 3.2.2) on macOS 26.7.1, fresh
process, Claude Code 2.1.317 and codex-cli 0.167.0. Synthetic empty Models `house-a.skp` and `house-b.skp`.
Client files lived in a scratch home outside the repository and outside the user's own client settings; it
was deleted at cleanup. No token value appears in any kept log or image (scanned for 48-hex strings).

Control: development bridge for labelled setup (redirected client paths, Model-only token issue) and for
firing page messages on the dialog's real callback; page buttons clicked by script, since HtmlDialog content
takes no background click; native dialog pixels by window capture; real `claude mcp add-json`/`remove`/`get`;
fresh client sessions in a GUI environment (only `HOME`, `USER`, system `PATH`).

| Assertion | Result | Observation |
| --- | --- | --- |
| Two profiles, scoped | Pass | Default (House A token) and `house-b` (House B token) in both clients; fresh Claude Code and Codex sessions: `ph-composer` discover listed only `house-a.skp`, `ph-composer-house-b` only `house-b.skp` |
| Client health | Pass | `claude mcp get` ran each helper: both entries Connected; rows read set up, contacted (`codex-mcp-client 0.167.0`, the token's latest) and token verified |
| Replacement shown | Pass | Connect without `replace` wrote nothing; the issued dialog showed "Default uses AW08 House A now" and Replace and connect |
| Stale and manual | Pass | A stale `replace` was refused "This connection changed since it was shown"; Repair on a read-only `config.toml` answered the read-only warning, file unchanged |
| Port repair | Pass | Port 46111: four profiles "set up for another port or file"; Repair (Codex url line with a 0600 backup; Claude Code remove and add-json by entry name) set all four up; both clients connected and stayed scoped on 46111 |
| Revoke one profile | Pass | Revoke confirm named "Claude Code (house-b), Codex (house-b)"; after it the house-b files were deleted, `ph-composer-house-b` failed in both clients and `ph-composer` kept working |
| Dialog widths | Pass | 560 x 700 and 360 x 520: rows wrap, no sideways overflow |
| Versions | Pass | As above |

Observed, not a defect: contacted and verified belong to the token, so a token used by two clients shows
the latest client's name on both rows, as the dialog's wording ("token contacted by") says. The Codex
model's final text in run three misread a completed discover as an error; its tool call completed and listed
`house-a.skp`.
