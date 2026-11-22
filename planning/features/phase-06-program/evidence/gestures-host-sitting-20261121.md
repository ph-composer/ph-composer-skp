# Phase 4a host sitting: real panel gestures, 2026-11-21

Commit `08a06474` (origin/main), `dist/ph_composer.rbz` sha256 `4f3f3d66d2e3efd7702fa52191b8145492230102dcbd796ccec182fcd38a4cfe`,
SketchUp 26.1.188, Ruby 3.2.2, macOS. Normal composition: no development callback or style in the panel. Control:
computer-use full-screen control from the conductor session (real pointer and keyboard events, Edit menu by real
clicks after reading the item's label); Model state read back through the development bridge in separate calls.
Fixtures are the synthetic reference models built through public operations in the sitting's run folder (private).
Earlier runs of each case in this sitting (bridge rows, scripted panel rows) are in their own evidence files.

## PG05

Apartments reference, fresh copy. Spaces sub-tab by real click. A rate typed into Apt 101 Living's supply cell and
committed with a real Return switched the Zone to detailed with the notice; its other Spaces read 0 (the scripted
Enter of the earlier panel run did not commit; the real one does). From Program, revealed by real pointer hover on
the Zone row, confirmed and cleared every Space. Edit > "Undo Clear Zone Airflows" and "Redo Clear Zone Airflows"
by real clicks restored and cleared the rates. All three assertions pass.

## PG04

Two-Segment reference, fresh copy. Real pointer hover revealed the ADU heading's gear; a real click opened Building
Segment settings, its Phius certification section at the defaults. Building status changed in the native popup and
saved by real clicks ("ADU settings saved."); the stored payload read back. Edit > "Undo Change Building Segment
Settings" and "Redo ..." by real clicks removed and restored it. All three assertions pass.

## PG06

Two-Segment reference, fresh copy. The ADU settings opened by real hover and click; the Airtightness section showed
n50, a blank result, 1/h and the default wind exposure. A typed 0 held Save with "Airtightness: Enter a test result
greater than 0, or leave it blank."; 0.6 saved and read back (basis n50, value 0.6). Edit > Undo and Redo of "Change
Building Segment Settings" by real clicks removed and restored it. All four assertions pass. The unit still sits
under the field rather than beside it (the layout defect the panel run recorded).

## PG03

Two-Segment reference, fresh copy. ADU Living checked by a real click and moved to No Building Segment from the
selection bar's native popup: the offer "Make ADU Living an Attached zone?" named its one Face shared with
Living-Kitchen. A real click on Make Attached zone created the Attached zone (one Face on it, read back). Moving the
Zone back to ADU by real clicks showed the notice to run Solve adjacencies. All three assertions pass. The offer's
primary button still carries the trash-can icon the panel run recorded.

## PG08

House reference, fresh copy. Real clicks through Geometry, Spaces and Programs showed the House heading's Default and
Single dwelling tags in each, and the amber bedrooms finding in Programs. Single dwelling switched off in the
settings by real clicks made a stored House Dwelling with the five Zones; Edit > Undo and Redo of "Change Building
Segment Settings" by real clicks reverted and restored it. Switched back on, the dialog noted that saving replaces
the Dwelling with the house, and Save returned the Segment to a single dwelling. All four assertions pass; the
heading's bedrooms "?" stays after Single dwelling is off (recorded defect).

## PG10

Five-journey reference, fresh copy. The Apartments settings, opened and scrolled by real input, showed Comfort at
18 °C heating and 26 °C cooling with the note that its Zones' Programs disagree. The Export tab, by real click,
listed the set-point and Equipment Set rows; a real click on the School row's Locate opened the Zones / Programs view
with School's two Zones checked. Both assertions pass. Locate also opens the Segment's settings dialog, the checked
rows sit under the selection bar, and the text reads "Apartments's" (recorded defects).

## PG12

Apartments reference, fresh copy. Real clicks walked Zones > Geometry, Spaces and Programs, the Programs tab and the
Export tab: each opened with the Segment heading and tags, Spaces By Program, the locked Program pills, the
Residential default Program with its cards and library sidebar, and the export's Worth checking rows. All three
assertions pass. This walk covers the panel half of the integrated run; its export rows and the PHX device failures
are in the bridge run's evidence.

## PG02

Two-Segment reference, fresh copy. + New Building Segment by real click opened its name in place; typed "Annex" and
a real Return created it. Bath moved into Annex from the selection bar's native popup; Edit > "Undo Edit Selected
Zones" and "Redo ..." by real clicks moved it back and forth (the Segment's creation is its own "Manage Zone
Options" step). The Annex heading's trash, by real hover and click, asked where its one Zone goes; House chosen,
Delete moved Bath to House and removed Annex. All four assertions pass. The in-place name field shows "...g Segment
3" (the narrow-field defect).

## PG09

House reference, fresh copy, Zones / Programs view. Bedrooms typed on the house row and committed with a real Return
saved 3 bedrooms (Occupants a muted 4 by the Phius rule). A real click on a locked Program pill opened the bubble
"House is a single dwelling" with Open settings; a real Escape closed it. Edit > Undo and Redo of "Change Building
Segment Settings" by real clicks removed and restored the bedrooms. **Fail**: choosing "Residential default devices"
on the house row by real clicks is refused, "ph_composer.programs.equipment_set.eqs_PHCDEFAULT01 does not exist.
Nothing was written." The default Equipment Set cannot be chosen while it has never been written.

## PG11

House reference, fresh copy, Programs tab by real click. The Occupancy card opened and closed under real clicks and
opened again from the keyboard (Return on its focused head). "Use a fixed value" and a typed 0.05 committed with a
real Return stored the default Program with 0.05 people per m2; Edit > "Undo Edit Program" and "Redo Edit Program"
by real clicks removed and restored the value. + New Program opened its title in place; typed "Office" and a real
Return created and opened it. All four assertions pass.

## PG11b

House reference, fresh copy. In the Constant ventilation Schedule, 2 hours typed into High turned every period amber
with "Total 26 of 24 h"; a real Escape restored the periods. A device added through Add device by real clicks and
typing ("Second dishwasher") made the default Set stored with 9 devices; Edit > "Undo Add Device" and "Redo Add
Device" by real clicks returned it to the unwritten 8 and back. All three assertions pass. After the Escape the
fraction field kept focus and the subtab switch was refused with "Finish editing the focused field before changing
sections." until a click elsewhere (the recorded subtabs.js follow-up).
