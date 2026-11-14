# Consistent entity user data: status

DATE: 2026-11-14
STATUS: In progress
AUTHOR: Ed May, BLDGTYP, with Codex
ISSUE: [#507](https://github.com/ph-composer/ph-composer-skp/issues/507)

## State

Ed requested consistent `user_data` support across all entities and clear documentation/context
on 2026-11-14. [PRD.md](PRD.md) records the confirmed scope. On 2026-11-14 Ed asked for the packet
to be implemented through the pr-loop on the existing `codex/entity-user-data` branch, with merge
delegated on green CI once every review comment is answered. The packet had no stage plan, so
[PLAN.md](PLAN.md) and [phases/](phases) now hold the source inventory, the lifecycle policy,
decisions D-UD-1 to D-UD-8 with recommendations, and stages EUD-01 to EUD-10. No code has changed.

Loop overrides: `--single-pr` on the named branch (each stage a signed commit, one Codex review
over the combined diff) and `--merge`.

## Next step

EUD-08, then the stages in order.

| Stage | Status | Evidence |
| --- | --- | --- |
| EUD-01 | Implemented on branch | `ph_composer.records.update_metadata` (API 1.52); catalog `*.update`, installs.save update rows and `attached_zone.save` with `id` no longer take `user_data`. `tests/record_metadata_test.rb` 10 runs, 219 assertions, also on Ruby 2.7.2; `make ci` exit 0: Ruby suite 2,852 runs, 35,188 assertions, 0 failures; JS 876 pass, 0 fail; Python 264 passed; RuboCop 742 files, no offenses; RBZ verified. Sonnet adversarial read: 10 findings, 8 fixed, 2 left as follow-ups (below) |
| EUD-02 | Implemented on branch | `Records::Part` and `RecordKind` `parts:` (validated at registration, part ids unique per parent, part maps JSON-checked, listed by `describe`); optional `user_data` on Assembly Layers and Layer-Segments at schema version 1; `records.update_metadata` takes `part_ids`, and entries for one record and its parts stage as one write (API 1.53). New tests in `record_metadata_test.rb` (14 runs, 312 assertions), `assembly_records_operations_test.rb` (23 runs, 397 assertions) and `registry_test.rb` (41 runs, 290 assertions), also on Ruby 2.7.2; `make ci` exit 0: Ruby suite 2,860 runs, 35,346 assertions, 0 failures; JS 876 pass, 0 fail; Python 264 passed; RuboCop 742 files, no offenses; RBZ verified. Assemblies panel JS checked: it clones stored values and builds no parts, unchanged. Sonnet adversarial read: 8 findings; a stale descriptor test, a vacuous copy-independence check, an untested registration branch, part-id uniqueness (now enforced in core), an unused projected read, the contributor doc and an error message fixed; the export guide now says part maps are not exported yet (EUD-07 maps them); 3 minor notes accepted as designed |
| EUD-03 | Implemented on branch | Optional `user_data` on Window Elements, the Window Type's `elements[]` part, written by `records.update_metadata` with `part_ids` `[element id]` and read by `types.elements.list` (API 1.54); the Type's own element-id uniqueness check removed (core part validation refuses repeats). `types.grid.merge` keeps the top-left map and returns `removed_user_data` (at most 50 entries, each with at most 50 keys, through the new `Records::Metadata.discarded_keys`) and `removed_user_data_total`. New tests in `record_metadata_test.rb` (15 runs, 329 assertions), `window_records_operations_test.rb` (18 runs, 975 assertions: kind change, merge with report and Undo, split, flip, insert, remove, installs save, Duplicate, whole-array update, product replacement, report bounds, repeated ids) and `window_unit_actions_test.rb` (37 runs, 537 assertions: `new_flipped_type`), also on Ruby 2.7.2; `make ci` exit 0: Ruby suite 2,864 runs, 35,467 assertions, 0 failures; JS 876 pass, 0 fail; Python 264 passed; RuboCop 742 files, no offenses; RBZ verified. Windows panel JS checked: it sends grid gestures, installs by element id and named values only, and rebuilds no elements; unchanged. Sonnet adversarial read: 8 findings; the unbounded report list, the band-removal note in the guide, a flip test that could not see a swap, report bound and repeated-id tests, and the export sentence fixed; a panel notice for removed maps, oversized single `elements.list` rows (as EUD-02's `segments.list`) and recomputing the merge selection for the report accepted as designed |
| EUD-04 | Implemented on branch | Building Segment and Level maps written by `records.update_metadata` (API 1.55) with the Zone `choice_evidence` and member-stamp rewrite as a kind-declared follow-up in the same step; merge, remove and manage keep the survivor's map and report the removed keys. `owner_writes_metadata` now only refuses the internal Zone option settings record. Tests: 5 new in `zone_options_test.rb`, 1 new and 1 changed in `record_metadata_test.rb`, 1 new in `registry_test.rb`, also on Ruby 2.7.2. `make ci` exit 0: Ruby suite 2,871 runs, 35,570 assertions, 0 failures; JS 876 pass, 0 fail; Python 264 passed; RuboCop 742 files, no offenses; RBZ verified. Sonnet adversarial read: 9 findings, 4 fixed, 5 risks or nits left as designed |
| EUD-05 | Implemented on branch | Edge rows of `thermal_bridges.edges.selection`, `selection_all`, `at` and `candidates` carry `user_data`, `extension_data` and `extension_status` (non-object maps of an invalid record read as `{}`); new `ph_composer.thermal_bridges.edges.update_metadata` by occurrence (API 1.56), at most 250 entries by the params schema; an invalid assignment with a valid id refuses `validation.failed`, one without has a null `entity_id` the params refuse; `edges.repair` reports `user_data` keys through `Records::Metadata.discarded_keys`, output unchanged. Tests: 4 new and 1 extended in `thermal_bridge_assignment_test.rb` (23 runs, 238 assertions, also on Ruby 2.7.2); `thermal_bridge_repair_test.rb` unchanged and passing (14 runs, 264 assertions); declaration count in `thermal_bridge_types_test.rb`. `make ci` exit 0: Ruby suite 2,875 runs, 35,670 assertions, 0 failures; JS 876 pass, 0 fail; Python 264 passed; RuboCop 742 files, no offenses; RBZ verified. Thermal-bridge panel JS checked: `assign_bar.js` reads `reference`, `values`, `write_refusal`, `record_problem`, `reason` and `path` only; unchanged, so no runtime manifest refresh. Sonnet adversarial read: 7 findings; the schema bound against `gesture.too_large`, a misleading `target.changed` on an invalid record, and missing tests (one Edge under two ids, uninstalled extension payload, legacy record read) fixed; a schema-only null-id refusal relabelled in its test; writing `{}` to a legacy Edge without maps commits a step, as Faces do, and one Edge row larger than a reply comes alone, as EUD-02's rows do, both left as designed |
| EUD-06 | Implemented on branch | New foundation feature `ph_composer.model` (`shell/model_metadata.rb`): `ph_composer.model.detail` reads the `ph_composer.model` ModelSettings dictionary (`user_data`, `extension_data`, absent as `{}` without a write) and `ph_composer.model.update_metadata` writes it under `expected_metadata` through `Records::Metadata.planned`, one step, none for a no-op. Volume records take optional `floor_user_data`, JSON-checked by the kind; Volume rows carry `floor` (`reference` `{floor_id, entity_path}` and `user_data`, a `volumes.list` field, not a default) and leave it out of `values`; `spaces.update_metadata` writes it by that reference under the Volume's write refusals, a Volume and its Floor in one batch as one write (API 1.57). Clearing a map a record never stored now writes nothing in every owner: the rule moved from `Engine#propose_metadata_update` into `Records::Metadata.updated`. Tests: new `model_metadata_test.rb` (5 runs, 52 assertions); 3 new in `spaces_operations_test.rb` (48 runs, 577 assertions); 1 new in `spaces_identity_test.rb` (17 runs, 133 assertions); 1 new in `entity_metadata_test.rb` (14 runs, 219 assertions); all also on Ruby 2.7.2. `make ci` exit 0: Ruby suite 2,885 runs, 35,823 assertions, 0 failures; JS 876 pass, 0 fail; Python 264 passed; RuboCop 744 files, no offenses; RBZ verified. Sonnet adversarial read: 8 findings; a Volume plus Floor batch test, the intermediate Undo state, a raw-text legacy check, `floor` in the `spaces.detail` path list and a named message label fixed; a Floor refusing `extension_payloads` `{}` (as parts do), untested locked and shared Floor refusals (the Volume's `Resolve.writable!`, tested there) and `Engine#propose_update` now leaving an absent map absent, left as designed; the silent export omission is EUD-07's |
| EUD-07 | Implemented on branch | Export carries the Model map to the HB `Model.user_data` through a new foundation section `ph_composer.model.export.model` (`shell/model_metadata.rb`, Python `model_metadata.py`, one record only when the map is not empty) and preflight `ph_composer.model.export_preflight`; a Volume's `floor_user_data` to its `SpaceFloor`; a Layer map to its own material (single EnergyMaterial or hybrid host, which no longer inherits its base cell's map) and a divided Layer's Layer-Segment maps to their cell materials (API 1.58). Material identifiers are `ph_composer_{assembly}_{layer}[_sN/_hybrid]`, Layer ids unique per Assembly, so no two Layers share one HB material; the reversed construction reuses the same objects. `RecordReader#records` now takes every `Records::Part` map out with a finding unless the contributor passes `parts: true` (Window Elements), Attached zones gain a finding, and identical findings are listed once (a Building-Segment named by two Zones, an Edge id on two Edges). Two clarifications of the stage doc: a membrane Layer's map stays local (no HB material), and "divided" means the grid path, so a single Layer-Segment with a steel stud spacing carries its map. Tests: new in `assemblies_export_test.rb` (7 runs, 94 assertions), `spaces_export_test.rb` (14 runs, 94 assertions), `model_metadata_test.rb` (6 runs, 67 assertions), `attached_zone_test.rb` (18 runs, 103 assertions), `export_test.rb` (19 runs, 124 assertions), extended `window_export_test.rb` (28 runs, 400 assertions), all also on Ruby 2.7.2; Python reload tests in `test_constructions.py`, `test_space_sections.py` and `test_model_sections.py` compare maps on `Model.from_dict` of the canonical HBJSON, including the reversed construction. `make runtime-manifest`: Runtime verified, 151 assets, 8 wheels. `make ci` exit 0: Ruby suite 2,891 runs, 35,878 assertions, 0 failures; JS 876 pass, 0 fail; Python 271 passed; RuboCop 744 files, no offenses; RBZ verified, 590 files. Sonnet adversarial read: 9 findings; the membrane rule now reuses `Materials::Schema.membrane_layer?`, Ruby tests added for a reserved key on a carried Layer, for reserved keys in local Window Element and Attached zone maps not blocking and for a Model envelope's finding, the Python refusal test checks its cause, the API note names the extraction changes; a mixed membrane Layer (the Assembly is refused before translation), whole-settings validation (the dictionary holds only the two maps) and the doc on Model envelopes (the record does carry `extension_data`) checked and left as designed |
| EUD-08 | Scoped | |
| EUD-09 | Scoped | |
| EUD-10 | Scoped | |

