# P4-14b: the shared line-group layer

DATE: 2026-11-24
STATUS: In review 2026-11-25 on `feat/phase-07-mechanical-p4-14b` (#582), on `main`; offline evidence in [p4-14b-line-group-layer](../evidence/p4-14b-line-group-layer.md); no host case of its own (M13b to M13e owed to MS3). Planned in full 2026-11-24 from [P4-14](p4-14-erv-ducting.md), "Size" and "Inferred in planning", P4-13e's recorded handover ([its evidence](../evidence/p4-13e-piping-view.md), "Recorded at implementation") and `context/EXTENSIBILITY.md`. Scoped. The shared-layer inference in P4-14 proceeded under Ed's standing approval for consolidating code; authorized with every stage on 2026-11-23 (STATUS, "Entry gates"). No host case of its own: the MS3 sitting runs M13b to M13e on the moved code.
AUTHOR: Ed May, BLDGTYP, with Claude
ISSUE: #562

## Entry and scope

Requires P4-14a and Ed's answer. Owns one move, with no change of behavior:

- A foundation package, `src/ph_composer/line_groups/` (Ruby `LineGroups`), holding the mechanics a line group
  needs, parameterized by the feature that uses it: a Group outside every Zone that holds loose drawn lines and links
  to one record; an Edge record directly in it; their reference targets, write steps, occurrence walk, selection rows,
  schedule paging and Locate.
- Piping moved onto it: every piping operation, result, refusal and golden the same.

Behavior owner: piping as built (P4-13b to P4-13e) and `context/TECH_STACK.md`, "Edge-owned assignments". Names: this
document, folded into `context/EXTENSIBILITY.md` and `context/TECH_STACK.md` in step 5. Pattern: P4-13c's move of the
chain rule to `core/edge_runs.rb`, a thin adapter left in the feature.

Review: the strong lane, `gpt-6-astra`, with the architecture rubric: a new generic seam beside the foundation, and a
move of shipped piping code.

Paths are relative to `src/ph_composer/`.

## What the sources settle

- "Keep domain behavior inside its owning feature unless several features need it and no feature owns it"
  (`context/EXTENSIBILITY.md`, the opening rules). Piping and ducting both need these mechanics; neither owns the
  other, and ducting may not name piping (P4-14, "The feature").
- `core/` names no shell (P4-13e's review, which declined moving the edge tool there). The parts below call
  `Pages` (`shell/pages.rb`), `EditContext` (`session/edit_context.rb`) and `ph_composer.context.open`, so they sit
  in a foundation package beside `colour_by/` and `export/`, loaded through `extension.rb`'s
  `FOUNDATION_DIRECTORIES`.
- A module outside `features/` names no feature (`tests/panel_layout_test.js` for the panel; the dependency tests for
  Ruby). `Zones::ChildLookup` (`features/zones/zone/index.rb`, eight lines, a per-read child index) is a feature
  class, so the layer takes an index with `matching(entities, persistent_id)` from its caller.

## Inferred in planning

- **What moves**, each with its kind, dictionary, prefix, label and linked-record key made parameters of one
  descriptor the feature builds once (`LineGroups::Spec`):

  | From `features/piping/` | To `line_groups/` | What it does |
  | --- | --- | --- |
  | `group/reference_target.rb` (the walk, `along!`, `located`, the path schema) | `group_target.rb` | Find every line-group occurrence by root-to-Group path, through Groups and components, once per placement; resolve a path step by step with `target.*` refusals |
  | `assignment/reference_target.rb` | `edge_target.rb` | Edge records directly in a line group by root-to-Edge path; refuse an Edge outside one |
  | `group/steps.rb`, `assignment/steps.rb` | `steps.rb` | Create an empty Group at the root with its record and open it; write and clear Edge records, one operation |
  | `scan/occurrences.rb`, the walk only | `scan.rb` | One walk: each occurrence's path, record, name, direct Edges, transform and `shared` |
  | `assignment/selection.rb`, the row building | `selection.rb` | The native selection under the active path as Edge references, with ignored entities counted |
  | `scan/schedule_pages.rb`, the paging | `schedule_pages.rb` | A schedule a bounded page at a time; the feature supplies its parts and name fields |
  | `run_locate.rb` | `locate.rb` | Select a run's Edges and frame them, opening the group through `ph_composer.context.open` |

  What each piping file keeps is its schema, its rows' fields and its names: `Piping::Group::Target` becomes a thin
  call into `LineGroups::GroupTarget` with piping's spec, and so on, as `Runs::Chains.build` is over `EdgeRuns`.
- **What stays in piping**: schemas, operations, declarations, the tree, recirculation, findings, the schedule's rows,
  Colour-by and the pipe tool. The pipe tool and Colour-by stay because ducting has no tool and its modes are small;
  a later duct tool could share the pipe tool's gesture from here.
- **No public change.** No operation, schema, code or result changes, so no API bump, `make fixtures` changes
  nothing, `docs/API_REFERENCE.md` is byte-identical, and the piping goldens (`tests/fixtures/piping/`) are
  byte-identical.
- **The size** is about 35 KB of piping moved and about 6 KB of parameter plumbing added (P4-14, "Size").

## Steps

1. **The package.** `line_groups/` with the files above, `LineGroups::Spec`, and `extension.rb`'s
   `FOUNDATION_DIRECTORIES` gaining `line_groups` after `colour_by`. Nothing in it names a feature, a kind id, a
   Hot Water System or a role.
2. **Piping onto it.** Each piping file in the table becomes its adapter; the declarations and operations are
   untouched apart from what they call.
3. **Hold the line.** Every piping test passes unchanged; the goldens and `docs/API_REFERENCE.md` are byte-identical;
   `make fixtures` writes nothing.
4. **Stale cases.** `uv run tools/hostkit/acceptance_ledger.py status --changed` over the moved files; record the
   count and the cases it names (expected: M13b to M13e, all owed to MS3, none a Pass), and update their dependency
   patterns in `planning/native-acceptance/cases.json` to include `src/ph_composer/line_groups/**`.
5. **Documents.** `context/EXTENSIBILITY.md` (a short section: what a line group is, the spec a feature builds, what
   stays in the feature), `context/TECH_STACK.md`, "Edge-owned assignments" (the piping bullet names the layer),
   `context/UBIQUITOUS_LANGUAGE.md` (Line group: a Piping group or a Ducting group, a Group outside every Zone that
   holds drawn lines and links to one record).

## Source

| PH-Composer file | Disposition |
| --- | --- |
| `features/piping/` (the seven files above) | Moved to `line_groups/`; thin adapters stay |
| `core/edge_runs.rb`, `features/thermal_bridges/runs/chains.rb` | The pattern of a move with an adapter |
| `extension.rb` | `FOUNDATION_DIRECTORIES` |
| `tests/piping_*_test.rb`, `tests/fixtures/piping/` | Must not change |

## Tests (write first)

1. Layer (`tests/line_groups_test.rb`): a probe spec (a test-only kind and dictionary) finds two placements of one
   group as two occurrences, resolves a group and an Edge path, refuses an Edge outside a group, creates and opens
   an empty group in one Undo step, writes and clears an Edge record, pages a probe schedule and locates two Edges;
   a grep test that nothing under `line_groups/` names a feature id (`ph_composer.piping`,
   `ph_composer.ducting`, `ph_composer.zones`, `ph_composer.mechanical`) or a feature module (`Piping`, `Ducting`,
   `Zones::`, `Mechanical`); the foundation's own `ph_composer.context.open` is allowed.
2. Piping: every existing test passes with no edit; the goldens are byte-identical.

## Host gate

None of its own. The MS3 sitting runs `M13b` to `M13e` on the build carrying the moved code, which their updated
dependency patterns make it do. Offline `make ci` passes on this sub-stage's PR.

## Out of scope

Anything ducting adds (P4-14c onward). Moving the pipe tool or Colour-by. Any change to piping's behavior.

## Stop

If the architecture review declines the package, or a part above cannot move without changing a piping result, stop
and report with the part named; P4-14c and P4-14d then copy piping's shape for that part and the size line in P4-14
is re-read.

## Done when

- P4-14b's row in ACCEPTANCE has offline evidence in `../evidence/p4-14b-line-group-layer.md`, with the stale-case
  count and the byte-identical goldens.
- `make ci` passes on both Rubies; the installed size is recorded against the 6 KB estimate.
