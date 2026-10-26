# P3b-01: thermal-bridge contracts and edge host facts

DATE: 2026-10-03
STATUS: Merged to main 2026-10-22 (PR #302); T01 pass. Corrected to `main` at `420c783a` on 2026-10-21 (DECISIONS Part 1b)
AUTHOR: Ed May, BLDGTYP, with Claude
ISSUE: [#301](https://github.com/ph-composer/ph-composer-skp/issues/301)

## Entry and scope

Requires Ed's authorization. The interview is complete: Ed answered every question in
[thermal-bridges DECISIONS](../DECISIONS.md) on 2026-10-03, and the PRD and
`context/UBIQUITOUS_LANGUAGE.md` were amended the same day; the packet was re-baselined against
`main` at `420c783a` on 2026-10-21, which answered five of CONTRACTS section 7's seven questions
from code (section 8) and added D3b-22 and D3b-23. Owns what must be true before any file exists
under `features/thermal_bridges/`: the two bindings still unconfirmed, proven by test; the answers
to D3b-22 and D3b-23 folded in; the host facts B4 left open; and the citation lint for the ids the
pattern still misses. No feature code and no screen.

Behavior owner: the [thermal-bridges PRD](../PRD.md). Names:
[thermal-bridges CONTRACTS](../CONTRACTS.md) sections 5 and 7. Host method:
`.agents/skills/ph-composer-native-acceptance/SKILL.md`.

Paths are relative to `src/ph_composer/`.

## Steps

1. **Check the fold.** The PRD, DECISIONS "Ed's answers" and the glossary were updated on
   2026-10-03 and the packet re-baselined on 2026-10-21. Confirm the PRD, CONTRACTS and the stage
   documents agree with every answer, D3b-20's change from the recommendation and Ed's answers to
   D3b-22 and D3b-23 included, and correct any drift. Fold the D3b-22 answer into CONTRACTS
   section 2 and the D3b-23 answer into section 1's `runs/` contract; record G-01's answers (the
   Edge facts, per-entry filtering, legend counting, line width) in the
   [geometry contribution contracts](../../geometry-contribution-contracts/STATUS.md)
   packet as well; both were answered as recommended on 2026-10-21.
2. **Answer the rest of CONTRACTS section 7.** Questions 2 and 3 each get a focused test
   (`EntityStore` round-trips a record on a stub Edge and the dictionary reaches the export
   attribute guard; `faces.host_context` answers the Faces of an Edge reached by its path plus a
   `face_ids` entry, or does not), added to section 8. Re-read `features/zones/zone/occurrences.rb`
   as PR #208 left it before binding H11 to its names. Correct every table the answers change. Run
   the architecture review on the corrected CONTRACTS and record its outcome.
3. **Close B4's open host cases.** Extend `tools/spikes/edge/edge_spike.rb` (development-only, it
   may cite planning) with five steps on a tagged edge inside a Zone-like Group, each followed by
   Undo, Redo, and a capture of persistent ids, endpoints and dictionaries: native Divide (the
   context-menu command, driven by a human or native control); native Weld (the menu command);
   a push-pull that removes the tagged edge; `Entities#intersect_with` of a crossing face; and
   erasing the crossing edge of a split so SketchUp heals two tagged collinear halves. Save, quit,
   relaunch and compare. For the heal, record which dictionary survives when the halves carry the
   same record, and when they carry different records.
4. **Fold the host facts.** Add the results to `context/SKETCHUP_HOST_BEHAVIOR.md`, "Components,
   glue and edge attributes", with the consequence column. If a case loses a tag or merges two
   different records silently, stop and record the consequence for D3b-01 in DECISIONS before
   P3b-03 starts.
5. **Citation lint (H17).** `PLANNING_IDS` (`Makefile:81`) already fails `P3b-01` and `D3b-02`.
   Extend it so an acceptance id (`T01`, and `S01` for the archived Spaces register) and a
   two-digit finding id (`F26`) in `src/` or `tests/` fail `make lint-citations`. Check the pattern
   against the whole current tree first: a new id must not match an existing legitimate token.
6. **Ledger cases.** Add T01 to `planning/native-acceptance/cases.json` (`authority`, `id`,
   `label`, `mode`, `native_control_required`, `paths`) with the spike and context paths it depends
   on.

## Source

| PH-Composer file | Disposition |
| --- | --- |
| `tools/spikes/edge/edge_spike.rb` | Extend with the five cases; keep its scan and registry code unchanged so earlier B4 results stay reproducible |
| `core/records/entity_store.rb`, `tests/support/sketchup/` (the stub Edge G-02 extended) | Question 2's test |
| `features/zones/faces/operations.rb` (`host_context`), `features/zones/zone/occurrences.rb` | Question 3's test; read for H11's binding |
| `Makefile` `PLANNING_IDS` | Extend for `T\d\d` and `F\d\d` |

## Tests (write first)

1. A planted `T01` and `F26` in a scratch file under `tests/` fail `make lint-citations`
   (`P3b-01` already does); the current tree passes.
2. The two focused tests that answer section 7's questions 2 and 3, kept only where they prove a
   contract a later stage relies on.

## Host gate

Fresh process, a synthetic Model with one tagged edge per case, the five B4 cases with Undo, Redo,
save and fresh-process reopen, read through the bridge. Native Divide and native Weld need native
controls or one precise human action each; follow `context/NATIVE_CONTROL_CAPABILITIES.md`.
Observe the host with the development tooling: `host_bridge.py wait-for` for deferred work, `host_bridge.py diagnostics` for what happened, `acceptance_case.py begin` and `finish` for the ledger row (`tools/hostkit/.index.md`).

## Out of scope

Any file under `features/thermal_bridges/`. Every Zones, Windows, Colour-by and export change.

## Done when

- T01 has evidence in `../evidence/p3b-01-edge-host-facts.md`, with the architecture review
  recorded.
- The PRD carries Ed's answers, D3b-22 and D3b-23 included; CONTRACTS section 8 answers all seven
  questions; every table agrees with the code; G-01's answers are recorded in both packets.
- `context/SKETCHUP_HOST_BEHAVIOR.md` holds the five results; `make ci` passes on both Rubies.
