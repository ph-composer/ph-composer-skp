# P3a-05: Colour-by derived geometry and readouts

DATE: 2026-10-15
STATUS: Merged: slice A through #147, slice B (operation marks) through #148; host gate pending ([evidence](../evidence/p3a-05-colour-by-extension.md))
AUTHOR: Ed May, BLDGTYP, with Claude
ISSUE: [#133](https://github.com/bldgtyp/ph-composer/issues/133)

## Entry and scope

Requires P3a-01 and D3a-5. Owns the extension to the shared Colour-by contract that D2-6 deferred
to this phase: a mode may supply derived geometry, and a readout registers separately. It is a
foundation stage. It names no feature, changes no existing mode's behavior and can run on its own
branch beside P3a-02 to P3a-04.

Designed once against both users, as the [README](../README.md), "Carried in", requires: the
Spaces volume preview, labels and selection totals (spaces Q22), and the Window Type mode's
operation marks (window-types, deferred by D2-6). Ed confirmed D3a-5 on 2026-10-15: the marks
are built here as slice B. Phase 3b's
[P3b-06](../../phase-03b-thermal-bridges/phases/p3b-06-thermal-bridge-colour-by.md) is a third
user: it draws assigned Edges as `derived` segments with the Edge as `entity`, and adds a per-mode
stroke weight itself. Nothing for it is built here.

Behavior owners: [Spaces PRD](../PRD.md), "Seeing the data in the model";
[window-types PRD](../../window-types/PRD.md), "Schedule and seeing windows in the
model". Contract owner: `context/EXTENSIBILITY.md`, "Colour-by modes". Names:
[CONTRACTS](../CONTRACTS.md) section 5 (H7, H8).

Paths are relative to `src/ph_composer/`.

## Steps

### Slice A: the contract

1. **Design note first.** Before code, write the proposed shapes into `context/EXTENSIBILITY.md`,
   "Colour-by modes", as proposed, and run the architecture review on them against one concrete
   contributor task for each user: "add the By height mode with its prism" and "add operation
   marks to By type". The questions it must answer: what a derived shape may be, who owns
   world-space conversion, how visibility along a path applies to shapes with no entity, what the
   legend counts, and what a readout may read. Added 2026-10-15: name thermal bridges as the third
   user and settle, once, the deferred geometry stage G-03's `ColourBy::LineEntry` against Phase
   3b's D3b-11 `derived` segments, so the contract gets one line primitive
   ([geometry contribution contracts](../../geometry-contribution-contracts/STATUS.md)).
   Say how derived shapes interact with the occurrence mask (`Service#filter`) and with a mode's
   `group`, both added since this stage was planned.
2. **Derived geometry (H7).** `ColourBy::Entry` gains `derived`: a list of world-space polygons,
   each filled and outlined in the entry's colour, and world-space segments, each drawn as a
   line. An entry may carry an entity, derived shapes or both. The projection computes the
   shapes; the service only draws. Visibility follows the entry's `path` exactly as it does for
   an entity: a hidden ancestor or tag hides the derived shapes too. An entry with neither entity
   nor shapes draws nothing and still counts in the legend.
3. **Tessellation and cache.** `colour_by/tessellation.rb` triangulates derived polygons into the
   same fill and outline buffers the overlay already draws, so depth testing and the translucent
   fill the overlay spike proved apply unchanged. The cache stays whole and keyed on the session
   revision. Resolve whatever CONTRACTS section 8 found for question 7.
4. **Readouts (H8).** `FeatureScope#colour_readout(name, label:, &projection)`: a pure projection
   over a read request, the shape a mode's projection receives plus the current selection, that
   returns viewport text anchors (a world point and lines of text parts) and HUD lines. A readout
   is on or off per Model, independent of the active mode and shown with none. Registration
   diagnostics follow `colour_mode`'s. `Service` holds the enabled readouts; `overlay.rb` draws
   text anchors with `view.draw_text` and appends HUD lines under the legend.
5. **Units in readouts.** A readout returns message parts with SI values and quantity ids, never
   formatted text, and the overlay formats them from the session's display units. Confirm the
   Ruby formatter this needs exists; if the overlay cannot format a quantity without one, stop
   and record the question, because `context/TECH_STACK.md`, "Display units", says Ruby formats
   no unit-bearing text and the viewport is the one place the panel cannot do it.
6. **Reads and menus.** `ph_composer.colour_by.state` reports registered readouts and which are
   on. A view command toggles one. The native Colour by menu lists readouts under the modes.
   Selection changes invalidate a readout that reads the selection, through the existing
   `:selection_changed` host event.
7. **Example.** A synthetic mode with a derived prism and a synthetic readout under
   `tools/examples/`, registered from outside `colour_by/`, as the example a contributor copies.
8. **Context.** Replace the proposed text of step 1 with what was built.

### Slice B: operation marks (D3a-5: built here)

9. In `features/windows/colour_modes.rb`, `by_type` entries gain derived segments for each
   element's operation, from the pure unit plan P2-12 already computes. No change under
   `colour_by/`. This is the proof that a second, existing mode adopts the contract by editing
   only its own feature.

## Source

No predecessor Colour-by service. The predecessor's `features/windows/panel/overlay/` (397
lines) drew operation marks directly and is the reference for slice B's geometry only.

## Tests (write first)

1. An entry with an entity and no `derived` draws exactly what it drew before; every existing
   Colour-by test passes unchanged.
2. A derived-only entry fills, outlines and counts in the legend.
3. A derived shape under a hidden ancestor, and under a hidden tag, is not drawn and is still
   counted.
4. A concave derived polygon triangulates correctly; a degenerate one draws nothing and raises
   nothing inside `draw`.
5. A readout registers, toggles, draws with no mode active and with a mode active, and is
   dropped on `detach`.
6. A selection change rebuilds a selection-reading readout and no mode.
7. Registration refuses a readout with a duplicate name and one whose owner is not installed.
8. The synthetic example registers with no change under `colour_by/` after this stage.
9. Slice B: `by_type` draws marks; `git diff --stat` for the slice touches only
   `features/windows/` and its tests.

## Host gate

Fresh process. Activate the synthetic mode: translucent prisms draw depth-tested against model
geometry, behind and in front. Hide a tag and an ancestor Group. Toggle the synthetic readout
with a mode on and with none. Orbit a model at the representative size the overlay spike used
([B2](../../phase-00-foundation/evidence/spike-overlay.md)) and record draw cost
against that baseline. Repeat the Phase 1 and Phase 2 Colour-by cases the ledger screens for
`colour_by/`. Slice B: marks on the reference model's four units, on a wall and on the flat roof.

## Out of scope

Any Spaces mode or readout (P3a-07, P3a-09). A height drag handle or any interactive derived
geometry. Hit testing against derived shapes.

## Done when

- S05 has evidence in `evidence/p3a-05-colour-by-extension.md`, with the stronger review recorded.
- `context/EXTENSIBILITY.md` documents derived geometry and readouts with the example's path.
- `make ci` passes on both Rubies. The window-types packet records the marks as delivered or
  still owed.
