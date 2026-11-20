# Phase 4a delivery plan: Building Segments and Programs on the Zones tab

DATE: 2026-11-15
STATUS: Scoped. The Programs tab review (G1) is done; P4a-01 to P4a-11 are written and ready to authorize; P4a-12 is the closing outline. No stage authorized.
AUTHOR: Ed May, BLDGTYP, with Claude
ISSUE: none (local planning draft; one issue per stage group when Ed authorizes)

## Outcome and scope

On a synthetic single-family model and a synthetic apartment-plus-common-area model: Segments
grouped and managed in every Zone view, a Zone kept out of every Segment, each Segment's settings
edited in one dialog, Programs, Dwellings and Equipment Sets assigned in Zones / Programs, detailed
airflows entered in Zones / Spaces, and an HBJSON that PHX turns into WUFI-Passive and METr input
with the occupancy, loads, airtightness and ventilation the user set, read back by a round trip.

Behavior: the [Phase 4a PRD](PRD.md) and the [Building Segments PRD](building-segments/PRD.md).
Records and seams: [CONTRACTS](CONTRACTS.md). Answers: [DECISIONS](DECISIONS.md). Acceptance
register: [ACCEPTANCE](ACCEPTANCE.md). Library files: the
[ph-composer-standards plan](../unscheduled/ph-composer-standards/README.md), whose stage S3 needs
P4a-07.

Out of this plan: the items the PRDs list as out of scope, the honeybee-ph and PHX fix for F4a-13
(its own authorization; until it ships, P4a-10 writes occupancy and lighting Schedules as rulesets only, while ventilation Schedules carry their operating periods, C4a-10), SketchUp 2023 and Windows host
proof, public distribution.

## What earlier phases supply

Paths are relative to `src/ph_composer/`. Planning baseline `origin/main` at `a4dc9601`. Reviewed on 2026-11-20 against `b409bdbc`, after Climate and
Shading: the Zones files this table names and the symbols the stages cite in Zones' export, options and the
registry validation still exist.

| Existing | Reused as | Still required |
| --- | --- | --- |
| `features/zones/options/` Segment and Level records, management, adoption | Segment membership and its rules | Nullable membership, last-Segment refusal, optional survivor (P4a-01) |
| `html/features/zones/overview.js` (the Zone views host), `faces_view.js` (Geometry), `zone_cells.js`, `option_dialog.js`; the `table_views` contract | Every Zone view | Segment heading rows in the host with a per-view sums hook; the Building-Segment column and Manage dialog removed (P4a-02) |
| `html/features/spaces/view.js`, `cells.js`, `selection.js` | Spaces view | Segment heading rows, Zone rows in the selection, per-Zone airflow mode (P4a-02, P4a-05) |
| `core/records/extension.rb`, structured extension envelopes, `engine.propose_metadata_update` | Segment settings and per-Zone assignments, staged by Zones (CONTRACTS sections 2 and 5) | Evidence narrowed to Segment values (P4a-02); an export projection for extensions on catalog records and a `segment` attachment host (P4a-04) |
| `features/zones/faces/attached_zone.rb`, `PhAdditionalZone` export | Shared Faces of Zones left out | The move-out offer; PHX duplicate check (P4a-03) |
| `python/ph_composer_translation/` sections, shared `BldgSegment` per Segment | Leaving Zones out; certification, airtightness and Program sections | New sections per stage |
| Library providers, file provider, library kinds (Materials, frames, glazings) | Program, Schedule and Equipment Set library kinds | P4a-07 |
| The `phx` dependency group, `PHX==1.57.5` (Climate, [D4c-22](../../archive/phase-04-climate/DECISIONS.md)) | Every PHX round trip | The pin choice (C4a-11) |
| `SiteSection` and `ShadeSection`, both attached at `MODEL` (Climate, Shading) | Unchanged | Left-out Zones stay known to Shading (C4a-12, P4a-03); the `segment` host hands out the `BldgSegment` objects `SiteSection` already set (P4a-04) |
| `session.open_in_panel`, `panel.navigate` and a preflight row's `locate` (Climate, D4c-27) | Preflight rows that open the Zones or Programs tab at the record | P4a-10 |
| Unit quantities `airflow`, `area` and `temperature` on the Ruby and JavaScript sides, with shared vectors (Climate [CONTRACTS](../../archive/phase-04-climate/CONTRACTS.md) section 8) | Set points, airflows, areas | Power, power per area, people per area, airflow per person and per area (P4a-07) |
| Agent registry, `API::CHANGES`, `docs/AGENT_GUIDE.md` | Every operation added here | One API minor bump and one guide recipe per stage that adds a name |

## Stages

