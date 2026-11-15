# Phase 4a contracts: records, ownership and seams

DATE: 2026-11-15
STATUS: Scoped for P4a-01 to P4a-06. Sections 5 to 7 are provisional until the Programs tab review. Open contract questions C4a-1 to C4a-6 at the end.
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
| Zone (entity record on the Zone Group) | **Schema 3**: `building_segment_id` becomes nullable. Null is No Building Segment. `level_id` unchanged. Schema 2 stays readable and reads as before |
| `ph_composer.zones.building_segment` (`bsg_`) | Unchanged fields: `name`, `colour`, immutable `export_identifier`. Gains the settings sections of other features as structured extensions (section 2) |
| `ph_composer.zones.option_settings` (`zop_`) | `default_segment_id` stays required and never null |

Rules, enforced by Zones' operations and the management validator in `features/zones/options/`:

- At least one Segment. A management draft or delete that would leave none refuses
  `zone.option_last_segment` (new code).
- Deleting a used Segment names a destination: a surviving Segment or null. Today's required
  survivor for Building Segments becomes optional; Levels keep their rule.
- Deleting the default moves `default_segment_id` to the destination, or to the first remaining
  Segment when the destination is null.
- Make Zone writes the default. Restore Zone recovers a null Segment as null.
- `ph_composer.zones.options.*` keep their names. Their params and results change shape where a
  Segment survivor becomes optional; one API minor bump with a change note (`shell/api.rb`).
