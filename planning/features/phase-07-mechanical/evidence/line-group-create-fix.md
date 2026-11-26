# Line-group create fix: Make Piping group and Make Ducting group

DATE: 2026-11-26
Issue: #598 (part of #562). Sections: [P4-13b](../phases/p4-13b-piping-groups-and-assignment.md) and
[P4-14c](../phases/p4-14c-ducting-groups-and-assignment.md), "The fallback taken", with the panel parts in
[P4-13e](../phases/p4-13e-piping-view.md) and [P4-14f](../phases/p4-14f-ducting-view.md). Register rows:
[M13b, M14c, M13e and M14f](../ACCEPTANCE.md); M15's label names the new flow.
Base: `main` at `d0adcba8`.

Offline evidence only. No SketchUp process was started. The host cases stay owed to the MS3 sitting's second hold.

## The defect and what the host showed

- **The crash** (MS3 sitting, 2026-11-25, [phase-07-ms3](../../../native-acceptance/evidence/phase-07-ms3.md),
  "The defect"): `ph_composer.piping.groups.create` and `ph_composer.ducting.groups.create` crashed SketchUp
  26.1.188 (`EXC_BAD_ACCESS`), three times through the action and once in raw Ruby. Without the path change, the
  empty Group was gone after the commit: SketchUp deletes an empty Group at commit, and `LineGroups::CreateStep`
  made that Group the active path in the same operation.
- **The probe of the fix's assumptions** (the conductor's first full-screen hold, 2026-11-26, recorded in
  phase-07-ms3, "The probe for the fix", by #599): wrapping selected loose Edges in a new Group by Ruby keeps their
  persistent ids and attribute dictionaries, as one Undo step, and Undo restores the loose Edges; the native Line
  tool draws into an open, labelled Piping group, and a new line meeting an Edge part way along splits it (18 Edges
  became 20, three meeting at the new vertex); Undo "Draw Line" restores the 18.
- Recorded in `context/SKETCHUP_HOST_BEHAVIOR.md`, "Making a line group", with the stub rule that pins the first
  fact.

## What changed

