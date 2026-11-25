# P4-13e evidence: the Piping pills, Colour-by and the pipe tool

DATE: 2026-11-24
Register row: [M13e](../ACCEPTANCE.md). Stage: [P4-13e](../phases/p4-13e-piping-view.md), under the parent index
[P4-13](../phases/p4-13-hot-water-piping.md).
Base: built on `feat/phase-07-mechanical-p4-13d` at `209457bc`, rebased onto `main` at `da3303f7` after #579 merged
(identical tree).

Offline evidence only. No SketchUp process was started. The host case `M13e` (in `planning/native-acceptance/cases.json`)
is owed to the MS3 sitting (D4-31), with the UI polish review on the host. M13e stays Open.

## What was built

| Step | Where | Note |
| --- | --- | --- |
| 1. Pills and Pipe Types | `html/features/piping/section.js`, `pipe_types.js`, `shared.js` | Pipe Types (order 40) and Piping (order 50) register on the Hot Water subtab after Tanks. Pipe Types is Mechanical's equipment table, which gains an `identity` option so a kind with no manufacturer keeps Notes as its only hideable column |
| 2. The Piping pill | `assign_bar.js`, `pipe_tool.js`, `groups.js`, `schedule.js`, `piping.css` | The assign bar (type, role, only the role's values, Assign, Clear, Assign by clicking, New Piping group), the Piping groups with their System chosen in place (`groups.link`, `groups.unlink`), the schedule with each branch under its trunk, totals by role and by System, findings and Locate |
| 3. The Systems columns | `systems_columns.js`; Mechanical's `hot_water/reads.rb`, `declarations/hot_water.rb`, `hot_water/systems.rb`, `html/features/mechanical/hot_water.js`, `mechanical.css` | Piping contributes `Recirc.` temperature and hours to `ph_composer.mechanical.hot_water_systems` through `table_contributions`, from `piping_systems`; Mechanical's `recirculation` field, its defaults constant and its column are gone |
| 4. Units | `core/units.rb`, `html/unit_tables.js`, `html/fields.js`, `tests/support/units_vectors.json` | `hours_per_day`, h/day in both systems, precision 1 |
| 5. Colour-by | `features/piping/colour_modes.rb` | `ph_composer.piping.by_role` and `ph_composer.piping.by_type`, 5 px stroke, legend `figure` the drawn length |
| 6. The pipe tool | `features/piping/pipe_tool.rb`, `declarations/pipe_tool.rb` | `pipe_tool.choose`, `.stop`, `.state` and its section, two menu items under "Hot water piping" |
| Panel read | `declarations/schedule.rb` | `ph_composer.piping.schedule.all`, the whole schedule for the panel (unbounded, prefers `schedule`) |
| 7. Preview and checks | `tools/ui-preview/host.js`, `fixtures.js`, `piping_checks.cjs`, `mechanical_checks.cjs` | The preview host answers the piping sections, reads and writes; the Mechanical script reads piping's column |
| 8. Documents | `docs/PRODUCT.md` ("Draw hot water piping"), `docs/AGENT_GUIDE.md` and the shipped guide, `context/AGENT_INTERFACE.md`, `context/CONTRACTS.md`, `context/UBIQUITOUS_LANGUAGE.md`, `planning/ui-baseline/README.md`, the packet CONTRACTS section 3 | API 1.102 |
| Host case | `cases.json` `M13e` | Owed to MS3 |

## Recorded at implementation

- **The edge tool stays in `features/thermal_bridges/`.** The architecture review did not agree to the move:
  `core/` names no shell, and the tool's generic part calls `API.invoke`, `ColourBy::Lease`, `ColourBy::Tessellation` and
  `Commands.install_feature_menus` (`context/EXTENSIBILITY.md`, the layer table). An injected seam would be a new
  contract designed for one more user; the pipe tool follows the thermal-bridge tool's shape instead, about 12 KB. No
  thermal-bridge file changed, so no host case went stale and the review lane stays `gpt-6.2-sol`. P4-14's duct tool
  decides whether a third copy earns a shared seam outside `core/`.
- **Used length reads the snapshot.** `pipe_types.all` rows carry `used_length_m` since P4-13c, so the Pipe Types
  column reads it rather than the schedule, and never shows a dash.
- **The Systems columns read the `piping_systems` snapshot section** P4-13c registered; no fetch. `compose` appends a
  contributed column after the owner's last, so `Recirc.` °C and h/day sit after Notes at the table's right. Their
  headers follow the unit preference (a getter on the contribution's `columns`).
- **The Piping groups have no snapshot section.** The pill reads `groups.all` with `schedule.all` when it opens, on
  Refresh and after a link it sent.
- **The pipe tool's pick** reads the Edge by the selection's rule (`Assignment::Selection.row` with no Zone read), so a
  group a Zone holds is refused by `pipes.assign` at release, not at the pointer. It leases Colour by pipe role.
- **Mode names** are `ph_composer.piping.by_role` and `ph_composer.piping.by_type` (the stage doc's `piping_by_role`
  is the short form). The agent guide names them as plain text: its test reads every backticked name as an operation.
- **Hours a day** keeps precision 1; a stored value is sent as stored unless the user edits it.

## Tests

- Ruby `tests/piping_colour_mode_test.rb` (3): one entry per pipe occurrence with its world segment, role colours, the
  legend's lengths equal `schedule.all`'s totals by role, a loose line uncoloured; the type mode in each type's colour
  with a missing type incomplete; nothing written.
- Ruby `tests/piping_pipe_tool_test.rb` (10): values frozen at button-down and one Undo step a gesture; Escape,
  suspension and a lost release write nothing; another cancel, deactivation and an edit-path change take only the
  gesture; one Edge past the limit refuses the whole gesture; an Edge outside a Piping group refuses at the pointer;
  recirculation values written; a deleted type refuses at button-down; the view commands, Colour by pipe role leased and
  given back, another role's values `params.invalid`, a missing type `target.not_found`; stop leaves another tool
  running; the menu items; detach.
- JS `tests/piping_panel_test.js` (6): the pills after Tanks; Pipe Types' nominal diameters, an update with
  `expected_values` and a refused draft kept; the bar's role values, Assign's references and values; schedule read once,
  the tree order, Locate, Refresh; link, unlink and New Piping group; the pipe tool armed and stopped, and a new
  selection leaving a running tool's choice on the bar; the Systems columns in °C and °F, muted at the defaults.
- Updated: `tests/mechanical_hot_water_test.rb` (no `recirculation` on rows), `tests/mechanical_hot_water_panel_test.js`,
  `tests/piping_dependency_test.rb`, `tests/units_test.rb`, `tests/units_test.js`, `tests/api_test.rb`.

## Review

- Sonnet adversarial read before the gate: 7 findings. Fixed: the stale runtime manifest; the preview host's
  `pipe_tool.stop` not giving back the Colour-by mode (now it does, and the check asserts the toggle is off after Stop);
  thinner tool tests (four cases added); a new selection overwriting a running tool's choice on the bar (fixed, test
  added). Recorded, not changed: hours a day at precision 1; a Zone-held group refused at release (deliberate); the
  evidence file (this one).
- Codex gpt-6.2-sol cycle 1 on `f08383c7`: 3 P1, 7 P2, 2 P3, all fixed in `a7e19e79`: Locate adopts only its own
  answer's revision (the thermal-bridge Schedule keeps the older carry-forward flag, a follow-up); a refused or invalid
  change to a running tool puts its armed values back on the bar; an unknown stored role no longer breaks the bar;
  runs sharing an identifier each keep a row; a group's unreadable record offers no Locate; unnamed groups read by
  path; Colour-by withholds shared pipes while a context is open; the tool reads its type without measuring used
  length (`pipe_types.list` measures only when its fields ask); refusals alone become the tool's and the link's
  notices; `schedule.all` describes its full unreadable list; a unit-switch draft test and a findings bubble at every
  panel size.
- Cycle 2 on `a7e19e79` (the cap): 2 P1, 6 P2. Fixed in the final commit, which merges unreviewed after the cap and is
  owed one Codex review before the phase archive: the tool keeps a frozen copy of its armed values and answers a
  copy; a tool armed without a value shows its default on the bar; Colour-by withholds shared pipes only while a
  repeated parent is open; Group by Piping group keys on the occurrence path and labels a shared name with its path;
  New Piping group follows the Systems snapshot; `pipe_tool.stop` says Select takes the viewport; typing in the
  recirculation fields repaints Assign. Declined: Locate after an edit landing between the read and the Locate (the
  read is stale at send in every ordering the panel can see; a narrower race than the snapshot cycle).

## Gate

Final head (the cycle-2 fixes), on `main` after #579:

- `make ci` on Ruby 3.2.2 and on 2.7.2: "Ruby suite, 10 processes: 3540 runs, 49558 assertions, 0 failures, 0 errors,
  2 skips" (the two private corpora absent from a worktree); JS 1226 pass, 0 fail; Python 460 passed, 17 skipped;
  hostkit 48 runs; "RBZ verified: 829 files, 9024533 bytes, 27753971 bytes installed".
- Installed size: 27,753,971 bytes, 91,305 over P4-13d's 27,662,666 against the 85 KB estimate (87,040 bytes; 4.9
  percent over, inside the 25 percent stop line). 246,029 bytes under the 28,000,000 ceiling are left for P4-14 and
  P4-15.
- PHX: `uv run --group phx pytest tests/python`: 486 passed, 1 skipped (`test_map_borders.py`,
  `PH_COMPOSER_MAP_DATA` unset); `-k phx_round_trip`: 26 passed.
- Browser checks: `make ui-checks` on the final head, 40 of 40 scripts pass, exit 0, none skipped
  (`piping_checks.cjs` new).
- Design System: owed. `hours_per_day` joins the unit registries and the equipment table gains `identity`; the re-sync
  from `main` follows this merge.
