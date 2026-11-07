# Usability walkthrough fixes: stage ledger

DATE: 2026-11-07
STATUS: In progress
AUTHOR: Ed May, BLDGTYP; Claude
ISSUE: https://github.com/ph-composer/ph-composer-skp/issues/373 (tracking)

Plan: [PLAN.md](PLAN.md). States: `Scoped` · `In progress` · `Implemented on branch` ·
`Merged to main` · `Blocked` · `Deferred`. Evidence names the command output or PR it rests on.

| Stage | Issue | State | PR | Evidence |
| --- | --- | --- | --- | --- |
| WT-01 | #358 | Merged to main | [#374](https://github.com/ph-composer/ph-composer-skp/pull/374) | Pre-fill not reproduced at `a39e1e19` (installed build `diff -rq` clean; preview form opens blank in SI and IP and sends `null`; host `materials.create` with nulls stored `null`). Rows 2 and 3 already met by `material.thermal_mass_defaulted` and existing Ruby and Python tests. New check in `inventories_checks.cjs` passes, fails on a seeded density (mutation run) |
| WT-02 | #359 | Merged to main | [#375](https://github.com/ph-composer/ph-composer-skp/pull/375) | D2 in Ruby (Face `assembly_reversed`, pair mirroring on assign, classify and Solve; preflight `construction.missing` only across Building-Segments, `face.assembly_pair_mismatch` blocking) and Python (reversed construction, unassigned interior pair, pair guard). `test_an_interior_surface_pair_exports_a_model_honeybee_accepts` runs honeybee `check_all` on the two-Zone export: passes assigned and unassigned; old fixture export failed it (reversed-layers message). `make ci` green |
| WT-03 | PH-Tools/PHX#169 | Merged to main | [PHX#170](https://github.com/PH-Tools/PHX/pull/170) | Spaces whose host Room had no People kept an unregistered occupancy pattern; PHX now registers `__phx_default_constant_occupancy__` for them. New `test_room_without_people.py` (3 tests; two failed before the fix with the dangling-reference error). PHX `pytest tests/` 1532 passed, 3 skipped. Local `tutorial_house.hbjson`: `hbjson_to_wufi_xml` and `hbjson_to_metr_json` both exit 0. Codex gpt-6.1-sol: no findings. Released as PHX 1.59.1 (PyPI) |
| WT-04 | #354 | Merged to main | [#376](https://github.com/ph-composer/ph-composer-skp/pull/376) | Cause measured on the host: `erase_entities` refuses a Group on the open edit path, so Delete failed with the Space open (panel Open, or double-click), not with only the Zone open. `DeleteSpaceStep` closes the path to the Space's parent inside its operation; Volume protection run by that path change joins the operation (a nested start split Delete into two Undo steps on the host). `test_delete_space_works_from_any_edit_context_in_one_undo_step` (root, Zone, Space, Volume open) failed before the fix with `operation.failed`; stub rule pinned by `test_erase_refuses_a_group_on_the_active_path`. Dialog: "Delete Space?", no Undo sentence |
| WT-05 | #353 | Merged to main | [#377](https://github.com/ph-composer/ph-composer-skp/pull/377) | Refuse branch of row 1 (accepting a solid is left to the WT-06 packet, D1). A vertical Face is never a floor: Create Space leaves it out (`vertical`), and Mark floor, Add Volume and the candidate read refuse it (`target.wrong_kind`). Every other Face of a closed solid (`Steps.closed_shells`: four or more Faces, each Edge bounding two of them, any side slope) is left out as `solid`, and Add Volume refuses one, so nothing counts twice. Codex (gpt-6.1-sol) found the sloped-sided case (a frustum accepted whole, 32 m2 for 16 m2); fixed and tested. `test_create_space_on_a_solid_refuses_its_walls_and_counts_no_floor_twice` (L-shaped solid, 4.88 m2 plan) failed before the fix with all 8 Faces accepted; `test_a_vertical_face_is_never_a_floor_candidate_a_marked_floor_or_a_new_volume` failed with no refusal. Host, WT-04 build: the same solid drawn in Floor-01 gave 8 accepted in the API preview and the native menu review. Two stacked separate outlines still both count (named in the WT-06 packet). Host check on the installed merge head `27d82cc7` (PR comment): L-solid 0 accepted (6 `vertical`, 2 `solid`), create refused, sloped solid 6 `solid`, flat outline accepted |
| WT-06 | #352 | Implemented on branch | | Design packet [spaces-authoring](../features/unscheduled/spaces-authoring/README.md): D1 made concrete as hosting by reference (W6-1, recommended) versus re-parenting, a proposal per #352 acceptance row, decisions W6-1 to W6-11 (including WT-05's residuals: accepting a solid, stacked outlines in one Volume) and seven implementation stages S10-1 to S10-7 that wait for Ed's go. Docs only |
| WT-07 | #363 | Scoped | | design packet; ends at Ed's review |
| WT-08 | #370 | Scoped | | |
| WT-09 | #344 | Scoped | | |
| WT-10 | #346 | Scoped | | |
| WT-11 | #345 | Scoped | | |
| WT-12 | #343 | Scoped | | |
| WT-13 | #347 | Scoped | | |
| WT-14 | #348 | Scoped | | |
| WT-15 | #349 | Scoped | | |
| WT-16 | #350 | Scoped | | |
| WT-17 | #351 | Scoped | | |
| WT-18 | #364 | Scoped | | |
| WT-19 | #366 | Scoped | | |
| WT-20 | #367 | Scoped | | |
| WT-21 | #372 | Scoped | | |
| WT-22 | #371 | Scoped | | |
| WT-23 | #369 | Scoped | | |
| WT-24 | #355 | Scoped | | |
| WT-25 | #356 | Scoped | | |
| WT-26 | #357 | Scoped | | |
| WT-27 | #360 | Scoped | | |
| WT-28 | #361 | Scoped | | |
| WT-29 | #362 | Scoped | | |
| WT-30 | #365 | Scoped | | |
| WT-31 | #368 | Scoped | | |