| Stage | Delivers | Depends on | Code owner | Host gate |
| --- | --- | --- | --- | --- |
| [P4a-01](phases/p4a-01-segment-membership.md) | Zone schema 3 (nullable Segment), last-Segment and default rules, Segment delete with destination, `update_field` accepting null | Ed's go | zones | Delete, move and Undo/Redo in a real Model; reopen |
| [P4a-02](phases/p4a-02-segment-rows-and-settings.md) | Segment heading rows in Geometry and Spaces; New, Delete and Move from the tables; the settings dialog, General section and section seam; Manage dialog and Geometry column removed | P4a-01 | zones, spaces, UI | Panel gestures with Ed |
| [P4a-03](phases/p4a-03-segment-export-rules.md) | Export minimum, Zones left out, empty Segments, the shared-Face refusal, the move-out offer, PHX round trip of `PhAdditionalZone` | P4a-02 | zones, spaces, thermal_bridges, export | RBZ export; WUFI XML and METr JSON read back |
| [P4a-04](phases/p4a-04-segment-certification.md) | The export projection for Segment extensions; `ph_composer.certification`: Phius certification section and its export to `BldgSegment` | P4a-02, P4a-03 (both edit Zones' export) | certification (new) | Exported values read back in PHX |
| [P4a-05](phases/p4a-05-detailed-airflows.md) | Per-Zone airflow mode, By Program, From Program, the notice, No Spaces warning | P4a-02 for the Zone-row action | spaces, UI | Spaces gestures with Ed; export round trip |
| [P4a-06](phases/p4a-06-programs-feature-and-airtightness.md) | `ph_composer.programs` with the Airtightness section and infiltration export | P4a-02, P4a-04 | programs (new), export | Entered n50 and q50 read back in PHX |
| G1 | **Programs tab review with Ed**: done 2026-11-15 (Q4a-21 to Q4a-25, Q4a-33 to Q4a-36; C4a-5, C4a-7 to C4a-10) | | | |
| [P4a-07](phases/p4a-07-program-records.md) | The `PhEquipment` pin; Program, Schedule and Equipment Set kinds with device editing; the default Program and default Equipment Set; library kinds with dependency copy | P4a-06 | programs | Panel-closed script, Undo/Redo, reopen |
| [P4a-08](phases/p4a-08-dwellings-and-single-dwelling.md) | Dwellings, per-Zone assignment extension, derivations, Single dwelling, Occupancy section, the Segment heading contribution | P4a-07, P4a-05 | programs | Single dwelling on and off, Undo/Redo, copy a Zone |
| [P4a-09](phases/p4a-09-zones-programs-view.md) | Zones / Programs view, selection bar, Dwelling and lock bubbles | P4a-08, P4a-05 | programs, UI | Panel gestures with Ed |
| [P4a-10](phases/p4a-10-program-export.md) | ProgramType, People, Process and set point export; Comfort section | P4a-08 | programs, export | Round trip of the five prototype journeys |
| [P4a-11](phases/p4a-11-programs-tab.md) | The Programs tab | P4a-07, P4a-08 | programs, UI | Panel gestures with Ed |
| [P4a-12](phases/p4a-12-acceptance-and-handoff.md) | Register closed; context, docs, glossary; handoff to Phase 7 mechanical | all above | integration | Fresh-process integrated run |

```
P4a-01 ── P4a-02 ─┬─ P4a-03 ── P4a-04 ── P4a-06 ── P4a-07 ──┬─ P4a-08 ─┬─ P4a-09 ─┐
                  │                                         │          ├─ P4a-10 ─┤
                  └─ P4a-05 ────────────────────────────────┘          └─ P4a-11 ─┴─ P4a-12
```
P4a-05 feeds P4a-08 (and through it P4a-09 and P4a-10).

P4a-03 and P4a-05 can run in parallel once P4a-02 merges; P4a-04 follows P4a-03 (both edit
`features/zones/export.rb`; the PHX test group it once waited for exists) and P4a-06 follows P4a-04, which it requires. Each stage is one PR through the pr-loop ([stage brief](../../../.agents/stage-brief.md)),
with one Sonnet read-through and one Codex review; P4a-01, P4a-02 (the new seam) and P4a-07 (the
record kinds) take the stronger review lane.

## Review and verification profile

- Focused tests while building, `make ci` on the final diff, runtime manifest refreshed for panel
  or Python changes, goldens reviewed against the contract.
- Every stage that adds or reshapes an operation bumps the API minor version and regenerates
  `docs/API_REFERENCE.md` with `make fixtures`.
- Every export stage ends with a PHX round trip that reads back the value the user entered, using
  the optional `phx` dependency group Climate added (C4a-11 sets its pin); those tests skip without it and run in the host
  gate with it.
- Host gates follow the [native acceptance skill](../../../.agents/skills/ph-composer-native-acceptance/SKILL.md)
  and record ledger receipts during the run.
