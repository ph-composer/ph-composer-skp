# Research: what PH-Composer has today

DATE: 2026-11-14
STATUS: Research complete against `main` at `186734ce`.
AUTHOR: Ed May, BLDGTYP, with Claude
ISSUE: none (local planning draft)

Everything in the repository that already touches programs, loads, schedules, occupancy or
ventilation, and the seams a Program feature would build on. Paths are repository-relative;
`src/` means `src/ph_composer/`.

## 1. The gap

- **No ProgramType, load or schedule is created anywhere in `src/`.** `ZoneSection.translate`
  (`src/python/ph_composer_translation/model_sections.py`) builds Faces, the Room, its display
  name and `user_data.ph_composer`, and never touches `room.properties.energy`. Every Room exports
  as `{"type": "RoomEnergyPropertiesAbridged"}` and honeybee-energy falls back to Plenum. The
  Model's `program_types` and `schedules` lists are empty (`tests/fixtures/phase_one/two_zones.hbjson`).
- **PHX fails on that HBJSON.** The November usability walkthrough found no People, infiltration or
  ventilation load (W-120); adding a zero People load made the WUFI conversion pass (W-122). Filed
  as PHX#169 (`planning/archive/usability-walkthrough-2026-11/SYNTHESIS.md`, S-29).
- **Spaces already promise an inherited value nothing supplies.** A Space with no airflow set "uses
  its Zone's ventilation load" (`src/features/spaces/scan/metrics.rb`,
  `src/features/spaces/colour_modes.rb`, `src/html/features/spaces/cells.js`,
  `src/python/ph_composer_translation/space_sections.py`). The Spaces packet names "the Zone loads
  packet" as the supplier and shows a muted dash until it exists
  (`planning/archive/phase-03a-spaces/PRD.md`, STATUS).

## 2. Zones, Spaces and the Building Segment

- **Zone** (the honeybee Room): stored on the Zone Group in dictionary `ph_composer.zone`
  (`src/features/zones/zone/schema.rb`). Schema v2: `name`, `building_segment_id`, `level_id`,
  `ground_depth_mm`. No load or program field.
- **Zone options** (`src/features/zones/options/definitions.rb`): Building Segment (`bsg`: name,
  colour, `export_identifier`), Level (`lvl`), and a default segment setting.
- **Space** (`src/features/spaces/schema.rb`): kind `ph_composer.spaces.space`, prefix `spc`:
  `name`, `number`, `default_height_m`, `zone_id`, and optional airflows `v_sup_m3h`, `v_eta_m3h`,
  `v_tran_m3h` in m³/h ("absent is unset, distinct from 0"). No occupancy, schedule or operating
  hours field.
- **Space export** (`space_sections.py`): the any-set rule. All three airflows unset writes `None`
  (inherit the Zone's Ventilation load); otherwise all three are written, an unset one as 0, divided
  by 3600 into `space.properties.ph._v_sup`, `_v_eta`, `_v_tran`.
- **Building Segment export** (`model_sections.py`, `attach`): one `ph_bldg_segment` per segment
  with only `identifier` and `display_name` set. Every other field carries honeybee-ph defaults the
  user never sees: certification program `7-PHIUS 2021 CORE`, category `1-RESIDENTIAL BUILDING`,
  use `1-RESIDENTIAL`, `num_dwelling_units` 1, set points 20 / 25 °C.
- **No per-Model setting** names a certification standard, a residential or non-residential
  category, or an airtightness value. Phius only is a founding decision
  (`planning/FOUNDING_BRIEF.md`).
- **Airtightness is authored nowhere.** No n50, q50 or infiltration field in `src/`, `context/` or
  live planning.

## 3. Record and assignment patterns to copy

**Definition record kinds.** `Records::RecordKind` (`src/core/records/record_kind.rb`) with
`DictionaryStore`: one Model dictionary per kind, `ph_composer.records.<kind id>`, one JSON string
per id (`src/core/records/dictionary_store.rb`). Registered with `feature.record_kind(KIND)`.

- **Smallest template: Thermal Bridge Types.** Kind `src/features/thermal_bridges/type/schema.rb`
  (prefix `tbt`), `type/operations.rb`, `type/reads.rb`, `declarations/types.rb` (CRUD,
  `export_ready`, `export_blockers`), `install.rb`, UI `src/html/features/thermal_bridges/types.js`.
- **Nested children** (a Program's loads, a Schedule's day profiles): Assemblies do this with
  layers, through `RecordKind references:` and `propose_duplicate`'s block (`context/CONTRACTS.md`,
  "Records and extension data").
- A feature joins the extension through `FEATURES` in `src/extension.rb`.
- A definition record end to end: `context/TECH_STACK.md`, "A definition record, end to end".

**Assigning a definition to a Zone.** Three precedents, none decided for Programs:

1. A field reference with a retargeter: Face to Assembly
   (`src/features/zones/declarations/assembly_assignment.rb`).
