# P4-14d: duct runs and the schedule

DATE: 2026-11-24
STATUS: Merged to main 2026-11-25 (#586, squash `1b05db9c`); offline evidence in [p4-14d-duct-runs-and-schedule](../evidence/p4-14d-duct-runs-and-schedule.md), host case `M14d` owed to MS3; corrections recorded under "Recorded at implementation". Planned in full 2026-11-24 from [P4-14](p4-14-erv-ducting.md), D4-37 (Q1, Q4, Q6, Q9) and the [ducting PRD](../erv-ducting/PRD.md), "Behaviors" and "Validation rows". Scoped. Authorized with every stage on 2026-11-23 (STATUS, "Entry gates"). Host case `M14d` runs in the MS3 sitting (D4-31).
AUTHOR: Ed May, BLDGTYP, with Claude
ISSUE: #562

## Entry and scope

Requires P4-14c. Owns, panel closed: the ducting scan, runs, findings, the schedule read and its paged reads,
`runs.locate`, used length per Duct Type, and the per-Ventilator duct lengths the Ventilators table reads (Q9).

Behavior owner: the [ducting PRD](../erv-ducting/PRD.md), "Behaviors" and "Validation rows". Names: this document,
folded into [CONTRACTS](../CONTRACTS.md) in step 6. Pattern: P4-13c (`features/piping/scan/`, `runs/`,
`declarations/schedule.rb`) without the tree, over P4-14b's walk, paging and Locate.

Paths are relative to `src/ph_composer/`.

## What the sources settle

- Runs are derived, never stored; nothing points at a run (`context/TECH_STACK.md`, "Edge-owned assignments").
- Connection does not matter, only the sum (PRD, "Behaviors"), so the chain rule in `core/edge_runs.rb` is not used.
- The schedule of an edge feature is asked for on opening and on Refresh, never on every refresh (D3b-13); a snapshot
  section that walks the Model stays in the snapshot only under the 200 ms repaint target, as piping's
  `piping_systems` does (P4-13c, measured at 55 ms on Ruby 3.2 and 70 ms on 2.7 for 2,000 pipes).
- honeybee-ph's `supply_ducting_total_length` and `exhaust_ducting_total_length` sum every element of the list (P4-14,
  "What the sources settle").

## Inferred in planning

- **A run** is every Duct of one Ducting group occurrence with one direction, one Duct Type and one quantity (P4-14).
  Its length is the sum of its Edges' lengths in metres.
- **Identifiers.** A run's identifier digests the container path, direction, type id, quantity and canonical points
  (`duct_` and 16 hex digits); a segment's digests its Edge path and canonical endpoints. Neither uses the assignment
  id a split shares. Display names are the direction word and a counter per Ventilator, numbered by group path, then
  the run's smallest point ("Outdoor air 1", "Exhaust air 2").
- **Lengths per Ventilator** are what the export carries: each run's drawn length times its quantity, summed over
  every occurrence, so a copied group and a quantity count alike (P4-14, the quantity inference). They equal
  honeybee-ph's two total-length properties after reload (P4-14e). The schedule's run rows show the drawn length and
  the quantity apart; its totals apply the quantity. Piping's totals are drawn length because honeybee-ph's trunk
  multiplier is not in its total; a duct's quantity is in honeybee-ph's total, since it exports as copies.
- **The findings**, each naming its run, Edge or Ventilator with a `locate`:

  | Code | When | Blocks export |
  | --- | --- | --- |
  | `ducting.type_missing` | A duct with no Duct Type, or a deleted one | yes |
  | `ducting.group_unlinked` | A Ducting group with no Ventilator, or a deleted one | yes |
  | `ducting.insulation_conductivity_missing` | A used Duct Type with insulation and no conductivity (P4-14a) | yes |
  | `ducting.group_in_zone` | A Ducting group a Zone now holds (moved there after creation) | yes |
  | `record.unreadable` | A duct or group record that cannot be read, a duct with no direction among them | yes |
  | `ducting.run_missing` | A Ventilator serving a Zone with no Outdoor air run, or no Exhaust air run | no |
  | `ducting.shared_definition` | Ducts reached through two placements of one group definition, both counted | no |

  The PRD's dimension row is a refusal since P4-14a, and its mixed-shape case cannot arise (P4-14).
- **The schedule** is a query, `ph_composer.ducting.schedule`, bounded, with no snapshot section, asked for on
  opening the Ducting pill and on Refresh, with compact paging through P4-14b's `SchedulePages`. Its rows: one per run
  (Ventilator, group, direction, Duct Type, drawn length, quantity, line count, findings); totals by direction and
  Ventilator; one `ventilators` row per Ventilator (`outdoor_air_length_m`, `exhaust_air_length_m`, quantity
  applied); one `types` row per Duct Type with its used length, which `duct_types.all` then reports as
  `used_length_m`.
- **The Ventilators read.** The `ventilators` rows are also a snapshot section, `ducting_ventilators`, which P4-14f's
  columns read, if step 5 measures it under the 200 ms target; otherwise P4-14f fetches them with the schedule. The
  evidence records which. Ducting draws two runs a Ventilator, far fewer lines than piping, so the section is
  expected to stay.

## Steps

1. **Scan.** `features/ducting/scan.rb`: P4-14b's walk with Ducting's spec, detached facts with the group record, the
   assignment, world endpoints in metres and the Edge path; `shared` through shared definitions; unreadable records
   as rows. It opens no operation.
2. **Runs.** `features/ducting/runs.rb`, pure: facts grouped by occurrence and key, lengths, identifiers and names
   as above.
