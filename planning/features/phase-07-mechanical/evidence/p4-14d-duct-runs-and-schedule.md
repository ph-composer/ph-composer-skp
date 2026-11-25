# P4-14d evidence: duct runs and the schedule

DATE: 2026-11-25
Register row: [M14d](../ACCEPTANCE.md). Stage: [P4-14d](../phases/p4-14d-duct-runs-and-schedule.md), under the parent
index [P4-14](../phases/p4-14-erv-ducting.md). Issue #562.
Base: cut from `origin/refactor/phase-07-line-groups-ops` at `2393daa0` (#585), moved onto `main` at `ef79e30d` after
#585 merged (identical tree, `git diff --stat 2393daa0 origin/main` empty).

Offline evidence only. No SketchUp process was started. The host case `M14d` (in
`planning/native-acceptance/cases.json`: the schedule against the hand measurement, the missing run, `runs.locate` into
a wrapped group and the hidden refusal, identifiers across save and reopen, the host measurement) is owed to the MS3
sitting (D4-31). M14d stays Open.

## What was built

| Step | Where | Note |
| --- | --- | --- |
| 1. Scan | `features/ducting/scan.rb`; `line_groups/scan.rb` (`Scan.edges`) | The layer's walk with ducting's spec; each readable duct detached with its group, world metres and vertex ids, `shared` through shared storage, an unreadable group or duct record (bad JSON, not an object, failing the schema: no direction, a quantity above 10,000) a `record.unreadable` row; Zones' containment only for the schedule. Piping's scan moved onto `Scan.edges` |
| 2. Runs | `features/ducting/runs.rb` | Pure: facts grouped by container path, direction, Duct Type and quantity; `duct_` and `duct_seg_` identifiers; names per Ventilator and direction |
| 3. Findings | `features/ducting/findings.rb`, `codes.rb` | The stage doc's table; `ducting.run_missing` on each served Ventilator's row, served read from `ph_composer.mechanical.ventilators.all` (`zones` non-empty) |
| 4. Schedule and locate | `features/ducting/schedule.rb`, `declarations/schedule.rb`, `declarations/duct_types.rb`, `type/reads.rb`; `line_groups/schedule_shapes.rb` | `ph_composer.ducting.schedule` (bounded, `compact`), `schedule.details`, `runs.members`, `ph_composer.ducting.ventilators` with the snapshot section `ph_composer.ducting.ducting_ventilators`, `runs.locate`; `duct_types.list` and `.all` rows gain `used_length_m`; API 1.106, one `CHANGES` row; the recipe gains the schedule read; `make fixtures` |
| 5. Measure | below | |
| 6. Documents | `context/CONTRACTS.md` ("ERV ducting"), `context/AGENT_INTERFACE.md`, `context/EXTENSIBILITY.md` ("Line groups"), `context/TECH_STACK.md` ("Edge-owned assignments"), `docs/AGENT_GUIDE.md` and the shipped guide, the packet CONTRACTS (sections 3 and 6) | |
| Host case | `cases.json` `M14d` | No walkthrough script: the MS3 sitting builds the case from the M14c walkthrough and reads the schedule |

## Step 5: the measurement

A synthetic stub Model of 50,000 Edges: forty Ducting groups at the root, each of five ducts (three Outdoor air, two
Exhaust air, so eighty runs), forty Ventilators each serving one Zone with one Space, and 50 plain Groups holding the
other 49,800 loose Edges. Each read timed seven times through `API.query`, median, on an Apple M1 Max (a scratch test
beside the test helper, not committed):

| Read | Ruby 3.2.2 | Ruby 2.7.2 |
| --- | --- | --- |
| `ph_composer.ducting.schedule`, `limit` 500 | 259.1 ms | 317.2 ms |
| `ph_composer.ducting.ventilators` | 12.3 ms | 15.2 ms |
| `ph_composer.ducting.duct_types.all` | 10.6 ms | 13.5 ms |
| `ph_composer.mechanical.ventilators.all` (inside the schedule) | 242.0 ms | 299.9 ms |
| The walk alone (`LineGroups::Scan.walk`) | 7.2 ms | 9.6 ms |
| `ph_composer.piping.pipe_types.all`, `ph_composer.piping.systems` (no pipes) | 6.8, 7.4 ms | 9.2, 9.4 ms |

Both ducting snapshot reads are far under the 200 ms target offline, so `ph_composer.ducting.ducting_ventilators` is
registered and `duct_types.all` carries `used_length_m`, as the stage doc says. The schedule's cost is almost all
Mechanical's Ventilators read, whose Serves and airflow balance cost about 240 ms at forty served Zones;
`ph_composer.mechanical.serves.all` alone costs 52.6 ms on 3.2.2. The schedule is read on opening and on Refresh
only (D3b-13), so it stays. *For Ed:* every panel refresh now walks the Model four times for line groups (ducting's
two sections and piping's two), about 37 ms together here on 3.2.2 with no pipes; piping's measured 55 ms each at
2,000 pipes (P4-13c). A stub Model is not the host: the host figures are `M14d`'s.

## Inferred beyond the stage doc

Recorded in the stage doc under "Recorded at implementation": the two layer pieces (`LineGroups::Scan.edges` and
`LineGroups::ScheduleShapes`, piping moved onto both); `ducting.run_missing` on the `ventilators` rows with
Mechanical's Locate and no user text in its message; used length applying the quantity; the 10,000 quantity cap;
`ducting.hidden`; run order by Ventilator id; no `schedule.all` (P4-14f's). Also: `ph_composer.ducting.ventilators`
cuts each name as a schedule page does, and declares itself unbounded, preferring `schedule.details` (cycle 1).

*For Ed:* ACCEPTANCE's "Delete ERV-2 with null: `ducting.group_unlinked` ... whose Locate selects DG-2" is met as
piping's group findings are: Locate opens DG-2 and selects the finding's run of ducts, not the Group entity. Selecting
the Group itself needs a new view command; P4-14f's host case reads it.

## Tests

`tests/ducting_runs_test.rb` (6: the ERV ducting case and its lengths, lines that do not touch and a type change, a
second quantity, a pasted group, identifiers across scans and a reassignment and a split, each finding on its case),
`tests/ducting_schedule_test.rb` (7, the stub Model: the case through the API in world metres, `ventilators` and both
Duct Type reads, Locate into a wrapper; `ducting.run_missing` for a served Ventilator only; unreadable rows and no
write or operation; a Zone-held and a pasted group; Locate refusals with `ducting.hidden`; compact, members, details
and foreign cursors refused before the walk; the quantity cap), `tests/line_groups_test.rb` (one added: `Scan.edges`
over the probe spec). `tests/api_test.rb` reads minor 106. Piping's tests and goldens are unchanged, and
`docs/API_REFERENCE.md` changes no piping line (checked by diffing the reference before and after the piping move).

## Stale cases

`uv run tools/hostkit/acceptance_ledger.py status` with `--changed` for every changed `src/` path, the shipped guide
and `docs/AGENT_GUIDE.md`: 44 of 161 cases name one. `needs_recheck` 21 (A04, A09, R01 to R06, E15, E17, the six UXR
cases, LH1, AW02, AW10, EUD09, EUD09X), each already `needs_recheck` on the base, as P4-14c2 found; `historical_affected`
4 (A03, A07, A12, A16); `not_run` 19 (E01 to E05, E07 to E13, M13a to M13e, M14a, M14c), owed to their sittings.
Unmapped: `docs/AGENT_GUIDE.md`. `M14d` is added to `cases.json` as owed to MS3. Nothing was rerun.

## Size

`uv run tools/runtime/vendor.py --check`: "Runtime verified: 223 assets, 8 wheels, 23168678 bytes" (unchanged).
Installed on the final head `c94cdca4`: 27,859,506 bytes on Ruby 3.2.2 (27,859,500 on 2.7.2), 34,137 over the base's
27,825,369 against the 30 KB estimate: 11 percent over 30,720, inside the 25 percent stop line. 140,494 bytes are left
under the 28,000,000 ceiling, 56,526 after P4-14e and P4-14f's estimates (30 and 52 KB, 83,968 bytes), above the 40 KB
line. Moving the shared schemas into the layer saved about 2,400 bytes against copying them.

## Review

Sonnet adversarial read before the gate: 11 findings. Fixed: the unserved-Ventilator filter now proven where it lives
(a test with ERV-1 missing its exhaust before it serves a Zone); the lengths read cuts names; a 10,000 positive control.
Declined, as piping's settled behavior: `duct_types.list` measures before paging; the non-compact page carries every
detail row (compact is the bounded route); an unreadable catalog record refuses the schedule; an empty group has no
run and so no finding. Noted: two walks per refresh (measured above). The evidence file and doc line lengths were the
rest.

Codex gpt-6.2-sol cycle 1 on `4ef8d0dc`: 1 P1, 6 P2. Fixed: the lengths read declared unbounded, preferring
`schedule.details` (`1d8c11ea`); this evidence file. Declined, each answered on its thread: group findings on runs
(the P1; an empty group exports nothing and `groups.all` shows it), Locate opening the group and selecting the run
(above, for Ed), the stored quantity cap (no users or saved models yet), `shared` for a single component placement
(the layer's walk, which piping reads; follow-up), an unreadable catalog record refusing the schedule (piping's and
thermal bridges' precedent).

Codex gpt-6.2-sol cycle 2 on `1d8c11ea`: 4 P2, 2 P3. Fixed in `c94cdca4`, which merges unreviewed after the two-cycle
cap: a test that a second quantity is a second run; the guide on what blocks export. Declined, each answered: an
oversized stored id (every line-group record checks ids as strings; follow-up for both features), the details read
refusing while a Duct Type is unreadable (a second paged lengths read would spend bytes P4-14e and P4-14f need), the
non-compact page past one reply (the layer's shared behavior; compact fits), `duct_types.list` walking before paging
(as piping's; follow-up).

Follow-ups for the layer, each changing piping too: id patterns on stored references; compact by default or capped
detail rows; measuring used length after the page check; `shared` from real placement counts.

## Gate

- `make ci` on the final code head `c94cdca4`, Ruby 3.2.2: "Ruby suite, 10 processes: 3602 runs, 50778 assertions, 0
  failures, 0 errors, 2 skips"; JS "pass 1226", "fail 0"; Python "460 passed, 17 skipped" (the worktree's `phx` group
  unsynced); hostkit "48 runs, 268 assertions, 0 failures"; "RBZ verified: 857 files, 9064193 bytes, 27859506 bytes
  installed". Ruby 2.7.2 (`RUBY=.../2.7.2/bin/ruby make ci`), the same head: "Ruby suite, 10 processes: 3602 runs,
  50778 assertions, 0 failures, 0 errors, 2 skips"; JS "pass 1226"; Python "460 passed, 17 skipped"; hostkit "48 runs";
  "RBZ verified: 857 files, 9064187 bytes, 27859500 bytes installed".
- PHX: `uv run --group phx pytest tests/python` on `c94cdca4`: "486 passed, 1 skipped" (`test_map_borders.py`,
  `PH_COMPOSER_MAP_DATA` unset); `-k phx_round_trip`: "26 passed, 461 deselected", none skipped (nothing here exports).
- Browser checks: `make ui-checks` on `c94cdca4`, after the last review fix: 40 of 40 scripts pass, exit 0, none
  skipped (no panel change).
- Runtime and panel manifests: `vendor.py --check` verified, `make panel-manifest-check` "up to date: 150 modules, 4
  pages" (no shipped panel or Python file changed).

- Design System: not needed. The re-sync owed from P4-13e was already done (the artifact's `lastChange` names
  `main@98ba249c`, `hours_per_day` added); nothing under `src/ph_composer/html/` or `core/units.rb` changed on `main`
  since, and this stage changes neither.
- The first 3.2.2 run on `4ef8d0dc`'s tree failed one unrelated test, `SpacesReadoutsTest#test_a_volume_with_no_height_keeps_its_label_and_draws_no_outline`
  (`KeyError: key not found: "ph_composer.spaces.show"`); it passed alone three times and in every later run.
