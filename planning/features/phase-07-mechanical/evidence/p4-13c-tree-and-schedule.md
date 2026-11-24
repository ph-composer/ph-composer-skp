# P4-13c evidence: the chain rule in core, the tree and the schedule

DATE: 2026-11-24
Register row: [M13c](../ACCEPTANCE.md). Stage: [P4-13c](../phases/p4-13c-tree-and-schedule.md), under the parent index
[P4-13](../phases/p4-13-hot-water-piping.md).
Base: built on `feat/phase-07-mechanical-p4-13b` at `7b84423c`, rebased onto `main` at `2f360b5b` after #577 merged
(identical tree).

Offline evidence only. No SketchUp process was started. The host case `M13c` (in
`planning/native-acceptance/cases.json`: the schedule against the hand measurement, a broken branch, `runs.locate` into
a wrapped group, identifiers across save and reopen, the host measurement and the stale thermal-bridge cases) is owed
to the MS3 sitting (D4-31). M13c stays Open.

## What was built

| Step | Where | Note |
| --- | --- | --- |
| 1. The chain rule to core | `core/edge_runs.rb` (`EdgeRuns`); `features/thermal_bridges/runs/chains.rb` | A generic fact (`path`, `key`, `vertex_ids`, `points_m`, `item`) and run (`key`, `container_path`, `closed`, `points_m`, `edge_paths`, `facts`, `length_m`, `items`), the canonical order and the point keys; names no feature. `Runs::Chains.build` keeps its signature and output: it keys by Zone path, type and `quantity.to_f`, reads each run's Zone, type and quantity from its first Edge and mints `tb_` identifiers as before |
| 2. Scan | `features/piping/scan/occurrences.rb` | One walk through Groups and components, once per placement; a fact per pipe directly in a readable Piping group with world metres and vertex ids, `shared` through component or shared Group storage; unreadable group and pipe records (bad JSON, not an object, failing the schema) as `record.unreadable` rows; Zones' containment read only for the group paths, and only by the schedule |
| 3. Runs and the tree | `runs/tree.rb` | `EdgeRuns` keyed by group occurrence, role, Pipe Type and role values (numbers as floats); parents by shared vertex, the first identifier of two; `pipe_` run and `pipe_seg_` segment identifiers; display names per System and role |
| 4. Recirculation | `runs/recirculation.rb` | honeybee-ph's arithmetic step for step: segment length as ladybug-geometry's magnitude, left-to-right sums as CPython 3.11, run means then System means, `int()` truncation |
| 5. Findings | `runs/findings.rb`, `codes.rb` | The stage doc's table; `piping.hidden` for locate |
| 6. Schedule and locate | `runs/schedule.rb`, `scan/schedule_pages.rb`, `run_locate.rb`, `declarations/schedule.rb`, `declarations/pipe_types.rb`, `type/reads.rb` | `ph_composer.piping.schedule` (bounded, `compact`), `ph_composer.piping.runs.members`, `ph_composer.piping.systems` with the snapshot section `ph_composer.piping.piping_systems`, `ph_composer.piping.runs.locate`; `pipe_types.list` and `.all` rows gain `used_length_m`; API 1.100 with one `CHANGES` row; `make fixtures` |
| 7. Measure | below | |
| 8. Documents | `context/CONTRACTS.md` ("Hot water piping"), `context/TECH_STACK.md` ("Edge-owned assignments"), `context/AGENT_INTERFACE.md`, `context/UBIQUITOUS_LANGUAGE.md` (Role), `docs/AGENT_GUIDE.md` and the shipped guide, the packet CONTRACTS (sections 3 and 6) | |
| Host case | `cases.json` `M13c`; `core/edge_runs.rb` added to the paths of `T04`, `T08` and `T09` | No walkthrough script yet: the MS3 sitting builds the piping case from the M13b walkthrough and reads the schedule; a measurement script like `thermal_bridge_measurement.rb` is owed to that sitting's preparation |

## The move: goldens and stale cases

- `tests/fixtures/thermal_bridges/extraction.json` and `result_fields.json` are byte-identical after `make fixtures`
  (`git status --short tests/fixtures` empty).
