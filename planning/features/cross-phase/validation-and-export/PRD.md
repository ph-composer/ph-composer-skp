# Validation and export: behavior contract

DATE: 2026-09-18
STATUS: Phase 1 HBJSON/report scope implemented and current-host verified 2026-09-30; later feature scope remains proposed. METr remains deferred.
AUTHOR: Ed May, BLDGTYP, with Codex review
ISSUE: none (local planning draft)

## Delivery scope

Ed deferred METr exporter development and consumer acceptance on 2026-09-20 until feature
development is further along; the return milestone is unscheduled. Phase 1 delivers the canonical
HBJSON/report workflow only. METr, exporter-selection defaults, optional-artifact recovery and
METr-specific acceptance below remain future contracts, not Phase 1 requirements. The existing
exporter seam and D2 policy remain valid.

## Problem

Each feature knows how to validate and project its own data, but the user needs one trustworthy
handoff. A successful run must prove that every supported candidate was emitted, refused or
declared outside scope; write a coherent HBJSON and human-readable account; and keep a failure in
one optional consumer from changing the canonical artifact.

The predecessor proved the workflow, report, complete-accounting rule, cancellable Model walk,
privacy allowlist and recoverable two-file replacement. PH-Composer removes every designPH
collector and makes feature contributors and downstream exporters the explicit seams.

## Product boundary

- HBJSON is the canonical interchange and the product's core promise.
- The Export report is the human-readable account of the same run. It is not a certification
  checklist and does not claim Phius acceptance.
- METr is the first optional exporter. It consumes only the accepted HBJSON and the user's export
  choices. It never reads the SKP extraction or feature contracts.
- Features own their validation rules and translation sections. This packet aggregates them and
  owns workflow, accounting, artifacts and exporter isolation. It never duplicates a feature scan.
- Export reads a coherent authored state. Any repair offered before export is an explicit Model
  action with its own Undo step, completed before the read-only snapshot begins.

## Artifacts and terminal states

The user chooses one HBJSON destination. The report name is derived beside it:

- `<name>.hbjson`
- `<name>-export-report.html`
- `<name>-metr.json` when the METr exporter is selected and succeeds; final extension to be
  confirmed against METr's import UI

The HBJSON and report are one coordinated pair. A METr artifact is a derived third output, not a
member of that atomic pair.

The panel ends in one state:

| State | Meaning |
| --- | --- |
| Export complete | HBJSON and report committed, with no findings; every selected exporter succeeded |
| Export complete with findings | HBJSON and report committed; the run has non-blocking findings or an optional exporter failed |
| Export cancelled | The user cancelled before commit; no new canonical pair was written |
| Export not created | Blocking validation, incoherent Model state, translation, conformance or pair-commit failure prevented a trustworthy canonical pair |

Under confirmed decision D2, a METr failure never changes a successfully committed canonical
pair and never overwrites an older METr file.

## Validation and complete accounting

Every validation rule is registered by its owning feature with severity, stable code, subject,
plain-language message and repair route. The validator evaluates the shared snapshot once.
Blocking findings prevent the canonical pair. Warnings and information remain visible but do not.

Face assignment owns the assembly and Attached zone reference requirements: every emitted opaque
face needs a valid authored construction, and AttachedZone needs a valid local reference. Failed
required construction lookup blocks the canonical pair even if translation continues to collect
other findings. The adjacency packet's reported omissions remain distinct; no implicit construction
or boundary default turns an incomplete authored face into an emitted one.

Every export candidate ends in exactly one category:

1. emitted without a finding;
2. emitted with a finding because the representation is approximate or incomplete but usable;
3. not emitted with a finding because it cannot be translated safely; or
4. outside supported scope.

Panel totals, the HTML report's embedded result and HBJSON object counts reconcile from this one
account. Unknown exceptions fail the pipeline; they do not become an `other` item bucket.

### Zone rows carried from zones-and-adjacency

Moved here on 2026-09-30 when the [zones-and-adjacency packet](../../../archive/phase-01-zones-and-adjacency/PRD.md) was archived. The table is
that PRD's validation contract with the state of each row in the merged code. Rows marked
"Not implemented" are later work for this packet.

