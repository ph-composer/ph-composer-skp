# AW-07 · Complete QA, export diagnostics and explicit repair

STATUS: Proposed, not authorized. ISSUE: https://github.com/ph-composer/ph-composer-skp/issues/435 (review/planning publication only).
DEPENDS ON: AW-04/AW-05; AW-06 for integrated library recipe.
FINDINGS: R09/R10; R16 optional. CONTRACTS: C06/C07. ACCEPTANCE: A09/A10; A16 if selected.

## Outcome

An agent can inspect every current finding, retrieve the original diagnostics of a blocked run,
perform a supported repair and verify it without an export loop or raw dictionary edits.

## Work

1. Add compact readiness/count/destination reads and bounded findings/repair pages by owner, code,
   severity and target. Keep existing whole contributor calls for their current consumers. Preserve
   complete repairs and separate oversized repair preimages from summary pages.
2. Retain and retrieve the caller's exact task finding/report detail for success, blocked and failure
   outcomes. Compact polling must preserve task/run/source identity; retrieving details must not
   consult the now-changed model or rerun translation. Reuse current retention and artifact ownership.
   Say when an early failure generated no report. Generated diagnostic content is required; written
   artifact file-byte retrieval remains AW-09's separate optional slice.
3. Reuse inexpensive extraction metadata validation in relevant preflights. Include reserved keys,
   required/unavailable extension policy and object/namespace refs; do not silently sanitize data.
   Document late Python conformance separately. Test with an otherwise export-ready model.
4. Add a dedicated preview/apply repair for malformed or stranded Thermal Bridge assignment bytes.
   Bind native occurrence, unchanged raw-content digest, revision and reference consequences. Clear
   only that owner's record, leaving geometry, Type and other dictionaries intact. Keep normal assign
   and clear strict. Update diagnostic action guidance to name a real supported route.
5. If D09 selected, add optional expected source revision at start. Source identity in retained receipts
   is already required by step 2. Refuse stale starts before filesystem recovery; preserve old callers
   and view-generation rules.

## Source and tests

`shell/dispatch.rb`, `export/{task,tasks,task_contract,record_reader,preflight_result,result_view}.rb`,
feature preflights and Thermal Bridge assignment/scan/reference code. Extend export task/preflight,
agent write-tool, metadata, artifact pair, thermal assignment/export suites. Required cases: 180
unclassified Faces; 240 distinct runtime findings; blocked report has no output pair; current model
changed after failure; expiry/close/revoke/wrong caller; partially invalid metadata; exact restored
bytes on Undo; malformed/outside-Zone/shared/locked/changed repair targets.
Large repair previews retain a reachable digest and complete reviewed affected/findings detail under
AW-04's contract before an apply may be treated as the reviewed change.

## Native gate and done

Run successful and blocked synthetic exports through the normal runtime, retrieve every diagnostic,
repair the chosen cause and export again. Verify actual HBJSON IDs/refs/values and file hashes.
Native repair Undo/Redo and save/reopen preserve the declared records. Use stronger review for repair,
retention/ownership and filesystem boundaries. Complete PLAN gates and docs-pass; no METr exporter
or arbitrary file API is included.
