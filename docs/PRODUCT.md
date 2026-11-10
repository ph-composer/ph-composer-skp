# Product shape

**DATE:** 2026-10-16

PH-Composer is a free, open-source authoring tool for Phius passive building models. The SKP
file holds the working building data. A consultant can enter every supported definition by hand,
assign it in the model, and export without an account or network service.

Everything below describes agreed product behavior. The predecessor, PH-Navigator for SketchUp,
settled most of it through recorded interviews between 2026-09-06 and 2026-09-17, and the rules
that did not depend on designPH carry over unchanged. Phase 1 implemented Zones, face
classification and the HBJSON/report export described under Zones, Envelope and Handoff; assembly
assignment, local libraries, Window Type records, the Builder and Unit operations are implemented
and accepted on the Phase 2 feature branch for SketchUp 26.1.188 on macOS. Normal export
includes authored opaque constructions and Apertures. File libraries, Place, Schedule and
Window Type Colour-by pass their named current-host requirements. Connection libraries are Phase 5. Spaces is
implemented and accepted on SketchUp 26.1.188 on macOS, and so are thermal bridges.

## The working environment

One persistent workspace combines the envelope classification tool, graphical assembly and Window
Type editors, local definition tables, the Space hierarchy, thermal bridge and equipment schedules,
piping and ducting workflows, model validation and Export. The predecessor shipped the Assembly
Builder, the Library, Window Types and the Spaces table; those transplant. Face assignment, window
placement and thermal bridges are new.

The Library is the one home for Materials and for Frames, Glazings and Psi-Install Types.
Every model has a default install psi-value, 0.04 W/mK until the user changes it, and the user
can choose a Psi-Install Type as the model default in its place. The Assembly Builder opens inside the
Assemblies tab. The accepted Space hierarchy is Space, then Volume, then Floor Segment.

## Local definitions and optional reuse

Materials, assemblies, frames, glazings, Window Types, Space Types and equipment definitions are
created within the model. Library import copies a record into the model, where it remains
editable and available offline. Remote changes never silently replace working data.

A library sidebar sits beside the Assembly Builder and beside Library / Materials. Its source is
any library provider: a library file on disk, or a read-only connection to a server. First use
copies one record into the file and assigns it, or adds it without assigning; repeat use reuses
the editable local copy. The file stores attribution, never a server address or credential.

## Assemblies and materials

Partially built assemblies can be saved and reopened. Missing materials or properties withhold
U-values until required inputs are present. An assigned assembly that lacks required thermal
inputs blocks ordinary export; unused incomplete definitions and missing optional evidence do not.

A committed Assembly edit updates every assigned face without manual reapplication, with affected
uses visible. To change only some faces, duplicate and edit the assembly, then assign the new
definition to those faces.

Duplicating an assembly reuses its shared materials and datasheets and starts with empty
installation-photo collections.

Deleting an assigned assembly requires a replacement for all assigned faces, with affected faces
shown and cancellation available. Unassigned assemblies delete directly. Geometry remains intact.

Deleting an in-use material requires an explicit replacement for all its uses, with affected
assemblies shown and cancellation available. Replacement materials use their own datasheets.
Source files remain untouched. Deletion must not break references.

One model-local record represents a material across its assembly uses. Editing its properties
updates those uses. Thickness belongs to each assembly layer; conductivity, density and specific
heat belong to the shared material. Installation photos belong to a material within an Assembly
definition, shared across faces using that assembly.

Material categories are preset, shown as a muted colored chip, with Uncategorized available for
unfinished records. Each material has an editable display color used for its Assembly Builder SVG
fill, presentation only. Duplicate Material creates a separately named independent material, with
Copy datasheet links unchecked by default. Ordinary reuse never creates another material.

The Assemblies inventory shows one row per assembly with its attributes, thermal performance,
usage and validation state. The Builder edits the drawing through an always-visible toolbar and
anchored property bubbles. Total thickness and U-value stay visible in the header. Both
inventories share filter, Group by, Order by and sort direction controls (the Zones tab sorts and
filters from its column headers instead); filtering retains local drafts and never changes the model
or the export scope.

## Zones

