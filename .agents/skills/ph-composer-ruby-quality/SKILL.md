---
name: ph-composer-ruby-quality
description: Review PH-Composer Ruby for contributor readability during a phase review, or guide an explicitly authorized refactor of one named module. Use for Ruby naming, data shapes, control flow, complexity diagnostics, and responsibility boundaries.
---

# PH-Composer Ruby Quality

Make one Ruby responsibility clearer for an outside contributor to read and safely change. Rules live in `context/CODING_STANDARDS.md` ("Ruby readability and contributor review"); this skill defines the procedure. Resolve paths from the repository root and reuse loaded authorities and current checks.

## Modes

- **Phase review:** Review substantive Ruby diffs and immediate consumers within the phase's coherent-diff review (supply these criteria to the existing reviewer). Read-only unless fixes are already authorized.
- **Dedicated refactor:** Requires explicit authorization naming the target module or slice in the owning plan. Read its receipt, finish one responsibility before widening scope, and limit edits to the smallest supporting changes across callers. Review or planning alone does not authorize a refactor.

## Establish Invariants First

1. Locate the entrypoint, immediate callers, and declared dependencies. Search for shared helpers by behavior as well as name, and check `module_function` callers before moving methods or changing visibility.
2. Trace one normal operation and one meaningful refusal through resolution, validation, proposal, and application.
3. Record invariants before proposing structural changes: public signatures, persisted/returned shapes, IDs and occurrence paths, SI units, `nil`/`false`/missing semantics, metadata preservation, error codes, batch scope, and transaction ownership.
4. Distinguish internal representations from published contracts. Extract a helper or named value only when it reduces what callers must remember; keep clear Ruby idioms and schema tables intact.

## Proportional Diagnostics

Reuse current lint, test, and coverage results. For affected files:

```sh
make lint-ruby RUBOCOP_ARGS=src/ph_composer/features/spaces/authoring.rb
```

For an initial investigation or changed hotspot, run diagnostic complexity cops (not part of normal CI; nonzero exit on default thresholds is diagnostic, not a CI failure or bug count):

```sh
make lint-ruby 'RUBOCOP_ARGS=--only Metrics/AbcSize,Metrics/CyclomaticComplexity,Metrics/PerceivedComplexity src/ph_composer/features/spaces/authoring.rb'
```

Record exact commands, values, and scope. A formula or schema validator can score high while staying readable; do not add threshold overrides or new metric tooling for routine reviews.

## Findings & Refactor Closure

- **Review output:** For each material finding, state source location, the contributor task obstructed, smallest adequate improvement, and affected checks. Separate contract defects, unverified risks, and optional improvements; never invent a correctness bug from a readability concern. Defer out-of-scope findings as follow-ups.
- **Authorized refactor:** Add missing behavioral tests before changing internal representation (test behavior, not helper names or layout). Keep round-trip, reference, fresh-process, and native SketchUp checks where the boundary requires them (Undo/Redo, edit paths, observers, drawing lifecycle).
- **Close out:** Run `make ci` for shipping-code changes and pass the final diff through the existing review ladder once. Update the owning receipt via `docs-pass` with completed responsibility, compatibility preserved, checks/review coverage, deferred host evidence, and how contributor cognitive load was reduced (line count alone is insufficient).
