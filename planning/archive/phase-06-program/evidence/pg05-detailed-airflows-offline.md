# PG05: Detailed airflows per Zone, offline rows, browser checks and PHX read-back

DATE: 2026-11-20
STATUS: Offline rows, the browser checks and the PHX read-back pass on the stage branch; the Spaces gestures in SketchUp and the installed-RBZ export are owed to the batched sitting under case `PG05`.
AUTHOR: Ed May, BLDGTYP, with Claude
ISSUE: [#538](https://github.com/ph-composer/ph-composer-skp/issues/538)

Run by the P4a-05 stage, offline: the Ruby suite against the SketchUp stub, the panel tests in Node, the Spaces
browser check in the preview (`make ui-checks UI_CHECKS=tools/ui-preview/spaces_checks.cjs`, a local Chrome,
not HtmlDialog or Chromium 88 evidence) and the Python translation with the optional `phx` group. SketchUp was
not launched: the earlier stages' launches reached no bridge.

## The references

The Spaces reference model (`tests/support/space_fixtures.rb`): Zone A holds Living (supply 60), Bath (extract
40) and Hall (transfer 20), so it is detailed; Zone B holds Loft with no rate, so it is By Program. The panel
and preview fixtures are the same model. The PHX round trip uses the two-Segment reference golden
(`tests/fixtures/segments/extraction.json`), whose Segment name holds no space, which PHX 1.59.1's
`cleanup.merge_rooms` refuses (P4a-03).

## Rows

| Assertion | Result | Evidence |
| --- | --- | --- |
| A Zone with no rates reads By Program and exports `None` | Pass | Reads: Zone B `airflow_mode` `by_program`, airflows null, Loft's copy `by_program` (`tests/spaces_reads_test.rb`, `test_zone_airflow_mode_and_sums`). Extraction: Loft's record carries `by_program` and no rate (`tests/spaces_zone_airflows_test.rb`). Python: every Space of a `by_program` Zone writes `_v_sup`, `_v_eta`, `_v_tran` as `None` (`tests/python/test_space_sections.py`, `test_a_blank_space_in_a_detailed_zone_writes_zero_and_a_by_program_zone_writes_none`). Panel: Loft reads a muted "By Program" (`tests/spaces_view_panel_test.js`, `spaces_cells_panel_test.js`, browser check) |
| One entered rate makes every Space in the Zone export its rates, 0 for blanks | Pass | `Metrics.zone_modes` (`tests/spaces_records_test.rb`, `test_one_rate_makes_the_zone_detailed_and_clearing_the_last_returns_it_to_by_program`); Python: a blank Space of a detailed Zone writes (0, 0, 0) and the rated one its supply; a record with no mode, an unknown one or a rate under `by_program` costs its Space. PHX 1.59.1: with a 360 m3/h Program load on every Room, the blank Space's PhxSpace load is 0 supply and 0 extract, so WUFI XML and METr JSON leave it out of their ventilation rooms; the rated Space reads 60 / 0 and the By Program Zone's only Space 360 / 360 (`tests/python/test_space_airflow_phx_round_trip.py`, run with `-rs`, not skipped) |
| The notice on the first entry | Pass | A rate typed on Loft: "Zone B now uses detailed airflows.", tone `info`, and with Stair beside it "…: its other Space exports 0 until you enter its rates."; one write switching two Zones names both in one notice; no notice when a Zone turns detailed with nothing of the view's in flight, as on Undo (`tests/spaces_zone_airflows_panel_test.js`); SketchUp's Set Airflows menu shows the same notice, tone `info`, for a first rate on Loft and none for a further rate in a detailed Zone (`tests/spaces_edit_menu_test.rb`); browser check: "Attic Zone now uses detailed airflows." after typing 30, Loft extract then reads 0 (`spaces-detailed-notice.png`) |
| From Program clears the Zone in one Undo step | Pass | `clear_zone_airflows` on Zone A: three Spaces cleared, one operation, Zone A `by_program`; Undo restores Living's 60 and the detailed mode; a By Program Zone writes nothing; a locked Space refuses the whole call `target.locked` with nothing written (`tests/spaces_zone_airflows_test.rb`). Panel: offered on a detailed Zone row only, confirms naming how many Spaces' rates go, Cancel sends nothing, Clear airflows sends the Zone reference (`tests/spaces_zone_airflows_panel_test.js`); browser check through the preview host (`spaces-from-program.png`). Clearing the last rate by hand returns the Zone to By Program (`tests/spaces_edit_menu_test.rb`, `tests/spaces_operations_test.rb`) |
| Zone sums | Pass | Zone A sums 60 / 40 / 20, Zone B's null and a dash with the By Program tooltip; a Segment's airflows are null while one of its Zones that hold Spaces is By Program (`by_program_zone_count`), and a Zone with no Spaces neither counts nor hides them (`test_a_zone_with_no_spaces_leaves_its_segments_sums_shown`); the export report reads "By Program" cells and a dash total (`tests/spaces_export_test.rb`) |
| The No Spaces warning in preflight | Pass | `space.zone_without_spaces`, not blocking, names an exported Zone with no Spaces; a left-out Zone is skipped and a copied Zone's rows are read together by id (`tests/spaces_zone_airflows_test.rb`). Panel: the amber No Spaces row with its alert marker and reason (`tests/spaces_zone_airflows_panel_test.js`; browser check `spaces-no-spaces.png`) |
| The agent reads per the C4a-6 answer | Pass | Each Zone row of `spaces.list` and `spaces.all` carries `airflow_mode`; each Space row a copy (`test_zone_airflow_mode_and_sums`); `docs/API_REFERENCE.md` regenerated; API 1.77 |
| Transfer header tooltip | Pass | "Transfer air reaches PHPP only. WUFI-Passive and METr receive supply and extract." (`tests/spaces_zone_airflows_panel_test.js`, browser check) |
| The Spaces gestures in SketchUp with Ed at the mouse, From Program's native Undo and Redo, the RBZ export round trip | Owed | Batched sitting, case `PG05` in the case ledger |

## Limits found

- PHX writes only Spaces with airflow into WUFI-Passive's and METr's ventilation rooms, so a blank Space of a
  detailed Zone is absent there rather than listed at 0 (PHX `PhxBuilding`, `building.py`).
- Until P4a-10 exports the Program's ventilation load, a By Program Zone's Spaces reach PHX with no flow.