A Zone is one SketchUp Group, the geometry unit that becomes one honeybee Room. The user makes a
Zone from a selected Group or from loose geometry, and tags it with a Building-Segment and an
optional Level. Solve adjacencies pairs the faces two Zones share, cutting partial overlaps so only
the shared region pairs, in one Undo step. It runs only when asked, and Export offers to run it
again before the model is written. A copied Zone or a split face keeps its records. Copying a Zone in
SketchUp makes the copy independent at once: it gets its own faces and identity, the Zone it was
copied from stays as it was, and one Undo removes both the copy and that change. A duplicate that is
already in a file, or a copy SketchUp keeps shared (inside a component or a copied parent group), is
read only until it is made independent with Make Zone independent, on its row or in its context
menu. Ambiguity is refused rather than guessed.

Make Zone and the Zone attributes are available from the selected geometry's native context menu.
The Zones header has no Make Zone button; use the native context menu to create a Zone. Make Zone is not offered on,
and refuses, a Space, a Volume, a Floor Segment or anything inside one.
The Geometry view's selection bar offers Solve when at least two Zones are fully checked. A partially
checked Zone is excluded; fully checked Zones remain included when hidden by a filter. Checking
all Zones provides the whole-Model workflow. The native command solves selected Zones. A pairing
that would change an unchecked neighbour is refused with a message naming that Zone.
A Zone's name follows its Group name in Entity Info and Outliner. Clearing that name restores
the last valid name.

## Envelope

The user selects Faces, then sets one face type, boundary or Assembly from the native context menu:
PH-Composer > Set Face Type, Set Face Boundary or Set Face Assembly. Each list marks the value every
selected Face holds; a selection with mixed values marks nothing. Surface comes only from Solve
adjacencies, so it shows greyed, for Faces that all hold it.
Existing Attached zones appear there; New attached zone opens a form for the captured selection.
The Classify tool also paints by click, drag or Shift-click across a connected plane, one Undo
step per gesture. In the Geometry view, Type, Boundary and Assembly column menus show visibility checkboxes
and separate paint icons beside their values. A paint icon starts that field only, including values
not yet used in the Model. An active header paint icon names the value and stops painting when
clicked. Starting paint switches Colour by to the matching field while painting; when painting
stops, the Colour by view from before it comes back, unless another one was picked meanwhile.
Attached zone painting uses Boundary condition Colour by. The Boundary menu also offers Attached
zone selection and a New attached zone route. Surface remains set by Solve adjacencies.
Suggest classification proposes a face type and boundary condition for each face of a Zone that
has no classification record yet, from its geometry.
Make Zone runs Suggest by default in the same Undo step. The tab's gear control stores the switch
and roof/floor tilt thresholds in the Model, initially 60 and 130 degrees. Settings changes can be
undone independently.
An Attached zone, such as a garage or attic, is a named boundary condition with its temperature
reduction factor. Colour by shows face type, boundary condition, Zone, Building-Segment, Level, Assembly
or Window Type on the model without changing its materials. The Zones tab is one table of Zones read
through views. Geometry is the first: each Zone with its own fields as columns and its faces beneath, with
Colour by, sorting and filters in the column headers. While more than one view is available, a row of
view tabs above the heading switches between them; each keeps its own column filters and sort, and this
computer remembers the view last shown. Each column's Show choices filter the table and leave excluded geometry in its plain SketchUp colour while
Colour by is active. Filters combine across columns, and Clear filter restores that column's values.
The active Colour-by column's choices include colour swatches. Text search remains table-only.
Zone fields include all geometry in matching Zones. Face fields colour only matching Faces;
detached Window units have no matching Face and lose their colour under those filters. To see past excluded Faces, use a section cut.
Filtering changes no geometry visibility, materials or saved Scenes. Faces checked in the table, or selected in SketchUp, are edited together from a bar
under the table. Locate frames faces and outlines them without changing the selection.
Assembly assignment is implemented with Assemblies on the Phase 2 branch. A face inside a repeated component is shared by every occurrence, and independent
classification requires the user to make the parent unique first. PH-Composer never does that
automatically. Unclassified faces are visible in validation and never silently exported.

