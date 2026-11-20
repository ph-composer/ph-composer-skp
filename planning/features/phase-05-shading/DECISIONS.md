# Shading: findings and decisions

DATE: 2026-11-19
STATUS: Scoped. D5s-01 to D5s-17 are Ed's (2026-11-19). Every stage authorized 2026-11-19 ([STATUS](STATUS.md#authorization)).
AUTHOR: Ed May, BLDGTYP, with Claude
ISSUE: [#526](https://github.com/ph-composer/ph-composer-skp/issues/526)

Ids carry the prefix `5s`: stages `P5s-01`, decisions `D5s-01`. `D5-1` and `P5-` belong to the
post-MVP phase, which was Phase 5 before the 2026-11-15 re-order and kept its ids. Findings are
`F1` to `F13`. Acceptance rows are `SD01` to `SD07` (`SH` is taken in the native case ledger).

## Part 1: findings

Read on `main` at `d22b83e4`. The honeybee and PHX findings are in the
[research note](research/honeybee-ph-and-phx-shading.md) and are not repeated here.

| Id | Finding | Source |
| --- | --- | --- |
| F1 | PHX reads only `Model.orphaned_shades`, groups them by `display_name` and writes one opaque component per name with no interior attachment. An unnamed Shade is its own component | Research note; run on PHX 1.57.5 |
| F2 | The Grasshopper `HB Shade` component writes `is_detached: true` by default; honeybee-core's constructor defaults to `false`. PHX reads neither | Research note |
| F3 | The export model is assembled in Python by `assembly.py`, which attaches each section's objects at `MODEL`, `ROOM` or `FACE`. No section writes a Shade today. Site and Model metadata already attach at `MODEL` | `python/ph_composer_translation/assembly.py`, `composition.py` |
| F4 | A section with `required_for_export = False` is optional: an object it cannot attach is left out with a non-blocking finding. Thermal bridges and Site are the two today | `context/CONTRACTS.md`, "Translation sections and artifacts" |
| F5 | The export `GeometrySnapshot` already holds every Face in the Model, inside Zones or not, one entry per occurrence with its root path, world transform and attribute dictionaries. Faces inside a cutting component are not captured | `export/geometry_snapshot.rb` |
| F6 | Records on entities outside Zones exist: Window Units and Spaces are reached from the Model root by a root-to-entity persistent-id path | `context/CONTRACTS.md`, "Geometry records and occurrence references" |
| F7 | Id-less records exist: the Zone membership stamp and the pane stamp carry recovery data and no durable id. Nothing references them | Same section, the dictionary table |
| F8 | A Zone Face with no classification blocks export as `face.unclassified` | `features/zones/faces/export.rb`, line 79 |
| F9 | `Records::EntityStore.new(..., claims_entity: true)` marks an entity as owned: Make Zone refuses a Group holding a claimed object at any depth. Spaces claims; Zones does not | `context/EXTENSIBILITY.md`, "Native menu items"; `core/records/entity_store.rb` |
| F10 | A right-click on a closed Group selects the Group, not a Face (measured on 26.1.188, 2026-09-20). The Face menu is only offered inside an open Group | `features/zones/faces/classify_menu.rb` |
| F11 | A native menu item is declared with `feature.menu_item`; a handler that changes the Model invokes a registered action through `API.invoke` with explicit references and the read revision, as Make Zone does | `features/zones/zone/menu.rb`; `context/EXTENSIBILITY.md` |
| F12 | `faces.classify` takes a keep, set or clear intent per field. Not verified: whether clearing every field removes the Face record, so the Face reads as unclassified again. P5s-01 checks it | `features/zones/declarations/faces.rb`, line 268 |
| F13 | Mutation through shared component storage refuses across the features (`target.shared_definition`); a copied plain Group shares its contents until isolated | `context/CONTRACTS.md`, "Geometry records and occurrence references" |

## Part 2: decisions

### Scope, answered by Ed, 2026-11-19

| Id | Decision |
| --- | --- |
| D5s-01 | **Tag and pass.** The MVP tags surfaces and exports them as the shading type WUFI-Passive and METr expect. No solar or shading solver |
| D5s-02 | **Match honeybee-ph and PHX.** The export is built to what they read today: orphaned honeybee Shades |
| D5s-03 | **Names come from the Group.** A Shading Face is named for the Group or Component it sits in; loose Faces at the root are "Shading". No naming UI |
| D5s-04 | **A Zone Face may be shading.** An unclassified Face inside a Zone can be tagged; it leaves the Zone's envelope and exports as a Shade |
| D5s-05 | **Faces and Groups.** The tag is offered on Faces and on a selected Group or Component, whose Faces at any depth all export as shading |
| D5s-06 | **Menu, Colour-by and the report.** Right-click Set as Shading and Clear Shading, a Shading Colour-by mode, a Shading section in the export report. No panel tab |

### Design, answered by Ed, 2026-11-19

Ed took each question in turn, with the alternatives beside it, and chose the recommendation every
time. The alternatives he set aside follow the table.

| Id | Question | Decision | Why |
| --- | --- | --- | --- |
| D5s-07 | Does the mark carry a durable id? | No. One dictionary, `ph_composer.shading`, record `{"schema_version": 1}`, with `user_data` allowed, on a Face, Group or ComponentInstance | Nothing references a shading surface (F7). Shading is copied and arrayed constantly; an id would need a copy watcher and a repair for no benefit. The exported identifier is derived per occurrence (D5s-08) |
| D5s-08 | What is the exported Shade's identifier? | `shd_` plus a digest of the occurrence's root-to-Face persistent-id path | One Face in a Component placed three times is three Shades (F5); honeybee identifiers must be unique. The path is stable across save and reopen, so re-export gives the same HBJSON |
| D5s-09 | `is_detached`? | `true` | What a Grasshopper-built Model carries (F2). PHX ignores it |
| D5s-10 | Name details D5s-03 leaves open | The nearest enclosing named Group or instance, an instance's own name before its definition's. A Zone as that container gives the Zone's name followed by " Shading". None gives "Shading" | A shading component named exactly like a Zone would read as the Zone in WUFI-Passive. A tagged Group with no name should not produce one component per Face (F1) |
| D5s-11 | Tagging a classified Zone Face | Refuse, and say to clear the classification first. If `classify`'s clear intent does not already return a Face to unclassified (F12), P5s-03 adds that to Zones, refusing a Surface-paired Face | Retiring a Face record inside the shading gesture would put Zones' pair rules into Shading. Without a clear route the refusal is a dead end, so the stage owns checking it |
| D5s-12 | How does Zones learn a Face left its envelope without naming Shading? | A neutral flag on the store, beside `claims_entity`: Shading constructs its store with it and Zones reads one foundation check wherever it enumerates a Zone's Faces. Shading does not use `claims_entity` | Zones may not name a feature that requires it. `claims_entity` would make Make Zone refuse a Group holding an overhang (F9), which contradicts D5s-04. P5s-01 names the flag and lists every Zones call site |
| D5s-13 | A mixed selection | Apply to what can take the mark, name what was left out. Refuse only when nothing can | The Spaces create rule. A selection of forty Faces should not fail on one pane Face |
| D5s-14 | A Face with a hole | Export it as honeybee writes a holed `Face3D`; no split, no refusal | Matches honeybee. What the two programs draw is acceptance row SD07, not a design question |
| D5s-15 | Is the section required for export? | Optional. Every shading finding is a note | A Model exports without shading today; a bad shading Face should not withhold the envelope |
| D5s-16 | A Face behind shared storage | Refuse the Face mark with `target.shared_definition` and point to the Component or Group, which can be tagged as a whole | The house rule (F13). Tagging the instance covers the common case, an array of fins. What is lost: tagging some Faces of a repeated Component and not others, which Make Unique or editing the definition's grouping solves |
| D5s-17 | A marked Group that holds a Zone, a Space or a Window Unit | Inheritance stops at a Zone and at any claimed entity: their Faces are never Shading Faces through a container above them. Assign refuses such a Group; if one arises later (Make Zone inside it, a paste), the preflight raises a non-blocking `shading.zone_inside` note naming the Group | Shading does not claim (D5s-12), so Make Zone inside a marked Group is reachable. Without this rule the mark would empty the Room |

Set aside:

| Id | Alternative | Why not |
| --- | --- | --- |
| D5s-07 | A durable id per mark | Needs a copy watcher and duplicate-id repair for a record nothing references |
| D5s-08 | Name plus a counter | One added or deleted Face renumbers the rest, so near-identical Models export differently |
| D5s-09 | `false`; or `false` inside a Zone and `true` elsewhere | The first misreads site context as attached; the second is a rule nothing reads today |
| D5s-10 | The Zone's name unchanged; or always "Shading" | The first lists a shading component under the Zone's own name; the second loses which Zone an overhang belongs to |
| D5s-11 | Tag and unclassify in one step, with or without a confirmation | Puts Zones' Surface-pair rules into Shading, and a wrong click drops a wall from the envelope |
| D5s-12 | `claims_entity`; or an exclusion record owned by Zones | The first contradicts D5s-04; the second writes two records per tag that must stay in step |
| D5s-13 | All or nothing | A large selection fails until every offender is found and deselected |
| D5s-14 | Split into hole-free polygons; or fill the hole | The first departs from honeybee's output; the second over-shades |
| D5s-15 | Block export on an invalid Shading Face | A sliver Face on a neighbour massing would withhold the whole Model |
| D5s-16 | Tag the shared definition, so every placement changes | One click changes placements out of view and breaks the shared-storage rule |
| D5s-17 | Shading claims the Group; or the tag wins over a Zone inside | The first contradicts D5s-04; the second can remove a Room by accident |
