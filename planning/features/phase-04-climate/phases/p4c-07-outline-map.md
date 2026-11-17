# P4c-07: The outline map

DATE: 2026-11-17
STATUS: Scoped. Not authorized.
AUTHOR: Ed May, BLDGTYP, with Claude
ISSUE: none (local planning draft)

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
