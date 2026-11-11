# AW-09 · Native coexistence and optional artifact access

STATUS: Complete. Merged to main (#449, `2e7c757c`), API 1.42; host case `AW09` pass; the mid-gesture rows closed by the Move guard (#453, API 1.43) and `AW10G`; A14 deferred, optional. ISSUE: https://github.com/ph-composer/ph-composer-skp/issues/439 (implementation); #435 tracked the review/planning publication.
DEPENDS ON: AW-01/AW-02; AW-07 for task artifacts.
FINDINGS: R13; optional R14. CONTRACT: C08. ACCEPTANCE: A13; A14 if selected.

## Required slice: measure before designing a host guard

In a coordinated throwaway native model, compare reads, ordinary model writes, view/context commands
and export starts while Select is idle, a native drawing/Move gesture is partway through, a custom
PH tool is active, deferred work is pending, a modal is open, another model activates, and a target
model closes. Record whether the call runs, returns busy, times out or changes the native operation.
Inspect Undo/Redo and readback; do not infer safety from tool name or a successful return alone.

Use that evidence to define which operations can run and which must refuse. Add the smallest shared
host-readiness guard required, with owner declarations only where policy actually differs. Never
cancel a user's tool, move focus or leave a queued write to apply after an unknown timeout. Retain
existing main-thread execution, queue bounds, commit-time validation and idempotency rules.

## Optional slices, select independently

- **Artifact bytes:** return bounded caller-owned export/capture content or native MCP image/resource
  content from known receipts. Preserve hashes/provenance, expiry/revocation and path compatibility.
  Test a client without general filesystem access. No caller-supplied path is accepted.
- **Operation history:** expose a bounded session/caller-scoped operation summary with affected refs,
  revisions, outcome/replay identity and incident reference. No payloads, credentials or unrelated
  Models; do not duplicate model persistence or store agent conversations.
- **Overlay capture:** experiment with native rendering support and exact-client image delivery.
  If overlays cannot be captured reliably without disturbing the user, keep geometry-only results
  and record the measured limitation. A failed experiment does not block the required timing slice.

## Source and verification

`session/model_session.rb`, `shell/{dispatch,context_commands}.rb`,
`agent_access/{server,executor,call_log,listener}.rb`, capture command/storage and export tasks.
Use `tools/hostkit/` supported diagnostics/bounded waits and the native acceptance skill. Read machine
host guidance before automation; coordinate with the other host owner. Keep native evidence files
and restoration receipts. Convert observed policy into focused offline regression tests; they do
not replace the native run. Preserve callback/worker-thread boundaries.

Use stronger review for host scheduling or artifact authorization. Required slice closes with an
evidence-backed contract and its implementation, or evidence that existing behavior already meets
it. Optional slices close or defer separately in STATUS. Complete PLAN gates and docs-pass.
