# P3b-02 evidence: Thermal Bridge Type records (T02)

DATE: 2026-10-25
STATUS: Host gate run on branch `feature/thermal-bridges-p3b-02` at `6a805df1` (PR #308), SketchUp 26.1.188, Ruby 3.2.2, macOS 26.7.1. All three assertions pass.
AUTHOR: Ed May, BLDGTYP, with Claude
ISSUE: [#301](https://github.com/ph-composer/ph-composer-skp/issues/301)

Register row [T02](../ACCEPTANCE.md). Offline half: `tests/thermal_bridge_types_test.rb` (11 runs) and
`tests/thermal_bridge_types_walkthrough_test.rb` (1 run), green on Ruby 3.2.2 and 2.7.2; `make ci` green at
`6a805df1` (2,129 Ruby runs, 737 JavaScript, 246 Python, fixtures, hostkit, RBZ verified). Review: one
pre-gate Sonnet read and two Codex gpt-6.1-sol cycles on PR #308. Host half: recorded through
`tools/hostkit/acceptance_case.py` in `_private/host/t02/T02/` (gitignored; synthetic fixture, no project
data). The ledger row records a branch commit, not `main`.

## Identity

| Item | Value |
| --- | --- |
| Installed RBZ | `dist/ph_composer.rbz` built at `6a805df1`, SHA-256 `56f5accdf56583ee4f7735c24389f3f0c2f0011ec8a61497e3abaed68addbae3` |
| Fixture | `_private/host/t02/T02/t02.skp`, a fresh copy of `blank-template.skp` (SHA-256 `2ae1418d`) |
| Process | Fresh, launched by `host_bridge.py launch`, the fixture the only document; composition normal (Assemblies, Zones, Windows, Spaces, ThermalBridges) |
| Controls | Bridge for the walkthrough's public `API.invoke` calls and every readback; System Events for native Undo (Cmd+Z) and Redo (Cmd+Shift+Z) |
| Readback | `ThermalBridgeTypesWalkthrough.state` through `types.all`, one bridge call per step: name to psi, group, source kind, stored colour, `user_data` |

## Results

| Assertion | Observed | Evidence |
| --- | --- | --- |
| Walkthrough, panel closed | Three creates, one psi edit (0.12 to 0.15), one duplicate, one delete, each `committed`; the read-back equals the expected catalog, the parapet's authored colour and `user_data` carried to its copy | `1-run.json` |
| Native Undo and Redo | Six Undos stepped back one action each (delete, duplicate, the edit back to 0.12, then each create) to an empty catalog; six Redos forward; `verify` passes after the last Redo | `2-undo-*.json`, `3-redo-*.json`, `4-verify.json` |
| Save and reopen | `save_copy`, quit, a fresh process on `t02-saved.skp`: `verify` reads the same three types, colour and `user_data` included | `7-reopen-verify.json` |

## Limits

- Extension payloads are proven offline only (`test_delete_of_an_unused_type_is_one_undo_step_that_restores_its_metadata`):
  no registered extension writes one through the public API.
- Guarded delete of a type in use waits for P3b-03, when an Edge can name a type.
- A single type whose notes exceed the agent reply budget cannot be paged past by `types.list`; every catalog list
  shares this, and it is recorded as a cross-catalog follow-up in the ledger.
