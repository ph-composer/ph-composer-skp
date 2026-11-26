---
name: ph-composer-architecture-review
description: Assess PH-Composer architecture plans, contribution boundaries, and code diffs against contributor extensibility and coding standards. Use during design review and coherent-diff code review; pairs with ph-composer-ruby-quality for Ruby scope and ph-composer-ui-polish for HtmlDialog screens.
---

# PH-Composer Architecture Review

Evaluate whether a contributor can understand and extend the affected capability without learning the whole application. Review alone does not authorize implementation, refactoring, commits, or publication.

## Authorities and Scope

Resolve paths from the repository root and reuse already-read authorities and current checks.

- Always consult `context/EXTENSIBILITY.md` and `context/CODING_STANDARDS.md`.
- Consult as relevant: `context/TECH_STACK.md`, `context/UBIQUITOUS_LANGUAGE.md` (domain terms), `context/AGENT_INTERFACE.md` (public queries, actions, host access, or adapters), the affected feature's section in `context/CONTRACTS.md`, and the owning plan.
- For substantive Ruby scope, include `.agents/skills/ph-composer-ruby-quality/SKILL.md` in the same review. For UI scope, pair with `.agents/skills/ph-composer-ui-polish/SKILL.md` for visible behavior.
- Bound the review to the requested plan or diff, affected contracts, and available verification evidence. Record unrelated issues as follow-ups.

## Design Review

1. Identify the contribution contract and owner for the proposed behavior.
2. Trace one concrete contributor task: files changed, public operations used, and what a newcomer must learn.
3. Compare alternatives only where they change contributor cost or compatibility tradeoffs. Recommend the simplest design that satisfies accepted behavior and host constraints.
4. State unresolved API choices explicitly. Do not invent a plugin framework, dynamic loader, or separate distribution layer for hypothetical future contributors.

## Code Review Rubric

Trace one representative operation through the actual code, including failure paths. Apply only the questions relevant to the diff:

- **Contribution boundary:** Can built-in and outside features use the same public contract without special branches in shell, session, export orchestration, or the UI kit? (A composition-root entry or generated inventory is fine.) Check explicit dependencies and registration diagnostics.
- **Separation of concerns:** Is pure domain logic isolated from SketchUp API calls? Are reads free of mutation and UI side effects? Do scripts and UI share the same validated operations and transaction ownership?
- **Domain clarity:** Are record identity, occurrence paths, references, and SI units explicit? Do names match `context/UBIQUITOUS_LANGUAGE.md`?
- **Persistence:** For storage changes, trace `user_data` and structured extension payloads across edits, supported round trips, and unavailable-extension handling. Preservation does not imply validation or permission to export arbitrary metadata.
- **Import / export:** Do importers propose changes through normal operations? Do exporters consume HBJSON alone? Does feature data enter translation through a declared contributor contract?
- **Edge-case coverage:** Does every ending, refusal, and cancellation named in the owning PRD have a test (especially gestures: lost release, secondary button, blur, disposal)? Check the PRD directly, not only the narrower plan test list.
- **Discoverability & proportionality:** Can a newcomer locate the public entrypoint, its contract, and a working example? Are abstractions earning their complexity? Treat length and complexity as evidence, not targets for mechanical splitting; require measurements before accepting complexity for performance.
- **Agent access (when affected):** Trace discovery, focused read, write, and read-back with the panel closed. Check explicit model/session targeting, stale-state refusal, retry outcomes, grants, and host scheduling. Keep supported operations distinct from development eval, and avoid adapter-specific business logic in feature registration.

## Output Format

Lead with actionable findings ordered by consequence. For each finding, state:

1. **Location & rule:** Source path/symbol or plan section and the governing context rule.
2. **Evidence & consequence:** Observed behavior and its concrete contributor or correctness impact.
3. **Correction & check:** Smallest adequate fix and proportional verification.

Classify each item as a reproduced defect, evidenced contract violation, unverified risk, or optional improvement. Missing required host evidence is an open gate, not proof of a code defect; never call a data-loss hypothesis confirmed without tracing the write or round trip.

If there are no actionable findings, state that along with the reviewed scope and material limitations. Record review outcomes and unresolved gates in the owning packet via `docs-pass`.
