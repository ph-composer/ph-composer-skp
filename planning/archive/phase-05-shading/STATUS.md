# Shading: tracking ledger

DATE: 2026-11-19
STATUS: Complete (2026-11-20), archived. Implementation: P5s-01 to P5s-07 built. Merge: all seven merged to main (PRs #527 to #533, last `906a102c`). Host acceptance: SD01 to SD07 Pass 2026-11-20 on `906a102c`, recorded in the native case ledger; Ed's words on the two files are quoted in the [Closure](#closure-2026-11-20). Release: none. Every stage authorized by Ed 2026-11-19 ([Authorization](#authorization)).
AUTHOR: Ed May, BLDGTYP, with Claude
ISSUE: [#526](https://github.com/ph-composer/ph-composer-skp/issues/526)

The one place Phase 5 completeness is read from. Update it in the same change as any stage's state.

## State

Ed requested the feature on 2026-11-19 and answered four scope questions the same day (D5s-01 to
D5s-06). honeybee-ph and PHX were read at the repository's pins and one round trip was run
([research](research/honeybee-ph-and-phx-shading.md)). Ed answered D5s-07 to D5s-17 one at a time the same
day, taking the recommendation each time. Issue [#526](https://github.com/ph-composer/ph-composer-skp/issues/526)
was filed at authorization.

## Authorization

Ed authorized every Shading stage on 2026-11-19: "Use the 'pr-loop' skill protocol for all reviews. Use a new branch for each phase of the work, and cleanup all branches and worktrees as you go. You are authorized to merge all PRs once the repo CI is green and all reviewer comments are addressed and resolved."

## Stages

| Stage | State | Acceptance | PR |
| --- | --- | --- | --- |
| P5s-01 Contracts and host facts | Merged to main ([#527](https://github.com/ph-composer/ph-composer-skp/pull/527), `f06f0efd`): CONTRACTS sections 4 and 7 answered, `tests/shading_mark_store_test.rb`; SD01 recorded `blocked` on `2a9c5e17` with eight of ten gestures measured ([evidence](evidence/sd01-host-facts.md)); Move-copy array and push-pull owed to a later hold; the batched rerun on `906a102c`, 2026-11-20, measured all ten gestures: SD01 Pass | SD01 | [#527](https://github.com/ph-composer/ph-composer-skp/pull/527) |
| P5s-02 Shading mark and operations | Merged to main ([#528](https://github.com/ph-composer/ph-composer-skp/pull/528), `f0049a3d`): `features/shading/` (mark, reads, eligibility, targets, operations, selection, inventory), the envelope-exclusion flag in `core/records/entity_store.rb`, API 1.69; `tests/shading_operations_test.rb` (19 runs), `tests/shading_reads_test.rb` (3), `tests/shading_mark_store_test.rb` (4); `make ci` green on `0f14c44d` (3058 runs, 0 failures); two gpt-6-astra reviews, six findings fixed; SD02 pass on `0f14c44d` ([evidence](evidence/sd02-operations.md)) | SD02 | [#528](https://github.com/ph-composer/ph-composer-skp/pull/528) |
| P5s-03 Zones seam | Merged to main ([#529](https://github.com/ph-composer/ph-composer-skp/pull/529), `afc108ad`): the envelope check at Zones' four funnels (`walk_faces`, `holding`, `resolve_face_path`, the export `zone_faces`) and in Spaces' candidate Faces; `face.outside_envelope`; `zones.faces.clear_classification` (D5s-11, F12); `shading.export_preflight` with `shading.zone_inside`; API 1.70; decisions in [CONTRACTS](CONTRACTS.md#what-p5s-03-decided); `tests/zones_envelope_exclusion_test.rb` (26 runs) and one Spaces offset test, D5s-11a (conductor extension, awaiting Ed's confirmation); call sites mapped below; SD03 Pass 2026-11-20 on `906a102c` in the batched host pass ([evidence](evidence/sd03-zones-seam.md)) | SD03 | [#529](https://github.com/ph-composer/ph-composer-skp/pull/529) |
| P5s-04 Native menu | Merged to main ([#530](https://github.com/ph-composer/ph-composer-skp/pull/530), `3a2bfaa4`): `features/shading/declarations/menu.rb` (Set as Shading and Clear Shading, `Shading::Menu::Client`), `docs/SHADING.md`; `tests/shading_menu_test.rb` (12 runs); `make ci` green (310 runs per Ruby job, 0 failures); two gpt-6.1-sol reviews, three findings fixed; SD04 case added to the native case ledger; SD04 Pass 2026-11-20 on `906a102c` in the batched host pass ([evidence](evidence/sd04-native-menu.md)) | SD04 | [#530](https://github.com/ph-composer/ph-composer-skp/pull/530) |
| P5s-05 Colour-by | Merged to main ([#531](https://github.com/ph-composer/ph-composer-skp/pull/531), `ced1be43`): `features/shading/colour_modes.rb`, mode `ph_composer.shading.by_component` (one entry per Shading Face occurrence with path and transform, keyed by component name, palette by name, area figure; a flattened placement amber with no figure); `Inventory.shading_face?` and `shading_faces` shared with `shading.list`; binding folded into `context/CONTRACTS.md`; `docs/SHADING.md` "See what is tagged"; `tests/shading_colour_mode_test.rb` (7 runs, 48 assertions); `make ci` green on the rebased head (Ruby suite 3104 runs, 0 failures); offline projection at 5,000 Shading Faces on the test stub about 115 ms (walk 26 ms, the rest `FaceCapture` area), stub rebuild about 340 ms with pure-Ruby tessellation, so not the host figure; SD05 Pass 2026-11-20 on `906a102c` in the batched host pass ([evidence](evidence/sd05-colour-by.md)) | SD05 | [#531](https://github.com/ph-composer/ph-composer-skp/pull/531) |
| P5s-06 Export | Merged to main ([#532](https://github.com/ph-composer/ph-composer-skp/pull/532), `ca3b9ea9`): `features/shading/export.rb` (section `ph_composer.shading.export.shades`, version 1, one record `{id, display_name, boundary, holes}` per Shading Face occurrence from the snapshot; inside a Zone Zones' `outside_envelope?` decides, so a Face is a Room's or a Shade), `shade_sections.py` and `contract/shade_records.py` (detached `Shade` at `MODEL`, optional), result fields, report section and conformance; `shading.export_preflight` now the section's preflight, so `shading.zone_inside` reaches every export, with one row per Group under a path id; `Reads.exported?` shared with `shading.list` and Colour-by; snapshot `native["definition_name"]`; `Records::EntityStore.claimed_entries?`; API 1.71; `tests/shading_export_test.rb` (12 runs), `tests/python/test_shade_sections.py` (9), `tests/python/test_shade_phx_round_trip.py` (PHX 1.57.5, run with `uv run --group phx`: five components, `InnerAttachment` and `idIC` -1, METr areas equal the result's); `make ci` green (Ruby suite 3117 runs, 0 failures; JavaScript 1031 pass; Python 297 passed, 1 skipped); cost at 5,000 Shading Faces below; two gpt-6-astra reviews, two findings fixed in `6e395e56` (a malformed `user_data` hid a required envelope; a path-like Group name in a note failed the artifact guard), the second review clean; SD06 not run on `6e395e56` (`host_bridge.py launch` found no bridge in 180 s), then Pass 2026-11-20 on `906a102c` in the batched host pass ([evidence](evidence/sd06-export.md)) | SD06 | [#532](https://github.com/ph-composer/ph-composer-skp/pull/532) |
| P5s-07 Acceptance and handoff | Merged to main ([#533](https://github.com/ph-composer/ph-composer-skp/pull/533), `906a102c`): pre-archive gpt-6-astra review of the five commits that merged unreviewed, four findings fixed ([evidence](evidence/prearchive-review.md)); its own gpt-6-astra review found two, both fixed in `6686c940`; docs pass, SD07 case entry. SD07 Pass 2026-11-20 on `906a102c`: the host part, then Ed's check of both files ([evidence](evidence/sd07-acceptance.md)) | SD07 | [#533](https://github.com/ph-composer/ph-composer-skp/pull/533) |

### P5s-06 cost at 5,000 Shading Faces

Measured offline on 2026-11-19 with the SketchUp test stub (Ruby 3.2.2) and CPython 3.11.13, not the host or
Pyodide: 1,000 marked Groups of five Faces beside one Zone. Snapshot capture 0.133 s; the full extraction 0.159 s
against 0.147 s without the Shades section, so the section adds about 12 ms; `shading.export_preflight` 0.134 s;
`shading.list` 0.141 s. Python translate, assembly and `to_dict` of 5,000 Shades 0.486 s and the conformance
reload 0.203 s, for a 2.5 MB HBJSON. Pyodide runs CPython code more slowly; SD06 records the host figure.

### P5s-03 call sites and their tests

Tests are in `tests/zones_envelope_exclusion_test.rb`. A row marked "funnel" inherits its funnel's test and
has none of its own.

| Call site (CONTRACTS section 4) | Test |
| --- | --- |
| A: `faces.list`, `faces.all`; Window Unit host Faces (funnel) | `test_face_reads_leave_out_an_excluded_face` |
| A: Zones view counts | `test_zone_view_counts_leave_out_an_excluded_face` |
| A: Suggest classification | `test_suggest_classification_leaves_an_excluded_face_without_a_record` |
| A: `face.unclassified` preflight row | `test_the_unclassified_preflight_row_leaves_out_an_excluded_face` |
| A: Face Colour-by modes (Face type tested; Boundary and Assembly by funnel) | `test_face_colour_modes_leave_out_an_excluded_face` |
| A: Solve candidates | `test_solve_adjacencies_does_not_pair_an_excluded_face` |
| A: Face splitting during Solve | `test_solve_does_not_split_an_excluded_face` |
| A: Solve and Classify retirements, a locked excluded side included | `test_retiring_a_pair_leaves_an_excluded_counterpart_unwritten` |
| Stamp writer and Zone copy repair walk every member, excluded or not (identity maintenance); split-identity repair (funnel A) | `test_zone_stamp_writer_and_copy_repair_keep_an_excluded_member_in_step` |
| A: Attached zone references; Assembly retarget (funnel) | `test_attached_zone_references_leave_out_an_excluded_face` |
| A: Assembly replacement and Attached zone delete name an excluded record's route | `test_stranded_records_inside_the_envelope_name_the_exclusion` |
| A, D: a component's mark, a Zone Group's record, a claim between | `test_a_component_excludes_a_zone_group_does_not_and_a_claim_wins` |
| B: `occurrence_for_path`, `containment`, `faces.host_context`; Thermal-bridge, Spaces and Windows host reads (funnel) | `test_point_reads_find_no_zone_face_for_an_excluded_face` |
| B: an Edge beside an excluded Face | `test_an_edge_beside_an_excluded_face_still_reads_its_zone` |
| B: Classify tool, `classifiable?` and the selection read | `test_the_classify_tool_and_the_selection_menu_leave_an_excluded_face_alone` |
| C: Classify, Reverse and `resolve_face`; Locate, metadata, Assembly assignment (funnel) | `test_an_explicit_reference_to_an_excluded_face_refuses_outside_envelope` |
| D: Zones section Room and `face.unclassified`; Faces section projection | `test_export_leaves_an_excluded_face_out_of_the_room_and_the_faces_section` |
| D: Surface counterpart in export | `test_an_excluded_face_with_a_record_leaves_the_export_and_its_surface_partner_omits` |
| Spaces' candidate Faces (own walker) | `test_spaces_candidate_faces_leave_out_an_excluded_face` |
| Spaces' offset preflight, live and snapshot (funnels A, D) | `tests/spaces_export_test.rb` `test_the_offset_leaves_out_a_face_outside_the_zone_envelope` |
| Clear classification | `test_a_classified_face_takes_the_tag_after_clear_classification`, `test_clear_classification_refuses_a_surface_pair_an_aperture_host_and_an_excluded_face` |
| Shading through the seam; D5s-17, a Zone and a cutting component inside a marked Group | `test_shading_tags_the_overhang_out_of_the_envelope_and_clear_brings_it_back`, `test_a_zone_made_inside_a_marked_group_keeps_its_faces_and_raises_zone_inside` |
| D5s-11a: assign refuses a Group holding classified Faces; classification wins; the preflight note | `test_assign_refuses_a_group_holding_classified_faces`, `test_a_classified_face_under_a_marked_group_stays_in_the_envelope`, `test_a_face_classified_under_a_marked_group_is_noted_by_the_preflight` |
| A Model with no shading exports byte-identically | `tests/phase_one_export_test.rb` golden unchanged; `make fixtures` moved only the API reference and guide |

## Next step

None in this packet. Ed's two confirmations and the follow-ups below are carried in the master
[STATUS](../../STATUS.md) row.

## Closure 2026-11-20

Four separate facts:

| Fact | State |
| --- | --- |
| Implementation | Complete: P5s-01 to P5s-07 built; the five commits that merged unreviewed were reviewed before the archive by gpt-6-astra, four findings fixed ([evidence](evidence/prearchive-review.md)) |
| Merge | P5s-01 to P5s-07 merged to main through PRs #527 to #533 (last `906a102c`, 2026-11-20 UTC); CI green on `906a102c` |
| Host acceptance | Complete: SD01 to SD07 recorded `pass` on `906a102c`, 2026-11-20, SketchUp 26.1.188, in `planning/native-acceptance/results.jsonl` |
| Release | None. No release, distribution, platform-support or certification claim follows from this packet |

### Ed's check of the two files (SD07)

Ed opened the files converted from SD07's host export on 2026-11-20 and said, of the METr JSON, "looks ok in
METr" and, of the WUFI XML, "WUFI looks right". The METr observations (five components, the holed Face drawn
with its hole) are in the [SD07 evidence](evidence/sd07-acceptance.md). Ed gave no further detail on WUFI-Passive,
and the [research note](research/honeybee-ph-and-phx-shading.md)'s three "Not checked" questions were not
answered separately.

### Final gates

- Stage gates, as each stage row records them; P5s-07's offline part (both Ruby gates, coverage, runtime
  page, footprint, browser checks) is in the [SD07 evidence](evidence/sd07-acceptance.md): Ruby coverage 97.2%
  of 31,266 lines (minimum 93%), JavaScript 97.4% of 19,604 (94%), Python 94.95% (92%); runtime verified,
  171 assets, 8 wheels, 22,487,023 bytes.
- `main` CI green on `906a102c` (#533's merge) and on the two docs commits after it.
- The archive PR's `make ci` counts are in its PR body.

### Residual risks

- WUFI-Passive: Ed's check was one sentence. Whether WUFI-Passive shades opaque components as well as
  windows with these surfaces, how it draws or meshes a holed (bridged) polygon, and how many shading
  polygons its calculation handles in reasonable time are not observed (research note, "Not checked").
  D5s-14 (export a holed Face as one bridged polygon) stands on METr's drawing; WUFI-Passive's handling of a
  holed Face is not observed.
- The export section cost was measured at 5,000 Shading Faces (SD06, 0.055 s); what WUFI-Passive or METr do
  with that many is not measured. PHX's coplanar merge is the user's mitigation.
- Acceptance ran on SketchUp 2026 on macOS only, as every phase so far.
- The PHX round trip test (`tests/python/test_shade_phx_round_trip.py`) runs only with `uv run --group phx`
  and skips in CI.

### Awaiting Ed's confirmation

Both are shipped and bound in `context/CONTRACTS.md`; a different answer is a follow-up change.

- **D5s-11a**: assign refuses a Group inside a Zone whose mark would reach classified Faces
  (`shading.face_classified`); if one arises later, classification wins and the preflight notes it
  (`shading.classified_inside`) ([DECISIONS](DECISIONS.md)).
- **The Window Unit refusal row** added in P5s-02: a Window Unit, its pane Faces and anything inside them
  refuse as a cutting component (`shading.cutting_component`) ([PRD](PRD.md), "What can be tagged").

### Deferred follow-ups

Found in the host pass:

- The Shading Colour-by rebuild at 5,000 Shading Faces takes about 350 ms (refresh about 30 ms), over the
  200 ms target ([SD05](evidence/sd05-colour-by.md)).
- The Colour-by legend takes a display-units change at the next viewport redraw, not at once
  ([SD05](evidence/sd05-colour-by.md)).
- The Classify tool, clicked on a Shading Face inside a Zone, says "That Face is in no Zone"; it should say
  the Face is a shading surface ([SD03](evidence/sd03-zones-seam.md)).

Carried from earlier packets, not Shading's: `tools/ui-preview/assembly_hover_checks.cjs` still fails as it
did before this packet ([SD07 evidence](evidence/sd07-acceptance.md)).

## Not in this packet

A whole Zone as shading stays in the [zone-shading brief](../../features/unscheduled/zone-shading.md), which
would reuse P5s-06's section.

## Ledger

| Date | Event |
| --- | --- |
| 2026-11-20 | Ed: "WUFI looks right". SD07 recorded `pass`; SD01 to SD07 all pass on `906a102c`. Packet marked Complete and archived to `planning/archive/phase-05-shading/`. |
