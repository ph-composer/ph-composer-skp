# Mechanical tab wireframes

DATE: 2026-11-15
STATUS: Reviewed. Ed reviewed these on 2026-11-15 and answered D4-13 to D4-20 against them ([DECISIONS, Part 3](../DECISIONS.md#part-3-wireframe-review-2026-11-15)). Static wireframes, not a screen; no panel code. Six items stay open there.
AUTHOR: Ed May, BLDGTYP, with Claude
ISSUE: none (local planning draft)

Ten static artboards of the Mechanical tab, drawn to settle the tab's navigation, the tables each
equipment family needs and what each exports. The decisions are the record; these illustrate them.
All data is synthetic, and every derived number on the Blended result board is a placeholder.

## Viewing

- Local: `make ui-preview`, then open
  `http://127.0.0.1:8765/planning/features/phase-04-mechanical/mockups/`. `index.html` frames each
  artboard with the panel's own stylesheets and shows its notes beneath it. `?board=Main` shows
  one board, named by its file without `.dc.html`.
- Design canvas: the same files are published to a private Design canvas built on the PH-Composer
  Design System. `canvas/project/` is that canvas's source: `canvas.json` is its index (artboard
  frames and the notes) and each `*.dc.html` is one artboard. The `support.js` and `ds/` paths in
  an artboard resolve only on the canvas.

## Boards

| # | File | Shows |
| --- | --- | --- |
| 1 | `Main.dc.html` | Ventilation › Ventilators, with the Zone picker for Serves open |
| 2 | `HeatPumpsEquipOutdoor.dc.html` | Heat Pumps › Equipment · Outdoor: the Phius estimator's inputs, and Paired indoor |
| 3 | `HeatPumpsEquipIndoor.dc.html` | Heat Pumps › Equipment · Indoor, identity columns only (open item 1) |
| 4 | `HeatPumpsUnitsIndoor.dc.html` | Heat Pumps › Units · Indoor, grouped by outdoor unit, carrying Serves |
| 5 | `HeatPumpsBlended.dc.html` | Heat Pumps › Blended result, in the Phius estimator's sections, shown in IP |
| 6 | `HotWaterSystems.dc.html` | Hot Water › Systems: Serves, tap points, read-only recirculation, the pooling note |
| 7 | `HotWater.dc.html` | Hot Water › Heaters |
| 8 | `HotWaterTanks.dc.html` | Hot Water › Tanks, with Role and the export slot |
| 9 | `Pumps.dc.html` | Pumps, also the pattern for Fans and Electric Heating |
| 10 | `Narrow.dc.html` | Ventilation at 420 px wide |

Not drawn: Heat Pumps › Units · Outdoor, Fans, Electric Heating, row actions, the New-record
forms, the Ventilator disclosure for its two optional fields, and the 360 x 520 panel size.

## Checked

Every board loads in the local viewer with no console error and each table's rows match its
header. The Design canvas rendering was not checked.
