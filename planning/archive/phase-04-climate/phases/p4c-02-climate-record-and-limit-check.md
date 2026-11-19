# P4c-02: The climate record and the Phius limit check

DATE: 2026-11-17
STATUS: Complete. Merged to main 2026-11-18 (PR #513, `85c4d78e`). CM02 Pass on `024768ea`, rechecked Pass on `1ca85729` in P4c-12's run. Authorized 2026-11-17 with every Climate stage ([STATUS](../STATUS.md#authorization)).
AUTHOR: Ed May, BLDGTYP, with Claude
ISSUE: [#511](https://github.com/ph-composer/ph-composer-skp/issues/511)

## Entry and scope

Requires P4c-01. Owns the Model's one climate record, its as-read copy and provenance, the operations
that need no file (save values, restore, clear), completeness, edited cells and the limit check.
Panel closed. Attaching from a station file is P4c-04; the grid that calls `save_values` is
P4c-11.

Behavior: [PRD](../PRD.md), "Records" and "An attached climate". Names:
[CONTRACTS](../CONTRACTS.md) sections 3 and 4. Answers: W6, W8, J3, J4, J7; D4c-02, D4c-03,
D4c-04, D4c-08. Boards: none built here; boards 5, 12, 15, 19 and 20 show the states these rules
produce. Paths are relative to `src/ph_composer/`.

## Entry checks

1. Read `features/zones/options/definitions.rb` and `options/operations.rb` and confirm the
   fixed-id singleton pattern covers create on first write, guarded update and delete, each as
   one proposal step.
2. Confirm in the pinned honeybee-ph wheel that a peak-load case's dewpoint and sky temperature
   may be `None` and are not in `peak_load_readiness_issues` (read 2026-11-17; D4c-08 rests on it).

### Entry check outcomes, 2026-11-17

1. Confirmed for create and update, with two notes. `Options.set_settings` creates the singleton
   under its fixed id with `proposal.put` after checking `SETTINGS.problems` itself, because
   `propose_create` mints a fresh id, and updates it with `propose_update`. Zones never deletes
   its settings record, so Clear rests on `Engine#propose_delete`, not on that pattern. Update
   departs: `Engine#propose_update` removes a key whose value is nil, and the climate's nullable
   fields would then be absent rather than null, so every climate write stages the whole record
   with `proposal.put`, checked by the kind first.
2. Confirmed in the pinned honeybee-ph 1.33.65 (`honeybee_ph/site.py`):
   `Climate_PeakLoadValueSet` defaults `dewpoint` and `sky_temp` to `None`, and
   `peak_load_readiness_issues` checks only `temp` and the five radiation values of each case.

### Departures

- **Two entry actions.** An action declares one Undo name and the dispatcher opens the operation
  under it, so "Enter Climate Values" and "Edit Climate Values" cannot come from one
  `save_values`. `climate.enter_values` creates a hand-entered climate and refuses
  `target.changed` over an existing one; `climate.save_values` edits. Recorded in
  [CONTRACTS](../CONTRACTS.md) section 3 and in P4c-11.
- **Edit Values keeps a station's name and coordinates**, refusing `validation.failed`, so no
  edit can move a station into the limits unmarked. P4c-11 already shows them read-only.
- **Write results omit the record.** With the record in each write's declared result, `describe`
  of `save_values` measured 35,979 bytes against the 24,576-byte reply; the writes answer
  `state`, `missing`, `edited_cells` and `limit_check`, and `climate.get` reads the record.
  `missing` is grouped by row and an edited cell is its row and column, so the largest
  `climate.get` measured 17,826 bytes.
- **A development seed for the host gate.** No public operation makes a station climate until
  P4c-04, so `tools/examples/climate/station_seed.rb` writes one through `Record.from_station` as
  "Seed Station Climate" for CM02's station half. The walkthrough itself uses public calls only.

## Steps

1. **Kind.** `features/climate/climate/schema.rb`: `ph_composer.climate.climate`, prefix `clm`,
   one fixed id, the fields of CONTRACTS section 3, every number with its `x-unit`. The schema
   refuses any key not listed, so a path cannot be stored by accident.
2. **Pure rules**, each a module with no SketchUp constant, under `features/climate/climate/`:
   - `completeness.rb`: complete or the list of what is missing, by row and column (D4c-08);
   - `edits.rb`: the edited cells against `as_read`, wind speed excluded;
   - `limit_check.rb`: CONTRACTS section 4, with the two limits as named constants and their
     source in a comment.
3. **Operations**: `climate.get` with the derived fields; `climate.save_values` (creates a
   hand-entered climate with `origin: "hand"`, a null `as_read` and a `user_defined` provenance,
   or changes the values of the existing one, leaves `as_read` alone and rewrites the provenance's
   source type and edited values in the same step, D4c-03); `climate.restore_original`, which
   does the same;
   `climate.clear`. Undo names: "Enter Climate Values", "Edit Climate Values", "Restore Climate
   Values", "Clear Climate". Codes: `climate.no_original`, `climate.not_found`.
4. **A builder** the reader will call in P4c-04: `Climate::Record.from_station(parsed, source)`,
   pure, returning the record with `as_read`, `provenance` and the wind-speed mean. Tested here with
   a hand-built parsed station.
5. **Site preview.** `site.preview_limit_check` (query): the verdict the attached station would
   get at a proposed latitude, longitude and elevation. `site.update`'s result gains the limit
   check after the change.
6. **Summary.** The climate card's state joins the `summary` snapshot section: none, a station
   with its verdict, hand-entered, Incomplete, edited.
7. **Contract and docs.** API minor bump, `make fixtures`; the agent guide recipe gains typing a
   climate and reading its state; the walkthrough is extended; `context/UBIQUITOUS_LANGUAGE.md`
   updates Climate snapshot, Station and Phius climate data; `context/CONTRACTS.md` names the
   kind.

## Source

| File | Disposition |
| --- | --- |
| `features/zones/options/definitions.rb`, `options/operations.rb` | Pattern for a fixed-id singleton record |
| `core/records/record_kind.rb`, `core/records/engine.rb` | The kind and its guarded writes |
| `features/thermal_bridges/type/schema.rb`, `operations.rb`, `reads.rb` | Pattern for schema, operations and reads beside each other |

## Tests (write first)

1. The schema round trips a station-origin and a hand-origin record; an unknown key, a
   thirteen-value month row and a wrong version are unreadable.
2. Completeness: a full record is complete; each needed field removed in turn is named; a null
   dewpoint in a design case is still complete.
3. Edits: one changed monthly cell, one changed peak value, the swing and the station elevation
   each show; a changed wind speed does not; a hand-entered record shows none.
4. Limit check, at the boundary: exactly 80.4672 km passes and a metre more fails; exactly
   121.92 m passes and more fails; each limit fails alone; no site and no station coordinates
   each read Not checked with their reason. Distances match hand values for three synthetic pairs.
5. `save_values` creates, updates and saves with gaps, each one Undo step; a stale record refuses.
   An edit to a station climate turns its stored source type to `user_defined` and lists the
   edit in `assumptions`; Restore and one Undo each turn it back with the values.
6. `restore_original` returns every cell and refuses for a hand-entered climate; `clear` deletes
   the climate and leaves the settings untouched.
7. `Record.from_station` sets the wind speed to the January and July mean and copies the values
   into `as_read` as separate objects.
8. A site change through `site.update` changes `climate.get`'s verdict with no climate write.

## Host gate

CM02 in [ACCEPTANCE](../ACCEPTANCE.md).

## Leaves for the next stage

P4c-04 feeds `Record.from_station` from real files and adds `attach_station` and source status.
P4c-05 exports the record. The Mechanical packet may start on its heat pump stage: the reads in
CONTRACTS section 9 exist after this stage.

## Done when

CM02 passes and the contract and glossary are updated.
