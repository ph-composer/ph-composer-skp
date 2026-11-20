# Shading: tracking ledger

DATE: 2026-11-19
STATUS: Scoped. PRD, decisions, contracts, plan, acceptance and stages P5s-01 to P5s-07 written 2026-11-19; every stage authorized by Ed 2026-11-19 ([Authorization](#authorization)). P5s-01 and P5s-02 merged to main; SD01 blocked, owing two gestures. P5s-03 implemented on branch.
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
| P5s-01 Contracts and host facts | Merged to main ([#527](https://github.com/ph-composer/ph-composer-skp/pull/527), `f06f0efd`): CONTRACTS sections 4 and 7 answered, `tests/shading_mark_store_test.rb`; SD01 recorded `blocked` on `2a9c5e17` with eight of ten gestures measured ([evidence](evidence/sd01-host-facts.md)); Move-copy array and push-pull owed to a later hold | SD01 | [#527](https://github.com/ph-composer/ph-composer-skp/pull/527) |
| P5s-02 Shading mark and operations | Merged to main ([#528](https://github.com/ph-composer/ph-composer-skp/pull/528), `f0049a3d`): `features/shading/` (mark, reads, eligibility, targets, operations, selection, inventory), the envelope-exclusion flag in `core/records/entity_store.rb`, API 1.69; `tests/shading_operations_test.rb` (19 runs), `tests/shading_reads_test.rb` (3), `tests/shading_mark_store_test.rb` (4); `make ci` green on `0f14c44d` (3058 runs, 0 failures); two gpt-6-astra reviews, six findings fixed; SD02 pass on `0f14c44d` ([evidence](evidence/sd02-operations.md)) | SD02 | [#528](https://github.com/ph-composer/ph-composer-skp/pull/528) |
| P5s-03 Zones seam | Implemented on branch `feat/shading-p5s-03`: the envelope check at Zones' four funnels (`walk_faces`, `holding`, `resolve_face_path`, the export `zone_faces`) and in Spaces' candidate Faces; `face.outside_envelope`; `zones.faces.clear_classification` (D5s-11, F12); `shading.export_preflight` with `shading.zone_inside`; API 1.70; decisions in [CONTRACTS](CONTRACTS.md#what-p5s-03-decided); `tests/zones_envelope_exclusion_test.rb` (22 runs) and one Spaces offset test, call sites mapped below; SD03 not run | SD03 | |
| P5s-04 Native menu | Scoped | SD04 | |
| P5s-05 Colour-by | Scoped | SD05 | |
| P5s-06 Export | Scoped | SD06 | |
| P5s-07 Acceptance and handoff | Scoped | SD07 | |

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
| A: Solve candidates and Face splitting | `test_solve_adjacencies_does_not_pair_an_excluded_face` |
| A: Solve and Classify retirements | `test_retiring_a_pair_leaves_an_excluded_counterpart_unwritten` |
| A: stamp writer; Zone copy repair `member_entries`; split-identity repair (funnel) | `test_zone_stamp_writer_and_copy_repair_leave_out_an_excluded_face` |
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
| Shading through the seam; D5s-17 | `test_shading_tags_the_overhang_out_of_the_envelope_and_clear_brings_it_back`, `test_a_zone_made_inside_a_marked_group_keeps_its_faces_and_raises_zone_inside` |
| A Model with no shading exports byte-identically | `tests/phase_one_export_test.rb` golden unchanged; `make fixtures` moved only the API reference and guide |

## Waiting on Ed

Nothing. SD07 will ask Ed to open the WUFI XML and METr JSON.

## Not in this packet

A whole Zone as shading stays in the [zone-shading brief](../unscheduled/zone-shading.md), which
would reuse P5s-06's section.
