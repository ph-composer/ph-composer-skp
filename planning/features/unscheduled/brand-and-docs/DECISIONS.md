# Brand and public documentation: decisions

DATE: 2026-11-25
STATUS: Scoped. BR-D1 to BR-D12 decided by Ed on 2026-11-25; BR-O1 to BR-O10 open.
AUTHOR: Ed May, BLDGTYP, with Claude
ISSUE: none (local planning draft)

Each decision was made by Ed while reviewing boards on a private Design canvas. The board named
beside a decision is its file under [mockups/canvas/project/](mockups/canvas/project/).

## Decided

### BR-D1. The mark is "Lift"

A stack of blocks in isometric view: pale blocks with windows on a slab, and one coloured block
held just above its place. It says that a foundation exists and the next piece is being added.
At a glance the raised block over the stack also reads as a tree, which Ed liked. "Lift" is a
working name for the mark, not a public one. Board: `T-LiftBrand.dc.html`.

### BR-D2. Small sizes drop the windows

At 24 px and below the mark is drawn without windows. 24 px is the size users see most, in the
SketchUp toolbar. Board: `S-LiftNatural.dc.html`.

### BR-D3. A product is told apart by the colour of the lifted block

The suite mark carries a green block. A product keeps the whole mark and changes only that block's
colour, and its name under the wordmark takes the same colour. Which product gets which colour is
open (BR-O1).

### BR-D4. Palette

| Name | Hex | Use |
| --- | --- | --- |
| White | `#f6f3ec` | Blocks, page tint |
| Maple | `#d9a66b` | Blocks, panels |
| Deep maple | `#c68a4e` | The slab, rules |
| Green | `#b8d430` | The lifted block; a chosen or checked state |
| Orange | `#f2691e` | Second accent; the crane; one product's block |
| Espresso | `#33261d` | Text, dark grounds |

Ed asked for natural tones built on white, maple and green, and kept orange and espresso from a
second variation. Boards: `S-LiftNatural.dc.html`, `T-LiftBrand.dc.html`.

### BR-D5. Text on orange is white, on a deeper orange

Ed found dark text on orange hard to read. A button or any other orange ground that carries text
uses `#c8500e` with white text; white on `#f2691e` is too faint at button size. Orange used as
text on white is `#b84a0c`. The mark keeps `#f2691e`.

### BR-D6. The splash illustration is the mark with a crane

An orange tower crane holds the green block over the stack. It is for the splash screen, the site
hero and docs covers. Orange was chosen over white, yellow and espresso because it reads on light
and dark grounds and adds no colour. The lifting straps meet the block partway in from its
corners. Board: `U-CraneSplash.dc.html`.

### BR-D7. Web, docs and tutorials use Figtree with DM Mono

Chosen over IBM Plex Sans, Space Grotesk with Inter, Zilla Slab with Source Sans 3, and Open Sans.
Both are free Google Fonts and can be self-hosted. Headlines and the wordmark are set at weight
700. Board: `W-TypeBrand.dc.html`.

### BR-D8. The SketchUp panel keeps the system font

The panel stays on the operating system's font so it reads as part of SketchUp. Read from the
stylesheets bundled in SketchUp 2026 for macOS: its own HTML panels declare Open Sans with a
system-font fallback. That SketchUp's native menus and trays use the system font is assumed from
how native macOS and Windows controls behave; it was not measured. Board: `V-TypeInApp.dc.html`.

### BR-D9. In the panel, large fills are SketchUp's greys and brand colour is a highlight

- Table headers, checked and selected rows, group rows and disabled controls use the greys
  SketchUp's own HTML panels use (`#f3f3f7`, `#e0e1e9` and their neighbours).
- Espresso carries structure: the active tab, links and the primary button.
- Green and orange appear only on small elements: green for a check or a chosen state, orange for
  an error or a strong highlight.

The panel's present teal accent, `#075360`, is retired by this rule. Boards:
`X-InAppColour.dc.html`, `Y-HeaderBar.dc.html` (treatment 2).

### BR-D10. No mascot and no pixel art

A beaver and three other illustrated characters were drawn and dropped: Ed judged a mascot wrong
for a technical product. A pixel-art version of the crane scene was also dropped because it does
not read at small sizes. It did lead to the block stack. Boards: `D-Beaver.dc.html` to
`K-BeaverSystem.dc.html`, `Q-PixelCrane.dc.html`.

### BR-D11. Keep a visible distance from Phius and from PH-Tools

PH-Composer is not part of Phius and must not be mistaken for it. The palette has no teal and no
navy, which are the core of the Phius identity, and the type is not Greycliff. The green echoes
the hi-vis accents common on construction sites. The brand also avoids PH-Tools' teal and magenta
and its Outfit typeface, so the two read as separate projects.

### BR-D12. Voice

Plain, direct and inviting. The product is free and open source, it is a foundation, and other
people are asked to build on it. Draft lines, not final copy:

- "Model passive buildings in SketchUp."
- "The ground floor is in. Bring the next block: a feature, a library provider or an exporter."

Any claim on the site must match the repository. In particular, do not describe the whole suite
as free and open source while a sibling product is private or its licence is undecided.

## Tried and set aside

| Direction | Outcome |
| --- | --- |
| Strata (flat stacked bands), Score (blocks on a staff), Open Grid (tiles with one open) | Judged generic. Strata's foundation idea and Open Grid's colour-per-product idea carried into Lift. |
| Hi-vis palette (orange, lime, slate on charcoal) | Liked, then replaced by the natural palette; its orange and green stayed. |
| Brick wall, building elevation and flat crane marks | Set aside in favour of the isometric stack. |
| Single-colour marks (solid, tone, line) | Removed from the brand board as not working yet (BR-O2). |

## Open

- **BR-O1. Product colours.** Which block colour each product takes. The mock-ups used orange for
  SketchUp and forest green for REVIVE as placeholders.
- **BR-O2. A one-colour mark.** Needed for one-colour print and for marks reversed out of a dark
  ground. The first attempts were set aside.
- **BR-O3. Orange for errors.** BR-D9 uses orange for errors. Today the panel uses red for errors
  and amber for warnings. Orange must stay distinguishable from amber, by lightness and by an icon
  or word, before red is replaced.
- **BR-O4. White blocks on a white page.** The top faces of the white blocks fade on pure white.
  Either the site uses a tinted ground behind the mark or the block white goes a step darker.
- **BR-O5. Where the brand assets live.** A suite-level repository under the `ph-composer`
  organization, or a folder in this one. A suite-level home fits BR-D3 better.
- **BR-O6. Domain and hosting for the site.** No domain has been chosen.
- **BR-O7. Where documentation is written.** In each product's `docs/` and pulled into the site,
  or in the site's own repository. See [PLAN.md](PLAN.md#documentation-map).
- **BR-O8. When the panel recolour lands.** It changes shipped stylesheets while Phase 7 work is
  in progress in the same files.
- **BR-O9. Use of the name and mark by others.** The code is AGPL-3.0-or-later. Whether forks and
  third-party extensions may use the PH-Composer name and mark is not stated anywhere.
- **BR-O10. The palette holds one product colour.** The suite mark takes green, which leaves
  orange as the only accent a product can use. The forest green used for REVIVE in the mock-ups is
  not in BR-D4. A second product therefore needs a new accent, a neutral block, or the suite mark
  giving up green. This is part of answering BR-O1.
