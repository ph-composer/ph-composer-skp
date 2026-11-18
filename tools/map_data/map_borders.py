# /// script
# requires-python = ">=3.11"
# dependencies = []
# ///
"""Generate the panel's outline-map borders (src/ph_composer/html/map_borders.js) from Natural Earth GeoJSON.

Development only; nothing here ships. The source files are downloaded by hand and never committed
(tools/map_data/README.md records the source, version, licence and the command). The output is the same bytes
for the same source and settings: features are ordered by their country and region codes, coordinates are
rounded to a fixed grid, and nothing about the run (a date, a path) is written.

    uv run tools/map_data/map_borders.py <countries.geojson> <states.geojson>   # rewrite map_borders.js
    uv run tools/map_data/map_borders.py <countries.geojson> <states.geojson> --check

Each ring is integers in hundredths of a degree: the first longitude and latitude, then the change from the point
before. Those are written with the encoded polyline algorithm (each integer in five-bit groups as printable
characters, 63 to 126), which takes about a third of the bytes of decimal text; rings are separated by a space, and
each layer is split into lines the repository's 120-character limit allows. Only outer rings are drawn: a lake
inside a country is not a border. The United States and Canada are simplified as finely as their states and
provinces, so the country's solid outline and the dashed state lines drawn over it agree along the coast.
"""

from __future__ import annotations

import argparse
import itertools
import json
import math
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parents[2]
OUTPUT = ROOT / "src" / "ph_composer" / "html" / "map_borders.js"
GRID = 100  # stored units per degree: 0.01 degree, about 1.1 km of latitude
DIVIDED = ("USA", "CAN")  # countries with their states and provinces drawn, simplified as finely as those
LINE = 112  # a line's written string with its quotes; with the indent and comma it stays within 120


@dataclass(frozen=True)
class Settings:
    """How far a simplified line may stray from the source, in degrees, and the smallest ring kept."""

    countries_tolerance_deg: float = 0.08
    states_tolerance_deg: float = 0.02
    smallest_ring_deg2: float = 0.05


Point = tuple[float, float]


def simplify(points: list[Point], tolerance: float) -> list[Point]:
    """Douglas-Peucker on longitude and latitude as plane coordinates, keeping the first and last point."""
    if len(points) < 3:
        return list(points)
    keep = [False] * len(points)
    keep[0] = keep[-1] = True
    stack = [(0, len(points) - 1)]
    while stack:
        first, last = stack.pop()
        farthest, index = 0.0, -1
        for i in range(first + 1, last):
            distance = _offset(points[i], points[first], points[last])
            if distance > farthest:
                farthest, index = distance, i
        if index >= 0 and farthest > tolerance:
            keep[index] = True
            stack.append((first, index))
            stack.append((index, last))
    return [point for point, kept in zip(points, keep, strict=True) if kept]


def _offset(point: Point, start: Point, end: Point) -> float:
    """The distance from `point` to the segment from `start` to `end`."""
    dx, dy = end[0] - start[0], end[1] - start[1]
    length2 = dx * dx + dy * dy
    if length2 == 0:
        return math.hypot(point[0] - start[0], point[1] - start[1])
    t = max(0.0, min(1.0, ((point[0] - start[0]) * dx + (point[1] - start[1]) * dy) / length2))
    return math.hypot(point[0] - start[0] - t * dx, point[1] - start[1] - t * dy)


def _area(points: list[tuple[int, int]]) -> float:
    """The ring's area in square degrees, from its grid points."""
    twice = sum(a[0] * b[1] - b[0] * a[1] for a, b in zip(points, points[1:] + points[:1], strict=True))
    return abs(twice) / 2 / (GRID * GRID)


def encode(ring: list[Point], tolerance: float, smallest: float) -> list[int] | None:
    """One outer ring as grid integers, the first point absolute and the rest as changes; None when the
    simplified ring is too small to draw."""
    simplified = simplify(ring, tolerance)
    grid: list[tuple[int, int]] = []
    for lon, lat in simplified:
        point = (round(lon * GRID), round(lat * GRID))
        if not grid or grid[-1] != point:
            grid.append(point)
    if len(grid) > 1 and grid[0] == grid[-1]:
        grid.pop()  # the drawing closes the ring itself
    if len(grid) < 3 or _area(grid) < smallest:
        return None
    encoded = [grid[0][0], grid[0][1]]
    for before, point in itertools.pairwise(grid):
        encoded += [point[0] - before[0], point[1] - before[1]]
    return encoded


def polyline(numbers: list[int]) -> str:
    """The integers in the encoded polyline algorithm: zigzag, then five bits a character from 63 upward."""
    characters = []
    for number in numbers:
        value = ~(number << 1) if number < 0 else number << 1
        while value >= 0x20:
            characters.append(chr((0x20 | (value & 0x1F)) + 63))
            value >>= 5
        characters.append(chr(value + 63))
    return "".join(characters)


