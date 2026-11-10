# AW-06 · Bounded libraries and discoverable compound copy

STATUS: Proposed, not authorized. ISSUE: https://github.com/ph-composer/ph-composer-skp/issues/435 (review/planning publication only).
DEPENDS ON: AW-02/AW-04. FINDINGS: R08/R15. CONTRACTS: C03/C05. ACCEPTANCE: A08/A15.

## Outcome

An agent can finish catalog review, compare a record, copy and assign atomically, and export the
requested whole library even when source notes or omissions are large.

## Work

1. Separate compact catalog rows, source detail, in-file comparison and warning/unavailable pages.
   Keep source identity/generation and comparison's Model revision binding. Count and expose every
   skipped source row; one large note has an exact retrieval route.
2. Wire AW-02's library descriptors to actual assignment callbacks. Include Material segment, Frame
   side, Glazing element and Psi perimeter/default examples. Correct generation prose without relaxing
   the guard. An adapter with no assignment says so; no built-in names appear in MCP.
3. Make preview's counts/digest/destination compact and page omissions against the same all/selected
   scope. Keep identity-new/update semantics, explicit replacement and changed-destination refusal.
   Preserve state/ID/counts in compact load/export outcomes, and apply AW-04's bounded compound
   action-preview contract to large copy/assign proposals.
4. If selected, return/retain a caller-owned written hash/size/library identity receipt for lost replies.
   This does not grant an arbitrary file read or path disclosure. Otherwise document the current
   destination-state verification and native file handoff precisely.

## Source and tests

`library/{install,catalog,coordinator,export_registration,export_projection,export_workflow,file_writer}.rb`,
connection load/use and kind adapters in Assemblies/Windows. Coordinate existing skipped-row UI work
and hosted provider acceptance; do not reimplement either. Extend library catalog/coordinator/export,
hosted load/copy, kind adapter and external-provider examples.

Required cases: 350 invalid rows plus one valid; one valid 30 KB notes value; 180 metadata omissions
in all-scope replacement; provider generation changes between pages; Model change during comparison;
atomic copy/assign refusal leaves no definition or assignment; all built-in assignment variants and
an outside synthetic kind work from published schema only. Check credentials and private provider
addresses remain absent from every new response.
Also retrieve the preview digest and complete reviewed detail of a large compound copy before apply.

## Native/client gate and done

Use a synthetic file provider and existing synthetic hosted provider; no real credential setup is
required. With panel closed, copy and assign in one native Undo step, read both objects back, and
round-trip the exported library through the existing reader. Refresh/cancel and stale generation
remain truthful. Complete PLAN gates and docs-pass; no new shipped provider or wire kind is implied.
