# P4a-12: Acceptance and handoff

DATE: 2026-11-15
STATUS: Merged to main 2026-11-21 ([#552](https://github.com/ph-composer/ph-composer-skp/pull/552), squash `08a06474`): steps 1, 3, 4 and 5 in the PR; step 2, the integrated run, in the batched host sitting, where PG12 passes after the PHX 1.59.3 pin in [#556](https://github.com/ph-composer/ph-composer-skp/pull/556). Written out from the outline on 2026-11-21. Authorized 2026-11-20 with the rest of Phase 4a; packet complete 2026-11-22 ([STATUS](../STATUS.md#host-sitting)).
AUTHOR: Ed May, BLDGTYP, with Claude
ISSUE: [#538](https://github.com/ph-composer/ph-composer-skp/issues/538)

## Entry and scope

Requires every stage above. Closes what can close offline, folds what landed into `context/` and `docs/`,
writes the handoff to Phase 7 mechanical, and makes the packet the durable record of the loop's departures,
follow-ups and owed host rows. No new behavior: a defect found on the way is fixed only when a register row or
the catch-up review names it, and is otherwise recorded as a follow-up.

Implementation, merge and host acceptance are separate facts. Every PG host row is owed to one batched sitting
with Ed, and step 2 needs the host, so this stage marks nothing Complete, does not archive the packet and does
not close #538. The archive (the packet moved to `planning/archive/phase-06-program/`, its row in
`planning/archive/README.md`) and `Closes #538` are a later PR, after the sitting.

## Steps

1. **Offline gates**, on the final head: `make ci` on Ruby 3.2.2 and the Ruby 2.7.2 floor run of the Ruby
   tests, `make coverage` at the Makefile's thresholds, `make ui-checks` (every browser check in
   `tools/ui-preview/`), and `uv run tools/runtime/browser_check.py --translation`, the runtime browser check with
   its Pyodide half (native and Pyodide translation of the same document must agree), which P4a-05 did not run.
   The packaged footprint from `make rbz-check` against the baseline P4a-01 reset (26,093,959 bytes), the growth
   allowance and the 28,000,000-byte ceiling (C4a-14). Record the counts in [STATUS](../STATUS.md) and PG12.
2. **The integrated run** from a fresh SketchUp process on the installed build of the final head, on the three
   synthetic reference models ([ACCEPTANCE](../ACCEPTANCE.md#synthetic-reference-models)): Segments (move,
   none, delete with a destination), Segment settings (General, Occupancy, Phius certification, Airtightness,
   Comfort), Spaces airflows (By Program, Detailed, From Program), Programs (assign, library copy, Program,
   Schedule and Equipment Set editors), export, and the PHX round trip of the HBJSON. Owed: it runs in the
   batched sitting, after the bridge-launch diagnosis (STATUS, "Host sitting"), with `acceptance_case.py begin`
   and `finish` receipts under case `PG12`.
3. **Context and docs.** Bring `context/CONTRACTS.md`, `context/EXTENSIBILITY.md`,
   `context/UBIQUITOUS_LANGUAGE.md`, `docs/PRODUCT.md`, `docs/USER_DATA.md` and `docs/AGENT_GUIDE.md` (with its
   shipped copy, through `make fixtures`) up to date with P4a-01 to P4a-11b. `AGENTS.md`'s routing table and
   `context/.index.md` reach the Programs contracts; the architecture review skill names them. Check the
   cross-references.
4. **Handoff to Phase 7 mechanical** (C4a-5; the ventilation unit per Space): written in this packet's
   [STATUS](../STATUS.md#handoff-to-phase-7-mechanical) and recorded in the Mechanical packet's STATUS as owed
   from elsewhere. Authorizes nothing there.
5. **The loop's record.** Fold the conductor's notes into the packet: each stage's departures, the follow-ups
   (recorded, not built), every owed host row by PG id with what it needs, and the bridge-launch failure of
   P4a-02 and P4a-03 as a diagnose-first item for the sitting. Run one Codex review (gpt-6-astra) over every
   commit that merged after its PR's last review cycle, fix what holds on the current code, and record each
   finding with its disposition.

## Tests

1. The gates of step 1, with their counts in STATUS.
2. A focused test for each catch-up finding fixed, written to fail first.
3. `make ci-docs` checks: citation and path lint on the folded documents, the help page, the fixtures (the
   shipped guide matches `docs/AGENT_GUIDE.md`).

## Host gate

PG12: the integrated run of step 2. Owed.

## Done when

On this branch: steps 1, 3, 4 and 5 recorded, the catch-up findings fixed or declined with a reason, PG12's
offline rows recorded in ACCEPTANCE, and P4a-12 `Implemented on branch` with step 2 owed. The phase closes
later, when the sitting passes every owed PG row and PG12 or records an accepted limit, and the archive PR lands.

## Open

Nothing beyond the stages' own contract questions.
