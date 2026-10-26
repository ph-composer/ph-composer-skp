# Phase 3a, Spaces: what the merged foundation changed, and the decisions that follow

DATE: 2026-10-16
STATUS: Scoped. D3a-1 to D3a-18 answered or superseded on 2026-10-15; D3a-19 and D3a-20 answered 2026-10-16; the interview record confirmed the same day. Part 1 is findings read from source on `main` at `70c340f` and the predecessor at `f358ebf`, re-verified against `87bdc62` in Part 1b. D3a-13's mechanism exists on `main`.
AUTHOR: Ed May, BLDGTYP, with Claude
ISSUE: [#133](https://github.com/bldgtyp/ph-composer/issues/133)

The [Spaces PRD](PRD.md) was interviewed on 2026-09-18, before the foundation existed and
before Phases 1 and 2 were built. It says its PLAN "follows the overlay spike and the foundation
transplant". This file is the review of that PRD against what is now on `main`. Part 1 lists what
differs. Part 2 lists the choices the differences force. The bindings are in
[CONTRACTS.md](CONTRACTS.md).

Paths are relative to `src/ph_composer/` unless stated. Predecessor paths are relative to
`../ph-navigator-sketchup/src/ph_navigator_sketchup/`. "Read from source" means the file was read,
not that the consequence was reproduced in a test or on a host. Nothing in Part 1 was reproduced.
P3a-01 reproduces each finding it depends on before acting on it.

Thermal bridges has no rows here; it is [Phase 3b](../phase-03b-thermal-bridges/DECISIONS.md). The
ids here were renumbered on 2026-10-03 when Phase 3 split: D3-1 to D3-12 became D3a-1 to D3a-12
and stages P3-01 to P3-12 became P3a-01 to P3a-12. F ids are unchanged.

## Part 1: findings

### Foundation the PRD assumed and that did not land

| # | Finding | Consequence for Spaces |
| --- | --- | --- |
| F1 | No deferred-reconciliation primitive exists. The PRD's disposition says the generic `PendingWork` and `UndoLedger` "land with the foundation transplant". They did not: `context/TECH_STACK.md`, "Observers report; deferred work mutates", describes them as the predecessor's, and a search of `core/` and `session/` finds only `session/timer.rb` (`CoalescedTimer`). The one worked example of deferred work is `Zones::Names::State` (`features/zones/zone/names.rb`) | The plan owns them. P3a-03 ports `reconciler/pending_work.rb` (64 lines) and `undo_ledger.rb` (81) as shared primitives that name no feature, with Spaces as the first user. Where they live is D3a-4 |
| F2 | Nothing assigns `model.active_path`. `context/TECH_STACK.md`, "Treat the active editing path as data", requires exactly one module to do so and a test that refuses any other. In the predecessor that module was `Spaces::ActivePath`, and Assemblies and Windows called into it | Under the layering (D2-1) Spaces is layer 3 and nothing below it may name it. The single writer is a foundation module, Spaces is its first caller, and the refusing test lands with it in P3a-03 |
| F3 | Nothing writes lock state, and no feature subscribes to `:pre_save` or `:post_save`. The host events exist (`session/host_observers.rb`, `Sessions::HOST_EVENTS`) | Volume protection, exit protection and the pre-save rule are first of their kind here. P3a-03 owns them and gets the stronger review |
| F4 | Identity is `Records::Identity`: a prefix and twelve characters, stored through `Records::EntityStore` and described with a `Records::ReferenceTarget`. The PRD says "a UUID ... as the predecessor's `identifiers.rb` issues it" | Bind to the foundation: `spc_`, `vol_` and `fsg_` ids. `identifiers.rb` (18 lines) is dropped, not ported. The PRD's Records section and disposition row are corrected when Ed confirms D3a-2 |
| F5 | There is no generic `duplicate_identity` finding and no Make independent. Three feature-local repairs exist: `zones.repair_identity`, `SplitIdentityRepair`, and Windows' `IdentityPlan` with `IdentityStep` | Spaces needs a fourth. Local or promoted is D3a-3 |
| F6 | Ruby `core/units.rb` has no `volume` and no `airflow` quantity. The panel's `html/unit_tables.js` has both (m3 and ft3; m3/h and cfm) | The Ruby rows are added in P3a-01. Ruby still formats no unit-bearing text; the rows exist for the Ruby length and number readers and for the report |
| F7 | The record engine has no migrations and treats an unknown key as unreadable (Phase 2 F6) | All three Spaces records ship version 1 with their final field set in P3a-02, the airflow fields included, although the airflow screens arrive in P3a-08 |

### Zones and the Face walk

| # | Finding | Consequence for Spaces |
| --- | --- | --- |
| F8 | `Zones::Occurrences.walk_faces` descends into every Group inside a Zone, skipping only a Group that carries a Zone record and a cutting component (`features/zones/zone/occurrences.rb:325-336`). `export/geometry_snapshot.rb` walks the same way. D2-5 covered cutting components only | A Space group sits inside its Zone group, so every Floor Segment face would be reported as an unclassified Zone Face: offered to Suggest classification, reachable by the Shift-click flood, seen by Solve and captured for export. Zones needs a host-level rule that names no feature before the first Space is created, exactly as D2-5 preceded the first window unit. See D3a-1 |
| F9 | The Zone stamp store (`ph_composer.zone_stamp`) exists, and `context/CONTRACTS.md` already lists "Space Groups when they exist" as a stamped entity. Restore Zone reads Face stamps only | The stamp on a Space group is the natural marker for D3a-1's rule. P3a-04 extends Restore Zone and orphaned-contents detection to Space stamps (zones Q14) |

### Colour-by and the viewport

| # | Finding | Consequence for Spaces |
| --- | --- | --- |
| F10 | A Colour-by entry needs a live entity; `colour_by/tessellation.rb` draws Faces and recurses into Groups and Components. Derived geometry is unsupported (Phase 2 F20). There is no readout registration: the HUD is drawn by `colour_by/overlay.rb` from the legend alone | The volume preview prism, Space labels and selection totals all need the extension D2-6 deferred to this phase. P3a-05 builds it as a foundation stage before any Spaces mode needs it. Its shape is D3a-5 |
| F11 | `entity_kind` is already open prose in `colour_mode` | Spaces Q22's "open entity kind" needs no change. Only derived geometry and readouts are new |
| F12 | There is no toolbar; nothing uses `UI::Toolbar`. There is no shared drawing-tool state: Classify and Place each call `model.select_tool`, and the panel's pressed state is per feature | The PRD's "beside the Classify tool on the toolbar" and "one of the two is pressed at a time" describe things that do not exist. See D3a-7 |
| F13 | `core/pick.rb` and `core/drag_set.rb` already carry comments naming Mark floor as a later user | Mark floor reuses both unchanged. P3a-06 confirms it adds nothing to either |

### Panel

| # | Finding | Consequence for Spaces |
| --- | --- | --- |
| F14 | `html/index.html` has a disabled "Spaces · Planned" tab and no Spaces pane. The Zones / Faces tree (`html/features/zones/overview.js`) is a fixed two-level Zone to Face projection that does not call `composeTable`, so another feature cannot contribute child rows to it | Spaces Q11 and face-assignment Q11 said "one tree" with the faces table as a sibling under each Zone. As built, that tree would have to be rewritten or the Spaces feature would have to edit Zones' panel module. See D3a-6 |
| F15 | `html/inventory_grid.js` has range selection, TSV paste and fill; `html/record_edits.js` has inline drafts. No right-click cell menu exists anywhere in `html/` | Range edit and paste are reuse. Select by (Q12) is a UI kit addition in P3a-07 |
| F16 | Units follow-up U1-F1: a unit switch on a 300-Space table repainted every cell at a median 513 ms in the predecessor, and the units packet leaves the optimization with Spaces "if measurements justify it" | P3a-07 measures it on the new table and records the number before deciding |

### Metrics and export

| # | Finding | Consequence for Spaces |
| --- | --- | --- |
| F17 | The predecessor's flatten rule lives only in Python (`spaces/geometry.py`, `authored.py:64-77`). It flattens a face whose z-spread is under 1 mm and omits one whose spread is larger. Ruby `metrics.rb` uses true `face.area` | Spaces Q14 and Q23 allow any non-horizontal face and use its projected horizontal area in metrics, preview and export alike. That is a replacement in both languages, not a port. The PRD's disposition says "Adapt ... adds the floor projection"; the omit branch is removed |
| F18 | The Python `Attachment` already names `ROOM` as a host, and `ApertureSection` is the working example of a section that attaches to an object another section built (`python/ph_composer_translation/sections.py`, `window_sections.py`) | The Spaces section attaches each `Space` to its Zone's Room with `Attachment(ROOM, key=zone id)`. The PRD's "open foundation question" about a section dependency is closed, as assemblies' was by Phase 2 F9 |
| F19 | PHX is not vendored (eight wheels, none PHX) and METr is deferred by D12 | Every "through PHX" and "PHX writes the METr rooms" step in the PRD's acceptance moves to [metr-export](../../features/unscheduled/metr-export/README.md), as Phase 2 F13 did. Spaces closes on HBJSON reloaded in the pinned honeybee stack |
| F20 | honeybee-ph's `SpaceProperties.has_ventilation_flow_rates` is `any([_v_sup, _v_eta, _v_tran])`, which is false when all three are 0. PHX tests each rate with `is not None` (`PHX/from_HBJSON/create_rooms.py:133`). Read from source in the sibling checkouts; not run, and the pinned honeybee-ph 1.33.65 was not checked against it | A user-specified Space with three explicit zeros stores three zeros and reads back as three zeros, but that honeybee-ph property reports false. P3a-10 asserts on the stored `_v_*` values, not on the property. Nothing here is called a defect; the consumer consequence belongs to metr-export when it resumes |
| F21 | Ruby registration checks that a contributor's section reads are declared and owned by a required feature, and has no cycle check among section reads (R05 item 2). `ZoneSection` builds `Room(id, [])` when every Face is omitted (R05 item 1) | Both are settled in P3a-01, before the Spaces contributor exists |
| F22 | The export report has a per-contributor hook: `report: ->(ResultView, display_units) { [html_section] }` | The Spaces schedule per Zone is one contributor's report section. No report seam is added |

## Part 1b: re-verification against `main` at `87bdc62`, 2026-10-15

About 240 commits landed between `70c340f` and `87bdc62`: the Zones / Faces table-first layout
(PR #73), managed Segment and Level choices (PR #80), Ruby units (PR #84), automatic Zone
independence on copy (PR #97), and the architecture refactoring program (PRs #99 to #126).
Every finding was read again from source; nothing was reproduced. Part 1 above is kept as
written at `70c340f`; this table is the current reading.

| # | Now | Current state and consequence | Evidence on `87bdc62` |
| --- | --- | --- | --- |
| F1 | Holds, narrowed | Still no `PendingWork`, Undo ledger or reconciler class. New and reusable: `HostFollowUp` runs a registered action's handler into one proposal, joins the user's step as a transparent operation, accepts only restorable steps and never aborts; the Zones copy watcher is a worked deferred pass over `CoalescedTimer` that drops its pending pass on Undo and Redo; feature state objects answer `pending?` and `settle`. P3a-03 builds on these and ports only what is still missing | `shell/host_follow_up.rb:5-92`; `features/zones/zone/copy_watch.rb:57-65`, `:96-105`, `:173-175`; `features/zones/zone/names.rb:55-100` |
| F2 | Holds | No `active_path=` assignment and no edit-context module | `context/TECH_STACK.md:70-72` |
| F3 | Holds | Nothing writes lock state; `:pre_save` and `:post_save` are published with no subscriber | `session/host_observers.rb:41-47` |
| F4 | Holds | `prefix_` plus twelve characters; `Identity.derived` gives deterministic ids, which Make Zone independent uses so a preview's ids hold at apply | `core/records/identity.rb:11-52` |
| F5 | Changed | Still no shared `duplicate_identity` finding. Now on `main`: Make Zone independent, the automatic copy watcher, `Units::ZoneCopy`, and two declared composition seams: `transition_contributor` (a child joins `ph_composer.zones.occurrence_independent` with restorable steps in the Zone's own proposal) and `proposal_participant` with `request.participate`. D3a-13's mechanism exists and Windows is its first adopter. D3a-3 and D3a-14 are refreshed for this | `shell/handler_request.rb:126-142`; `shell/registry.rb:457-464`; `features/windows/units/zone_copy.rb:12-35`; `context/CONTRACTS.md`, "Compound proposals" |
| F6 | Settled | Ruby `volume` and `airflow` quantities merged through PR #84. H2 is done | `core/units.rb:37-39`, `:54-57` |
| F7 | Holds | No base-record migrations. Structured extension payloads now have their own migration path; Space records do not need it | `core/records/engine.rb:156-174` |
| F8 | Holds | `walk_faces` still descends into every Group except a Zone or a cutting component; the export snapshot and `core/face_capture.rb` (PR #121) follow it. D3a-1 stands | `features/zones/zone/occurrences.rb:325-338`; `export/geometry_snapshot.rb:113-123` |
| F9 | Holds | Restore Zone reads Face stamps only. The stamp is now schema 2: `zone_id`, `building_segment_id`, `level_id` and `choice_evidence`; schema 1 names are still read | `features/zones/zone/repair.rb:263-306`; `features/zones/zone/schema.rb:96-105` |
| F10 | Holds, contract grew | Still no derived geometry or readouts. Since `70c340f` a mode may declare a `group` (Assembly and Window Type share `construction`), the service has an occurrence mask (`filter`), and the Zones / Faces table puts each mode's toggle in its column header. Phase 3b's deferred G-03 proposes a separate `ColourBy::LineEntry`, which competes with D3b-11's use of P3a-05 `derived` segments; see D3a-5 | `shell/registry.rb:425`; `colour_by/service.rb:19`, `:161-175`; `geometry-contribution-contracts` STATUS |
| F11 | Holds | `entity_kind` is free prose ("zone", "face", "window_unit") | `features/zones/colour_modes.rb:17-25` |
| F12 | Holds | No toolbar, no shared tool state. Classify's palette is column-scoped in the Zones / Faces table; the floating selection bar holds bulk Face edits | `html/features/zones/classify.js:220`; `html/selection_bar.js` |
| F13 | Holds | Both comments name Mark floor | `core/pick.rb:13`; `core/drag_set.rb:12` |
| F14 | Changed | The disabled "Spaces" tab is still there with no pane. Zones / Faces is no longer a tree with an inspector: it is one full-width table with an in-place Zone and Face hierarchy, editable Zone cells, Colour by and value filters in column headers, a checkbox set separate from Locate, and a floating selection bar (zones-table-first, D1 to D9). It sets no `tableId`, so no feature can add columns or rows to it. D3a-6 and D3a-11 are refreshed; P3a-07's tree, inspector and Level rail predate this pattern | `html/index.html:19-27`; `html/features/zones/overview.js`; [zones-table-first](../zones-table-first/README.md) |
| F15 | Changed | Range selection, TSV paste and fill remain in `inventory_grid.js`; still no right-click menu. New: per-column menus for sort and value filter (`column_menu.js`) and table contributions (`table_contributions.js`) for tables that set a `tableId` | `html/inventory_grid.js:38-78`; `html/column_menu.js`; `html/table_contributions.js` |
| F16 | Holds | U1-F1 unmeasured, still allocated to P3a-07 | `planning/features/cross-phase/units/STATUS.md` |
| F17 | Holds | Area is the true polygon area; no projection exists | `core/face_geometry.rb:42-67` |
| F18 | Holds | `Attachment(ROOM)` is defined and resolved but no section uses it yet; Spaces would be the first | `python/ph_composer_translation/sections.py:46-70`; `assembly.py:36-56` |
| F19 | Holds | Eight wheels, no PHX | `vendor/manifest.json` |
| F20 | Holds | honeybee-ph pinned at 1.33.65 | `vendor/wheels/` |
| F21 | Changed | Item 2 settled: registration refuses export sections that require each other as `registration.cycle` (PR #122). Item 1 holds: `ZoneSection` builds the Room from whatever Faces survive, with no empty guard. H3 is done; H4 remains with P3a-01 | `shell/registry_validation.rb:387-411`; `python/ph_composer_translation/model_sections.py:261` |
| F22 | Holds | The per-contributor `report:` hook is unchanged | `shell/registry.rb:412`; `export/report.rb:29` |

### New since `70c340f`, not covered by F1 to F22

| # | Finding | Consequence for Spaces |
| --- | --- | --- |
| F23 | Entity owners publish `extension_status` in their reads and one `update_metadata` action each (Zones, Faces, Window Units), with the shared rules in `core/records/metadata.rb` (EC-01, EC-02) | Spaces, Volumes and Floor Segments follow the same canon: `extension_status` in `list`, and one `update_metadata` action per record kind or one for all three. Bound in CONTRACTS section 3 |
| F24 | `user_data` passes through to HBJSON "only where its owner opts in" (`context/CONTRACTS.md`, Records, Export row). Ed opted in Zone, Face, Window Unit and Assembly on 2026-10-13 (PR #125). A user key named `ph_composer` blocks | The PRD's "None of it is exported" was written before the rule existed. Whether Spaces opts in is D3a-15 |
| F25 | Export contributors can claim another feature's extension payloads (`entity_projections:`, EC-03) | Not needed by Spaces. A later feature that stores data on Spaces claims it the same way, so the Spaces section does not need to know about it |
| F26 | The Zones copy watcher tells a native copy from a cut and paste: a Group added with a Zone id that another live occurrence holds is a copy, and a cut and paste leaves no duplicate. It makes the copy independent through `HostFollowUp` in the same Undo step, and leaves a copy whose path crosses a ComponentInstance alone (copied-Zone D-1, D-7) | PRD Q20 says "a deferred pass cannot tell a copy from a cut and paste". Zones now does exactly that on the host. D3a-14 asks whether a standalone Space copy should follow the Zones precedent |
| F27 | Native-acceptance case prefixes in use are `A`, `R`, `UXK`, `E`, `HGUI`, `PTAB`, `ZO`, `UXR` and `GH` | `S` is still free for S01 to S12 |

## Part 2: decisions for Ed

Each row says whether it is a UI choice or a code-structure choice, gives a recommendation and
names the stage it blocks. Recommendations for D3a-3, D3a-4, D3a-5, D3a-6, D3a-9 and D3a-11 were
refreshed on 2026-10-15 against Part 1b; D3a-14 to D3a-18 are new. Ed answered every row on
2026-10-15: the UI rows in the UI and UX discussion, the rest one at a time afterwards.

| ID | Kind | Question | Recommendation | Blocks | Ed's answer |
| --- | --- | --- | --- | --- | --- |
| D3a-1 | Code | What does Zones do with a Space group inside a Zone? (F8) | One host-level rule in Zones that names no feature: a Group inside a Zone that carries a Zone stamp is a nested authoring container, and its Faces are not Zone Faces. The walk, the export snapshot, Suggest, the Shift-click flood and Solve skip it. Spaces writes the stamp at creation, which `context/CONTRACTS.md` already expects. Zones still never names Spaces. The alternative, Zones asking "is this a Space?", would make layer 2 depend on layer 3 | P3a-01 | Ed, 2026-10-15: as recommended. Envelope Faces stay loose in the Zone group; only Space groups carry the stamp, so the rule adds no nesting for the user |
| D3a-2 | Code | Which identity do Space, Volume and Floor Segment carry? (F4) | The foundation's: `spc_`, `vol_`, `fsg_` ids through `EntityStore`, with a `ReferenceTarget` each. No UUID. This amends the PRD's Records section; the honeybee-ph identifiers still derive from the id | P3a-02 | Ed, 2026-10-15: as recommended |
| D3a-3 | Code | Is `duplicate_identity` with Make independent Spaces-local or a shared contract? (F5) | Refreshed 2026-10-15. The Zone-copy half is no longer open: Spaces joins `ph_composer.zones.occurrence_independent` through `transition_contributor`, as `Units::ZoneCopy` does, and builds nothing shared for it. For a standalone Space, Volume or Floor Segment copy, keep the repair Spaces-local: a pure plan and a restorable step shaped like Windows' `IdentityPlan` and `IdentityStep`, reused by the Zone-copy contributor and by whatever D3a-14 decides. Zones, Windows and Spaces would then be three repairs with different keeper rules; record the consolidation as a refactor candidate when P3a-04 closes. The reason is design evidence, not protecting existing code | P3a-04 | Ed, 2026-10-15: as recommended, Spaces-local |
| D3a-4 | Code | Where do the edit-context writer and the deferred-work primitives live? (F1, F2) | Refreshed 2026-10-15. In `session/`, naming no feature: one edit-context module that is the only `active_path=` writer. For deferred work, reuse what `main` now has (`CoalescedTimer`, the `pending?` and `settle` convention, `HostFollowUp` for restorable transparent writes) and add only what is missing: a keyed coalescing queue, and the Undo ledger for protection writes that are not record changes (lock state and `home_transform` do not fit `HostFollowUp`'s record-step rule as written; P3a-03 confirms). Spaces composes them in its own reconciler in `features/spaces/`. `Zones::Names::State` and the copy watcher are not migrated in this phase; with Spaces they become three callers, and the migration is a refactor candidate when P3a-03 closes | P3a-03 | Ed, 2026-10-15: as recommended, `session/` |
| D3a-5 | Code | What is the Colour-by extension, and are the Window Type operation marks built with it? (F10) | Two additions to the existing contract and no new framework. One: an `Entry` may carry `derived`, a list of world-space polygons and segments the service fills and outlines in the entry's colour, with or without a backing entity. Two: `FeatureScope#colour_readout`, a separately registered pure projection that returns viewport text anchors or HUD lines, shown with any mode and with none. Build the operation marks in the same stage as the second real user: a contract proven only by a synthetic mode and one feature is not proven, and D2-6 asked for one design against both. Added 2026-10-15: the deferred geometry stage G-03 proposes a separate `ColourBy::LineEntry` for Edges, while Phase 3b's D3b-11 draws Edges as `derived` segments. Settle that once, in P3a-05's design note, with thermal bridges as the third named user, so Colour-by does not grow two line primitives. The design note must also fit the column-header toggles and mode `group` added since `70c340f` | P3a-05 | Ed, 2026-10-15: as recommended. `derived` and readouts; no `LineEntry`; operation marks built in P3a-05 |
| D3a-6 | UI | Where does the Space tree live? (F14) | Refreshed 2026-10-15. On its own Spaces tab, enabling the reserved pane, built in the table-first pattern Zones / Faces now uses rather than the tree and inspector this row first assumed: one full-width table with a Zone, Space, Volume, Floor Segment hierarchy column, editable cells, Colour by and value filters in the column headers, a checkbox set separate from Locate, and the floating selection bar for bulk edits. The airflow balance view is a second subtab. The Zones / Faces table stays unchanged. This amends spaces Q11 and face-assignment Q11 ("one tree") and settles zones Q13. The two tables answer different questions, envelope versus rooms, and Zones / Faces has no row contribution point | P3a-07 | Ed, 2026-10-15: neither its own tab nor a tree inside Zones / Faces. Spaces is a view of the Zones tab, beside Faces (D3a-16) |
| D3a-7 | UI | How do Mark floor and Create Space start, with no toolbar? (F12) | From the Spaces tab, the Extensions menu and the right-click menu, as Classify and Place start. A toolbar button waits with [zones-entry-points](../../features/unscheduled/zones-entry-points/README.md) E1 and covers all three tools together. "One pressed at a time" is met by SketchUp's single active tool: each panel palette already derives its pressed state from its own tool's `active?`, so no shared tool-state rule is added | P3a-08 | Ed, 2026-10-15, accepting the mockup: Mark floor starts from the paint choices in the Weighting factor column menu, as Classify's column-scoped paint does; Create Space is in SketchUp's native context menu, as Make Zone is. No toolbar, no palette |
| D3a-8 | Code | How does the equipment packet regroup the airflow balance view later? | Build the grouping as a pure function the balance read takes as an argument, with Zone grouping as the only caller. Do not add a registration point now. The PRD's promise that equipment "edits nothing in this feature's folder" is kept by adding the registration when the equipment packet is planned, against its real shape | none | Superseded 2026-10-15: there is no separate balance view. Balance by Zone is on the Spaces view's Zone rows; balance by ventilator belongs with the Ventilation assignments, which may become a Systems tab. No grouping function or provider |
| D3a-9 | Code | Is the Spaces export section required for export? (R05 item 4) | Yes. A Space that fails to translate blocks the canonical pair, consistent with the PRD's blocking findings. So Spaces is not the first optional attaching section. R05 item 4 is allocated to Phase 3b's P3b-08, whose thermal-bridge section is the first optional one (D3b-20) | P3a-10 | Ed, 2026-10-15: required |
| D3a-10 | Code | Does a blocked run report `construction_usage`, `window_face_areas` and the Spaces schedule? (R05 item 3) | A blocked run reports them, and the report says in one line that the figures come from a run that published nothing. Hiding them removes the numbers a user needs to fix the block | P3a-10 | Ed, 2026-10-15: shown, labelled |
| D3a-11 | UI | Does the Spaces tab keep the predecessor's Level rail and saved column layout? | Refreshed 2026-10-15. Drop the Level rail: Level is a managed Zone choice (PR #80), and the Level column's header filter does the rail's job in the table-first pattern. Keep column layout only to the extent the shared table already persists it; add no Spaces-specific layout store. `docs/PRODUCT.md` still describes the rail and is corrected when P3a-07 lands | P3a-07 | Ed, 2026-10-15, accepting the mockup: no Level rail. Level is the Zone's column, hidden by default in the Spaces view, with its header filter. Column layout follows the shared table |
| D3a-12 | UI | The PRD warns where supply and extract "differ by more than 10 percent" and does not say of what | Of the larger of the two sums: warn when the absolute difference exceeds 0.10 times the larger. A Zone with one sum at zero and the other not is always warned | P3a-07 | Ed, 2026-10-15: of the larger sum |
| D3a-14 | UI and behavior | A user copies a Space, Volume or Floor Segment natively, outside a Zone copy. Is the copy made independent automatically? (F26) | Follow the Zones precedent for a Space Group: a copy watcher in Spaces treats a Space Group added with an id another live occurrence holds as a copy and makes it independent through `HostFollowUp` in the same Undo step, with the next free number; a cut and paste leaves no duplicate and is untouched; a copy through a ComponentInstance is left alone with the existing finding. Keep the blocking `duplicate_identity` finding and the explicit Make independent repair for the cases the watcher declines and for Volumes and Floor Segments until P3a-04 measures their copy gestures on the host. This amends Q20's "no silent reissue", which rested on a premise Zones has since disproved on the host | P3a-04 | Ed, 2026-10-15: yes |
| D3a-15 | Code | Does Spaces opt in to the `user_data` pass-through to HBJSON? (F24) | Yes, for all three records, on the honeybee-ph object each maps to (`Space`, `SpaceVolume`, `SpaceFloorSegment`), beside the reserved `ph_composer` key, as Zones, Faces, Window Units and Assemblies do. P3a-01 confirms each honeybee-ph class carries `user_data` through `to_dict` at 1.33.65; any class that does not is recorded and left out. Amends the PRD's "None of it is exported" | P3a-10 | Ed, 2026-10-15: yes, all three |
| D3a-16 | UI | How is the Zones tab organized now that Spaces lives there? | Asked by Ed. See "UI and UX discussion" below | P3a-06, P3a-07 | Ed, 2026-10-15: one Zones tab with views, as recorded below |
| D3a-17 | UI and code | What is the factor that decides whether a Floor Segment's area counts, and how is it entered? | Asked by Ed. See "UI and UX discussion" below | P3a-02, P3a-07, P3a-08 | Ed, 2026-10-15: "Weighting factor", a number from 0 to 1 with quick picks |
| D3a-18 | UI | Spaces Q12 asked for Select by from a right-click on any cell. In the table-first pattern, a column's value filter plus the header checkbox ("check every row the filter shows") does the same job with no cell context menu. Is that enough? | Yes. Drop the cell context menu (H9) and the `select_by` command; the column menu's Show list and the check-all box are Select by. A value the user wants to select by is always a column value, so nothing is lost | P3a-07 | Ed, 2026-10-15: yes, filter and check-all; no cell menu |
| D3a-19 | Behavior | SketchUp autosave fires `onPreSaveModel` and `onSaveModel` as a save does (observed in the P3a-03 host run, 2026-10-15). The predecessor's save rule, which this packet keeps, protects the open Volume before the save and closes it afterwards, so every autosave would lift the user out of a Volume they are editing. Keep that, or after a save unlock the Volume again and leave the user in it? | Keep the predecessor's rule until Ed decides: the saved file must hold the Volume protected, and closing after the save is what its evidence covers. Unlocking again would keep the user in place at the cost of one more transparent write after every save | P3a-03 follow-up; no stage blocked | Ed, 2026-10-16: B, after a spike. The spike (2026-10-16) found that the lock in `onPreSaveModel` is what strands the user: SketchUp does not restore a context with a locked Group on its path. Ed then chose B3: do not lock the open Volume at a save, so the host keeps the user in it with nothing written, and protect a Volume saved unlocked when the Model is next opened. B, which re-enters after the save, added an Undo entry the user's next Cmd+Z would spend leaving the Volume |
| D3a-20 | Delivery | The installed footprint reached 23,994,083 bytes at P3a-12, under 6 KB short of the 24 MB ceiling in `tools/runtime/vendor.py` (`installed_ceiling_bytes`). The pinned runtime and wheels are fixed; the extension's own code grows about 1 MB a feature phase. Raise the limits, shrink the payload, or budget growth? | Raise the target to 24 MB and the ceiling to 26 MB, and add a growth budget: a phase that adds more than 1.5 MB installed needs a recorded decision | Phase 3b packaging (T09) | Ed, 2026-10-16: yes, raise the limits and add the growth budget |

Ed confirmed the interview record in the Spaces PRD, Q1 to Q24 as amended, on 2026-10-15.

## UI and UX discussion, 2026-10-15

Ed's direction, worked through a mockup ([mockups/](mockups/README.md)). It answers D3a-6, D3a-7,
D3a-11, D3a-14, D3a-16 and D3a-17 and supersedes D3a-8.

**D3a-16, Zone views.** The Zones / Faces tab becomes the Zones tab. Data managed per Zone is shown
in views of one Zones table, chosen from a view row:

| View | Rows under each Zone | State |
| --- | --- | --- |
| Faces | The Zone's Faces, as the Zones / Faces table shows them today | Exists; moves onto the view contract in P3a-06 |
| Spaces | Space, Volume, Floor Segment | This packet, P3a-07 |
| Occupancy, Electric loads and appliances, Lighting, Hot water | None expected: loads and schedules sit on the Zone (honeybee-energy's Room) | Future packets |
| Ventilation system assignments, Heat pump assignments | Equipment assignments | Future; Ed may instead flip these into Systems tabs that list the Zones each unit serves. Decided when equipment is planned |

- The view row is the shared subtabs nav, the same part Window Types / U-Values / Schedule uses,
  placed above the "Zones" heading as Window Types places it. No new visual style.
- A view is listed only once it is built. Planned views are not shown.
- Shared by every view: the Zone rows and the Zone Name column, the text filter, which Zones are
  expanded, which rows are checked where the row exists in both views, and Locate. Each view
  supplies its own child rows, columns, column-header Colour-by toggles, selection-bar controls and
  settings.
- Views are registered contributions. Zones hosts them and names none; Faces registers through the
  same contract as Spaces. The contract must also admit a view with no child rows (Occupancy) so
  it is not shaped around two tree views. P3a-06 builds it.
- The Spaces view follows honeybee-ph's nesting: rows are Zone (the Room), Space, Volume
  (`SpaceVolume`) and Segment (`SpaceFloorSegment`). `SpaceFloor` is exactly one per Volume; it is
  stored (`floor_id`) and has no row. Columns: No., Name, Floor area (`floor_area`), Weighting
  factor, Weighted area (`weighted_floor_area`), Height, Net volume (`net_floor_area` times
  height), Supply, Extract, Transfer. Net area factor, Building-Segment and Level are hidden by
  default (Table options). Height is edited on Volume rows; the Space row shows honeybee-ph's
  floor-area-weighted `avg_clear_height`, read only. Zone rows carry the sums and the airflow
  imbalance marker. The table needs a fourth tree tier.

**D3a-17, Weighting factor.** The neutral term, and honeybee-ph's own field name
(`weighting_factor`), replaces "iCFA factor" on screen and in the record. The weighted area is
iCFA for a Phius model and TFA for a PHI one; the label stays neutral. The cell is a number from 0
to 1, not the two Counts / Does not count chips of Q4, so PHI's partial weights fit. Quick picks
are 1.0 and 0 always, plus every other value the model already uses: they are the paint choices
in the column menu that start Mark floor, and Colour by weighting factor shows one band per value.
Amends Q4.

## PRD amendments that follow

Applied to [PRD.md](PRD.md) only after Ed answers, one change per decision. The rows marked
applied were applied on 2026-10-15.

| From | Amendment |
| --- | --- |
| F1, D3a-4 | Disposition row for `reconciler`, `undo_ledger`, `pending_work`, `session_state`: the generic primitives land in P3a-03, not with the foundation transplant. Applied |
| F4, D3a-2 | Records, Identity: foundation ids, not UUIDs. Disposition row for `identifiers`: Drop. Applied |
| F12, D3a-7 | Mark floor: no toolbar wording; the pressed-state sentence restated. Applied |
| F14, D3a-6, D3a-16 | "The model tree and the table": the Spaces view of the Zones tab. Applied |
| F26, D3a-14 | Records, "Copies (Q20)": the copy-watcher rule. Applied |
| F24, D3a-15 | Records, "`user_data`": exported on all three. Applied |
| F17 | Disposition row for Python `geometry.py`: Replace the flatten rule. Applied |
| F19 | Acceptance shape: PHX and METr steps point at metr-export. Applied |
| D3a-18 | "The Spaces view", Select by; Q12. Applied |
| D3a-8 | Airflows: no separate balance view; balance on the Zone rows. Applied |
| D3a-17 | Vocabulary, Records, Mark floor, modes and export: weighting factor as a number. Applied |

## Confirmed copy decision D3a-13

**D3a-13, confirmed by Ed 2026-10-12:** when a Zone is copied and made independent, every Space
included in that copy becomes an independent authored instance. This includes independent
storage and identities for its Volumes, Floor Segments and logical Space Floors, correct copied
Zone membership stamps, preserved ordinary values/metadata under their copy rules, and typed
references remapped within the copied collection. The original Zone and its Spaces stay unchanged.

Window Units in that same Zone follow Windows' protocol: new instances reference their existing
Window Type. Copying the Zone does not create new Window Type definitions in the same Model.
See [copied-Zone D-2 to D-6](../copied-zone-edit-refusal/DECISIONS.md).

This qualifies PRD Q20's "no silent reissue" rule: the standalone Spaces reconciler still cannot
guess which occurrence to rewrite, and standalone Space/Volume/Floor Segment copies retain their
explicit repair workflow. A proven Zone-copy gesture supplies the parent-copy scope; Spaces must
participate through its own declared copy planning/application, in that gesture's one atomic
proposal and Undo step. Zones must not learn Space schemas or rewrite their dictionaries. A
refusal/failure cannot leave a reported-independent Zone holding shared or duplicated Spaces.

Allocated to P3a-04, with S04/S12 host acceptance and S10 HBJSON read-back. Before implementation,
resolve the participation binding, child-storage isolation, typed collection mapping and failure
recovery against the copied-Zone mechanism then present. D3a-3's architecture choice remains open;
this decision specifies the result, not a new shared identity framework.

D3a-1 to D3a-12 remain open. No Spaces stage is authorized or implemented by this decision.

On 2026-10-13 Ed accepted the shared [Zone-child ownership pattern](../code-review-refactoring/ZONE_CHILD_PATTERN.md).
The [child lifecycle plan](../zone-child-lifecycle/PLAN.md) now specifies the
proposed parent transition and Windows/synthetic adopter proof. P3a-04 must reuse that accepted public
contract once implemented, rather than designing another copy framework. Spaces still owns its
collection mapping/storage and S04/S12/S10 evidence; its earlier decisions remain open. The contract is
implemented (zone-child lifecycle ZC-02 and ZC-03): a `transition_contributor` for
`ph_composer.zones.occurrence_independent`, described in [CONTRACTS.md](../../../context/CONTRACTS.md),
"Compound proposals", with Windows as the first adopter.

## Ledger

| Date | Event |
| --- | --- |
| 2026-10-03 | Drafted from a source review at `70c340f`, the predecessor at `f358ebf` and the Spaces PRD. Twenty-two findings, twelve decisions, none answered. |
| 2026-10-12 | Ed confirmed D3a-13 through the copied-Zone review: Spaces copied with a Zone become independent authored instances; Window Units remain instances of their existing Type. Q20 and P3a-04 qualified; the twelve earlier decisions and implementation gates remain open. |
| 2026-10-15 | Re-verified F1 to F22 against `main` at `87bdc62` (Part 1b): F6 settled, F21 item 2 settled, F5, F10, F14, F15 changed, the rest hold. Added F23 to F27. Refreshed the recommendations for D3a-3, D3a-4, D3a-5, D3a-6, D3a-9 and D3a-11; added D3a-14 (automatic independence for a standalone Space copy) and D3a-15 (`user_data` pass-through). No decision answered. |
| 2026-10-15 | UI and UX discussion with Ed, worked through a mockup: D3a-6, D3a-7, D3a-11 and D3a-14 answered, D3a-8 superseded, D3a-16 (Zone views) and D3a-17 (weighting factor) recorded as Ed's direction, D3a-18 (Select by) raised. PRD amendments for those applied. |
| 2026-10-15 | Ed answered the remaining decisions one at a time: D3a-1 to D3a-5, D3a-9, D3a-10, D3a-12, D3a-15 and D3a-18, each as recommended (D3a-5 with the operation marks in P3a-05). He confirmed the PRD interview record. Every PRD amendment in the table is applied. |
