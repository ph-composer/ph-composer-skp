# P4c-05: Export of the site and climate

DATE: 2026-11-17
STATUS: Scoped. Not authorized. E1 and E2 in DECISIONS need Ed's answer first.
AUTHOR: Ed May, BLDGTYP, with Claude
ISSUE: none (local planning draft)

## Entry and scope

Requires P4c-02, owed check 6, and Ed's answers to E1 and E2. Writes the Model's site and climate
into the HBJSON as honeybee-ph `Site`, with its findings and the Export report's climate section.
Ruby decides everything (what is written, what is left out, the provenance, Cooling 2); the
Python section builds honeybee-ph objects from the contract record and computes nothing.

It does not need the reader: tests build climate records directly. It can run beside P4c-03 and
P4c-04.

Behavior: [PRD](../PRD.md), "What honeybee-ph and METr take" and "Export". Names:
[CONTRACTS](../CONTRACTS.md) section 7. Answers: W4, W8, J4, J5, J8, R2, R5, R6, R7; D4c-03,
D4c-07, D4c-14. Board: 18 (`ExportReport`), for the report section's content. Paths are relative
to `src/ph_composer/`.

This stage takes the stronger review lane: serialization.

## Entry checks

**Owed check 6.** PHX's handling of the exported `Site` was read in a local checkout, not run.
Before the section is written, with a released PHX installed in a scratch environment outside
the repository's `.venv`:

1. Build the synthetic `Site` of CONTRACTS section 7 in honeybee-ph, put it on a small Model's
   Building Segment, and convert it to WUFI XML and METr JSON.
2. Record what arrives: the four peak-load cases with Cooling 2 equal to Cooling 1; the monthly
   ground row; an empty hours from UTC; climate zone 1; that a provenance with both availability
   flags true converts and one without is refused.
3. Record what honeybee-ph's default `Site` becomes in both outputs. That is today's export, and
   it is what E1 asks about.
4. Choose the released PHX version for the `phx` test group (D4c-14); if the Programs packet's
   P4a-03 has added the group, use its pin.

Already run in the pinned honeybee-ph 1.33.65 on 2026-11-17 and not owed again: `Location`
accepts and round trips a `None` offset; a `Climate` with a `phius_approved` provenance, both
flags true, a nested `assumptions` dict and Cooling 2 copied from Cooling 1 has empty readiness
lists and round trips through `BldgSegment`.

Also settle C4c-4 by reading `export/report.rb` and `export/result_view.rb`, and confirm in
`python/ph_composer_translation/assembly.py` that a section requiring the Zones section attaches
at `MODEL` after the Rooms and their shared Building Segments exist. Unrelated sections sort by
id, and this one's id sorts before Zones', so the order must come from the declared requirement.

## Steps

1. **Contributor** (`features/climate/export.rb`): section `ph_composer.climate.export.site`,
   version 1, requiring the Zones section. It emits the one record of CONTRACTS section 7:
   `status`, `location`, `climate` with `cool_2` added, the derived provenance and the report
   block. It reads the settings and the record through `Export::RecordReader` and the snapshot,
   as `shell/model_metadata.rb` does, never the live Model.
2. **Left-out rules**, in Ruby: no climate; an incomplete climate; no site (R2); and, per E2, a
   site with no climate.
3. **Preflight** (`ph_composer.climate.export_preflight`): the findings of CONTRACTS section 7,
   all non-blocking, each with its code declared in `codes.rb`. Add the E1 finding if Ed agrees.
4. **Python section** (`python/ph_composer_translation/site_sections.py`, `SiteSection`), listed
   in `composition.py` after `ZoneSection`, attached at `MODEL`, optional for export. `translate`
   builds `Location`, the monthly collections, the four `Climate_PeakLoadValueSet`s,
   `ClimateProvenance` and `Site`; `attach` sets that `Site` on each distinct `ph_bldg_segment`.
   A `left_out` record builds nothing. Ground temperatures are not touched.
5. **Result fields and privacy.** The fields of CONTRACTS section 7 declared through
   `Export::Privacy`; none is named or holds a path, and the artifact hygiene check stays green.
6. **Conformance.** The reloaded HBJSON: every Building Segment carries the same `Site`; the
   location and the climate equal the record; Cooling 2 equals Cooling 1; no `source_uri`.
7. **Report section** (`report:` on the contributor), in the order of board 18: site; dataset
   and station; limit check; edited values with their as-read values; peak loads with the
   Cooling 2 line; wind speed; design temperatures and their source note, marked as kept in the
   Model. Rendered through `export/report_html.rb` and `Units`, in the display profile the run
   captured. A left-out climate renders its reason in the same section.
8. **PHX round trip.** Through the `phx` group: export the reference Models, convert to WUFI XML
   and METr JSON, and read back latitude, both elevations, climate zone, the monthly rows and the
   four peak-load cases. Skipped without the group.
9. **Goldens.** A `tests/fixtures/climate/` extraction and result-fields pair, owned by a Ruby
   export test added to the Makefile's `FIXTURE_OWNERS`.
10. **Contract and docs.** `make fixtures`; runtime manifest refreshed for the new Python file;
    `context/CONTRACTS.md`, "Translation sections and artifacts", gains the section;
    `docs/` gains what the HBJSON and the report carry for climate; the agent guide's export
    section; the user data guide row for the climate record (its `user_data` stays in the Model).

## Source

| File | Disposition |
| --- | --- |
| `shell/model_metadata.rb`, `python/ph_composer_translation/model_metadata.py` | Pattern for a Model-level contributor and a section attached at `MODEL` |
| `features/thermal_bridges/export.rb`, `thermal_bridge_sections.py` | Pattern for an optional section, its result fields, report and conformance; how a section reaches `ph_bldg_segment` |
| `python/ph_composer_translation/model_sections.py` (`ZoneSection.attach`) | Where Building Segments are shared; unchanged |
| `export/preflight_result.rb`, `export/report_html.rb`, `export/privacy.rb`, `export/artifact_hygiene.rb` | Reused |
| `pyproject.toml` | The optional `phx` group, if not already added |

## Tests (write first)

1. Contract record: a complete station climate with a set site is `written` with Cooling 2 equal
   to Cooling 1; each left-out case is `left_out` with its reason.
2. Provenance: unedited station, edited station and hand-entered climate give the three
   expected source types, names and checksums; assumptions carry the coordinates and the edits.
3. Preflight: each code on its case, none blocking; an unset zone and an unset offset each give
   one finding and the export still writes.
4. Python: the HBJSON reloads in the pinned stack; a two-Segment Model has the same `Site` on
   both; a `left_out` record leaves honeybee-ph's default in place.
5. Conformance fails when a segment's `Site` is altered after assembly.
6. Report: every line of board 18 for an edited station with one finding; the design
   temperatures and note; IP and SI; no folder location anywhere in the HBJSON, the report or
   the result. The test searches for the fixture folder's absolute path and its parent's name; the
   dataset name, which defaults to the folder's own name, is expected to appear.
7. The PHX round trip.

## Host gate

CM05: the packaged RBZ exports the reference Models; the round trip reads them back.

## Leaves for the next stage

If P4c-06 has merged, this stage gives each finding a `locate` that opens the Climate tab at its
card; if not, P4c-06 does (CONTRACTS section 7). The Mechanical packet adds its
own finding for a heat pump left out for want of design temperatures.

## Done when

CM05 passes, owed check 6 is recorded, and C4c-4 is answered.
