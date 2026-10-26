# P3b-04: runs, the schedule read and findings

DATE: 2026-10-03
STATUS: Implemented on branch `feature/thermal-bridges-p3b-04` (PR #310), T04 passed 2026-10-26; D3b-13 measured over budget, so the schedule is read on request with no snapshot section. Corrected to `main` at `420c783a` on 2026-10-21 (DECISIONS Part 1b)
AUTHOR: Ed May, BLDGTYP, with Claude
ISSUE: [#301](https://github.com/ph-composer/ph-composer-skp/issues/301)

## Entry and scope

Requires P3b-03 and D3b-06, D3b-07, D3b-10, D3b-13, D3b-16, D3b-21 and D3b-23 (answered
2026-10-21), with PRD Q5 and Q7. Owns the pure run
builder, the schedule read and snapshot section, the findings that need no Windows read, and
`runs.locate`. Panel closed. After this stage the feature is complete as data: milestone T-M1.

Behavior owner: the [thermal-bridges PRD](../PRD.md), "Runs", "Schedule" and
"Validation rows". Names: [CONTRACTS](../CONTRACTS.md) sections 3 and 6.

Paths are relative to `src/ph_composer/`.

## Steps

1. **Run builder.** `runs/chains.rb`, pure Ruby with no SketchUp: input is detached edge facts
   (occurrence path, Zone id, Building-Segment, type id, quantity, world endpoints in metres and
   the two vertex ids the snapshot already carries); output is runs. Group by Zone, type and
   quantity; join Edges that share a vertex keyed on container path plus vertex id (D3b-23; SketchUp merges endpoints within 0.0254 mm inside one Entities collection,
   `context/SKETCHUP_HOST_BEHAVIOR.md`, "Zone grouping and face topology", so inside one container
   the two rules agree and the id is exact, while two placements of one component carry the same
   vertex ids and must not join); split at free ends and at vertices where the group's degree is
   not two; a closed chain is one closed run. Each run carries its ordered points, its edge paths, its length in metres, and the D3b-07
   name and identifier, the identifier digesting the container path with the Zone, type and
   endpoints so two coincident placements of one component get two identifiers. Order is deterministic so goldens are stable.
2. **Schedule.** `runs/schedule.rb`: rows per run with Zone, Building-Segment, type, length, psi,
   quantity and psi times length times quantity in W/K; totals by type and by group; used length
   per type, which `types.all` now reports. All arithmetic in Ruby (`context/CODING_STANDARDS.md`,
   "Layering"); the panel formats.
3. **Scan.** `scan/occurrences.rb` walks the Model once for tagged Edges, collects detached facts
   and asks `zones.containment` once for all paths. Edges inside shared definitions yield one fact
   per occurrence with the `shared` mark (D3b-10).
4. **Findings.** `runs/findings.rb`: `type_missing`, `psi_missing` (blocking only for an assigned type, D3b-21),
   `outside_zone`, `no_envelope_face` and `interior_junction` (from `faces.host_context` on the
   Edge's Faces), `counted_twice` (coincident assigned Edges in different Zones),
   `shared_definition`, and `zone_omitted` when the Zone is omitted from export. Each finding
   names its run or Edge and a `locate` with `runs.locate`'s params.
5. **Declarations.** The `schedule` query and snapshot section, bounded, with `response:` naming
   the bound, and `runs.locate` as a view command (`capability: "view"`, `side_effects` saying it
   selects, frames and may open a Zone's context) that selects a run's Edges along their paths and
   zooms, refusing hidden targets; a run inside a nested Zone opens that context through the
   foundation's `ph_composer.context.open`, as `spaces.locate` does, never a navigation of its own
   (D3a1-04). One `API::CHANGES` row; extend the agent guide recipe with the schedule read.
6. **Measure (D3b-13).** Build a synthetic Model of 50,000 Edges with 5,000 assigned through the
   bridge, measure the schedule read and the panel refresh on the proving host, and record the
   numbers against the 200 ms repaint target the units packet set (Zones measured 161 ms with every
   row open, PR #289). If the budget is exceeded, implement the PRD's scan on panel open and Refresh
   instead of live and record the change in DECISIONS.

## Source

| PH-Composer file | Disposition |
| --- | --- |
| `features/zones/declarations/assembly_assignment.rb` (`assembly_usage`) | Pattern for a live aggregate read and its measurement |
| `features/zones/faces/locate.rb`; `features/spaces/declarations/context.rb` (`spaces.locate` and its use of `ph_composer.context.open`) | Pattern for `runs.locate` |
| `features/windows/units/areas` read | Pattern for a schedule read over placed things |

## Tests (write first)

1. Chain rule: a U of three Edges is one open run of four points; a square is one closed run; a
   T of three Edges is three runs; two Edges sharing a vertex in one container join, two
   coincident Edges in different containers do not, and two placements of one component in one
   Zone share vertex ids and do not join (D3b-23); two quantities on one chain give two runs.
2. Lengths and totals on the reference model's facts equal ACCEPTANCE's hand calculation to
   0.001 m and 0.001 W/K, including the negative Footing and the quantity-2 Balcony.
3. Names and identifiers are deterministic across two scans and change only with geometry; two
   coincident placements of one component in one Zone give two runs with distinct identifiers.
4. Each finding fires on its case and on no other.
5. A tag in a component placed twice yields two runs, each marked shared.
6. The scan opens no operation and writes nothing.

## Host gate

Fresh process on the reference model, panel closed: read `schedule` and compare with the hand
calculation; `runs.locate` into a nested Zone; the counted-twice and outside-Zone cases from
ACCEPTANCE; the 50,000 Edge measurement. Observe the host with the development tooling: `host_bridge.py wait-for` for deferred work, `host_bridge.py diagnostics` for what happened, `acceptance_case.py begin` and `finish` for the ledger row (`tools/hostkit/.index.md`).

## Out of scope

Screens (P3b-05). The window-perimeter finding (P3b-08, D3b-15). Export (P3b-08).

## Done when

- T04 has evidence in `../evidence/p3b-04-runs-and-schedule.md`, with the measurement and the
  D3b-13 outcome.
- `make ci` passes on both Rubies.
