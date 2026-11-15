# Phase 4a contracts: records, ownership and seams

DATE: 2026-11-15
STATUS: Scoped for P4a-01 to P4a-06; revised the same day after an independent review against the code (14 findings folded in). Sections 5 to 7 are provisional until the Programs tab review. Open contract questions C4a-2 to C4a-8 at the end.
AUTHOR: Ed May, BLDGTYP, with Claude
ISSUE: none (local planning draft)

The data structures the [Phase 4a PRD](PRD.md) and the [Building Segments PRD](building-segments/PRD.md)
need, who owns each, and the seams between features. Names here bind the stages in [PLAN](PLAN.md).
`context/CONTRACTS.md` and `context/EXTENSIBILITY.md` are canonical for the engine rules cited; this
file says how Phase 4a uses them, and each stage folds what it lands back into `context/`.

There are no users yet, so no migration: a schema that changes moves its version and the test
fixtures are rewritten (Ed, standing guidance).

## 1. Building Segment membership (Zones; P4a-01)

| Record | Change |
| --- | --- |
| Zone (entity record on the Zone Group) | **Schema 3**: `building_segment_id` nullable; null is No Building Segment. Schema 2 stays readable |
| `ph_composer.zones.building_segment` (`bsg_`) | Fields unchanged: `name`, `colour`, immutable `export_identifier`. Carries other features' settings as structured extensions (section 2) |
| `ph_composer.zones.option_settings` (`zop_`) | `default_segment_id` stays required, never null |

Rules, enforced by Zones' operations and the management validator in `features/zones/options/`:

- At least one Segment. A management draft or delete that would leave none refuses
  `zone.option_last_segment` (new code).
- Deleting a used Segment names a destination: a surviving Segment or null.
- Deleting the default moves `default_segment_id` to the destination, or to the first remaining
  Segment when the destination is null.
- Make Zone writes the default; Restore Zone recovers null as null; the membership stamp and
  `choice_evidence` carry null.
- **Assigning**: the existing `ph_composer.zones.update_field` with `field: building_segment`
  (`declarations/selection.rb`) accepts null. No new action.
- `ph_composer.zones.options.*` keep their names; `manage` and `remove` accept a null Segment
  destination, and their result adds `removed_extensions` (each removed Segment's extension
  namespaces), because `removed_user_data` lists `user_data` keys only. One API minor bump.

## 2. Building Segment settings (P4a-02 frame; sections later)

