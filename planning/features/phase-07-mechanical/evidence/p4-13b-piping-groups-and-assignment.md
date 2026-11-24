# P4-13b evidence: Piping groups and the pipe assignment

DATE: 2026-11-24
Register row: [M13b](../ACCEPTANCE.md). Stage: [P4-13b](../phases/p4-13b-piping-groups-and-assignment.md), under the
parent index [P4-13](../phases/p4-13-hot-water-piping.md).
Base: built on `feat/phase-07-mechanical-p4-13a` at `ba5cbe88`, rebased onto `main` at `99a712a8` after #576 merged (identical tree).

Offline evidence only. No SketchUp process was started. The host case `M13b` (in
`planning/native-acceptance/cases.json`: H1 an empty group created by `groups.create` survives the commit and opens,
H2 the Line tool draws into it, H3 T-split and crossing splits of loose Edges in a faceless group, H4 assign and clear
over a native selection and a pasted group refusing until made unique, and the System delete's retarget) is owed to
the MS3 sitting (D4-31). M13b stays Open.

## What was built

| Step | Where | Note |
| --- | --- | --- |
| 1. Group record and target | `features/piping/group/schema.rb`, `reference_target.rb` | `ph_composer.piping.group` on a Group, `ppg_`, `hot_water_system_id` (string or null, a `one` reference to the System), claims its Group; target `{group_id, group_path}`, its own path walk (pipes sit outside Zones), refusing a nested group, a locked or shared step |
| 2. Group operations | `group/operations.rb`, `steps.rb`, `declarations/groups.rb` | `groups.create` (an empty Group at the root, the record, `EditContext.enter`, one step), `groups.link`, `groups.unlink` (guarded, at most 250, `piping.group_in_zone` from `zones.containment`), `groups.all`, the bounded `groups.list` |
| 3. Pipe record and target | `assignment/schema.rb`, `reference_target.rb` | `ph_composer.piping` on an Edge, `ppe_`, `pipe_type_id` (string or null), `role`, the role's values (trunk `multiplier` and `demand_recirculation`, recirculation `water_temp_c` and `daily_period` 0 to 24), required for the role and absent for the others; `GESTURE_EDGE_LIMIT` 250; target `{group_path, entity_path, entity_id}`, refusing `piping.outside_group` |
| 4. Assign and clear | `assignment/operations.rb`, `steps.rb`, `declarations/pipes.rb` | Every target resolved through one child index and the groups' Zone containment read once before any write; one step; a fresh `ppe_` id on a first assignment; `session.changed` from the dispatcher |
| 5. Selection | `assignment/selection.rb` | `pipes.selection` (bounded), `pipes.selection_all`, the `pipes.selected` snapshot section and a `Client` for the assign bar |
| 6. Delete in use | `assignment/operations.rb` (`delete_type`, `replace_type`), `declarations/pipe_types.rb`; `mechanical/hot_water/operations.rb`, `declarations/hot_water.rb`; `group/operations.rb` (`retarget`) | See "Inferred beyond the stage doc" |
| 7. Declarations | `codes.rb`, `shell/api.rb` | Codes `piping.outside_group`, `piping.group_in_zone`, `piping.group_nested`; API 1.99 with one `CHANGES` row; `make fixtures` |
| 8. Documents | `context/CONTRACTS.md` (storage rows, "Hot water piping", the System delete), `context/TECH_STACK.md` ("Edge-owned assignments"), `context/AGENT_INTERFACE.md`, `docs/AGENT_GUIDE.md` and the shipped guide, `docs/USER_DATA.md`, packet CONTRACTS | |
| Host case | `tools/examples/authoring/piping_assignment_walkthrough.rb`, its README section, `tests/piping_assignment_walkthrough_test.rb`, `cases.json` `M13b` | |

## Inferred beyond the stage doc

- **The Hot Water System delete (for Ed).** The stage doc's stop condition was met: Mechanical's System delete did not
  route other features' referrers through the engine. With a Piping group naming System A, a scratch probe on
  2026-11-24 read `refused reference.in_use` "ph_composer.piping.group ppg_AAAAAAAAAAAA still refers to
  ph_composer.mechanical.hot_water_system hws_…" for the delete with no replacement, with `replacement_id` B and with
  null. The stage stopped and reported. The conductor chose the generic seam: the System delete calls
  `request.retarget_references` with an id or null and joins that plan to Serves' (`HotWater::Operations.with_retargeted`),
  naming no feature; piping registers `ph_composer.piping.groups.retarget_hot_water_system`. A group the retarget
  cannot reach (locked, shared, nested) refuses the delete `reference.in_use`.
- **Pipe Type delete.** Piping owns both the type and the pipes, so `pipe_types.delete` calls
  `Assignment::Operations.delete_type`, which rewrites every pipe (or nulls its type) and hands the plan to the
  type's delete; `PipeType` still names no Edge.
- **Stores in `schema.rb`**, as thermal bridges'; no `store.rb`.
- **A same-role reassign keeps its role values**; a new role takes its defaults.
- **No repair route.** Unreadable text on an Edge or group refuses every write through it; deletes pass over it.
- **`groups.create` takes no shown-Model or idle-tool check.**
- **Rewrites reach misplaced groups.** A Pipe Type or System delete rewrites a group a Zone holds, so no reference
  dangles; assign, clear, link and unlink refuse it.

## Tests

`tests/piping_group_test.rb` (6), `tests/piping_assignment_test.rb` (8), `tests/piping_assignment_walkthrough_test.rb`
(1), and one in `tests/mechanical_hot_water_test.rb` (a probe feature's record retargeted by a System delete with an
id and with null, one Undo step). The registry's reference test and `tests/agent_guide_test.rb` cover the new
operations and the recipe.

## Gate

- `make ci` on Ruby 3.2.2 on the tree of `0954e2a3` (rebased unchanged as `3dc8715d`): "Ruby suite, 10 processes:
  3478 runs, 49440 assertions, 0 failures, 0 errors, 1 skips"; JS 1214 pass, 0 fail; Python 467 passed, 1 skipped;
  hostkit 48 runs; "RBZ verified: 804 files, 8956811 bytes, 27557624 bytes installed".
- Installed size: 27,557,624 bytes, 70,697 over P4-13a's 27,486,927 against the 75 KB estimate; 442,376 under the
  28,000,000 ceiling. No shipped panel or Python file changed.
- Final head `d232556d`, after both review cycles: `make ci` on Ruby 3.2.2 and on 2.7.2: "Ruby suite, 10 processes:
  3481 runs, 49468 assertions, 0 failures, 0 errors, 1 skips"; JS 1214 pass; Python 467 passed, 1 skipped; hostkit 48
  runs; "RBZ verified: 804 files, 8957684 bytes, 27560479 bytes installed" (3.2.2; 27560473 on 2.7.2), 73,552 over
  P4-13a against the 75 KB estimate, 439,521 under the ceiling.
- Browser checks: `make ui-checks` on `d232556d`: 39 of 39 scripts pass, exit 0, none skipped (no panel change).
- PHX: `uv run --group phx pytest tests/python` on `d232556d`: 467 passed, 1 skipped (`test_map_borders.py`,
  `PH_COMPOSER_MAP_DATA` unset); `-k phx_round_trip`: 24 passed, 0 skipped (this stage exports nothing).
- Design System: not needed; no kit CSS, shared kit part or unit quantity changed.
- `core/records/reference_resolution.rb` changed by one line (cycle 2), so native cases fingerprinting it read stale.

## Review

Sonnet adversarial read before the gate: 15 findings. Fixed: a same-role reassign reset the trunk multiplier;
`groups.link` dropped disagreeing repeats (now `params.invalid`); the System delete's description and side effects now
name other features' records; stranded messages name nested groups; an unreadable group record now refuses a pipe
write and reads as a refusal in the selection; the client passes the first row's refusal; one child index per
command; CONTRACTS lists `pipes.clear` among the Zone refusals and says deletes rewrite misplaced groups; tests for
the shipped limit after reset, `marks?` rather than an empty dictionary, both placements stranded, the walkthrough's
System, a same-role reassign, a stale pipe, an unknown type, nested and Zone-held groups and an unreadable group.
Declined: an unreadable record is invisible to the reference scan (thermal bridges' rule, no repair route this
stage); shared path helpers stay in `Group::Target` (the pipe target composes them); 251 real Edges (the limit is
exercised by lowering it, as thermal bridges do); reopen is a host step (H1).

## Codex review

- Cycle 1, gpt-6.2-sol on `2b6b8753`: 3 P1, 4 P2, 2 P3. Fixed in the next commit: a Piping group under a component
  now refuses `target.wrong_hierarchy` in the shared write check, so reads, preview and both retargeters refuse it
  before a write's Group-only scope does; a pipe or group record whose `user_data` or `extension_data` is not a JSON
  object enters the reference scan without that map rather than failing every delete; a pipe record of another
  schema version refuses `validation.failed` on assign rather than being downgraded; a malformed group record reads as
  a selection row with no group and a `validation.failed` refusal, and refuses a pipe write; both write steps resolve
  through one child index at apply; `pipe_types.delete` names the pipe rewrite in its side effects; the assign
  schema says when a role's values are kept. Declined: clearing many distinct ids runs one engine reference check per
  id, as thermal bridges' clear does, since the engine has no batch removal check (a core follow-up); metadata reads
  and a guarded metadata update for groups and pipes are not in the stage doc's operations (a follow-up for Ed,
  `docs/USER_DATA.md` says "Not yet").
- Cycle 2, gpt-6.2-sol on `30ec21f0`: 1 P1, 5 P2. Fixed in the next commit, which merges unreviewed after the
  two-cycle cap: clear checks incoming references on a pipe whose metadata map is malformed, read as the scan reads
  it, so a record naming it refuses the clear; `pipe_types.delete` rewrites from the record as stored and strands an
  invalid one (`reference.in_use`, with its path) rather than rolling back at apply; the engine's `reference.in_use`
  message names a referrer with no id by its occurrence key rather than raising (`core/records/reference_resolution.rb`,
  one line); the selection gives a record of another schema version a `validation.failed` write refusal; tests for a
  mixed and an over-limit clear refusing whole, the malformed-map referrer and a group with no id. Declined again: one
  engine check per cleared id (core follow-up).
