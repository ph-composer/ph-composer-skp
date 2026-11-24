# P4-02 evidence: the Mechanical feature and the Ventilator kind

DATE: 2026-11-23
Register row: [M02](../ACCEPTANCE.md). Stage: [P4-02](../phases/p4-02-equipment-feature-and-ventilator-kind.md).
Base: `feat/phase-07-mechanical-p4-01` at `dd8a3ad7`; after #564 merged as `73936d2a` (identical tree), rebased onto
`main`. Branch `feat/phase-07-mechanical-p4-02`.

Offline evidence only. No SketchUp process was started. The host case `M02` (fresh process, the walkthrough through
`API.invoke` with the panel closed, native Undo and Redo of each step, save, reopen and read-back) is owed to the MS1
sitting (D4-31); nothing here is host evidence.

## What was built

| Step | Where | Note |
| --- | --- | --- |
| 1. Feature skeleton | `src/ph_composer/features/mechanical/install.rb`; `extension.rb` | `ph_composer.mechanical`, module `Mechanical`, requires `ph_composer.zones` and `ph_composer.spaces`; `FEATURES` ends `..., Programs, Mechanical]`. No `codes.rb`: every refusal this stage raises is a foundation code (below), so the `mechanical` noun's file arrives with `mechanical.slot_filled` in P4-03 |
| 2. The kind | `ventilators/schema.rb` | `ph_composer.mechanical.ventilator`, `vnt_`, `schema_version` 1, `Fields.common` plus the CONTRACTS section 2 fields with their defaults and `x-unit`s (`Wh/m3`, `C`; `fraction` on the three 0 to 1 fields, recorded in CONTRACTS); the two optional fields absent by default and nullable; no `sys_type`, no rated flow |
| 3. Operations | `ventilators/operations.rb` | `create`, `update`, `duplicate`, `delete` with named arguments; names unique; `duplicate` names the copy and sets `source` `derived`; delete is the engine's guarded delete |
| 4. Declarations | `declarations/shapes.rb`, `declarations/ventilators.rb`, `ventilators/reads.rb` | `ventilators.all` (`response:` unbounded, preferring `ventilators.list`), the snapshot section `ph_composer.mechanical.ventilators`, the four actions with Undo names, side effects and preconditions; rows carry `export_ready` and `export_blockers` (empty). API 1.87, one `API::CHANGES` row |
| 5. Layer test | `tests/mechanical_dependency_test.rb` | No family folder (every folder but `serves/` and `declarations/`) names Zones, Spaces, Programs, the Zone record, `serves/` or `Sketchup::`; no other feature names Mechanical; the pattern's positive controls are asserted |
| 6. Metadata | engine; `docs/USER_DATA.md` | Reads carry `user_data`, `extension_data`, `extension_status`; `ph_composer.records.update_metadata` writes them; the USER_DATA row says the map stays in the Model until the Ventilator export decides |
| 7. Generated artifacts | `docs/API_REFERENCE.md`, `src/ph_composer/agent_access/guide.md` (`make fixtures`); `tools/examples/authoring/ventilators_walkthrough.rb`; `docs/AGENT_GUIDE.md` "Mechanical: Ventilators" | The API reference diff is additions only (`git diff --diff-algorithm=histogram --stat`: 2,212 insertions, 0 deletions) |

Departure: `ventilators.list` is not in the stage doc. The registry refuses an `all` read whose `response:` does not
name a registered bounded query (`shell/registry_validation.rb`, `check_responses`), and the stage doc asks for
`response:`; CONTRACTS section 3 gains the row in this change.

Refusals observed through `API.invoke` (a scratch probe, not committed): a recovery fraction of 1.2 or a `quantity`
of 0 refuses `params.invalid` at the params schema ("Nothing was written."); a stale `expected_values` refuses
`target.changed` with effect `none`; an unknown id refuses `target.not_found` on update, duplicate and delete; a
blank name and a null required value refuse `validation.failed`.

## Tests (Ruby 3.2.2, focused)

```
$(rbenv prefix 3.2.2)/bin/ruby -Itests tests/mechanical_ventilators_test.rb
10 runs, 133 assertions, 0 failures, 0 errors, 0 skips
$(rbenv prefix 3.2.2)/bin/ruby -Itests tests/mechanical_dependency_test.rb
3 runs, 27 assertions, 0 failures, 0 errors, 0 skips
$(rbenv prefix 3.2.2)/bin/ruby -Itests tests/ventilators_walkthrough_test.rb
1 runs, 10 assertions, 0 failures, 0 errors, 0 skips
make fixtures
137 runs, 9582 assertions, 0 failures, 0 errors, 0 skips
```

