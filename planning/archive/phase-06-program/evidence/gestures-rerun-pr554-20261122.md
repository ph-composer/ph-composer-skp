# Phase 4a gesture reruns on #554's head, 2026-11-22

PR #554 head (code `09d417f9`; the ledger rows record the branch commit `f70578a2`, a docs-only commit on top),
`dist/ph_composer.rbz` sha256 `6a4863b482a51a82f6d3e3e71cefaad606d91f27cce5a108802a7d30bdd71fae`, SketchUp 26.1.188,
Ruby 3.2.2, macOS. Normal composition. Control: computer-use full-screen control from the conductor session (real
pointer and keyboard events, Edit menu by real clicks after reading the item's label); Model state read back through
the development bridge in separate calls. Fresh copies of the sitting's synthetic reference fixtures.

## PG09

House reference, Zones / Programs view. A real click on the house row's Equipment Set select and on "Residential
default devices" in the native popup saved ("House saved."): the House payload names `eqs_PHCDEFAULT01` and the
default Set is stored with its 8 devices (the sitting's refusal is gone). Edit > "Undo Change Building Segment
Settings" by real click cleared the payload and left the Set unwritten again; "Redo ..." restored both. Both
assertions pass.

## PG06

Two-Segment reference. The ADU settings opened by real hover and click showed Airtightness (n50, blank, 1/h, the
default wind exposure); a typed 0 held Save with "Airtightness: Enter a test result greater than 0, or leave it
blank."; 0.6 saved and read back; Edit > Undo and Redo of "Change Building Segment Settings" by real clicks removed
and restored it. All four assertions pass.

## PG02

Two-Segment reference. + New Building Segment by real click opened its name in place; "Annex" and a real Return
created it. Bath moved into Annex from the selection bar's native popup; Edit > "Undo Edit Selected Zones" and
"Redo ..." by real clicks moved it back and forth. The Annex trash, by real hover and click, asked where Bath goes;
House chosen and Delete moved it and removed Annex. All four assertions pass.

## PG12

Apartments reference. Real clicks walked Zones > Geometry, Spaces and Programs, the Programs tab and the Export tab,
each opening as in the sitting (heading tags, locked Program pills, the Residential default with its cards and
library sidebar, the Worth checking rows). All three assertions pass; the PG12 PHX device rows stay failed in the
bridge rerun.
