# P4-14b evidence: the shared line-group layer

DATE: 2026-11-25
Register row: [M14b](../ACCEPTANCE.md). Stage: [P4-14b](../phases/p4-14b-line-group-layer.md), under the parent index
[P4-14](../phases/p4-14-erv-ducting.md).
Base: `main` at `295a4a15` (#581 merged before this PR opened; the branch was cut from #581's head `95b1be8f`, whose
tree equals `295a4a15`). Code commit `f0f5923d`; PR [#582](https://github.com/ph-composer/ph-composer-skp/pull/582).

Offline evidence only. No SketchUp process ran during this stage (`pgrep -x SketchUp` empty before each gate). This
stage has no host case of its own: the MS3 sitting runs `M13b` to `M13e` on the build carrying the moved code, which
their dependency patterns now name. M14b stays Open.

## What was built

| Step | Where | Note |
| --- | --- | --- |
| 1. The package | `line_groups/spec.rb`, `group_target.rb`, `edge_target.rb`, `steps.rb`, `scan.rb`, `selection.rb`, `schedule_pages.rb`, `locate.rb`; `extension.rb` | `LineGroups`, loaded through `FOUNDATION_DIRECTORIES` after `colour_by`. `LineGroups::Spec` carries the label and Edge noun, the two target kinds, stores and record kinds, the linked-record key, four codes and the child-index factory. `LineGroups.read`, `contents` and `scannable` moved from `features/piping/group/schema.rb` |
| 2. Piping onto it | `features/piping/line_group.rb` (the spec), `group/reference_target.rb`, `assignment/reference_target.rb`, `scan/occurrences.rb` (the walk), `assignment/selection.rb` (the rows), `scan/schedule_pages.rb` (the paging), `group/schema.rb`; `group/operations.rb`, `assignment/operations.rb`, `declarations/schedule.rb` call the layer's steps, pages and Locate | Each target, the walk, the selection and the schedule pages keep piping's schemas, constants and public names and call the layer with `Piping::LINE_GROUP` |
| 3. Hold the line | | Every piping test unedited; `tests/fixtures/` and `docs/API_REFERENCE.md` byte-identical; no API bump |
| 4. Stale cases | `planning/native-acceptance/cases.json` | `M13b` to `M13e` name `src/ph_composer/line_groups/*` and `features/piping/line_group.rb`; `M13c` drops the deleted `run_locate.rb` |
| 5. Documents | `context/EXTENSIBILITY.md` ("Line groups"), `context/TECH_STACK.md` ("Edge-owned assignments", the piping bullet), `context/UBIQUITOUS_LANGUAGE.md` (Line group) | |

## Inferred beyond the stage doc

- **Three piping files are gone, not thinned.** `group/steps.rb`, `assignment/steps.rb` and `run_locate.rb` held only
  what moved; an adapter subclass or one-line module would have cost bytes against the size line for nothing, so
  `group/operations.rb`, `assignment/operations.rb` and `declarations/schedule.rb` build `LineGroups::CreateStep`,
  `GroupWriteStep`, `EdgeWriteStep` and call `LineGroups::Locate` with the spec, and the schedule declarations call
  `SchedulePages::PAGES`. The other four files in the stage doc's table stay as adapters.
- **The record reads moved too.** The layer needs `read`, `contents` and `scannable`, which lived in
  `features/piping/group/schema.rb` (outside the table); they are `LineGroups.read`, `contents` and `scannable`, and
  piping's `Group.read`, `contents`, `scannable` and `validate!` delegate.
- **What a caller passes per call.** Zones' containment (`contained:`, the query id names Zones) and the gesture limit
  (`limit:`, which tests lower) are arguments to `LineGroups::Selection`, never in the frozen spec. The child index is
  a factory on the spec, since steps resolve at apply with no request.
- **Names the spec derives.** The `affected` kind and step names come from the label in snake case
  (`piping_group`, `create_piping_group`, `piping_groups`) and the Edge noun (`pipe`, `pipes`), so the noun is one word.
  A compact schedule page's count keys (`system_count`, `type_count`) are the feature's `counts:`, not derived.
- **A schema-version check** reads the Edge record kind's `schema_version` (1 for pipes) instead of a literal 1.

## Tests

`tests/line_groups_test.rb` (9), a probe spec with its own dictionaries and codes: two placements of one group are
two `shared` occurrences, two group entries and every Edge entry; a group path and an Edge path resolve, the Edge
refuses `target.shared_definition` when mutable, and an Edge in a plain Group refuses the probe's outside code; an
empty group created and opened in one operation, its `affected` and descriptor names, removed by one Undo; an Edge
record written, cleared and a stale write refused `target.changed`; a probe schedule paged compact two runs at a time
with its count key, a run's members and a detail list, an unknown run refused with the probe's run label; Locate
selects two Edges and opens their group, and a path to a plain Group's Edge refuses; the selection rows with the
group, values, ignored count, a Zone-held refusal with the probe's code, an assignable row and the gesture limit; a
nested group and a hidden Edge refuse with the probe's codes; a grep that nothing under `line_groups/` names
`ph_composer.piping`, `.ducting`, `.zones` or `.mechanical`, or `Piping`, `Ducting`, `Mechanical` or `Zones::`.

Piping: every `tests/piping_*_test.rb` and `tests/pipe_types_walkthrough_test.rb` unedited and passing. String check:
every string literal of the nine old piping files is reproduced by the layer with the spec's label, noun and run label
substituted (a scratch `comm` of the literal sets; the only differences are literals split across lines).

## Gate

- `make ci` on Ruby 3.2.2 on the working tree before the first commit: "Ruby suite, 10 processes: 3563 runs, 50062
  assertions, 0 failures, 0 errors, 2 skips"; JS "pass 1226", "fail 0"; Python "460 passed, 17 skipped" (the
  worktree's `phx` group not synced); hostkit "48 runs, 268 assertions, 0 failures"; "RBZ verified: 841 files,
  9037422 bytes, 27786134 bytes installed".
- `make ci RUBY=$(rbenv prefix 2.7.2)/bin/ruby` on the same tree: "Ruby suite, 10 processes: 3563 runs, 50062
  assertions, 0 failures, 0 errors, 2 skips"; JS "pass 1226"; Python "460 passed, 17 skipped"; "RBZ verified: 841
  files, 9037422 bytes, 27786134 bytes installed".
- Installed size: 27,786,134 bytes, 7,260 over the base's 27,778,874 (the same build on `95b1be8f` in this worktree;
  #581 recorded 27,778,880) against the 6 KB estimate, 18 percent over, under the 25 percent stop line. The first
  draft measured 12,454 over; deleting the three adapter files that held only moved code and cutting repeated
  comments brought it here. 213,866 under the 28,000,000 ceiling; less the estimates still to run (P4-14c to P4-14f,
  157 KB) that leaves about 56 KB, above the 40 KB line. `uv run tools/runtime/vendor.py --check`: "Runtime verified:
  223 assets, 8 wheels, 23168678 bytes". No shipped panel or Python file changed, so the runtime manifest and the
  panel manifest needed no refresh.
- Byte-identical: `make fixtures` wrote nothing, and `git diff --stat 295a4a15 -- tests/piping_*
  tests/pipe_types_walkthrough_test.rb tests/fixtures docs/API_REFERENCE.md src/ph_composer/agent_access/guide.md` is
  empty. No API bump.
- PHX round trips: `uv run --group phx pytest tests/python -k phx_round_trip`: "26 passed, 461 deselected" (this
  stage exports nothing new). Whole group: "486 passed, 1 skipped" (`test_map_borders.py`, `PH_COMPOSER_MAP_DATA`
  unset).
- Browser checks: `make ui-checks` on the same tree: 40 of 40 scripts (`tools/ui-preview/*.cjs`), exit 0, none skipped (no panel
  change).
- Design System: not needed. P4-14a re-synced it from `main@98ba249c` as version 41; nothing under
  `src/ph_composer/html/` changed since, on `main` or here.

## Stale cases

`uv run tools/hostkit/acceptance_ledger.py status` with `--changed` for each of the 22 changed, added or deleted paths
(source, tests, `context/` and `cases.json`): 30 of 160 cases name one, 23 of them through `extension.rb` alone. By
state: `needs_recheck` 12 (A02, A04, A05, A09, A11, R01, R02, R03, R04, E17, LH1, AW10), every one already
`needs_recheck` on the base `95b1be8f` with no change named, so this stage stales no current Pass;
`historical_affected` 10 (A01, A03, A06, A07, A08, A10, A12, A13, A14, A16); `deferred` 1 (A15); `not_run` 7 (E02,
M13a, M13b, M13c, M13d, M13e, M14a). `M13b` to `M13e` are owed to MS3, as expected; none was a Pass. No change is
unmapped. Nothing was rerun.

## Review

Sonnet adversarial read before the gate: no behavior drift (every message, code, key order, step name, `affected` row
and traversal order matched line by line). Fixed: the layer test now covers the selection rows (group, values, ignored
count, a Zone-held refusal, the gesture limit), a nested group and a hidden Edge with the probe's codes; the probe's
Edge noun is one word and the Spec says the noun is also the step name; two comments no longer name Zones;
EXTENSIBILITY names the session beside the shell. Declined: memoizing the Edge id pattern (one Regexp per selected
Edge, at most 250 a gesture, not measurable); a layer that never says "Zone" (a Zone-held group is a line group's own
refusal, and the containment read stays the caller's); the glossary's Ducting group (P4-14a added the term).

Codex, gpt-6-astra (the strong lane), cycle 1 on `f0f5923d`: no findings, verdict approve; its residual gaps are that
its read-only sandbox could not run the focused tests (it read the gate evidence) and the owed MS3 cases. No code
changed after it, so no second cycle.
