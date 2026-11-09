# Spaces: creation, editing and visibility (design)

DATE: 2026-11-07
STATUS: Scoped. Design for Ed's review; no implementation is authorized.
AUTHOR: Ed May, BLDGTYP; Claude
ISSUE: https://github.com/ph-composer/ph-composer-skp/issues/352

## Problem

The 2026-11 walkthrough ([SYNTHESIS.md](../../../archive/usability-walkthrough-2026-11/SYNTHESIS.md) S-10;
[LOG.md](../../../archive/usability-walkthrough-2026-11/LOG.md) W-036 to W-052) found that a Space is hard
to draw, hard to see and hard to change:

- Create Space works only inside an open Zone. There the Zone's own Faces cover the plan, its tag
  cannot be hidden, and an outline drawn on a Zone Edge splits Zone geometry (W-036, blocker).
- Users draw rooms as solids; PH-Composer wants a floor outline plus a height, and nothing on the
  SketchUp side says so (W-037, W-039). WT-05 (#353, PR #377) now refuses a closed solid with that sentence
  (upright walls as walls, every other Face as part of the solid), so nothing counts twice, but a
  solid is still not accepted.
- A Space's height cannot be typed or dragged in the viewport, and its outline changes only through
  the panel's Open (W-038). The one native height route is Height from solid, in the Extensions and
  context menus for a selected Volume plus a solid (`src/ph_composer/features/spaces/height_from_solid_menu.rb`);
  Ed did not find it.
- Spaces vanish when their Zone closes: they nest in the Zone Group, behind its Faces and under its
  tag, so no Spaces tag can show or hide them (W-046, W-052). Space labels did not show (W-046).
- A Space cannot be removed while keeping its floor geometry (W-042).

Keep: a flat floor outline makes a Space in one step (W-044).

## Where the current model comes from

Membership is the parent Group: "A Space is in a Zone when its group is inside the Zone group"
([archived PRD](../../../archive/phase-03a-spaces/PRD.md), Q2). Everything below follows from it:

| Consequence | Where it is stated or built |
| --- | --- |
| Create Space needs the Zone's edit context open | `src/ph_composer/features/spaces/create_route.rb` (`NO_ZONE`) |
| Spaces carry a Zone stamp so Zones' walk skips them | [D3a-1](../../../archive/phase-03a-spaces/DECISIONS.md); `context/CONTRACTS.md`, "Zone membership stamp" |
| Move to Zone re-places the Space Group in another Zone Group | `src/ph_composer/features/spaces/move/plan.rb` |
| A copied Zone carries its Spaces; Spaces join its independence transition | `src/ph_composer/features/spaces/zone_copy.rb`; D3a-3 |
| Export attaches each Space to the Room whose Group holds it | `context/CONTRACTS.md`, Spaces export section; `src/ph_composer/features/spaces/export.rb` |
| The scan finds a Space's Zone by path prefix | `src/ph_composer/features/spaces/scan/occurrences.rb` (`zone_path`) |

Hiding, tags and visibility follow SketchUp's own nesting rules, so no overlay or setting can make
a nested Space visible while its Zone is closed and opaque, or hide it independently of the Zone's
tag. Acceptance row 5 of #352 therefore needs the Space Group outside the Zone Group.

## D1, made concrete

D1 (accepted 2026-11-07): Spaces can be built outside a Zone and then hosted in one; Create Space
inside an open Zone keeps working. "Hosted" has two readings, and only one meets row 5.

| | A1: host by re-parenting | A2: host by reference (recommended) |
| --- | --- | --- |
| Hosting | Move the Space Group into the Zone Group (today's Move to Zone) | The Space record names its Zone; the Space Group stays outside every Zone Group |
| Drawing (row 2) | Outside, then moved in; never touches Zone geometry | Outside; never touches Zone geometry |
| Visible with the Zone closed | No (W-052 stays) | Yes |
| Own tag, toggled alone | No | Yes |
| Archived contracts | Unchanged | Amended (list below) |

A2 amends, in one change: the membership rule (archived Q2, the scan's "Membership is the parent
Group only"), the Zone stamp on Space Groups (no longer needed; Zones' walk never meets a Space),
export keying (by the stored Zone, not the parent), Move to Zone (becomes a record edit), Zone copy
(a copied Zone no longer carries Spaces; see W6-10), Space CopyWatch (a copied Space keeps its Zone
reference), and a new finding for a Space whose Zone is gone. The Zone reference is a declared
record reference, so the existing reference rules apply: deleting a Zone that Spaces name is
refused with `reference.in_use` or offers to unhost them (W6-9).

There are no users and no saved models to carry, so A2 is one rule with no compatibility path for
nested Spaces.

## Proposal by acceptance row

Rows are #352's. Each names the decision it waits on.

1. **Design packet first.** This document.
2. **Create a Space without touching Zone geometry.** Create Space works on loose Faces in any
   context outside a Zone (the root, or a plain Group such as a storey). The review shows a Zone
   picker (W6-3). Inside an open Zone it keeps working (W6-2).
3. **Say that a Space is a floor outline plus a height.** The menu item, the review header and
   every refusal say it; WT-05's refusal text is the first. The review shows the height the Space
   will take and where it comes from (the Model's last height). Create Space keeps refusing a closed
   solid, with WT-05's sentence (W6-7).
4. **Edit height and outline in the viewport.** Height from solid stays. A Set height tool (W6-6) and an Edit outline
   context-menu item on a Space or Volume selection, which opens the Volume unprotected as the
   panel's Open does now.
5. **Visible by default, toggled by the user's tag.** Space Groups stay Untagged (W6-4): a user who wants
   tag toggling applies a tag to them, which works because Spaces now sit outside the Zone Groups. A Show Spaces
   overlay, on by default, draws each Space's prism outline and its label with or without a
   Colour-by mode (W6-5). Zone Faces still hide Spaces drawn inside the building from outside; the
   user hides the Zones' tag, cuts a section or uses X-ray, as SketchUp users do now.
6. **Remove a Space, keep its floors.** Remove Space beside Delete Space (W6-8).

## Decisions for Ed

| ID | Question | Recommendation | Alternative |
| --- | --- | --- | --- |
| W6-1 | How is a Space hosted in a Zone? | A2: by reference, the Space Group outside every Zone Group | A1: re-parent into the Zone Group. Meets row 2 (draw outside, then move in); row 5 stays unmet, since a hosted Space is again behind its Zone's Faces and under its tag |
| W6-2 | Under A2, what does Create Space inside an open Zone make? | A Space placed outside the Zone at the same world position, hosted in it: one rule, nothing nests. Placement uses the measured re-placing route Move to Zone uses ([SKETCHUP_HOST_BEHAVIOR.md](../../../../context/SKETCHUP_HOST_BEHAVIOR.md), "Re-placing a Group's definition") | A nested Space as today, so two membership rules |
| W6-3 | How does a Space drawn outside pick its Zone? | The review's Zone picker, preselected with the Zone whose plan footprint holds the outline's centroid and whose height range holds the outline; "No Zone" when none does. The user can change it before Create | No picker: the Space is created unhosted and Move to Zone hosts it |
| W6-4 | Which tag holds Space Groups? | One tag, named by a Spaces setting that starts as `02_SPACES` (Ed's convention beside `01_GEOM`), created on first use. Raw Faces inside stay Untagged | Untagged Space Groups; the user tags them |
| W6-5 | What does Show Spaces draw? | A check in Zones > Spaces, on by default, per Model session: each Space's prism outline (floor loops at floor and at height, and the verticals) and its label, with any Colour-by mode or none. Fix the W-046 label defect in the same stage | Labels only; the prism stays a Colour-by preview |
| W6-6 | How is height edited in the viewport? | A Set height tool: click a Space's prism, drag the top or type a value in the measurements box, one Undo step through `update` | Height derived from a solid the user keeps editing. Not recommended: a deferred pass ([TECH_STACK.md](../../../../context/TECH_STACK.md), "Observers report; deferred work mutates") would rewrite the height after every geometry edit, a write the user never asked for, and the geometry becomes a solid again, against outline plus height |
| W6-7 | Does Create Space accept a closed solid? | Yes, as a conversion: on a selected closed Group or closed shell of loose Faces, the downward Faces become the floor outline, the solid's volume over that area becomes the height (as Height from solid computes it), and the walls and top are erased. One Undo restores the solid. The review says so before Create | No: keep WT-05's refusal, which tells the user to draw the outline alone |
| W6-8 | How is a Space removed while keeping its floors? | Remove Space: the Space's and its Volumes' records go, both Groups are exploded, the floor Faces stay where they are as plain geometry, one Undo step. This is `RemoveVolumeStep` one level up | Delete Space with a "Keep floor outlines" check |
| W6-9 | What happens to a Space whose Zone is deleted? | Deleting the Zone offers to unhost its Spaces (they stay, with no Zone, and the `space.outside_zone` finding) in the same Undo step | Refuse the delete with `reference.in_use` until the Spaces are moved |
| W6-10 | Copying: a Zone, or a storey Group holding Zones and their Spaces | A copied Zone copies no Spaces. A copied plain Group holding Zones and Spaces needs a new collection-copy contract, which S10-1 designs: today's Zone independence transition carries one `zone_path` and maps only that Zone's descendants (`src/ph_composer/features/spaces/zone_copy.rb`), and Space CopyWatch leaves a copied plain Group alone. The contract gives every copied Space a new identity and remaps a copied Space's Zone reference to the copied Zone only when that Zone came in the same copy; a Space whose Zone stayed behind keeps its reference | Copying a Zone also copies the Spaces that name it |
| W6-11 | Two separate outlines stacked in one Volume still both count (WT-05 residual) | A blocking finding `space.floor_overlap` when two Floor Segments of one Volume overlap in plan. One Volume only: two storeys of one Zone overlap legitimately | A warning that does not block export |

## Proposed stages after Ed's go

One PR each, through the walkthrough plan's rules, host check on each. Order is dependency order.

| Stage | Scope | Depends on |
| --- | --- | --- |
| S10-1 | Membership by reference: Zone reference on the Space record, scan, findings, export keying, Move to Zone as a record edit, Zone deletion (W6-9), the collection-copy contract (W6-10), stamp removal, contract and context updates | W6-1 |
| S10-2 | Create Space outside a Zone: review Zone picker and inference, placement inside an open Zone (W6-2), Space Groups Untagged (W6-4), wording (row 3) | S10-1 |
| S10-3 | Show Spaces overlay and the label defect | S10-1 |
| S10-4 | Set height tool and Edit outline | S10-1 |
| S10-5 | Remove Space, keep floors | none |
| S10-6 | Floor overlap finding, a warning that does not block export (W6-11) | none |

## Acceptance checks for implementation

- A Space drawn at the root and hosted in Floor-01 exports in Floor-01's Room, and the same model
  with that Space's Zone reference changed exports it in Floor-02's.
- With every Zone closed, every Space is visible. Hiding the Zones' tag hides no Space; a tag the user
  applies to Space Groups hides them and no Zone.
- Drawing an outline for Create Space never changes a Zone Face's persistent id or Edge count.
- Copying a storey Group that holds two Zones and their Spaces gives the copied Spaces new ids,
  each hosted in the copied Zone its original was hosted in; the originals are unchanged.
- The walkthrough's L-shaped solid is refused as today (W6-7), and no floor counts twice.
- Two Floor Segments overlapping in plan in one Volume raise `space.floor_overlap` as a warning; export
  still runs (W6-11).
- Set height and Remove Space are each one native Undo step on the host.
