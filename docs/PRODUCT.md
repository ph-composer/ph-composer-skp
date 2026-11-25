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

## Enter or edit climate values by hand

**Enter Values by Hand** opens one editor with a grid in the order of a Phius climate file: outdoor
temperature, the north, east, south, west and global radiation, dewpoint and sky temperature, by
month, then the Heating 1, Heating 2 and Cooling design values. It needs no climate data folder and
no site. Use it for a custom dataset from Phius, or for a station outside the USA, which Phius
supplies only as an Excel workbook. A climate entered this way exports as user-defined.

1. Type a name and the station elevation; both are needed to save. Type the daily temperature
   swing and the average wind speed. Latitude and longitude are optional: without them the Phius
   limit check reads "Not checked, entered by hand".
2. In the workbook, select the eight series rows of the block in your unit system, from the label
   column or the first month to the last design column, and copy. From a station file, copy the
   eight series lines. Click the first cell of the grid and paste. The labels are left out, a value
   that is not a number is left empty and counted, and a block that does not fit from the cell you
   chose fills nothing. Do not include the month and day rows above the series.
3. Type or correct any cell. The arrow keys and Enter move between cells.
4. **Save** stores the climate as one Undo step. Empty cells may be saved: the card then reads
   Incomplete, the pane lists what is missing, and export leaves the climate out until it is
   complete. The dewpoint and sky temperature of the design columns may stay empty.

**Edit Values**, in the page header with a climate in the Model, opens the same editor on its
values. For a station, the name and coordinates stay as its file gave them; **Replace** changes the
station. For a station, each value you change is marked as edited, and **Restore Original Values**
puts the file's values back. If the climate changed elsewhere while the editor was open, saving refuses and your
values stay in the grid.

A Model holds one climate. To type a climate by hand in place of an attached station, **Clear** it
first.

## Make Zones and classify the envelope

1. Select a Group or loose geometry. Right-click and choose **PH-Composer > Make Zone**. Each
   Zone becomes one Honeybee Room.
2. Place each Zone in a Building Segment. Every Zone view groups the Zones under a heading row for
   each Segment, with Zones in no Segment last. To move Zones, check their rows and choose a
   Segment, **New Building Segment** or **No Building Segment** under **Building Segment** in the
   selection bar. The **+** icon beside the Zone count makes a new Segment and opens its name. A
   heading row's settings icon opens the Segment's settings: its name, colour, whether new Zones
   join it, and the settings other features add. Its delete icon asks where its Zones go. Set the
   optional Level in the Level column, whose menu manages the Levels and their colours.
3. In each Segment's settings, set its **Occupancy** (Single dwelling, and the house's counts), its
   **Phius certification** (building category, program, use, status and type), its **Airtightness**
   (the blower-door result as n50 or q50, and the wind exposure), read its **Comfort** set points,
   which come from its Zones' Programs, and set its **Mechanical** settings (whether the building has
   mechanical cooling, the mechanical room temperature, and the summer bypass and summer air changes).
   Save writes every section in one Undo step. With no blower-door result, the Zones keep their
   Program's infiltration. The export checks warn when mechanical cooling is switched on and no heat
   pump serving the Segment cools, or off while its heat pumps cool.
4. Set Face Type, Face Boundary and Face Assembly from the context menu. To paint a value onto
   several Faces, use the paint icon beside it in the column menu. An Attached zone, such as
   a garage or attic, defines a boundary with a temperature reduction factor.
5. Check the Zones you want to pair and choose **Solve**. Include both Zones in a shared
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
5. Leave the airflows empty to use each Zone's Program ventilation: its cells read **By Program**.
   Typing any rate on a Space switches that Zone to detailed airflows: every Space in it then exports
   its own Supply, Extract and Transfer, and a blank counts as 0. **From Program** on the Zone row
   clears them all. Transfer reaches PHPP only; WUFI-Passive and METr receive supply and extract.
   A Zone with no Spaces shows an amber No Spaces row and exports with no iCFA, net volume or
   ventilation.

Use the table to review iCFA, net volume and airflows. Locate an item from its row. **Move to Zone**
changes a Space's Zone assignment and keeps its position. **Remove** returns its Floor Segments
to plain geometry. **Delete** erases those Faces.

