# P4a-07b: Program, Schedule and Equipment Set library kinds

DATE: 2026-11-20
STATUS: Scoped (split from P4a-07 on 2026-11-20). Authorized 2026-11-20 with the rest of Phase 4a ([STATUS](../STATUS.md)).
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
