# P4-14a: the ducting feature and Duct Types

DATE: 2026-11-24
STATUS: Planned in full 2026-11-24 from [P4-14](p4-14-erv-ducting.md), D4-37 (Q5, Q7), D4-19, D4-20, D4-31 and the [ducting PRD](../erv-ducting/PRD.md), "Records". Scoped. Authorized with every stage on 2026-11-23 (STATUS, "Entry gates"). Host case `M14a` runs in the MS3 sitting (D4-31).
AUTHOR: Ed May, BLDGTYP, with Claude
ISSUE: #562

## Entry and scope

Requires P4-13e's head (the last feature registered before this one). Stacks on P4-13e's branch while #580 is open.
Needs nothing of P4-14b, and does not wait on Ed's answer about the shared layer.

Owns:

- The `ph_composer.ducting` feature: `install.rb`, `codes.rb`, last in `FEATURES` after Piping, requiring
  `ph_composer.mechanical` and `ph_composer.zones`.
- One flat catalog kind, the Duct Type (`ph_composer.ducting.duct_type`, `dct`), and its operations, panel closed.

Behavior owner: the [ducting PRD](../erv-ducting/PRD.md), "Records", with D4-37. Names: this document, folded into
[CONTRACTS](../CONTRACTS.md) sections 1 to 3 in step 5. Pattern: the Pipe Type (`features/piping/type/`,
`declarations/pipe_types.rb`, P4-13a), which follows the Thermal Bridge Type.

Paths are relative to `src/ph_composer/`.

## What the sources settle

The wheel's `PhDuctSegment` values and defaults are in [P4-14](p4-14-erv-ducting.md#what-the-sources-settle-for-every-sub-stage).
A Duct Type carries what a segment takes from its specification: the shape and its dimensions and the three insulation
values. The geometry is the Duct's (PRD, "Records").

## Inferred in planning

