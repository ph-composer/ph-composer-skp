# P4a-02: Segment heading rows, table management and the settings dialog

DATE: 2026-11-15
STATUS: Scoped. Not authorized.
AUTHOR: Ed May, BLDGTYP, with Claude
ISSUE: none (local planning draft)

## Entry and scope

Requires P4a-01. Owns the Segment heading rows in Geometry and Spaces, New, Delete and Move from
the tables, the Building Segment settings dialog with its General section, and the new
settings-section seam. Removes the Geometry Building-Segment column and the Manage Building
Segments dialog (BS-4). Load the UI polish and architecture review skills first.

Behavior: [Building Segments PRD](../building-segments/PRD.md), "In the Zone views" and "Building
Segment settings". Names: [CONTRACTS](../CONTRACTS.md) section 2. Prototype: `j3-no-segment`,
`j3-move-segment`, `j3-new-segment`, `j3-segment-settings`, `j3-delete-segment`,
`j1-segment-actions`, `j4-long-name` in [mockups](../mockups/README.md).

## Steps

1. **Settle C4a-1** (the foreign-extension write route) with a focused test against
   `core/records/extension.rb`; record the answer in CONTRACTS section 2.
2. **Seam.** `panel.segmentSettingsSection(featureId, {...})` in the panel kit; registration
   refuses a section whose feature declares no `<feature>.segment_settings.write` participant.
   Add it to `context/EXTENSIBILITY.md` as the fourth panel seam, with a development example under
   `tools/examples/`.
3. **Save action.** `ph_composer.zones.save_segment_settings`: General values (name, colour,
   default) and each section's payload, one compound proposal, one Undo step; stale-value guard.
4. **Heading rows.** A shared Segment-group renderer used by `html/features/zones/overview.js` and
   `html/features/spaces/view.js`: two-line heading, tags, findings flag, Settings and Delete in
   the Actions cell (Delete `aria-disabled` with its reason on the last Segment), view-owned sums,
   the No Building Segment group.
5. **Control row and selection bars.** New Building Segment icon in each view; Building Segment in
   the Geometry selection bar and in the Spaces selection bar, which gains Zone rows
   (`html/features/spaces/selection.js`).
6. **Delete confirmation.** Names the Zones and offers a destination (Segments, No Building
   Segment); names the settings that go with it.
7. **Remove** the Geometry column, its column menu entry and `option_dialog.js`'s Segment mode;
   Levels keep their dialog.
8. **Docs.** `docs/PRODUCT.md` step 2; UI polish skill's patterns reference gains the Segment
   heading row; Design System re-sync if the kit changes.

## Tests (write first)

1. Browser checks (`tools/ui-preview/`): heading rows in both views, tags, Actions cell, No
   Building Segment group, New, Move, Delete with destination, long-name truncation.
2. Seam: a development section registers, renders, validates and saves; a section without a
   participant refuses at registration; Save is one Undo step across two sections.
3. The dialog's Cancel, close and Escape write nothing.

## Host gate

PG02: panel gestures with Ed at the mouse; UI polish review recorded.

## Done when

PG02 passes and the seam is documented with a working example.
