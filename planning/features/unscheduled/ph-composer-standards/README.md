# ph-composer-standards: one home for library content

DATE: 2026-11-14
STATUS: Scoped (2026-11-15). Spec in [PRD.md](PRD.md); stages below. Creating the repository needs Ed's go; S3 waits on Phase 4a P4a-07.
AUTHOR: Ed May, BLDGTYP, with Claude
ISSUE: none (local planning draft; open one when Ed authorizes S1)

A public repository, `ph-composer/ph-composer-standards`, holding every library file PH-Composer
users may start from: generic starter records and data sets taken from standards, with the
scripts that generate them. Named after honeybee's standards packages. The extension never loads
it; users add its files in Library setup.

## Why

Ed proposed it on 2026-11-14 in the [Phase 4a](../../phase-06-program/DECISIONS.md#answered)
review (Q4a-19, Q4a-20). Programs, Window Types, Assemblies and later Mechanical Equipment follow
one rule: content arrives as a library file or a remote Connection and is copied into the SKP as
editable records; only behaviour, such as Phase 4a's residential default, stays in the extension.
It also finishes D2-9, which put `starter-library/` here only "until a project site exists". It is
not speculative extraction in the sense of the [migration plan](../github-organization-migration.md):
its files have consumers today and Phase 4a adds more.

## What changes in ph-composer-skp (S2)

- Remove `starter-library/` (`materials.json`, `LICENSE`, `README.md`).
- Replace `tests/starter_library_test.rb` with a test that loads the pinned standards release's
  `starter/materials.json` when present (skip when absent) and a test that the published kind
  schemas are current (STD-1).
- Generate the JSON Schema per registered library kind from its `RecordKind` declaration
  (`make fixtures`), committed under `docs/library_schemas/`.
- `docs/LICENSING.md` ("Bundled components and data"), `docs/LIBRARY_FILE_FORMAT.md` and the
  "Starter library" row in `context/UBIQUITOUS_LANGUAGE.md` point to the new repository.
- `tools/rbz/build.py` drops its `starter-library` guard and test with the folder.

## Stages

| Stage | Delivers | Depends on | Done when |
| --- | --- | --- | --- |
| S1 | The repository with README, LICENSE, `starter/` (materials moved unchanged, its CC0 LICENSE and README), `schemas/materials.json`, CI that validates every file against `schemas/`, and a first tagged release | Ed's go; STD-1 and STD-2 confirmed | CI green on the release; the file adds in PH-Composer's Library setup and its Materials import |
| S2 | ph-composer-skp points at it, as above, in one PR | S1 | `make ci` green with the release absent and present |
| S3 | `generators/phius.py`, `phius/multifamily.json`, `phius/non_residential.json`, their README with source, edition and terms, the Program and Schedule schemas | Phase 4a P4a-07; the edition check (PRD rule 3); the honeybee-ph licence check below | CI regenerates byte-identical files; each file adds in Library setup and its Programs copy into a Model |
| S4 | On need: `doe/` (Q4a-20), starter frames and glazings, Equipment Sets, mechanical equipment | Their kinds registered | As S3 |

## Gates

- Ed's go to create a public repository.
- Q4a-28, answered 2026-11-15: the Phius values may be published (PRD rule 2).
- Before S3 and S4: confirm the licences of honeybee-ph (GPL-3.0-or-later) and honeybee-energy-standards and
  what they mean for data generated from them. Not checked for this plan.

## Questions

STD-1 (which side validates) and STD-2 (versioning) are in the [PRD](PRD.md#questions) with
recommendations: JSON Schemas published by PH-Composer and validated here; tagged releases.
