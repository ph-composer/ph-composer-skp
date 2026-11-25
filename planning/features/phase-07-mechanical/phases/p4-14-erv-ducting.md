# P4-14: ERV ducting

DATE: 2026-10-21
STATUS: Implemented in full: P4-14a to P4-14e and the consolidation P4-14c2 merged (#581 to #587), P4-14f in review (#PRNUM); the M14a to M14f host cases are owed to the MS3 sitting. Planned in full 2026-11-24 as six sub-stages, P4-14a to P4-14f, each one pull request, from the gate stub, the [ducting PRD](../erv-ducting/PRD.md), D4-09, D4-13, D4-25, D4-30, D4-31 and D4-37 (Q1 to Q9 all as recommended). This file is their parent index: the entry gates, the size budget, what the sub-stages share and the inferences that cross them. Not one pull request: the installed-size headroom and the diff size both refuse it (see "Size"). Two inferences are for Ed before P4-14b and P4-14e ("Inferred in planning"). Authorized with every stage on 2026-11-23 (STATUS, "Entry gates"). Host cases run in the MS3 sitting (D4-31).
AUTHOR: Ed May, BLDGTYP, with Claude
ISSUE: #562

## Entry gates

P4-04 merged (the ventilation section the ducts join, #567); P4-13's draw and assign behavior (P4-13a to P4-13e merged, #576 to #580); Phase 3b's P3b-03, P3b-06, P3b-07 and P3b-08 merged, all met on 2026-10-26 (P3b-04's chain rule is not needed: only the sum of a run's lengths matters); the ERV ducting interview ([its PRD](../erv-ducting/PRD.md), Q1 to Q9), met 2026-11-23 (D4-37); D4-09 answered. P4-14a stacked on P4-13e until #580 merged on 2026-11-25.

## Owns

Roadmap 4.2 as the ducting PRD scopes it: Duct Type records, Ducting groups linked to a Ventilator, direction, type and quantity on edges, the schedule, the Colour-by modes, the section that appends `PhDuctElement`s to the required ventilation objects before attach with lengths in metres (D4-09), the Ducting pills under Ventilation on the Mechanical tab (D4-13), and the two duct-length columns contributed to the Ventilators table through `html/table_contributions.js` (Q9). It also owns the shared line-group layer that piping and ducting both stand on (P4-14b), which P4-13e's evidence left to this stage.

## Sub-stages

Each is one pull request with its own document, written to be handed to a coding agent with this packet's CONTRACTS and the ducting PRD. They run in order: each needs the one before it, except that P4-14a needs nothing of P4-14b. Size is the estimated growth of the installed RBZ, read file by file from piping's measured stages (below).

| Sub-stage | Delivers | Review lane | Host case, owed to MS3 | Size estimate |
| --- | --- | --- | --- | --- |
| [P4-14a](p4-14a-duct-types.md) | The `ph_composer.ducting` feature and the Duct Type kind with its operations, panel closed | ordinary, `gpt-6.2-sol` | `M14a` | 25 KB |
| [P4-14b](p4-14b-line-group-layer.md) | The shared line-group layer, a foundation package naming no feature, extracted from piping; piping moved onto it with no change of behavior | strong, `gpt-6-astra` (a new generic seam) | none of its own; the M13b to M13e cases run on the moved code | 6 KB net |
| [P4-14c](p4-14c-ducting-groups-and-assignment.md) | Ducting groups linked to a Ventilator, the duct assignment on an Edge (Duct Type, direction, quantity), assign, clear, selection, delete in use for Duct Types and Ventilators | ordinary, `gpt-6.2-sol` | `M14c` | 45 KB |
| [P4-14d](p4-14d-duct-runs-and-schedule.md) | Runs, findings, the schedule read, `runs.locate`, used length per Duct Type and the per-Ventilator lengths | ordinary, `gpt-6.2-sol` | `M14d` | 30 KB |
| [P4-14e](p4-14e-ducting-export.md) | The ducting contributor and Python section appending `PhDuctElement`s to every (Ventilator, Zone) system before attach (D4-09), conformance and a PHX round trip (D4-25) | ordinary, `gpt-6.2-sol`; the conductor may take `gpt-6-astra` for the export | `M14e` | 30 KB |
| [P4-14f](p4-14f-ducting-view.md) | The Duct Types and Ducting pills under Ventilation, the assign bar and New Ducting group, the schedule table, the Ventilators table's two duct columns and the two Colour-by modes | ordinary, UI, `gpt-6.2-sol` | `M14f` | 52 KB |

Their register rows are M14a to M14f in [ACCEPTANCE](../ACCEPTANCE.md) (P4-14b's row records that piping is unchanged), and the geometry they test against is its [ERV ducting case](../ACCEPTANCE.md#erv-ducting-case-p4-14); their ledger rows are in [STATUS](../STATUS.md).

## Size

The installed RBZ on P4-13e's head is 27,753,971 bytes, 246,029 under the 28,000,000 byte ceiling, for P4-14 and P4-15. The ceiling is not raised. P4-15 ships little code but is reserved about 40 KB, so P4-14 has about 206 KB.

Piping's five stages grew the installed size by 25,203, 73,552, 58,070, 44,117 and 91,305 bytes (292,247 in all; the stage evidence). Ducting drops the tree, the roles and their values, recirculation, the Systems columns' unit and the edge tool, and keeps everything else: a type kind, a linked Group, an Edge assignment with its target and selection, a scan, a schedule with paged reads, an export section and a view. Read file by file against piping's sources (`features/piping/`, 190 KB of Ruby; `html/features/piping/`, 63 KB; the Python section and records, 22 KB), the estimate is:

| | Copying piping's shape | On the shared layer (P4-14b) |
| --- | --- | --- |
| P4-14a, Duct Types | 25 KB | 25 KB |
| P4-14b, the layer | | 6 KB net (about 35 KB of piping moves; the layer is the same code with its kind made a parameter) |
| P4-14c, groups and assignment | 66 KB | 45 KB |
| P4-14d, runs and schedule | 40 KB | 30 KB |
| P4-14e, export | 30 KB | 30 KB |
| P4-14f, view | 52 KB | 52 KB |
| Total | 213 KB, leaving about 33 KB for P4-15 | 188 KB, leaving about 58 KB for P4-15 |

So P4-14 fits beside P4-15 only on the shared layer, and with little margin: piping's stages ran 5 to 23 percent over their estimates, and a 15 percent overrun leaves about 30 KB. Two stop lines guard it. Each sub-stage reads `uv run tools/runtime/vendor.py --check` and records the installed size in its evidence; one that lands more than 25 percent over its estimate stops and reports before merging, as P4-13's did. And after each sub-stage, if the headroom left less the estimates of the sub-stages still to run is under 40 KB, the next one does not start until Ed has seen the figure. A duct tool (about 20 KB, the pipe tool's shape) does not fit and is out of scope (below).

The diff size refuses one pull request on its own: piping's merged stages added 3,773 to 12,053 lines each (`git show --shortstat` of #576 to #579, fixtures and generated references included), and ducting is five of them.

## What the sources settle, for every sub-stage

Read in the pinned wheel `src/ph_composer/vendor/wheels/honeybee_ph-1.33.68-py3-none-any.whl` on 2026-11-24 (the PRD cites 1.33.65; re-read here at 1.33.68, which differs from the PRD in one point, the `duct_type` check below):

| Source | What it says | Consequence |
| --- | --- | --- |
| `honeybee_phhvac/ducting.py`, `PhDuctSegment` | `geometry` (a `LineSegment3D`, required), `insulation_thickness` (0.0254), `insulation_conductivity` (0.04), `insulation_reflective` (True), `diameter` (0.160), `height` and `width` (None); all lengths in model units, metres, with no suffix; rectangular when both height and width are set, otherwise round; `user_data` from `_PhHVACBase` | A Duct Type carries the specification in millimetres; the translation divides by 1,000 (D4-09, PRD) |
| Same file, `PhDuctElement` | `display_name`, `duct_type` (1 supply, 2 exhaust), segments keyed by identifier; `add_segment` raises "Cannot join round and rectangular duct segments"; `shape_type_description` raises on mixed sizes; no `quantity` field | One run is one element of one Duct Type, so one shape. Segment identifiers are unique within an element and derived from geometry |
| `honeybee_phhvac/ventilation.py`, `PhVentilationSystem` | `supply_ducting` and `exhaust_ducting` lists; `add_supply_duct_element` and `add_exhaust_duct_element` append with no check; only the `balanced_hrv` constructor validates `duct_type` against its list (the PRD says the system validates it); `supply_ducting_total_length` and `exhaust_ducting_total_length` sum the elements | The section appends through the public adders and its `conformance` checks each element's `duct_type` against its list itself. The Ventilators columns equal the two total-length properties after reload |
| `honeybee_phhvac/properties/model.py` | On reload, two Rooms' ventilation systems sharing an identifier must have equal `to_dict()`, or the load raises "Conflicting ventilation systems share identifier" | Every (Ventilator, Zone) object of one Ventilator gets identical ducts with deterministic identifiers (CONTRACTS section 8, question 2) |

Read in PHX 1.59.4 (checkout at tag `v1.59.4`; the `phx` test group, not shipped): `from_HBJSON/create_variant.py` builds one ventilation device per system key and adds every element of `supply_ducting` and `exhaust_ducting` through `create_hvac.build_phx_duct`, which copies each segment's diameter, height, width and insulation values; `model/hvac/collection.py` `add_vent_ducting` keys elements by identifier, so equal identifiers on two Rooms give one duct; `model/hvac/ducting.py` `PhxDuctElement.quantity` is fixed at 1.

The Grasshopper component (`honeybee_grasshopper_ph`, `honeybee_ph_rhino/gh_compo_io/hvac/create_vent_duct.py`, read in the local checkout at `8967c64`; not vendored) builds one `PhDuctElement` per call from one size and insulation specification and a direction, defaulting `duct_type` to 1, which corroborates one element per Duct Type.

## Inferred in planning, across the sub-stages

Each follows the stub, D4-37, the PRD, D4-09, piping's built shape or the sources above. The first two have consequences Ed should see; the rest change no result.

- **The shared line-group layer (for Ed, before P4-14b).** Ducting needs what piping built for Piping groups: a Group outside every Zone linked to one record, created empty and opened for the Line tool, resolved by its root-to-Group path; an Edge assignment directly in it, resolved by its root-to-Edge path; the write steps; the occurrence walk; the native selection as references; the schedule's paging; and Locate. That code names no Hot Water System and no role, but sits in `features/piping/`, which ducting may not name. `context/EXTENSIBILITY.md` keeps domain behavior in its feature "unless several features need it and no feature owns it", and P4-13c moved the chain rule to `core/` on that rule. These parts also call the shell (`Pages`, `EditContext`, `ph_composer.context.open`), and `core/` names no shell (P4-13e's review), so P4-14b moves them to a new foundation package beside `colour_by/` and `export/`, `src/ph_composer/line_groups/`, which names no feature, and moves piping onto it with every piping test and golden unchanged. Without it ducting copies piping's shape and the budget leaves about 33 KB for P4-15. If Ed prefers the copy, P4-14b is dropped, P4-14c and P4-14d follow piping's files directly, and P4-15's reserve is re-planned. If P4-14b's architecture review declines the package, P4-14b stops and reports, as P4-13e's declined core move did.
- **A run's quantity has no carrier (for Ed, before P4-14e).** D4-37 repeats units "by both group copy and run `quantity`", and METr has a quantity field, but honeybee-ph 1.33.68's `PhDuctElement` has no quantity and PHX 1.59.4's `PhxDuctElement.quantity` is always 1. So a run of quantity N exports as N identical elements with distinct deterministic identifiers, exactly what N copies of its Ducting group export, and the Ventilators columns and honeybee-ph's total lengths count it N times. The quantity lives on the duct assignment (integer 1 or more, default 1) and joins the run key, as a thermal bridge's `quantity` and a trunk's `multiplier` do. It is independent of the Ventilator's own Quantity (honeybee-ph's `Ventilator.quantity`, "number of identical units"): PHX writes that to the METr device's `quantV` and never multiplies the ducts by it (`to_METr_JSON/metr_schemas.py`, `_PhxDuctElement` writes each duct's own `quantity`), so the plan leaves the Ventilator's alone and a Ventilator of Quantity 40 exports the ducts drawn for it, no more. *For Ed:* METr then shows N duct rows of quantity 1, not one row of quantity N; carrying it in `user_data` instead would leave the energy model's lengths unchanged; and whether a Ventilator's Quantity should multiply its ducts is a question this plan does not answer. One bullet in P4-14e, one clause of M14e.
- **The feature** is `ph_composer.ducting` (Ruby `Ducting`, `features/ducting/`, `html/features/ducting/`, `python/ph_composer_translation/ducting_sections.py`), last in `FEATURES` after Piping, requiring `ph_composer.mechanical` (the Ventilator kind and the ventilation section, D4-09; PLAN, "Ownership and dependency direction") and `ph_composer.zones` (the containment refusal, Q5). Mechanical never names it, and it never names piping.
- **A run** is the Ducts of one Ducting group occurrence with one direction, one Duct Type and one quantity. Connection does not matter (PRD), so no chain rule: the Ducts of one key in one occurrence are one run whether they touch or not. Two Duct Types in one direction are two runs, so honeybee-ph's mixed-shape refusal cannot fire, and no finding is needed for it.
- **Direction** is stored `outdoor_air` or `exhaust_air` and shown Outdoor air and Exhaust air (Q2), mapped to `duct_type` 1 and `supply_ducting`, and 2 and `exhaust_ducting`. Outdoor air is the cold intake from the outside to the ventilator, which honeybee-ph and WUFI call supply.
- **A Duct Type's shape fields are required for its shape and absent for the other**, as a Hot Water Heater's variant fields are (D4-19): Round holds `diameter_mm` (160 by default, the class's), Rectangular `width_mm` and `height_mm` (no default; a Rectangular type must be given both). So the PRD's blocking "Round type with no diameter, Rectangular type missing width or height" is a refusal, `params.invalid`, and cannot be a finding; it is dropped, as piping dropped its nominal-size warning. Insulation is 25.4 mm at 0.04 W/(m K), reflective, by default (the class's).
- **Every (Ventilator, Zone) object gets the ducts.** A Ducting group's Ventilator may serve several Zones; P4-04 gives each pair its own `PhVentilationSystem` with one identifier, so the section appends identical elements to each, built once per object from the same record, never one shared instance. A Ventilator with ducts and no exported Zone gives the note `ducting.ventilator_unexported`.
- **The missing-run warning** (PRD: "Ventilator with no supply run or no exhaust run") is `ducting.run_missing`, raised for a Ventilator that serves a Zone and has no Outdoor air run or no Exhaust air run. An unserved Ventilator already raises Mechanical's `mechanical.item_unserved` and gets no second finding.
- **A Ducting group copy is shared storage**, as piping's is (P4-13): each occurrence's Ducts count, with distinct run identifiers since they digest the container path, `ducting.shared_definition` notes it, and a write through either refuses until one is made unique. A copy keeps its Ventilator link (PRD, Q4).
- **The Ventilator delete routes foreign referrers.** Mechanical's `ventilators.delete` today rewrites only Serves (`features/mechanical/ventilators/operations.rb`), so a Ducting group naming the Ventilator would refuse the delete with a replacement or null, the stop P4-13b met for Hot Water Systems. P4-14c makes the same generic change up front: the delete calls `request.retarget_references` and joins that plan to Serves', naming no feature; ducting registers its retargeter.
- **Pills, labels and columns.** Two pills after Ventilators under Ventilation, `Duct Types` and `Ducting`, since Duct Types and the schedule are two tables (D4-13 names one Ducting pill; piping took two for the same reason). The Ducting pill opens with one line saying only the two cold runs between each ventilator and the outside are drawn (Q1, "labeled clearly"). The Ventilators table gains `Outdoor air duct` and `Exhaust air duct`, lengths in the length quantity, read from a `ducting_ventilators` snapshot section (Q9).
- **Two Colour-by modes** in one module, as piping's: `ducting_by_direction` (fixed colours for Outdoor air and Exhaust air) and `ducting_by_type` (the Duct Type's `color`, which the PRD's record carries). The stub says "the Colour-by mode"; the second costs about a kilobyte.
- **No duct tool.** Neither the stub's "Owns" nor D4-37 names one; select then Assign is the primary route (PRD), and the tool, about 20 KB in the pipe tool's shape, does not fit the budget. It is a later item if P4-15 closes with room.
- **Lengths and units.** A Duct-Segment's geometry is the Edge's world endpoints in metres from the snapshot; the type's millimetres divide by 1,000. Diameter, width, height and insulation thickness display in the shipped `length_mm` quantity (millimetres, inches under IP), the units packet's ducting row.

## P4-14c2: line-group operations consolidated

Not a planned sub-stage: a consolidation pull request between P4-14c and P4-14d (issue #584), under Ed's standing
approval to consolidate duplicate code (2026-11-25), numbered so that nothing above moves. P4-14c built ducting's
group and assignment operations as near-copies of piping's. P4-14c2 moves the parts that name no feature into
`line_groups/`: `GroupOperations` (create, link and unlink, the retarget a linked record's delete runs, the Zone
containment read, the occurrence rows) and `EdgeOperations` (clear, the type delete and its rewrite, and the resolve,
update and step an assign builds on), each taking the feature's `LineGroups::Spec`, which gains the linked record's
kind and label, the type's kind, field and label, and the containment query. Each feature keeps its own assign and
its declarations. The move closes four piping gaps P4-14c's review fixed only in ducting, each first reproduced by a
failing piping test: the clear's reference check, a stale Pipe Type delete reporting `reference.in_use` before
`target.changed`, group rows not showing the placement refusal, and `groups.create` lacking `session.inactive`. API
1.105 records them. Every other piping and ducting test, golden and `docs/API_REFERENCE.md` line is unchanged. P4-14d
reads Zone containment through `LineGroups::GroupOperations.contained` with ducting's spec, as piping's scan now does.
Its row is in [STATUS](../STATUS.md) and its evidence in
[p4-14c2-line-group-operations](../evidence/p4-14c2-line-group-operations.md); host verification rides on M13b and
M14c in the MS3 sitting.

## Host cases owed to MS3

Measured and cited, not owed: an Edge's dictionary survives split, copy and paste, weld, Undo, Redo and reopen ([B4, T01](../../../../context/SKETCHUP_HOST_BEHAVIOR.md#components-glue-and-edge-attributes)); a pasted Group carries its dictionary and shares storage (SD01).

Owed by piping and relied on here, not repeated: an empty Group created by an operation survives the commit and opens for editing, and the native Line tool drawing in it puts its Edges there (P4-13b's H1 and H2, case `M13b`). If those fail in the MS3 sitting, P4-14c's `groups.create` fails with them and both features take the "Make group over selected lines" route P4-13b names.

## Out of scope

Duct sizing, pressure drop, fittings, routing and room-side distribution ducts (PRD, Q1). A duct tool (above). A Duct Type library kind (Q7). METr's duct list and `lassVU` (metr-export).

## Planned in full when

Done 2026-11-24. The interview is recorded in the [ducting PRD](../erv-ducting/PRD.md) and [DECISIONS, Part 5](../DECISIONS.md#part-5-kickoff-review-and-remaining-interviews-2026-11-23) (D4-37).
