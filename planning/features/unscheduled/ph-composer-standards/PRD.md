# ph-composer-standards: library content for PH-Composer

DATE: 2026-11-15
STATUS: Scoped. Plan and stages in [README](README.md); creating the repository needs Ed's go.
AUTHOR: Ed May, BLDGTYP, with Claude
ISSUE: none (local planning draft; open one when Ed authorizes stage S1)

## Problem

PH-Composer copies library content into the SKP as editable records, from library files the user
adds in Library setup or from Connections (Q4a-19). Content PH-Composer did not author for itself,
the starter Materials today and the Phius Programs next, needs one public home with its source,
edition and terms stated, generated reproducibly, and checked against the kinds PH-Composer reads.
Bundling it in the extension would make every content update a release (D2-9, Libraries Q9).

## What the repository is

`ph-composer/ph-composer-standards`, public. A set of library files in PH-Composer's
[library file format](../../../../docs/LIBRARY_FILE_FORMAT.md) and the scripts that generate them.
Nothing in it is loaded by the extension; a user adds a file, or a Connection serves one.

```text
ph-composer-standards/
  README.md          what each folder holds, how to add a file in PH-Composer
  LICENSE            AGPL-3.0 for the generators and tooling, as ph-composer-skp
  starter/           generic records we write; CC0 (LICENSE in the folder)
    materials.json   moved unchanged from ph-composer-skp/starter-library/
  phius/             Phius Multifamily and Non-Residential Programs and their Schedules
  doe/               optional DOE reference Programs (Q4a-20)
  generators/        one PEP 723 script per generated file, run with uv run
  schemas/           the JSON Schema per kind, published by PH-Composer (STD-1)
```

## Rules

1. **Each data folder's README states its source, edition and terms.** `starter/` is CC0 and
   follows the Libraries rules (Q19: generic records citing public sources, no table transcribed
   from a standard). `phius/` and `doe/` are taken from standards and are not CC0.
2. **Phius values are publishable (Q4a-28).** They come from public documents and are not Phius's
   intellectual property: the non-residential programs from the Phius Certification Guidebook, the
   multifamily space types from the Phius Multifamily Lighting and Misc Load Calculator. Each file
   names the document and edition it follows.
3. **Generated files are never edited by hand.** `generators/phius.py` reads honeybee-ph's
   `PHIUS_programs.py` at a pinned version; `generators/doe.py` reads honeybee-energy-standards at a
   pinned version. A change goes into the generator or its pin, and CI regenerates and compares.
   honeybee-ph cites Guidebook v3.02 Table N-10 and the Multi-Family Calculator of 2021-03-23;
   check both against the current editions before S3 generates the files.
4. **Every file validates** against the published schema of each kind it holds, at the
   `kind_schema_versions` it declares. A kind PH-Composer does not register cannot appear.
5. **Releases are tagged** (STD-2); a release lists its files with their kind schema versions
   and the PH-Composer version that reads them.

## Kinds over time

| Kind | Registered in PH-Composer | Files here |
| --- | --- | --- |
| `materials` | Today | `starter/materials.json` (S1) |
| `frames`, `glazings`, `psi_install_types` | Today | When someone needs starter records |
| Programs and Schedules | Phase 4a P4a-07 | `phius/multifamily.json`, `phius/non_residential.json` (S3); `doe/*.json` (S4). Each Program complete, as honeybee-REVIVE's `honeybee_revive_standards/programtypes/` with its `schedules/` beside it: every slot filled, the slots the Phius data lacks from the paired 2019 base program with their source named (Q4a-25) |
| Equipment Sets | Phase 4a P4a-07 | The Phius single-family default Set is built into PH-Composer (PRD, "Dwellings"); a Phius multifamily default Set may come here later |
| Mechanical equipment | Phase 4 | Later |

## Questions

| Id | Question | Recommendation |
| --- | --- | --- |
| STD-1 | Which side checks files against PH-Composer's kinds? | (c): PH-Composer publishes a JSON Schema per kind, generated from its `RecordKind` declarations, and this repository's CI validates against a pinned copy. Language-neutral; no Ruby or SketchUp in this CI. ph-composer-skp keeps one test that its schemas still load a pinned release |
| STD-2 | How are files versioned? | Tagged releases with the files attached; the default branch for development only |

## Out of scope

A hosted Connection serving these files (later), any content PH-Composer would need to load
without the user adding it, licensed PHPP or WUFI material.
