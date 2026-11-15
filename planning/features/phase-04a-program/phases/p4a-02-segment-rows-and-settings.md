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

1. **Evidence.** Narrow `Options.evidence` (`options/definitions.rb`) to the Segment's `name`,
   `colour` and `export_identifier`, so a Segment write no longer rewrites every member Zone
   (`rewrite_evidence`) or refuses on a locked one; adoption brings no settings.
2. **Save action.** `ph_composer.zones.save_segment_settings`: General values (name, colour,
   default) and a payload per namespace. Zones checks each payload with its installed validator
   (`Extension#problems`) and stages it with `engine.propose_metadata_update`: one proposal, one Undo
   step, stale-value guard (CONTRACTS section 2).
3. **Seam.** `panel.segmentSettingsSection(namespace, {...})` in the panel kit, `readOnly` for a
   section that collects nothing. Add it to `context/EXTENSIBILITY.md` as a panel seam, with a
   development example under `tools/examples/` that registers a namespace and a section.
4. **Heading rows in the host.** `html/features/zones/overview.js`, the Zone views host, renders
   Segment heading rows and the No Building Segment group for every view: two-line heading, tags,
   findings flag, Settings and Delete in the Actions cell (Delete `aria-disabled` with its reason on
   the last Segment). A new `table_views` hook, `segmentSums(rows)`, lets each view fill its own
   columns; Geometry (`faces_view.js`) and Spaces (`html/features/spaces/view.js`) supply theirs.
   Update `context/EXTENSIBILITY.md`, "Zone views".
5. **Control row and selection bars.** New Building Segment icon in each view; Building Segment in
   the Geometry selection bar and in the Spaces selection bar, which gains Zone rows
   (`html/features/spaces/selection.js`).
6. **Delete confirmation.** Names the Zones and offers a destination (Segments, No Building
   Segment); names the settings that go with it.
7. **Remove** the Building-Segment column from the host (Geometry) and from Spaces
   (`spaces/view.js`, which offers it today), its filter and sort, its column menu entry and
   `option_dialog.js`'s Segment mode; Levels keep their dialog.
8. **Docs.** `docs/PRODUCT.md` step 2; UI polish skill's patterns reference gains the Segment
   heading row; Design System re-sync if the kit changes.

## Tests (write first)

1. Browser checks (`tools/ui-preview/`): heading rows in both views, tags, Actions cell, No
   Building Segment group, New, Move, Delete with destination, long-name truncation.
2. Seam: a development namespace and section register, render, validate and save; a payload its
   validator refuses blocks Save and writes nothing; Save is one Undo step across two namespaces;
   a member Zone that is locked does not block a settings save.
3. The dialog's Cancel, close and Escape write nothing.

## Host gate

PG02: panel gestures with Ed at the mouse; UI polish review recorded.

## Done when

PG02 passes and the seam is documented with a working example.
