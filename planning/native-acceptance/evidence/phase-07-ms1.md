# Phase 7 MS1 host sitting: M01 to M04

DATE: 2026-11-25
STATUS: Recorded. M02, M03 and M04 pass; M01 unknown (one clause not observable on the host).
ISSUE: #562

Synthetic summary of the MS1 sitting (D4-31) for [Phase 7 Mechanical](../../features/phase-07-mechanical/ACCEPTANCE.md).
Raw Models, HBJSON, reports, logs, drivers and `steps.md` per case stay in gitignored `_private/host/phase-07-ms1/`.

## Build and host

- Source: `main` at `a2bb7957`. `make rbz && make install && make bridge-install`; `dist/ph_composer.rbz` sha256
  `2fd51f46be24d49024aed715f0a61bf094a5a9e4b404709bd54548238a1af93e`, 9,097,094 bytes (27,943,439 installed);
  `acceptance_run.py package` matches, 877 entries, no extras.
- SketchUp 26.1.188, Ruby 3.2.2, macOS. Every case in its own fresh process from `host_bridge.py launch`, panel
  closed throughout. HBJSON reloaded with honeybee-core 1.64.65, honeybee-energy 1.123.23, honeybee-ph 1.33.68.
- Fixtures, built through public operations in fresh processes from the blank template:
  `reference.skp` (sha256 `5114c998`): ACCEPTANCE's reference model, Zone A 5 x 4 x 3 m and Zone B 4 x 4 x 3 m
  adjacent with the shared wall solved, one Segment, Spaces A1 60/50 and B1 40/40 m³/h.
  `reference-wrapped.skp` (sha256 `98b2c2dc`): the same with Zone B inside a plain Group turned 90 degrees about its
  centre and no adjacency, plus `VentilatorsWalkthrough.run`'s catalog (ERV-1, ERV-1 (copy)) as labelled setup.
  M02 started from a fresh copy of the blank template (sha256 `2ae1418d`).

## Control route

Product writes through registered actions (`PhComposer::API`), reads through the bridge in separate calls. Exports
through `API.start_export` with a labelled approved-location stand-in for the Export tab's approval, revoked after
each export (none left). Background `app_menu` reported Edit > Undo disabled and a background title-bar click was
refused, so native Undo, Redo, Copy and Paste In Place were pressed by System Events AXPress of the Edit menu item by
its exact title, with SketchUp already the frontmost process after its launch and no fronting call. Each press read
the item's title first and refused a mismatch. `M02` was run twice: run 1's `begin` named background `app_menu` as
the controller, so its uncommitted ledger row was dropped and the case rerun with the route actually used. No full-screen control was used.

## Results

| Case | Outcome | Assertions |
| --- | --- | --- |
| `M01` | unknown | export-runtime-completes pass; rooms-carry-ph-hvac pass; phhvac-loaded-after-honeybee-ph unknown |
| `M02` | pass | walkthrough-registered-actions, native-undo-redo-five-steps, save-reopen-catalog |
| `M03` | pass | serve-walkthrough, undo-redo-delete-restores, each-step-one-undo, native-copy-keeps-slots, save-reopen-slots |
| `M04` | pass | base-case-two-systems, shared-case-one-identifier, shared-case-item-unserved-reported, zone-left-out, reexport-same-ventilation |

### M01

The installed RBZ exported the reference model (ERV-1 on Zone A, ERV-2 on Zone B) in the host's export runtime:
`export.complete`. The exact HBJSON reloads with both Rooms' `properties.ph_hvac` a `RoomPhHvacProperties` holding a
`PhVentilationSystem`. The load order (honeybee_phhvac through `stack.load` after honeybee_ph) is not observable on the
host: the export status and run diagnostics record no module loads, and the runtime reports stack modules only at
boot. It stays unknown; the order is covered offline by `browser_check.py --translation` in Chromium 88
([p4-01](../../features/phase-07-mechanical/evidence/p4-01-contracts.md)).

### M02

On a blank Model the walkthrough created ERV-1 and ERV-2, edited ERV-1's quantity, duplicated ERV-1 and deleted ERV-2,
every step committed. Edit > Undo, five times (Delete, Duplicate, Edit, Create, Create Ventilator), took back one
step each, read after each, to an empty catalog; Redo five times rebuilt it and `verify` matched. After save and a
fresh-process reopen, `ventilators.all` reads ERV-1 and ERV-1 (copy) with every value and the `user_data`.

### M03

With Zone B under the turned wrapper, `serve` committed its seven actions and both Zones read ERV-2. Undo Delete
Ventilator restored ERV-1 under its original id with Zone B's slot naming it; Redo returned both to ERV-2. Seven
Undo presses (Delete Ventilator, Assign Equipment, Clear Equipment, Assign Equipment three times, Create Ventilator)
each took back one action, ending at the fixture state; seven Redo presses rebuilt them. Edit > Copy and Paste In
Place of Zone B inside the wrapper gave a copy that is its own Zone with ERV-2 in its slot; the Edit item read
Undo Paste, one Undo removed the copy and Redo brought it back with the same Zone id and slot, and the live
registry's transition contributors are Windows, Spaces and Programs, none Mechanical. After save and a
fresh-process reopen, `serves.all` reads the three occurrences as before saving.

### M04

- Base case: Room A holds ERV-1 and Room B ERV-2, each `sys_type` 1 with the ACCEPTANCE values (0.85 / 0.60,
  0.45 Wh/m³, frost protection, -5 °C, conditioned, quantity 1; 0.75 / 0.00, 0.35, no frost protection, not
  conditioned, subsoil 0.20) and unit identifiers `<id>_unit`: two systems.
- Shared case: a plain assign of ERV-1 to Zone B refused `mechanical.slot_filled`; with `replace: true` both Rooms
  carry one identifier, ERV-1's, and ERV-2 is absent from the HBJSON; the report lists `mechanical.item_unserved`
  for ERV-2, not blocking.
- Zone B in no Building Segment: the first export refused `face.partner_left_out`, because the reference model's
  Zones share a solved Surface wall (the offline test's boxes stand 1 m apart; unsolved adjacent boxes were not
  tried). After the documented repair (Zone B
  made the Attached zone of the shared Faces) the export wrote Room A only, with `mechanical.zone_left_out` on ERV-1
  naming Zone B, not blocking.
- Re-export: base case restored (Zone B back in the Segment, ERV-2 back, adjacency solved again), exported, saved,
  reopened in a fresh process and exported again. Room identifiers, every Room's `ph_hvac`, the model's `ph_hvac`
  and the reloaded ventilation read-backs are identical. The whole files differ at the same size: random
  honeybee-ph identifiers on the team and Segment sub-objects, and list order in the energy properties; with
  UUID-shaped values masked and lists sorted, the two files are equal. Compared by section, as p4-15's decision 3
  proposes.

## Open

- `M01/phhvac-loaded-after-honeybee-ph`: needs a host-side probe of the export runtime's module loads, or Ed's
  ruling that the offline browser check covers the order.
- Ed's decision 3 in [p4-15](../../features/phase-07-mechanical/evidence/p4-15-acceptance.md) (section or whole
  file) governs whether `M04/reexport-same-ventilation` stands as recorded.

## Restoration

No fault, provider override or preference change. Every approved location the sitting created is revoked.
SketchUp was quit at the end with no open document; no stray file in `~/Documents`.
