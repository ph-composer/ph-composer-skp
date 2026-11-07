# Libraries view: rows a load left out

DATE: 2026-11-07
STATUS: Implemented on branch `feature/library-skipped-rows`; host case pending (below).
ISSUE: [#379](https://github.com/ph-composer/ph-composer-skp/issues/379)

## Why

Admission skips a library row it cannot accept and keeps a code-only catalog note
([contracts](../../../context/CONTRACTS.md), "Catalog notes"), but the Libraries sidebar showed
one sentence, "Some library records were skipped or normalized." A user could not tell which
records were left out or why. PH-Elements' Library now serves every saved record, nameless ones
included, so this matters for its connector first (PH-Tools/ph-elements#137, stage 3), and for
every provider.

## Scope

- The sidebar lists each row a load left out, by record ID, with a reason worded in PH-Composer
  from the note's code: `library.row_required_invalid`, `row_optional_invalid`, `unit_invalid`,
  `row_semantic_invalid`, `row_label_invalid`. At most 20 are listed, then "And N more."
- Notes for rows kept (`row_optional_absent`, `row_fields_omitted`) say records were normalized;
  any other note (a skipped file, a provider's own code, a skip naming no record) says records or
  files were skipped, without a list.
- No change to the note shape, admission, codes or any provider contract: a note still carries
  only codes and identities, so no provider text reaches the UI. Record names are not shown: a
  skipped row's name is either what was missing or provider text the note does not carry.

## Acceptance

- `tests/library_sidebar_test.js`: listed by ID and reason, the 20-row cap, cleared when a later
  load has none; kept-row notes, a skipped file, an ID-less skip and another provider's code each
  reported apart without a list.
- The PH-Elements connector's seam test (`ph-composer-elements` `make composer`) loads a version 2
  snapshot with a nameless Frame through this code: the row is left out and its note names it.
- Host case (pending): in SketchUp, a hosted load with a nameless Frame shows that record's ID and
  reason in the Libraries view. Runs with PH-Elements #137 stage 5 (the live round trip), which
  needs the version 2 service and the connector installed; this branch does not claim it.
