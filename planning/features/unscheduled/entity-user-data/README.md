# Consistent entity user data

DATE: 2026-11-14
STATUS: In progress
AUTHOR: Ed May, BLDGTYP, with Codex
ISSUE: [#507](https://github.com/ph-composer/ph-composer-skp/issues/507)

Make `user_data` a consistent, documented entry point for extending every authored PH-Composer
entity, including nested authored parts. Reuse the existing record and metadata contracts; close
coverage gaps and show users how to attach their own data through public operations.

Read [PRD.md](PRD.md) for scope, the current evidence and acceptance, then [STATUS.md](STATUS.md)
for progress and the next step. [PLAN.md](PLAN.md) holds the inventory, decisions and stages
EUD-01 to EUD-10.

Ed requested this feature packet on 2026-11-14 after a code review found that the core mechanism
already exists but its public access and nested-entity coverage are incomplete. Planning is
authorized. Implementation, merge, native acceptance and release remain separate facts.

The feature is unscheduled. Its scope includes a complete entity inventory, consistent local
read/write/copy/persistence behavior, explicit interchange policies, beginner scripting examples
and contributor guidance. It adds no requirement for a general metadata editor or plugin loader.

Owning contracts: [metadata and extension data](../../../../context/EXTENSIBILITY.md#metadata-and-structured-extension-data),
[record lifecycle](../../../../context/CONTRACTS.md#records-and-extension-data) and
[public API](../../../../context/CONTRACTS.md#public-interface).
