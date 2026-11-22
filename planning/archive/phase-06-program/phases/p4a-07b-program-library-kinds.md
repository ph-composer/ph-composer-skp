# P4a-07b: Program, Schedule and Equipment Set library kinds

DATE: 2026-11-20
STATUS: Merged to main 2026-11-20 ([#546](https://github.com/ph-composer/ph-composer-skp/pull/546), squash `e6166275`). PG07b passes on the host. Split from P4a-07 on 2026-11-20. Authorized 2026-11-20 with the rest of Phase 4a; packet complete 2026-11-22 ([STATUS](../STATUS.md#host-sitting)).
AUTHOR: Ed May, BLDGTYP, with Claude
ISSUE: [#538](https://github.com/ph-composer/ph-composer-skp/issues/538)

## Entry and scope

Requires P4a-07a (the three record kinds, [stage doc](p4a-07-program-records.md)). Owns the library kinds of
Programs, Schedules and Equipment Sets and the library coordinator's new dependency copy. Panel closed: the
Programs tab sidebar that copies from a library is P4a-11, choosing a library Program on a Zone P4a-09.

Behavior: [Phase 4a PRD](../PRD.md), "Programs tab", "Library Programs". Names: [CONTRACTS](../CONTRACTS.md)
section 5, "Library kinds". Answers: Q4a-19, Q4a-22, Q4a-25 in [DECISIONS](../DECISIONS.md). Paths are relative
to `src/ph_composer/`.

## Steps

1. **Library kinds** (Q4a-19, Q4a-22): wire kinds `programs`, `schedules`, `equipment_sets` in
   `docs/LIBRARY_FILE_FORMAT.md`, each with its `kind_descriptor`, wire mapping, fingerprint and create,
   replace and assign callbacks, through the existing coordinator as Materials and Frames. Assignment targets the
   Model's default (`ph_composer.programs.settings.update`), and a Zone once P4a-08's assignment exists. The
   callbacks call P4a-07a's operations (`features/programs/operations.rb`), which take their inputs as arguments.
2. **Dependency copy** (new in the coordinator, `library/copy_participant.rb`, `catalog.rb`): a kind declares
   `dependencies(record) -> [{kind, id}]`; copying a Program also copies each Schedule it references in the same
   proposal, reusing a local copy found by source identity, and remaps the references. A missing dependency in
   the library refuses the copy (`library.dependency_missing`, new). Document it in `context/CONTRACTS.md`
   beside the library rules and give Bookshelfing in `context/UBIQUITOUS_LANGUAGE.md` its implemented meaning.
3. **Contract and docs.** Codes, API minor bump with change note, `make fixtures`; an agent guide recipe for a
   library Program; the library walkthrough extended to a Program with its Schedules.

## Source

| File | Disposition |
| --- | --- |
| `library/kind_descriptor.rb`, `copy_participant.rb`, `coordinator.rb`, `catalog.rb`, `features/assemblies/library_kind.rb` | Library kind pattern; the dependency copy is new |
| `features/programs/operations.rb`, `store.rb` | The operations the callbacks call; a library Schedule never lands on a reserved id |

## Tests (write first)

1. Library: copy a Program from a synthetic library file; its Schedules come with it; a second copy reuses the
   local Program and Schedules; a Schedule missing from the file refuses the copy and writes nothing.
2. Each kind's wire mapping and fingerprint round trip; an Equipment Set's devices keep their types and fields.
3. Copy plus assignment as the Model's default is one native Undo step.

## Host gate

PG07b in [ACCEPTANCE](../ACCEPTANCE.md).

## Done when

PG07b passes and the library file format and contracts are updated.

## Decisions in implementation (2026-11-20)

Each recorded in `context/CONTRACTS.md`, "Library dependencies" and "Programs, Schedules and Equipment Sets".

- **Declaration.** `Declarations::LibraryDependencies` (`kinds`, `list`, `remap`) on the adapter, validated at
  registration (other registered wire kinds only) and named by `describe`. A wire row names a dependency by its
  record id in the same library; the local copy names the local record.
- **Resolution in local terms.** The incoming values are compared with each dependency already copied from the same
  source named by its local copy, so a reused Program reads `reuse`; the fingerprint stays the row's own.
- **Which catalog.** A dependency is read from the current loaded catalog of its kind, same provider and library.
  Absent, or the kind never loaded, refuses `library.dependency_missing` with `catalog_state`. A same-named local
  record of other values refuses `library.review_required` naming it: the user replaces that record from the
  library (`use_library`) or renames it first; `keep_local` gives it no source, so it does not resolve.
- **Snapshots.** A Program's source snapshot keeps the library's Schedule ids and an Equipment Set's keeps id-less
  devices, so the Programs kinds declare their library form for the snapshot (`KindFields.with`).
- **Equipment Set replacement.** Keeps each local device whose place the incoming device of the same type takes,
  with its id and `user_data`, and refuses `validation.failed` rather than drop a device holding `user_data`.
- **Assignment.** `{"mode": "model_default", "expected_settings"}` for Programs and Equipment Sets, the Psi-Install
  Type default's shape; Schedules copy without assignment.
- **Projected engine.** `ProjectedEngine#find` and `resolve_reference` accept the change set they read through, so
  the Programs operations, which pass their proposal, run inside a library callback unchanged.
- **Walkthrough.** A sibling of the Materials walkthrough, `tools/examples/library/programs_walkthrough.rb` with
  `programs.json`, rather than extending the Materials one, whose fixture other tests pin to four kinds.
