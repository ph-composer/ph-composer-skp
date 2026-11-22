# Visual fixes: host check of #555, 2026-11-22

PR #555 head `dd83bc2c`, `dist/ph_composer.rbz` sha256 `b8dba137...` installed, SketchUp 26.1.188, macOS. Real pointer
and keyboard input under one full-screen hold from the conductor session; the panel sized by labelled
`Panel.show`/`set_size` setup; fresh copies of the sitting's synthetic reference models. An observation run, not a
ledger case: the panel files this PR changes are dependencies of most PG cases, so those cases' ledger rows are
stale by path until their next run; this check shows the fixed behaviour on the host.

| Item | Host observation |
| --- | --- |
| 1 Airtightness row | Test result basis, value field and "1/h" on one line in the Apartments settings |
| 2 Attached zone offer | "Make Attached zone" a primary button with no trash icon |
| 3 Locate | Locate on the Apartments set-point row opened Zones / Programs with its 4 Zones checked and visible above the selection bar; no settings dialog |
| 4 Possessive | "The Programs of Apartments' Zones give different set points" |
| 5 Heading after Single dwelling off | House saved with Single dwelling off: no amber bedrooms "?" on its heading |
| 6 No Spaces row | Storage's amber Note row spans the full row |
| 7 New Segment name | The in-place field shows "Building Segment 4" whole, in view |
| 8 Headings at 360 px | At 360 px wide the table pans to Name; the "Apartments" heading name shows |
| 9 Bubble and pills | "Not part of a Dwelling" wraps inside the bubble; locked Equipment Set pills read "Residential default devices" |
| 10 Devices | Device names and "Phius rule: bedrooms and iCFA" show whole; the dialog's Type help sits on its own line |
| 11 Subtabs | After typing in a Schedule field and Escape, Equipment Sets opened with no "Finish editing" block |

All eleven pass. Captures are kept privately with the sitting's run folder.