| Part | Where | What |
| --- | --- | --- |
| The make | `line_groups/group_operations.rb` (`GroupOperations.make`), `line_groups/make.rb` (`LineGroups::Make`), `line_groups/steps.rb` (`MakeStep`, replacing `CreateStep`) | `edge_paths` (root-to-Edge, deduplicated, at most the feature's gesture limit) resolved through one child index; the rule below; a new record; one step that finds each line again, still loose, in the open context, and wraps them with `entities.add_group(lines)`. The edit path is left as it was. Nothing in the layer adds an empty Group |
| The selection read | `line_groups/selection.rb` | `all` and `page` add `make_refusal`, `Make.refusal` over the whole native selection |
| Declarations | `features/piping/declarations/groups.rb`, `pipes.rb`; `features/ducting/declarations/groups.rb`, `ducts.rb` | `groups.make` replaces `groups.create` (undo names "Make Piping Group", "Make Ducting Group"); the selection results declare `make_refusal`. API minor 109 |
| The panel | `html/line_groups/assign_bar.js`, `groups.js`, `pill.js`; each feature's `assign_bar.js` and `section.js` | **+ New Piping group** and **+ New Ducting group** become **Make Piping group** and **Make Ducting group**, disabled with `ui.reasonButton` beside them while the read's `make_refusal` is set; the form asks for the linked record, says how many lines move, and sends their paths; the pill renders the bar before the form so the form reads this state's selection |
| The preview | `tools/ui-preview/host.js` | The selection sections answer `make_refusal`; `groups.make` adds the group over the selected loose lines |
| Walkthroughs | `tools/examples/authoring/piping_assignment_walkthrough.rb`, `ducting_assignment_walkthrough.rb` | `draw` (loose, selected), `make`, `open_group` (`ph_composer.context.open`), `reselect`, then assign and clear as before |
| Stub | `tests/support/sketchup/entities.rb`, `model.rb` | A Group `add_group` made empty in an open operation is erased at its commit, as the host does |

## The rule (`Make.refusal`), each refusal writing nothing

| Selection or paths | Code | Piping test | Ducting test |
| --- | --- | --- | --- |
| Nothing (`edge_paths` empty, or nothing selected) | `params.invalid` | `test_make_refuses_lines_it_cannot_wrap_and_writes_nothing`, `test_the_selection_read_says_whether_its_lines_make_a_group` | the same two |
| A path to a Face, or a selected non-Edge | `target.wrong_kind` | both | both |
| An Edge bounding a Face | `target.wrong_kind` | refuse test | |
| A path to nothing | `target.not_found` | refuse test | |
| Lines in two collections | `target.wrong_hierarchy` | refuse test | refuse test |
| Lines outside the open context | `target.edit_path_changed` | refuse test | refuse test |
| Lines in an open Zone, or a Group in a Zone | `piping.group_in_zone`, `ducting.group_in_zone` | refuse test (both) | refuse test (the Zone) |
| Lines in a group of its kind | `piping.group_nested`, `ducting.group_nested` | both | both |
| Lines in another feature's line group | `target.wrong_hierarchy` | refuse test (a Ducting group) | refuse test (a Piping group) |
| A locked Group, shared storage | `target.locked`, `target.shared_definition` | refuse test | |
| More lines than the gesture limit | `gesture.too_large` | refuse test (limit lowered to 1) | |

At apply, `MakeStep` refuses `target.edit_path_changed` when the open context moved and `target.changed` when a line
is gone, no longer an Edge or bounds a Face (`tests/line_groups_test.rb`,
`test_make_refuses_at_apply_when_the_context_or_a_line_changed`). No code is new.

## Tests, written first

Run on the base tree with the new tests (Ruby 3.2.2): `tests/piping_group_test.rb` "11 runs, 62 assertions, 4
failures", each a missing `groups.make` (`request.unknown_operation`) or `make_refusal`. Then, after the change:

- `tests/line_groups_test.rb`: the step wraps loose lines keeping ids and records in one Undo step, the edit path
  unchanged, and Undo restores them; the apply-time refusals.
- `tests/support/sketchup_stub_test.rb`: an empty Group made in an operation is erased at its commit, one made
  outside an operation or filled before the commit stays.
- `tests/piping_group_test.rb`, `tests/ducting_group_test.rb`: a make over three (two) loose lines, the record, the
  lines' ids and a user dictionary kept, one committed operation named "Make Piping Group" ("Make Ducting Group"),
  Undo; the refusal tables above; the selection read's `make_refusal` on the whole and the paged read; a Model
  SketchUp is not showing takes the make (the two `session.inactive` tests re-pointed: the make moves no edit path).
- The walkthrough tests: draw loose, make, open, assign, clear, Undo, Redo (and ducting's reopen).
- `tests/piping_panel_test.js`, `tests/ducting_panel_test.js`: Make disabled with the host's reason for lines in a
  group, enabled for loose lines, a link in flight holding it, the form's count and the `groups.make` params, the
  form held when the selection turns unmakeable, the groups read again after a make.
- `tools/ui-preview/piping_checks.cjs`, `ducting_checks.cjs`: Make disabled with "Why Make ... is unavailable", the
  preview's selection replaced by loose lines, the dialog's count, the sent paths and the selection emptied.

## Inferred beyond the stage documents

- **The name.** `groups.make` replaces `groups.create` rather than keeping the name with new params, as
  `zones.make` is named; there are no users to keep (minor 109).
- **The shape.** `edge_paths`, root-to-Edge paths as the selection read gives them, as `spaces.create` takes
  `faces`, so lines from two collections are a refusal the action can name; the selection read carries only
  `make_refusal`, and the panel sends the rows' paths.
- **A line bounding a Face is refused**: wrapping only an Edge of a Face was not measured.
- **Zones' `outside_envelope` and `cutting_instance` reasons do not refuse**, as `groups.link` and the assign read
  containment today; a cutting component on the path is refused by the write refusal anyway.
- **No shown-Model check**: the make moves no edit path, as Make Zone takes none; `add_group` on a Model in the
  background worked in AW-10 (`context/SKETCHUP_HOST_BEHAVIOR.md`, "Driving the host from a script").
- **The limit**: a make takes at most the feature's Edge gesture limit, 250 lines, like an assign; more lines make
  two groups.
- **The group's tag** is the Model's active tag, as before (Create Space sets Untagged; this does not).
