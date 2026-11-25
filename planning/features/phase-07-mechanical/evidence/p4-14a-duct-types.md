# P4-14a evidence: the ducting feature and Duct Types

DATE: 2026-11-25
Register row: [M14a](../ACCEPTANCE.md). Stage: [P4-14a](../phases/p4-14a-duct-types.md), under the parent index
[P4-14](../phases/p4-14-erv-ducting.md).
Base: the P4-14 plan commits on `feat/phase-07-mechanical-p4-14`, rebased onto `main` at `98ba249c` after #580 merged.
Code commits `ed5d9b9b`, `43668076` and `aebd301e`; PR [#581](https://github.com/ph-composer/ph-composer-skp/pull/581).

Offline evidence only. No SketchUp process ran during this stage (`pgrep -x SketchUp` empty before each gate). The
host case `M14a` (in `planning/native-acceptance/cases.json`: the Duct Types walkthrough with the panel closed, native
Undo and Redo of its five steps, save and fresh-process reopen) is owed to the MS3 sitting (D4-31); nothing here is
host evidence. M14a stays Open.

## What was built

| Step | Where | Note |
| --- | --- | --- |
| 1. The feature | `features/ducting/install.rb`, `codes.rb`, `extension.rb` | `ph_composer.ducting`, last in `FEATURES` after Piping, requiring `ph_composer.mechanical` and `ph_composer.zones`; noun `ducting` with `ducting.insulation_conductivity_missing` |
| 2. The kind | `features/ducting/type/schema.rb`, `operations.rb`, `reads.rb` | `ph_composer.ducting.duct_type`, `dct_`, schema 1: Tag, notes, datasheets, source; `shape` `round` (default) or `rectangular`; `diameter_mm` > 0 (160 for a round create), `width_mm` and `height_mm` > 0 (no default); `insulation_thickness_mm` >= 0 (25.4), `insulation_conductivity_w_mk` > 0 or absent (0.04), `insulation_reflective` (true), `color` (ramp by id until stored). CRUD through Mechanical's `CatalogOperations`; delete checks `replacement_id` and threads `reference_plan` for P4-14c |
| 3. Declarations | `features/ducting/declarations/duct_types.rb`, `shell/api.rb` | `duct_types.list`, `.all` and its snapshot section, `.create`, `.update`, `.duplicate`, `.delete`, with Mechanical's `Shapes`; API 1.103 with one `CHANGES` row |
| 4. Metadata | engine route, `docs/USER_DATA.md` | `user_data` written with `ph_composer.records.update_metadata`, guarded by `expected_metadata`; Duplicate copies it, delete reports its keys in `removed_user_data`; kept in the Model only |
| 5. Documents | `context/CONTRACTS.md` ("ERV ducting"), `context/AGENT_INTERFACE.md`, `context/UBIQUITOUS_LANGUAGE.md` (Duct Type, Duct, Ducting group, Direction, Outdoor air, Exhaust air, Duct run, Duct-Segment, replacing the "Ducting" row), `docs/PRODUCT.md` ("Draw ERV ducting"), `docs/AGENT_GUIDE.md` and the shipped guide ("ERV ducting"), `docs/API_REFERENCE.md`, packet CONTRACTS sections 1 to 3 | |
| Host case | `tools/examples/authoring/duct_types_walkthrough.rb`, its README section, `tests/duct_types_walkthrough_test.rb`, `cases.json` `M14a` | As P4-13a's Pipe Types walkthrough; its update is the Round to Rectangular change |

## Inferred beyond the stage doc

- **The refusal code's mechanism.** The stage doc asks `params.invalid` for a missing or other-shape dimension "as a
  heater carrying another variant's field does", but the heater's variant rule is its kind's validation and refuses
  `validation.failed` (`tests/mechanical_hot_water_test.rb`). The Duct Type keeps the same rule in its kind's
  validation, so a stored record breaking it reads as unreadable, and `create` and `update` check it first on the
  values they would write and raise `params.invalid`. An update whose `expected_values` are stale skips that check, so
  the engine refuses `target.changed` first, as every guarded edit does.
- **A shape change** removes the old shape's dimensions in the operation (the stage doc's test sends only width and
  height); one the edit gives itself stays and is refused. A change to Round must give its diameter.
- **A null** for the other shape's dimension is absent, on create and on update, as a null removes any optional value
  (`CatalogOperations.update`); a null for the shape's own dimension leaves it missing and refuses. Codex's first
  review asked that a null other-shape dimension refuse; declined (below).
- **Reuse.** Duct Type CRUD is Mechanical's `CatalogOperations`, and its params are Mechanical's `Shapes`, whose create
  text already says a map is left out of the export with a finding (P4-14e). Ducting has no `Shapes` module of its own.
- **Piping's dependency test** asserted Piping installs last; it now asserts Piping installs after Mechanical, and
  `tests/ducting_dependency_test.rb` asserts Ducting is last.
- **The Design System re-sync** owed from P4-13e is done (below).

## Tests

