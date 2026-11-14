# ph-composer-standards: one home for library content

DATE: 2026-11-14
STATUS: Requested. Plan only; creating the repository and changing this one each need Ed's go.
AUTHOR: Ed May, BLDGTYP, with Claude
ISSUE: none (local planning draft; open one when Ed authorizes the repository)

Create a public repository, `ph-composer/ph-composer-standards`, that holds every library file
PH-Composer users may want to start from: generic starter records and data sets taken from
standards. Its name follows honeybee's standards packages. It is a set of library files, not code
the extension loads.

## Why

Ed proposed it on 2026-11-14, in the [Phase 4a](../../phase-04a-program/DECISIONS.md#answered)
review (Q4a-19, Q4a-20). Programs, Window Types, Assemblies and later Mechanical Equipment then
follow one rule: content arrives as a library file or a remote Connection, and is copied into the
SKP as editable records. Only behaviour stays in the extension, such as Phase 4a's default
residential Program.

It also finishes an earlier decision. The Libraries interview called the starter library "a
separate download" (Q9). D2-9 put it at `starter-library/` in this repository, CC0 and excluded
from the RBZ, only "until a project site exists". This repository is that separate home. It is not
speculative extraction in the sense of the
[migration plan](../github-organization-migration.md): its files have consumers today (the file
provider and the Materials kind) and Phase 4a adds more.

## What it holds

```text
ph-composer-standards/
  starter/      generic records we write, CC0: materials.json moved from this repository
  phius/        Phius Multifamily and Non-Residential Programs and their Schedules (Phase 4a)
  doe/          optional DOE reference Programs from honeybee-energy-standards (Q4a-20)
  generators/   scripts that build each generated set from its pinned source
```

- **Two classes of content, kept apart.** `starter/` follows the Libraries rules (Q19): generic
  records citing public sources, no table transcribed from a standard, CC0. `phius/` and `doe/`
  are taken from standards, so each folder's README states the source, its version and its terms.
  They are not dedicated under CC0.
- **Generated, not typed in.** The Phius files come from honeybee-ph's `PHIUS_programs.py` and
  the DOE files from honeybee-energy-standards, each at a pinned version, by a script in
  `generators/` (PEP 723 dependencies, run with `uv run`). Editing a generated file by hand is
  refused in review; change the generator or its source.
- **Every file is a [library file](../../../../docs/LIBRARY_FILE_FORMAT.md).** The kinds it may
  hold are the ones PH-Composer registers: today `materials`, `frames`, `glazings` and
  `psi_install_types`; Phase 4a adds Programs and Schedules, and Phase 4 equipment may add more.
  Starter frames and glazings do not exist yet; they are written there when someone needs them.
- **Never loaded by the extension.** The user adds a file in Library setup, as with any library
  file. A hosted Connection serving the same files is possible later and out of scope here.

## What changes in ph-composer-skp

- Remove `starter-library/` (`materials.json`, `LICENSE`, `README.md`).
- Move the check in `tests/starter_library_test.rb`, which loads the file through the file provider
  and validates each row against the Materials adapter, to wherever the open question below puts it.
- `docs/LICENSING.md` ("Bundled components and data") and the "Starter library" row in
  `context/UBIQUITOUS_LANGUAGE.md` point to the new repository.
- `tools/rbz/build.py` refuses `starter-library` as development material, tested in
  `tests/python/test_rbz_build.py`. Keep or drop that guard in the same change.

## Stages

1. **Create the repository** in the `ph-composer` organization with `starter/materials.json`, its
   README and LICENSE moved unchanged, and file validation in CI. Needs Ed's go.
2. **Point this repository at it**: the removals and doc changes above, as one PR.
3. **Phius Programs** (Phase 4a): the generator and the two files, once PH-Composer registers the
   Program and Schedule kinds and Q4a-28 is answered.
4. Later, on need: DOE Programs (Q4a-20), starter frames and glazings, equipment.

## Gates

- Ed's go to create a public repository.
- Q4a-28: Ed confirms the Phius program values may be published with a note of their source and
  terms. honeybee-ph already publishes them.
- Verify, before stage 3 and 4, the licenses of honeybee-ph and honeybee-energy-standards and what
  they mean for data generated from them. Not checked for this plan.

## Open questions

| Id | Question | Options |
| --- | --- | --- |
| STD-1 | Which side checks the files against PH-Composer's kind definitions? | (a) The standards CI checks out ph-composer-skp at a pinned commit and runs the file provider and adapters, as `starter_library_test.rb` does now; (b) ph-composer-skp's CI fetches a pinned standards release and runs the check here; (c) PH-Composer publishes a JSON Schema per kind and the standards CI validates against it |
| STD-2 | How are files versioned for users? | Tagged releases with the files attached; or the default branch only until a user needs a fixed version |
