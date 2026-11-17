# P4c-01: The Climate feature, the site and the design temperatures

DATE: 2026-11-17
STATUS: Implemented on branch `feature/climate-p4c-01`. Authorized by Ed, 2026-11-17. CM01 not run.
AUTHOR: Ed May, BLDGTYP, with Claude
ISSUE: [#511](https://github.com/ph-composer/ph-composer-skp/issues/511)

## Entry and scope

Requires Ed's go. Owns the `ph_composer.climate` feature's registration, the unit quantities the
packet needs, and the site and design temperatures as Model settings with their operations and
reads. Panel closed: no tab (P4c-06), no climate record (P4c-02), no export (P4c-05).

Behavior: [PRD](../PRD.md), "Site location" and "Design temperatures". Names:
[CONTRACTS](../CONTRACTS.md) sections 1, 2 and 8. Answers: W2, W4, W6, J2, J5, R7; D4c-02, D4c-09.
Boards: none built here; boards 1, 8 and 13 show the values these operations hold. Paths are
relative to `src/ph_composer/`.

Load the architecture review skill before step 2.

## Entry checks

1. Trace one contributor task through `features/thermal_bridges/install.rb` and
   `features/spaces/settings.rb` and confirm the layout in CONTRACTS section 1 against them.
2. Confirm that one `ModelSettings` dictionary can hold the site and the design temperatures
   with two separate public operations, each guarding only its own fields' preimage; if the
   primitive guards the whole dictionary, use two dictionaries and record it (D4c-02).
3. Read `core/units.rb` and `html/unit_tables.js` and confirm what CONTRACTS section 8 lists as
   missing, including the IP form `length` takes for an elevation.

### Entry check outcomes, 2026-11-17

1. Confirmed. `features/thermal_bridges/install.rb` names its parts in a header, requires them, and
   installs each registration module from one `install`; `features/spaces/settings.rb` is a
   `ModelSettings` service with a `get` query and a guarded `update` action. Climate follows both:
   `install.rb`, `settings.rb`, `codes.rb`, `site/` and `declarations/`. `FEATURE_ID` is defined
   before the requires, as in `features/assemblies/install.rb`, because the settings constants use it.
2. Not as planned. `ModelSettings` guards the whole dictionary: `propose` compares every field with
   `expected_values`, the scope digests the whole stored dictionary, and the step's `apply` rereads
   all of it. One dictionary would let a design-temperature change stale a site read. Two
   dictionaries are used and D4c-02 is amended in [DECISIONS](../DECISIONS.md).
   `design_temperatures.update` takes any of its three fields and guards each one given; the
   handler merges them over the stored values before the whole-dictionary proposal.
3. Confirmed. Ruby had no temperature; JavaScript had `temperature` and `temperature_difference`;
   neither had `irradiation`, `irradiance`, `wind_speed` or `distance`. Ruby's `length` shows
   decimal feet in IP. The panel's `length` shows decimal feet too unless the field names a
   dimension scope, when it follows the user's dimension format, so an elevation field (P4c-06)
   takes no scope.

## Steps

1. **Units.** Add `temperature`, `temperature_difference`, `irradiation`, `irradiance`,
   `wind_speed` and `distance` to `core/units.rb` and the missing ones to `html/unit_tables.js`,
   with descriptors in `html/fields.js` and vectors in `tests/support/units_vectors.json`. Ruby
   needs them for the Export report (P4c-05).
2. **Feature.** `features/climate/install.rb` registering `ph_composer.climate`, requiring
   `ph_composer.zones` (the export section's dependency, P4c-05); one `require_relative` and one
   entry in `FEATURES` in `extension.rb`. `codes.rb` starts with the codes this stage refuses with.
3. **Settings.** `features/climate/settings.rb`: the dictionaries `ph_composer.climate_site` and
   `ph_composer.climate_design_temperatures` (entry check 2) with the eight fields of CONTRACTS section 2, each with its `x-unit` and range; the ten
   climate-zone codes as an enum; the rule that latitude, longitude and elevation are set
   together.
4. **Operations and reads**, declared under `features/climate/declarations/`:
   `site.get`, `site.update`, `design_temperatures.get`, `design_temperatures.update`, and the
   `summary` snapshot section with the site and design-temperature card states (the climate
   card's state joins in P4c-02). Undo names: "Set Site Location", "Change Design Temperature".
   `site.geolocation` and `site.preview_limit_check` are not built here (P4c-06, P4c-02).
5. **Zone codes.** One table in `features/climate/site/climate_zones.rb` mapping each stored
   code to its label (Not defined, 1, 2, 3, 4, 4C, 5, 6, 7, 8), read by the panel and the report.
6. **Contract and docs.** API minor bump with a change note, `make fixtures`; an agent guide
   recipe (read the site, set it, set a design temperature); a panel-closed walkthrough under
   `tools/examples/climate/`; `context/UBIQUITOUS_LANGUAGE.md` gains Site location and loses
   "planned" on Design temperatures; `context/CONTRACTS.md`, "Model settings", names the
   dictionary.

## Source

| File | Disposition |
| --- | --- |
| `features/spaces/settings.rb`, `core/model_settings.rb` | Pattern for the settings service, its query and its guarded action |
| `features/thermal_bridges/install.rb`, `codes.rb`, `declarations/` | Pattern for a feature's layout and code declarations |
| `core/units.rb`, `html/unit_tables.js`, `html/fields.js`, `tests/units_test.rb`, `tests/units_test.js` | Extended |
| `extension.rb` | One feature added |

## Tests (write first)

1. Each new quantity converts both ways in Ruby and JavaScript and matches the shared vectors.
2. The feature installs in the built-in registry with its dependency; an operation without
   `refuses:` or with an undeclared code fails registration as the suite already checks.
3. A fresh Model: `site.get` reads Not set and writes nothing; the SKP is not modified.
4. `site.update`: all five fields in one Undo step; latitude without elevation refuses
   `validation.failed`; out-of-range values refuse; zone 19 refuses; a null zone and a null
   offset save with the site still set.
5. `design_temperatures.update`: one value alone reads Incomplete; both read Set; null unsets;
   heating at or above cooling saves with the warning; the note round trips.
6. A stale `expected_values` refuses `target.changed` on both actions.
7. The walkthrough runs through registered operations only.

## Host gate

CM01 in [ACCEPTANCE](../ACCEPTANCE.md).

## Departures in the build

- `codes.rb` declares one code, `climate.heating_not_below_cooling`, the warning the
  design-temperature read carries. The operations refuse only with foundation codes.
- Out-of-range values and an unlisted zone refuse with `params.invalid`, from the declared schema,
  before the handler runs; a partial location refuses with `validation.failed`.
- The `summary` snapshot section is backed by the query `ph_composer.climate.summary.get`.
- `site.get` adds `climate_zone_label` from the zone table, so the panel and the report read the
  label from Ruby.
- `site.update`'s result is the site read; the limit check joins it in P4c-02.

## Leaves for the next stage

P4c-02 adds the climate record and the limit check beside these settings. P4c-06 builds the
panes over `site.*`, `design_temperatures.*` and `summary`.

## Done when

CM01 passes, the walkthrough runs and the contract and glossary are updated.