2. A Model default: Windows `default_psi_install_id` (`context/CONTRACTS.md`, "Model settings").
3. A separate entity record on the Zone Group, planned for equipment "Serves" (dictionary
   `ph_composer.equipment_serves`, `planning/features/phase-04-mechanical/CONTRACTS.md`, D4-03),
   chosen because "Zones names no feature" (equipment PRD).

Copying a Zone needs a transition contributor for `ph_composer.zones.occurrence_independent`
(`context/EXTENSIBILITY.md`, "Records inside a Zone occurrence"; example
`src/features/spaces/zone_copy.rb`).

## 4. Export seams

- Ruby export contributors: `src/features/zones/export.rb`, `src/features/spaces/export.rb`.
- Python sections listed in `src/python/ph_composer_translation/composition.py`. Spaces is the
  example of a section that attaches to a Room (`context/CONTRACTS.md`, "Translation sections and
  artifacts").
- `stack.PACKAGES` (`src/python/ph_composer_translation/stack.py`): honeybee, honeybee_energy,
  honeybee_ph, honeybee_energy_ph, ladybug, ladybug_geometry, PHX. It does not include
  `honeybee_ph_standards`, `honeybee_ph_utils` or `honeybee_standards`; adding one follows the
  phase-04 precedent (CONTRACTS A1) and `tests/python/test_imports.py`.
- Cross-language rule: anything Ruby sends to the shipped Python is pinned by a fixture both sides
  read (`context/TECH_STACK.md`). Template: `tests/fixtures/thermal_bridges/` with
  `tests/python/test_thermal_bridge_sections.py`.
- Pins (`pyproject.toml`, `src/vendor/manifest.json`): honeybee-core 1.64.65, honeybee-energy
  1.123.23, honeybee-standards 2.0.7, honeybee-ph 1.33.65, ladybug-core 0.44.56,
  ladybug-geometry 1.35.3, ph-units 1.5.38. No honeybee-energy-standards, no PHX wheel.

## 5. UI seams

- Top-level tabs (`src/html/index.html`): Zones, Assemblies, Window Types, Thermal Bridges,
  Library, Export, plus Setup. A new tab is a permitted composition-root edit of `index.html`, then
  `panel.section(name, render, { pane })` and the `main`, `inspector`, `tools` and `actions`
  regions (`context/EXTENSIBILITY.md`). Thermal Bridges is the nearest full-tab example
  (`src/html/features/thermal_bridges/section.js`, Types and Schedule subtabs).
- **Zone views** inside the Zones tab: Geometry (`src/html/features/zones/faces_view.js`) and
  Spaces (`src/html/features/spaces/view.js`). The Zone views contract already anticipates this
  work: "Add an Occupancy view registers `columns` and `value` with no `children`"
  (`context/EXTENSIBILITY.md`, Zone views), and the Spaces decisions require the contract to admit
  a view with no child rows. Example: `tools/examples/zones/example_zone_view.js`.
- Phase 4 plans a separate Systems tab for equipment (equipment PRD Q9, Q10).

## 6. Libraries

The file provider serves every registered kind (`src/library/install.rb`). Registered kinds today:
Materials, Frames, Glazings, Psi-Install Types. A new kind needs a `Declarations::LibraryAdapter` in
its owning feature (`context/EXTENSIBILITY.md`, Library kinds), a section in
`docs/LIBRARY_FILE_FORMAT.md` and optional starter rows (`starter-library/`). Thermal Bridge Types
are not yet a library kind (roadmap 5.4).

## 7. What the planning record already says

- **Equipment Q12** (`planning/features/phase-04-mechanical/equipment/PRD.md`), answered
  2026-10-21: equipment "owns the appliance records and their default set, exported as Process
  loads; the Zone loads packet, when drafted, owns occupancy, lighting and the non-appliance loads
  and reuses the same Room-load section." **This packet is that Zone loads packet.**
- Equipment PRD: the appliance default set "needs dwelling count and bedroom count per Zone";
  stage P4-12 asks where those counts are stored. honeybee-ph stores them on
  `People.properties.ph`, which this packet owns.
- Equipment non-goals: "No schedules."
- Phase 4 defers "Occupancy, lighting and the other Room loads (Q12)" to "the Zone loads packet,
  not drafted" (`STATUS.md`, `PLAN.md`, `README.md`).
- Spaces PRD: "A Space inherits everything from its Zone: occupancy, lighting, equipment, hot water
  and ventilation loads and schedules." Spaces DECISIONS: these "sit on the Zone (honeybee-energy's
  Room)", future packets. Space Types await their own interview.

**Inconsistencies to correct when the interview settles terms:**

- `context/UBIQUITOUS_LANGUAGE.md` says a Zone carries "loads and schedules" and a Space carries
  "occupancy"; neither exists, and the glossary has no Program, Load or Schedule entry.
- `planning/ROADMAP.md` item 4.6 called the Q12 boundary open; corrected 2026-11-14.
