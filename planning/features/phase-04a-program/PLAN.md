# Phase 4a delivery plan: Building Segments and Programs on the Zones tab

DATE: 2026-11-15
STATUS: Scoped. Stages P4a-01 to P4a-06 are ready to authorize; P4a-07 to P4a-11 wait on the Programs tab review (gate G1). No stage authorized.
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
(its own authorization; P4a-10 writes rulesets until it ships), SketchUp 2023 and Windows host
proof, public distribution.

## What earlier phases supply

Paths are relative to `src/ph_composer/`. Planning baseline `origin/main` at `a4dc9601`.

| Existing | Reused as | Still required |
| --- | --- | --- |
| `features/zones/options/` Segment and Level records, management, adoption | Segment membership and its rules | Nullable membership, last-Segment refusal, optional survivor (P4a-01) |
| `html/features/zones/overview.js`, `zone_cells.js`, `option_dialog.js` | Geometry view | Segment heading rows; the column and Manage dialog removed (P4a-02) |
| `html/features/spaces/view.js`, `cells.js`, `selection.js` | Spaces view | Segment heading rows, Zone rows in the selection, per-Zone airflow mode (P4a-02, P4a-05) |
| `core/records/extension.rb`, structured extension envelopes | Segment settings and per-Zone assignments (CONTRACTS sections 2 and 5) | The foreign-extension write route (C4a-1) |
| Proposal participants and compound proposals | One Undo step for the settings dialog | One participant per section owner |
| `features/zones/faces/attached_zone.rb`, `PhAdditionalZone` export | Shared Faces of Zones left out | The move-out offer; PHX duplicate check (P4a-03) |
| `python/ph_composer_translation/` sections, shared `BldgSegment` per Segment | Leaving Zones out; certification, airtightness and Program sections | New sections per stage |
| Library providers, file provider, library kinds (Materials, frames, glazings) | Program, Schedule and Equipment Set library kinds | P4a-07 |
| Agent registry, `API::CHANGES`, `docs/AGENT_GUIDE.md` | Every operation added here | One API minor bump and one guide recipe per stage that adds a name |

## Stages

| Stage | Delivers | Depends on | Code owner | Host gate |
| --- | --- | --- | --- | --- |
| [P4a-01](phases/p4a-01-segment-membership.md) | Zone schema 3 (nullable Segment), last-Segment and default rules, Segment delete with destination, `set_building_segment` | Ed's go | zones | Delete, move and Undo/Redo in a real Model; reopen |
| [P4a-02](phases/p4a-02-segment-rows-and-settings.md) | Segment heading rows in Geometry and Spaces; New, Delete and Move from the tables; the settings dialog, General section and section seam; Manage dialog and Geometry column removed | P4a-01 | zones, spaces, UI | Panel gestures with Ed |
| [P4a-03](phases/p4a-03-segment-export-rules.md) | Export minimum, Zones left out, empty Segments, Attached zone on shared Faces, the move-out offer, PHX round trip of `PhAdditionalZone` | P4a-01 | zones, spaces, thermal_bridges, export | RBZ export; WUFI XML and METr JSON read back |
| [P4a-04](phases/p4a-04-segment-certification.md) | `ph_composer.certification`: Phius certification section and its export to `BldgSegment` | P4a-02 | certification (new) | Exported values read back in PHX |
| [P4a-05](phases/p4a-05-detailed-airflows.md) | Per-Zone airflow mode, By Program, From Program, the notice, No Spaces warning | P4a-02 for the Zone-row action | spaces, UI | Spaces gestures with Ed; export round trip |
| [P4a-06](phases/p4a-06-programs-feature-and-airtightness.md) | `ph_composer.programs` with the Airtightness section and infiltration export | P4a-02, P4a-04 | programs (new), export | Entered n50 and q50 read back in PHX |
| G1 | **Programs tab review with Ed**; P4a-07 to P4a-11 are rewritten to its answers | P4a-06 merged or not | | |
| [P4a-07](phases/p4a-07-program-records.md) | Program, Schedule and Equipment Set kinds, the built-in residential default, library kinds | G1 | programs | Panel-closed script, Undo/Redo, reopen |
| [P4a-08](phases/p4a-08-dwellings-and-single-dwelling.md) | Dwellings, per-Zone assignment extension, derivations, Single dwelling, Occupancy section | P4a-07 | programs | Single dwelling on and off, Undo/Redo, copy a Zone |
| [P4a-09](phases/p4a-09-zones-programs-view.md) | Zones / Programs view, selection bar, Dwelling and lock bubbles | P4a-08, P4a-05 | programs, UI | Panel gestures with Ed |
| [P4a-10](phases/p4a-10-program-export.md) | ProgramType, People, Process and set point export; Comfort section | P4a-08 | programs, export | Round trip of the five prototype journeys |
| [P4a-11](phases/p4a-11-programs-tab.md) | The Programs tab | G1, P4a-07 | programs, UI | Panel gestures with Ed |
| [P4a-12](phases/p4a-12-acceptance-and-handoff.md) | Register closed; context, docs, glossary; handoff to Phase 4 | all above | integration | Fresh-process integrated run |

```
P4a-01 ─┬─ P4a-02 ─┬─ P4a-04 ─ P4a-06 ─ G1 ─ P4a-07 ─┬─ P4a-08 ─┬─ P4a-09 ─┐
        │          │                                  │          └─ P4a-10 ─┤
        │          └─ P4a-05 (also feeds P4a-09)      └─ P4a-11 ────────────┼─ P4a-12
        └─ P4a-03 ──────────────────────────────────────────────────────────┘
```

P4a-03, P4a-04 and P4a-05 can run in parallel once their dependency merges; they touch different
features. P4a-06 follows P4a-04, which it requires. Each stage is one PR through the pr-loop ([stage brief](../../../.agents/stage-brief.md)),
with one Sonnet read-through and one Codex review; P4a-01, P4a-02 (the new seam) and P4a-07 (the
record kinds) take the stronger review lane.

## Review and verification profile

- Focused tests while building, `make ci` on the final diff, runtime manifest refreshed for panel
  or Python changes, goldens reviewed against the contract.
- Every stage that adds or reshapes an operation bumps the API minor version and regenerates
  `docs/API_REFERENCE.md` with `make fixtures`.
- Every export stage ends with a PHX round trip through the pinned stack that reads back the value
  the user entered, as P4a-03 and P4a-06 define.
- Host gates follow the [native acceptance skill](../../../.agents/skills/ph-composer-native-acceptance/SKILL.md)
  and record ledger receipts during the run.