| Stage doc test | Test |
| --- | --- |
| 1. Round trip; unknown key and wrong `schema_version` unreadable | `test_a_ventilator_round_trips_and_an_unknown_key_or_another_version_is_unreadable` |
| 2. Defaults, both optional fields absent | `test_a_new_ventilator_takes_the_defaults_and_leaves_both_optional_fields_absent`, `test_an_optional_value_is_set_and_a_null_removes_it_but_a_null_required_value_refuses` |
| 3. Recovery 1.2, negative efficiency, quantity 0 refuse | `test_out_of_range_values_refuse_and_write_nothing` (create and update; revision unchanged) |
| 4. Stale `expected_values` refuses whole, writes nothing | `test_a_stale_expected_value_refuses_the_whole_edit_and_writes_nothing` (update and delete) |
| 5. Duplicate: new id, independent `user_data`, `derived` | `test_duplicate_gives_a_new_id_an_independent_user_data_copy_and_a_derived_source` |
| 6. Delete unused; Undo restores it with its metadata | `test_deleting_an_unused_ventilator_is_one_undo_step_that_restores_its_metadata` (`user_data` and a third party's extension payload) |
| 7. Layer test | `tests/mechanical_dependency_test.rb`. Mutation check: a `Sketchup::Model` line appended to `ventilators/reads.rb` fails it (`Expected ["mechanical/ventilators/reads.rb"] to be empty`); the line was removed |
| 8. API reference golden, reference and guide tests | `make fixtures`; `tests/api_reference_test.rb` 8 runs and `tests/agent_guide_test.rb` 5 runs, 0 failures |
| M02: `user_data` and extension payloads through edit, Duplicate, Undo/Redo and reopen | `test_metadata_and_extension_payloads_survive_edit_duplicate_undo_redo_and_reopen` (the metadata write, the edit and the duplicate each undone and redone; reread through `ventilators.all` on the reopened Model) |
| M02: a panel-closed script through registered actions only | `tests/ventilators_walkthrough_test.rb` runs the walkthrough, undoes all five steps, redoes them and verifies |

Not covered here: M02's "guarded delete refuses while in use" is from P4-03 on, when a Serves payload can name a
Ventilator.

## Gate

`make ci` on the staged change, chained into the commit `001644f7` (before the rebase onto `main`, whose tree for
P4-01 is identical):

```
Ruby syntax: 882 files OK
883 files inspected, no offenses detected
lint-citations: ok
Ruby suite, 10 processes: 3312 runs, 43661 assertions, 0 failures, 0 errors, 1 skips
364 passed, 1 skipped in 6.04s
48 runs, 268 assertions, 0 failures, 0 errors, 0 skips   (hostkit)
All checks passed!
```

The local suite runs Ruby 3.2.2; CI's 2.7 job runs the floor. The three new test files pass on Ruby 2.7.2 locally
(`$(rbenv prefix 2.7.2)/bin/ruby -Itests ...`: 10 runs, 133 assertions; 3 runs, 27; 1 run, 10; no failures). Two
earlier gate runs failed on literals this stage had to move and were fixed before the commit: the shipped kind count
in `tests/agent_access_discovery_test.rb` (16 to 17) and the feature list in
`tools/hostkit/tests/host_helpers_test.rb`.

## Review

Architecture and Ruby quality rubrics applied while building. One Sonnet adversarial read of the diff before the gate:
20 findings. Fixed: the out-of-range refusals now assert `params.invalid`; the default temperature is asserted a
Float; the metadata test undoes and redoes the metadata write and the edit and rereads through the public read after
the reopen; `target.not_found` and a stale delete are tested; the original keeps `manual`; `ph_composer.records.list`
lists a Ventilator; the walkthrough's Undo compares the whole restored catalog; the layer pattern has positive
controls and catches `ZONE_KIND` and `zone_id`; the list query's name has one source; the create description and the
guide's delete sentence are accurate; CONTRACTS records `x-unit` `fraction`. Declined: `reference.invalid` and
`reference.in_use` stay in the declared refusals as on the Thermal Bridge Type (the engine checks them and P4-03
makes them reachable); the defrost temperature stays unbounded as CONTRACTS binds it; the fixed temporary save path
follows the Programs test's precedent.

Codex gpt-6.2-sol, cycle 1 on `9b2978a4` (PR #565): 5 P2, 1 P3, all fixed in the next commit. An update checks
`expected_values` before name uniqueness, so a stale read with a taken name refuses `target.changed`; update, duplicate
and delete declare `target.ambiguous`; `ventilators.list` takes only `vnt_` ids (another kind's id refuses
`params.invalid`); the walkthrough compares every stored value and the `user_data` and fails on an unreadable record,
with an offline case for each; the layer test also catches bare module names and relative imports in both directions,
with positive controls; create and update state the unique-name precondition.

Codex gpt-6.2-sol, cycle 2 on `f8582bbb`: 2 P2, 1 P3, all fixed in the next commit, which merges after the two-cycle
cap unreviewed. A taken name on update now refuses the proposal itself, so a caller that rescues the refusal cannot
commit the staged rename (tested against the operation directly; removing the refusal fails the test); the
walkthrough compares one entry per record, so an extra equal record fails `verify`; the duplicate's `name` describes
the numbered copy names.

## Native case

`M02` added to `planning/native-acceptance/cases.json` (mode `mixed`, `native_control_required: true`) with paths for
the feature's files, the record engine and store, and the walkthrough. `acceptance_ledger.py status` with the changed
`extension.rb`, `shell/api.rb` and the feature's install screens 48 cases as affected by those shared files, `M02`
among them, all owed to their sittings; none was run here.
