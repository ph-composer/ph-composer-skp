# P4a-04: Phius certification on Building Segments

DATE: 2026-11-15
STATUS: Scoped. Not authorized.
AUTHOR: Ed May, BLDGTYP, with Claude
ISSUE: none (local planning draft)

## Entry and scope

Requires P4a-02 (the seam). Adds the `ph_composer.certification` feature: the Phius certification
section of the Segment settings, stored as its structured extension on the Segment, and its
export. The first outside-Zones feature on the seam, so it is also the seam's proof.

Behavior: [Building Segments PRD](../building-segments/PRD.md), settings table, "Phius
certification". Names: [CONTRACTS](../CONTRACTS.md) sections 2 and 3.

## Steps

1. **Feature.** `features/certification/install.rb`, `requires: ["ph_composer.zones"]`, listed in
   `extension.rb`; codes under the `certification` noun.
2. **Extension.** Namespace `ph_composer.certification` on `ph_composer.zones.building_segment`:
   `category`, `program`, `use`, `status`, `type`, each an enum mapped to honeybee-ph's
   `PhiusCertification` values (`honeybee_ph/phius.py` in the pinned wheel); defaults residential,
   Phius 2021 CORE, residential, in planning, new construction; `export_relevance: required`.
3. **Participant and section.** `certification.segment_settings.write`; the panel section in the
   order the PRD gives.
4. **Read.** `certification.segment` query: one Segment's values with defaults applied, for other
   features (Programs reads the category).
5. **Export.** An export contributor and Python section that set the `BldgSegment`'s
   `phius_certification` fields for each exported Segment.
6. **Docs.** Glossary rows; agent guide recipe; API minor bump.

## Tests (write first)

1. Extension round trip, copy with the Segment, gone with it on delete, kept on the survivor of
   a merge only.
2. Section: renders defaults, validates enums, saves through the dialog as one Undo step.
3. Export: each field in the HBJSON `BldgSegment`; PHX writes it to the WUFI XML.

## Host gate

PG04.

## Done when

PG04 passes.