## Blockers and open decisions

None. Ed answered D-UD-1 to D-UD-8 as recommended on 2026-11-14.

Follow-ups from EUD-01, for EUD-08: `Engine#propose_update` still takes `user_data:` for contributor
kinds, and the foundation example's `update_parts` (`tools/examples/foundation/`) still writes
`user_data` through it; decide whether the example moves to `records.update_metadata`. Invalid JSON
in params reaches no handler over the public API: the dispatcher refuses it as `request.malformed`;
the engine's own `params.invalid` answers only a Ruby caller staging directly.

Follow-up from EUD-05, closed in EUD-06: writing `{}` through an entity owner's `update_metadata` to a
legacy record stored without the maps committed a step that added them, where `records.update_metadata`
wrote nothing. `Records::Metadata.updated` now leaves an absent map absent when it is cleared, so every
owner, the catalog action and the new Model and Space Floor writes treat it as no change.

## Verification

Baseline: clean `main` at `186734ce`. The preceding investigation in this chat passed 276 focused
Ruby tests with 2,665 assertions and 52 Python tests. It covered existing metadata edits, copy
paths, export and library behavior, not universal entity support. No new native host run was made.

The packet's UD-01 through UD-10 acceptance criteria are pending. Documentation-only checks for
this write-up passed: local link/heading validation across all six changed documents and whitespace
checks. The PRD was reviewed against the current owning contracts and known source gaps. The
implementation gates have not run for a new code change.

