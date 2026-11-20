# P4a-06: The Programs feature and Segment airtightness

DATE: 2026-11-15
STATUS: Scoped. Authorized 2026-11-20 with the rest of Phase 4a ([STATUS](../STATUS.md)).
AUTHOR: Ed May, BLDGTYP, with Claude
ISSUE: [#538](https://github.com/ph-composer/ph-composer-skp/issues/538)

## Entry and scope

Requires P4a-02 (the seam) and P4a-04 (Programs requires Certification). Creates
`ph_composer.programs` with its first contribution: the Airtightness section of the Segment
settings and its export into each Room's Infiltration, so PHX reads back the entered test result.
No Program records yet.

Behavior: [Phase 4a PRD](../PRD.md), "Segment settings sections Programs owns". Names:
[CONTRACTS](../CONTRACTS.md) sections 2, 3 and 7. Research: F4a-09 and
[PH stack](../research/ph-stack-consumption.md#infiltration-and-airtightness).

## Steps

1. **Feature.** `features/programs/install.rb`, `requires: ["ph_composer.zones",
   "ph_composer.spaces", "ph_composer.certification"]`, listed in `extension.rb`.
2. **Extension.** Namespace `ph_composer.programs.airtightness` on the Segment: `basis` (`n50`,
   `q50`), `value` (number or null), `wind_exposure` (seven values), `export_relevance: required`,
   exported through P4a-04's projection.
3. **Section.** The Airtightness section: basis select, value with its unit, wind exposure; Zones'
   Save stages it.
4. **Conversion (C4a-4).** Read PHX's back-conversion in the pinned PHX (`from_HBJSON/cleanup.py`,
   the exposed-area rule; exponent 0.65; n50 by net volume) and implement its inverse: a Room
   `Infiltration` `flow_per_exterior_area` at 4 Pa such that PHX reports the entered value for the
   Segment. Pure Ruby, used by the panel's preview and the contributor; the Python section takes
   `flow_per_exterior_area` from the contract record and computes nothing (P4a-10's rule). A Face tagged as shading is outside the envelope and outside the
   HBJSON Room, so the exposed area reads a Zone's Faces through Zones' own reads, which leave it out
   (`context/CONTRACTS.md`, "Envelope exclusion").
5. **Export.** Contributor and Python section: each Room of a Segment with a test result gets that
   Infiltration; `BldgSegment.wind_exposure_type`; a Segment without a result leaves the Room's
   Infiltration to its Program (P4a-10) or PHX's default.
6. **Docs.** Glossary; agent guide; API minor bump.

## Tests (write first)

1. Extension round trip and copy; section validation (a negative or zero value refuses).
2. Conversion: unit tests of the inverse against the PHX formula, both bases.
3. PHX round trip (the `phx` group; skips without it): an n50 and a q50 Segment each read back
   from the WUFI XML and METr JSON within 0.01.

## Host gate

PG06.

## Done when

PG06 passes and C4a-4's answer is recorded in CONTRACTS.