**Storage: each section is a structured extension on the Segment record**, under a namespace its
feature registers on `ph_composer.zones.building_segment` (`context/CONTRACTS.md`, "Records and
extension data"). Namespaces start with the owner's id (`shell/registry_validation.rb`) and are
global (`core/records/catalog.rb`), so each payload gets its own:

| Section | Namespace | Payload |
| --- | --- | --- |
| Occupancy | `ph_composer.programs.segment` | `single_dwelling` (bool, default true when the extension is absent), `dwelling_id` (reference to `programs.dwelling`, set while single), `default_program_id` (reference to `programs.program`; null is the built-in default) |
| Phius certification | `ph_composer.certification.segment` | `category` (`residential`, `non_residential`), `program`, `use`, `status`, `type`, each an enum mapped to honeybee-ph `PhiusCertification` |
| Airtightness | `ph_composer.programs.airtightness` | `basis` (`n50`, `q50`), `value` (number or null), `wind_exposure` (the seven `PhWindExposureType` values) |
| Comfort | none, read only | Set points derived from the Zones' Programs |

**Save: Zones stages every namespace itself.** `ph_composer.zones.save_segment_settings` carries
the General values (name, colour, default) and a payload per namespace. Zones checks each payload
with that namespace's installed validator (`Extension#problems`) and writes it with
`engine.propose_metadata_update`, all in one proposal and one Undo step. No section owner writes
the Segment record, so there is no `proposal.foreign_write` and no dependency cycle (a section
owner requires Zones, so Zones cannot call its participants). This answers the earlier C4a-1.

**Rules that span namespaces are findings, not refusals, on generic routes.** A namespace
validator sees only its own payload, and `ph_composer.records.update_metadata` writes any installed
payload. So "Single dwelling needs a residential Segment" and "a Dwelling lies in one Segment" are
read findings and export preflight rows, enforced as refusals only in Programs' own actions. The
dialog keeps them consistent in the draft: checking Single dwelling sets the certification draft's
category to residential. **Effective Single dwelling** is `single_dwelling` and a residential
category; a non-residential Segment is never a single dwelling, whatever its payload says.

**Zone evidence carries Segment values, not extensions.** Today `Options.evidence` copies the whole
Segment record into each Zone's `choice_evidence` and stamp, and every Segment write rewrites every
member Zone (`options/operations.rb` `rewrite_evidence`), refusing on a locked Zone. P4a-02 limits
evidence to `name`, `colour` and `export_identifier`, so a settings save touches only the Segment.
Adoption from another Model therefore brings no settings: the adopted Segment reads defaults.

**Panel seam: a settings section**, keyed by namespace:

```
panel.segmentSettingsSection(namespace, {
  title, order,                         // "Occupancy", 20
  readOnly,                             // true for Comfort: renders, collects nothing
  render(segment, draft, context),      // reads its namespace from the Segment read
  validate(draft) -> problems[],        // shown in the dialog; Save stays disabled while any remain
  collect(draft) -> payload             // what Save sends for this namespace
})
```

Zones owns the dialog frame, the General section and Save. P4a-02 adds the seam to
`context/EXTENSIBILITY.md` with a working development example.

**Export: Segment extensions need a projection.** Today Zones' `exported_choices`
(`features/zones/export.rb`) reads Segments without their extensions, an `entity_projections` claim
accepts only reference targets (`shell/registry_validation.rb` `check_claim`), and the Python
sections attach only to `model`, `room` and `face` (`sections.py`). A Segment extension with
`export_relevance: required` would therefore block every export. P4a-04 first adds (a) a projection
for extensions on catalog records, claimed by the namespace owner's export contributor, and (b) a
`segment` attachment host in the Python sections, one per exported `BldgSegment`.

## 3. Feature ownership

| Feature | Requires | Owns |
| --- | --- | --- |
| `ph_composer.zones` (exists) | | Zones, Faces, Segments, Levels, Attached zones; Segment membership; the Zone views host (`html/features/zones/overview.js`), which gains Segment heading rows; the settings dialog, its seam and Save; Geometry (`faces_view.js`) |
| `ph_composer.spaces` (exists) | zones | Spaces, Volumes, Floor Segments; Space airflows and the per-Zone airflow mode; the Spaces view |
| `ph_composer.certification` (new, P4a-04) | zones | `certification.segment` and its export to `BldgSegment.phius_certification` |
| `ph_composer.programs` (new, P4a-06) | zones, spaces, certification | `programs.airtightness`, `programs.segment`, `programs.zone_assignment`; Programs, Schedules, Equipment Sets, Dwellings; occupancy and ventilation derivations; the Programs view; the Programs tab |

## 4. Space airflows: the mode is per Zone (Spaces; P4a-05)

No record change: Space records keep `v_sup_m3h`, `v_eta_m3h`, `v_tran_m3h`, each optional.

- **A Zone is detailed when any of its Spaces has any rate**, else By Program (Q4a-29, Q4a-30).
- Export: the contract record carries the Zone's mode and the Python Space section moves to
  version 2 (`space_sections.py`, now `versions = frozenset({1})`). In a detailed Zone every Space
  writes `_v_sup`, `_v_eta`, `_v_tran` in m³/s, 0 for a blank; in a By Program Zone every Space
  writes `None`. PHX never mixes the two (F4a-24, F4a-25).
- Reads (`features/spaces/scan/metrics.rb`): `airflow_mode` values become `by_program` and
  `detailed` (today `inheriting`, `user_specified`), read per Zone; Space rows keep a copy derived
  from their Zone (C4a-6). A Space row's `airflows` are 0 for blanks in a detailed Zone and null in a
  By Program Zone; Zone sums are null while By Program. The values also change in
  `colour_modes.rb` and the table export (`features/spaces/export.rb`, where "Zone" becomes
  "By Program"). API minor bump.
- New: `ph_composer.spaces.clear_zone_airflows`, every Space's rates in the given Zones, one Undo
  step (the Zone row's From Program).
- Room ventilation is never written from Space rates (F4a-29, Q4a-31).

## 5. Programs records (Programs; P4a-07 and P4a-08; provisional)

Field lists follow [loads and schedules](research/loads-and-schedules.md) and the answered
interview; the Programs tab review may change them.

| Kind | Prefix | Holds |
| --- | --- | --- |
| `ph_composer.programs.program` | `pgm_` | Name, notes, source; eight load sections (People, Lighting, Electric equipment, Gas equipment, Service hot water, Infiltration, Ventilation with four terms and method fixed to Sum, Setpoint), each with its values and Schedule references (Q4a-02, Q4a-15) |
| `ph_composer.programs.schedule` | `sch_` | Name, type (fractional, activity level, temperature), the PH form (start, end, fraction while operating and otherwise, days per week, weeks per year) and its honeybee ruleset (Q4a-07, Q4a-09) |
| `ph_composer.programs.equipment_set` | `eqs_` | Name; devices as `Records::Part`s, each a honeybee-ph `PhEquipment` type with its values (Q4a-03) |
| `ph_composer.programs.dwelling` | `dwl_` | Name, `units` (integer ≥ 1), `bedrooms` (number or null), `occupants` (number or null), `equipment_set_id` (reference or null) |

**The residential default Program is built in, not a record** (Q4a-13): a frozen definition in
code, seeded from the pinned honeybee-ph rules and schedules, addressed as program id null.
Whether it can be edited in place is Q4a-23.

**Per-Zone assignment: a structured extension on the Zone record**, namespace
`ph_composer.programs.zone_assignment`: `program_id`, `dwelling_id`, `equipment_set_id` (references
or null), `bedrooms` and `occupants` (number or null). It travels with a copied Zone; absent reads as
unassigned. Zones never reads it. Programs' own actions write it through Zones' staging route (the
same rule as section 2) and refuse cross-record violations; the generic metadata routes can write
it too, so the same rules are also findings.

**Library kinds.** Program, Schedule and Equipment Set register library kinds; choosing a library
Program copies it and the Schedules it references into the Model (Q4a-19, Q4a-22). The file layout
is the [ph-composer-standards PRD](../unscheduled/ph-composer-standards/PRD.md).

## 6. Derived values (Programs, Ruby; P4a-08 and P4a-09)

Domain calculations live in Ruby (AGENTS.md); the panel formats them and the Python translation
reproduces the same rules for HBJSON.

| Value | Rule |
| --- | --- |
| Effective Program of a Zone | Under effective Single dwelling, the built-in default; else the Zone's `program_id`; else its Segment's `default_program_id`; else the built-in default |
| Dwelling of a Zone | Under effective Single dwelling, the Segment's `dwelling_id` (created when first needed); else the Zone's `dwelling_id` |
| Dwelling bedrooms and occupants | The Dwelling's own value when set; else the sum over its Zones; occupants with neither use the Phius rule, bedrooms + units (F4a-20) |
| Zone people | Residential default: the Dwelling's occupants over its presence schedule mean, shared by gross floor area. Other Programs: people per area × floor area |
| Zone ventilation (Programs view) | By Program: the Program's four terms summed, PHX's split (F4a-10). Detailed: the larger of the Zone's Spaces' supply and extract sums |
| Segment set points | From its Zones' effective Programs; a finding when they disagree or a set point schedule is not constant (Q4a-04) |

## 7. Export mapping (P4a-03, P4a-04, P4a-06, P4a-10)

| Source | HBJSON | Section owner |
| --- | --- | --- |
| Zone in no Segment | Left out, with its Faces, Spaces and Edges; info finding | Zones |
| Surface Face whose partner Zone is left out | Refused, naming the Face; the move-out offer reclassifies such Faces to an Attached zone first (BS-6; the Face schema allows `attached_zone_id` only on the AttachedZone boundary, `features/zones/faces/schema.rb`) | Zones |
| `certification.segment` | `BldgSegment.phius_certification` fields | Certification |
| `programs.airtightness` | Each Room's honeybee `Infiltration`, converted so PHX's back-conversion returns the entered value (F4a-09); `BldgSegment.wind_exposure_type` | Programs |
| Space airflows | `SpacePhProperties._v_*` per section 4 | Spaces |
| Effective Program | The Room's honeybee `ProgramType` with its loads and Schedules | Programs |
| Dwelling and counts | honeybee-ph People extension per Room (F4a-19) | Programs |
| Equipment Set | honeybee-ph `PhEquipment` Process loads, by Dwelling (F4a-17, Q4a-21) | Programs |
| Segment set points | `BldgSegment.set_points` | Programs |

**PHX in tests.** PHX is not a dependency today (`pyproject.toml`; the research read a local
checkout, PHX 1.59.1). P4a-03 adds an optional `phx` dependency group pinned to a released PHX; the
round-trip tests skip when it is absent and run in each stage's host gate with it installed.

## Open contract questions

| Id | Question | Recommendation | Settle in |
| --- | --- | --- | --- |
| C4a-2 | A copied Zone shares its source's Dwelling: does it stay in it? | Yes, until the user chooses One dwelling each; a finding when a Dwelling spans Segments | P4a-08 |
| C4a-3 | A Dwelling's Zones in two Segments | Refused by Programs' actions; a finding on generic routes | P4a-08 |
| C4a-4 | The n50/q50 conversion's exposed area: PH-Composer's envelope sum, or PHX's `cleanup` rule exactly | Match PHX, proven by a round trip reading back the entered value | P4a-06 |
| C4a-5 | Which feature owns mechanical cooling and the mechanical room temperature | Phase 4 mechanical; listed under Planned until then | Ed, with this plan |
| C4a-6 | Keep a per-Space `airflow_mode` copy for agents | Yes, derived from the Zone, for one API minor version | P4a-05 |
| C4a-7 | Single dwelling's default: on for every Segment whose extension is absent (so a new Model's first Segment and every added Segment start on), or on only for the first | On for every Segment, effective only while residential. It needs no Segment-created transition and fits Q4a-27; it replaces the earlier proposal that added Segments start off | Ed, with this plan |
| C4a-8 | Moving a Zone back into a Segment after its shared Faces were reclassified to an Attached zone | Leave them as Attached zone; the user re-runs Solve to restore Surface pairs, and the move-back notice says so | Ed, with this plan |
