# Windows: draw a rectangle, convert it to a Window Type (design)

DATE: 2026-11-07
STATUS: Scoped. Design for Ed's review; no implementation is authorized.
AUTHOR: Ed May, BLDGTYP; Claude
ISSUE: https://github.com/ph-composer/ph-composer-skp/issues/363

## Request

The 2026-11 walkthrough ([SYNTHESIS.md](../../../archive/usability-walkthrough-2026-11/SYNTHESIS.md) S-21;
[LOG.md](../../../archive/usability-walkthrough-2026-11/LOG.md) W-095, Ed: "the biggest UX change I want to
include"): draw the opening as a rectangle with native SketchUp tools, snapping to CAD, select it,
right-click Convert to Window Type. The new Type takes its size from the geometry, several selected
rectangles become one mulled Type, and the Faces are replaced by a placed Window Unit of that Type.
Frames, glazing and Psi-Install are set afterwards in the panel. Build-then-Place stays.

This is how designPH and Honeybee users already draw windows, and it answers W-094 (Place does not
snap) for the first placement of each opening.

## What the Windows feature already gives Convert

| Need | What exists | Where |
| --- | --- | --- |
| A Type sized from geometry | A Type has no width or height field: its size is the band lists `columns_m` (left to right) and `rows_m` (top down); elements cover every grid cell exactly once with `row_span` and `column_span` | `src/ph_composer/features/windows/types/schema.rb`, `types/grid.rb` |
| What the size means | The bands are the frame outer size: element area is band width by height, glazing is that less the frame widths, and the exported aperture is the band rectangle. There is no in-plane installation gap; `install_depth_m` is reveal depth | `types/thermal.rb`, `export_assessment.rb`; `context/UBIQUITOUS_LANGUAGE.md` |
| Up and sill on any host | Up is world Z projected onto the host Face, or the green axis on a horizontal Face; right is up crossed with the normal. The sill is the low edge on a wall or a sloped roof | `placement/plane.rb`; [archived PRD](../../../archive/window-types/PRD.md), "Place" (Q6) |
| Host rules | A Zone Face, Wall or RoofCeiling; a Surface Face is refused (`window.surface_host`), a Face in no Zone too (`target.wrong_zone`); export needs Outdoors | `placement/host.rb`, `placement/tool_target.rb` |
| Placement checks | `window.overhang` (outline leaves the host or crosses a hole), `window.overlap` (another Unit on the plane) | `placement/fit.rb` |
| Placing without the tool | The public action `ph_composer.windows.units.place` takes a host Face reference, a Type, an anchor and offsets | `declarations/units.rb`, `units/actions.rb` |
| Create a Type and place it in one proposal | `PlaceStep` requires a stored, unchanged Type. `FlipStep` already writes a new Type in the proposal that places it ("The caller writes the new Type") | `units/place_step.rb`, `units/flip_step.rb` |
| Turn loose Faces into a Unit | Restore infers a Unit's matrix from loose stamped panes, places it and erases the panes in one Undo step. It accepts only stamped glass panes, so a hand-drawn rectangle is not one | `units/restore_step.rb`, `units/restore_panes.rb` |
| A selection menu with a review | Create Space: the item shows on any Face selection, a review in the panel lists what is taken and what is left out with a reason, Create confirms. Make Zone refuses a wrong selection with `target.wrong_kind` | `features/spaces/create_route.rb`; `features/zones/zone/operations.rb` |
| Same-size Type lookup, "last used" Type | None. The only last-used precedent is the Spaces setting `last_height_m` | `windows/settings.rb`; `context/CONTRACTS.md` |

## The hole problem

A rectangle drawn wholly inside a Zone Face leaves that Face with a hole and the rectangle as a second
Face ([SKETCHUP_HOST_BEHAVIOR.md](../../../../context/SKETCHUP_HOST_BEHAVIOR.md), the row on drawing a
coplanar outline onto a Face). `Fit` refuses an outline that overlaps a hole, so erasing only the
rectangle Face and placing would be refused as `window.overhang`. Convert must also erase the
rectangle's Edges, so the host Face is whole again, before the Unit is placed, all in one operation.
A rectangle that shares part of the host's boundary (a door on the floor line) splits the host into
separate Faces instead; Convert refuses those (W7-2), so the user draws them inset and moves the Unit
after. The interior-rectangle sequence has not been measured on the host: which `persistent_id` the
healed Face keeps, and whether the Zones Faces scan has already given the rectangle piece a Face
record. These are spike H1 and H3 below, run before S21-2 is built.

## Proposal

1. **Menu.** Convert to Window Type... on the context menu and the Extensions menu when the selection
   holds at least one Face. Like Create Space, it opens a review in the panel; nothing changes until
   Convert.
2. **Accepted geometry.** Each selected Face must be a rectangle lying on one Zone Face, its sides
   parallel to that Face's up and right axes from `placement/plane.rb`. A rectangle is read by its
   corners, not its Edges: after collinear boundary vertices are merged, as Restore does
   (`units/restore_panes.rb`), its outer loop has four corners at right angles within 0.1 degree and
   it has no inner loop. A side split by a T junction in a mulled layout (a tall rectangle beside two
   stacked ones) is still one side; the original Edges are kept for the guard and the erase. Two places count as "on" a Zone Face (W7-1): inside the open Zone, drawn on
   the Face itself, or outside it, coplanar with the Face and within its outer loop. Every other Face
   is listed as left out with its reason, as Create Space's review does.
3. **Grouping and mulling.** Rectangles that share an Edge segment form one group; a group becomes
   one Type. Its column and row bands are the distinct coordinates of the group's sides along the
   host's right and up axes, and each rectangle becomes one element spanning the cells it covers. A
   group whose rectangles do not tile one rectangle exactly (a gap, an overlap, an L shape) is left
   out as one row, `window.mull_not_rectangular`, naming its Faces. Rectangles that touch nothing are
   groups of one (W7-5).
4. **Reuse.** A group whose bands and element spans match an existing Type within 1 mm is offered
   that Type; several groups of one size in one conversion share one new Type and become several
   Units (W7-6).
5. **New Type.** Named, sized and laid out from the group, with its elements blank as the panel's New
   Type makes them, or copied from a Type the review names (W7-7, W7-8). It is export-blocking until
   its thermal inputs are set, as any placed incomplete Type is.
6. **Replace.** One operation per Convert: write the new Types, erase each rectangle and the Edges
   that only it and its host piece share (healing the host), then place one Unit per group on the
   healed Face at the rectangle's position (anchor and offsets computed from the geometry). One native
   Undo restores the rectangles and leaves no Type or Unit behind (W7-9).
7. **Parity.** The review reads through a query (`ph_composer.windows.units.convert_review`) and Convert
   runs through an action (`ph_composer.windows.units.convert`), so an agent converts with the panel
   closed. The source rectangles are named by root-to-Face persistent-id paths, as Restore's
   `pane_paths` are, because a rectangle outside every Zone has no Zone Face reference
   ([CONTRACTS.md](../../../../context/CONTRACTS.md), the Face target shape). The host is resolved
   separately and reported as a Zone Face reference. The review returns each source's geometry, and
   Convert refuses with `target.changed` when a source no longer matches it, as Restore refuses
   changed panes. A rectangle lying on two coplanar Zone Faces is left out as `window.host_ambiguous`.

## Decisions for Ed

| ID | Question | Recommendation | Alternative |
| --- | --- | --- | --- |
| W7-1 | Where may the rectangle be drawn? | Both: on the Zone Face inside the open Zone (Convert heals the host), or outside every Zone, coplanar with a Zone Face and within it (Convert just erases the rectangle). Inference reaches across Groups, so the second keeps Zone geometry untouched while snapping to CAD | Only inside the open Zone, as Ed described it |
| W7-2 | A rectangle that shares the host's boundary (a door on the floor line, a window at a corner) | Accepted when spike H2 shows the merge restores one host Face with its record; until then left out as `window.convert_on_boundary` ("Convert cannot yet replace a rectangle that touches its host Face's edge."), a condition of its own: `window.overhang` stays the containment refusal it is for Place | Always refused: the user draws it inset and moves the Unit after |
| W7-3 | Rotated rectangles and the sill on flat roofs | Refused when a side is not parallel to the host's up or right axis (`window.not_aligned`); on a horizontal Face, up is the green axis as Place does. A skylight drawn at an angle on a flat roof is the one case this refuses that a user may want | Accept any rectangle and take the side nearest the host's up axis as the sill, placing a rotated Unit. Place has no rotation today, so this adds one to the Unit contract |
| W7-4 | Does the rectangle mean the frame outer size or the rough opening? | The frame outer size: the Type's bands, so the Unit's outline is the rectangle and the user draws the frame outline | The rough opening, with an installation gap setting that shrinks the Type. No carrier exists for the gap today |
| W7-5 | How do several selected rectangles become a mulled Type? | Rectangles sharing an Edge segment form one group and one Type; the group must tile a rectangle; separate rectangles are separate groups | Every selection is one Type whatever touches, refused when it does not tile |
| W7-6 | Same-size Types | Preselect a matching Type (bands and spans within 1 mm, alphabetical when several match), with New Type always offered; same-size groups in one Convert share one new Type | Always a new Type; the user swaps Types after |
| W7-7 | What does a new Type hold besides size? | Blank elements (no glazing, frames, installs or operation), with an optional "Copy from" Type picker in the review, default none. Copying takes the source's first glazed element's glazing, frames, installs and operation for every element | Copy from the last Type the user placed. Needs a new remembered setting, and the copy is invisible until export blocks or does not |
| W7-8 | The new Type's name | Its size in display units, `Window 1200 x 1500` (mm) or `Window 47.2 x 59.1` (in), with ` (2)` added when taken; editable in the review | The panel's next free `Window Type N`, moved to Ruby so the agent route gives the same name |
| W7-9 | Undo and Redo | One Undo step restores the rectangles and leaves no Type or Unit; Redo converts again | Types kept on Undo: not recommended, a native Undo that leaves records behind breaks the transaction rules ([TECH_STACK.md](../../../../context/TECH_STACK.md)) |
| W7-10 | What Convert leaves when the host is not exportable yet | Converts anyway: the host needs a Zone but no Face record (archived Q4), so windows can be drawn before classification, as Place allows | Refuse until the host Face is classified Outdoors |

## Host facts to measure first (spike, part of S21-2)

Each on SketchUp 26.1 through the development bridge, recorded in `context/SKETCHUP_HOST_BEHAVIOR.md`:

- **H1.** A rectangle drawn wholly inside a Zone Face, then its Face and four Edges erased in one
  operation: the host has no hole, keeps its `persistent_id` and dictionaries, and its Face record
  (if any) is unchanged after the Zones scan settles.
- **H3.** The rectangle piece of H1 before Convert: does the Zones Faces scan or a Classify
  deferred pass give it a Face record or a classification, which Convert must then remove in the same
  operation.

## Proposed stages after Ed's go

One PR each, through the walkthrough plan's rules. Order is dependency order.

| Stage | Scope | Depends on |
| --- | --- | --- |
| S21-1 | Rectangle reading and grouping, pure: Faces in, groups with bands, spans and refusal rows out (W7-3, W7-5), and a rectangle touching its host Face's boundary left out as `window.convert_on_boundary` (W7-2); `convert_review` query with host resolution and Type matching (W7-6); offline tests | W7-1, W7-2, W7-3, W7-4, W7-5 |
| S21-2 | Spike H1 and H3, then `ConvertStep` (new Types written in the proposal, as FlipStep does; rectangles erased and the host healed; Units placed through the PlaceStep checks) and the `convert` action, one Undo step; host check | S21-1; W7-9 |
| S21-3 | Context and Extensions menu item and the panel review (UI polish skill): groups, left-out rows, Type choice, name, Copy from (W7-7, W7-8); host check | S21-2 |

## Acceptance checks for implementation

- One rectangle drawn on a Zone wall and converted gives one Type whose `columns_m` and `rows_m` are
  the rectangle's width and height to 1 mm, one Unit whose outline is the rectangle, and a host Face
  with no hole and its original `persistent_id`.
- Three rectangles sharing Edges in a row of a 0.6 m, 1.2 m and 0.6 m width give one Type with three
  columns and three elements; an L of three rectangles is left out as `window.mull_not_rectangular`
  and nothing changes.
- A full-height rectangle beside two stacked ones (a T junction splitting the tall one's side into
  two Edges) gives one Type of two columns and two rows whose tall element spans both rows.
- A rectangle drawn outside every Zone, coplanar with a Zone wall, converts by its root-to-Face path;
  the same call after the rectangle was moved is refused with `target.changed` and writes nothing.
- Four separate same-size rectangles give one new Type and four Units, or four Units of an existing
  Type of that size when the review keeps its preselection.
- A rectangle at an angle to the host's up axis is left out as `window.not_aligned` (W7-3).
- A rectangle touching its host Face's edge is left out as `window.convert_on_boundary`, with a message
  saying to draw it inset and move the Window after, and nothing changes (W7-2).
- One native Undo restores every rectangle and removes every new Type and Unit; Redo converts again.
- The same conversion through `convert` with the panel closed gives the same records.
- Build-then-Place behaves as before: the existing Place tests and the Window Types host walkthrough
  pass unchanged.
