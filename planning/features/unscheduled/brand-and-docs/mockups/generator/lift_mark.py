# /// script
# requires-python = ">=3.11"
# dependencies = []
# ///
"""Draw the PH-Composer "Lift" mark as SVG.

The mark is a stack of blocks in true isometric projection: pale blocks on a maple slab, with one
coloured block held above its place. Run `uv run lift_mark.py <out-dir>` to write every variant:

- `lift.svg`, the full mark with windows
- `lift-plain.svg`, the same without windows, for 24 px and smaller
- `lift-product.svg` and `lift-product-plain.svg`, whose lifted block is `currentColor`, so a
  product colour is set by the `color` of the element that embeds it
- `crane.svg`, the enlarged version with a tower crane holding the lifted block
"""

from __future__ import annotations

import math
import sys
from dataclasses import dataclass
from pathlib import Path

UNIT = 40.0
COS_30 = math.cos(math.radians(30))
STOREY = 0.8
SHADE = "#3a2a1c"

WHITE = "#f6f3ec"
MAPLE = "#d9a66b"
MAPLE_DEEP = "#c68a4e"
GREEN = "#b8d430"
ORANGE = "#f2691e"
ESPRESSO = "#33261d"
GLASS = "#3a2e26"
CURRENT = "currentColor"

Point = tuple[float, float]


@dataclass(frozen=True)
class Box:
    """One block: its near-origin corner, its size, its colour and whether it has windows."""

    x: float
    y: float
    z: float
    width: float
    depth: float
    height: float
    colour: str
    windows: bool = False
    gap: float = 0.04


def project(x: float, y: float, z: float) -> Point:
    """Map a model point to the page: x runs right and down, y left and down, z up."""
    return ((x - y) * COS_30 * UNIT, (x + y) * 0.5 * UNIT - z * UNIT)


def mix(colour: str, toward: str, amount: float) -> str:
    """Blend one hex colour toward another."""
    start = [int(colour[i : i + 2], 16) for i in (1, 3, 5)]
    end = [int(toward[i : i + 2], 16) for i in (1, 3, 5)]
    return "#" + "".join(f"{round(a + (b - a) * amount):02x}" for a, b in zip(start, end, strict=True))


def polygon(points: list[Point], fill: str, opacity: float | None = None) -> str:
    """One filled SVG polygon."""
    coords = " ".join(f"{px:.1f},{py:.1f}" for px, py in points)
    alpha = "" if opacity is None else f' fill-opacity="{opacity}"'
    return f'<polygon points="{coords}" fill="{fill}"{alpha}></polygon>'


def line(start: Point, end: Point, colour: str, width: float = 2.4) -> str:
    """One round-capped SVG line."""
    return (
        f'<path d="M{start[0]:.1f} {start[1]:.1f} L{end[0]:.1f} {end[1]:.1f}" stroke="{colour}" '
        f'stroke-width="{width}" stroke-linecap="round" fill="none"></path>'
    )


def draw_box(box: Box) -> tuple[list[str], list[Point]]:
    """The three visible faces of a block, then its windows, with the points they cover."""
    x0, y0 = box.x + box.gap, box.y + box.gap
    x1, y1 = box.x + box.width - box.gap, box.y + box.depth - box.gap
    z0, z1 = box.z + box.gap * 0.6, box.z + box.height - box.gap * 0.6
    top = [project(x0, y0, z1), project(x1, y0, z1), project(x1, y1, z1), project(x0, y1, z1)]
    left = [project(x0, y1, z1), project(x1, y1, z1), project(x1, y1, z0), project(x0, y1, z0)]
    right = [project(x1, y0, z1), project(x1, y1, z1), project(x1, y1, z0), project(x1, y0, z0)]

    if box.colour == CURRENT:
        shapes = [
            polygon(left, CURRENT),
            polygon(right, CURRENT),
            polygon(right, SHADE, 0.28),
            polygon(left, SHADE, 0.1),
            polygon(top, CURRENT),
            polygon(top, "#ffffff", 0.16),
        ]
    else:
        pale = box.colour == WHITE
        left_shade, right_shade, top_light = (0.07, 0.17, 0.35) if pale else (0.1, 0.28, 0.16)
        shapes = [
            polygon(left, mix(box.colour, SHADE, left_shade)),
            polygon(right, mix(box.colour, SHADE, right_shade)),
            polygon(top, mix(box.colour, "#ffffff", top_light)),
        ]

    if box.windows:
        dark_glass = box.colour in (WHITE, MAPLE)
        fill, left_alpha, right_alpha = (GLASS, 0.72, 0.85) if dark_glass else ("#ffffff", 0.88, 0.62)
        half_w, half_h = 0.1 * box.width, 0.1 * box.height
        for column in range(2):
            for row in range(2):
                cx = x0 + (x1 - x0) * (column + 0.5) / 2
                cy = y0 + (y1 - y0) * (column + 0.5) / 2
                cz = z0 + (z1 - z0) * (row + 0.5) / 2
                on_left = [
                    project(cx - half_w, y1, cz + half_h),
                    project(cx + half_w, y1, cz + half_h),
                    project(cx + half_w, y1, cz - half_h),
                    project(cx - half_w, y1, cz - half_h),
                ]
                on_right = [
                    project(x1, cy - half_w, cz + half_h),
                    project(x1, cy + half_w, cz + half_h),
                    project(x1, cy + half_w, cz - half_h),
                    project(x1, cy - half_w, cz - half_h),
                ]
                shapes += [polygon(on_left, fill, left_alpha), polygon(on_right, fill, right_alpha)]
    return shapes, top + left + right


