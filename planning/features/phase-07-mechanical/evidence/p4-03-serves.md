# P4-03 evidence: Serves, the assignment payload on the Zone

DATE: 2026-11-23
Register row: [M03](../ACCEPTANCE.md). Stage: [P4-03](../phases/p4-03-serves-assignment.md).
Base: `feat/phase-07-mechanical-p4-02` at `603bf5e5` (PR #565, auto-merge armed, not merged when this stage
branched). Branch `feat/phase-07-mechanical-p4-03`.

Offline evidence only. No SketchUp process was started. The host case `M03` (fresh process on the reference model
with Zone B under a rotated wrapper; the walkthrough's `serve`; native Undo and Redo of the delete; a native copy of
Zone B; save, reopen and read back) is owed to the MS1 sitting (D4-31); nothing here is host evidence.

## What was built

| Step | Where | Note |
| --- | --- | --- |
| 1. The payload | `src/ph_composer/features/mechanical/serves/payload.rb` | `ph_composer.mechanical.zone_serves`, schema version 1, `local_only`, on the Zone record. One slot table, one line per slot: `ventilator_id`, a declared `one` reference to the Ventilator kind. The validator takes a whole payload (each slot present, an id of the slot's kind or null, a `many` list holding no id twice, no other key) |
| 2. Operations | `serves/operations.rb`, `serves/state.rb`, `declarations/serves.rb` | `serves.assign` (targets `{reference, expected_values}`, `slot`, `item_id`, `replace`) and `serves.clear` (targets, an optional `slot`). One `zones.all` read; every target checked (a changed slot refuses `target.changed`) and the item found before anything is staged; each Zone's whole payload staged through `ph_composer.zones.stage_extension`. `mechanical.slot_filled` names the current item unless `replace`. Clear stages the emptied payload, and leaves a Zone with no payload as it is |
| 3. Delete in use | `serves/operations.rb` `delete` and `release`; `declarations/ventilators.rb`; `ventilators/operations.rb` takes a `reference_plan:` | Without `replacement_id`, `reference.in_use` whose message names the Zones; with an id every slot naming the item moves to it; with null each is emptied; staged in the delete's proposal and handed to `propose_delete` as a `Records::ReferencePlan`, one Undo step. A stale `expected_values` refuses first. A move over a Zone whose two occurrences share an id (a copy not yet independent) refuses `target.ambiguous`. The family folder still names no Zone: the declaration composes the two |
| 4. Reads and findings | `serves/reads.rb`, `codes.rb` | `serves.all` (snapshot section `ph_composer.mechanical.serves`) and the bounded `serves.list`; rows carry `slots`, `items` with names, `payload_status` and `findings` (`{code, severity, message, blocks_export}`). `ventilators.all` and `ventilators.list` rows gain `zones` and `findings`. Codes `mechanical.slot_filled`, `zone_unventilated`, `item_unserved`, `item_missing`, `zone_left_out`. API 1.88 with one `API::CHANGES` row |
| 5. Metadata | `docs/USER_DATA.md` | Serves keeps no map of its own; the Ventilator row and "Objects without a map of their own" say so |
| 6. Walkthrough | `tools/examples/authoring/ventilators_walkthrough.rb` `serve`, `serve_state`, `serve_verify`; `tests/ventilators_walkthrough_test.rb` | Seven Undo steps on every occurrence of Zone A and Zone B: a Zone in a turned Group and a copy made independent |

Docs: `context/CONTRACTS.md` "Mechanical equipment", `context/AGENT_INTERFACE.md`, `docs/AGENT_GUIDE.md` "Mechanical:
what serves each Zone" and the shipped guide, `docs/API_REFERENCE.md` (`make fixtures`; `git diff --diff-algorithm=histogram
--stat`: 863 insertions, 8 deletions, each deletion a Ventilator read's or the delete's description, refusals or row
fields), the walkthrough
README.

## Departures

- **`mechanical.item_missing` is reachable only outside the engine.** Test 8 asked for the payload stored through
  `ph_composer.zones.update_metadata`. That route refuses a slot naming no stored Ventilator as `reference.invalid`, as
  every engine route does for a declared reference, so the test asserts that refusal and then writes the Zone record
  through the store, as a Zone pasted from another Model arrives. Packet CONTRACTS sections 2 and 6 now say so.
- **Two `zones.all` reads per snapshot, not one.** The stage asks for one per snapshot. Each snapshot section is its own
  request, so Mechanical's two sections (`serves` and `ventilators`) each read the Zones once. Measured by counting
  `Zones.all` calls in one `Snapshot.build` (a scratch test, not committed): 8 in all, `serves.all` 1,
  `ventilators.all` 1, `programs.zones` 2, `programs.programs.all` 1, `programs.equipment_sets.all` 1, `spaces.all` 1,
  `zones.all` 1. Each Mechanical read reads the Zones once and walks nothing else. Sharing one read across sections is a
  snapshot-level change, recorded as a follow-up with Phase 6's.
- **Clear on a Zone with no payload writes nothing**, so it cannot refuse with Zones' codes; the refusal test for clear
  uses a served Zone.
- **Assign over a payload this version does not understand** (invalid) stages a whole new one, as Programs' assign does;
  Zones refuses an outdated or unsupported one.

## Tests

`tests/mechanical_serves_test.rb`, Ruby 3.2.2 and 2.7.2: 13 runs, 320 assertions, 0 failures.

| Stage doc test | Test |
| --- | --- |
| 1. Assign; second refuses `slot_filled` naming the current item; `replace`; Undo | `test_assign_stages_the_payload_a_second_refuses_naming_the_first_and_replace_replaces` (payload read from the Zone record; nothing written on the refusal; Undo and Redo) |
| 2. Stale `expected_values` on one of two refuses whole | `test_a_stale_expected_value_on_one_of_two_zones_refuses_the_whole_command` (the fresh target first; assign and clear) |
| 3. Locked, shared definition, nested Zone | `test_zones_write_refusals_pass_through_unchanged` (`target.locked`, `target.shared_definition`, `target.wrong_hierarchy`; revision and operations unchanged) |
| 4. Clear | `test_clear_leaves_a_zone_reading_as_served_by_nothing_as_a_zone_with_no_payload_does` (two Zones one Undo step; slot and every slot; a cleared Zone reads as a Zone with no payload). Several slots: only `ventilator_id` ships, so "several" is covered by the every-slot clear over one |
| 5. Delete in use | `test_a_plain_delete_of_a_ventilator_a_zone_names_refuses_naming_the_zones`, `test_a_delete_with_a_replacement_moves_every_slot_in_one_undo_step`, `test_a_delete_with_null_empties_the_slots_and_a_bad_replacement_refuses` (the Zone in a Group moves with the root one; Undo restores the item and both slots) |
| 6. Copied Zone | `test_a_copied_zone_keeps_what_serves_it_with_no_step_of_this_feature` (copy made independent keeps the slot; no Mechanical transition contributor; before independence a move refuses `target.ambiguous` and an assign Zones' `target.ambiguous`). The native gesture is the host case |
| 7. Reads and findings | `test_the_reads_carry_names_and_findings_and_a_zone_left_out_is_not_unventilated` (names, `zone_unventilated`, `item_unserved` not blocking, `zone_left_out` on the Zone and the Ventilator, no unventilated finding on a left-out Zone, `serves.list` pages equal `serves.all`, `ventilators.list` rows equal `ventilators.all`'s) |
| 8. Missing item; unknown key | `test_a_payload_naming_a_missing_ventilator_reads_item_missing_and_an_unknown_key_refuses` (see Departures; assign with `replace` repairs it) |
| 9. Beside Programs | `test_serves_and_programs_writes_leave_each_others_payload_on_the_zone` |
| Export | `test_a_serves_payload_never_blocks_export` (no `extension.*` or `export.blocked` finding) |

Mutation checks (source restored after each): skipping the `expected_values` comparison fails test 2; staging nothing
in the delete's move fails four tests (replacement, null, copy, beside Programs).

`tests/ventilators_walkthrough_test.rb`: 2 runs, 23 assertions (the Serves steps forward, each of the seven Undo
steps back read in turn, and Redo). `tests/mechanical_dependency_test.rb` holds with `serves/` in place.

## Gate

`make ci` on the staged change, Ruby 3.2.2 (`.ruby-version`) and then Ruby 2.7.2
(`make ci RUBY=$(rbenv prefix 2.7.2)/bin/ruby`), both exit 0, the same counts on each:

```
Ruby syntax: 889 files OK
890 files inspected, no offenses detected
lint-citations: ok
Ruby suite, 10 processes: 3326 runs, 44229 assertions, 0 failures, 0 errors, 1 skips
364 passed, 1 skipped
48 runs, 268 assertions, 0 failures, 0 errors, 0 skips   (hostkit)
RBZ verified: 720 files, 8742334 bytes, 26901138 bytes installed
```

The installed size is 26,901,138 bytes, 1,098,862 under the 28,000,000-byte ceiling. A first 3.2.2 run failed only
`tests/api_reference_test.rb` after two schema descriptions changed; `make fixtures` regenerated the reference before
the passing runs. No panel or Python file changed, so the runtime manifest is untouched.

## Review

Architecture and Ruby quality rubrics applied while building: the family folder stays Zone-free (the delete composes
Serves and the family operation in `declarations/`), and no mechanical code writes a Zone record.

One Sonnet adversarial read of the diff before the gate, 12 findings. Fixed: the stale test puts the fresh Zone first,
so a command that staged Zone by Zone would fail it; clear across two Zones is asserted as one Undo step; a matching
`expected_values` on the delete; an assign on one occurrence of a copy not yet independent refuses Zones'
`target.ambiguous`; the row's `building_segment_id` says it is null for a Zone not yet adopted; the result `zone_ids`
says it lists the Zones named; a family comment no longer names what the Ventilator serves. Declined: the Ventilator
reads now refuse when the Zones read does (Programs' catalog reads do the same); a Ventilator row lists every Zone it
serves (the list honours `fields`, and a page cuts at a whole row); the in-use message names the Zones whose payload
is understood (the engine's incoming check refuses the rest); assign over an invalid payload rebuilds it, as
Programs' does; `proposal.refuse` keeps the first refusal, so calling it twice is harmless.

Codex: see the PR.

## Native case

`M03` added to `planning/native-acceptance/cases.json` (mode `mixed`, `native_control_required: true`) with paths for
the feature's files, Zones' participant and occurrences, the engine's reference handling and the walkthrough.
`acceptance_ledger.py status` with the changed shared files (`shell/api.rb`, the feature's install, the Ventilator
declarations, operations and reads, the walkthrough) screens 38 cases as affected, `M02` among them, all owed to their
sittings; none was run here.
