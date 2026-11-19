# P5s-06: the Shades export section

DATE: 2026-11-19
STATUS: Scoped. Authorized 2026-11-19 with every Shading stage ([STATUS](../STATUS.md#authorization)).
AUTHOR: Ed May, BLDGTYP, with Claude
ISSUE: [#526](https://github.com/ph-composer/ph-composer-skp/issues/526)

## Entry and scope

Requires P5s-02 and P5s-03. Owns `features/shading/export.rb`,
`python/ph_composer_translation/shade_sections.py` with its contract record, the report section
and the PHX round-trip test. Paths are relative to `src/ph_composer/`. Behavior owner: the [PRD](../PRD.md). Names: [CONTRACTS](../CONTRACTS.md).

## Steps

1. **Ruby projection.** `feature.export_contributor("ph_composer.shading.export.shades",
   section_version: 1, requires: [zones section], preflight:, result:, report:)`. From the
   snapshot only: every Face entry that carries the mark or whose path passes a marked container,
   its derived name (D5s-10), its identifier (D5s-08) and its loops in world SI. A Face that
   cannot become a Shade is left out with `reader.note`.
2. **Preflight.** The same findings read live, each locating its Face; all non-blocking. The
   mark's `user_data` raises `export.metadata_omitted` through `Export::MetadataCheck`.
3. **Python section.** `ShadeSection`: reads the record, builds the `Shade` with
   `is_detached=True` and the display name, `attaches = Attachment(MODEL)`,
   `required_for_export = False`, checks every object before `model.add_shade`. One line in
   `composition.py`. Refresh the runtime manifest.
4. **Result, report, privacy, conformance** as CONTRACTS section 6.
5. **PHX round trip.** `tests/python/test_shade_phx_round_trip.py`, skipped without the `phx`
   group: the reference model's HBJSON through the pinned PHX gives five shading components per
   Variant, `InnerAttachment` -1 in WUFI XML and `idIC` -1 in METr JSON.
6. **Cost.** Measure the section and the snapshot at 5,000 Shading Faces; record it.
7. Fold the section into `context/CONTRACTS.md`, "Translation sections and artifacts".

## Tests

Record contract (version, malformed record, unknown key); translate and attach, with a forced
refusal leaving the pair written; identifiers unique across three placements of one definition and
stable across two runs; names per D5s-10; a holed Face; a Model with no shading exports
byte-identically to before the stage.

## Done when

SD06 passes from the packaged RBZ.
