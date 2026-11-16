# METr export

DATE: 2026-09-30
STATUS: Deferred. Carried from Phase 1 acceptance row A15; return milestone unscheduled.
AUTHOR: Ed May, BLDGTYP, with Claude
ISSUE: none (local planning draft)

## Problem

The MVP targets METr, but Phase 1 closed on HBJSON/report. Ed deferred METr exporter development
and consumer acceptance on 2026-09-20 until more authoring features exist
([P1-Q1](../../../archive/phase-01-faces-and-zones/DECISIONS.md)). Nothing on the branch writes a METr file today. Until this
packet completes, PH-Composer cannot claim a METr outcome.

## What already exists

- **Canonical input.** The HBJSON/report pair, its export task, pair recovery and privacy checks
  ([P1-E evidence](../../../archive/phase-01-faces-and-zones/evidence/p1-e-export-workflow.md)). METr is an optional second
  artifact produced from that HBJSON, never from the SKP directly.
- **Conversion route.** The B1 spike ran PHX `from_HBJSON` and `to_METr_JSON` in Pyodide without
  Excel ([spike evidence](../../../archive/phase-00-foundation/evidence/spike-phx.md)). It proved conversion only;
  the output was never opened in METr. PHX packaging is tracked upstream in
  [PH-Tools/PHX#157](https://github.com/PH-Tools/PHX/issues/157).
- **Failure policy.** D2: when METr fails, keep the valid HBJSON/report pair, report the failure
  and preserve any prior METr file.
- **Climate boundary.** D9: a climate-bearing METr export is blocked until the user supplies
  authorized peak-load values. Never synthesize peak loads.

## Scope when resumed

1. Re-scope against the authoring features that exist at that point (Assemblies, Window Types,
   Spaces, equipment). Decide which METr sections are required for a first useful export.
2. Add PHX and its dependencies to the pinned wheel manifest; re-measure installed footprint
   against the package ceiling and re-run native/Pyodide parity.
3. Register the METr exporter through the public exporter registry, with no special case in core
   orchestration.
4. Implement optional-artifact replacement and recovery beside the canonical pair, under D2.
5. Consumer acceptance: import actual exports into METr and reconcile identifiers, areas,
   assemblies and references against the HBJSON.

### Zone mapping carried from zones-and-adjacency

Moved here on 2026-09-30 from the archived [zones-and-adjacency PRD](../../../archive/phase-01-zones-and-adjacency/PRD.md): one METr variant per
Building-Segment, with that Segment's Zones merged. A Surface pair inside one Building-Segment is
omitted; a Surface pair across Building-Segments and a To neighbour Face are both written as
to-neighbour. PHX's Building-Segment rule governs (zones Q10). Building-Segment names become the
METr model's names.

## Open questions

| # | Question | Note |
| --- | --- | --- |
| Q1 | Final file extension and overwrite UX | Validation/export PRD Q6; confirm against METr's import UI |
| Q2 | Floor-area source | B1 left zone rooms empty and floor areas zero. Decide whether Spaces must exist first or another source is acceptable; no workaround without a decision |
| Q3 | Minimum sections for a useful first export | Depends on which Phase 2 to 4 features have landed |
| Q4 | Climate in the first export | Governed by D9 and the [climate data](../../phase-04-climate/README.md) packet |

## Acceptance shape

A real authored Model (no tools-only construction provider) exports HBJSON and METr in one run;
METr imports the file; its zones, envelope areas, assemblies and adjacency match the HBJSON; a
forced METr failure leaves the canonical pair and any prior METr file intact. Real-project METr
exports stay in `_private/`.
