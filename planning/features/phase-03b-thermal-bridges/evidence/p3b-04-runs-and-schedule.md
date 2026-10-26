# P3b-04 evidence: runs, the schedule read and findings (T04)

DATE: 2026-10-26
STATUS: Host gate run on branch `feature/thermal-bridges-p3b-04` at `e618f1e3` (PR #310), SketchUp 26.1.188, Ruby 3.2.2, macOS 26.7.1. All six assertions pass. D3b-13: the schedule is read on request.
AUTHOR: Ed May, BLDGTYP, with Claude
ISSUE: [#301](https://github.com/ph-composer/ph-composer-skp/issues/301)

Register row [T04](../ACCEPTANCE.md). Offline half: `tests/thermal_bridge_runs_test.rb` (12 runs, the chain
rule, the hand calculation, determinism, every finding on its case), `tests/thermal_bridge_schedule_test.rb` (7,
the live scan, paging, a 600-Edge run, `runs.locate` and its refusals) and the lookup case in
`tests/zones_containment_test.rb`, green on Ruby 3.2.2 and 2.7.2; `make ci` green at `e618f1e3`. Review: one
pre-gate Sonnet read (19 items, 13 fixed in `433d9a84`) and two Codex gpt-6.1-sol cycles on PR #310 (cycle 1: 2
P2, fixed in `77587f50`; cycle 2: 1 P2 and 1 P3, fixed in `e618f1e3`). Host half: recorded through
`tools/hostkit/acceptance_case.py` in `_private/host/t04/T04/` (gitignored; synthetic fixture, no project data).
The ledger row records a branch commit, not `main`.

## Identity

| Item | Value |
| --- | --- |
| Installed RBZ | `dist/ph_composer.rbz` built at `e618f1e3`, SHA-256 `db7e7ef231c519335604e19ddbcf4a117009f9782c32cd215e4040002e67cbdb` |
| Fixture | `_private/host/t04/T04/t04.skp` (SHA-256 `5ddd125b`), a copy of `t04-reference-base.skp`, which `ThermalBridgeReferenceModel.build` made from `blank-template.skp`: ACCEPTANCE's two adjacent Zones, Zone W in a Group turned 30 degrees, the five types, every Face classified as Zones suggests, a Window Unit on Zone A's south wall, the Balcony line across Zone B's south wall, a line at the Model root, nothing assigned |
| Measurement Model | `_private/host/t04/measure-classified.skp`: ten Zones of 417 one-metre boxes (50,040 Edges, 25,020 Faces, every Face classified), 5,000 Edges assigned through `edges.assign` in calls of 250, five types; `measure.skp` is the same with the Faces unclassified |
| Process | Fresh, launched by `host_bridge.py launch`, the fixture the only document; composition normal |
| Controls | Bridge for every public call and readback; System Events for the native Undo, after reading the Edit menu's first item |

## Results

| Assertion | Observed | Evidence |
| --- | --- | --- |
| Hand calculation | Five runs equal ACCEPTANCE to 0.001 m and 0.001 W/K: Parapet 1 14 m 0.700, Parapet 2 12 m 0.600, Slab edge 1 14 m 1.680, Footing 1 12 m -0.240, Balcony 1 4 m at quantity 2 2.000; groups 3.300, 1.680, -0.240; Model 4.740 W/K; no finding | `1-verify.json` |
| Open context | Every run's length and points are identical read with Zone W open inside the turned wrapper, with Zone A open, and with the path closed | `2-open-context.json` |
| Counted twice, Undo | Parapet on the x = 5 m roof Edge in both Zones: closed runs of 18.000 and 16.000 m, each with `counted_twice` only (ACCEPTANCE corrected, DECISIONS F39). One native Undo restored the hand calculation | `3-*.json` |
| Outside a Zone | The Balcony record on the root line reads as one Edge finding, `outside_zone`, not blocking; the runs are unchanged | `4-outside-zone.json` |
| Locate into a nested Zone | Parapet 3 on Zone W's roof, closed, 8.000 m. `runs.locate` opened the wrapper and Zone W, selected exactly the four Edges and targeted the run's centre | `5-locate-nested.json`, `5-locate-nested-framed.png` |
| Measurement | See the table below | `6-measurement.json` |

## D3b-13 measurement

Median of five reads, milliseconds, on 50,040 Edges with 5,000 assigned (1,250 closed runs). "Before" is the
first build of the stage, where Zones resolved each path by scanning every collection along it.

| Phase | Before, unclassified | Final, unclassified | Final, classified (`e618f1e3`) |
| --- | --- | --- | --- |
| Walk for assigned Edges | 115 | 125 | 127 |
| `zones.containment`, 10 pages | 10,150 | 589 | 605 |
| `zones.faces.host_context`, Face pages | 12,201 | 771 | 797 |
| `schedule.all` | 22,594 | 1,831 | 1,842 |
| `schedule.list`, first page | 22,484 | 1,685 | 1,708 |
| Panel snapshot | 35,057 (schedule section live) | 11,960 (no section) | 12,064 (no section) |

The 200 ms refresh target is the units packet's (DECISIONS F36). `schedule.all` is about nine times over it, so
the recorded fallback applies: no snapshot section, and the Schedule reads it on opening and on Refresh. The
per-read `Zones::ChildLookup` is what makes even that usable; what remains is per path in Zones (about 30 ms per
500 paths building the Zone occurrence and write refusal) and the validation of each published result (17 ms per
page of 500). The snapshot's twelve seconds are Zones' own whole-Model sections on 25,020 Faces (F40), outside
this packet.

## Host facts recorded here

- One collection or entity read twice is the same Ruby object, a Group's `entities` included; the
  `context/SKETCHUP_HOST_BEHAVIOR.md` row of 2026-09-30 that said otherwise is corrected.
- `host_bridge.py shot` calls `View#zoom_extents` before writing the image, so it cannot show a framing a command
  set. Write the image with `View#write_image` to keep the camera.

## Limits

- `counted_twice` compares whole Edges: an Edge one Zone splits where the other does not is not found.
- One run larger than the page budget is sent alone, so a run of a few hundred Edges can exceed a caller's
  reply budget until a `fields` projection exists.
- `thermal_bridge.zone_omitted` is not registered: no Zone omission state exists (F38).
- The `no_envelope_face`, `interior_junction`, `type_missing`, `psi_missing` and `shared_definition` cases are
  proven offline only; the host gate covers the cases its stage document names.