- **Fields.** `Fields.common` (the name is the Tag), `shape` (`round` or `rectangular`, required, default `round`),
  `diameter_mm` (number > 0, required for `round` and absent for `rectangular`, default 160, the class's 0.160 m),
  `width_mm` and `height_mm` (numbers > 0, required for `rectangular` and absent for `round`, no default),
  `insulation_thickness_mm` (number >= 0, default 25.4, the class's), `insulation_conductivity_w_mk` (number > 0 or
  null, default 0.04, the class's), `insulation_reflective` (boolean, default true), `color` (stored only once
  authored, a ramp colour by id until then, as Pipe Types do), the source snapshot and `user_data` (F36). Schema
  version 1. The stored shape words are lower case; the screen shows Round and Rectangular.
- **Shape fields per shape** (the cross-stage inference in P4-14): a create or update carrying the other shape's
  field refuses `params.invalid` and writes nothing, as a heater carrying another variant's field does (D4-19). An
  update changing the shape must carry the new shape's fields, and the old shape's are removed in the same write.
  So no stored type lacks its dimensions, and the PRD's dimension finding is dropped.
- **The blocking insulation finding** (PRD: thickness with no conductivity) is a type export blocker,
  `ducting.insulation_conductivity_missing`, raised only once an Edge uses the type (P4-14d and P4-14e read it), as
  the Pipe Type's is. A type with thickness 0 needs no conductivity.
- **Delete.** `duct_types.delete` follows the Pipe Type's contract: refused `reference.in_use` while a duct names it,
  rewritten with `replacement_id`, cleared with null. Nothing references a type in this sub-stage; the in-use paths
  are tested in P4-14c, which adds the referrer.
- **Not a library kind** (Q7). No import, no provider.
- **Used length** per type is P4-14d's.

## Steps

1. **The feature.** `features/ducting/install.rb` with `FEATURE_ID = "ph_composer.ducting"`, `codes.rb` (noun
   `ducting`, arriving with `ducting.insulation_conductivity_missing`), registered last in `extension.rb` `FEATURES`,
   requiring `ph_composer.mechanical` and `ph_composer.zones`. A dependency test in the shape of
   `tests/piping_dependency_test.rb`: nothing under `features/mechanical/`,
   `html/features/mechanical/`, `features/piping/` or `html/features/piping/` names `ph_composer.ducting`,
   `Ducting::` or `features/ducting`, and nothing under the ducting folders names piping. Mechanical's own words
   for ducts, if any, are not names of the feature.
2. **The kind.** `features/ducting/type/schema.rb`: `DUCT_TYPE_KIND`, `SHAPES`, the fields above, `defaults`,
   `color`, `export_blockers`; `Records::RecordKind` with prefix `dct`; persistence through
   `Records::DictionaryStore`; operations in the Pipe Type's shape (`type/operations.rb`, `type/reads.rb`).
3. **Declarations.** `declarations/duct_types.rb`: `duct_types.list`, `.all` and the `duct_types` snapshot section,
   `.create`, `.update`, `.duplicate`, `.delete` (with `replacement_id`), each with schemas and an example. API minor
   bump with one `API::CHANGES` row; `docs/AGENT_GUIDE.md` and the shipped guide gain an "ERV ducting" recipe that
   later sub-stages extend; `context/AGENT_INTERFACE.md`; `make fixtures`.
4. **Metadata.** `user_data` read and written through the guarded route; a row in `docs/USER_DATA.md`. HBJSON
   carriage is P4-14e's.
5. **Documents.** `context/CONTRACTS.md` (the feature, the kind and its store), the packet CONTRACTS (sections 1 to
   3), `context/UBIQUITOUS_LANGUAGE.md` (Duct Type, Duct, Duct-Segment, Duct run, Direction, Outdoor air, Exhaust
   air, Ducting group, from the PRD's vocabulary as D4-37 settled it), `docs/PRODUCT.md` (an "ERV ducting" section,
   filled out by P4-14f).

## Source

| PH-Composer file | Disposition |
| --- | --- |
| `features/piping/type/`, `declarations/pipe_types.rb`, `install.rb`, `codes.rb` | The kind's shape, its declarations and the feature's registration |
| `features/mechanical/hot_water/heaters.rb` | Fields required for one variant and absent for the other |
| honeybee-ph `honeybee_phhvac/ducting.py` (pinned 1.33.68) | The field set and defaults |

## Tests (write first)

1. Ruby (`tests/ducting_duct_type_test.rb`): a type created with only a Tag is Round, 160 mm, 25.4 mm insulation at
   0.04 W/(m K), reflective; a Rectangular type with width and height reads back with no diameter; a Rectangular
   type missing either, a Round type with a width, a zero or negative dimension, a negative thickness and a
   conductivity of 0 refuse `params.invalid` and write nothing; an update to Rectangular with both dimensions drops
   the diameter in one Undo step; a taken Tag refuses; a stale `expected_values` refuses; duplicate keeps
   `user_data`; delete removes it; Undo restores it.
2. The type's export blocker: thickness above 0 with null conductivity gives `ducting.insulation_conductivity_missing`;
   thickness 0 with null gives none.
3. The dependency test above.
4. The registry's reference test covers the new operations; `tests/agent_guide_test.rb` the recipe.

## Host gate

Batched into the `MS3` sitting (D4-31): case `M14a` in `planning/native-acceptance/cases.json`, panel closed, as
`M13a` is: a script creates, edits (Round to Rectangular), duplicates and deletes Duct Types through registered
actions only; native Undo and Redo; save and a fresh-process reopen read the same types. Offline `make ci` passes on
this sub-stage's PR.

## Out of scope

The shared layer (P4-14b). Ducting groups and assignment (P4-14c). Used length and the schedule (P4-14d). Export
(P4-14e). The Duct Types pill (P4-14f). A library kind (Q7).

## Done when

- M14a has offline evidence in `../evidence/p4-14a-duct-types.md`; host verification lands in `MS3`.
- `make ci` passes on both Rubies; the installed size is recorded against the 25 KB estimate and the headroom rule
  in P4-14, "Size".
