# P3b-06: the thermal-bridge Colour-by mode

DATE: 2026-10-03
STATUS: Merged to `main` 2026-10-26 as `da53f66e` (PR #312), T06 passed 2026-10-26. Corrected to `main` at `420c783a` on 2026-10-21 (DECISIONS Part 1b)
AUTHOR: Ed May, BLDGTYP, with Claude
ISSUE: [#301](https://github.com/ph-composer/ph-composer-skp/issues/301)

## Entry and scope

Requires P3b-04 and D3b-11 and D3b-12; P3a-05's `derived` geometry, legend figures and the
one-line-primitive decision (D3a-5) are on `main`. Owns the one Colour-by addition thermal bridges
need, a stroke weight (H14), and the `by_type` mode. It is `derived`'s third user, after the Spaces
prisms and the Window Type operation marks, and adds no second way to draw a coloured line;
tessellation is unchanged.

Behavior owner: the [thermal-bridges PRD](../PRD.md), "Colour-by mode". Contract:
`context/EXTENSIBILITY.md`, "Colour-by modes", as P3a-05 amended it. Get the stronger independent
review: this stage changes a contribution contract.

Paths are relative to `src/ph_composer/`.

## Steps

1. **Confirm the entity contract.** Check that an entry whose `entity` is an Edge and whose
   `derived` holds one world segment draws only the derived segment (`Tessellation.partition`
   yields nothing for an Edge, F8, which is the wanted result), keeps the occurrence-path
   visibility check, and still serves Locate and Show only this through its `entity`. Record the
   check beside `tests/colour_by_derived_test.rb`.
2. **Stroke weight (H14).** `colour_mode(..., stroke:)`: an optional weight for that mode's
   `derived` segments, validated at registration, applied as the one `line_width` the overlay sets
   before drawing the per-colour line batch (`colour_by/drawing.rb`, `@lines`; `overlay.rb`,
   `LINE_WIDTH`). Outline and hatch weights are unchanged. Fold the addition into
   `context/EXTENSIBILITY.md`, "Colour-by derived geometry", which already reserves it.
3. **The mode.** `features/thermal_bridges/colour_modes.rb` registers
   `ph_composer.thermal_bridges.by_type`, entity kind `edge`, one entry per assigned Edge
   occurrence carrying the Edge as `entity`, its path, its world segment in `derived`, the type as
   value, its colour, the type name as label and `figure: ["length", metres]`, which the legend
   sums per type and shows in the display units as "Parapet (12) 26.0 m" (D3b-12, CONTRACTS
   section 8 question 6). An Edge naming a missing type is `state: :incomplete`. Unassigned Edges
   produce no entry.
4. **Units in the label.** Nothing to build: `Preferences.unit_system` is read in Ruby and the
   service formats figures where it shows them. Confirm the HUD and the panel legend show the same
   number after a unit switch.
5. **Measure.** Draw cost at 5,000 assigned Edges on the proving host, against the overlay spike's
   method.

## Source

| PH-Composer file | Disposition |
| --- | --- |
| `features/zones/faces/colour_modes.rb` (`BY_ASSEMBLY`) | Pattern for colouring by a record's own `color` |
| `features/windows/colour_modes.rb` | Pattern for `derived` segments placed through an occurrence transform |
| `features/spaces/colour_modes.rb` (`entry`) | Pattern for an entry carrying `figure` and `derived` together |
| `colour_by/overlay.rb`, `colour_by/drawing.rb`, `shell/registry.rb`, `shell/declarations.rb` | Extend for `stroke:` only |

## Tests (write first)

1. An entry with an Edge `entity` and one `derived` segment under a rotated parent draws that
   segment in world coordinates and nothing else; a Face entry is unchanged.
2. `stroke:` outside its range refuses registration; absent keeps the existing weight.
3. The mode registers with no change under `colour_by/` beyond H14, and `colour_by/` names nothing
   of thermal bridges.
4. Legend rows sum each type's length figure and format it in the display units; a missing type
   is incomplete.
5. A hidden ancestor on the path draws nothing and keeps the legend count.

## Host gate

Fresh process on the reference model: turn the mode on from the native Colour by menu; the four
types draw thick in their colours, depth-tested, inside a nested Zone; hide a tag and an ancestor;
Show only this and Locate from the legend; the HUD reads type, count and length; capture by window
id (`context/SKETCHUP_HOST_BEHAVIOR.md`, "Overlays"). Repeat the Colour-by cases the ledger screens
(`acceptance_ledger.py status --changed`), S05 among them. Observe the host with the development tooling: `host_bridge.py wait-for` for deferred work, `host_bridge.py diagnostics` for what happened, `acceptance_case.py begin` and `finish` for the ledger row (`tools/hostkit/.index.md`).

## Added in implementation

- `ColourBy::Tessellation.skipped?` treats a tag inside a hidden tag folder as hidden, as `runs.locate`
  already did (the defect Codex found in P3b-04's review), and the session's tag observer publishes
  `tags_changed` for tag folder events and for a tag or folder moved to another folder, so a folder
  hidden in the Tags panel rebuilds the drawing. This
  touches every mode, not only this one: Faces, Zones, Windows and Spaces stop painting geometry under a
  hidden folder. Whether SketchUp fires the folder event for a visibility toggle is a host fact T06
  checks.

## Out of scope

Derived geometry and readouts (on `main` since P3a-05). Highlights inside the edge tool (P3b-07).

## Done when

- T06 has evidence in `../evidence/p3b-06-colour-by.md`, with the stronger review recorded.
- `context/EXTENSIBILITY.md` describes the edge entry and `stroke:`; `make ci` passes.