## Ledger

| Date | Event |
| --- | --- |
| 2026-11-14 | Reviewed the existing affordance and identified public API, nested-entity and interchange boundaries at `186734ce`. |
| 2026-11-14 | Ed confirmed universal entity consistency and documentation as the feature goals; authorized the planning write-up. Created the scoped PRD and linked it from the planning indexes. |
| 2026-11-14 | Created tracking issue [#507](https://github.com/ph-composer/ph-composer-skp/issues/507). Added a current-coverage qualification to the contributor contract; runtime code is unchanged. |
| 2026-11-14 | Ed asked for implementation through the pr-loop on `codex/entity-user-data`, merge on green delegated. Wrote PLAN.md and ten stage documents from a source inventory at `68919a8c`; decisions D-UD-1 to D-UD-8 put to Ed. |
| 2026-11-14 | Ed answered D-UD-1 to D-UD-8 "All as recommended"; implementation authorized. |
| 2026-11-14 | EUD-01 implemented on `codex/entity-user-data`: the core catalog metadata action, `RecordKind` `owner_writes_metadata` for Zone options, and `user_data` removed from catalog updates. |
| 2026-11-14 | EUD-02 implemented on `codex/entity-user-data`: `RecordKind` part declarations, Assembly Layer and Layer-Segment maps, and part addressing in `records.update_metadata`. |
| 2026-11-14 | EUD-03 implemented on `codex/entity-user-data`: Window Element maps as the Window Type's `elements[]` part, and the merge report of removed maps. |
| 2026-11-14 | EUD-04 implemented on `codex/entity-user-data`: Building Segment and Level metadata through the core action, with the Zone evidence rewrite as a follow-up. |
| 2026-11-14 | EUD-05 implemented on `codex/entity-user-data`: Edge rows carry metadata and `thermal_bridges.edges.update_metadata` writes it by occurrence. |
| 2026-11-14 | EUD-06 implemented on `codex/entity-user-data`: the Model's own maps (`ph_composer.model.*`), the Space Floor map on its Volume, and one no-op rule for clearing an absent map. |
| 2026-11-14 | EUD-07 implemented on `codex/entity-user-data`: HBJSON mappings for the Model, Space Floor, Layer and divided Layer-Segment maps, and one `export.metadata_omitted` finding per entity whose map stays local. |
