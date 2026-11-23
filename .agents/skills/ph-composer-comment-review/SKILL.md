---
name: ph-composer-comment-review
description: Audit PH-Composer source comments and suppressions for stale guidance, repeated workarounds, and rules that can be enforced in code. Use for a comment audit or in the existing review of an affected diff.
---

# PH-Composer comment review

Use comments to find places where contributors must remember a rule the code could enforce. Keep
the context a contributor needs to use a published contract or understand an external constraint.

## Scope

Use the requested files, feature or diff. For a change review, start with the affected diff and
trace immediate callers and tests. For a repository audit, screen tracked source and sample
candidates across Ruby, panel JavaScript and Python, including relevant tests and tooling. Look
for suppressions from retired tools and opaque references that citation lint may miss. Report the
scope and depth. Fold the findings into the existing review. A review request authorizes findings.
Make edits only within the caller's authorized change scope.

Use [Coding standards](../../../context/CODING_STANDARDS.md#comments) for the comment policy.
Check [Contributor architecture](../../../context/EXTENSIBILITY.md) for public boundaries and
[Measured SketchUp behavior](../../../context/SKETCHUP_HOST_BEHAVIOR.md) for host constraints.

## Review a candidate

1. Read the enclosing behavior, its callers and the relevant checks. Search for equivalent code
   elsewhere. Treat phrases such as “for now,” “keep in step” and “must not” as leads. For a lint
   or type suppression, identify the active checker and confirm it covers the file. Check what
   the exception permits and run that checker on the affected scope after removal.
2. Choose the smallest change that improves the next contributor's task.

   - **Remove or update** stale guidance, dead code in comments, or narration the code already
     conveys. When part of a comment has gone stale, keep the accurate guidance and change the
     stale claim. Verify any replacement claim against the owning code or contract, including
     alternate modes and the reason for a dependency. Check nearby examples for the same pattern.
   - **Clarify the code** when a name, explicit unit, named Ruby value, or simpler control flow
     can carry the meaning. Preserve persisted and public shapes.
   - **Enforce the rule** when callers can violate an important invariant. Prefer the owning API
     or registration check when it can prevent the mistake. Use a focused behavioral test for
     outcomes and parity across runtimes. Use lint for a recurring, mechanically identifiable
     violation with a clear supported path and an actionable diagnostic.
   - **Keep the rationale** for measured SketchUp or browser behavior, domain assumptions that
     matter to the next edit, and public contracts. Keep license headers and runtime directives.
     Put extended contracts in their owning `context/` document, with a short nearby pointer
     where the code needs it. Preserve a plausible constraint while its evidence is unresolved.

3. For a workaround, trace the reason it exists and the paths that depend on it before proposing
   deletion. A shared adapter can contain a real platform quirk. When the cause is in our own
   code, propose the smallest fix that removes the need for the workaround. Check the negative
   path and the affected host behavior before dropping the rationale for a rule.

Aborting a transparent operation can undo the user's preceding SketchUp gesture. Keep that reason
near the restore-and-commit path, with the measured host reference. The adapter and its tests
carry the operational rule. A panel comment asking callers to leave a mutable preference profile
alone calls for a different response. Trace the readers and consider read-only access at the store
boundary and a test that a consumer cannot change the profile without a preference update.

Lead with findings that affect behavior or contributor decisions. Report each with its path and
symbol, evidence, consequence, and the smallest adequate change and check. Distinguish observed
behavior from inferred effects. For an authorized pilot, prioritize a reproducible failure when
verification fits the scope. If it needs separate host evidence, record the reproduction and
the exact host check still needed.
Use the affected repository gates. Judge the review by the stale guidance removed, real
constraints preserved and failure modes made harder to repeat.

Adapted from [Lauren Tan's talk](https://ai.engineer/code/2026/talks/lauren-tan) and the
[pstack `no-comments` review](https://github.com/cursor/plugins/tree/main/pstack/skills/no-comments).
