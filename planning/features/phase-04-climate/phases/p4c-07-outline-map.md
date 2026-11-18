# P4c-07: The outline map

DATE: 2026-11-17
STATUS: Implemented on branch `feature/climate-p4c-07`, 2026-11-18; CM07 not run. Authorized with every Climate stage on 2026-11-17 ([STATUS](../STATUS.md#authorization)).
AUTHOR: Ed May, BLDGTYP, with Claude
ISSUE: [#511](https://github.com/ph-composer/ph-composer-skp/issues/511)

## Entry and scope

Requires P4c-06, P4c-02 and owed check 2. Owns the outline map as a UI kit part with its shipped
border data, and its first use: placing the site in Set Location, with the attached station and
its ring shown there. The station picker's use of the map is P4c-09.

Behavior: [PRD](../PRD.md), "Product boundary" and "Site location". Answers: W1, J2, J7; D4c-15;
C4c-5. Boards: 1 (`Main`, the map in Set Location), 21 (`SetLocationAttached`). Paths are
relative to `src/ph_composer/`.

Load the UI polish skill and the architecture review skill first. The map is a kit part: it
knows points, rings and borders, and nothing about climate.

## Entry checks

**Owed check 2.** Before any data is added, recorded under `evidence/`:

1. **Source and licence.** Name the dataset for world country borders and for US state and
   Canadian province borders, its version and where it was fetched from, and read its terms. The
   candidate is Natural Earth, which describes its data as public domain; the check confirms
   that by reading the terms page and records the wording and date. Anything not plainly public
   domain is refused. The attribution, if any is asked for, goes in the shipped `LICENSE.txt`.
2. **Size.** Simplify to a level that still draws recognisable state borders at the picker's
   closest zoom, generate the module, and record the bytes it adds to the RBZ through the
   runtime manifest. Budget: 300 KB added, uncompressed; over it, drop detail before dropping
   coverage. State the current RBZ size beside it.
3. **Chromium 88.** Draw the generated borders with about 1,000 markers as SVG in the browser
   evidence tool and in the real HtmlDialog; record first paint and pan and zoom frame time.
   The panel's ESLint API list must pass with no new exception.
4. **Content policy.** The data loads as a defined module from the extension's own files under
   the panel's `Content-Security-Policy`, with no fetch, no network and no violation reported
   (`tests/page_csp_test.js`).
5. C4c-5: the projection and the zoom range.

## Steps

1. **Data tool.** `tools/map_data/` (development only, not shipped): reads the public-domain
   source the developer downloads, simplifies it, and writes `html/map_borders.js` as a
   `PhComposerUI.define` module of coordinate arrays. The source files are not committed; the
   tool's README records the source, version, licence wording and the command. The generated
   module is committed and pinned by the runtime manifest.
2. **Kit part.** `html/outline_map.js` and `outline_map.css`:
   `outlineMap({ points, rings, pin, selected, onSelect, onPlace, onHover })`. It draws borders,
   markers with a tone each, rings in kilometres, and one pin; pans by drag, zooms by buttons and
   wheel, and offers Reset. `frame(bounds)` sets the view. A hover tip is the caller's content.
   Keyboard: the zoom and reset buttons are reachable; placing and selecting always have a
   non-map route (typed fields, the list).
3. **Projection** (C4c-5): equirectangular, scaled by the cosine of the view's centre latitude,
   so a 50 mile ring reads as a circle near the site. Pure functions for projecting, inverting a
   click, and a ring's outline, tested without a browser.
4. **Set Location.** The map fills the dialog's region: a click places the pin and fills
   latitude and longitude; typing moves the pin. With a station attached (board 21) the map
   shows the station and its ring, and `site.preview_limit_check` drives a warning before Set
   when the new site would make the station fail (J7). Set still saves.
5. **Development example** under `tools/examples/` showing the kit part with invented points,
   as the contributor pattern asks.
6. **Docs.** The UI polish patterns reference gains the map; `context/TECH_STACK.md`, "Panel",
   notes the shipped borders and that no tiles load; the Design System re-sync; the shipped
   `LICENSE.txt` gains the data's attribution if required.

## Source

| File | Disposition |
| --- | --- |
| `html/dom.js` (`svg`), `features/assemblies/canvas.js`, `features/windows/canvas.js` | Pattern for SVG drawing and pointer handling in the panel |
| `html/overlay.js` (`Bubble`) | The hover tip |
| `tools/panel_manifest.js`, `tools/runtime/vendor.py` | The new module in both manifests |
| `tests/page_csp_test.js` | The policy the map must load under |

## Tests (write first)

1. Projection: a point projects and inverts to itself; a ring of 80.4672 km is equidistant from
   its centre by the limit check's own distance function at three latitudes.
2. The kit part renders borders, markers and a ring from invented data; select, place and hover
   call back with the right ids and coordinates; pan and zoom keep the pin under the cursor.
3. Set Location: a click fills latitude and longitude; typed values move the pin; with an
   attached station the warning shows for a failing site and not for a passing one.
4. The page reaches no network and reports no content-policy violation with the map open.
5. Browser checks at the three panel sizes; the map never forces horizontal scroll.
6. The generated module is deterministic for the same source and settings.

## Host gate

CM07 in [ACCEPTANCE](../ACCEPTANCE.md).

## Leaves for the next stage

P4c-09 reuses the kit part for the picker, with every station as a marker.

## Done when

CM07 passes, owed check 2 is recorded with the licence wording, and C4c-5 is answered.

## Departures, 2026-11-18

- **Owed check 2** ([evidence](../evidence/owed-check-2-20261118.md)): Natural Earth 5.1.2 at 1:50m, public
  domain with no attribution asked, so the shipped `LICENSE.txt` is unchanged. The borders are written in the
  encoded polyline algorithm (90 KB), not as decimal arrays (187 KB): both fit the 300 KB budget, but the decimal
  draft left 70 KB under the runtime manifest's installed ceiling for P4c-08 to P4c-11.
- **The tool** is `tools/map_data/map_borders.py`, a standard-library PEP 723 script, with
  `tests/python/test_map_borders.py` (synthetic GeoJSON; the real source when `PH_COMPOSER_MAP_DATA` is set).
- **Projection** lives in its own module, `html/map_projection.js`, so its tests need no DOM. The
  ring test's "the limit check's own distance function" is a Ruby test (`tests/map_ring_test.rb`) measuring
  the shared ring points in `tests/support/map_ring_vectors.json` with `LimitCheck.distance_km`; the panel's ring
  function is held to the same points in JavaScript, and the panel's copy of the 80.4672 km limit to the file's.
- **Hover tip**: the map's own positioned tip, not a `Bubble`. Markers are SVG nodes redrawn on every pan and
  zoom frame, which a `Bubble` trigger cannot be; the tip still holds the owner's content.
- **Set Location** reads the attached station once on open with `climate.climate.get` (an existing query), so
  no operation or API version changed. The dialog grows to board 21's two columns (940 px), the map above the
  fields below 760 px at 220 px tall. The warning is the amber warning tone, not board 21's red: the site still
  saves. It names the failing limits (distance, elevation or both) from the host's preview, asked one request at
  a time, and an answer for values no longer typed is not shown.
- **Limits in Phius's units**: the ring label and the warning give the limits as Phius states them, 50 mi and
  400 ft, in both display systems; the measured distance and elevation follow the display units.
- **Sonnet read-through before the gate**: 12 findings. Fixed: a late station read reframing a map the user had
  moved; typed coordinates off the view now pan to them; a pressed marker's tip coming back; a release of
  another button ending a left press, and an uncaptured press ending when the pointer leaves; pan and wheel
  painted once per display frame; the wheel over the zoom buttons zooms; a failed limit check now says so; the
  preview host's double takes the Ruby's floating-point slack. Kept: a preview per keystroke (one at a time,
  stale answers dropped); a ring near ±180° longitude is not wrapped (the borders stop there too, and no Phius
  station is near it); tests 4 and 5 are browser evidence, outside `make ci`, as every panel browser check is.
- **Not built**: board 21's pane map (the Site location pane drawing the site on the map) is in no stage's steps;
  left for Ed to place.
- **Example**: `tools/examples/outline_map/example_outline_map.js`, loaded by the preview page and shown with
  `?example=outline_map` (`&markers=1000` for the timing).