`tests/ducting_duct_type_test.rb` (10): a Tag-only create is Round, 160 mm, 25.4 mm at 0.04, reflective, with the
ramp's colour for its id; a Rectangular create holds width and height and no diameter, a null diameter left absent; 15
create and 9 update refusals (`params.invalid`, no revision, no Undo step, no record): Rectangular missing either
dimension, Round with a width, a change to Rectangular with one dimension or with a diameter, a change to Round with no
diameter, a null for the shape's own dimension, zero and negative dimensions, a negative thickness, a conductivity of 0
or below, an unknown shape, a bad colour or reflective flag; a taken Tag on create and on rename refuses
`validation.failed`; a Round to Rectangular update drops the diameter in one Undo step, Undo restores it and a change
back with a null width is accepted; a stale `expected_values`, even with a short new shape, refuses `target.changed`;
the export blocker by create and by update, none at thickness 0; duplicate with `user_data`; the bounded list and the
snapshot section; `user_data` through the core route with a stale refusal; delete with `removed_user_data`, Undo, a
self or missing replacement refused, an existing one and null accepted.
`tests/ducting_dependency_test.rb` (3), `tests/duct_types_walkthrough_test.rb` (1, including the Undo of the shape
change bringing the diameter back and a stored round type with a width failing the read as unreadable);
`tests/agent_guide_test.rb` asserts the `recipes.erv_ducting` topic; the registry reference test covers the new
operations.

## Gate

- `make ci` on Ruby 3.2.2 on `ed5d9b9b`: "Ruby suite, 10 processes: 3554 runs, 49931 assertions, 0 failures, 0
  errors, 2 skips"; JS "pass 1226", "fail 0"; Python "460 passed, 17 skipped" (the worktree lacks the private
  corpora); hostkit "48 runs, 268 assertions, 0 failures"; "RBZ verified: 835 files, 9033294 bytes, 27778788 bytes
  installed".
- `make ci RUBY=$(rbenv prefix 2.7.2)/bin/ruby` on `ed5d9b9b`: "Ruby suite, 10 processes: 3554 runs, 49931
  assertions, 0 failures, 0 errors, 2 skips"; JS "pass 1226"; Python "460 passed, 17 skipped"; "RBZ verified: 835
  files, 9033288 bytes, 27778782 bytes installed".
- Installed size: 27,778,788 bytes, 24,817 over P4-13e's 27,753,971 against the 25 KB estimate (under the 25 percent
  stop line); 221,212 under the 28,000,000 ceiling. Less the estimates still to run (P4-14b to P4-14f, 163 KB) that
  leaves about 58 KB, above the 40 KB line. `uv run tools/runtime/vendor.py --check`: "Runtime verified: 223 assets,
  8 wheels, 23168678 bytes". No shipped panel or Python file changed, so the runtime manifest needed no refresh.
- Browser checks: `make ui-checks` on `ed5d9b9b`: 40 of 40 scripts (`tools/ui-preview/*.cjs`), exit 0, none skipped
  (no panel change).
- PHX round trips: `uv run --group phx pytest tests/python -k phx_round_trip`: "26 passed, 461 deselected" (this stage
  exports nothing). Whole group: "486 passed, 1 skipped" (`test_map_borders.py`, `PH_COMPOSER_MAP_DATA` unset).
- `acceptance_ledger.py status --changed` for `extension.rb`, `shell/api.rb` and `features/ducting/install.rb`: 53
  cases affected, every one `needs_recheck` (24), `not_run` (18), `historical_affected` (10) or `deferred` (1);
  `M14a` `not_run`.
- Design System: re-synced from `main@98ba249c` (#580) as artifact version 41: the Table card gains P4-13e's
  `hours_per_day` (h/day) quantity; no kit stylesheet changed since `main@a963b22e` (`piping.css` and
  `mechanical.css` are feature screens, outside the bundle); tokens unchanged. This stage adds no kit part.

## Review

Sonnet adversarial read before the gate: no correctness or contract defect. Fixed: the dimension descriptions now say
a round create defaults to 160 and null removes; the dependency regex also catches a feature folder without its slash
and a code under the noun; the refusal loops check the Undo stack and the record count; the colour test names the
ramp itself; the guide test asserts the recipe's topic. Declined: a doubled period in the engine's unreadable message
and the `validation.failed` refusal of a null on a required field (both core, shared with every kind, as P4-13a
declined); a corrupt record cannot be deleted through the API (the engine's).

## Codex review and the final head

- Cycle 1, gpt-6.2-sol on `ed5d9b9b`: 1 P1, 1 P2, 1 P3. Fixed in `43668076`: the dependency regexes match
  `PhComposer::Piping` and `PhComposer::Ducting` as constants, a code under the noun and the folder without its
  slash; the glossary's Duct run leaves the export's element count to P4-14e. Declined: a null for the other shape's
  dimension refusing (it means absent, as a null removes any optional value on this kind; any non-null other-shape
  value refuses); the guide now says so and the shape-change test sends one.
- Cycle 2, gpt-6.2-sol on `43668076`: 1 P2, 1 P3, both fixed in `aebd301e`, which merges unreviewed after the
  two-cycle cap: each dependency test also scans Ruby code outside comment lines for the bare constant (`Ducting`
  under Mechanical and Piping, `Piping` under Ducting); the recipe says a null conductivity blocks only an insulated
  type.
- Final head `aebd301e`: `make ci` on Ruby 3.2.2 and on 2.7.2: "Ruby suite, 10 processes: 3554 runs, 49959
  assertions, 0 failures, 0 errors, 2 skips"; JS "pass 1226"; Python "486 passed, 1 skipped"; hostkit 48 runs;
  "RBZ verified: 835 files, 9033335 bytes, 27778880 bytes installed" on 3.2.2 (+24,909 over P4-13e, estimate 25 KB;
  221,120 under the ceiling). `make ui-checks`: 40 of 40 scripts, exit 0, none skipped. PHX round trips: 26 passed.

Not run: anything in SketchUp.
