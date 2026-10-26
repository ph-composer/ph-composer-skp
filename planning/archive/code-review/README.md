# Code and architecture review

DATE: 2026-10-13
STATUS: Complete and archived 2026-10-14. All 17 findings resolved by the refactoring program (PRs 99 to 126, archived at [code-review-refactoring](../code-review-refactoring/README.md)); F06's remaining geometry stages G-01, G-03 and G-04 continue in [archive/geometry-contribution-contracts](../geometry-contribution-contracts/STATUS.md), scheduled by phase 3b.
ISSUE: none (local review requested by Ed)
BASELINE: `main` at `cfe01a6aad99a0e09d5ecf0de5659c606d7ba4f9`

PH-Composer has a sound modular foundation, with explicit registration, validated public operations,
Model-owned data and useful contributor seams. It implements much of the intended dependency
direction. It is not yet a fully portable onion platform: common modules mix pure rules and host
adapters, some Windows definition operations know placement internals, and geometry-backed custom
data lacks the public write/status/export capabilities already available to catalog records.

This review records **17 findings**, including two optional structural/maintenance improvements.
The most consequential work is to make contributor registration and composition reliable, complete
entity customization, and remove duplicated Ruby/JavaScript domain ownership. The architecture
does not need a wholesale replacement or speculative plugin loader.

## Read in this order

1. [Architecture atlas](ARCHITECTURE.md): eight diagrams covering the system, dependencies, edit/Undo,
   snapshots, library copy, export, identity/custom data and the proposed boundary refinement.
2. [Findings register](FINDINGS.md): classified findings, priorities and important qualifications.
3. Section reviews: [01 foundation](sections/01-foundation.md), [02 shell and sessions](sections/02-shell-session.md),
   [03 shared services](sections/03-services.md), [04 Ruby features](sections/04-ruby-features.md),
   [05 JavaScript](sections/05-javascript.md), [06 export](sections/06-export.md).
4. [Contributor workflows and candidate workstreams](sections/07-contributor-workflows.md): what a
   contributor must change today and the recommended refactoring design order.
5. [Evidence](evidence/README.md): commands, baseline checks, reproducible synthetic probes and limits.
6. [Windows boundary discussion](WINDOWS_BOUNDARY.md): why placement needs context, which native
   policies were deliberate, and how definitions can remain independent. Corrects RF-02's discovery claim.
7. [Refactoring plans](../code-review-refactoring/README.md): twelve logical packets cover all findings, with rationale,
   dependencies, implementation stages and acceptance matrices. The [Zone-child pattern](../code-review-refactoring/ZONE_CHILD_PATTERN.md)
   records Ed's accepted direction for Windows, Spaces and future entities. Planning only.

The diagrams use Mermaid so their source remains reviewable and maintainable alongside code.
The section diagrams trace additional feature-level relationships and UI state transitions.
Two [rendered PNG reading aids](ARCHITECTURE.md) show dependencies and data flow without a Mermaid renderer.

## Method and scope

The review began with the current branch, clean working tree, planning status and canonical
EXTENSIBILITY/CODING_STANDARDS/CONTRACTS authorities. It used the repository architecture-review
rubric and UI-polish guidance. Two bounded reviewers handled Ruby built-ins and JavaScript; the
main review inspected common foundation, shell/session, service and export boundaries, validated
their material claims against source, and ran retained reproductions.

Each section was inventoried and dependency-scanned, then representative operations were traced
through successful preparation, failure/refusal, apply, read-back and lifecycle paths. This is a
methodical architecture review, not a claim that every line of every geometry algorithm was
independently proved. Python/runtime composition was inspected to assess the Ruby/JS handoff;
Python domain algorithms did not receive a separate exhaustive review.

The central acceptance questions were:

- Does a contributor use the same contracts as built-ins without feature branches in orchestration?
- Do domain rules point toward explicit values, with native IO and UI at visible boundaries?
- Can a firm's automation update and read custom data without private stores, including failure cases?
- Are copy/reference/Undo and export ownership preserved across the supported seams?
- Can a newcomer trace a complete working example and its disposal/refusal paths?

Findings distinguish reproduced defects, direct contract mismatches, planned capability gaps and
optional improvements. Test coverage and line counts are evidence aids, not proof of extensibility.
The early-development instruction permits future breaking changes; existing decisions and host
invariants still need explicit treatment in those plans.

## Verification

`make test` passed on Ruby 3.2.2: **1,490 Ruby tests / 18,315 assertions**, **508 JavaScript tests**,
and **195 Python tests**, with no failures. The panel manifest was current: 78 modules / two pages.
Configured Ruby size metrics reported zero offenses; cyclomatic/branch complexity and fresh
coverage were not measured. The retained review probes reproduce the documented uncovered cases:
six foundation scenarios, two feature scenarios and four JavaScript checks.

No shipping source, existing tests, examples or runtime assets changed. This packet and its row in
the planning index are documentation. No implementation, commit, PR, deployment, native-host
acceptance or release claim is included. `make ci` was not required for these documentation-only
changes and was not run. Existing SketchUp 2023, Windows, exporter and release gates remain as
recorded by their owning packets.
