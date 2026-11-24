# UI baseline

DATE: 2026-09-18
STATUS: Scoped
AUTHOR: Ed May, BLDGTYP, with Claude
ISSUE: none (no remote)

Ed's direction on 2026-09-18: the UI and UX of PH-Navigator for SketchUp is the basis for
PH-Composer. Copy and match it wherever possible. He supplied six screenshots of the
predecessor at 0.4.0-b2 as the reference.

This document reads those six screens and rules on every visible part: what is kept as it is,
what changes because of a recorded packet decision, what is removed with designPH, and what is
added. It then lists the screens PH-Composer needs that have no predecessor to copy.

It does not restate how the UI is built or polished. That is
`.agents/skills/ph-composer-ui-polish/` and its `references/patterns.md`, which name the
predecessor's source files for every pattern below. Behavior belongs to the feature packets; where
this document and a packet PRD disagree, the PRD wins and this document is corrected.

## The screenshots

The six images reached the session as temporary files that no longer exist, so they are not in
the repository yet. `screens/` is ready for them under these names:

| File | Screen |
| --- | --- |
| `01-spaces.png` | Spaces table |
| `02-assemblies-inventory.png` | Assemblies inventory |
| `03-assembly-builder.png` | Assembly Builder with the library sidebar and a material details bubble |
| `04-window-type-builder.png` | Window Type Builder |
| `05-library-materials.png` | Library / Materials with the source chooser open |
| `06-library-glazings.png` | Library / Glazings with a connected provider and a record details bubble |

They show the PH-Navigator name and rows from BLDGTYP's product catalog, so they stay out of the
repository: `screens/` is gitignored (U4).

## Disposition words

| Word | Meaning |
| --- | --- |
| Keep | Copy the predecessor's layout, control and behavior unchanged |
| Change | Same place and pattern, different content, because of the packet decision cited |
| Remove | Existed for designPH or PHI and has no job here |
| Add | New, placed inside the predecessor's existing pattern |

## The shell, on every screen

| Part | Ruling |
| --- | --- |
| Window title "PH-Navigator for SketchUp" | Change to the product name |
| One row of primary tabs, the active tab filled dark teal | Keep |
| A tab for a feature that is not built yet, shown muted as "Ducts · Planned" | Change (UI and UX refinement D3, 2026-10-03). The tab stays, muted and disabled, after the working tabs, with a short label and "Planned" in its tooltip. It moves to its working position in the change that ships it |
| IP / SI toggle at the right end of the tab row | Keep. It changes display and entry only; everything stored is SI (libraries Q14) |
| Status bar: product version, then "Editing: Model" showing the active edit context | Keep. The context readout matters more now, since Create Space and Place depend on being inside a Zone |
| Page heading with a count beside it, primary "+ New" button at the right | Keep |
| Filter, Group by, Order by, Direction as one control row above every inventory | Change (UI and UX refinement D2, 2026-10-03). Still one row: the filter field without a label, Group by, Order by, and Direction as one icon toggle |
| Grid toolbar: fill down, fill right, the keyboard hint, and a "…" Table options menu | Change (D2). The fill tools join the control row and show once a range is selected; the hint sits behind a help button. The Table options menu is not built yet and arrives with the first table that needs column show and hide |
| Yellow banner under the page heading for warnings | Keep the pattern. Its designPH messages go |
| Enum values as coloured chips with a chevron | Keep. The values change where a packet says so |

The tab row accepted in U1 was:
Zones / Faces, Spaces, Assemblies, Window Types, Thermal Bridges · Planned, Systems · Planned,
Library, Export. D4 confirms Equipment, ERV ducting and Hot-water piping as peer subtabs under
Systems, with one work surface at a time. Do not add separate primary Ducting or Piping tabs.

