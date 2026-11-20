# Pre-archive Codex review of the Shading commits that merged unreviewed

DATE: 2026-11-19
STAGE: P5s-07 (pr-loop step 8 rule: one Codex review covers every fix pushed after a PR's last review)

Reviewer: Codex gpt-6-astra, `codex_pr_review.py` dry run (not posted), context the packet's DECISIONS
(D5s-11a included), CONTRACTS and PRD plus the repository's architecture and Ruby rubrics. Each commit's own
diff was reviewed against the P5s-06 branch head as working tree. The commits are on `main` inside the squash
merges #528, #529, #530 and on #532's branch.

| Commit | Stage | Verdict | Findings |
| --- | --- | --- | --- |
| `0f14c44d` | P5s-02, list marks inside cutting components; `geometry.invalid` | approve | none |
| `47382d12`, `35e04012` | P5s-03, excluded members kept in step; classification wins | request changes | three, below |
| `9a975e34` | P5s-04, the container a cleared Face still shades through | approve | none |
| `8ed78237` | P5s-06 ledger, SD06 case entry | request changes | one, below |

## Findings and handling

1. **P2, `features/shading/preflight.rb`: a cutting component, Zone or claimed object beside classified Faces
   hid `shading.classified_inside`.** A marked Group inside a Zone holding both reported only
   `shading.zone_inside`. Real: reproduced by
   `test_a_marked_group_holding_a_cutting_component_and_a_classified_face_takes_both_notes`
   (`tests/zones_envelope_exclusion_test.rb`), which failed with only `shading.zone_inside`. Fixed in P5s-07:
   `container_findings` gives both notes, and skips the classified count for a marked Zone Group itself;
   `context/CONTRACTS.md`, "The shading mark", says a container can take both.
2. **P2, `tests/zones_envelope_exclusion_test.rb`: the copy-repair test never ran `RepairIdentityStep` or
   `MakeIndependentStep`.** Real: dropping either `envelope: false` left the suite green. Two tests added to
   `tests/zone_repair_test.rb`, `test_repair_restamps_a_member_face_outside_the_envelope` and
   `test_make_independent_restamps_a_member_face_outside_the_envelope`; both fail with the two arguments
   removed and pass with them.
3. **P3, packet CONTRACTS, "What P5s-03 decided": it still said Assign takes a Group holding classified Faces.**
   Real; it contradicted D5s-11a. Rewritten: assign refuses such a Group, classification wins over an
   inherited mark, and a classified Face leaves the envelope only through an excluding mark on the Face itself.
4. **P2, `planning/native-acceptance/cases.json`: SD06's paths omitted code the case exercises.** Real under
   the case ledger's dependency rule. Added `features/zones/export.rb` (which decides Room or Shade),
   `core/face_capture.rb`, `core/records/entity_store.rb`, and the translation `assembly.py` and
   `composition.py`. SD07's new entry carries the same paths.

Residual gaps Codex named, not acted on: clearing a mark inside a uniquely placed cutting component has no
success-path test (P5s-02; a cutting component's contents are left out of assign, so only clear reaches it);
the native rows stay with the batched host pass.