Thermal bridges are identified on the model as edges, assigned a type carrying a psi-value, and
exported with their measured length. A Thermal Bridge Type holds one psi-value, its group (Ambient,
Perimeter or Basement floor) and links to its calculation report; a second value is a second type.
Edges inside a Zone take a type from the Thermal Bridges tab's assign bar, from the right-click
"Thermal bridge" menu, or by clicking them with Assign by clicking Edges; each gesture is one Undo step, and
the assignment lives on the edge, so a copy or a split carries it. Connected edges of one type,
quantity and Zone form one run, named by its type and a counter. The Schedule lists each run's
length, psi-value, quantity and heat loss with totals by type and by group. Colour by shows assigned
edges in their type's colour or their group's, from the palette icons on the Name and Group columns of
the Types table and the Type and Group columns of the Schedule, or from the Colour by menu. Export writes each run as one thermal bridge on its Zone's
Building-Segment. Where two Zones each hold an edge at a shared junction, assign it from either or
both: the same type at the same quantity in one Building-Segment counts once. Coincident edges that
differ in type, quantity or Building-Segment are a warning and both count until one is cleared. A
missing type or psi-value blocks export; an edge outside every Zone, a stray line, an interior
junction, coincident edges that differ and an edge on a placed window's outline are warnings in the
preflight and the report, and the rest export. Point bridges and chi-values
are outside the MVP. They can return as later scope only after the canonical honeybee-ph artifact
has a real carrier for them.

## Window Types and placement

Window Types describe exact size, layout, frames, glazing, operation, handedness and
perimeter Psi-Install Type assignments. Shared frame and glazing records hold product properties
and datasheets. Users define explicit installation variants by duplicating a Window Type and
changing its Psi-Install Type assignments. Every placement follows its type; there are no
per-instance installation overrides.

The graphical editor covers windows, doors, skylights and mulled units. An opaque door is entered
as a glazing with a g-value of 0.
Placement and resizing use sill center as the default fixed point; the user can choose another
anchor per unit, shown before changes and retained for later resizes.

A window unit is a flat component PH-Composer generates from its Window Type, with one face
per glazed element, glued to and cutting an envelope face. PH-Composer authors no window
shading; METr handles it after export.

Incomplete types can be saved and, with sufficient size and layout, assigned. Missing required
thermal inputs on assigned types block ordinary export. Unused incomplete types do not. Export
does not silently substitute values or omit windows.

Place starts with the chosen Window Type from the Builder, Type browser or Schedule. It previews
an outline on a host Face and stays active for repeated placements. Nine anchors are available.
In SketchUp's measurement box, `sill=<length>` sets the opening bottom above the host's minimum
up extent; `offset=<length>` sets the chosen anchor's inward distance from the nearest outer
host edge. Stop or Escape ends the tool. The cursor infers and snaps as native tools do, to
endpoints, midpoints, edges and guides, so CAD linework can guide the anchor in one step; a point
off the host's plane, such as linework in front of the wall, lands square onto it. While placing,
the panel shows the two measurements as a callout and SketchUp labels its measurement box.

Draw-then-convert is the other route. Draw the opening as a rectangle with SketchUp's own tools on a Zone Face, or
coplanar with one outside every Zone, select it and choose Convert to Window Type from the context menu or the
Extensions menu. In an open Zone the context menu offers it only on a Face nested in the Face around it. The panel lists what becomes a Window Type and why anything else is left out. Rectangles sharing an
Edge become one mulled Type, and same-size rectangles share one. Each new Type is named by its size and blank unless
you choose Copy from. One Undo restores the drawn rectangles.

A Window pasted or moved off its Face goes back to the nearest Face of its Zone, in the same Undo
step, and says so in SketchUp: it keeps its position if it already lies clear on a Face, and
otherwise is squared to the Face and brought just inside its edge. A Window with no Face beside it
in its own container, or no room on one, stays where it is, says why, and keeps its Unhosted
finding in the Schedule.

The Schedule counts Unit occurrences by Type, including detached definitions, and shows Zone,
host Face, Level and Locate. Differing or unhosted Units retain their state and offer explicit
repair routes. Window Type Colour-by paints the generated panes through the shared drawing
service and respects hidden geometry and tags.

A Window's name is its SketchUp instance name. It can be typed in the Schedule or in Entity Info's
Instance field, and each shows the other's. A Window with no name reads as its Type and a number in
the Schedule, as a hint. Names need not be unique, as in SketchUp; each Window's row sits under its
Type. Selecting Windows in SketchUp marks their rows in the Schedule and scrolls to them.

The Schedule shows net opaque host area: the gross host polygon minus the openings of glazed
elements. Empty panels leave opaque area intact. Uncertain native Window geometry withholds
the net value until repaired. The Geometry view and assembly usage retain gross area.

