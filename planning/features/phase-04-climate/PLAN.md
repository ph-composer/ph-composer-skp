# Phase 4 delivery plan: Climate

DATE: 2026-11-17
STATUS: In progress. Stages P4c-01 to P4c-11 are written; P4c-12 is the closing outline. Ed authorized every stage on 2026-11-17: "Use the 'pr-loop' skill protocol for all reviews. Use a new branch for each phase of the work, and cleanup all branches and worktrees as you go. You are authorized to merge all PRs once the repo CI is green and all reviewer comments are addressed and resolved." P4c-01 is merged (PR #512) and CM01 passed; P4c-02 is merged (PR #513), CM02 passed and CM01 passed its recheck. P4c-03 is merged (PR #514) and CM03 passed. P4c-04 is implemented (PR #515) and CM04 passed.
AUTHOR: Ed May, BLDGTYP, with Claude
ISSUE: [#511](https://github.com/ph-composer/ph-composer-skp/issues/511)

## Outcome and scope

On a synthetic Model, with a synthetic climate data folder of Phius-shaped station files: a site
set by typing, by a click on the outline map or from SketchUp's geolocation; a station found by
distance and attached with its Phius limit check; values typed by hand on a second Model; two
typed design temperatures; and an HBJSON whose honeybee-ph `Site` carries the climate, with the
dataset and station named in the Export report and no folder location anywhere.

Behavior: the [PRD](PRD.md). Records and seams: [CONTRACTS](CONTRACTS.md). Answers:
[DECISIONS](DECISIONS.md). Acceptance register: [ACCEPTANCE](ACCEPTANCE.md). Screens: the
[wireframes](mockups/README.md), 23 boards.

Out of this plan: everything in the PRD's Deferred table and Non-goals (the hourly weather file,
PHI data, an `.xls` reader, a registered format contract, design temperatures to METr); the
blended heat pump, which the Mechanical packet builds on the reads this plan publishes; SketchUp
2023 and Windows host proof; public distribution.

Ids: stages `P4c-nn`, planning decisions `D4c-nn`, contract questions `C4c-n`, acceptance rows
`CMnn`. `P4-` and `D4-` belong to the Mechanical packet and `P4a-` to Programs, so this packet takes
the lettered form with `c` for climate (D4c-01).

## What earlier phases supply

Paths are relative to `src/ph_composer/`. Planning baseline `origin/main` at `03612a94`.

| Existing | Reused as | Still required |
| --- | --- | --- |
| `extension.rb` `FEATURES`; `shell/registry.rb` `FeatureScope` | Registering `ph_composer.climate` and everything it declares | One `require_relative` and one module in `FEATURES` (P4c-01) |
| `core/model_settings.rb` `ModelSettings`; `features/spaces/settings.rb` as the small example | The site and the design temperatures, each guarded by the values last read | Two settings dictionaries, D4c-02 as amended (P4c-01) |
| `core/records/` record kinds; the fixed-id singleton in `features/zones/options/definitions.rb` | The Model's one climate record | The kind and its operations (P4c-02) |
| `core/units.rb`, `html/unit_tables.js`, `html/fields.js`, `tests/support/units_vectors.json` | Display and entry in SI and IP | Ruby has no temperature; neither side has radiation, wind speed or a distance in km and miles (P4c-01) |
| `library/setup.rb` (per-computer store in SketchUp's preferences), `core/diagnostics.rb` `data_root` (inside SketchUp's versioned folder), `agent_access/connections.rb` (a folder under the user's home) | Precedents only. None fits: the PRD puts Climate's settings in PH-Composer's own file outside SketchUp's versioned folders | A per-computer settings file and its path rule (P4c-03) |
| `shell/native_approval.rb` (`UI.select_directory` behind an approval), `library/setup_commands.rb` (`add_folder`) | Choosing a climate data folder without a path in params or logs | Climate's setup commands (P4c-03) |
| `shell/setup_entries.rb`, `html/sections/setup.js`; Agent Access is the only entry today | The Setup view line for climate data | Climate's summary (P4c-03) and entry (P4c-08) |
| `export/` contributors, `Export::PREFLIGHT_RESULT`, `export/report_html.rb`, `Export::Privacy`; `shell/model_metadata.rb` as the Model-level example | The `Site` section, its findings and its report section | The contributor (P4c-05) |
| `python/ph_composer_translation/` `sections.py`, `composition.py`, `model_sections.py` `ZoneSection.attach` (one shared `ph_bldg_segment` per Building Segment, `site` left at honeybee-ph's default) | Writing `Site` onto each exported Building Segment | A section attached at `MODEL` after `ZoneSection` (P4c-05) |
| `html/index.html` tab row, `html/panel.js` (`activeTab: "overview"`), `html/page_header.js`, `html/subtabs.js`, `html/overlay.js` `formDialog`, `html/library/sidebar.js` | The Climate tab, its sidebar cards and dialogs | The tab, the source cards and three dialogs (P4c-06 to P4c-11) |
| `html/dom.js` `svg`; `features/assemblies/canvas.js` and `features/windows/canvas.js` | SVG drawing in the panel | The outline map kit part (P4c-07) |
| `html/inventory_grid.js` (`parse` of tab-separated text, the paste listener) | Pasting a block into a grid | The Phius-shaped grid (P4c-11) |
| `shell/api.rb` `API::MINOR` and `CHANGES`, `docs/AGENT_GUIDE.md`, `make fixtures` | Every operation added here | One API minor bump and one guide recipe per stage that adds a name |

Nothing in the code reads SketchUp's geolocation or `ShadowInfo` today, and nothing touches
honeybee-ph `Site` (searched 2026-11-17).

## Stages

Twelve stages, each one PR. Records and operations come first with the panel closed, then export,
then the screens (D4c-12).

| Stage | Delivers | Depends on | Code owner | Host gate |
| --- | --- | --- | --- | --- |
| [P4c-01](phases/p4c-01-feature-site-and-design-temperatures.md) | `ph_composer.climate`; the new unit quantities; the site and the design temperatures as Model settings with their operations and reads | Ed's go | climate (new), units | Panel-closed script, Undo/Redo, save and reopen |
| [P4c-02](phases/p4c-02-climate-record-and-limit-check.md) | The climate record with its as-read copy and provenance; save, restore and clear; completeness; edited cells; the Phius limit check | P4c-01 | climate | Panel-closed script, Undo/Redo, save and reopen |
| [P4c-03](phases/p4c-03-settings-file-and-climate-folders.md) | PH-Composer's per-computer settings file; climate data folders: add, name, locate, remove; the Setup summary line | P4c-01; owed check 1 | shell, climate | The file survives a restart on SketchUp 2026, macOS |
| [P4c-04](phases/p4c-04-station-reader-and-attach.md) | The Phius station reader; folder counts; the station list with distance and verdict; attach, replace and update from file; source status | P4c-02, P4c-03; owed check 3 | climate | Real-size folder read time; attach with the panel closed |
| [P4c-05](phases/p4c-05-site-export.md) | The export contributor, findings, the Python `Site` section, conformance, the report's climate section, the PHX round trip | P4c-02; owed check 6 | climate, export | RBZ export; WUFI XML and METr JSON read back |
| [P4c-06](phases/p4c-06-climate-tab-site-and-design-temperatures.md) | The Climate tab, its sidebar cards, the Site location pane and Set Location with typed fields and the geolocation read, the Design temperatures pane | P4c-01; owed check 4 | climate, UI | Panel gestures with Ed |
| [P4c-07](phases/p4c-07-outline-map.md) | The outline map kit part and its data; click to place the site in Set Location; the attached station and its ring there | P4c-06, P4c-02; owed check 2 | UI kit, climate | Map gestures in the real panel |
| [P4c-08](phases/p4c-08-climate-data-dialog-and-phius-states.md) | Climate Data on This Computer; the Phius climate data pane's states with nothing attached | P4c-03, P4c-04, P4c-06 | climate, UI | Panel gestures with Ed |
| [P4c-09](phases/p4c-09-station-picker.md) | Set Phius Climate Data: the map, the list, filters, the verdict, Attach and Replace | P4c-04, P4c-07, P4c-08 | climate, UI | Panel gestures with Ed |
| [P4c-10](phases/p4c-10-attached-climate-pane.md) | The pane of an attached climate: limit check, tables, Where this lives, edited marks, Restore, source status, Update from File, Clear | P4c-09 | climate, UI | Panel gestures with Ed |
| [P4c-11](phases/p4c-11-hand-entry-and-edit-values.md) | Enter Phius Climate Values and Edit Values: the grid, one paste, gaps and Incomplete | P4c-10; owed check 5 | climate, UI | Paste from a real workbook and text file |
| [P4c-12](phases/p4c-12-acceptance-and-handoff.md) | Register closed; context, docs, glossary; handoff to Mechanical | all above | integration | Fresh-process integrated run on SketchUp 2026 |

```
P4c-01 ─┬─ P4c-02 ─┬─ P4c-05 ─────────────────────────────────────────┐
        │          └──────────┐                                       │
        ├─ P4c-03 ── P4c-04 ──┼───────────┬─ P4c-08 ── P4c-09 ── P4c-10 ── P4c-11 ── P4c-12
        └─ P4c-06 ── P4c-07 ──┴───────────┘
```

P4c-04 needs P4c-02 and P4c-03. P4c-07 needs P4c-02 and P4c-06. P4c-08 needs P4c-03, P4c-04 and
P4c-06. P4c-09 needs P4c-07 and P4c-08. P4c-03, P4c-05 and P4c-06 can run in parallel once their
entries merge. Each stage is one PR through the pr-loop
([stage brief](../../../.agents/stage-brief.md)) with one Sonnet read-through and one Codex
review; P4c-01 (the new feature), P4c-03 (a new per-computer store) and P4c-05 (serialization)
take the stronger review lane.

P4c-04 is the largest stage. If its entry check makes the read sliced, split it in two: the
reader, the walk and the counts; then the list, attach and source status.

The Mechanical packet's heat pump stage can start once P4c-02 has merged: the reads it needs are
published by P4c-01 and P4c-02 (CONTRACTS section 9).

## Owed checks, each an entry check

The PRD lists six. Each is run before its stage writes code, recorded under `evidence/`, and
folded into `context/SKETCHUP_HOST_BEHAVIOR.md` when it is a host fact.

| # | Check | Stage | If it fails |
| --- | --- | --- | --- |
| 1 | SketchUp's preferences are per SketchUp version; where the settings file sits on macOS and Windows | P4c-03 | If preferences are shared across versions the separate file still stands (J1 gives a second reason: the extension's folder is replaced on reinstall). Only the macOS half is run, on SketchUp 2026. The Windows location and the two-version checks are deferred (E3 in [DECISIONS](DECISIONS.md)) |
| 2 | The outline map: data source and licence, size in the RBZ, drawing on Chromium 88, loading under the panel's content policy | P4c-07 | Coarser borders or fewer countries until the size fits; no network in any case |
| 3 | Read time when the picker opens: Ruby inside SketchUp, and a cloud-synced folder whose files are not downloaded | P4c-04 | The read is sliced, and a cache is added only if a warm read is still slow (J1, D4c-11) |
| 4 | SketchUp geolocation: what an ungeolocated Model reports, whether `Model#georeferenced?` tells the two apart, whether `TZOffset` is a usable offset, whether an elevation is exposed | P4c-06 | Board 22 is redrawn to what the host reports; the read fills only what is proven |
| 5 | The paste: one block copied from a real Phius `.xls` workbook and from a text file fills the grid | P4c-11 | The grid's row order follows the source; a second accepted layout is added only if the workbook differs |
| 6 | PHX's handling of the exported `Site` end to end: four peak-load cases, the ground row, an empty hours from UTC | P4c-05 | The export is corrected to what PHX reads, or the gap is recorded as a finding and a PHX issue |

## Deferred out of this packet

Ed's answer E3 (2026-11-17). Each item is future work in the packet named, and no stage here
builds or tests it.

| Item | Why | Goes to |
| --- | --- | --- |
| The Windows location of the settings file: choose it, write it, test it | All Windows path work is deferred; a large body of Windows testing is still to come and this joins it | [Windows support](../unscheduled/windows-support/README.md) |
| Preferences per SketchUp version: write in one version, read in another | Ed tests on SketchUp 2026 only for now | [2023 floor](../unscheduled/sketchup-2023-floor/README.md) |
| One settings file read by two SketchUp versions | The same | [2023 floor](../unscheduled/sketchup-2023-floor/README.md) |

## Trace: PRD behaviors to stages

| PRD section | Stage |
| --- | --- |
| How it works, steps 1 and 2 (folders, the settings file) | P4c-03 |
| How it works, steps 3 and 4 (attach copies; the Model reads anywhere) | P4c-02, P4c-04 |
| Records | P4c-01 (site, design temperatures), P4c-02 (climate), P4c-03 (this computer) |
| The tab | P4c-06 |
| Site location | P4c-01 (rules), P4c-06 (pane, dialog, geolocation), P4c-07 (map) |
| Climate data on this computer | P4c-03 (commands), P4c-04 (counts), P4c-08 (dialog, Setup view) |
| Choosing a station | P4c-04 (list, verdict, attach), P4c-08 (pane states), P4c-09 (picker) |
| An attached climate | P4c-02 (rules), P4c-04 (source status), P4c-10 (pane), P4c-11 (editor) |
| Design temperatures | P4c-01 (rules), P4c-06 (pane) |
| Export | P4c-05 |
| Acceptance shape | P4c-12, with each stage's register row |

## Trace: boards to stages

| Board | Stage | Board | Stage |
| --- | --- | --- | --- |
| 1 Main | P4c-06, P4c-07 | 13 DesignTemps | P4c-06 |
| 2 PhiusEmpty | P4c-08 | 14 DataSetupMoved | P4c-08 |
| 3 DataSetup | P4c-08 | 15 PhiusEdited | P4c-10 |
| 4 Picker | P4c-09 | 16 PickerReplace | P4c-09 |
| 5 PhiusAttached | P4c-10 | 17 SourceChanged | P4c-10 |
| 6 OtherComputer | P4c-10 | 18 ExportReport | P4c-05 |
| 7 Narrow | P4c-06, then every pane stage | 19 PhiusFailAttached | P4c-10 |
| 8 SiteEmpty | P4c-06 | 20 HandEnteredPane | P4c-11 |
| 9 PhiusNeedsSite | P4c-08 | 21 SetLocationAttached | P4c-07 |
| 10 PhiusReady | P4c-08 | 22 GeoUnavailable | P4c-06 |
| 11 PickerFail | P4c-09 | 23 Small | P4c-06, then every pane stage |
| 12 HandEntry | P4c-11 | Hourly weather file card (Planned) | P4c-06 |

The W, J and R answers are traced to stages in [DECISIONS](DECISIONS.md).

## Review and verification profile

- Focused tests while building, `make ci` on the final diff, the panel and runtime manifests
  refreshed for panel or Python changes, goldens reviewed against the contract.
- Every stage that adds or reshapes an operation bumps the API minor version and regenerates
  `docs/API_REFERENCE.md` with `make fixtures`.
- Public fixtures are synthetic station files of the Phius shape. A test that reads the private
  corpus takes its location from an environment variable and skips when it is unset; P4c-04
  defines that pattern, which no test uses yet.
- The export stage ends with a PHX round trip through an optional `phx` dependency group; the
  tests skip without it (D4c-14).
- Screen stages load the UI polish skill and its patterns reference first, check each board at
  1280 x 800, 420 x 732 and 360 x 520, and run the Design System re-sync when the kit changes.
- Host gates follow the [native acceptance skill](../../../.agents/skills/ph-composer-native-acceptance/SKILL.md)
  and record ledger receipts during the run.
