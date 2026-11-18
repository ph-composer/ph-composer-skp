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
the state of the Model's climate and opens the station picker (see "Choose a Phius station"), and
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

## Choose a Phius station

With a climate data folder set up and the site set, choose **Phius climate data**, then **Choose
Station**. The picker shows every station of one dataset on the outline map and in a list, with
each station's distance from the site, its elevation above or below the site, and a Pass or Fail
result. It opens on the dataset of the station already attached, else the one you used last, sorted
by distance, with State on All and the map framed on a 50 mile ring around the site.

- **Dataset** changes the folder, and the picker opens on it next time. **State** narrows the list
  and the map to one state folder, and the search field narrows them by name. **Find Nearest** goes
  back to the opening view with the nearest station selected.
- Click a station on the map or in the list to select it in both. Hover over a station on the map
  for its name, distance, elevation difference and result. In the list, the arrow keys move the
  selection.
- Under the map and the list, the selected station is compared with both limits. **Attach** copies
  its values into the Model, as one Undo step.

A station passes when it is within 50 miles (80 km) of the site and within 400 feet (122 m) of the
site's elevation. Outside either limit it fails. Both limits are Phius's (Certification Guidebook
2024, section 1.4.4.2). A failing station can still be attached, with no extra step: the picker says
before Attach that Phius asks for a custom dataset there unless an exception applies, and the card,
the pane and the Export report then show the climate as outside the Phius limits. PH-Composer
reports the result and does not approve or refuse a station; Phius decides.

With a climate already in the Model, the page header offers **Replace**. The picker then shows the
current and the selected station side by side, with their dataset, distance, elevation difference
and result, and says how many edited values replacing would discard. **Replace** is one Undo step.

## Read an attached climate

With a climate in the Model, **Phius climate data** shows it in full, read from the Model alone:

- The station's name, its dataset and place, and its marks: Pass or Outside Phius limits, Edited,
  Incomplete, and Source changed.
- The Phius limit check: the distance and elevation difference from the site, each against its
  limit, with the result. It is worked out again whenever the site changes. A station outside the
  limits says so above the values, with a line that Phius asks for a custom dataset there.
- The monthly temperatures and radiation, and the peak loads for Heating 1, Heating 2 and Cooling 1.
  Ground temperatures and a second cooling case are not part of a Phius station file and are shown
  as such. On a narrow panel each table scrolls sideways inside its own box.
- The station elevation, the daily temperature swing and the average wind speed. The wind speed
  starts as the mean of the file's January and July values; type another and press Enter to change
  it. Changing it does not count as an edit.
- **Where this lives**: what the Model holds, whether the station file is on this computer, and what
  the climate is ready for.

A value that differs from the station file is marked in its table; hover over it for the file's
value. A line above the values names the edits, and **Restore Original Values** puts the file's
values back as one Undo step. The Model keeps the values as read, so this works without the folder.

When the station file on this computer differs from the copy in the Model, Where this lives says
**Source changed**, and **Update from File** opens the picker in Replace on that station. Nothing
updates on its own.

On another computer, or one with no climate data folder, the pane reads in full with no notice, and
Where this lives says the source is not on this computer. **Replace** then explains that there is no
folder and offers **Choose Climate Data Folder**. **Clear**, in the page header's **More climate
actions** menu, removes the climate as one Undo step with no confirmation; the site and the design
temperatures stay.

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
