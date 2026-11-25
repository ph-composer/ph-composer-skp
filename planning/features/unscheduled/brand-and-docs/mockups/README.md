# Brand mock-ups

DATE: 2026-11-25
STATUS: Scoped. Working material from the 2026-11-25 prototyping session.
AUTHOR: Ed May, BLDGTYP, with Claude
ISSUE: none (local planning draft)

## What is here

- `generator/lift_mark.py`: draws the mark as SVG from a short list of blocks. Run it with
  `uv run generator/lift_mark.py marks` from this folder.
- `marks/`: the generator's output. `lift.svg` is the mark, `lift-plain.svg` the small-size
  variant, `lift-product*.svg` take the lifted block's colour from `color`, and `crane.svg` is the
  splash illustration.
- `canvas/project/`: the source of the Design canvas, one `*.dc.html` file per board plus
  `canvas.json`. The canvas itself is private to Ed.
- `canvas/ph-composer-pixel-crane.png`: the pixel-art test image the `Q-PixelCrane` board shows.
  On the canvas it is an uploaded asset; the board file refers to it by the upload's address.

## Boards

| Round | Boards | What it settled |
| --- | --- | --- |
| 1 | `Main` (Strata), `B-Score`, `C-OpenGrid` | Three first directions; all judged generic |
| 2 | `D-Beaver`, `E-Songbirds`, `F-Tortoise`, `G-House`, `H-Colour` | Illustrated marks, and three palettes set beside the Phius colours |
| 3 | `J-BeaverMarks`, `K-BeaverSystem` | The beaver developed, then dropped (BR-D10) |
| 4 | `L-StrataHiVis`, `M-StrataEmber`, `N-StrataCounter` | Strata with a colour per product, in three palettes |
| 5 | `P-HiVisLogos`, `Q-PixelCrane` | Logo variations and the pixel-art test |
| 6 | `R-AxonStack`, `S-LiftNatural` | The isometric stack; the natural palettes |
| 7 | `T-LiftBrand`, `U-CraneSplash` | The chosen direction (BR-D1 to BR-D7) |
| 8 | `V-TypeInApp`, `W-TypeBrand` | Type in the app and on the web (BR-D7, BR-D8) |
| 9 | `X-InAppColour`, `Y-HeaderBar` | Colour and logo in the app (BR-D9) |

## Notes for whoever edits these

- The boards after round 5 were assembled by script from the generator's output, so their mark
  drawings are long lists of polygons. Regenerate the mark and swap the `<symbol>` block; do not
  edit the polygons by hand.
- `T-LiftBrand` and `U-CraneSplash` are the boards to keep current. The earlier rounds are a
  record and can stay as they are.
- `H-Colour` lists the Phius brand colours as reference swatches. They are there for comparison
  only and are not part of this brand.