## Assign Programs, Dwellings and Equipment Sets

1. Use **Zones > Programs** to see each Zone's Program, Dwelling, bedrooms, occupants and Equipment Set,
   with its floor area, iCFA and the peak people, lighting and ventilation the export writes. Each
   Building Segment's heading row sums them. A column header's tooltip names the area a value is
   worked out on.
2. A residential Building Segment starts as a single dwelling. Its Zones are one house with the
   residential default Program, and their cells are locked. Enter the house's bedrooms, and its
   occupants and Equipment Set if they differ from the defaults, on the Segment's heading row. The
   bedrooms read as an amber **?** until entered. Click a locked cell or the **Single dwelling** tag to
   see why, and **Open settings** to switch Single dwelling off in the Segment's settings.
3. With Single dwelling off, choose each Zone's Program. A Zone with none uses its Segment's
   default Program, else the Model's, shown in italics. Programs from an added library file are
   listed after this file's own; choosing one copies it with its Schedules and assigns it in one
   step.
4. Click a Zone's Dwelling, or **None**, to choose its Dwelling: an existing one, a new one, or none.
   The same bubble edits the Dwelling's units, and shows its Zones, bedrooms, occupants and iCFA.
   Enter bedrooms and occupants on each Zone of a Dwelling; the Dwelling totals them. Left empty,
   occupants follow the Phius rule, bedrooms + 1 per unit.
5. Choose an Equipment Set for a Dwelling on any of its Zones, or for a Zone in no Dwelling. A Zone in
   a non-residential Building Segment shows a dash: PHX reads its Program's equipment watts there.
6. To assign several Zones at once, check them and choose a Building Segment, Program, Dwelling (one
   shared, one each, none, or an existing one) or Equipment Set in the selection bar. Each choice is
   one Undo step for every checked Zone. Zones of a single dwelling cannot be checked.

A value PH-Composer cannot work out yet reads as an amber **?**; its tooltip names what is
missing. A Zone's alert flag names its findings, such as a Program with equipment watts in a
residential Building Segment. Areas and ventilation follow the unit system (ft² and cfm in IP);
lighting stays in W. Escape closes an open bubble, then clears the checked Zones.

## Edit Programs, Schedules and Equipment Sets

1. Use the **Programs** tab. Its subtabs, **Programs**, **Schedules** and **Equipment Sets**, each show
   one record at a time with a sidebar of the records in this file. The model's default Program and
   Equipment Set are listed under **Default**, the rest under **In this file**; Schedules are grouped by
   type. Choose a record in the sidebar to open it.
2. **+ New** in the sidebar makes a record under a free name and opens its title for renaming. Rename a
   record with the pencil beside its title (Enter applies, Escape cancels), copy it with
   **Duplicate**, and delete it from the **...** menu. Deleting a record that Zones, Building Segments,
   Dwellings or Programs use asks which record takes its place; everything that used it moves to that
   record in the same Undo step. PH-Composer's own residential default Program and default Equipment
   Set carry **Reset to PH-Composer default** in the same menu.
3. A Program shows its users and its people, lighting and equipment at the top, then one card per load:
   Occupancy, Lighting, Ventilation, Electric equipment, Setpoint and Infiltration, then Gas equipment
   and Hot water, which only EnergyPlus reads. A closed card shows its values and Schedule on one line,
   with an amber alert when a value the export needs is missing. Open a card to edit its values on the
   left and choose its Schedules on the right; each change is one Undo step. **+ New Schedule** makes a
   Schedule of the slot's type and names it there.
4. Occupancy, Lighting and Hot water may follow a rule worked out per Dwelling at export (the Phius
   occupancy and lighting rules and the Building America hot water rule). **Use a fixed value** switches
   the load to a value of its own, and **Use the ... rule** switches it back; the lighting rule's
   high-efficacy fraction stays editable.
5. To add a Program from a library file, choose the file in the Programs sidebar's source list and click
   a row. Adding it copies it with its Schedules; a row already in this file shows a check.
