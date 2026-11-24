# P4-13a: the piping feature and Pipe Types

DATE: 2026-11-24
STATUS: Merged to main 2026-11-24 (#576, squash `99a712a8`); offline evidence in [p4-13a-pipe-types](../evidence/p4-13a-pipe-types.md), host case `M13a` owed to MS3. Planned in full 2026-11-24 from [P4-13](p4-13-hot-water-piping.md), D4-36 (Q3, Q4, Q9, Q10), D4-20, D4-31 and the [piping PRD](../hot-water-piping/PRD.md), "Records" and "Pipe Types". Scoped. Authorized with every stage on 2026-11-23 (STATUS, "Entry gates"). Host case `M13a` runs in the MS3 sitting (D4-31).
AUTHOR: Ed May, BLDGTYP, with Claude
ISSUE: #562

## Entry and scope

Requires P4-06 (merged, #569) and D4-36. Stacks on P4-11's branch while #575 is open; the plan's own commit is the
first on `feat/phase-07-mechanical-p4-13a`, and this sub-stage adds its code there and opens the PR.

Owns:

- The `ph_composer.piping` feature: `install.rb`, `codes.rb`, last in `FEATURES` after Mechanical, requiring
  `ph_composer.mechanical` and `ph_composer.zones`.
- One flat catalog kind, the Pipe Type (`ph_composer.piping.pipe_type`, `ppt`), and its operations, panel closed.
- `PLANNING_IDS` catching a lettered register row (`M13a`), so the sub-stages' register ids are linted like `M10`.

Behavior owner: the [piping PRD](../hot-water-piping/PRD.md), "Records" and "Pipe Types", with D4-36. Names: this
document, folded into [CONTRACTS](../CONTRACTS.md) sections 1 to 3 in step 6. Pattern: Thermal Bridge Types
(`features/thermal_bridges/type/`, a Model-owned definition with a colour) and the mechanical flat kinds.

Paths are relative to `src/ph_composer/`.

## What the sources settle

The wheel's `PhHvacPipeSegment` values and defaults, the material enum and the nominal diameter list are in
[P4-13](p4-13-hot-water-piping.md#what-the-sources-settle-for-every-sub-stage). A Pipe Type carries what a segment takes
from its specification: material, diameter and the four insulation values (Q3, Q9). Temperature and period are not on
the type (PRD, "Records").

## Inferred in planning

- **Fields.** `Fields.common` (the name is the Tag), `material` (integer 1 to 8, required, default 2, Copper L, the
  class's), `diameter_mm` (one of 9.525, 12.7, 15.875, 19.05, 25.4, 31.75, 38.1, 50.8, required, default 12.7, the
  class's 1/2 in), `insulation_thickness_mm` (number >= 0, default 12.7, the class's), `insulation_conductivity_w_mk`
  (number > 0 or null, default 0.04, the class's), `insulation_reflective` (boolean, default true), `insulation_quality`
  (1 None, 2 Moderate, 3 Good, default 1, the class's), `color` (stored only once authored, a ramp colour by id until
  then, as Thermal Bridge Types do, D3b-05), the source snapshot and `user_data` (F36). Schema version 1.
- **Labels.** Material words follow honeybee-ph's enum (Copper M, Copper L, Copper K, CPVC CTS SDR, CPVC Sch 40, PEX,
  PE, PEX CTS SDR). Diameters are labelled by their nominal inch size in both unit systems (units Q2): 3/8 in to 2 in.
- **The blocking insulation finding** (PRD: thickness with no conductivity) is a type export blocker,
  `piping.insulation_conductivity_missing`, raised only once an Edge uses the type (P4-13c and P4-13d read it), as
  a Thermal Bridge Type's missing psi-value is. A type with thickness 0 needs no conductivity.
- **Delete.** `pipe_types.delete` follows the Assembly delete contract: refused `reference.in_use` while a pipe names
  it, or rewritten with `replacement_id`, or cleared with null. In this sub-stage nothing references a type yet; the
  in-use paths are tested in P4-13b, which adds the referrer.
- **Not a library kind** (Q10). No import, no provider.
- **Used length** per type is P4-13c's (the schedule read), added to `pipe_types.all` there.
- **The register id gap.** `PLANNING_IDS` matches `M\d\d` and `M\d[a-z]` but not `M13a`, so shipped code citing a
  sub-stage's register row would pass the lint. The pattern becomes `M\d\d[a-z]?`.

## Steps

1. **The feature.** `features/piping/install.rb` with `FEATURE_ID = "ph_composer.piping"`, `codes.rb` (noun `piping`,
   arriving with `piping.insulation_conductivity_missing`), registered last in `extension.rb` `FEATURES`, requiring
   `ph_composer.mechanical` and `ph_composer.zones`. A dependency test in the shape of
   `tests/mechanical_dependency_test.rb`: nothing under `features/mechanical/` or `html/features/mechanical/` names
   the feature (`ph_composer.piping`, `Piping::` or `features/piping`). Mechanical's own words for piping
   (`piping_calc_method`, `from_piping`) are not names of the feature and stay.
2. **The kind.** `features/piping/type/schema.rb`: `PIPE_TYPE_KIND`, the fields above, `DIAMETERS_MM` with their labels,
   `MATERIALS`, `defaults`, `color`, `export_blockers`; `Records::RecordKind` with prefix `ppt`. Persistence through
   `Records::DictionaryStore`; CRUD through mechanical's `CatalogOperations` if its shape fits a kind with no Serves
   slot, otherwise through the Thermal Bridge Type operations' shape (`features/thermal_bridges/type/operations.rb`).
3. **Declarations.** `declarations/pipe_types.rb`: `pipe_types.list`, `.all` and the `pipe_types` snapshot section,
   `.create`, `.update`, `.duplicate`, `.delete` (with `replacement_id`), each with schemas and an example. API minor bump
   with one `API::CHANGES` row; `docs/AGENT_GUIDE.md` and the shipped guide gain a "Hot water piping" recipe that this
   and later sub-stages extend; `context/AGENT_INTERFACE.md`; `make fixtures`.
4. **The register id lint.** `Makefile` `PLANNING_IDS`: `M\d\d` becomes `M\d\d[a-z]?`; `tests/python/test_githooks.py`
   plants `"M" + "13a"` beside its other ids, and its SVG path cases still pass.
5. **Metadata.** `user_data` read and written through the guarded route; a row in `docs/USER_DATA.md`. HBJSON carriage
   is P4-13d's (each segment's `user_data` is the Edge's, not the type's).
6. **Documents.** `context/CONTRACTS.md` (the feature, the kind and its store), the packet CONTRACTS (sections 1 to 3),
   `context/UBIQUITOUS_LANGUAGE.md` (Pipe Type, Pipe, Piping group, Role, Twig and Pipe-Segment from the PRD's
   vocabulary as D4-36 settled it), `docs/PRODUCT.md` (a "Hot water piping" section, filled out by P4-13e).

## Source

| PH-Composer file | Disposition |
| --- | --- |
| `features/thermal_bridges/type/`, `declarations/types.rb` | The Model-owned definition with a colour and delete with replacement |
| `features/mechanical/catalog_operations.rb`, `declarations/*.rb` | The shared CRUD and declaration shape |
| `Makefile` (`PLANNING_IDS`), `tests/python/test_githooks.py` | The citation lint |
| honeybee-ph `honeybee_phhvac/hot_water_piping.py` (pinned 1.33.68) | The field set and defaults |

## Tests (write first)

1. Ruby (`tests/piping_pipe_type_test.rb`): a type created with only a Tag takes Copper L, 1/2 in, 12.7 mm insulation at
   0.04 W/(m K), reflective, quality 1; a material outside 1 to 8, a diameter off the nominal list, a negative thickness,
   a conductivity of 0 and a quality outside 1 to 3 refuse `params.invalid` and write nothing; a taken Tag refuses;
   guarded update with stale `expected_values` refuses; duplicate keeps `user_data`; delete removes it; Undo restores it.
2. The type's export blocker: thickness above 0 with null conductivity gives `piping.insulation_conductivity_missing`,
   thickness 0 with null gives none.
3. The dependency test: nothing under `features/mechanical/` or `html/features/mechanical/` names `ph_composer.piping`,
   `Piping::` or `features/piping`.
4. `tests/python/test_githooks.py`: a planted `M13a` fails the citation lint; the SVG cases pass.
5. The registry's reference test covers the new operations; `tests/agent_guide_test.rb` the recipe.

## Host gate

Batched into the `MS3` sitting (D4-31): case `M13a` in `planning/native-acceptance/cases.json`, panel closed, as `M02`
was: a script creates, edits, duplicates and deletes Pipe Types through registered actions only; native Undo and Redo;
save and a fresh-process reopen read the same types. Offline `make ci` passes on this sub-stage's PR.

## Out of scope

Piping groups and assignment (P4-13b). Used length and the schedule (P4-13c). Export (P4-13d). The Pipe Types pill
(P4-13e). A Pipe Type library kind (Q10).

## Done when

- M13a has offline evidence in `../evidence/p4-13a-pipe-types.md`; host verification lands in `MS3`.
- `make ci` passes on both Rubies; the installed size is recorded against the 30 KB estimate.
