# P4-02: the Mechanical feature and the Ventilator kind

DATE: 2026-10-21
STATUS: In review on `feat/phase-07-mechanical-p4-02` (2026-11-23); host case owed to MS1. Corrected 2026-11-22 after Phase 6 Programs: composition order, the metadata step. Renamed the same day to `ph_composer.mechanical` (D4-22). See [DECISIONS, Part 4](../DECISIONS.md#part-4-review-after-programs-2026-11-22).
AUTHOR: Ed May, BLDGTYP, with Claude
ISSUE: #562

## Entry and scope

Requires P4-01, D4-02, D4-05, D4-20 and D4-22, and the Ventilators interview (V1 to V6). CONTRACTS section 2 binds the Ventilator's `manufacturer` and `model` fields (D4-20). Owns the feature's folder and registration and the first family kind, with its operations and reads, panel closed. No Zone, no Serves, no screen.

Behavior owner: the [equipment PRD](../equipment/PRD.md), "The shared shape" and "Family 1".
Names: [CONTRACTS](../CONTRACTS.md) sections 1 to 3. Pattern: the Window product kinds and the
Assembly kind, `context/TECH_STACK.md`, "A definition record, end to end".

Paths are relative to `src/ph_composer/`.

## Steps

1. **Feature skeleton.** `features/mechanical/install.rb` registers `ph_composer.mechanical`
   (module `Mechanical`) with `requires: ["ph_composer.zones", "ph_composer.spaces"]`; P4-05 adds
   `ph_composer.programs` and P4-08 `ph_composer.climate`; add the `require_relative` and the
   `FEATURES` entry in `extension.rb`, last, after `Programs` (F22). `codes.rb` declares the `mechanical`
   noun's codes as each stage needs them, starting with this stage's refusals.
2. **The kind.** `ventilators/schema.rb` builds `Records::RecordKind`
   `ph_composer.mechanical.ventilator`, prefix `vnt`, `schema_version` 1, from `Fields.common` plus
   the fields CONTRACTS section 2 lists with their defaults and `x-unit`s. The two optional fields
   are absent by default and nullable (V3). No `sys_type`, no rated flow (V2, V6).
3. **Operations.** `ventilators/operations.rb`: `create`, `update`, `duplicate` and `delete`, each
   taking named arguments beside the request, as `Products::Operations` does. Delete without a
   replacement is the engine's guarded delete; the replacement and clear paths (D4-05) arrive in
   P4-03 when a Serves payload can name a Ventilator. `duplicate` names the copy and records
   `source` `derived`.
4. **Declarations.** `declarations/ventilators.rb` registers `ventilators.all`, the `ventilators`
   snapshot section and the four actions with params and results from `SchemaShapes` and the
   feature's own `Shapes`, hand-written descriptions, Undo names, side effects and
   `preconditions`, and examples that validate; the query declares `response:`. Rows carry
   `export_ready` and `export_blockers` (none for a Ventilator alone; the shape is for later
   families). Bump `API::MINOR` once with one `API::CHANGES` row.
5. **Layer test.** A test that nothing under `features/mechanical/ventilators/` references Zones,
   Spaces, Programs, the Zone record, `serves/` or `Sketchup::`, and that no other feature folder names
   this feature.
6. **Metadata (F36).** The Ventilator keeps a `user_data` map through the engine, its reads
   carry `extension_data` and `extension_status`, `ph_composer.records.update_metadata` is its
   one write route, and `docs/USER_DATA.md` gains its row, stating that the map leaves on the
   `Ventilator` object or stays in the Model with `export.metadata_omitted` (P4-04 decides which).
7. **Generated artifacts.** Regenerate `docs/API_REFERENCE.md` and its fixture through
   `make fixtures`. Add the panel-closed walkthrough
   `tools/examples/authoring/ventilators_walkthrough.rb`, and a "Mechanical: Ventilators" recipe
   to `docs/AGENT_GUIDE.md`.

## Source

| PH-Composer file | Disposition |
| --- | --- |
| `features/windows/products/schema.rb`, `products/operations.rb`, `declarations/records.rb` | Pattern for kind, operations and declarations |
| `features/spaces/declarations/operations.rb` | The newest declarations: `preconditions`, `side_effects`, bounded `response:` |
| `core/records/authoring_fields.rb` | Reuse `Fields.common` unchanged |
| `features/programs/install.rb` | The sibling registered just before this one |

## Tests (write first)

1. Schema round trip; an unknown key is unreadable; a wrong `schema_version` is unreadable.
2. Defaults on create: quantity 1, 0.55 Wh/m³, frost protection true, -5 °C, in conditioned space
   true, both optional fields absent.
3. A recovery fraction of 1.2 refuses; a negative electric efficiency refuses; `quantity` 0 refuses.
4. Update with a stale `expected_values` refuses the whole proposal and writes nothing.
5. Duplicate gives a new id, copies `user_data` independently and sets `source` to `derived`.
6. Delete of an unused Ventilator succeeds and Undo restores it with its metadata.
7. The layer test in step 5.
8. The API reference golden includes every new declaration and the change row; the reference test
   and the agent-guide test pass.

## Host gate

Fresh process: the walkthrough creates two Ventilators, edits one, duplicates one and deletes
one through `API.invoke` with the panel closed; Undo and Redo each step natively; save, reopen and
read back the same values through `ventilators.all`. Observe with the development tooling and
record the case with `acceptance_case.py`.

## Out of scope

Serves, Zones, the balance (P4-03, P4-05). Export (P4-04). The Systems tab (P4-05).

## Done when

- M02 has evidence in `../evidence/p4-02-ventilator-kind.md`.
- `make ci` passes on both Rubies; the API reference regenerates with no unrelated diff.