6. A Schedule shows its PH form by type: the operating hours and the level while operating and
   otherwise for a fractional or activity Schedule, one value for a temperature Schedule, and for a
   ventilation Schedule its four periods (high, standard, basic and minimum), each hours per day and a
   fraction of the design flow. Each change is one Undo step. A ventilation Schedule's hours must total
   24: while they do not, the total turns amber and nothing is saved; Escape restores the periods. Below
   the form, the 24-hour strip, the days of the week it applies on, its full-load hours and the loads
   that use it. The hourly editor is planned.
7. An Equipment Set lists its devices with their quantity, energy demand (or the Phius rule a rule
   device follows), whether each is in conditioned space and its reference quantity. **Add device**
   opens a form laid out for the device's type, with only the fields that apply, such as a gas
   dryer's gas fields. Click a row, or its pencil, to edit it; the type is fixed once added. Delete
   asks first and names the Dwellings that use the Set. Each change is one Undo step.

Values follow the unit system: people and watts per ft², cfm per person and per ft², and °F in IP.
Hot water flow stays in L/h per m².

## Add Ventilators and choose the Zones they serve

1. Use the **Mechanical** tab. Its subtabs are the systems a model carries, **Ventilation**, **Heat Pumps**,
   **Hot Water**, **Pumps**, **Fans** and **Electric Heating**, and the pills beneath them pick one table of that system. The
   tab remembers the subtab and table you last used on this computer.
2. **+ New Ventilator** asks for a Tag; every other value starts at its default (0.55 Wh/m³, frost
   protection on below -5 °C, in conditioned space). Edit any value in its cell: Enter or leaving the cell
   applies it as one Undo step. Recovery efficiencies are fractions from 0 to 1. Electric efficiency
   reads in Wh/m³, or W/cfm in IP.
3. Click a row's **Serves** cell to choose its Zones. Zones are listed under their Building Segments, and a
   Segment's checkbox takes all of its Zones. A Zone another Ventilator serves says so; assigning it asks
   first and then **Replace and assign** moves it. Zones you uncheck are cleared. Each Zone has one
   Ventilator.
4. **Supply** and **Extract** add up the Zones the Ventilator serves: each Zone's Space rates, or, for a Zone
   on its Program's ventilation, that flow as both. They turn amber when they differ by more than a tenth.
   A dash means the value is not known yet; its tooltip says why.
5. The subsoil heat exchanger and the preheated intake temperature sit behind the chevron at the start of
   each row, blank until you enter them. The chevron is filled while either is set.
6. **Columns** hides Manufacturer, Model and Notes. The palette in the **Serves** header colours each Zone
   in the model by its Ventilator; a Zone with none stays uncoloured. **Duplicate** copies a Ventilator,
   and **Delete** asks which Ventilator takes its place on its Zones, or clears them.

## Add hot water systems, heaters and tanks