def draw_boxes(boxes: list[Box]) -> tuple[list[str], list[Point]]:
    """Draw blocks back to front: lower first, then farther from the viewer first."""
    shapes: list[str] = []
    points: list[Point] = []
    for box in sorted(boxes, key=lambda b: (b.z, b.x + b.y)):
        drawn, covered = draw_box(box)
        shapes += drawn
        points += covered
    return shapes, points


def square_view_box(points: list[Point], pad: float = 4) -> str:
    """A square viewBox centred on the drawing."""
    xs = [p[0] for p in points]
    ys = [p[1] for p in points]
    width = max(xs) - min(xs) + 2 * pad
    height = max(ys) - min(ys) + 2 * pad
    side = max(width, height)
    left = min(xs) - pad - (side - width) / 2
    top = min(ys) - pad - (side - height) / 2
    return f"{left:.1f} {top:.1f} {side:.1f} {side:.1f}"


def stack(lifted: str, windows: bool, lift_height: float, slab_from: float = -0.2) -> list[Box]:
    """The slab, two storeys of pale blocks with one maple block, and the lifted block."""
    slab = Box(slab_from, -0.2, -0.2, 2.2 - slab_from, 2.4, 0.2, MAPLE_DEEP, gap=0)
    ground = [Box(x, y, 0, 1, 1, STOREY, WHITE, windows) for x, y in ((0, 0), (1, 0), (0, 1), (1, 1))]
    upper = [
        Box(0, 0, STOREY, 1, 1, STOREY, WHITE, windows),
        Box(1, 0, STOREY, 1, 1, STOREY, WHITE, windows),
        Box(0, 1, STOREY, 1, 1, STOREY, MAPLE, windows),
        Box(1, 1, lift_height, 1, 1, STOREY, lifted, windows),
    ]
    return [slab, *ground, *upper]


def lift_mark(lifted: str = GREEN, windows: bool = True) -> tuple[str, str]:
    """The mark: viewBox and SVG body."""
    shapes, points = draw_boxes(stack(lifted, windows, STOREY + 0.55))
    return square_view_box(points), "\n".join(shapes)


def crane_mark(steel: str = ORANGE, cab: str = WHITE) -> tuple[str, str]:
    """The mark with a tower crane holding the lifted block: viewBox and SVG body."""
    jib_height = 3.7
    lift_height = STOREY + 0.8
    mast = Box(-0.93, 1.37, 0, 0.26, 0.26, jib_height, steel, gap=0)
    shapes, points = draw_boxes([*stack(GREEN, True, lift_height, slab_from=-1.35), mast])

    hook = project(1.5, 1.5, lift_height + STOREY + 0.5)
    shapes.append(line(project(1.5, 1.5, jib_height), hook, steel))
    for strap_x, strap_y in ((1.74, 1.26), (1.26, 1.74)):
        shapes.append(line(hook, project(strap_x, strap_y, lift_height + STOREY), steel))

    upper = [
        Box(-1.75, 1.28, jib_height - 0.42, 0.5, 0.44, 0.42, MAPLE_DEEP, gap=0),
        Box(-1.75, 1.42, jib_height, 4.3, 0.16, 0.14, steel, gap=0),
        Box(-1.02, 1.28, jib_height - 0.5, 0.44, 0.44, 0.5, cab, gap=0),
    ]
    for box in upper:
        drawn, covered = draw_box(box)
        shapes += drawn
        points += covered

    apex = project(-0.8, 1.5, jib_height + 0.75)
    for tie_x in (1.6, -1.6):
        shapes.append(line(apex, project(tie_x, 1.5, jib_height + 0.14), steel))
    shapes.append(line(apex, project(-0.8, 1.5, jib_height + 0.14), steel, width=4))
    points.append(apex)
    return square_view_box(points, pad=5), "\n".join(shapes)


def write_svg(path: Path, view_box: str, body: str) -> None:
    """Write one standalone SVG file."""
    path.write_text(f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="{view_box}">\n{body}\n</svg>\n')


def main(out_dir: Path) -> None:
    """Write every variant of the mark into `out_dir`."""
    out_dir.mkdir(parents=True, exist_ok=True)
    variants = {
        "lift": lift_mark(GREEN, True),
        "lift-plain": lift_mark(GREEN, False),
        "lift-product": lift_mark(CURRENT, True),
        "lift-product-plain": lift_mark(CURRENT, False),
        "crane": crane_mark(),
    }
    for name, (view_box, body) in variants.items():
        write_svg(out_dir / f"{name}.svg", view_box, body)


if __name__ == "__main__":
    main(Path(sys.argv[1]))
