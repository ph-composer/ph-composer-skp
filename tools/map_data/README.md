# Outline map data

Development only; nothing here ships. `map_borders.py` writes `src/ph_composer/html/map_borders.js`, the
borders the panel's outline map draws (`html/outline_map.js`). The generated module is committed and pinned by
the runtime manifest; the source files are not committed.

## Source

| | |
| --- | --- |
| Dataset | Natural Earth 5.1.2: `ne_50m_admin_0_countries.geojson` and `ne_50m_admin_1_states_provinces.geojson` |
| Where | The official repository, `https://github.com/nvkelso/natural-earth-vector`, tag `v5.1.2`, folder `geojson/` |
| Licence | Public domain. The terms page (`https://www.naturalearthdata.com/about/terms-of-use/`, read 2026-11-18): "All versions of Natural Earth raster + vector map data found on this website are in the public domain." and "No permission is needed to use Natural Earth. Crediting the authors is unnecessary." |

Download the two data files into a folder outside the tracked tree (the repository keeps them in the gitignored
`_private/map_data/`, with a `MANIFEST.md` of their checksums). Never commit them.

## Command

```sh
uv run tools/map_data/map_borders.py <folder>/ne_50m_admin_0_countries.geojson \
  <folder>/ne_50m_admin_1_states_provinces.geojson            # rewrite the module
uv run tools/map_data/map_borders.py <countries> <states> --check   # fail if the module differs
```

Then `make runtime-manifest` and `make rbz`, since the module is a shipped panel file.

The same source and settings give the same bytes. Settings live in `Settings` in the script: how far a simplified
line may stray (0.08° for countries, 0.02° for United States and Canadian states and provinces) and the smallest
ring kept (0.05 square degrees). Coordinates are rounded to 0.01°. Rings are written in the encoded polyline
algorithm, about a third of the bytes of decimal text. The United States and Canada are drawn from their states
and provinces only, so their outline is not drawn twice.

The extension's installed size has a ceiling (`tools/runtime/vendor.py`); the map was held to 300 KB added and
uses about 90 KB. Coarser settings come before dropping a layer.

`tests/python/test_map_borders.py` checks the script on synthetic GeoJSON, and checks the committed module
against the real files when `PH_COMPOSER_MAP_DATA` names their folder.
