# AW07 export QA, run diagnostics and thermal-bridge repair, 2026-11-10

Case `AW07` (agent-workflows stage AW-07, acceptance A09 and A10 of
[the packet](../../archive/agent-workflows-2026-11/ACCEPTANCE.md)). Branch `feat/agent-workflows-aw-07`
at `0d5cd927` (PR #446, squash-merged to main as `009b5915` with identical source), installed RBZ built from that head (SHA-256 `ad70209a6f95…`), SketchUp 26.1.188, Ruby 3.2.2,
macOS. Fresh process on a fresh copy of the blank template; synthetic data only.

Control: an MCP client outside SketchUp over HTTP to the real loopback listener with a read, model_write and export
token; native Edit > Undo and Redo through the SketchUp menu bar; save, quit and relaunch through the bridge.
Development eval only for labelled setup: the token, records from the synthetic Assemblies fixture, a Thermal Bridge
Type, two Groups (a wall and 180 floor squares), an Edge holding unreadable text beside another owner's dictionary, a
loose Edge holding a stranded assignment, and the approved destination. Raw output is in the gitignored run folder.

| Assertion | Result |
| --- | --- |
| preflight-compact-and-paged | The whole preflight is refused as too large; compact counts 183 findings, 181 blocking, 1 repair; every finding pages; code, owner and `blocks_export` filters and a whole row read work |
| blocked-run-diagnostics-kept | The run is refused `record.unreadable` with its source revision; the report is absent (`no_translation`, part read `target.not_found`); kept findings survive a Model edit and a later run; nothing written |
| repair-broken-record | The candidate's fingerprint is the stored bytes' SHA-256; the reviewed repair removes only that text, the other dictionary stays |
| native-undo-redo-exact-bytes | Native Undo restores the exact bytes; Redo removes them again |
| repair-stranded-record | The stranded record's values are disclosed, then removed by the reviewed repair |
| written-run-report-and-hashes | Export through the normal runtime completes with 372 kept findings; report and result rejoin; the files on disk match the run's hashes; two rooms with the Assembly's construction |
| save-and-reopen | After save and a fresh process both repairs and the other owner's value hold; the renamed Zone reads back |
| replies-within-budget | 105 tool results, largest 23,358 bytes, all within 24,576 |

Limitations: an earlier rehearsal in the same build found driver bugs, fixed before this run. The blocked run here
is refused before translation; the 240-finding translation-blocked run, the caller, expiry, close and revoke
controls and the reserved-metadata blockers are offline only (`export_diagnostics_test`). A16 is deferred, optional.
Windows and SketchUp 2023 were not exercised.