Export maps each glazed element to an Aperture on its gross parent Face. Construction identity
includes product references and translated thermal values, including the element's size-dependent
U-w and resolved Psi-Install values. Shared internal edges carry Psi-Install 0; perimeter edges
use the assigned Psi-Install Type, the model-default Psi-Install Type, or the model's default
value when no Type is chosen. The report lists installs by name, the default value as "Model default", and
gross, glazed and net host areas.

Exact g-values of 0 and 1 are preserved. The pinned honeybee-energy runtime accepts these
endpoints; honeybee-schema's simple glazing range excludes them. Local conformance permits
only this documented endpoint exception, and the Export report names each affected construction.
PH-Composer does not substitute a nearby value.

Optional external evidence follows its owner: product photos on Window Types, datasheets on frame
and glazing records, installation photos and calculation reports on Psi-Install Types.

## Spaces

Spaces contain protected Volumes, and Volumes contain Floor Segments the user has classified as
iCFA. Creating a floor inside a Volume registers it; creating one at a Space root creates the next
Volume. Context changes reconcile and protect the structure. Native Save and Undo retain the
measured host contracts.

Spaces are read in the Spaces view of the Zones tab. Beneath each Zone are its Spaces, beneath each
Space its Volumes, and beneath each Volume its Floor Segments, with their floor area, weighting
factor, weighted area (iCFA), height, net volume and airflows. A Space outside every Zone is listed
after the Zones. A text filter that matches a Zone's name, Building-Segment or Level lists all its
Spaces; one that matches only a Space's number or name lists just the Spaces it matches. Spaces list by number within their Zone, Floor Segments read Floor in the Hierarchy column, and Height
shows on the Volume row, where it is set. Each Zone row shows its Spaces' sums; while any Space in a Zone
inherits its airflow from the Zone, the Zone shows a dash instead. Cells edit in place, and a range fill or a paste from a
spreadsheet is one Undo step. Checked rows edit together in the selection bar, and checked Zones
stay checked when switching to the Geometry view. Each row offers Locate and, where they apply, Open,
Close, Enter, Delete, Remove, Remove Volume, Move to Zone and the repair its problem names. The Weighting
factor column filters the table and colours the Model by factor. A Volume's height can be set from a closed solid the user draws, its volume over the Volume's net floor area, after a confirmation that shows both numbers. There is no Level rail and no
separate balance view; column widths last for the session.

The Weighting factor column menu starts Mark floor: a paint icon beside 0, 1 and each factor in use
turns it on with that factor, and a pressed paint glyph in the column header stops it, as Escape does.
Colour by weighting factor shows while it runs, and the Colour by view from before comes back when
it stops.
In the viewport, a click or a drag over Faces inside a Volume marks them as Floor Segments in one Undo
step; a click or a drag over loose Faces at a Space's root adds the next Volumes. A Face loose in the open context
and in no Space is offered Create Space, and a classified Zone Face or a Face inside a closed Group is refused with the reason.
Create Space is in SketchUp's Extensions menu, and in the context menu on a selection with at least one unclassified,
non-vertical Face, in any open context outside a Space: at the
Model root, in a plain Group such as a storey, or in an open Zone, where the Space is placed outside the Zone at the
same world position, so Zone Faces are never touched. The review says what a Space is and why it
leaves out any Faces, and offers a Zone choice, set to the
open Zone or the Zone whose plan footprint and height range hold the floor surface, which you can change, or No Zone. The new Space takes the Model's last height.
Create makes the Space, its Volumes and their Floor Segments in one Undo step. Faces share a Volume only when they
are joined: two Faces sharing a SketchUp Edge, a step between a floor and a ramp included, go in one Volume, while
Faces meeting only at a corner, or not at all, make a Volume each.
With a Space open, Add New Volume to Space takes the place of Create Space in the context menu on loose Faces at the
Space's root. It opens no dialog: the selected Faces become the Space's next Volumes by the same rule, with weighting
factor 1 and the Space's default height, in one Undo step. Space Groups stay Untagged; apply a tag of
your own to show or hide them. Draw a room's floor surface just below the Zone's floor, or
inset from its walls, so that it touches no envelope Face. A floor surface drawn with its edges on the
walls splits them, and Create Space leaves it out, saying to Undo it and draw it below or inset.
A Space is a floor surface plus a height, so a vertical Face is never a floor: Create Space, Mark floor
and a new Volume all refuse it. A room drawn as a closed solid, with upright or sloped sides, is left
out whole, its upright walls as walls and its other Faces as parts of the solid, so no floor is
counted twice; a new Volume refuses one too. The refusal says to draw the floor surface alone, or to
group the solid and use Height from solid.

