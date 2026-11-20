# SD06: Shading export on the host

DATE: 2026-11-20
STATUS: Recorded. Bridge-only host run from the packaged RBZ.
AUTHOR: Ed May, BLDGTYP, with Claude
ISSUE: [#526](https://github.com/ph-composer/ph-composer-skp/issues/526)

Head `906a102c` (main after #533), SketchUp 26.1.188, Ruby 3.2.2, panel closed. Driver and run files are under
`_private/host/sd06-20261119/` (not tracked). The ledger row is in
[`results.jsonl`](../../../native-acceptance/results.jsonl).

## What ran

1. The reference model, built in a fresh copy of the blank template: Zone A made through `zones.make`, its six
   Faces classified and given a synthetic Assembly, then nine targets tagged through `shading.assign` in one
   operation.
2. Export from the installed RBZ: `export.complete`, HBJSON and report written. The three findings are the
   synthetic Assembly's type and exterior-condition mismatches; none concerns shading.
3. Save, quit, fresh launch of the saved file, export again.
4. Offline read-back of both HBJSON files through the pinned PHX.
5. A second Model with 5,000 Shading Faces, timed.

## Results

| Assertion | Result |
| --- | --- |
| Shades | 18 orphaned Shades; the Room still exports (1 Room) |
| Names | Fin 2, Louvre 6, Neighbour 6, Shading 3, Zone A Shading 1 |
| Detached | `is_detached` true on all 18; one Shade keeps its hole |
| Conformance | Passed: the export wrote its files, which it does only after conformance |
| Report | The Shading section lists the five components and "18 Shades in 5 shading components, 100.20 m² in all" |
| Attach refusal | Offline only: `test_a_refused_shade_is_left_out_with_a_non_blocking_finding_and_the_model_is_still_written` |
| PHX | One Variant; five shading components in WUFI XML and METr JSON; `InnerAttachment` -1, `idIC` -1; areas match the report |
| Re-export | The reopened Model's HBJSON equals the first, identifiers normalized |
| Cost at 5,000 Shading Faces | Extraction 0.454 s with the Shades section, 0.399 s without; Shading preflight 0.252 s |

The first timing assign was refused `target.not_found`: the test driver's cached API connection still pointed at
the previous Model. It was reset and the assign rerun through the public action. The product was not involved.

The WUFI XML and METr JSON converted from this export are for Ed's check in SD07.
