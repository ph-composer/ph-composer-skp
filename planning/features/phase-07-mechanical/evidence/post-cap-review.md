# Post-cap review evidence: the Phase 7 commits merged past their review cap

DATE: 2026-11-25
Issue: [#589](https://github.com/ph-composer/ph-composer-skp/issues/589), part of [#562](https://github.com/ph-composer/ph-composer-skp/issues/562).
Base: `main` at `4a835641` (#588 merged). PR: [#590](https://github.com/ph-composer/ph-composer-skp/pull/590) against `main`.

Offline evidence only. No SketchUp process was started. The fixes touch behaviour the owed host cases already
cover (`M05`, `M13e`, `M14f`, `M16`); they stay owed to the MS3 sitting (D4-31) and no register row is flipped.

## The review

pr-loop caps each stage at two Codex cycles; a fix made after the cap merges unreviewed and is logged for one
review before the archive PR. Eighteen Phase 7 commits merged that way (P4-05 to P4-14f). One gpt-6.2-sol review
read each of them (eighteen runs, no retries). The raw reports are local only (the conductor's scratchpad), not
committed. Each finding was verified against `main` at `0ec589a8` and again at `4a835641`:

| Outcome | Count |
| --- | --- |
| Findings reported | 69 |
| Live on `main` | 26 (one `names.rb` case left to #321) |
| Already fixed by a later stage, or dropped (test-only, wording, contrived, style) | 43 |

## Live findings and their fixes

| Commit | Finding | Fix | Test (red on `main`) |
| --- | --- | --- | --- |
| `07e4a7bf`, `1d47eaa6` (P2) | A copied unit cell rounds to display precision (45.04 W copies `45`, a percentage 0.421234567 copies `42.1`), so pasting it writes the rounded value | `units.formatExact`: the fewest digits that read back as the stored value; `RecordEdits.copyText`, used by the grid's copy | `units_test.js` "the exact text reads back..."; `mechanical_pump_panel_test.js` "a copied power and operation keep every stored digit..." |
| `2b7b1afb` (P2) | A refused optional value (`revision.stale`) is re-guarded by the new Model value, so closing the bubble overwrites a concurrent edit | The draft keeps the guard it was sent with | `mechanical_panel_test.js` "a refused optional value keeps the guard it was sent with..." |
| `2b7b1afb` (P2) | Closing while one value is out commits another draft; the first answer lands on the wrong field | Close commits nothing while a value is out; a value committed while busy stays a draft | "closing while a value is out sends no other draft..." |
| `2b7b1afb` (P3) | A refused optional value comes back display-rounded (4.567 °C as 4.6) | `UnitField` passes its typed draft to `onCommit` and `restore(draft)` gives it back | "a refused value gives back the digits typed, and a retry sends them" |
| `07e4a7bf` (P3) | A unit switch wipes a refusal message | Refusals kept in the bubble's state, painted again after a preference change | "a refusal stays beside its field through a unit switch" |
| `07e4a7bf` (P3) | `1e300` parses to infinity, sent as null | `validate` keeps a value too large to round as it is | `units_test.js` "a value too large to round..." |
| `2b7b1afb` (P3) | A Zone replaced at a checked path shows checked once | The picker drops lapsed changes before drawing | "a Zone replaced at a checked path shows unchecked at once..." |
| `ea5d6306` (P3) | Trunk to Branch to Trunk on a running tool resets Multiplier and Demand recirculation | Armed defaults apply to the armed role's values only | `piping_panel_test.js` "a running tool switched from Trunk to Branch and back..." |
| `ea5d6306` (P3) | A tool armed while Multiplier has focus is marked shown though the field keeps its old value | Shown only once every field shows it; leaving the field re-renders | "a tool armed while Multiplier has focus..." |
| `ea5d6306` (P3) | Escape on an invalid recirculation draft leaves Assign disabled | Both unit fields repaint the bar on cancel | "Escape on an invalid recirculation draft..." |
| `ea5d6306` (P3) | Order by Piping group sorts by stored path, not name | `ViewControls.project` takes an optional `groupKey`; the schedule sorts by name and groups by path | "ordering by Piping group follows the group names..." |
| `ea5d6306` (P3) | Any open component hides every shared pipe from Colour-by | Only a definition placed more than once counts as repeated | `piping_colour_mode_test.rb` (an open single-placement component) |
| `fccb84e4` (P3) | A change to the same ducts, or a Clear, consumes the unsent quantity | `Bar.selectionPaths`; only new lines or an Assign end the draft | `ducting_panel_test.js` "an unsent quantity outlives..." |
| `a683cf91` (P3) | An unreadable outdoor unit makes an in-use model look unused: plain Delete, then `reference.in_use` | Heat-pump usage reports `incomplete`; the Delete dialog treats unknown uses as uses and says why | `mechanical_heat_pump_panel_test.js` "an unreadable outdoor unit leaves a model's uses unknown..." |
| `a683cf91` (P3) | The last required model in use opens a dialog with no choice and no direction | The dialog says to cancel, create one, then delete | "a model in use with nothing to replace it..." |
| `07e4a7bf` (P3) | Spaces zone totals measure a Space beside its Zone that names a Zone in no Building Segment (KeyError on a malformed Floor Segment) | Spaces filtered to exported Zones before measuring | `spaces_export_test.rb` "zone totals leave out a space naming a zone in no building segment..." |
| `dd8a3ad7` (P3, two) | The citation lint skips `d = "M01 2026-11-23"` and flags valid path data (` M12`, `4e0`) | `SVG_PATH_DATA` anchored to a `<path` (or `%3Cpath`) `d` attribute, standard number syntax | `tests/python/test_githooks.py` (one failing and four passing fixtures added) |
| `c0c27741` (P3, two) | The preview host checks only a single slot's own guard, and moves a reassigned list item to the end | One guard check for both branches; an existing item keeps its place | `tools/ui-preview/mechanical_checks.cjs` (two assertions) |
| `dd8a3ad7` (P3) | `context/CONTRACTS.md` and the packet CONTRACTS overstate when a preserved payload refuses a delete | Wording: `copy.rule_missing` for an unreadable envelope or invalid payload; any other scanned through its declarations | Wording only |
| `768eb228`, `3338f0a4`, `9e4e0889` (P3) | `cases.json` `M05`, `M16` and `M14c` miss dependency files | Paths added | Ledger only |
| `603bf5e5` (P3) | `names.rb` compares case in ASCII only | Not fixed: pre-existing, tracked in #321 | |

Red runs on unmodified source were kept with the conductor's local logs.

## Gate

- `make ci` on Ruby 3.2.2 on the code commit `e052f98b`: "Ruby suite, 10 processes: 3618 runs, 51083 assertions, 0
  failures, 0 errors, 2 skips"; JS "tests 1249", "pass 1249", "fail 0"; Python "483 passed, 18 skipped" (the worktree's
  `phx` group unsynced); hostkit "48 runs, 268 assertions, 0 failures"; "Runtime verified: 238 assets, 8 wheels,
  23228616 bytes"; "RBZ verified: 877 files, 9096799 bytes, 27942628 bytes installed", 6,435 over P4-14f's 27,936,193
  and 17,372 under the 27,960,000 that keeps P4-15's reserve.
- PHX round trips: `uv run --group phx pytest tests/python/*phx_round_trip*.py`, "29 passed"; the whole group "512
  passed, 1 skipped" (`test_map_borders.py`, `PH_COMPOSER_MAP_DATA` not set).
- Browser check `make ui-checks UI_CHECKS=tools/ui-preview/mechanical_checks.cjs` passes with the two new host.js
  assertions; the full run on the final head is below.

Final head `17b07275`, after the last review fix:

- `make ci` on Ruby 3.2.2: "Ruby suite, 10 processes: 3618 runs, 51083 assertions, 0 failures, 0 errors, 2 skips";
  JS "tests 1253", "pass 1253", "fail 0"; Python "514 passed, 1 skipped"; hostkit "48 runs, 268 assertions, 0
  failures"; "RBZ verified: 877 files, 9097032 bytes, 27943250 bytes installed".
- `make ci RUBY=$(rbenv prefix 2.7.2)/bin/ruby`: the same Ruby, JS, Python and hostkit counts; "RBZ verified: 877
  files, 9097026 bytes, 27943244 bytes installed". Installed size: 7,057 bytes over P4-14f's 27,936,193 and 16,750
  under 27,960,000, the line that keeps P4-15's reserve. `vendor.py --refresh-manifest`: "Runtime verified: 238
  assets, 8 wheels, 23229238 bytes".
- `make ui-checks`: 40 of 41 scripts pass. `header_checks.cjs` failed "pressed mode does not move label" (x 483.6 vs
  480.6, the known 3 px flake); this diff touches no header code, and the script run alone passes ("Column header
  checks passed").
- PHX round trips: "29 passed"; the whole group "514 passed, 1 skipped" (`PH_COMPOSER_MAP_DATA` not set).
- Design System re-sync from `main` at `4a835641`: version 42 of the artifact. No kit stylesheet or token changed
  since its last sync at `98ba249c`; P4-14f's `line_groups.css` is a feature layer moved out of `piping.css`, and
  `choice_cell.js` draws the existing enum pill. Only the change note was written.

## Review

- Sonnet adversarial read of the diff before the gate: 9 findings. Fixed: a refusal repainted after a retry that
  landed (`apply` now clears it, with the assertion added), an `open` that ignored a refused close and leaked the
  preference subscription, and the contract list missing an unmigratable version. Recorded: `formatExact` keeps a
  dimension format's edit digits for lengths (documented in the code); only the heat-pump usage reports `incomplete`
  (Ventilators, Pumps, Fans and Electric heaters read their Zones from the snapshot, a follow-up); a refused duct
  Assign ends the quantity draft at send (pre-existing, P4-14f's rule). Declined: the empty-choice message reaching
  Assemblies (they always allow Clear, so it never shows), the preview's unmapped slots, and the narrower SVG
  skip (no shipped path splits a `d` across lines).

- Codex gpt-6.2-sol cycle 1 on `5da11cb5`: 2 P1, 1 P2, 3 P3, all fixed in `7fb25aaa`, test-first:
  - a draft that ends without a write now shows the Model's value, so the next guard is what is shown;
  - unknown uses no longer force Replace and delete, which an invalid referrer would also refuse; a guarded plain
    Delete stays and the dialog says the uses are not all known;
  - a cell's own copied text pastes back as itself past the nanounit;
  - leaving a refused field keeps its refusal;
  - M05 gains the edit and unit modules;
  - the citation skip starts at the `d` value, so an attribute before it is linted.
- Cycle 2 on `7fb25aaa`: 2 P2, 3 P3. Fixed in `17b07275`, which merges unreviewed after the cap:
  - a focus-held piping field now leaves the armed state unmarked;
  - the citation skip again needs a move to two coordinates;
  - M05 gains `inventory_grid.js` and `unit_numbers.js`;
  - the Ventilator delete wording defers to the general rule.
- Declined in cycle 2:
  - a value stored past the parser's nanounit pasted into another cell takes the parser's rounding. Every typed value
    does, and carrying canonical values through the clipboard is a follow-up.
  - `d` after another attribute or after two spaces is linted. A skip that starts at `<path` would hide the
    attributes before `d`, and CI's PCRE2 reads no variable-length lookbehind. No shipped SVG writes it so.

Follow-ups, not in this PR:
- `incomplete` usage for the Ventilator, Pump, Fan and Electric heater delete dialogs.
- Exact clipboard digits for lengths in a dimension format.
- A refused duct Assign keeping its quantity draft.
- The `names.rb` Unicode case check (#321).