- Phase 3b's chain-rule cases (U, square, T; one container and never across containers; two placements; any input
  order; a loop hung from a junction) moved to `tests/edge_runs_test.rb` over generic facts, with a fact's item read
  back and a grep that `core/edge_runs.rb` names no feature. `tests/thermal_bridge_runs_test.rb` keeps an adapter test
  (the adapter's runs equal core's, Zone, type and quantity read back, two placements two identifiers) and every other
  test unchanged; one assertion added, below.
- `uv run tools/hostkit/acceptance_ledger.py status` with `--changed` for every path changed outside
  `features/piping/` and `planning/` against `7b84423c` (the two the stage doc names plus `shell/api.rb`, the shipped
  guide, `docs/API_REFERENCE.md` and the tests): 28 cases named. Needs recheck (24): `A04`, `A09`, `R01` to `R06`,
  `E15`, `E17`, `UXR-SOLVE`, `UXR-FILTER`, `UXR-HATCH`, `UXR-PAINT`, `UXR-COLOUR`, `UXR-FILTER-OCC`, `T04`, `T08`,
  `T09`, `LH1`, `AW02`, `AW10`, `EUD09`, `EUD09X`. Historical evidence named (4): `A03`, `A07`, `A12`, `A16`. All 24
  read `needs_recheck` already at the base `7b84423c` (a detached worktree, `status` with no `--changed`), so the
  stage stales none that was current. Of them, the move's own two paths name `T04`, `T08`, `T09`, `E17` and `AW10`
  (and `A16`'s historical row, through `core/*`); the rest are named by `shell/api.rb`'s API bump. `core/edge_runs.rb`
  alone named only `E17` and `A16`, so it was added to `T04`, `T08` and `T09`'s paths. MS3 repeats `T04`, `T08` and
  `T09` with `M13c`.
- One representational difference: a thermal-bridge run whose Edges mix a quantity of 1 and 1.0 reads the quantity of
  its first Edge in run order; before the move it read the Edge its walk began from. The value is equal either way and
  no golden or reference model mixes them; `test_a_quantity_of_one_and_one_point_zero_is_one_run` pins the new rule.

## Step 7: the measurement

A synthetic stub Model of 50,000 Edges: twenty Piping groups at the root, each a chain of 100 pipes (25 each of
trunk, branch, twig and recirculation, so 80 runs), and 48 plain Groups of 1,000 loose Edges. Each read timed seven
times through `API.query`, median, on an Apple M1 Max (a scratch script beside the test helper, not committed):

| Read | Ruby 3.2.2 | Ruby 2.7.2 |
| --- | --- | --- |
| `ph_composer.piping.schedule`, `limit` 500 | 60.9 ms | 74.9 ms |
| `ph_composer.piping.systems` | 55.5 ms | 69.0 ms |
| `ph_composer.piping.pipe_types.all` | 54.4 ms | 70.9 ms |
| The walk alone (`Scan.walk`) | 6.1 ms | 7.8 ms |

On 3.2.2 the parts were: building the facts (record reads and schema checks) 34 ms, the tree 22 ms, of it the core
chain rule 15 ms. P3b-04's thermal-bridge figure, 1.84 s, was measured on the host at 5,000 assigned Edges, where the
cost was Zones' per-path answers; the piping reads ask Zones nothing but the group paths, so the two are not
comparable offline. Both snapshot reads are under the 200 ms target offline, so `ph_composer.piping.piping_systems` is
registered and `pipe_types.all` carries `used_length_m`, as the stage doc says. Each walks the Model on every panel
refresh. A stub Model is not the host: the host figure is `M13c`'s, and over 200 ms both leave the snapshot.

## Inferred beyond the stage doc

- **Two recirculation runs on the piping case.** Test 3 said one; the case's two loop lines differ in temperature and
  hours, and the run key includes the role values, so they are two, as the case's "Expected" line says.
- **3.3 m and 1.7 m at 24 h (for Ed).** As one run of two pipes the hours read 24. As two runs honeybee-ph's own
  `recirc_hours` reads 23 (checked on the pinned 1.33.68 wheel in the repository's Python 3.11:
  `79.19999999999999 / 3.3` is `23.999999999999996`), and this read must equal the export, so it reads 23 too.
  Nesting cannot keep 24 for every split; a fix belongs in honeybee-ph (rounding before `int()`).
- **The order of the sums.** Runs add in schedule order and pipes in run order; P4-13d must add elements and segments
  in that order for float equality.
- **`compact`, `schedule.details` and `runs.members`.** A page carries each run's `edge_paths` and each finding's, and
  every System, Pipe Type and unreadable row; one long run, one long name or many records would pass an agent's 24 KiB
  reply, which the executor refuses. As thermal bridges' `schedule.list`, `compact` counts the paths and leaves the
  three lists out, counted; `ph_composer.piping.schedule.details` pages those lists and
  `ph_composer.piping.runs.members` one run's pipes, or a finding's. Names from user text and finding messages are cut
  to 256 and 512 characters and named in `truncated`. A compact page and every details page fit one reply with a
  30,000-character name and 60 unreadable records (`tests/piping_schedule_test.rb`).
- **`water_temp_c` 0 to 100.** The pipe assignment's temperature had no bound, so a stored `1e308` made the
  recirculation sum infinite, which no JSON reply carries. The schema now takes 0 to 100 °C; a stored record outside it
  reads as unreadable.
- **Locate takes pipes only.** A path that does not end at an Edge carrying a pipe record directly in a Piping group
  refuses `target.wrong_kind`; repeated paths are selected once. `piping.hidden` is a new code, as thermal bridges'
  `thermal_bridge.hidden`.
- **Group findings sit on each run of the group**, so every finding names pipes for `locate`; a group with no pipes
  has no run and so no finding.
- **`ph_composer.piping.systems` and `pipe_types` used length skip Zones**, so an unreadable Zone record does not
  refuse them; only the schedule reads `piping.group_in_zone`.
- **Section and query names.** The query is `ph_composer.piping.systems` and the section
  `ph_composer.piping.piping_systems`, as `heat_pumps.blended` and `heat_pumps_blended`.
- **Pure facts for P4-13d.** `Runs::Fact` carries the group as a detached hash, so P4-13d builds facts from the
  snapshot's group and edge entries and calls `Runs::Tree`, `Runs::Findings` and `Runs::Recirculation` unchanged.

## Tests

`tests/edge_runs_test.rb` (7), `tests/piping_runs_test.rb` (11, the piping case and its variants, identifiers,
recirculation vectors, each finding on its case), `tests/piping_schedule_test.rb` (8, the stub Model: the case through
the API, unreadable records as rows, the scan writing nothing and opening no operation, Zone-held and pasted groups,
locate refusals, compact and members, used length), `tests/thermal_bridge_runs_test.rb` (the adapter test replacing
the two moved tests, one assertion on a mixed quantity). The registry's reference test and `tests/agent_guide_test.rb`
cover the new operations and the recipe.

## Review

Codex gpt-6-astra cycle 1 on `79f98ede`: 2 P2, both fixed in the next commit. The System and Pipe Type rows beside the
runs, with uncut names, and the 50 unreadable messages could pass one reply even with `compact` and `limit` 1 (now
cut, left out of compact pages and paged by `schedule.details`). A run's parents were deduplicated by `uniq` on whole
Run Structs, hashing their pipes and the tree: an alternating-type branch over 1,998 pipes took 1.24 s in `Tree.call`
(Codex's figure); by identity it takes 41 ms (scratch, Ruby 3.2.2), with a test for a branch touching its trunk twice.


Sonnet adversarial read before the gate: 13 findings. Fixed: an unbounded `water_temp_c` could make the sum infinite
(schema bound); names and messages uncut and long runs past a reply (cut, `compact`, `runs.members`); the two doc
corrections above; evidence and the stub-only measurement stated as such; the thermal-bridge quantity sample pinned by
a test and recorded; locate accepting any Edge and repeated paths; table-driven tests for malformed records, used
length on the list, compact and members; `Tree.call` returning its order explicitly; the scan's helpers private.
Declined: an unreadable Pipe Type or Hot Water System refuses the schedule and the Systems read, as thermal bridges'
schedule refuses an unreadable type, and a refusing snapshot section fails alone (`shell/snapshot.rb`); the core grep
pattern is wide enough for what it guards; the recirculation test's run double reads only `facts`, as the module does.
