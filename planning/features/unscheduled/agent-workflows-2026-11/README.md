# Agent workflow completeness

DATE: 2026-11-09
STATUS: Scoped, implementation plans drafted. No implementation authorized.
ISSUE: https://github.com/ph-composer/ph-composer-skp/issues/435 (review/planning publication only)
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

The review/planning publication is tracked by #435 and was authorized on 2026-11-10. It changes
only planning material and retained synthetic evidence. No implementation, installation or release
is authorized. Create stage-specific issue-backed intake when implementation is selected. Coordinate
native host use with other work; the Spaces UI packet is now merged and archived, and its changes
must be included in the stage-entry recheck.