1. Use **Mechanical > Hot Water**. Its pills are **Systems**, **Heaters**, **Tanks**, **Pipe Types** and
   **Piping** (see [hot water piping](#draw-hot-water-piping)). A Hot Water System
   is what serves Zones; each Heater and Tank names the System it belongs to.
2. **+ New Hot Water System** asks for a Tag. Enter its **Tap points**, or leave them blank for the piping
   to count them. Click its **Serves** cell to choose its Zones, as for a Ventilator; each Zone has one
   System. The palette in the **Serves** header colours each Zone by its System.
3. **Recirc.** temperature and hours, at the right of the table, are read only. They come from the
   recirculation pipes, and read 60 °C and 24 h, muted, until one is drawn. A **Calculation method** is stored
   with the System;
   the info mark beside it says when the export cannot carry it yet.
4. When two Systems serve one Building Segment, a note under the table says that WUFI-Passive and METr add
   their tanks and heaters together and keep one tap point count.
5. **+ New Hot Water Heater** and **+ New Hot Water Tank** ask for a Tag and the System. Choose another
   System in a row's **System** cell.
6. A Heater's **Type** decides which efficiency values it takes: a performance ratio for an annual heat
   pump, two COPs at two rating temperatures for a monthly one, an energy factor for one inside the
   envelope, and none for an electric heater. The others read as a dash and cannot be typed or pasted
   into. Changing the Type opens a form for the new Type's values and names the values that go.
   **Coverage** is the share of the System's hot water the Heater makes, in percent.
7. A Tank's **Role** (Storage, Buffer or Solar) and Tag decide its **Export slot**: storage Tanks fill
   Tank 1 and Tank 2 in Tag order, a buffer Tank the buffer slot, a solar Tank the solar slot. A Tank with
   no slot left is amber and the export leaves it out. **Capacity** reads in litres, or US gallons in IP.
8. Deleting a System asks which System takes its place on its Zones, Heaters and Tanks. You can clear its
   Zones instead only when no Heater or Tank names it.

## Add pumps

1. Use **Mechanical > Pumps**. Its pill is **Pumps**.
2. **+ New Pump** asks for a Tag. A new pump is one hot water circulation pump in conditioned space, at
   0 W for 8.76 kh a year (the whole year). Choose its **Type** (heating circulation, hot water
   circulation, hot water storage load or other) and enter its **Power** in W and its **Operation** in
   kilohours a year.
3. Its internal heat gains sit behind the row's arrow: the **Utilization factor**, the share of its energy
   that becomes a gain inside the envelope (1 by default), and the **Usage profile**, the season the gain
   lands in. The profile follows the Type (winter for a heating circulation pump, none for a hot water
   pump, whose losses the hot water distribution counts, and all year for other) until you choose one;
   **From type** returns to it. The arrow is filled while the factor is not 1 or a profile is chosen.
4. Click a row's **Serves** cell to choose its Zones, as for a Ventilator. A Zone may have several pumps,
   so assigning one never replaces another. PHX reads a pump through a Room's Spaces, so the Export pane
   warns when a pump serves a Zone with no Spaces.
5. Deleting a pump that serves Zones asks which pump takes its place on them, or clears it from them.

## Add fans

1. Use **Mechanical > Fans**. Its pill is **Fans**.
2. **+ New Fan** asks for a Tag. A new fan is one user-defined exhaust moving 0 m³/h for 0 minutes a year,
   with no Power. Choose its **Type** (kitchen hood, dryer or user-defined) and enter its **Flow** and its
   **Runtime** in minutes a year.
3. Enter its **Power** in W to model its electricity; leave Power blank when you do not. A fan with Power
   exports a second object beside its exhaust: a supportive device drawing that power, so one row gives two
   honeybee-ph objects. The supportive device takes the fan's Quantity, so a row of three hoods draws three times
   its Power.
4. Its electric values sit behind the row's arrow: **In conditioned space** (Yes by default) and the
   **Operation** in kilohours a year its supportive device runs. Leave Operation blank to follow the
   runtime: its empty field shows the value the runtime gives (minutes a year over 60,000). Both export
   only with Power. The arrow is filled while the fan is outside conditioned space or names an Operation.
5. Click a row's **Serves** cell to choose its Zones, as for a Ventilator. A Zone may have several fans,
   so assigning one never replaces another. PHX reads a fan through a Room's Spaces, so the Export pane
   warns when a fan serves a Zone with no Spaces.
6. Deleting a fan that serves Zones asks which fan takes its place on them, or clears it from them.

## Add electric heaters

1. Use **Mechanical > Electric Heating**. Its pill is **Heaters**.
2. **+ New Electric Heater** asks for a Tag. **Coverage** is the share of the heating load the heater
   covers, in percent, and starts at 100%. Coverages are not added up or checked against each other or
   against a heat pump.
3. Click a row's **Serves** cell to choose its Zones, as for a Ventilator. A Zone may have several
   heaters, so assigning one never replaces another; unchecking a Zone takes only this heater off it.
4. Deleting a heater that serves Zones asks which heater takes its place on them, or clears it from them.

## Draw hot water piping

Hot water piping is traced as lines over the model, each line given a Pipe Type and a role, and exported
into the Hot Water System it belongs to. Scripts and assistants reach the same steps through the
[agent guide](AGENT_GUIDE.md#hot-water-piping).

1. Use **Mechanical > Hot Water > Pipe Types**. A **Pipe Type** is one pipe specification kept in the
   model: a **Material** (Copper M, L or K, CPVC CTS SDR, CPVC Sch 40, PEX, PE or PEX CTS SDR), a
   **Diameter** from the eight nominal sizes METr takes, 3/8 in to 2 in, and its **Insulation**: thickness,
   **Conductivity**, a **Reflective** facing and the **Quality** of its installation. **+ New Pipe Type**
   asks for a Tag; the new type is a 1/2 in Copper L pipe with 12.7 mm of reflective insulation at
   0.04 W/(m K). Edit each value in its cell. **Used length** is the drawn length of the pipes using the
   type. A type with insulation and no conductivity cannot export once a pipe uses it; a bare pipe needs
   none. Deleting a type in use asks for another to take its place, or clears it from those pipes.
2. Use the **Piping** pill. **+ New Piping group** asks for the Hot Water System its pipes serve, then adds
   a group at the top of the model and opens it in SketchUp. Draw the pipes inside it with SketchUp's own
   Line tool, snapping to the model. Keep Piping groups outside Zones. A tree (a trunk, its branches and
   their twigs) is drawn in one group; a riser can be drawn once and given a multiplier.
3. Select lines in the open group, then choose a Pipe Type and a role in the bar above the groups:
   **Trunk**, **Branch**, **Twig** or **Recirculation**. A trunk also takes a **Multiplier** (how many
   identical risers it stands for) and **Demand recirculation**; a recirculation pipe takes its **Water
   temperature** and **Hours a day**. **Assign** writes them to the selected lines as one Undo step, and
   **Clear** removes them. **Assign by clicking** does the same as you click or drag across lines in
   SketchUp, one Undo step a gesture, until you click it again or press Escape there.
4. The **Piping groups** table lists each group with its Hot Water System, chosen in place, and its pipe
   count. A group linked to no System, or one a Zone holds, says so.
5. The **Schedule** shows one row per run: the connected lines of one role and Pipe Type. Each branch sits
   under the trunk it touches and each twig under its branch. A row's alert mark lists what keeps it from
   the export, such as a branch that reaches no trunk, each with a **Locate**. Click a row to select its
   lines in SketchUp. **Totals** sum the drawn length by role and by Hot Water System, with each System's
   recirculation temperature and hours. The schedule reads the model when the pill opens and on
   **Refresh**; after you draw or assign it says **Changed since read**.
6. The palette in the schedule's **Role** header colours the pipes in the viewport by role, and the one in
   the Pipe Types **Tag** header by Pipe Type. The legend sums each colour's length.

## Draw ERV ducting

ERV ducting is the two cold runs between each ventilator and the outside, Outdoor air and Exhaust air,
traced as lines over the model and exported into the ventilator's system. It is being built in steps. What
exists now is the Duct Type, available to scripts and assistants through the
[agent guide](AGENT_GUIDE.md#erv-ducting); the panel's Duct Types table, the Ducting groups that hold drawn
lines, assignment and the schedule follow.

A **Duct Type** is one duct specification kept in the model: its **Shape**, Round or Rectangular, with a
**Diameter** for a round duct or a **Width** and **Height** for a rectangular one, and its insulation:
thickness, conductivity and a reflective facing. A new type is a 160 mm round duct with 25.4 mm of
reflective insulation at 0.04 W/(m K). Changing a type's shape asks for the new shape's size. A type with
insulation and no conductivity cannot export once a duct uses it; a bare duct needs none.

## Reuse library definitions

Use **Libraries** to add a file, a folder of files or a connection supplied by a hosted provider.
Copy the definition into your model and edit the local record. PH-Composer keeps its source
attribution. The model continues to use the local copy when the source changes or is offline.
The [library file format](LIBRARY_FILE_FORMAT.md) covers the supported wire kinds and limits.

## Export HBJSON

Run preflight in the **Export** tab. Resolve the blocking findings and run Solve if the
adjacencies need updating. Review warnings about omitted or uncertain geometry. A finding's
**Locate** frames its geometry or opens the tab and record it names; a Program finding opens
**Zones > Programs** at its Zones. A Zone in no Building Segment is left out of the export with its
Faces, Spaces, Edges and windows, and the report names it. A Surface Face paired with a Face of a
left-out Zone blocks the export. When you move a Zone out of every Segment, PH-Composer offers to
make such Faces an Attached zone boundary, in one Undo step. Choose a
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
