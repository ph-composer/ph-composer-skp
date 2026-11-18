# Model a building in PH-Composer

Open a SketchUp model of the building. Work through the envelope and Spaces, then save the
SKP and write HBJSON from the Export tab.

## Set the site and the design temperatures

Open the **Climate** tab, the first tab in the row. The panel still opens on Zones. The cards on
the left show each part's state; at a narrow panel width they become one list above the page.

1. Choose **Site location**, then **Set Location**. Type the latitude, longitude and elevation.
   All three are needed to set the site. The climate zone and the hours from UTC are for export
   and may stay unset; the Export tab names an unset one. **Read from SketchUp Geolocation**
   fills the latitude and longitude when SketchUp reports the Model as geolocated, and otherwise
   says it has no geolocation. It does not fill the
   elevation or the hours from UTC, and it writes nothing back to SketchUp. The outline map beside
   the fields places the site too: drag to pan, scroll or use the zoom buttons, and click to fill
   the latitude and longitude. The map ships with PH-Composer and loads nothing from the internet.
   With a station attached, the map shows it and its 50 mile ring, and Set Location warns before
   a site that would put the station outside the Phius limits; the site can still be set. Set
   Location is one Undo step.
2. Choose **Design temperatures** and type the ASHRAE 99% heating and 1% cooling dry bulbs, with
   an optional source note. Each field saves when you press Enter or leave it, as its own Undo
   step. Clear a field to unset it. A heating value at or above the cooling value is saved with a
   warning. The design temperatures stay in the Model; export does not wait on them.

Values follow the IP and SI switch and are stored in SI. The **Phius climate data** card shows
the state of the Model's climate; choosing a station from this tab comes in a later version, and
the **Hourly weather file** card is planned.

## Set up climate data on this computer

PH-Composer includes no climate data. Phius licenses its climate files to you, so they stay on
your computer, and PH-Composer reads them where you keep them. It copies nothing and shares
nothing: your licence covers your own use of the files, and PH-Composer never sends them anywhere.

Open **Climate Data on This Computer** from the Climate tab's page header, or from the Setup view
behind the gear at the right end of the tab row, where its line says how many folders and stations
there are. With no folder set up, the **Phius climate data** card offers **Choose Climate Data
Folder** as well.

1. Choose **Add Folder** and pick the folder that holds your Phius station files. Subfolders are
   read too; a station's state is the name of the folder its file sits in.
2. Type the dataset name. It starts as the folder's own name, and it is the name the Model and the
   Export report show.
3. Each folder's row shows where it is, the format found, the number of stations and states, and
   the files it did not read, by kind. A folder that also holds spreadsheets or other files is not
   at fault: those are counted and left alone.

The counts are read each time the dialog opens, so a file you add or change shows up the next time,
with nothing to rescan or import. A folder that cannot be found, because it moved or is on a drive
that is not connected, keeps its row: **Locate** points the setting at its new place, and
**Remove** forgets it. Its stations are left out of the station picker until then. PH-Composer
never removes a folder setting itself, and removing one never changes a Model.

What is kept where: each folder's location and dataset name in a PH-Composer settings file in your
user folder, outside SketchUp's own folders, so every SketchUp version on this computer reads it;
the station files, read when they are needed; and in a Model, only the station you attach, never a
folder location. Climate data folders are available on macOS for now.

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

The HBJSON carries the site and the climate on every Building-Segment. The site location is
written once it is set. The climate is written once it is complete and the site is set, with its
source: an unedited Phius station, or a climate you edited or typed. The second cooling case
repeats the station's one. The report's Climate section lists the site, the dataset and station,
the Phius limit check, any edited values with the file's values, the peak loads, the wind speed
and the design temperatures, which stay in the Model. It names no folder on your computer. A
climate left out is named there with the reason, and the export still runs.