def unpolyline(text: str) -> list[int]:
    """The inverse of `polyline`."""
    numbers, value, shift = [], 0, 0
    for character in text:
        bits = ord(character) - 63
        value |= (bits & 0x1F) << shift
        shift += 5
        if bits < 0x20:
            numbers.append(~(value >> 1) if value & 1 else value >> 1)
            value, shift = 0, 0
    return numbers


def decode_layer(lines: list[str]) -> list[list[int]]:
    """A layer as the module holds it (lines of encoded rings separated by spaces) back to integers."""
    return [unpolyline(ring) for ring in "".join(lines).split(" ")]


def outer_rings(geometry: dict[str, Any]) -> list[list[Point]]:
    """The outer ring of each polygon in a Polygon or MultiPolygon."""
    kind, coordinates = geometry["type"], geometry["coordinates"]
    polygons = [coordinates] if kind == "Polygon" else coordinates if kind == "MultiPolygon" else []
    return [[(float(x), float(y)) for x, y, *_ in polygon[0]] for polygon in polygons]


def layer(features: list[dict[str, Any]], tolerance: float, smallest: float) -> list[list[int]]:
    rings = []
    for feature in features:
        for ring in outer_rings(feature["geometry"]):
            if (encoded := encode(ring, tolerance, smallest)) is not None:
                rings.append(encoded)
    return rings


def _code(feature: dict[str, Any], *keys: str) -> str:
    properties = feature["properties"]
    return "|".join(str(properties.get(key) or "") for key in keys)


def build(countries: dict[str, Any], states: dict[str, Any], settings: Settings, version: str) -> str:
    """The module's text for the two parsed GeoJSON sources."""
    world = sorted(countries["features"], key=lambda feature: _code(feature, "ADM0_A3", "NAME"))
    regions = sorted(
        (feature for feature in states["features"] if feature["properties"].get("adm0_a3") in DIVIDED),
        key=lambda feature: _code(feature, "adm0_a3", "iso_3166_2", "name"),
    )
    data = {
        "source": f"Natural Earth {version}, 1:50m Admin 0 countries and Admin 1 states and provinces",
        "licence": "Public domain (naturalearthdata.com/about/terms-of-use)",
        "grid": GRID,
        "countries": [
            ring
            for feature in world
            for ring in layer(
                [feature],
                settings.states_tolerance_deg
                if feature["properties"].get("ADM0_A3") in DIVIDED
                else settings.countries_tolerance_deg,
                settings.smallest_ring_deg2,
            )
        ],
        "states": layer(regions, settings.states_tolerance_deg, settings.smallest_ring_deg2),
    }
    body = ",\n".join(f"    {json.dumps(key)}: {_value(value)}" for key, value in data.items())
    return (
        "/* Generated by tools/map_data/map_borders.py; do not edit. World country borders and the states and\n"
        "   provinces of the United States and Canada, from Natural Earth, which is in the public domain. A layer's\n"
        "   lines joined are its rings separated by spaces, each in the encoded polyline algorithm: integers in\n"
        "   1/grid of a degree, the first longitude and latitude, then the change from the point before.\n"
        "   outline_map.js decodes and draws them; nothing is fetched. */\n"
        'PhComposerUI.define("map_borders", [], function () {\n'
        '  "use strict";\n'
        "  return {\n"
        f"{body}\n"
        "  };\n"
        "});\n"
    )


def _value(value: object) -> str:
    if isinstance(value, list):
        text = " ".join(polyline(ring) for ring in value)
        lines, chunk = [], ""
        for character in text:  # a backslash is written as two, so the limit counts the written form
            if len(json.dumps(chunk + character)) > LINE:
                lines.append(json.dumps(chunk))
                chunk = ""
            chunk += character
        lines.append(json.dumps(chunk))
        return "[\n" + ",\n".join("      " + line for line in lines) + "\n    ]"
    return json.dumps(value)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("countries", type=Path, help="ne_50m_admin_0_countries.geojson")
    parser.add_argument("states", type=Path, help="ne_50m_admin_1_states_provinces.geojson")
    parser.add_argument("--version", default="5.1.2", help="the Natural Earth version the files are from")
    parser.add_argument("--out", type=Path, default=OUTPUT)
    parser.add_argument("--check", action="store_true", help="fail when the module on disk differs")
    args = parser.parse_args(argv)
    countries = json.loads(args.countries.read_text(encoding="utf-8"))
    states = json.loads(args.states.read_text(encoding="utf-8"))
    text = build(countries, states, Settings(), args.version)
    if args.check:
        current = args.out.read_text(encoding="utf-8") if args.out.exists() else ""
        if current != text:
            print(f"{args.out} is stale; rerun without --check")
            return 1
        print(f"{args.out} is current")
        return 0
    args.out.write_text(text, encoding="utf-8")
    print(f"wrote {args.out}: {len(text.encode('utf-8'))} bytes")
    return 0


if __name__ == "__main__":
    sys.exit(main())
