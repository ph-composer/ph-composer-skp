# P4-13a evidence: the piping feature and Pipe Types

DATE: 2026-11-24
Register row: [M13a](../ACCEPTANCE.md). Stage: [P4-13a](../phases/p4-13a-pipe-types.md), under the parent index
[P4-13](../phases/p4-13-hot-water-piping.md).
Base: the plan commits on `feat/phase-07-mechanical-p4-13a`, rebased onto `main` at `a963b22e` after #575 merged.
Code commit `17f63e6a`.

Offline evidence only. No SketchUp process was started by this stage (one opened by someone else during the run was
quit before the gate). The host case `M13a` (in `planning/native-acceptance/cases.json`: the Pipe Types walkthrough
with the panel closed, native Undo and Redo of its five steps, save and fresh-process reopen) is owed to the MS3
sitting (D4-31); nothing here is host evidence. M13a stays Open.

## What was built

| Step | Where | Note |
| --- | --- | --- |
| 1. The feature | `features/piping/install.rb`, `codes.rb`, `extension.rb` | `ph_composer.piping`, last in `FEATURES`, requiring `ph_composer.mechanical` and `ph_composer.zones`; noun `piping` with `piping.insulation_conductivity_missing` |
| 2. The kind | `features/piping/type/schema.rb`, `operations.rb`, `reads.rb` | `ph_composer.piping.pipe_type`, `ppt_`, schema 1: Tag, notes, datasheets, source; `material` 1 to 8 (2), `diameter_mm` one of the eight literals 9.525 to 50.8 (12.7), `insulation_thickness_mm` >= 0 (12.7), `insulation_conductivity_w_mk` > 0 or absent (0.04), `insulation_reflective` (true), `insulation_quality` 1 to 3 (1), `color` (ramp by id until stored). A null given on create leaves an optional value absent, as on update. CRUD through Mechanical's `CatalogOperations`; delete checks a `replacement_id` (not itself, existing) and threads `reference_plan` for P4-13b |
| 3. Declarations | `features/piping/declarations/shapes.rb`, `pipe_types.rb`, `shell/api.rb` | `pipe_types.list`, `.all` and its snapshot section, `.create`, `.update`, `.duplicate`, `.delete`; API 1.98 with one `CHANGES` row |
| 4. The citation lint | `Makefile`, `tests/python/test_githooks.py` | `M\d\d` became `M\d\d[a-z]?`; a planted `M13a` fails the lint (and passed it before the change); the SVG path cases still pass; `make lint-citations` on the whole tree: ok |
| 5. Metadata | engine route, `docs/USER_DATA.md` | `user_data` written with `ph_composer.records.update_metadata`, guarded by `expected_metadata`; Duplicate copies it, delete reports it in `removed_user_data`; export leaves it out (P4-13d) |
| 6. Documents | `context/CONTRACTS.md` ("Hot water piping"), `context/AGENT_INTERFACE.md`, `context/UBIQUITOUS_LANGUAGE.md` (Pipe Type, Pipe, Piping group, Role, Twig, Pipe-Segment), `docs/PRODUCT.md` ("Hot water piping"), `docs/AGENT_GUIDE.md` and the shipped guide ("Hot water piping"), `docs/API_REFERENCE.md`, packet CONTRACTS sections 1 to 3 | |
| Host case | `tools/examples/authoring/pipe_types_walkthrough.rb`, its README section, `tests/pipe_types_walkthrough_test.rb`, `cases.json` `M13a` | As P4-02's Ventilators walkthrough |

## Inferred beyond the stage doc

- **Mechanical's dependency test.** `tests/mechanical_dependency_test.rb` refused any other feature naming Mechanical,
  which piping's `requires` and its use of `CatalogOperations` must. It now exempts the features whose registration
  requires `ph_composer.mechanical`, read from the registry; Mechanical's `install.rb` comment and `context/CONTRACTS.md`
  say so. `tests/piping_dependency_test.rb` holds the other direction.