Set Height, in SketchUp's Extensions menu and in the context menu on a Space or Volume, is a viewport tool for one
Volume's height. A selected Volume, or the one Volume of a selected Space, is picked as soon as the tool starts:
type a value in the measurements box and press Enter, or drag the top of the Space. For a Space with several
Volumes, click one Volume first. Each entry is one Undo step, and the value also becomes the Model's last height. Edit Floor Surface, in the same menus, opens the
Volume of a selected Volume or a one-Volume Space, unprotected, for ordinary SketchUp edits to its floor surface; leaving
it protects the Volume again.

The context menu on selected Spaces offers Set Name… and Set Airflows… for one or several Spaces, and Set Number…
and Move to Zone for one. Move to Zone lists the Model's Zones with the Space's own checked. Set Airflows… shows
Supply, Extract and Transfer in the panel's units, each with the value the selected Spaces share or blank where they
differ. A field left as shown changes nothing, an emptied field removes the value, and with all three removed the
Space uses its Zone's ventilation load again. Set Weighting Factor, on Floor Segment Faces in an open Volume, on
Volumes and on Spaces, sets every Floor Segment they hold to 1, to a factor already used in the Model, or to a value
from 0 to 1 typed in Other…. A factor is checked only when all of those Floor Segments have it. Each of these edits
is one Undo step.

Colour by Space, Ventilation, Weighting factor and Height colour each Space's Floor Segments and the
Volume preview that its height draws over them, with a legend. Show Spaces, on by default each time a
Model is opened, draws the outline of every Volume preview and each Space's label whether or not a mode is on, in the
panel's units; turn it off from Table options in Zones > Spaces or the Colour by menu. Selection totals, the
sums for the selected Spaces, are turned on in the same places. None of this is saved in the model.

Copying a Space in SketchUp makes the copy independent at once, with the next free number in its Zone,
and one Undo removes both. A copied Zone copies no Spaces outside it. A storey Group copied whole,
with Zones and Spaces inside it, gives every copied Space its own identity, and each copied Space
follows the copied Zone its original was hosted in; a Space whose Zone stayed behind keeps its
reference. A copied Volume or Floor Segment is marked as a duplicate until Make independent is run on
its row. Move to Zone hosts a Space in another Zone where it stands, keeping its number and values.
If its Zone is erased, the Space stays with a finding that blocks export and offers Remove from Zone.
Two Floor Segments of one Volume that overlap in plan raise a warning, since the area they share counts
twice; export still runs. Separate Volumes are not compared, so two storeys of one Zone overlap freely.
A Volume whose Floor Segments no longer all share Edges, after a joining Face is erased or a separate Face is marked
in it, raises a warning too. Export still runs and nothing is split for you.
Remove on a Space's row takes away the Space and its Volumes and leaves their floor Faces where they
are as plain geometry; Delete erases the Faces too. Each is one Undo step.

## Handoff

Export produces HBJSON with an adjacent report explaining supported content and findings. A
preflight lists blocking findings and offers repairs such as Solve adjacencies before anything is
written. The run can be cancelled, a failed replacement leaves the previous pair intact, and Export
never saves the SKP. A run blocked by a finding writes nothing, and the Export tab still shows its
report, marked as coming from a run that wrote no model, so its figures are there to fix the block.
Each Space travels on its Zone's Room with its Volumes, heights, Floor Segments, both factors, its
Volume previews and its airflows. The report gives a Spaces schedule for each Zone with the table's
columns and the totals for each Zone and Building-Segment, and names any Space drawn beside its Zone,
which exports where it was drawn. The METr model is a later exporter, deferred until more of the building can be
authored. Independent consumers decide how to view, review and calculate
it. Optional linked PDFs and photos remain in external project folders. Ordinary model use never
depends on those files.

## Delivery

The proposed scope is in [the PRD](PRD.md). Interview order and implementation readiness are in
[the planning folder](../planning/ROADMAP.md). Public release scope is undecided and requires Gate A.