| Finding | Severity | Repair | State |
| --- | --- | --- | --- |
| No Zone in the model | blocking for export | Make Zone | Implemented: preflight `zone.none` |
| Face outside any Zone | warning | Move into a Zone or ignore | Not implemented as a row; the Classify tool refuses such a Face |
| Zone not closed (`manifold?` on the deferred pass; disclosed in the Zones table and the report) | info; blocking for EnergyPlus | Fix geometry | Not implemented |
| Candidate interior face unsolved (multi-Zone model only) | warning; blocking for EnergyPlus | Solve adjacencies or mark To neighbour | Not implemented |
| Adjacency stale | warning; blocking for EnergyPlus | Solve adjacencies | Partly: preflight offers the Solve repair and the report lists Surface omissions; no validation row |
| Adjacency endpoint unresolved or ambiguous | warning; blocking for EnergyPlus | Resolve identity ambiguity, then Solve adjacencies | Partly: reported as a Surface omission |
| Retired adjacency needs boundary classification | warning; blocking for EnergyPlus | Classify or Solve adjacencies | Partly: reported as a Surface omission |
| Sliver skipped; overlapping Zones; Face overlaps more than one neighbour | warning | Named with both Zones or neighbours | Implemented as Solve findings, not export validation rows |
| Orphaned stamped contents | warning | Native Undo, or limited Restore Zone when eligible | Not implemented as a row; Restore Zone exists |
| Zone inside a Zone, or a component marked as a Zone | warning | Regroup | Export refuses instead (`face.wrong_zone` and resolution refusals); reconcile severity |
| Interior window | blocking for export | Move the window to an Outdoors face | Owned by window-types |

Consumer policy from the same PRD (zones Q10): closure and unsolved interior faces block only a
later EnergyPlus exporter; the HBJSON artifact and METr accept an open Zone and disclose it.

## Workflow

### Ready and preflight

- The Export tab states that it produces HBJSON and an Export report, with optional exporters
  listed separately. Runtime internals remain in diagnostics.
- Preflight shows blocking findings before opening a destination dialog and gives Locate or the
  feature's named repair. It does not invent automatic fixes.
- The zones packet's **Re-solve adjacencies before export** is a checked preflight action already
  accepted by that packet. The UI names the Model change and Undo boundary, runs it
  before the snapshot and revalidates. Export itself remains read-only.
- Preflight passes an explicit all-Zone mutation set to the zones feature's public solve operation,
  independent of selection. Its proposal, refusal and atomic rollback rules are the same as a
  direct call. If the user skips repair, translation still excludes stale or unresolved Surface
  references and any counterpart whose target is not emitted. The report accounts for those faces
  and retired faces awaiting classification as omissions, preserving the zones packet's warning-only
  HBJSON/METr policy. No exporter receives a dangling Surface or repairs the Model itself.
- A development-only fixture construction may be used by the Phase 1 synthetic skeleton to prove
  the vertical path. It is not the planned SD assembly, never becomes a Model record, is forbidden
  in a user build and is not a fallback for an incomplete face. Phase 2 closes that temporary gate
  with real assemblies.

### Destination and run

1. Open the native save dialog before Model collection or runtime boot. Cancel returns to ready
   without a write.
2. Make intended replacement of an existing coordinated pair explicit.
3. Prepare contributors, settle open feature transactions and capture one export-relevant Model
   generation.
4. Read the Model under bounded, cancellable slices; boot Pyodide only after a viable snapshot.
5. Translate and run local conformance on the in-memory HBJSON.
6. Let selected exporters consume that exact accepted document and stage any successful optional
   outputs. Exporter findings join the result account; they never alter the HBJSON.
7. Finalize optional outputs under the run's recovery ledger. A failed optional write restores or
   preserves its prior file and becomes an exporter finding rather than a canonical-export failure.
8. Build and verify the self-contained report from the final result account, then stage and commit
   the canonical pair. If the canonical commit fails, roll back any optional output finalized by
   this run.

User-facing stages are Reading Model, Preparing Export, Translating, Checking Export, Writing
Files and, when selected, Writing METr. Progress uses counts where a denominator is known and
never invents a percentage.

If export-relevant Model content changes after collection starts, the run stops without a new
pair. Camera, selection and navigation do not invalidate it. Cancellation remains available until
canonical-pair commit begins; a request during a non-interruptible Python step discards the result
at the next stage boundary.

### Result

A successful result leads with artifact names and counts. Findings are grouped by cause and link
back to the owning feature's Locate or repair action. The HTML report carries complete item detail,
run and conformance versions, supported-scope statement, unit system captured when the run began,
and exporter results. It is self-contained and escapes every Model-authored string.

