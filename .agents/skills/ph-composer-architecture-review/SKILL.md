---
name: ph-composer-architecture-review
description: Assess PH-Composer architecture plans and code changes against its contributor extensibility and readability standards. Use before designing contribution boundaries and within the existing implementation review; complements the UI polish skill.
---

# PH-Composer architecture review

Assess whether a contributor can understand and extend the affected capability without learning
the whole application. Apply this rubric during design and the existing coherent-diff review.
Review alone does not authorize implementation, refactoring, commits or publication.

## Authorities and scope

Resolve paths from the repository root. Read `context/EXTENSIBILITY.md` and
`context/CODING_STANDARDS.md`; use only the relevant sections of `context/TECH_STACK.md` and the
owning plan. Read `context/UBIQUITOUS_LANGUAGE.md` for disputed domain names. For public queries,
actions, host access or external adapters, also read `context/AGENT_INTERFACE.md`. For Building Segment
settings, Programs or a feature's export contributor, read the matching sections of `context/CONTRACTS.md`
("Programs, Schedules and Equipment Sets", "Occupancy", "Program export", "Building Segments at export").
Reuse already-read
authorities and verified checks while they remain current. These documents own the rules; do not
copy them into another checklist or treat an unimplemented contract as an existing API.

Establish the requested plan or diff, affected contracts, dirty-work ownership and available
verification evidence. Bound the review to that scope. Record significant unrelated findings as
follow-ups rather than expanding the task.

## During design

Identify the contribution contract and owner for the proposed behavior. Trace one concrete
contributor task: which files must change, which public operations it uses, and what a newcomer
must learn. Compare alternatives only where they change those costs or introduce compatibility
tradeoffs. Recommend the simplest design that meets the accepted behavior and host constraints.

State unresolved API choices explicitly. Do not invent a plugin framework, dynamic loader or
independent distribution requirement to satisfy a hypothetical future contributor. A design
review produces recommendations and acceptance checks, not implementation unless authorized.

## During code review

Trace a representative operation through the actual code, including relevant failure paths.
Select the applicable questions; do not demand evidence for capabilities outside the change.

For substantive Ruby scope, include `.agents/skills/ph-composer-ruby-quality/SKILL.md` in this review.
It applies the Ruby criteria in `context/CODING_STANDARDS.md`; it does not add a second reviewer.

- Can built-in and outside features use the same public contract? Does adding one require a
  special branch in shell, session, export orchestration or the UI kit? A composition-root entry
  or generated inventory is permitted. Check explicit dependencies and registration diagnostics.
- Is pure domain behavior separate from SketchUp access? Are reads free of mutation and UI side
  effects? Do scripts and UI use the same validated operations and transaction ownership?
- Are record identity, occurrence paths, references and SI units apparent? Do names match the
  domain? Explain where a vague name or abstraction forces the reader to infer missing meaning.
- Where persistence changes, trace `user_data` and structured extension payloads through edits,
  supported round trips and unavailable-extension handling. Check actual references and version
  behavior. Preservation does not imply validation or permission to export arbitrary metadata.
- Do importers propose changes through normal operations? Do exporters consume HBJSON alone?
  Does feature data enter translation through a declared contributor contract?
- Does every ending, refusal and cancellation the owning PRD names have a test? Check the PRD's
  list itself, not only the plan's test list, which can be narrower; gestures especially (lost
  release, another button, blur, disposal).
- Can a newcomer find a public entrypoint, its contract and a small working example? Are required
  tests proportional to the changed boundary? Use runtime, compatibility and host evidence where
  the owning gate requires them.
- Does the abstraction reduce what a reader must know? Are side effects and failures explicit?
  Treat length and complexity as evidence; never recommend mechanical fragmentation just to
  reduce a number. Performance arguments need measurements when used to justify complexity.
- For agent-access changes, trace discovery, focused read, write and read-back with the panel
  closed. Check explicit model/session targeting, stale-state refusal, retry outcomes, grants and
  host scheduling. Distinguish supported operations from development eval. Feature registration
  must not require adapter-specific business logic. Check visual context and long-task contracts
  only when affected; do not require an unimplemented external adapter for unrelated feature work.

## Fit the existing implementation workflow

`implement` and `implement-loop` read repository instructions. `AGENTS.md` routes them here at
design time and for their existing final review. Do not fork or modify those shared skills.

Use the repository's review ladder. For a routine change, supply this rubric to its one bounded
reviewer; for an architectural or high-risk change, supply it to the stronger independent review
instead. Trivial edits can be reviewed locally. Include existing lint, test, coverage and
complexity results when available; report missing measurements without inventing tooling or
rerunning unchanged passing gates. This skill adds criteria, not another mandatory reviewer.

For UI changes, apply the UI polish skill to the visible behavior and this rubric to code
boundaries in the same review where practical. Keep the required native-host acceptance.

## Findings and completion

Lead with actionable findings, ordered by consequence. Each finding names:

- The source location or plan section and governing context rule.
- The observed behavior and concrete contributor or correctness consequence.
- The smallest adequate correction and relevant verification.

Distinguish a reproduced defect, a directly evidenced contract violation, an unverified risk and
an optional improvement. Aesthetic preferences are not blockers. Missing required host evidence
is an outstanding gate, not proof of a code defect. Do not label a data-loss hypothesis confirmed
without tracing the write or demonstrating the round trip.

If there are no actionable findings, say so and state the reviewed scope and material limitations.
When implementing, fix in-scope findings under existing authorization and recheck affected paths.
Record the review outcome and unresolved gates in the owning packet through the normal docs pass.
Do not claim extensibility verified until the relevant example and acceptance evidence exist.
