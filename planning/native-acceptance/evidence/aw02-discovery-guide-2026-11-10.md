# AW02 discovery and installed guide, 2026-11-10

Case `AW02` (agent-workflows stage AW-02, acceptance A05, the installed-route part of A12 and the descriptor
part of A15 of [the packet](../../features/unscheduled/agent-workflows-2026-11/ACCEPTANCE.md)). Branch
`feat/agent-workflows-aw-02` at `5c93488b` (PR #441), installed RBZ built from that head (SHA-256 `55ce53c2ea7a…`),
SketchUp 26.1.188, Ruby 3.2.2, macOS. Fresh process on a fresh copy of the blank template; synthetic data only.

Control: an MCP client outside SketchUp over HTTP to the real loopback listener (127.0.0.1:46110) with a
read-only bearer token. Development eval only for the labelled setup: issuing that token as the Agent Access
dialog does, and revoking it afterwards. Raw step output is in the gitignored run folder.

| Assertion | Result |
| --- | --- |
| initialize-names-guide | `initialize` instructions name the guide route; `_meta` carries API 1.35 and the guide's version (digest of the shipped `guide.md`, 15 topics, read pointer); `tools/list` shows the six read tools |
| guide-topics-read | The index points to the guide; the guide section lists 15 topics with the same digest; every topic's text reads through `discover` |
| sections-and-descriptors | Record kinds 11, reference targets 9, extensions 0 with status meanings, library kinds 4; each library kind's `describe` gives its assignment target and examples (Psi-Install Types 2); 26 common codes each have a meaning; contracts carry task retention |
| operations-paged | Operations followed through 4 pages: 241 rows, all unique, equal to the total |
| replies-within-budget | 32 tool results, largest 16,695 bytes, all within 24,576 |
| revoked-refused | After revoke the token is refused with HTTP 401; the listener stays up because other live tokens exist on this machine |

Limitations: one read-only token and the shipped features only (the outside synthetic kind, extension and library
adapter are covered offline). No independent agent client ran; whether two fresh clients find and use the guide
unprompted is AW-10's client gate. Windows and SketchUp 2023 were not exercised.
