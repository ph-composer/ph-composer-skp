# AW-02 · Complete discovery and installed guidance

STATUS: Implemented on branch `feat/agent-workflows-aw-02` (API 1.35); review and host/MCP gate in STATUS. ISSUE: https://github.com/ph-composer/ph-composer-skp/issues/439 (implementation); #435 tracked the review/planning publication.
DEPENDS ON: authorization; can precede target fixes without claiming safe writes.
FINDINGS: R05, R12, R15 descriptor portion. CONTRACTS: C02/C03. ACCEPTANCE: A05/A12/A15.

## Outcome

A fresh client learns every installed data kind, reference target, extension and supported compound
assignment from the connection itself. It can retrieve a concise operating recipe without a checkout.

## Work

1. Add additive bounded discovery sections/cursors while keeping the compact operation index and
   existing owner query. Publish record/reference catalogs, common refusal sets/documentation,
   task/contract metadata and installed extension descriptors. Bind cursors to registry identity.
2. Describe each reachable descriptor from registration. Define library adapter descriptors with
   wire/record kind/version and optional assignment target schemas/examples; do not enumerate built-in
   kinds in transport. Publish unavailable/unsupported states explicitly.
3. Choose D04's topic-read route unless actual-client evidence supports resources equally well.
   Package the guide with the build and expose version/topic pointers from initialize/discovery.
   Keep payloads small and immutable; do not turn model text into instructions.
4. Reconcile `docs/AGENT_ACCESS.md`, `AGENT_GUIDE.md`, `docs/.index.md` and the current/proposed sections
   of `context/AGENT_INTERFACE.md`. Correct host_extent availability, file receipts, model identity
   selection, generation requirements and metadata export wording. Preserve historical receipts.

## Source and tests

`src/ph_composer/shell/api.rb`, `agent_access/{tools,mcp,executor}.rb`, registry descriptors,
`library/install.rb`, library adapter declarations, `tools/api_reference/` and guide tests. Extend
`api_reference_test`, `agent_access_server_test`, `agent_guide_test`, library registration tests and
the outside synthetic feature/provider examples. Prove every catalog entry has a reachable descriptor;
all page envelopes fit after adding many synthetic features; common codes resolve; new adapters
require no transport changes. Preserve token-filtered sessions and capture-only tool availability.

## Client gate and done

Both selected independent clients start without repository instructions, discover the guide and a
synthetic new kind, describe it and perform a focused read. Record exact client versions and all
setup prerequisites. Do not declare complete future-feature authoring from discovery alone. Run PLAN
gates, generated reference/manifest checks and docs-pass; record the new API minor and evidence.
