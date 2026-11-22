# P4-08b: Building Segment mechanical settings

DATE: 2026-11-22
STATUS: Requested. A gate stub: written in full after D4-26 is answered and summer ventilation is interviewed.
AUTHOR: Ed May, BLDGTYP, with Claude
ISSUE: none (local planning draft)

Added on 2026-11-22 from the [Phase 6 handoff](../../../archive/phase-06-program/STATUS.md#handoff-to-phase-7-mechanical)
(C4a-5). The finding is [DECISIONS](../DECISIONS.md#part-4-review-after-programs-2026-11-22) F30.

## Entry gates

P4-02 merged (the feature exists to register the namespace). P4-08 merged, if D4-26 is answered
as recommended, because the finding compares the switch with the blended heat pump's cooling.
D4-26 answered. A short summer ventilation interview: which of honeybee-ph's eleven
`SummerVentilation` fields are shown, and their defaults.

## Owns

A Mechanical section in the Building Segment settings dialog and its export:

- A structured extension on the Building Segment record, in this feature's own namespace,
  holding mechanical cooling, the mechanical room temperature and the summer ventilation values.
- The panel section, registered with `segmentSettingsSection`, after Comfort.
- An export contributor that claims the namespace on the Building Segment kind through
  `entity_projections`, one record per exported Segment, defaults included.
- A Python section at the `SEGMENT` host that sets `set_points.mechanical_cooling`,
  `mech_room_temp` and `summer_ventilation` on the shared `BldgSegment` in place. It never sets
  `set_points.winter` or `.summer`, which Programs writes.
- A PHX round trip if D4-25 is answered as recommended: PHX copies mechanical cooling and the
  mechanical room temperature to the Variant.

## Reuses

The shipped seam, unchanged: `context/EXTENSIBILITY.md`, "Building Segment settings". Phius
certification (`features/certification/`, `certification_sections.py`) is the pattern for a
section that stores on the Segment and attaches at `SEGMENT`. Zones owns the dialog, Save and the
Segment record; this stage writes none of them.

## Planned in full when

D4-26 is answered and the summer ventilation interview is recorded in
[DECISIONS](../DECISIONS.md). The full document then follows the shape of
[P4-06](p4-06-hot-water-records-and-export.md): scope, steps, source, tests first, host gate, out
of scope, done condition. Its register row M16 in [ACCEPTANCE](../ACCEPTANCE.md) is filled in the
same change. Until then this stage is not authorized and has no steps.
