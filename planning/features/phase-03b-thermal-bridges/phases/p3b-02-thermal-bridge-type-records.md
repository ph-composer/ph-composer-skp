# P3b-02: Thermal Bridge Type records and operations

DATE: 2026-10-03
STATUS: Implemented on branch `feature/thermal-bridges-p3b-02`, PR #308; T02 passes (2026-10-25). Corrected to `main` at `420c783a` on 2026-10-21 (DECISIONS Part 1b)
AUTHOR: Ed May, BLDGTYP, with Claude
ISSUE: [#301](https://github.com/ph-composer/ph-composer-skp/issues/301)

## Entry and scope

Requires P3b-01 and D3b-03, D3b-04 and D3b-05, and PRD Q2 and Q9. Owns the feature's folder and
registration and the one catalog record kind, with its operations, panel closed. No Edge, no
screen.

Behavior owner: the [thermal-bridges PRD](../PRD.md), "Records" and "Types tab".
Names: [CONTRACTS](../CONTRACTS.md) sections 1 to 3. Pattern: the Psi-Install
Type and Assembly kinds, `context/TECH_STACK.md`, "A definition record, end to end".

Paths are relative to `src/ph_composer/`.

## Steps

1. **Feature skeleton.** `features/thermal_bridges/install.rb` registers
   `ph_composer.thermal_bridges` with `requires: ["ph_composer.zones"]`; add the `require_relative`
   and the `FEATURES` entry in `extension.rb`, last. `codes.rb` declares the `thermal_bridge`
   noun's codes as each stage needs them, starting with this stage's refusals.
2. **The kind.** `type/schema.rb` builds `Records::RecordKind` `ph_composer.thermal_bridges.type`,
   prefix `tbt`, `schema_version` 1, from `Fields.common` plus `psi_w_mk` (number or null, signed,
   `x-unit` `W/mK`), `group` (enum of the three honeybee-ph strings, default `15-Ambient`) and
   `color` (hex, defaulted from a ramp by id as Assemblies do). Validation is the kind's own; a
   negative psi is valid.
3. **Operations.** `type/operations.rb`: `create`, `update`, `duplicate` and `delete`, each taking
   named arguments beside the request, as `Products::Operations` does. Delete without replacement
   is the engine's guarded delete; the replacement path arrives in P3b-03 when Edges can name a
   type. `duplicate` names the copy and records `source` `derived`.
4. **Declarations.** `declarations/types.rb` registers `types.all`, the `types` snapshot section
   and the four actions with params and results built from `SchemaShapes` and the feature's own
   `Shapes`, hand-written descriptions, Undo names, side effects and `preconditions`, and examples
   that validate; the query declares `response:` where its rows are bounded. `types.all` rows
   carry `export_ready` and `export_blockers` (`thermal_bridge.psi_missing`). Bump `API::MINOR`
   once with one `API::CHANGES` row naming the kind and its operations (CONTRACTS section 3).
5. **Layer test.** A test that nothing under `features/thermal_bridges/type/` references Zones,
   Windows, `Sketchup::Edge` or `runs/`, and that no other feature folder names thermal bridges.
6. **Generated artifacts.** Regenerate `docs/API_REFERENCE.md` and its fixture through
   `make fixtures`. Add the panel-closed walkthrough
   `tools/examples/authoring/thermal_bridge_types_walkthrough.rb`, and a "Thermal Bridge Types"
   recipe to `docs/AGENT_GUIDE.md`, which `tests/agent_guide_test.rb` checks against the registry.

## Source

| PH-Composer file | Disposition |
| --- | --- |
| `features/windows/products/schema.rb`, `products/operations.rb`, `declarations/records.rb` | Pattern for kind, operations and declarations |
| `features/spaces/declarations/operations.rb` | The newest declarations: `preconditions`, `side_effects` and bounded `response:` as the agent-access phase left them |
| `features/assemblies/assembly/schema.rb` | Pattern for the colour ramp |
| `core/records/authoring_fields.rb` | Reuse `Fields.common` unchanged |

## Tests (write first)

1. Schema round trip; an unknown key is unreadable; a wrong `schema_version` is unreadable.
2. `psi_w_mk` accepts -0.02 and null and refuses a string; `group` refuses `Ambient` and accepts
   each of the three stored strings; create defaults `group` and `color`.
3. Update with a stale `expected_values` refuses the whole proposal and writes nothing.
4. Duplicate gives a new id, copies `user_data` independently and sets `source` to `derived`.
5. Delete of an unused type succeeds and Undo restores it with its `user_data` and extension data.
6. `types.all` reports `export_ready: false` with `thermal_bridge.psi_missing` for a null psi.
7. The layer test in step 5.
8. The API reference golden includes every new declaration and the change row; the reference test
   and the agent-guide test pass.

## Host gate

Fresh process: the walkthrough creates three types, edits one, duplicates one and deletes one
through `API.invoke` with the panel closed; Undo and Redo each step natively; save, reopen and read
back the same values through `types.all`. Observe the host with the development tooling: `host_bridge.py wait-for` for deferred work, `host_bridge.py diagnostics` for what happened, `acceptance_case.py begin` and `finish` for the ledger row (`tools/hostkit/.index.md`).

## Out of scope

Any Edge, Zones or Windows code. The Thermal Bridges tab (P3b-05). A library kind (PRD Q8).

## Done when

- T02 has evidence in `../evidence/p3b-02-type-records.md`.
- `make ci` passes on both Rubies; the API reference regenerates with no unrelated diff.