- New: `ph_composer.zones.set_building_segment` assigns a Segment or null to Zones by reference,
  one Undo step (the selection bar's route, used by every Zone view).

## 2. Building Segment settings (Zones frame, feature sections; P4a-02)

**Storage: each section is a structured extension on the Segment record.** A feature that
contributes a section registers an extension namespace on `ph_composer.zones.building_segment`
(`context/CONTRACTS.md`, "Records and extension data"): its own namespace, schema version, payload
validator, references and `export_relevance`. The Segment record stays atomic (name, colour,
export identifier); the feature's values live in `extension_data["<feature id>"]`, travel with
copies by the extension's copy rules, and go with the record on delete. A merge keeps the
survivor's extensions and drops the removed Segment's, which the delete confirmation names.

**Panel seam: a settings section.** New, registered by the feature that owns the namespace:

```
panel.segmentSettingsSection(featureId, {
  title, order,                         // "Occupancy", 20
  render(segment, draft, context),      // reads its own extension from the segment read
  validate(draft) -> problems[],        // shown in the dialog; Save stays disabled while any remain
  collect(draft) -> extension payload   // what Save writes
})
```

Zones owns the dialog frame, the General section (name, colour, default) and Save. Save sends one
action, `ph_composer.zones.save_segment_settings`, carrying the General values and each section's
payload; Zones validates its own fields and calls each section owner's proposal participant
(`<feature>.segment_settings.write`) for its namespace, so the whole dialog is one Undo step and
no feature writes another's kind (`proposal.foreign_write`). Registration refuses a section whose
feature registers no participant. This is the fourth panel seam; P4a-02 adds it to
`context/EXTENSIBILITY.md`.

Planned sections and owners:

| Section | Namespace | Payload |
| --- | --- | --- |
| Occupancy | `ph_composer.programs` | `single_dwelling` (bool), `dwelling_id` (reference to `programs.dwelling`, set while single), `default_program_id` (reference to `programs.program`, null for the built-in default) |
| Phius certification | `ph_composer.certification` | `category` (`residential` or `non_residential`), `program`, `use`, `status`, `type`, each an enum mapped to honeybee-ph `PhiusCertification` |
| Airtightness | `ph_composer.programs` | `airtightness_basis` (`n50` or `q50`), `airtightness_value` (number or null, 1/h or m³/h·m² at 50 Pa), `wind_exposure` (the seven `PhWindExposureType` values) |
| Comfort | none | Read only: set points derived from the Zones' Programs |

## 3. Feature ownership

| Feature | Requires | Owns |
| --- | --- | --- |
| `ph_composer.zones` (exists) | | Zones, Faces, Segments, Levels, Attached zones; Segment membership and its rules; the settings dialog frame and seam; Zones / Geometry |
| `ph_composer.spaces` (exists) | zones | Spaces, Volumes, Floor Segments; Space airflows and the per-Zone airflow mode (section 4); Zones / Spaces |
| `ph_composer.certification` (new, P4a-04) | zones | The Phius certification extension on Segments and its export to `BldgSegment.phius_certification` |
| `ph_composer.programs` (new, P4a-06) | zones, spaces, certification | Programs, Schedules, Equipment Sets, Dwellings; the per-Zone assignment extension; the Occupancy and Airtightness extensions on Segments; occupancy and ventilation derivations; Zones / Programs; the Programs tab |

Programs requires Certification because the category decides which Process path PHX reads
(Q4a-14) and Single dwelling needs a residential Segment. Switching Single dwelling on over a
non-residential Segment sets the category through Certification's participant in the same
proposal.

## 4. Space airflows: the mode is per Zone (Spaces; P4a-05)

No schema change: Space records keep `v_sup_m3h`, `v_eta_m3h`, `v_tran_m3h`, each optional.

- **A Zone is detailed when any of its Spaces has any rate**, else By Program (Q4a-29, Q4a-30).
- Export (`python/ph_composer_translation/space_sections.py`, `airflow_rates`): in a detailed Zone
  every Space writes `_v_sup`, `_v_eta`, `_v_tran` in m³/s, 0 for a blank; in a By Program Zone
  every Space writes `None` for all three. PHX never mixes the two (F4a-24, F4a-25).
- Reads (`features/spaces/scan/metrics.rb`): `airflow_mode` moves from the Space row to the Zone row,
  values `by_program` or `detailed`; a Space row keeps `airflows`, with 0 for blanks in a detailed
  Zone and null in a By Program Zone. Zone sums are null while By Program. API minor bump.
- New: `ph_composer.spaces.clear_zone_airflows` clears every Space's rates in the given Zones, one
  Undo step (the Zone row's From Program).
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

**The residential default Program is built in, not a record** (Q4a-13). It is a frozen definition
in code, seeded from the pinned honeybee-ph rules and schedules, addressed as program id null.
Whether it can be edited in place is Q4a-23.

**Per-Zone assignment: a structured extension on the Zone record**, namespace
`ph_composer.programs`, payload `program_id` (reference or null), `dwelling_id` (reference or
null), `bedrooms` and `occupants` (number or null), `equipment_set_id` (reference or null). It
travels with a copied Zone, as an apartment's Program should; a missing extension reads as all
null (unassigned). Zones never reads it.

**Library kinds.** Program, Schedule and Equipment Set register library kinds so a library file
or Connection can supply them; choosing a library Program copies it and the Schedules it
references into the Model (Q4a-19, Q4a-22). The file layout is the
[ph-composer-standards PRD](../unscheduled/ph-composer-standards/PRD.md).

## 6. Derived values (Programs, Ruby; P4a-08 and P4a-09)

Domain calculations live in Ruby (AGENTS.md); the panel formats them and the Python translation
reproduces the same rules for HBJSON.

| Value | Rule |
| --- | --- |
| Effective Program of a Zone | The Zone's `program_id`; else its Segment's `default_program_id`; else the built-in default. Under Single dwelling, always the built-in default |
| Dwelling of a Zone | Under Single dwelling, the Segment's `dwelling_id`; else the Zone's `dwelling_id` |
| Dwelling bedrooms and occupants | The Dwelling's own value when set; else the sum over its Zones; occupants with neither use the Phius rule, bedrooms + units (F4a-20) |
| Zone people | Residential default: the Dwelling's occupants over its presence schedule mean, shared by gross floor area. Other Programs: people per area × floor area |
| Zone ventilation (Programs view) | By Program: the Program's four terms summed, PHX's split (F4a-10). Detailed: the larger of the Zone's Spaces' supply and extract sums |
| Segment set points | From its Zones' effective Programs; a finding when they disagree or a set point schedule is not constant (Q4a-04) |

## 7. Export mapping (P4a-03, P4a-04, P4a-06, P4a-10)

| Source | HBJSON | Section owner |
| --- | --- | --- |
| Zone in no Segment | Left out, with its Faces, Spaces and Edges; info finding | Zones |
| Face whose Surface partner is left out | Its Attached zone as `PhAdditionalZone`; refused when none | Zones |
| Certification extension | `BldgSegment.phius_certification` fields | Certification |
| Airtightness extension | Each Room's honeybee `Infiltration`, converted so PHX's back-conversion returns the entered n50 or q50 (F4a-09); `BldgSegment.wind_exposure_type` | Programs |
| Space airflows | `SpacePhProperties._v_*` per section 4 | Spaces |
| Effective Program | The Room's honeybee `ProgramType` with its loads and Schedules | Programs |
| Dwelling and counts | honeybee-ph People extension per Room (F4a-19) | Programs |
| Equipment Set | honeybee-ph `PhEquipment` Process loads, by dwelling (F4a-17, Q4a-21) | Programs |
| Segment set points | `BldgSegment.set_points` | Programs |

## Open contract questions

| Id | Question | Recommendation | Settle in |
| --- | --- | --- | --- |
| C4a-1 | Can a feature write a structured extension on another feature's catalog or entity record through its own participant, or must the record owner stage it? `context/CONTRACTS.md` covers reading, copying and export of foreign extensions, not the write route | Owner-staged: Zones exposes one participant that writes a named namespace's payload after the namespace owner validates it | P4a-02, with a test |
| C4a-2 | Native copy of a Zone Group carries the Programs extension; does a copied Zone that shares a Dwelling stay in it? | Yes: a copied apartment Zone joins the same Dwelling until the user chooses One dwelling each; a finding when a Dwelling spans Segments | P4a-08 |
| C4a-3 | A Dwelling's Zones in two Segments | Refuse at assignment; PHX counts dwellings per Segment | P4a-08 |
| C4a-4 | Where the n50/q50 conversion's exposed area comes from: PH-Composer's own envelope sum, or a rule matching PHX's `cleanup` exactly | Match PHX, proven by a round trip that reads back the entered value | P4a-06 |
| C4a-5 | Which feature owns mechanical cooling and the mechanical room temperature | Phase 4 mechanical; listed under Planned until then | Ed, with this plan |
| C4a-6 | The `airflow_mode` read moves from Space rows to Zone rows: keep a per-Space copy for agents | Keep it on Space rows too, derived from the Zone, for one API minor version | P4a-05 |
