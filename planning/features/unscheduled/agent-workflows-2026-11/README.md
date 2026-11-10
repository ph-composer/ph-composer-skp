# Agent workflow completeness

DATE: 2026-11-09
STATUS: In progress. Implementation authorized 2026-11-10; AW-01 merged (#440); AW-02 implemented on branch.
ISSUE: https://github.com/ph-composer/ph-composer-skp/issues/439 (implementation); #435 tracked the review/planning publication
BASELINE: `f65ccee62b0a3994a46001d55f7aefd1a69f0faf`, API 1.31.

This packet turns the [comprehensive review](../../../code-review/agent-workflows-2026-11/README.md)
into ten implementation stages. It completes the existing application interface so agents can
discover targets, inspect complete data, make safe edits and verify results through the installed
connection. It adds no built-in agent, model-provider dependency or general Ruby evaluation endpoint.

- [Plan and dependencies](PLAN.md)
- [Proposed contracts](CONTRACTS.md)
- [Decisions and scope choices](DECISIONS.md)
- [Acceptance cases](ACCEPTANCE.md)
- [Single delivery ledger](STATUS.md)

For handoff, authorize a stage by ID and give its coding agent the stage document plus AGENTS.md,
this packet's contracts/acceptance and the linked finding/probe. The agent must check the latest
merged source before implementing a baseline finding. A proposed plan is not evidence that the
feature exists or that its implementation has permission.

The review/planning publication was tracked by #435 (closed). Ed authorized implementation of all ten
stages on 2026-11-10, tracked by #439: one branch and PR per stage through the pr-loop, Codex review,
merge on green delegated, computer use authorized. Installation, release and public distribution remain
unauthorized. The Spaces UI packet is merged and archived; its changes are part of each stage-entry recheck.
