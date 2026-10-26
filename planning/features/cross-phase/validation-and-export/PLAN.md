# Validation and export: implementation plan

DATE: 2026-10-07
STATUS: Phase 1 and Phase 2 scope merged and accepted; later scope remains and METr is deferred.
ISSUE: none (local planning draft)

The [PRD](PRD.md) owns the proposed workflow and the accepted D2 failure policy. The
[Phase 1 plan](../../../archive/phase-01-faces-and-zones/PLAN.md) coordinates feature delivery. Open interview answers and
the accepted METr deferral are in [Phase 1 decisions](../../../archive/phase-01-faces-and-zones/DECISIONS.md).

## Phase 2 allocation

Original allocation, added 2026-09-30 and completed through PR #15 on 2026-10-01. The
[archived Phase 2 packet](../../../archive/phase-02-envelope/README.md) records the implemented
changes and [qualified acceptance](../../../archive/phase-02-envelope/STATUS.md). The allocation
changed this feature's contracts in two stages and added nothing to `export/` orchestration:

| Change | Stage |
| --- | --- |
| The assemblies contributor and constructions section; `ZoneSection` takes a declared requirement instead of a construction provider; the Face preflight's unconditional construction rows are replaced; the tools-only synthetic provider and its fixtures are retired | [P2-06](../../../archive/phase-02-envelope/phases/p2-06-construction-export.md) |
| The windows contributor, the window constructions and apertures sections, the windows preflight rows, the documented g-value schema exception in local conformance | [P2-14](../../../archive/phase-02-envelope/phases/p2-14-aperture-export.md) |
| One Export report line per record copied from a library | [P2-07](../../../archive/phase-02-envelope/phases/p2-07-library-seam-and-file-provider.md) |

After P2-06 the normal build exports, which supersedes the "safely refuses without authored
Assemblies" state recorded below. No wheel is expected to be added: honeybee-energy and
honeybee-ph are already pinned.

## Existing versus missing

Phase 0 supplies the contributor/result declarations, privacy/report contracts and recoverable
canonical pair. P1-C adds typed Zone/Face translation. P1-E now implements the bounded task,
feature-owned preflight, panel lifecycle, wheel payload, conformance and pair commit. P1-F adds
fresh integrated acceptance. [Evidence](../../../archive/phase-01-faces-and-zones/evidence/p1-e-export-workflow.md) closes
A11 to A14 and A16 on the current host. The normal composition continues to refuse missing authored
constructions; the synthetic provider remains development-only. Broader feature validation,
Assembly authoring and the deferred METr consumer milestone are outside this Phase 1 closure.

## Delivery allocation

| Stage | Deliverable | Acceptance |
| --- | --- | --- |
| P1-A | Shared snapshot/geometry reader and proposal/preflight boundary design | One coherent read, no feature-specific orchestration or hidden repair |
| P1-C | Complete 2026-09-20: two-Zone HBJSON development proof through registered sections | [Typed dependencies, exact reload, references/areas/accounting and fixture isolation](../../../archive/phase-01-faces-and-zones/evidence/p1-c-adjacency-hbjson.md) |
| P1-E | Run coordinator, Export UI, progress/cancellation, snapshot guard and conformance | Clean/warning/blocking/cancelled/changed-Model outcomes; destination-first behavior and report consistency |
| P1-E | Pinned HBJSON translation wheels | Native/Pyodide parity and manifest/footprint |
| P1-E/F | Fresh-process canonical export gate | Exact HBJSON/report reconciled against authoring |
| P3b-08 | Thermal-bridge section, the first optional section, and the optional-attachment rule (R05 item 4) | [Phase 3b T08](../../phase-03b-thermal-bridges/ACCEPTANCE.md): runs read back on their Building-Segment; a refused run is omitted and the pair is written |
| Deferred, unscheduled | METr exporter and actual import | Re-scope against available features when Ed resumes this work |

## Implemented Phase 1 contracts

1. **Task lifecycle:** a per-session run with explicit stages, task identity, bounded progress,
   cancellation and teardown. Define bounded task/result retention and retrieval through polling;
   a timeout does not mean cancellation. Specify model-close cancellation/discard, expired handles
   after host restart, and artifact recovery separately from in-memory task state. Test loss of
   the panel/client while the task runs and retrieval without duplicate writes. Keep model-write
   operations separate from file export grants.
   The panel and scripts see the same terminal outcome without requiring the panel to be open.
2. **Snapshot:** contributors prepare once, then read a shared bounded snapshot. Record the
   export-relevant generation and edit context; distinguish content changes from selection and
   camera changes. Validate again before accepting runtime output and before commit.
3. **Translation:** Zone/face sections own their findings and typed results. Resolve emitted
   counterpart references before conformance. No dangling Surface and no hidden default
   construction. Report omissions under the PRD's warning policy; independent blocking findings
   still prevent the canonical pair.
4. **Artifacts:** complete the canonical HBJSON/report pair recovery and report its final state,
   not merely successful serialization. Optional-output replacement/recovery waits with METr.
5. **Runtime:** retain the separate token-origin page by default. Load only manifest-pinned
   wheels, after a viable snapshot. Cancellation during Python execution discards the result at
   the next boundary. No network dependency resolution or system-Python export fallback.

A contributor adds its extraction/result/report declarations and a Python section registration.
A new exporter adds a Python registration taking HBJSON and options only. Use the foundation
example to prove this trace; no new exporter branch belongs in `export/` or a feature scanner.

## Deferred consumer gate and temporary construction

B1 demonstrated PHX conversion of Python-generated synthetic HBJSON in headless Chromium 88.
It did not test an authored SketchUp model, the shipped HtmlDialog conversion path or METr import.
Preserve that evidence for the deferred exporter; Phase 1 selects only the HBJSON translation
wheel set and verifies its real runtime path.

Ed deferred METr export on 2026-09-20 until feature development is further along. Its return
milestone is unscheduled. Floor-area policy, actual import, PHX-specific pins and optional-output
recovery are not Phase 1 blockers. Revisit them against available features when work resumes;
do not add temporary Spaces or derive iCFA now.

The deterministic fixture construction is development-only, separately registered and excluded
from the normal packaged build. Its proof does not satisfy Phase 2's real-assembly gate. Keep
normal incomplete-face and dangling-reference refusals tested throughout development.

## Verification

Use the PRD's canonical-pair failure matrix and active Phase 1 A10 through A16, excluding A15.
Include HTML escaping/privacy, actual references after HBJSON reload, fault injection at each
canonical artifact replacement boundary, and fresh-process native save-dialog and model-lifecycle
checks. METr comparison/import and optional-output failures are deferred. Certification evidence
and a successful energy calculation remain outside this milestone.