3. **Findings.** `features/ducting/findings.rb`: the table above. `ducting.run_missing` reads the Ventilators' Serves
   through Mechanical's published read, `ph_composer.mechanical.ventilators.all`, which reports the
   Zones each serves (`request.query`), naming no mechanical internals.
4. **Schedule and locate.** `features/ducting/schedule.rb`, `declarations/schedule.rb`: the `schedule` query and its
   paged details, `runs.locate` (`capability: "view"`, over `LineGroups::Locate`), `duct_types.all` rows gaining
   `used_length_m`, and the `ducting_ventilators` section. One `API::CHANGES` row; the recipe gains the schedule
   read.
5. **Measure.** The schedule read and the `ducting_ventilators` section on a synthetic Model of 50,000 Edges with 200
   ducts in forty groups (forty units, two runs each), offline here and on the proving host in MS3; record both.
6. **Documents.** `context/CONTRACTS.md` (the schedule read, `runs.locate`, the section, the codes), the packet
   CONTRACTS (sections 3 and 6).

## Source

| PH-Composer file | Disposition |
| --- | --- |
| `features/piping/scan/`, `runs/schedule.rb`, `runs/findings.rb`, `declarations/schedule.rb` | The shape of the scan, schedule, findings and declarations |
| `line_groups/` (P4-14b) | The walk, paging and Locate |
| `features/mechanical/declarations/ventilators.rb`, `serves.rb` | The published reads the missing-run finding uses |

## Tests (write first)

1. Runs (`tests/ducting_runs_test.rb`) on the [ERV ducting case](../ACCEPTANCE.md#erv-ducting-case-p4-14)'s facts:
   four runs, lengths 2.500, 1.800, 2.500 and 1.500 m to 0.001 m; ERV-1's lengths 2.500 and 1.800 m, ERV-2's 2.500 and
   3.000 m (quantity 2); two lines of one direction and type that do not touch are one run; one line of DG-1's
   Outdoor air run set to DT-2 gives two Outdoor air runs; a pasted DG-1 gives two of each of its runs with distinct
   identifiers, `ducting.shared_definition`, and ERV-1's lengths 5.000 and 3.600 m.
2. Identifiers and names are the same across two scans and after a reassignment that changes no key; a split Edge
   gives two segments with distinct identifiers.
3. Each finding fires on its case in ACCEPTANCE and on no other; `ducting.run_missing` does not fire for an unserved
   Ventilator; the scan writes nothing and opens no operation.
4. The schedule's paged reads page runs and details and refuse a bad cursor before the walk.

## Host gate

Batched into the `MS3` sitting (D4-31): case `M14d`, fresh process on the reference model with the ERV ducting case,
panel closed: read `schedule` and compare with the hand measurement; clear DG-1's exhaust lines and read
`ducting.run_missing`; `runs.locate` into a Ducting group inside a wrapper; save, reopen and read the same
identifiers; the measurement in step 5. Offline `make ci` passes on this sub-stage's PR.

## Out of scope

Export (P4-14e). Screens (P4-14f). Joining runs by connection.

## Recorded at implementation (2026-11-25)

- **The layer gained two pieces, and piping moved onto them.** Piping's scan built each pipe's detached record, group
  hash, world points and unreadable row in code that names no role; ducting needs the same, so it is
  `LineGroups::Scan.edges`, and each feature maps its Edges to its own facts. The schedule's shared schemas (a
  finding, a run row's Edge paths and compact counts, the unreadable row) and the members and `runs.locate`
  registrations are `LineGroups::ScheduleShapes`, worded by the spec's Edge noun. Piping's tests, goldens and
  `docs/API_REFERENCE.md` lines are unchanged. Each feature keeps its findings, rows and the rest of its
  declarations, as `context/EXTENSIBILITY.md` assigns them; ducting's type, group and shared findings are short
  twins of piping's, a consolidation candidate for Ed.
- **`ducting.run_missing` sits on the `ventilators` rows.** It names a Ventilator, not ducts, so it rides on that
  Ventilator's schedule row, its `locate` Mechanical's (`{name: "ph_composer.mechanical.locate", params:
  {ventilator_ids}}`, the `row_locate` P4-13d's export uses for a System finding). Its message names no user text,
  so the details pages stay bounded. The `ducting_ventilators` section and `duct_types.all` never read Mechanical's
  Ventilators, which pulls Serves and Spaces; only the schedule does.
- **Used length applies the quantity**, as every total does, so P4-14f's by-type legend can equal the schedule.
- **A duct's quantity is at most 10,000.** It had no maximum, and a length times a large enough integer is
  Infinity, which no reply carries (P4-13c's `water_temp_c` precedent). A stored record above it reads unreadable;
  `ducts.assign` refuses it `params.invalid`. API 1.106 records it.
- **`ducting.hidden`** is new in `codes.rb` and ducting's spec: `LineGroups::Locate` reads it.
- **Run order and names.** Runs sort by Ventilator id, as piping's sort by Hot Water System id, then group path,
  direction and smallest point; a run's ducts in canonical order (sorted endpoints, then path), which `edge_paths`
  and the segment identifiers follow.
- **No `schedule.all`.** Piping's panel read arrived with its view (P4-13e); ducting's is P4-14f's.

## Done when

- M14d has offline evidence in `../evidence/p4-14d-duct-runs-and-schedule.md`, with the measurement and whether
  `ducting_ventilators` is registered.
- `make ci` passes on both Rubies; the installed size is recorded against the 30 KB estimate and the headroom rule
  in P4-14, "Size".