Revised 2026-11-15 by Phase 4's
[D4-13](../features/phase-07-mechanical/DECISIONS.md#part-3-wireframe-review-2026-11-15): the
tab is named Mechanical; its subtabs are by system (Ventilation, Heat Pumps, Hot Water, Pumps,
Fans, Electric Heating); a pill row under the subtabs picks one table inside a system, with
Ducting under Ventilation and Piping under Hot Water. Still no primary Ducting or Piping tab.

As shipped on 2026-11-22 the row is Climate, Zones, Programs, Assemblies, Window Types, Thermal
Bridges, Library, Export, then the reserved Systems button, disabled. Phase 4's
[D4-27](../features/phase-07-mechanical/DECISIONS.md#part-4-review-after-programs-2026-11-22),
answered 2026-11-22, puts the Mechanical tab after Thermal Bridges and before Library.

Built by P4-05 on 2026-11-24 (offline; the host review is owed to the MS2 sitting): the row reads Climate, Zones,
Programs, Assemblies, Window Types, Thermal Bridges, Mechanical, Library, Export, and the reserved Systems button is
gone. Mechanical opens on one page header, the Ventilation subtab and its Ventilators pill; the pill row is the kit
part `html/pill_row.js`, and later families register their subtabs and pills without editing the tab.

Built by P4-07 on 2026-11-24 (offline; the host review is owed to the MS2 sitting): the Hot Water subtab follows
Ventilation with its Systems, Heaters and Tanks pills (Piping joins with P4-13). Every equipment table is one shared
part, `html/features/mechanical/equipment_table.js`, which the Ventilators table now uses too: Tag pinned first, the
family's columns, Manufacturer, Model and Notes behind Columns, New in the page header, Duplicate and Delete in the
shared dialog. Read-only values (recirculation, a Tank's export slot) are plain cells, muted while they are
honeybee-ph's defaults; a Heater's Type changes in the shared form dialog, since the new Type needs its own values.

## 1. Spaces

Superseded in part on 2026-10-15 by the Spaces packet's D3a-16 and D3a-17: Spaces is a view of the
Zones tab, beside Faces, in the table-first pattern, with no Levels rail, no Airflow balance subtab
and a numeric weighting factor rather than two chips. The rulings below record the predecessor
screen; where they disagree with D3a-16 or D3a-17, those win. See
[the Spaces mockups](../archive/phase-03a-spaces/mockups/README.md).

What the screenshot shows: a Levels rail on the left with All levels and one checkbox per level,
each with a count. A control row with Filter, Order by, Direction, Collapse all and Expand all.
A tree table with Actions (Locate, Enter, Delete), Hierarchy (Space with a chevron, Volume rows
beneath), Number, Name, Floor level, Height, Raw area, Net factor, Net area, TFA factor and TFA.
A footer legend: "Height inherited from Volume · TFA = raw area × TFA factor · Vn50 = net area ×
height".

| Part | Ruling |
| --- | --- |
| Levels rail, control row, tree table, row actions, range edits, saved layout, footer legend | Keep |
| TFA factor, TFA | Change to iCFA factor and iCFA. The factor cell is two chips, Counts and Does not count (spaces Q4) |
| Hierarchy of Space and Volume | Change. Zone rows sit above Spaces once a second Zone exists (zones Q13), and Floor Segment rows sit under Volumes |
| Floor level column, editable per Space | Change. Level belongs to the Zone and a Space inherits it, so the cell is read only here (zones Q6) |
| Footer legend | Change the wording to iCFA and net volume. "Vn50" goes |
| Supply, extract and transfer airflow columns | Add, with missing shown distinct from zero (spaces Q8) |
| Net volume column | Add (spaces, Volume section) |
| Move Space to Zone in the row actions | Add (spaces Q18) |
| A subtab pair, Spaces and Airflow balance, using the shared subtabs nav | Add (spaces Q9, Q16) |
| Select by on any cell | Add (spaces Q12) |

## 2. Assemblies inventory

What the screenshot shows: heading with "+ New Assembly", "Push to designPH (1)" and an info
button. A yellow warning banner about a declared-U slab. A table with Actions (Open, Select
faces, Replace, Duplicate, Delete), Name, a Type chip, an Exterior chip, Thickness, U, a State
cell with a designPH row id beneath it, a Faces count with a refresh icon, and Notes.

| Part | Ruling |
| --- | --- |
| Table, control row, row actions, Faces count | Keep. The count comes from face records and is live, so the refresh icon goes (Phase 2 decision D2-3, 2026-09-30, superseding assemblies Q13). The icon returns only if the P2-05 measurement forces the scan-on-request fallback |
| Push to designPH button, the designPH line under State, "not pushable" | Remove |
| The declared-U warning | Remove. There are no assemblies without layers (assemblies Q4) |
| Type chip: Wall, Floor | Change to Wall, Roof, Floor or blank, stored as honeybee's words (assemblies Q2) |
| Exterior chip: Outdoor air, Ground | Change to Outdoors, Ground, Attached zone, To neighbour or blank (assemblies Q2) |
| Colour swatch column, as the Materials table has | Add (assemblies Q6) |
| Paint onto faces in the row actions | Add (assemblies Q14) |
| Faces cell | Add the summed area beside the count |

## 3. Assembly Builder

What the screenshot shows: a collapsible Material Library sidebar with a source selector
("In this file · Model"), search, a Category filter and a sort, and a tree grouped by category
with colour swatches. A details bubble anchored to a tree row with Conductivity, Density,
Specific heat, Emissivity, a "Source and notes" disclosure and a Use button. A header with a back
arrow, the assembly name, the Type and Exterior chips, "Update in designPH", and two metrics at
the right: Total thickness and U-value. A floating toolbar reading "Layer 3 · segment 1" with the
material swatch and name, "Advanced...", "Esc to deselect", zoom out, fit, zoom in, an
eyedropper, flip and layer controls. The drawing, labelled "EXTERIOR · Outdoor air · Rse ..."
above and "INTERIOR · Rsi ... · horizontal heat flow" below, with thickness and width dimensions.

| Part | Ruling |
| --- | --- |
| Sidebar, details bubble, Use, drag and drop, header layout, toolbar, drawing, film labels, dimensions | Keep |
| "Update in designPH" and its info button | Remove |
| Header metrics: Total thickness, U-value | Change. Two U-values, with surface films and without (assemblies Q8) |
| Toolbar label "Layer 3 · segment 1" | Change to "Layer 3 · Layer-Segment 1" (assemblies Q3) |
| Type and Exterior chip values | Change, as in the inventory |
| Assembly colour swatch in the header | Add (assemblies Q6) |
| Ventilated cladding toggle, under "Advanced..." at assembly level | Add. It changes the Rse shown above the drawing (assemblies Q8) |
| Source selector in the sidebar | Change. It lists every configured provider (libraries Q4) |

## 4. Window Type Builder

What the screenshot shows: subtabs Window Types, U-Values and Schedule. A collapsible type list
with Add, Sort and New group. A header with the type name, U-w and U-w,installed metrics with an
info bubble, then icon buttons, a yellow "Before placing" alert, a disabled Place button and a
"…" menu. A drawing toolbar with the "Exterior view" chip and zoom at the left, and Clear, Merge,
Split, Empty, Flip, Eyedropper and Undo at the right. The dimensioned drawing with element name
pills, dashed operation marks and a hover insert control. "Showing 1 of 2 elements" with "Show
all elements". An element card with rows for Glazing and four Frames, a product select in each,
columns for U-value, Width, g-value and psi-install, incomplete rows in yellow with an alert
icon, and a star toggle at the top right of the card.

| Part | Ruling |
| --- | --- |
| Subtabs, type list, header metrics, drawing toolbar, drawing, insert controls, element cards, incomplete-row treatment, "Show all elements" | Keep (window-types Q11) |
| The star toggle on the card, designPH's preview reference | Remove |
| The push or upload icon in the header | Remove |
| Place, shown disabled | Change. It starts the Place tool with this type chosen (window-types, Place) |
| "Before placing" alert | Keep. Its steps lose the designPH items |
| Installs button and its staged session | Keep (window-types Q12) |
| Schedule subtab | Change. It lists PH-Composer's own units by type, with Zone, host, Level and Locate |
| Install depth | Add: a model default beside the Psi-Install model default in Library, and a type override in the header "…" menu (window-types Q9) |
| "Frame" as the row label | Keep. It already matches the rename (window-types Q15) |

## 5. Library / Materials

What the screenshot shows: the Library heading with a count and "Definitions stored in this
model." Subtabs Materials, Frames, Glazings and Psi-Install Types. The sidebar with its source
chooser open: "Choose material library", "In this file" marked Viewing, "BLDGTYP · PH-Nav Web",
and "Library setup...". A table with Actions (Duplicate, Delete, a uses count that opens a
bubble), Name with a "Library" badge on copied records, a Color swatch, a Category chip, the four
thermal properties and Notes. "+ New Material" at the right of the control row.

| Part | Ruling |
| --- | --- |
| Heading, subtabs, table, row actions, uses bubble, Library badge, category chips, swatches | Keep |
| Source chooser popup | Change. It lists In this file and every configured provider that serves this kind: library files by name, connections by their label. Never an address (libraries Q4, Q16) |
| "Library setup..." | Change. It opens the Libraries section of preferences: add a file or folder, add a connection, remove one (libraries, Changed by the pivot) |
| Attached zones subtab | Add (face-assignment Q21) |
| Library badge | Add the provider's name on hover, and a quiet "source changed" mark while that provider is loaded (libraries Q8) |
| Export model library to file, in the heading's actions | Add (libraries Q15) |

## 6. Library / Glazings and Frames

What the screenshot shows: the same page on the Glazings subtab with a provider connected
("BLDGTYP · PH-Nav Web · Connected"). The sidebar tree grouped by manufacturer with counts. A
record already copied shown muted and italic with a file icon. A details bubble with U-g and
g-value, "Source field review" and "Source and notes" disclosures and an "Add to this file"
button. The grid toolbar's muted aggregates: "1 record · 1 element use · 0 placements". Columns
Actions (Uses, Duplicate, Delete), Name, Manufacturer, Product code, U-g, g-value, Description,
Color.

| Part | Ruling |
| --- | --- |
| Everything shown | Keep |
| "0 placements" | Change to "0 units", the packet's word for a placed window |
| Connected state label | Keep. The other states carry over too: signed out, waiting for approval, offline, library file open |

## Screens with no predecessor

These need design work, not a copy. Each is built from the shared primitives above and recorded
in the polish skill's `patterns.md` once Ed accepts it.

| Screen | Closest predecessor pattern | Owning packet |
| --- | --- | --- |
| Overview: the model tree of Zones, with the faces table under each | The Spaces tree table and its Locate | zones-and-adjacency Q13, face-assignment Q11 |
| Overview's pane order, built 2026-09-20 in P1-D D7 | The Zone tree first as the work surface, then Colour by, then the Classify palette. Each is its own section with its own heading, and the palette shows its Stop control only while the tool has the viewport. Needs Ed's ruling: the alternative is one heading with the two controls in the tree's action bar | ui-polish "Layout" |
| Classify tool palette: face type chips, boundary condition chips, assembly picker | Enum chips and the Builder's floating toolbar | face-assignment |
| Colour-by control and the viewport HUD legend | None. The legend draws in the viewport, not the panel | face-assignment Q16 to Q18 |
| Airflow balance | Superseded 2026-10-15 (spaces D3a-8): sums and a marker on the Spaces view's Zone rows | spaces Q9, Q16 |
| Place tool's panel side: chosen type, anchor picker, the measurement box hint | The "Before placing" alert and header actions | window-types |
| Window Schedule for our own units | The predecessor's Schedule layout, minus adoption | window-types |
| Preferences / Libraries | The predecessor's Library setup surface | libraries |
| Attached zones subtab and its inline creation from the boundary condition chip | A Library subtab with `formDialog` | face-assignment Q20, Q21 |
| Systems: Equipment, ERV ducting and Hot-water piping peer subtabs | Shared subtabs nav, one work surface at a time | confirmed by D4; equipment Q9, ducting Q8, piping Q12. Revised 2026-11-15 by Phase 4 D4-13: the Mechanical tab, subtabs by system, a pill row for the tables inside one. Built by P4-05 (Ventilation › Ventilators), host review owed to MS2 |

## Decisions recorded

2026-09-18. Ed agreed to all five.

| # | Decision | Answer |
| --- | --- | --- |
| U1 | Primary tab row | Zones / Faces, Spaces, Assemblies, Window Types, Thermal Bridges · Planned, Systems · Planned, Library, Export. The Zone tree and faces table live under Zones / Faces. Systems contains Equipment, ERV ducting and Hot-water piping peer subtabs; no extra primary tab is proposed. Revised 2026-11-15 by Phase 4 D4-13: Systems is named Mechanical and its subtabs are by system |
| U2 | Chip words | Chips show the palette's short words, such as Roof. Records hold honeybee's, such as `RoofCeiling` |
| U3 | U-value in the Assemblies inventory | One column, with films. Both values appear in the Builder header |
| U1a | Overview renamed | 2026-09-30: the Overview tab becomes **Zones / Faces**, with tab settings behind a gear icon in its action bar. Implemented and accepted in [Phase 1 UX follow-ups](../archive/phase-01-ux-followups/README.md) Z5 |
| U4 | Screenshots | Kept out of the repository. `screens/` is gitignored and the files stay in Dropbox |
| U5 | Accent colour | The predecessor's dark teal, until the product has its own identity |

## Next step

Ed drops the six files into `screens/`. After the foundation transplant, each
screen's first PH-Composer build is reviewed against its table here with the polish skill.
