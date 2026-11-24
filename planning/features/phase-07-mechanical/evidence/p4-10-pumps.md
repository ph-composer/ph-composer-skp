# P4-10 evidence: pumps

DATE: 2026-11-24
Register row: [M10](../ACCEPTANCE.md). Stage: [P4-10](../phases/p4-10-pumps.md).
Base: branched from `feat/phase-07-mechanical-p4-09` at `c0c27741` (PR #573, open at branch time); after #573 merged
as `a88790fe` (identical tree), rebased onto `main`. Branch `feat/phase-07-mechanical-p4-10`.

Offline evidence only. No SketchUp process was started by this stage. The host case `M10` (in
`planning/native-acceptance/cases.json`: the Pumps subtab, create, type, power and operation in place, the internal heat
gains disclosure with the profile following the type, Serves with two pumps on one Zone, a pump on a Zone with no Space
and its Export-tab warning, delete with a replacement in one native Undo step, Undo and Redo, export and exact HBJSON
reload, save, fresh-process reopen and re-export, the three panel sizes) is owed to the MS3 sitting (D4-31); nothing
here is host evidence. M10 stays Open.

## What was built

| Step | Where | Note |
| --- | --- | --- |
| 1. The kind | `features/mechanical/pumps/schema.rb`, `reads.rb` | `ph_composer.mechanical.pump`, `pmp_`, schema 1: Tag, Notes, `manufacturer`, `model`, `device_type` (4, 6, 7, 10; 6), `quantity` (1), `in_conditioned_space` (true), `norm_energy_demand_w` (0), `annual_period_operation_khrs` (8.76), `ihg_utilization_factor` (1.0), `ihg_usage_profile` (absent: follows the type). `Pumps.ihg_usage_profile` resolves it; rows add `ihg_usage_profile_default`. Persistence is `CatalogOperations` unchanged |
| 2. Serves slot | `serves/payload.rb`, `declarations/serves.rb` | `pump_ids`, `many`, payload schema 5 |
| 3. Declarations | `declarations/pumps.rb`, `install.rb`, `shell/api.rb` | `pumps.list`, `.all` and its snapshot section, `.create`, `.update`, `.duplicate`, `.delete` with `replacement_id`; API 1.96 with one `CHANGES` row |
| 4. The plan | `pump_plan.rb` | Pure: one pair per (pump, exported Zone) under the pump's id with the profile resolved; the shared item findings; `mechanical.item_missing` blocking |
| 5. No-Spaces finding | `codes.rb`, `export_zones.rb`, `features/spaces/export.rb` | `mechanical.zone_without_spaces` (warning) from `ExportZones.spaceless_findings(exported, items, slot, label, spaced)`, which Fans call with their slot; Spaces' projection gains `space_count` and a row for every exported Zone holding a Space, Volume or not |
| 6. Export, preflight, Locate | `pump_export.rb`, `preflight.rb`, `locate.rb` | `ph_composer.mechanical.export.pumps`, requiring Zones, the Ventilator export and Spaces; the preflight reads `ph_composer.spaces.all` only while an exported Zone names a pump, and a refused read skips the finding and keeps the pump rows; `locate` takes `pump_ids` |
| 7. Python | `mechanical_sections.py`, `contract/mechanical_records.py`, `composition.py` | `PumpSection`: a fresh `PhSupportiveDevice` per pair, `device_type` set before `ihg_usage_profile`, `add_supportive_device` once per pump on a Room, rows `pumps` with each digest, `conformance` by identifier and digest per Room and no unreported supportive device under a Pump id |
| 8. Panel | `html/features/mechanical/pumps.js`, `optional_values.js`, `index.html` | Pumps subtab (order 40), Pumps pill: Tag, Type, Quantity, Power (W), Operation (kh/yr), In conditioned space, Serves chips with the list picker, hideable identity; the internal heat gains behind each row's arrow (utilization factor, usage profile with "From type (...)"); `optional_values.js` gains choice fields and per-field defaults |

Docs: `context/CONTRACTS.md` (the kind, Serves schema 5, Locate, the table, the export, the Spaces projection),
`context/AGENT_INTERFACE.md` (API 1.96), `context/UBIQUITOUS_LANGUAGE.md` (Pump; the Mechanical tab row),
`docs/AGENT_GUIDE.md` and the shipped guide ("Mechanical: pumps", "Mechanical: the Pump export", the list slots),
`docs/PRODUCT.md` ("Add pumps"; the subtab list), `docs/USER_DATA.md` (Pump row), `docs/API_REFERENCE.md`
(`make fixtures`), the packet CONTRACTS (sections 1, 2, 3 and 6), the equipment README and STATUS. Runtime and panel
manifests refreshed. Host case `M10` added to `cases.json`.

## Departures and choices

- **Inferred in planning** (the stage doc's list): the profile stored as an override (null follows the type, the
  Grasshopper component's reading), `in_conditioned_space` on the row, 0 W on create (the Grasshopper component's
  default), power in W in both unit systems, the label Pump and id `pmp`, the type and profile labels, the finding's
  code and helper, the Pumps pill at order 40, Pump-id conformance scoping, the shared disclosure extended.
- **The arrow's pressed state.** It is pressed while the factor is not 1 or a profile is chosen, including a chosen
  profile equal to the type's; the docs say so.
- **Goldens.** Every extraction golden gains the empty Pump section (`make fixtures`);
  three Ruby tests and `tests/python/test_model_sections.py` that list sections by hand name it; the discovery test
  counts 26 record kinds.

## PHX trace and round trip

Read in PHX 1.59.4 (`from_HBJSON/create_variant.py`, `add_supportive_devices_from_hb_room`): PHX walks each Room's
Spaces, takes each supportive device once by key and builds a `PhxSupportiveDevice`
(`create_hvac.py`, `build_phx_supportive_device`); `merge_all_devices` groups by identifier. Proved by
`tests/python/test_pumps_phx_round_trip.py`: the reference's three pairs give two devices, each once, with type,
quantity, watts, kilohours, factor and profile as stored (quantity 2 not summed by a merge), each named once in WUFI
XML; with Zone B's Space removed, P-1 still reaches PHX once through Room A; a pump only on the Room with no Spaces
gives no device.

## Tests

- `tests/mechanical_pump_test.rb`: defaults, eight out-of-range values refused on create and update, a taken Tag; the
  profile following a type change, an override surviving one and null returning to the type; guarded edit with stale
  refusal, Undo and Redo; Duplicate with `user_data`; two Zones and two pumps on one, Clear with `item_id`, an id of
  another kind; delete in use, with a replacement (kept once) as one Undo step that Undo restores, with null.
- `tests/mechanical_pump_export_test.rb`: the reference (P-1 on A and B with `user_data`, P-2 on A with a chosen
  profile) gives three pairs, equal per pump, no notes and no preflight rows, owning
  `tests/fixtures/mechanical/pump_extraction.json`; a pump on a Zone with no Space noted and still written, the same in
  the preflight; a Space with no Volume gives no finding; a refused Spaces read skips the finding; an unserved pump, two
  Segments and a left-out Zone; a missing pump blocks; an unreadable pump blocks as unreadable; a reserved `user_data`
  key; Locate; the privacy allowlist.
- `tests/python/test_pump_sections.py`: one `PhSupportiveDevice` per pair with every value, the chosen profile surviving
  the type; the reload and conformance; tampered rows, a lost pump and an unreported Pump id refused, another section's
  supportive device passing; unequal pairs under one identifier refused; ten bad record values block their pair.
- `tests/python/test_pumps_phx_round_trip.py` (`phx`): the three cases above.
- `tests/mechanical_pump_panel_test.js`: the subtab, pill and columns; a type change and a power edit guarded, a
  negative power held; the disclosure (pressed states, "From type (Winter)", an override sent and refused, the factor,
  From type as null); a factor off 1 pressing the arrow, the open list kept through a repaint and following a type
  change; New with the Tag only; the picker; delete with clearing; Locate.
- `tools/ui-preview/mechanical_checks.cjs`: a Pumps step (a type in place, the internal heat gains, Serves beside a
  Zone's others, New, delete with clearing) and the tab at 1280 x 800, 420 x 732 and 360 x 520; screenshots in
  [p4-10/](p4-10/).

## Gate

`make ci` on Ruby 3.2.2 at `732ae216` (chained into its commit) and on Ruby 2.7.2 (`make ci RUBY=$(rbenv prefix
2.7.2)/bin/ruby`) on the same tree, each: "Ruby suite, 10 processes: 3435 runs, 48169 assertions, 0 failures, 0 errors,
1 skips"; JS 1208 pass, 0 fail; Python "445 passed, 1 skipped"; hostkit "48 runs, 268 assertions, 0 failures"; "RBZ
verified: 780 files, ... 27409404 bytes installed" (2.7.2: 27409398), 590,596 under the 28,000,000 ceiling (P4-09 left
27,358,492). The first 3.2.2 run stopped on the runtime manifest and the shipped guide, both stale after the review
fixes; regenerated before the passing run.

Also: `make ui-checks` all 39 scripts exit 0 (`mechanical_checks.cjs` with the Pumps step; `header_checks.cjs`
passed); `uv run --group phx pytest tests/python`: "445 passed, 1 skipped" (`test_map_borders.py`,
PH_COMPOSER_MAP_DATA unset), the PHX round trips 21 executed, 0 skipped (3 new); `uv run tools/runtime/vendor.py
--refresh-manifest` "Runtime verified: 211 assets, 8 wheels, 23059331 bytes".

Final head `07e4a7bf` (after both review cycles): `make ci` on Ruby 3.2.2 (chained into its commit) and 2.7.2:
"Ruby suite, 10 processes: 3437 runs, 48212 assertions, 0 failures, 0 errors, 1 skips"; Python "445 passed, 1
skipped"; "27412194 bytes installed", 587,806 under the ceiling. `make ui-checks` 39 of 39 scripts exit 0 on this head.

## UI polish review

Against `ph-composer-ui-polish`: the Pumps table is the shared `EquipmentTable`; the disclosure is the Ventilator's
anchored bubble, headed "Internal heat gains of" its Tag, one field per value applying at once, no Apply or Cancel; the
type is the tables' enum pill; Power and Operation carry their units in the header; Tag pinned, identity behind
Columns; the page header's one primary action is New Pump; no new kit part or CSS, so no Design System re-sync. No
sideways scroll at the three panel sizes ([internal heat gains](p4-10/pumps-internal-heat-gains.png),
[360 x 520](p4-10/pumps-360x520.png)). Host review owed to MS3.

## Review

Sonnet adversarial read before the gate: no P1 or P2, 9 P3. Fixed: a refused Spaces read in the preflight no longer
drops the pump rows (test); the two-Segment assertion now checks P-1's Zones; the profile list is redrawn only when its
labels change, so a repaint keeps it open (test); panel tests for the factor's pressed state and the type change; the
docs' arrow wording and the guide's row findings; the Pump id pattern matches whole. The evidence file (this one) was
owed. Declined: the preflight and export counting Spaces by different keys; they differ only for a Space whose stored
Zone is stale, which Spaces blocks as `space.zone_missing` or `space.outside_zone`.

Codex gpt-6.2-sol cycle 1 on `2ff8a47d` ([review](https://github.com/ph-composer/ph-composer-skp/pull/574#pullrequestreview-6042810257)):
1 P1, 3 P2, all fixed in the next commit. Fixed: a choice in the disclosure now always shows the latest snapshot after a
refusal, so the next write is guarded by the value shown (panel test reproducing the stale guard); the preflight counts
Spaces as the export does, a Space inside a left-out Zone leaving with it (Ruby test reproducing the miss); the
no-Spaces finding is one per pump naming each Zone, so same-named Zones cannot collapse into one note; delete with
clearing asserts one Undo step that restores the pump and both Zones' lists.

Codex gpt-6.2-sol cycle 2 on `68f0a5fb` ([review](https://github.com/ph-composer/ph-composer-skp/pull/574#pullrequestreview-6043033949)):
1 P1, 3 P2, all fixed in the next commit, which merges after the two-cycle cap unreviewed. Fixed: a unit field in the
disclosure with no draft now follows a newer snapshot after a `target.changed` refusal and keeps its message, so a retry
is guarded by the value shown (panel test failing on the old code); the no-Spaces message says PHX reads the pump
through another Room in the same Building Segment; Power and Operation use new `electric_power` and `kilohours`
quantities (W and kh/yr in both systems) so the regional number format applies (panel test with comma decimals; both
unit registries and the shared vectors gain them); the Spaces projection keeps rows for exported Zones only, so a
Space beside its Zone naming a left-out one gives no row (no dedicated test: the row was invisible to every reader).