- **Cross-feature reuse.** Pipe Type CRUD calls `Mechanical::CatalogOperations` (the stage doc's first choice); piping
  keeps its own `Shapes` and refusal lists. Lifting `CatalogOperations` to `core/` is a follow-up, not this stage's.
- **A walkthrough script** for the host case, as P4-02 gave M02.
- **Diameters** must equal the eight literals; `0.375 * 25.4` (9.524999999999999) refuses `params.invalid`.

## Tests

`tests/piping_pipe_type_test.rb` (8): defaults on a Tag-only create; each diameter and material stored as given; out of
range material, diameter (22, 12.7001, 0.375 x 25.4), thickness, conductivity (0, negative), quality, reflective and
colour refuse `params.invalid` on create and update and write nothing; a taken Tag on create and on rename refuses;
the export blocker for null conductivity by create and by update, none at thickness 0; guarded update one Undo step,
stale `expected_values` refused, Undo of create; duplicate with `user_data`; `user_data` through the core route with
a stale refusal; delete with `removed_user_data`, Undo, a self or missing replacement refused, an existing one and null
accepted. `tests/piping_dependency_test.rb` (2), `tests/pipe_types_walkthrough_test.rb` (1); the registry reference
test and `tests/agent_guide_test.rb` cover the new operations and the recipe.

## Gate

- `make ci` on Ruby 3.2.2 on the tree of `17f63e6a`: "Ruby suite, 10 processes: 3461 runs, 49038 assertions, 0
  failures, 0 errors, 1 skips"; JS 1214 pass, 0 fail; Python 467 passed, 1 skipped; hostkit 48 runs; "RBZ verified:
  793 files, 8931830 bytes, 27486880 bytes installed".
- `make ci RUBY=$(rbenv prefix 2.7.2)/bin/ruby` on `17f63e6a`: "Ruby suite, 10 processes: 3461 runs, 49038
  assertions, 0 failures, 0 errors, 1 skips"; JS 1214 pass; Python 467 passed, 1 skipped; "RBZ verified: 793 files,
  8931824 bytes, 27486874 bytes installed".
- Installed size: 27,486,880 bytes, 24,679 bytes over P4-11's 27,461,724 against the 30 KB estimate; 513,120 under the
  28,000,000 ceiling. No shipped panel or Python file changed; `vendor.py --check` verified the runtime manifest.
- Browser checks: `make ui-checks` on `17f63e6a`: 39 of 39 scripts pass, exit 0, none skipped (no panel change).
- PHX round trips: `uv run --group phx pytest tests/python -k phx_round_trip`: 24 passed, 0 skipped (no change, this
  stage exports nothing). Whole group: 467 passed, 1 skipped (`test_map_borders.py`, `PH_COMPOSER_MAP_DATA` unset).
- `acceptance_ledger.py status --changed` for `extension.rb`, `mechanical/install.rb` and `shell/api.rb`: 58 cases
  affected, every one already `needs_recheck`, `historical_affected`, `deferred` or `not_run`; `M13a` `not_run`.
- Design System: re-synced from `main@a963b22e` (#575) as artifact version 38: the Table card gains P4-11's
  `annual_minutes` (min/yr) quantity; no stylesheet changed since `main@3a1483bd`; tokens unchanged. This stage adds no
  kit part.

## Review

Sonnet adversarial read before the gate: no blocking finding. Fixed: a null conductivity on create was stored as null
where an update removes it (now absent both ways); the diameter comment and a refusal case for `0.375 * 25.4`; the
delete's `replacement_id` wording in the guide and the param (nothing to move while no pipe uses a type); tests for a
rename onto a taken Tag, Undo of create and an existing replacement. Declined: the refusal lists keep the Thermal
Bridge Types' codes (`reference.in_use` is P4-13b's; the others mirror the engine's paths); `fetch` on a required
field stays; the whole-folder dependency exemption is intended.

Not run: anything in SketchUp.
