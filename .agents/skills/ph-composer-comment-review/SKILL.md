---
name: ph-composer-comment-review
description: Audit PH-Composer source comments and lint/type suppressions for stale guidance, repeated workarounds, and invariants that code or tests should enforce. Use for a dedicated comment audit or within a code review of an affected diff.
---

# PH-Composer Comment Review

Audit comments and suppressions to remove stale guidance, convert enforceable rules into code or tests, and preserve non-obvious constraints that contributors genuinely need. Review requests authorize findings only; edit only within authorized scope.

## Scope & Authorities

- **Diff review:** Start with the affected diff and trace immediate callers and tests.
- **Repository audit:** Sample tracked source across Ruby, panel JavaScript, Python, tests, and tooling for stale suppressions, repeated workarounds, and opaque references.
- **Authorities:** [Coding standards](../../../context/CODING_STANDARDS.md#comments) (comment policy), [Contributor architecture](../../../context/EXTENSIBILITY.md) (public boundaries), and [Measured SketchUp behavior](../../../context/SKETCHUP_HOST_BEHAVIOR.md) (host constraints).

## Review Procedure

For each candidate comment or suppression:

1. **Trace context:** Read the enclosing behavior, callers, and checks. Search for equivalent code elsewhere. Treat phrases like "for now", "keep in step", and "must not" as leads. For lint/type suppressions, confirm which checker covers the file, what the exception allows, and whether removing it passes the checker.
2. **Pick the smallest improvement:**
   - **Remove or update:** Delete dead commented-out code, narration the code already expresses, or stale claims. When a comment is partly stale, keep the accurate rationale and verify the replacement against the owning contract.
   - **Clarify the code:** Replace explanatory comments with clearer names, explicit SI units, named Ruby values, or simpler control flow while preserving persisted and public shapes.
   - **Enforce the rule:** When callers can violate an invariant, enforce it in the owning API or registration check. Use focused behavioral tests for runtime parity and outcomes, or lint for recurring, mechanically detectable violations.
   - **Keep the rationale:** Retain measured SketchUp/browser quirks, domain assumptions that affect future edits, public contract pointers (keep extended contracts in `context/`), license headers, and runtime directives. Keep plausible constraints until disproven.
3. **Trace workarounds before deleting:** Confirm whether a workaround isolates a real host/platform quirk (keep in a shared adapter with its host-behavior reference) or compensates for our own code (fix the root cause).

## Examples

- **Keep host rationale:** Aborting a transparent SketchUp operation can undo the user's preceding gesture. Keep that rationale beside the restore-and-commit path with its `SKETCHUP_HOST_BEHAVIOR.md` reference; the adapter and its tests enforce the rule.
- **Enforce instead of warning:** A panel comment asking callers not to mutate a shared preference profile should become read-only access at the store boundary plus a test asserting callers cannot mutate it directly.

## Output Format

Lead with findings that affect behavior or contributor decisions. For each, give:

- Path and symbol
- Observed evidence (distinguished from inferred risk) and consequence
- Smallest adequate change and verification check (note exact host check if offline verification is insufficient)

Adapted from [Lauren Tan's talk](https://ai.engineer/code/2026/talks/lauren-tan) and the [pstack `no-comments` review](https://github.com/cursor/plugins/tree/main/pstack/skills/no-comments).
