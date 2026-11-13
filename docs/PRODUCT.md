# Model a building in PH-Composer

Open a SketchUp model of the building. Work through the envelope and Spaces, then save the
SKP and write HBJSON from the Export tab.

## Make Zones and classify the envelope

1. Select a Group or loose geometry. Right-click and choose **PH-Composer > Make Zone**. Each
   Zone becomes one Honeybee Room.
2. Set the Zone's Building-Segment and optional Level. Use the column menus in **Zones > Geometry**
   to manage the choices and their colours.
3. Set Face Type, Face Boundary and Face Assembly from the context menu. To paint a value onto
   several Faces, use the paint icon beside it in the column menu. An Attached zone, such as
   a garage or attic, defines a boundary with a temperature reduction factor.
4. Check the Zones you want to pair and choose **Solve**. Include both Zones in a shared
   adjacency. Solve cuts partial overlaps and assigns the Surface boundary to the paired regions.

Make Zone runs Suggest classification by default. The Geometry view's settings let you change
that behavior and the roof and floor tilt thresholds. Review the suggestions with **Colour by**
and use column filters to see the matching Faces. **Locate** frames the chosen geometry.

A native copy of a Zone at the model root gets its own identity. Use **Make Zone independent**
when SketchUp keeps a copied Zone shared or PH-Composer flags an ambiguous Zone.

## Build and assign Assemblies

Create Materials in the Library. Enter thermal properties on the Material and thickness on each
Assembly layer that uses it. In **Assemblies**, use the Builder to lay out layers and segments.
Check thickness and U-value in the Builder header. Fill the required inputs before export.

Assign the Assembly from a Face's context menu or from the Geometry selection bar. Editing an
Assembly updates its assigned Faces. To change part of the envelope, duplicate the Assembly
and assign the new definition to those Faces. Before deleting a Material or Assembly in use,
choose a replacement for its assignments.

## Define and place windows

Create Frames, Glazings and Psi-Install Types in the Library. In the Window Type Builder,
set the size and layout, assign the products and check the calculated performance. To model a
different installation, duplicate the Window Type and change its perimeter assignments.
Perimeter edges use the assigned Psi-Install Type or the Model default. The initial default
psi-value is 0.04 W/mK.

Choose **Place** from the Builder, Type browser or Schedule. Pick an anchor and click the host
Face. The measurements box accepts `sill=<length>` and `offset=<length>` for controlled placement.
Alternatively, draw and select rectangles and use **Convert to Window Type**. Review the proposed
Types and placements before applying.

The Schedule lists each Unit by Type and identifies its host Face, Zone and Level. Use it to find
unhosted Units and resolve differences from the Type. The Schedule reports net opaque area from
the openings. The Geometry view and Assembly usage report gross area. Export puts each glazed
element on its gross parent Face as an Aperture.

## Assign thermal bridges

Create a Thermal Bridge Type with a psi-value and a group: Ambient, Perimeter or Basement floor.
Select edges inside a Zone and assign the type from the Thermal Bridges tab or the context menu.
Use **Assign by clicking Edges** to work directly in the viewport.

The Schedule groups connected edges of one type and quantity within a Zone into runs. It lists
length, psi-value, quantity and heat loss, with totals by type and group. Matching coincident
edges within one Building-Segment count once. If their type, quantity or Building-Segment differs,
review the warning and clear any duplicate assignment. Resolve missing types and psi-values
reported by preflight.

## Author Spaces and iCFA

1. Draw floor surfaces on loose Faces. Keep the floor inset from the envelope or slightly below
   the Zone floor so drawing it leaves the envelope Faces intact.
2. Select those Faces and choose **Create Space**. Review the proposed Zone and floor surfaces.
   Faces connected by an edge go into the same Volume.
3. Use **Zones > Spaces** to review each Space, its Volumes and their Floor Segments. Set height
   on a Volume. Use **Height from solid** when you want to derive height from the volume of a
   separate closed solid and the net floor area.
4. Set weighting factors in the table or use **Mark floor** from the Weighting factor column menu.
   To edit a protected floor surface, use **Edit Floor Surface** and leave the Volume when finished.
5. Enter Supply, Extract and Transfer for each Space that needs its own airflows. Clear all three
   fields to use the Zone's ventilation load.

Use the table to review iCFA, net volume and airflows. Locate an item from its row. **Move to Zone**
changes a Space's Zone assignment and keeps its position. **Remove** returns its Floor Segments
to plain geometry. **Delete** erases those Faces.

## Reuse library definitions

Use **Libraries** to add a file, a folder of files or a connection supplied by a hosted provider.
Copy the definition into your model and edit the local record. PH-Composer keeps its source
attribution. The model continues to use the local copy when the source changes or is offline.
The [library file format](LIBRARY_FILE_FORMAT.md) covers the supported wire kinds and limits.

## Export HBJSON

Run preflight in the **Export** tab. Resolve the blocking findings and run Solve if the
adjacencies need updating. Review warnings about omitted or uncertain geometry. Choose a
destination and write the HBJSON and its companion report. Use the findings in the Export tab to diagnose a stopped run. Save changes to the SKP through SketchUp.

The report records exported quantities and findings. Share linked datasheets and photos
separately when the recipient needs them.
