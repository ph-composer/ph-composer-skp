# P4-15 evidence: acceptance and handoff, the offline part

DATE: 2026-11-25
Issue: part of [#562](https://github.com/ph-composer/ph-composer-skp/issues/562).
Base: built on `fix/phase-07-post-cap-review` at `d433b597` (PR #590), rebased onto `main` at `44ca8237` after #590 merged (its squash). Branch
`feat/phase-07-mechanical-p4-15`, worktree `.claude/worktrees/p4-15`.

Offline evidence only. No SketchUp process was started and no host case ran: Ed is not at the Mac, so step 2 of the
[stage document](../phases/p4-15-acceptance-and-handoff.md), the integrated host run, is owed to the MS3 sitting
(D4-31) as case `M15`, and every other host case to its sitting. No ACCEPTANCE row is Pass. The diff changes no
code: documentation, the ledger and one native case.

## Step 1: offline gates

Run on the tree that became this branch's commit (documentation only on top of `d433b597`, so the code under test is
#590's head, whose tree `main` at `44ca8237` carries). Logs were saved as they ran and the figures below are read from them.

| Check | Result |
| --- | --- |
| `make coverage` (Ruby 3.2.2) | Ruby 97.4% of 38,891 lines in 618 files (minimum 93), its suite 3,618 runs, 51,083 assertions, 0 failures, 2 skips (the private climate corpus and the map data); JavaScript 97.1% of 27,248 lines in 166 files (minimum 94); Python 95.42% (minimum 92) |
| `make ui-checks` | 41 of 41 scripts pass, exit 0 (`header_checks.cjs` among them, no flake this run) |
| `make runtime-browser-check` (Chromium 88) | PASS: `chromium_88`, cross-origin isolation, single-flight boot, translation answers; cold boot 2,333 ms, warm round trip 2 ms |
| `vendor.py --check` | Runtime verified: 238 assets, 8 wheels, 23,229,238 bytes (the runtime payload) |
| `vendor.py --pins-check` | Wheel pins agree: 8 wheels |
| `tools/rbz/build.py --check` (the packaged inventory) | RBZ verified: 877 files, 9,097,026 bytes, 27,943,244 bytes installed |
| PHX round trips | 29 executed, 0 skipped (below) |
| `make ci` on Ruby 3.2.2 and on 2.7.2 | Pass on each, on `e372fa8f` (this commit rebased onto `main`) with the ledger lines recording #590's merge uncommitted: 3,618 runs, 51,083 assertions, 0 failures, 2 skips; JavaScript 1,253 pass; Python 514 passed, 1 skipped; hostkit 48 runs; RBZ 27,943,244 bytes installed. A first attempt on `4d2a6699` was stopped in its syntax step: a SketchUp process the stage had not started was running; the coordinator quit it before these runs |


### The installed size

| Figure | Bytes |
| --- | --- |
| Ceiling (`installed_ceiling_bytes`) | 28,000,000 |
| Baseline Phase 6 reset at its entry (`installed_baseline_bytes`, F37) | 26,093,959 |
| Growth allowance (`installed_growth_bytes`) | 2,500,000, so the growth limit is 28,593,959 |
| Installed at P4-01's entry, on `main` | 26,841,808 |
| Installed on this head | 27,943,244 |
| Growth over the baseline | 1,849,285, inside the 2,500,000 allowance |
| Under the ceiling | 56,756 |

The ceiling is the nearer limit, as the stage document says. **Proposed new baseline: 27,943,244 bytes**, the
installed size at this phase's close. The reset "by a recorded decision" is Ed's and is not made here: the gate
keys in `tools/runtime/vendor.py` are unchanged. With the growth allowance kept at 2,500,000 the ceiling stays the
binding limit, leaving 56,756 bytes for the next phase, so the reset also needs Ed's call on the ceiling or the
allowance.

## Step 3: the register

Each row's offline evidence is its stage's evidence file; nothing is Pass. "Sitting" is the batch D4-31 sets.

| Row | Stage | Offline evidence | Sitting | Host case | Repeated with it |
| --- | --- | --- | --- | --- | --- |
| M01 | P4-01 | [p4-01-contracts](p4-01-contracts.md) | MS1 | `M01` | |
| M02 | P4-02 | [p4-02-ventilator-kind](p4-02-ventilator-kind.md); the delete-in-use clause in [p4-03-serves](p4-03-serves.md) | MS1 | `M02` | |
| M03 | P4-03 | [p4-03-serves](p4-03-serves.md) | MS1 | `M03` | |
| M04 | P4-04 | [p4-04-ventilator-export](p4-04-ventilator-export.md) | MS1 | `M04` | |
| M05 | P4-05, post-cap fixes | [p4-05-systems-tab](p4-05-systems-tab.md), [post-cap-review](post-cap-review.md) | MS2 | `M05` | `ZO-H1`, `ZO-H2`, `ZO-H3`, `ZO-O7`, `PTAB`, `HGUI`, `UXR-SOLVE`, `UXR-FILTER`, `UXR-HATCH`, `UXR-PAINT`, `UXR-COLOUR`, `UXR-FILTER-OCC` (P4-05's evidence, "the Zone views cases") |
| M06 | P4-06 | [p4-06-hot-water-records](p4-06-hot-water-records.md) | MS2 | `M06` | |
| M07 | P4-07 | [p4-07-hot-water-view](p4-07-hot-water-view.md) | MS2 | `M07` | |
| M08 | P4-08 | [p4-08-heat-pumps](p4-08-heat-pumps.md) | MS3 | `M08` | |
| M09 | P4-09 | [p4-09-electric-heaters](p4-09-electric-heaters.md) | MS3 | `M09` | |
| M10 | P4-10 | [p4-10-pumps](p4-10-pumps.md) | MS3 | `M10` | |
| M11 | P4-11 | [p4-11-fans](p4-11-fans.md) | MS3 | `M11` | |
| M12 | P4-12 | Superseded by Phase 6's Equipment Sets (PG07, PG10, PG11b) | none | none | |
| M13a | P4-13a | [p4-13a-pipe-types](p4-13a-pipe-types.md) | MS3 | `M13a` | |
| M13b | P4-13b, P4-14c2 | [p4-13b-piping-groups-and-assignment](p4-13b-piping-groups-and-assignment.md), [p4-14c2-line-group-operations](p4-14c2-line-group-operations.md) | MS3 | `M13b` | |
| M13c | P4-13c | [p4-13c-tree-and-schedule](p4-13c-tree-and-schedule.md) | MS3 | `M13c` | `T04`, `T08`, `T09` (P4-13c's evidence, "The move") |
| M13d | P4-13d | [p4-13d-piping-export](p4-13d-piping-export.md) | MS3 | `M13d` | |
| M13e | P4-13e, post-cap fixes | [p4-13e-piping-view](p4-13e-piping-view.md), [post-cap-review](post-cap-review.md) | MS3 | `M13e` | |
| M14a | P4-14a | [p4-14a-duct-types](p4-14a-duct-types.md) | MS3 | `M14a` | |
| M14b | P4-14b | [p4-14b-line-group-layer](p4-14b-line-group-layer.md) | MS3 | none of its own: `M13b` to `M13e` run on the moved code | |
| M14c | P4-14c, P4-14c2 | [p4-14c-ducting-groups-and-assignment](p4-14c-ducting-groups-and-assignment.md), [p4-14c2-line-group-operations](p4-14c2-line-group-operations.md) | MS3 | `M14c` | |
| M14d | P4-14d | [p4-14d-duct-runs-and-schedule](p4-14d-duct-runs-and-schedule.md) | MS3 | `M14d` | |
| M14e | P4-14e | [p4-14e-ducting-export](p4-14e-ducting-export.md) | MS3 | `M14e` | |
| M14f | P4-14f, post-cap fixes | [p4-14f-ducting-view](p4-14f-ducting-view.md), [post-cap-review](post-cap-review.md) | MS3 | `M14f` | |
| M15 | P4-15 | This file | MS3 | `M15` (added to `cases.json` by this stage) | the integrated run; the stale cases below that Ed assigns to it |
| M16 | P4-08b, post-cap fixes | [p4-08b-segment-mechanical-settings](p4-08b-segment-mechanical-settings.md), [post-cap-review](post-cap-review.md) | MS3 | `M16` | |

One clause needs a word at the sitting. The cases `M04`, `M06`, `M08` to `M11`, `M13d`, `M14e` and `M16` ask that save,
reopen and re-export give the same HBJSON (`M14e` already narrows it to the same ventilation systems). P4-13d's review noted, not reproduced, that two Python processes give canonical HBJSON differing in
`team` identifiers, `bldg_segments` and list order, so a whole-file byte comparison cannot hold; P4-13d compared the
hot water systems and piping, which were identical. The sitting should compare those clauses' sections, not the
file's bytes, unless Ed rules otherwise ("For Ed" below).

## Owed host cases, by sitting

From `acceptance_ledger.py status` on this head, with `--changed` for each of the 449 paths
`git diff --name-only 73936d2a^ 44ca8237` names (every Phase 7 change up to #590): 165 cases with `M15`, of which 113 `needs_recheck`, 36
`not_run`, 10 `historical_affected`, 5 `source_unchanged_environment_unchecked` and 1 `deferred`.

| Sitting | Cases | Count |
| --- | --- | --- |
| MS1 | `M01`, `M02`, `M03`, `M04` | 4 |
| MS2 | `M05`, `M06`, `M07`; with `M05`, the twelve Zone views cases in the register's M05 row | 3 + 12 |
| MS3 | `M08`, `M09`, `M10`, `M11`, `M13a`, `M13b`, `M13c`, `M13d`, `M13e`, `M14a`, `M14c`, `M14d`, `M14e`, `M14f`, `M16` and `M15` last; with `M13c`, `T04`, `T08`, `T09` | 16 + 3 |
| Not assigned: stale, and `--changed` names a Phase 7 path in its dependencies | `A02`, `A04`, `A05`, `A09`, `A11`, `R01` to `R06`, `E14`, `E15`, `E17`, `GH41`, `GH43`, `GH47`, `S02`, `S10`, `SH3-A8P`, `SH3-A8E`, `T03`, `T05`, `LH1`, `AW01`, `AW02`, `AW05`, `AW05R`, `AW10`, `EUD09`, `EUD09X`, `CM01`, `CM02`, `CM05` to `CM12`, `SD06`, `SD07`, `PG01`, `PG03`, `PG05`, `PG06`, `PG12` | 48 |
| Not assigned: stale, and no Phase 7 path is in its dependencies (stale from earlier changes) | `UXK1`, `R11H`, `E18`, `S01`, `S03` to `S09`, `S11`, `PS1` to `PS9`, `DV1` to `DV5`, `T01`, `T02`, `T06`, `T07`, `AW03`, `AW04`, `AW06` to `AW08`, `AW09`, `AW09M`, `AW10G`, `AW10H`, `CM04`, `SD01` to `SD05`, `PG02`, `PG08`, `PG09`, `PG11`, `PG11b` | 50 |
| Outside the sittings | `E01` to `E13` never run in this ledger; `CM03`, `PG04`, `PG07`, `PG07b`, `PG10` source unchanged with the environment unchecked; `A01`, `A03`, `A06` to `A08`, `A10`, `A12` to `A14`, `A16` historical; `A15` deferred to metr-export | 29 |

Most of the 48 are named only because `extension.rb`, `shell/api.rb`, `index.html` or a shared kit file changed with
every stage. Which of them the MS3 sitting repeats is Ed's call ("For Ed"); no stage document names them.

## Steps 4 and 5: context and product documents

| Document | State | Change here |
| --- | --- | --- |
| `context/UBIQUITOUS_LANGUAGE.md` | Mostly current from each stage | The Systems table's heading drops "for planned features"; Equipment names the `ph_composer.mechanical` feature; a Ventilator row, a Piping and a Ducting row added; "Ventilation assignment" corrected: Serves on the Zone, no per-Space assignment (F25) |
| `docs/USER_DATA.md` | A row per new entity since each stage | "Objects without a map of their own" adds the Building Segment's mechanical settings, the blended heat pump and pipe and duct runs |
| `context/CONTRACTS.md` | Current: "Mechanical equipment", "Hot water piping", "ERV ducting" and the piping section that adds to another section's objects | None |
| `context/TECH_STACK.md` | Current: "Edge-owned assignments" covers piping, ducting and `line_groups/`; Mechanical adds no host behaviour beyond Zones' staged extension | None |
| `context/EXTENSIBILITY.md` | "Line groups" covers `line_groups/` and `html/line_groups/` | A paragraph on the three Phase 7 features: Serves as the second feature payload on the Zone record after Programs' assignment, piping and ducting above Mechanical, and their sections adding to a required section's objects before attach |
| `context/AGENT_INTERFACE.md` | Current to API 1.108, one paragraph per stage | None |
| `docs/PRODUCT.md` | Ventilators, hot water, pumps, fans, electric heaters, piping and ducting current | "Add heat pumps" added (it had none); "Export HBJSON" says what the HBJSON carries for equipment |
| `docs/API_REFERENCE.md`, its "API changes" rows, `docs/AGENT_GUIDE.md` | Generated and current: `make fixtures` and `fixtures-check` pass, and the guide has a recipe per family, piping and ducting | None, so the shipped guide and the installed size do not move |

`docs/` has no em or en dash (`grep` for both, 0 hits). `docs-pass` ran before the gate.

## Step 6: handoff

### PHX round trips (D4-25)

`uv run --group phx pytest tests/python` on this head: 514 passed, 1 skipped (`test_map_borders.py`, which needs `PH_COMPOSER_MAP_DATA`). The round trips alone: 29 executed, 0 skipped,
of which these 19 are this phase's:

| File | Tests | Stage |
| --- | --- | --- |
| `test_shared_ventilator_phx_round_trip.py` | 1 | P4-01 |
| `test_ventilation_phx_round_trip.py` | 2 | P4-04 |
| `test_hot_water_phx_round_trip.py` | 2 | P4-06 |
| `test_heat_pumps_phx_round_trip.py` | 1 | P4-08 |
| `test_mechanical_segment_phx_round_trip.py` | 1 | P4-08b |
| `test_electric_heaters_phx_round_trip.py` | 1 | P4-09 |
| `test_pumps_phx_round_trip.py` | 3 | P4-10 |
| `test_fans_phx_round_trip.py` | 3 | P4-11 |
| `test_piping_phx_round_trip.py` | 2 | P4-13d |
| `test_ducting_phx_round_trip.py` | 3 | P4-14e |

The other ten predate the phase (site, shading, Building Segment, certification, airtightness, airflow, Programs).

### METr rows

Every METr file and import row this packet names is in [metr-export's STATUS](../../unscheduled/metr-export/STATUS.md),
"From Phase 7, mechanical", ten rows, owner that packet when Ed schedules it: duct `lassVU`, the pipe diameter enum,
the recirculation heat loss coefficient, distribution pipe temperature and hours, the shared item, the duct quantity
with no carrier, the fan exhaust quantity PHX 1.59.4 drops, the re-export that is not byte-identical, cooling over
200 kW, and the piping calculation method.

### honeybee_ph#135

`gh issue view 135 -R PH-Tools/honeybee_ph` on 2026-11-25: open, no comments, last updated 2026-10-22. The simplified
hot water methods stay out of the export; `mechanical.method_not_exported` still notes a System that sets one.

### Units Q2 and Q3

Closed in the [units packet](../../cross-phase/units/STATUS.md). Q2: a Pipe Type's diameter is one of METr's eight
nominal sizes, stored in mm and shown by its inch size (P4-13a). Q3: `electric_efficiency`, `volume_l`,
`annual_minutes` and `hours_per_day` in both registries, `percent` and `capacity` in the panel's; `capacity` has no
Ruby report row because no report shows one.

## Step 7: tracking

The packet [STATUS](../STATUS.md), its README, the three feature packets' STATUS files, `planning/STATUS.md` and the
roadmap's Phase 7 table and ledger say P4-15 is in review with every host case owed. Phase 7 is not complete, the
packet is not archived, M15 is not Pass and no `Closes #562` PR is opened. The roadmap records that Phase 7 closing is
the MVP boundary D1 set, not yet reached.

## For Ed

One line each, with its source (paths under this packet unless they say otherwise). Decisions first, then follow-ups.
Rows marked "not re-verified" were collected from the evidence files and not checked against the code here.

### Decisions

| # | Item | Source |
| --- | --- | --- |
| 1 | Reset the installed-size baseline to this head's size (proposed above), and say whether the 2,500,000 growth allowance or the 28,000,000 ceiling moves; under the ceiling the next phase has the headroom above | This file, step 1; stage document step 1 |
| 2 | Which of the 48 stale cases Phase 7's changes name the MS3 sitting repeats (no stage document names them) | This file, "Owed host cases" |
| 3 | "Same HBJSON" on re-export (cases `M04`, `M06`, `M08` to `M11`, `M13d`, `M14e`, `M16`): compare the sections, as P4-13d did, or the whole file, which differs across Python processes (noted in review, not reproduced) | p4-13d-piping-export, "Review"; ACCEPTANCE M04, M14e, M16 |
| 4 | A duct run of quantity N exports as N identical elements, so METr lists N rows of quantity 1; built as inferred. The alternative is carrying it in `user_data` | p4-14e-ducting-export, "Recorded at implementation"; phases/p4-14-erv-ducting, "Inferred in planning" |
| 5 | Whether a Ventilator's own Quantity should multiply its ducts (a Ventilator of Quantity 40 exports the ducts drawn for it) | phases/p4-14-erv-ducting, "Inferred in planning" |
| 6 | A large duct quantity multiplies the HBJSON, each element once per served Room; only the 10,000 cap bounds it | p4-14e-ducting-export, "Review" (not re-verified) |
| 7 | `ducting.group_unlinked`'s Locate opens the group and selects that run's ducts, not the Group (a conductor decision; selecting the Group needs a new view command) | p4-14d-duct-runs-and-schedule, "Inferred beyond the stage doc"; p4-14e-ducting-export |
| 8 | P4-13 inference: a pipe tree lives in one Piping group, so a riser group with per-floor branch groups does not export | phases/p4-13-hot-water-piping, "Inferred in planning" |
| 9 | P4-13 inference: recirculation temperature and hours, and a trunk's multiplier and demand recirculation, sit on the pipe assignment, not on the group or System | phases/p4-13-hot-water-piping, "Inferred in planning" |
| 10 | P4-13 inference, built in P4-13e: the Systems table's recirculation field moved from Mechanical to piping, removing a shipped API field | phases/p4-13-hot-water-piping; phases/p4-13e-piping-view, "Inferred in planning" |
| 11 | The Hot Water System delete routes foreign referrers through the generic `request.retarget_references` (a conductor decision at P4-13b, reused by the Ventilator delete) | p4-13b-piping-groups-and-assignment, "Inferred beyond the stage doc" |
| 12 | Three estimator expressions kept faithfully in the heat pump blend: HSPF weighted by cooling share; the HSPF derating's temperature term; v25.1.2's SEER branch picked by the entered SEER | p4-08-heat-pumps, "Departures and choices" |
| 13 | Summer ventilation's omitted values export honeybee-ph's class defaults (extract fan power 0.0 Wh/m³, night minimum 0.0 °C), not the Grasshopper component's (0.65 Wh/m³, 22 °C) | p4-08b-segment-mechanical-settings, "For Ed's judgment" |
| 14 | An Electric Heater on a Zone with no Spaces reaches the HBJSON but not PHX; Pumps and Fans have a finding for this, heaters none | p4-09-electric-heaters, "For Ed's judgment" |
| 15 | A Fan's linked supportive device takes its quantity, but PHX 1.59.4 drops the exhaust ventilator's, so WUFI-Passive and METr see one exhaust device per Fan | p4-11-fans, "Departures and choices"; metr-export STATUS |

### Follow-ups

| # | Item | Source |
| --- | --- | --- |
| 16 | `17b07275`, #590's last commit, merged past its cap. A read-only `codex -m gpt-6.2-sol review --commit` on 2026-11-25 found one live P3: the citation lint flags valid compact SVG path data such as `M12.5.6v16` (no shipped file has it today). P4-01's `dd8a3ad7` and P4-02's `603bf5e5` were among the eighteen #589 read (its table cites both); a second read of each found nothing live beyond row 21 | post-cap-review, "Live findings"; this stage's review |
| 17 | The agent `discover` index is past its 20 KiB budget (`Discovery::INDEX_BYTES`), so it answers counts, not names; raise the budget or trim the index | p4-05-systems-tab, "Departures and choices"; the stage brief |
| 18 | Upstream, PH-Tools/PHX: the exhaust ventilator's quantity is dropped (row 15) | p4-11-fans |
| 19 | Upstream, honeybee-ph: recirculation runs of 3.3 m and 1.7 m at 24 h read 23 h (`int()` truncation); Ruby matches the export on purpose | p4-13c-tree-and-schedule; p4-13d-piping-export |
| 20 | Upstream, honeybee_ph#135 (open): the calculation-method field; `piping_calc_method` is a guessed attribute until it lands | p4-06-hot-water-records; STATUS, "Deferred" |
| 21 | `Records::Names.unique!` compares case in ASCII only (`casecmp`) while `copy_name` uses `downcase`, so with `ÉRV` and `érv (copy)` a Duplicate skips to `ÉRV (copy 2)` though `ÉRV (copy)` is accepted; left to #321, which has since merged without changing it (checked on `main` 2026-11-25) | p4-13a-pipe-types; post-cap-review |
| 22 | Core `Descriptor#patch_schema` admits null for required fields on update, for every kind | p4-13a-pipe-types, Codex cycle 1 (not re-verified) |
| 23 | Share one `zones.all` read across snapshot sections (Mechanical reads Zones four times per `ventilators.all`) | p4-03-serves; p4-05-systems-tab (not re-verified) |
| 24 | `OccurrencePath.resolve` scans each level per row; index it if a large Model is slow on the host | p4-01-contracts; p4-05-systems-tab (not re-verified) |
| 25 | Lift `Mechanical::CatalogOperations` to `core/`: piping and ducting call it across features | p4-13a-pipe-types, "Inferred beyond the stage doc" |
| 26 | The engine has no batch removal check, so a clear of many ids runs one `reference.in_use` check per id | p4-13b; p4-14c (not re-verified) |
| 27 | Metadata reads and a guarded metadata update for Piping and Ducting groups and their Edges (`docs/USER_DATA.md` says "Not yet") | p4-13b, Codex cycle 1 |
| 28 | The shared selection read's single `write_refusal` and its order in `LineGroups::Selection` | p4-14c2-line-group-operations; p4-14c |
| 29 | The piping and thermal-bridge schedule Locate keeps the older carry-forward revision flag | p4-13e-piping-view, Codex cycle 1 (not re-verified) |
| 30 | Ducting's type, group and shared findings are short twins of piping's; a consolidation candidate | p4-14d-duct-runs-and-schedule, "Recorded at implementation" |
| 31 | Line-group layer follow-ups, each changing piping too: id patterns on stored references, compact or capped detail rows, used length measured after the page check, `shared` from real placement counts, `duct_types.list` walking before paging | p4-14d, "Review" (not re-verified) |
| 32 | A Duct or Pipe Type whose only Edges sit outside every group reads as unused, then the host refuses the delete | p4-14f-ducting-view, Codex cycle 2 (not re-verified) |
| 33 | Locate on a run of more than 10,000 lines sends more paths than `runs.locate` takes (both features) | p4-14f, Codex cycle 2 (not re-verified) |
| 34 | The preview host's Assign leaves its synthetic runs unchanged; a Ventilator named "No Ventilator" groups with unlinked runs | p4-14f, Codex cycle 2 (not re-verified) |
| 35 | No duct tool (about 20 KB in the pipe tool's shape); Select then Assign is the route. The edge tool's shared seam stays undecided | phases/p4-14-erv-ducting; p4-13e-piping-view |
| 36 | Focus after a Serves save, shared by every Serves table | p4-09-electric-heaters, Codex cycle 1 |
| 37 | `incomplete` usage in the Ventilator, Pump, Fan and Electric Heater delete dialogs, as the heat pumps have | post-cap-review, "Follow-ups, not in this PR" |
| 38 | Exact clipboard digits for lengths in a dimension format | post-cap-review, "Follow-ups, not in this PR" |
| 39 | A refused duct Assign keeps its quantity draft | post-cap-review, "Follow-ups, not in this PR" |
| 40 | Carry canonical values through the clipboard past the parser's nanounit | post-cap-review, "Declined in cycle 2" |
| 41 | The recirculation heat loss coefficient is not shown, and distribution pipes export at 60 °C and 24 h; what METr does with them is metr-export's | phases/p4-13-hot-water-piping; metr-export STATUS |

## Review

A Sonnet adversarial read of the diff against this stage document and M15, every added claim checked against the
code and the cited evidence: no factual error in the documents or the counts; 8 findings. Fixed before the gate: the
P4-15 ledger row, roadmap rows 4.5 and 4.6 without their owed host cases, the roadmap's PR range and #590, the heat
pump product section not saying a missing record blocks, the stale split's rule unstated, and the gate logs uncited
(this section's table). Left: a pre-existing stale sentence in STATUS "State" (P4-08 to P4-14 as stubs), not this
stage's; and "neither names the other" for piping and ducting, true of `src/` and now stated in EXTENSIBILITY.
Codex gpt-6.2-sol cycle 1 on `54c5544a` (PR #591): 6 P2, 3 P3, all fixed in `aa5e1efa` (M15's climate, expected values and dependency paths; the METr tree, duct list and Spaces rows and the per-Segment shared item; when the heat pump blend is omitted and what blocks; every case asking for the same HBJSON; the pinned path count; `capacity` at P4-08; the past-tense planning lines), each thread answered. The fixes are documentation and ledger only, so no second cycle ran.

## Not run

The integrated host run (step 2) and every host case; the Design System re-sync (not needed: no CSS or kit part
changed); a Windows or SketchUp 2023 check; METr.