## Privacy and artifact hygiene

- The report and HBJSON use a composed allowlist: shell fields plus fields declared by registered
  feature contributors and exporters. An undeclared result field fails Checking Export.
- Credentials, provider addresses, local source paths, arbitrary attribute dictionaries, private
  evidence bytes, diagnostics and usernames are excluded.
- Every selected output is serialized to a narrowly named staging file in the destination folder
  and verified before replacement. The canonical pair is committed with a recoverable prior pair;
  a failed replacement must never leave one new canonical final beside one old final. Optional
  output replacement is separately recoverable and is rolled back if the canonical pair fails.
- Startup or the next run performs bounded recovery only for staging and backup names owned by
  PH-Composer. It never deletes unrelated files.

## Exporter contract

An exporter registers a label, output format, choice schema, `run(hbjson, choices)` and report
renderer. It receives the exact accepted HBJSON document and returns its artifact bytes plus
structured findings. It cannot read the Model, contributor extraction or feature code.

The METr exporter calls PHX in the shipped runtime. Its gate proves that PHX imports without
Excel-only dependencies, converts a synthetic multi-Zone HBJSON, stays within an accepted payload
budget and has a complete license manifest. Failure of that gate defers METr output; it does not
defer HBJSON.

## Decisions for the interview

| # | Question | Recommendation |
| --- | --- | --- |
| Q1 | Commit HBJSON/report when METr fails? | Confirmed in D2. Record the exporter failure and preserve any prior METr file |
| Q2 | May a run with blocking findings write a diagnostic report? | Do not write the canonical pair. Keep the complete diagnostic account in the panel; offer an explicitly named **Save diagnostic report** later only if users need it |
| Q3 | Should stale-adjacency repair remain checked by default? | Yes, because the zones interview accepted it, but present it as a named preflight Model action with one Undo step before export begins |
| Q4 | Should a successful export save the SKP? | No. Export reads current in-memory state and never saves or changes the Model implicitly |
| Q5 | Which exporters are selected by default? | HBJSON/report are always on. METr defaults on once its gate passes and the preference may be remembered per user, not per SKP |
| Q6 | Final METr file extension and overwrite UX | Deferred with METr; confirm against its import UI when work resumes, since B1 did not open the output there |
| Q7 | Is the Phase 1 placeholder construction acceptable as development-only proof? | Yes. Refuse it in packaged/user builds and remove the gate before Phase 2 can close |

## Non-goals

Certification evidence completeness, Phius rule checking, hosted upload, review conversations,
automatic Model versioning, HBJSON reconstruction, feature-specific calculations, silent repair,
or rewriting correct HBJSON around a consumer defect.

## Acceptance shape

Offline:

- Versioned synthetic contributor contracts for Zones and faces; exhaustive result categories;
  stable cause codes; deterministic identity and ordering without sorting geometry.
- Clean, warning, blocking, cancellation, Model-mutation, translation, conformance, serialization,
  exporter and every pair-commit failure path.
- Privacy allowlist and HTML escaping; no local paths, credentials, provider addresses, arbitrary
  dictionaries or evidence bytes in either canonical artifact.
- The exact accepted HBJSON loads in pinned honeybee and passes current PHX conversion when the
  METr exporter is enabled. The HBJSON is identical whether or not METr was selected.

Fresh-process host gate:

- On a synthetic two-Zone model, cancel the destination dialog; run a clean export; run with a
  warning; introduce a blocking finding; cancel during collection and translation; mutate the
  Model during a yielded read; replace an existing pair; inject a commit failure; and confirm the
  terminal state and files each time.
- Reconcile Model records, panel totals, embedded result, HTML detail, HBJSON objects and METr
  values. Verify one nested rotated Zone and export while a nested edit context is open.
- Run one exporter failure after a valid canonical pair and prove the pair remains available and
  the prior METr artifact is not overwritten.

## Prior art and evidence

- Predecessor `planning/archive/E1_supported-envelope-export.md` and
  `E1_ACCEPTANCE_EVIDENCE.md`: complete accounting, workflow, privacy, cancellation and artifact
  replacement.
- Predecessor `src/ph_navigator_sketchup/export/`: contributor registry, task workflow, report and
  artifact hygiene to adapt without designPH collectors.
- [`context/TECH_STACK.md`](../../../../context/TECH_STACK.md), "Pyodide and Export boundary" and
  "The exporter seam".
