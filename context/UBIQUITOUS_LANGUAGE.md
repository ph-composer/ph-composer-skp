# Ubiquitous language

Use these terms in code, schemas, UI text and guides. Planned terms are identified where they
appear. See the [modeling guide](../docs/PRODUCT.md) for the current workflow.

## Product and storage

| Term | Meaning |
| --- | --- |
| PH-Composer | The free, open-source SketchUp extension for authoring Phius passive building models |
| Model | The SKP file carrying the authored building and its local definitions |
| Project | The building job being modeled |
| Model library | Definitions stored in this Model, including intentionally retained unused definitions |
| Library provider | An optional source of definitions to browse and copy, such as a JSON file, a folder or a hosted catalog |
| Library file | A library provider that is one JSON file, or a folder of them, on disk. The same envelope is the connection's wire format |
| Connection | A library provider reached over HTTPS at an address the user types, signed in by none, a static token or device-code approval as the server declares |
| Starter library | A separately distributed CC0 library of generic records |
| Library record | One definition as a provider publishes it, carrying a stable record id from that provider |
| Library kind | A kind of definition a library can carry, such as Materials or Frames, named by its wire kind id. The feature that owns the record kind registers how library rows map to and from its local records; a provider serves kinds and never learns which feature owns them |
| Catalog | The library records one provider serves for one library kind, as read into the open Model's session. Held in memory only and never stored in the SKP |
| Catalog generation | The number identifying one successful read of a catalog. A copy names the generation it was reviewed against and refuses if the catalog has been successfully read again since |
| Bookshelfing | Copying a library record and its needed dependencies into the Model so they remain usable and editable offline. Implemented by the library coordinator's dependency copy: a library Program copies with each Schedule it names, in one Undo step, reusing a local copy of each from the same source ([CONTRACTS](CONTRACTS.md#library-providers-and-catalogs), "Library dependencies") |
| In this file | Sidebar state resolved by source identity: provider kind, library id, record kind and record id. One match reuses the local copy even after rename; multiple matches require explicit resolution. Cross-source reuse follows the same-name/value rule |
| Source attribution | The record of where a definition came from. The SKP owns the editable copy |
| Definition source | The stored form of source attribution: `manual`, `derived` (duplicate or variant of another record), or `library` with the provider and record id |
| Source update review | Proposed per-record comparison of a copy against its provider's current record, with a per-field choice to take the source value, keep the local value or enter another |
| Type | A reusable definition stored in the Model |
| Instance | A particular use, placement, quantity or installed occurrence of a definition |
| Assignment | The relationship between an authored object and the definition or system it uses |
| User data | An authored object's optional `user_data` JSON map for a user's or tool's own data under its own top-level key. Stored, copied and exported where the object has an HBJSON object of its own; never read by a calculation. See the [user data guide](../docs/USER_DATA.md) |
| Record part | A nested object inside a definition record that has its own id and `user_data`, addressed by `part_ids` from the record down: an Assembly's Layers and Layer-Segments, a Window Type's elements |
| Derived object | Data PH-Composer calculates or generates from authored objects, such as thermal-bridge runs, the honeybee schedule rulesets export writes from Schedules, and generated Window geometry. It carries no user data of its own |
| Local override | A proposed explicit deviation from a shared definition; supported fields require the owning interview |
| Display units | The user's SI or IP choice for how the panel shows numbers and reads unsuffixed input. A local preference outside the SKP. It never changes stored values, geometry or SketchUp's own Model units |
| Dimension format | A builder's choice of how lengths appear within the active display units: mm, cm or m in SI; decimal inches, decimal feet, feet and inches, or fractional inches in IP |
| Canonical unit | The fixed SI unit of a stored field, such as millimetres in `thickness_mm` |
| Table layout | A table's saved column visibility, widths and ordering. A local user preference outside the SKP; filter text and expansion are not part of it |
| Agent token | The secret an agent's client presents to PH-Composer's local connection, issued, listed and revoked by the user in the Agent Access window, with the access chosen when it was issued |
| Client profile | One entry PH-Composer sets up in an agent client, Default (`ph-composer`) or named (`ph-composer-<name>`), each reading its own saved Agent token. Not a library Connection |
| Locate | A command that frames the target in the SketchUp view. Selection behavior depends on the operation |

## Geometry units and the honeybee mapping

Use the PH-Composer terms in the interface and the Honeybee names in export mappings.
See [geometry records and occurrence references](CONTRACTS.md#geometry-records-and-occurrence-references).

| Term | Meaning | honeybee object | Note |
| --- | --- | --- | --- |
| Zone | The fundamental geometry unit: one SketchUp Group, at Model root or inside plain wrapper groups and never inside another Zone, carrying envelope faces, Spaces, loads and schedules. A building may be one Zone; a Zone is required before export | `honeybee.room.Room` | honeybee calls this a Room. PH-Composer never uses Room for it, and honeybee's own `Room.zone` text tag is a different thing that PH-Composer does not surface |
| Building-Segment | A Model-owned option that groups Zones. A Zone belongs to at most one Building-Segment, and the Model keeps at least one | honeybee-ph `BldgSegment` | Carries the settings export writes to the `BldgSegment`: Phius certification, airtightness, wind exposure and set points |
| Default Building Segment | The Building-Segment every new Zone joins. Never none: deleting it moves the default to the Segment its Zones moved to, else to the first remaining one | | `default_segment_id` in the Zone option settings |
| No Building Segment | The state of a Zone in no Building-Segment: `building_segment_id` is null. Such a Zone is left out of export | | Export leaves the Zone out with its Faces, Spaces, Edges and Window Units and reports `zone.left_out`; `zone.no_segment` refuses an export in which no Zone is in a Segment |
| Segment heading row | The row that opens each Building-Segment's group of Zones in every Zone view: its name, tags such as Default, a findings flag, its sums in the view's columns, and Settings and Delete. No Building Segment is the last, muted heading | | `features/zones/segment_rows.js`; tags come from `table_views.heading` contributions |
| Building Segment settings | The dialog that edits one Building-Segment's name, colour and default (its General section) and the settings sections other features register, saved in one Undo step | | Each section is a structured extension on the Segment, saved by `ph_composer.zones.save_segment_settings`; sections register with `panel.segmentSettingsSection` |
| Phius certification | The Building Segment settings section for a Segment's Phius building category, certification program, building use, building status and building type. A Segment with none set reads Residential, Phius 2021 CORE, Residential, In planning and New construction | honeybee-ph `BldgSegment.phius_certification` (`PhiusCertification`) | The `ph_composer.certification.segment` extension, read by `ph_composer.certification.segment.get`; values follow the pinned honeybee-ph enums, whose programs stop at Phius 2021 |
| Airtightness | The Building Segment settings section for a Segment's blower-door test result, n50 (air changes per hour at 50 Pa over the net volume) or q50 (m³/h per m² of envelope at 50 Pa), and its wind exposure. With no test result, its Zones keep their Program's infiltration | honeybee `Infiltration.flow_per_exterior_area` on each Room; honeybee-ph `BldgSegment.wind_exposure_type` | The `ph_composer.programs.airtightness` extension, read by `ph_composer.programs.airtightness.get`; export converts the result so PHX reads it back (`features/programs/conversion.rb`) |
| Comfort | The read-only Building Segment settings section showing the heating and cooling set points the Segment's Zones' Programs give, which the export writes to the Segment | honeybee-ph `BldgSegment.set_points` | The `ph_composer.programs.comfort` section in `html/features/programs/occupancy.js`; no payload |
| Mechanical (Building Segment settings) | The Building Segment settings section for whether the Segment has mechanical cooling, its mechanical room temperature and its summer ventilation: the heat recovery bypass and the ventilation system, daytime window and nighttime window air changes. A Segment with none set reads no mechanical cooling, 20 °C, bypass always, no ventilation system rate and no window ventilation | honeybee-ph `BldgSegment.set_points.mechanical_cooling`, `BldgSegment.mech_room_temp`, `BldgSegment.summer_ventilation` (`SummerVentilation`) | The `ph_composer.mechanical.segment` extension, read by `ph_composer.mechanical.segment.get`; the mechanical cooling switch is entered, and the preflight warns `mechanical.segment_cooling_mismatch` when it disagrees with the blended heat pump |
| Program | A Model-owned record of the eight loads a Zone carries: People, Lighting, Electric and Gas equipment, Service hot water, Infiltration, Ventilation and Setpoint, each with its values in honeybee units and its Schedule references. A rule load names a Phius rule that sets its value per Dwelling at export; switching it to a fixed value keeps the rule's inputs | honeybee `ProgramType` | The `ph_composer.programs.program` kind (`pgm_`); exported as one ProgramType, or one per Dwelling for a rule Program (context/CONTRACTS.md, "Program export") |
| Schedule | A Model-owned record shared by id across Programs: its type (Fractional, Activity level, Temperature or Ventilation) and one PH form, operating hours with a value while operating and otherwise, a constant temperature, or the four ventilation periods high, standard, basic and minimum totalling 24 h, plus days per week and weeks per year | honeybee `ScheduleRuleset`, written at export | The `ph_composer.programs.schedule` kind (`sch_`); `ph_composer.programs.schedules.profile` draws its 24-hour profile and full-load hours |
| Equipment Set | A Model-owned record of honeybee-ph devices: each device one of the fourteen `PhEquipment` types, with its quantity, reference quantity, energy values and the type's own fields, edited one device at a time | honeybee-ph `PhEquipment` on Process loads | The `ph_composer.programs.equipment_set` kind (`eqs_`); devices are its parts (`devices[]`), typed by `features/programs/equipment_types.rb` |
| Dwelling | One or more Zones counted as one dwelling unit, or as `units` identical ones; its bedrooms and occupants are its Zones' summed, and occupants with none use the Phius rule, bedrooms + units. A Dwelling with no Equipment Set uses the Model's default Set | honeybee-ph `PhDwellings` on each Room's People | The `ph_composer.programs.dwelling` kind (`dwl_`); Zones name it in their `ph_composer.programs.zone_assignment` |
| Single dwelling | A Building Segment setting, on unless switched off: every Zone in a residential Segment is one Dwelling, named for the Segment, with the residential default; the house's bedrooms, occupants and Equipment Set are the Segment's own settings. A non-residential Segment is never a single dwelling | | `single_dwelling` in the Segment's `ph_composer.programs.segment` payload; no Dwelling record until it is switched off |
| Residential default | PH-Composer's built-in residential Program, after honeybee-ph's Set Residential Program, with its Schedules, and its default Equipment Set of the eight Phius devices. The Model's default Program and Set until another is chosen; reads answer them until a write stores them, after which they are ordinary editable records with Reset to PH-Composer default | | Reserved ids `pgm_PHCDEFAULT01` and `eqs_PHCDEFAULT01`; the `ph_composer.programs.settings` dictionary holds the Model's choice, null for these |
| Rule load | A Program load whose value a rule works out per Dwelling at export: the Phius occupancy and lighting rules, and the Building America hot water rule. **Use a fixed value** switches it to a value of its own and keeps the rule's inputs | | `rule` on the load's values; `ExportPlan` in `features/programs/` works it out |
| Device | One item of an Equipment Set: its type, which fixes its fields, its quantity and energy values. Added, edited and deleted one at a time | honeybee-ph `PhEquipment` | A part of its Equipment Set (`devices[]`), with its own id and `user_data` |
| Zones / Programs view | The third Zone view: each Zone's Program, Dwelling, bedrooms, occupants and Equipment Set, with floor area, iCFA and the peak people, lighting and ventilation the export writes, summed on each Segment heading row | | `ph_composer.programs.zones`, registered on the Zone views host |
| Programs tab | The tab after Zones that edits Programs, Schedules and Equipment Sets one record at a time, each subtab its editor beside the library sidebar | | `html/features/programs/tab.js` and `record_page.js` |
| Segment envelope | The Faces PHX keeps when it merges one Building-Segment's Rooms: every exported Face of its Zones less each Surface Face whose other side is in the same Segment. Airtightness weights an n50 result by its area | | `Faces::ExportProjection.segment_envelope` |
| Level | An optional Model-owned choice for grouping and sorting Zones. A Space inherits its Zone's Level | `Room.story` | |
| Adjacency | A reciprocal pairing of path-qualified face endpoints in different Zones, carrying Zone UUIDs, face persistent ids and solved world-geometry stamps | `Surface` boundary condition while current | Solved on demand, never live; identity and freshness are separate |
| Interior face | A face of a Zone whose other side is another Zone, solved or not | `Surface` when solved, `Adiabatic` when marked To neighbour | Distinct from an envelope face facing Outdoors or Ground |
| To neighbour | The on-screen boundary condition for a face whose other side is not modeled or does not matter: a party wall, a floor over an unmodeled podium | `Adiabatic` | WUFI and METr vocabulary on screen, honeybee's in the stored value (zones packet, Q22) |
| Make Zone independent | What makes a copied Zone editable: the copy gets its own faces and a new identity, pairs copied with it are retired and the Zone it was copied from keeps its identity, faces and pairs, as one Undo step. Offered on the copy's row and in its context menu; a Zone inside a component or a still-shared parent Group says what to do first | | `ph_composer.zones.make_independent` |
| Repair Zone identity | The script-level repair for a copied Zone whose storage is already its own: the copy and its faces receive new identities, pairs copied with it are retired and the original's pairs are kept, as one Undo step. A plain copy that shares storage is refused until the user runs SketchUp's Make Unique | | `ph_composer.zones.repair_identity` |
| Repair split Face identities | The explicit repair after a native split copies one face identity onto several pieces: a provable stored path, or the user's choice, keeps the old identity and the other pieces receive new ones | | `ph_composer.zones.repair_split_face`; the Repair menu item |
| Restore Zone | A limited repair regrouping eligible surviving stamped contents and recovering Zone id, Building-Segment and Level; other Zone fields are unavailable and disclosed | | Native Undo is the full recovery route while available; no surviving stamps means no Restore Zone |
| Closed Zone | A Zone whose group is a manifold solid | Required by EnergyPlus only | `Group#manifold?` |
| Solve adjacencies | The explicit action that pairs interior faces across Zones, splits them to match, and records the Adjacencies as one Undo step | | Validation offers it again whenever an Adjacency is stale |
| Stale adjacency | An Adjacency whose reciprocal endpoints or world geometry no longer match the solved state | | Re-solving replaces or retires it; unresolved Surface references are omitted from export with findings |

## Envelope

Face types and boundary conditions follow Honeybee. A Zone owns its Face assignments.

| Term | Meaning |
| --- | --- |
| Envelope face | A SketchUp Face that carries a PH-Composer envelope classification record |
| Face type | The honeybee face type of an envelope face: `Wall`, `RoofCeiling`, `Floor` or `AirBoundary` |
| Boundary condition | What is on the other side of an envelope face: honeybee's `Outdoors`, `Ground`, `Adiabatic`, `Surface`, and honeybee-ph's `PhAdditionalZone`. Shown as Outdoors, Ground, To neighbour, Surface (set only by Solve adjacencies) and Attached zone |
| Attached zone | A named unconditioned space outside the envelope (garage, attic, crawlspace) with one temperature reduction factor, initially 0.95. Zones owns the record kind and assigns it as a Face boundary condition. Maps to honeybee-ph `PhAdditionalZone` |
| Ground depth | A per-Zone height, default the Model's z=0, below which the Classify tool suggests Ground |
| Face record | The classification record on one face: face type, boundary condition, assembly id and Zone stamp. A retired pair can leave the boundary condition absent. Payload preservation and endpoint validity are distinct requirements, subject to native-host acceptance |
| Face assignment | Writing a Face record through the context menu, Classify tool, Geometry view or Suggest classification |
| Classify tool | The modal viewport tool that writes face records: palette in the panel, click, drag, Shift-click for connected coplanar faces, one Undo step per gesture |
| Suggested classification | Face type and boundary proposed from geometry. Suggest classification fills eligible unclassified Faces and can run during Make Zone |
| Unclassified face | A Zone Face without a classification record. Export preflight reports it as a blocker |
| Incomplete face | A Face record with a missing or invalid required value or reference. Export preflight reports the finding |
| Colour-by | The shared visualization component: one viewport overlay, one panel legend with counts, Locate and Isolate (leave every other row in its plain SketchUp colour), and one viewport HUD legend drawn while a mode is active. Features register modes; it is the fourth contribution seam. Never writes a SketchUp material |
| Colour-by mode | One registered way of colouring the model: a name, an entity kind (a face, a Zone, a Volume or another kind a feature names), a colour function, a label and optionally derived geometry such as the Volume preview. A readout, such as Show Spaces or Selection totals, registers separately and does not depend on the active mode. Face type, boundary condition and assembly come from face assignment; Zone, Building-Segment and Level from the zones packet |
| HUD legend | The compact text legend the Colour-by overlay draws in the upper left of the viewport while a mode is active, so a screenshot carries its own key |
| Classification overlay | Colour-by in a Face mode, such as face type, boundary condition or Assembly |
| Geometry view | The Zones screen's view of each Zone's Faces and the Zone's own Level and Ground depth, under the tab labelled Geometry |
| Faces table | The panel inventory of face records with editable type, boundary condition and assembly cells, area, state and Locate |
| Material | Physical and product properties used by assembly layers. METr's own screen word. Maps to honeybee `EnergyMaterial`. Distinct from SketchUp display materials |
| Input form | One way a datasheet states a value, chosen beside the field that takes it: R per inch or a conductivity unit for a Material's conductivity. The Model stores W/(m K) whichever form is entered |
| Material category | A preset classification shown as a chip. The Material display colour is a separate field |
| Material variant | A separately named Material with independent properties, created through Duplicate Material |
| Assembly | A reusable construction definition of ordered layers. METr's own screen word. Maps to honeybee `OpaqueConstruction` |
| Ventilated cladding | An Assembly's exterior choice. It is stored as honeybee's Outdoors plus the Assembly's ventilated flag, which sets the exterior surface film; construction resistance does not change |
| Layer | A position in an assembly owning thickness and containing one or more Layer-Segments. Exports as one honeybee `EnergyMaterial` |
| Layer-Segment | One side-by-side strip of a Layer: a Material and a width. Always written with its qualifier, as Building-Segment is. Exports as one column of the layer's honeybee-ph `PhDivisionGrid` |
| Assembly usage | The set of envelope faces assigned to a Model-library assembly, measured by a scan and reported as of the scan time |
| Thermal Bridge Type | A reusable junction detail stored in the Model: a name, one psi-value, a group, a colour and a link to the psi-value calculation report. A different psi-value is a different type. Maps to the psi-value and group of honeybee-ph's `PhThermalBridge` |
| Thermal bridge | A run of assigned edges with a measured length and the type's psi-value. HBJSON carries it as a `PhThermalBridge` on the Zone's Building-Segment |
| Thermal bridge assignment | A record on a SketchUp Edge naming its Thermal Bridge Type and quantity. Copies and splits carry it. Deleting the Edge removes the record |
| Run | Connected assigned edges with the same Zone, type and quantity, ending at a free end or at a junction of three or more. A closed loop is one run. Derived each time the Model is read, never stored |
| Shading mark | The record that says a Face, Group or ComponentInstance is shading. It carries no values and no id |
| Shading Face | A Face that carries the shading mark, or sits at any depth inside a marked Group or ComponentInstance with no Zone or claimed entity between. It leaves its Zone's envelope and is meant to export as one orphaned honeybee `Shade` per occurrence |
| Shading component | The Shading Faces that export under one name, derived from the nearest named container. One component in WUFI-Passive and METr |
| Thermal bridge group | Ambient, Perimeter or Basement floor, METr's words for its three groups. Stored as honeybee-ph's `15-Ambient`, `16-Perimeter` and `17-FS/BC`; shown in METr's words |

## Windows

| Term | Meaning |
| --- | --- |
| Frame | A reusable head, jamb, sill or mullion profile with its product properties. Each glazed element references its side profiles |
| Glazing | A reusable glazing definition with its product properties |
| Psi-Install Type | A reusable installation-junction definition assigned to Window Type perimeter edges. Unset edges visibly inherit the Model default: the Psi-Install Type the user chose, or otherwise the Model's own value, which starts at 0.04 W/mK and is a setting, not a library record. It is an authoring layer over the Frame, so one Frame product serves every wall it is installed in without a copy per wall. On export its value is written to that side of the frame, honeybee-ph's `PhWindowFrameElement.psi_install` |
| Window Type | A reusable exact-size and layout configuration defined by size, glazing, frames, operation and handedness, and perimeter Psi-Install Type assignments. Installation differences use explicit named variants; placements follow their type with no per-instance overrides |
| Element | One cell of a Window Type's layout, possibly merged across rows or columns. A glazed element names a Glazing, a Frame and a Psi-Install Type for each of its four sides, and an operation, any of which may still be unset (an unset install edge inherits the Model default); an empty element is an Empty panel |
| Window unit | One placed use of a Window Type: an instance of the type's flat component, which PH-Composer generates with one face per glazed element, glued to and cutting an envelope face. Each unit has its own identity, and a copied unit receives its own the next time the feature changes the Model |
| Install depth | The reveal depth from the wall's outer surface to the glass. A model default with a Window Type override. Exports to honeybee-ph `install_depth` |
| Window occurrence | A placed window reached through its full SketchUp parent path. Repeated parents expose the same child through different occurrences, and its stored attributes are not independent per occurrence. Independent edits require explicit parent uniqueness; PH-Composer never makes a parent unique automatically |
| Primary definition | The one generated SketchUp component definition a Window Type's Units use. Make Unique creates a detached copy that the Type no longer updates; Reset to type puts a Unit back on its Type's primary definition, regenerating that definition from the Type |
| Window anchor | The fixed point for placement and resize, named by row and column on the opening: `sill_left`, `sill_center`, `sill_right`, `center_left`, `center`, `center_right`, `head_left`, `head_center`, `head_right`. Sill center is the default |
| Empty panel | A layout cell representing excluded wall area. Retained for layout editing and excluded from window thermal contributions |
| Install edge source | Where one element edge's installation value comes from: `explicit`, `default`, `derived_zero` (an edge shared with a neighbouring element), `unsupported_partial`, `dangling` or `missing` |

## Spaces

| Term | Meaning |
| --- | --- |
| Space | One unique SketchUp Group hosted in a Zone through the Zone reference on its record, containing one or more Volumes and Space-level data: iCFA and ventilation airflows. Maps to a honeybee-ph `Space` on its Zone's Room. Do not call it Room in product copy, and do not confuse it with honeybee's Room, which is a Zone |
| Volume | A protected structural Group directly inside a Space, holding one logical Space Floor: Faces joined by shared Edges. Create Space and Add New Volume to Space make one Volume per joined set; Faces meeting only at a corner are separate |
| Space Floor | Logical grouping of Floor Segments in a Volume; not another SketchUp Group |
| Floor surface | The Face or Faces drawn to define a Space's floor. Create Space turns each one into a Floor Segment. Do not call it an outline in product copy |
| Floor Segment | A Face inside a Volume marked as floor area, with an identity, weighting factor and net area factor. Maps to honeybee-ph `SpaceFloorSegment` |
| Weighting factor | The share of a Floor Segment's area that counts toward iCFA, a number from 0 to 1 (honeybee-ph's `weighting_factor`): 1 counts it whole, 0 not at all. What counts is the user's to decide from the Phius rule; nothing enforces it |
| Net area factor | The share of a Floor Segment's area that counts toward net volume, default 1 |
| Average clear ceiling height | The one height a Volume carries. Net volume is net floor area times this height, as honeybee-ph's `SpaceVolume` computes it |
| Volume preview | The overlay extrusion of a Volume's Floor Segments by its height. Drawn, never modeled |
| Height from solid | The helper that sets a Volume's height from a closed group the user drew: the group's volume divided by the Volume's net floor area |
| Set Height | The viewport tool that sets one Volume's height. It starts with a selected Volume, or a Space's one Volume, already picked; a Space with several Volumes waits for a click on one. Then drag the top or type a value in the measurements box |
| Add New Volume to Space | The context-menu item, offered on loose Faces at an open Space's root in place of Create Space, that makes them the Space's next Volumes in one Undo step, with no dialog |
| Delete Volume | The context-menu item, offered on one Volume selected in an open Space, and the Volume row's Delete in the Spaces view, that erase the Volume with its floor Faces in one Undo step. For a Space's only Volume both offer Delete Space instead. Remove Volume, a scripting operation, keeps the Faces |
| Edit Floor Surface | The context-menu item that opens a selected Volume, or a Space's one Volume, unprotected, as Enter does in the Spaces view |
| Set Weighting Factor | The context-menu submenu that sets one weighting factor on every Floor Segment the selection holds: a Floor Segment Face in an open Volume, each Floor Segment of a Volume, or each one in a Space's Volumes, in one Undo step |
| Space label | Viewport text at a Space's reference point, as `101 Living \| iCFA 2,083 ft² \| Vol: 20,831 ft³`. Its values are whole numbers. iCFA and net volume show unless turned off; supply and extract, shown on request, follow as `\| Sup 60 cfm / Ext 60 cfm` |
| Selection totals | The HUD readout of summed iCFA, net volume and airflows for the selected Spaces |
| Airflow balance | Each Zone row of the Spaces view: its Spaces' supply, extract and transfer sums. A By Program Zone shows a dash. Nothing compares supply with extract per Zone: balance is per ventilator, on the Ventilators table of the Mechanical tab |
| Balance by ventilator | A Ventilator's supply and extract, summed over the Zones the export writes it to: a Zone's Spaces' rates, or a By Program Zone's Program flow as both. Out of balance when the two differ by more than a tenth of the larger |
| Move Space to Zone | The action that hosts one Space in another Zone by writing the Zone's id on the Space record. The Space Group stays where it stands |
| Mark floor | The Spaces tool that marks a face inside a Volume as a Floor Segment with a weighting factor, started from the Weighting factor column menu. A separate tool beside Classify, not a mode of it |
| Make independent | The repair for a copied Space, Volume or Floor Segment: the copy and everything inside it receive new identities, in one Undo step. Resolve shared identities before export |
| iCFA | Interior conditioned floor area. PH-Composer sums weighted Floor Segment areas for this quantity |
| Net volume | The sum of Volume net floor areas multiplied by their respective average clear ceiling heights |
| Space default height | Explicit Space value copied to new Volumes; not inferred from floor geometry |
| Floor level | Shown on a Space and read from its Zone's Level; see Level above. Not editable on the Space. A blank value is shown as Unassigned |
| Space Type | A reusable Space definition; labels, defaults and inheritance await their interview |
| Authoring context | The active Space or Volume editing path that determines structural ownership |
| Reconciliation | Updating PH-Composer structure and protection after external geometry changes |
| Volume protection | Contextual locking that prevents independent Volume movement outside its edit context |
| Supply, Extract and Transfer airflow | Separate optional Space inputs, stored so that unset is different from explicitly zero. Whether they apply is the Zone's airflow mode: see By Program and Detailed airflows |
| By Program | A Zone's airflow mode while none of its Spaces has a rate: every Space takes its floor-area share of the Zone's Program ventilation, with the Program's schedule. Its airflow cells read By Program and its sums a dash. Stored as `by_program` |
| Detailed airflows | A Zone's airflow mode once any of its Spaces has a rate: every Space in it exports its own supply, extract and transfer, a blank counting as 0, and none takes a Program share. **From Program** clears every rate in the Zone and returns it to By Program. Stored as `detailed` |
| Ventilation assignment | Relationship from a Space to serving ventilation equipment |

## Site and climate

Shipped in Phase 4 (Climate). The hourly weather file and its peak-load gate are deferred; their
terms are at the end, marked planned.

| Term | Meaning |
| --- | --- |
| Site location | The Model's latitude, longitude and elevation, set together, with an optional climate zone (stored as the WUFI-Passive code) and an optional typed offset from UTC. The site is set when all three of latitude, longitude and elevation are present. Set in Set Location by typing, by a click on the outline map, or from SketchUp's geolocation, which fills latitude and longitude only |
| Climate data folder | A per-computer setting, kept in PH-Composer's settings file on this computer: a folder of climate files the user is licensed to use, named by its dataset name, read where it is and never copied into a Model. Listed, added, renamed, located and removed in Climate Data on This Computer |
| Dataset | The name the user gives a climate data folder. The picker shows one dataset at a time; a station's source is matched by station name, state and checksum across every folder, not by dataset name |
| Settings file | PH-Composer's own per-computer file, outside SketchUp's versioned folders, with one section per feature. Climate's section holds the climate data folders. Never in a Model or HBJSON |
| Station | One location in a climate data folder, read from one Phius station file. The Model keeps the station's coordinates for the Phius limit check |
| Attach and Replace | Attach copies a station's values into a Model with no climate, with an as-read copy, so edited values show and Restore Original Values works on any computer. Replace swaps the Model's climate for another station in one Undo step. Both are refused with no site |
| Phius climate data | The climate a Model holds from a Phius station, or values typed by hand in the same grid: monthly temperatures and radiation and three peak-load cases (Heating 1, Heating 2, Cooling). Complete when the station elevation, daily swing, wind speed, all 96 monthly values and each case's air temperature and five radiation values are present; Incomplete otherwise |
| Climate | The Model's one climate record: monthly and peak-load values, the as-read copy of a station's file, and provenance in honeybee-ph's shape. It remains readable without its source file or folder, and holds no file location |
| Enter Values by Hand, Edit Values | The one values editor: Enter Values by Hand types a climate into a Model with none; Edit Values changes the Model's climate. One paste of the eight series rows fills the grid |
| Edited value | A value of a station's climate that differs from its as-read copy. Marked in the pane and listed in the Export report; Restore Original Values copies the file's values back. Wind speed is never an edited value |
| Source status | Whether the attached station's file is on this computer: Source found, Source changed (the file differs from the as-read copy; Update from File offers it) or Not on this computer. Read each time; the Model reads in full in every case |
| Phius limit check | Whether the station is within 50 miles and 400 feet of the site, Phius's limits for a climate dataset. Pass, Fail (shown as Outside Phius limits), or Not checked with no site or a climate typed without coordinates. Worked out each time, never stored |
| Design temperatures | The typed ASHRAE 99% heating and 1% cooling dry-bulb temperatures for the site, in °C, with an optional source note. Not set, Incomplete (one of the two) or Set; heating at or above cooling saves with a warning. Kept in the Model only |
| Source card | A card in a tab's sidebar naming one source of data with its state chip: on the Climate tab, Site location, Phius climate data, Hourly weather file (planned) and Design temperatures |
| Outline map | The world map shipped with the extension: country borders, and the state and province borders of the United States and Canada; no tiles and no network. Used in Set Location and the station picker |
| Hourly weather file | Planned. A second climate source, an annual EPW from which honeybee-ph derives a preliminary monthly climate. Shown on the Climate tab as Planned and inert |
| EPW-derived monthly climate | Planned. Preliminary monthly climate produced by honeybee-ph from a user-selected annual EPW |
| Monthly-demand ready | Planned. The climate has the complete monthly values required by preliminary demand calculations and overlays |
| METr-climate ready | Planned. The climate has both monthly values and the user-supplied peak-load cases required by the planned METr export |

## Systems terminology for planned features

| Term | Meaning |
| --- | --- |
| Equipment | Model-local records of the ventilators, hot water systems, heat pumps, heaters, pumps and fans a Phius model needs. Appliances and Phius devices are Equipment Sets instead. One record per item with a quantity; there is no separate product definition, except heat pumps, which separate an equipment model from its installed units. An item serves one or more Zones. Shown on the Mechanical tab |
| Mechanical tab | The primary tab after Thermal Bridges: a subtab per system (Ventilation, Heat Pumps, Hot Water, Pumps, Fans and Electric Heating) and, beneath it, a pill row picking one table of that system (Ventilators, later Ducting; Systems, Heaters, Tanks, Pipe Types and Piping; Pumps; Fans; Heaters) |
| Serves | Which Zones an equipment item serves. Shown as Zone chips on the item's row; the Zone picker chooses them, grouped by Building Segment |
| Tag | An equipment item's name, as its tables show it |
| Hot Water System | The hot water record that serves Zones, one per Zone, with its tap points. Exported as one honeybee-ph hot water system per served Room, all under the System's id |
| Hot Water Heater, Hot Water Tank | Their own rows, each naming its Hot Water System. A Heater's variant, shown as its **Type** (Electric, Heat pump · annual, Heat pump · monthly, Heat pump · inside), picks its efficiency values: a performance ratio, two COPs at two rating temperatures, or an energy factor; the others are not used. Its **Coverage** is the share of its System's hot water it makes, shown in percent. A Tank's role (Storage, Buffer, Solar) picks its tank slot; its **Type** is honeybee-ph's tank type (No storage tank, Hot water and heating, Hot water only) |
| Tank slot | One of honeybee-ph's four places for a System's tanks: `tank_1` and `tank_2` for storage Tanks in name order, `tank_buffer`, `tank_solar`. Shown as a Tank's **Export slot** (Tank 1, Tank 2, Buffer tank, Solar tank). A Tank with no free slot of its role is unslotted ("No slot left") and left out of the export |
| Recirculation | A Hot Water System's recirculation temperature and hours per day, read only: honeybee-ph works them out from the recirculation piping and gives 60 °C and 24 h while there is none |
| Piping calculation method | How a Hot Water System's distribution losses are worked out, one of PHX's four: Individual pipes (simplified), Hot water calculator (simplified), Piping per unit, Piping per floor. Stored, and exported once honeybee-ph carries a field for it |
| Pooled hot water | Two or more served Hot Water Systems in one Building Segment. WUFI-Passive and METr add their tanks and heaters together and keep one tap point count; a note, not an error |
| Heat Pump Outdoor Equipment, Heat Pump Indoor Equipment | The outdoor and indoor heat pump models, shown as Equipment · Outdoor and Equipment · Indoor. An outdoor model holds the Phius estimator's inputs (capacities at 17 °F, 47 °F and 95 °F, a COP pair or an HSPF, an EER and SEER or an IEER) and may name its paired indoor model; an indoor model is identity only |
| Heat Pump Outdoor Unit, Heat Pump Indoor Unit | Installed units, shown as Units · Outdoor and Units · Indoor. An outdoor unit installs an outdoor model; an indoor unit installs an indoor model on an outdoor unit and serves Zones, several to a Zone |
| Pump | An auxiliary pump, one record serving any number of Zones, several to a Zone, shown in Pumps › Pumps. Its **Type** is a heating circulation, hot water circulation (the default), hot water storage load or other pump; its power in W runs for its **Operation** in kilohours a year. Its **internal heat gains** sit behind the row's disclosure: the **utilization factor**, the share of its energy that becomes a gain (1.0 by default), and the **usage profile**, the season the gain lands in (all year, winter, summer or none), which follows the Type until one is chosen. Exported as one honeybee-ph supportive device per served Room, all under the pump's id; PHX reads it through a Room's Spaces |
| Fan | An exhaust fan, one record serving any number of Zones, several to a Zone, shown in Fans › Fans. Its **Type** is a kitchen hood, a dryer or a user-defined exhaust (the default); it exhausts its **Flow** for its **Runtime** in minutes a year. Its **Power** in W is optional: blank means its electricity is not modelled. Its **electric values** sit behind the row's disclosure: whether it is **in conditioned space** (yes by default), and an **Operation** in kilohours a year that, blank, follows the runtime (minutes over 60,000). Exported as one honeybee-ph exhaust ventilator per served Room and, with Power, a linked supportive device beside it, both under the fan's id; PHX reads both through a Room's Spaces |
| Electric Heater | Direct electric resistance heating, one record serving any number of Zones, several to a Zone, shown in Electric Heating › Heaters. Its **Coverage** is the share of the heating load it covers, shown in percent, 100% by default; coverages are not added up or checked. Exported as one honeybee-ph direct electric heating system per served Room, all under the heater's id |
| Blended heat pump | The one air-source heat pump exported for each Building Segment, on every Room an indoor unit serves, computed by the Phius Heat Pump Performance Estimator's method from the outdoor models whose units serve the Segment's Zones. Read-only in the Blended result pill |
| Pipe Type | A named hot water pipe specification kept in the Model: a **Material** (honeybee-ph's eight, Copper M to PEX CTS SDR; Copper L by default), a **Diameter** from METr's eight nominal sizes, 3/8 in to 2 in (1/2 in by default), shown by its inch size in both unit systems, and its **Insulation**: thickness, conductivity, reflective facing and quality (None, Moderate or Good). One specification serves every role; a pipe's role, water temperature and hours are not on it. Not a library kind |
| Pipe | One drawn SketchUp line inside a Piping group that carries a Pipe Type and a Role. Lines outside a Piping group are never Pipes |
| Line group | A Piping group or a Ducting group: a SketchUp group outside every Zone that holds drawn lines and links to one record. Its shared mechanics are the foundation's `line_groups/` package; the words a user sees are each feature's |
| Piping group | A SketchUp group at the Model root, or in a plain wrapper, never inside a Zone, that holds drawn Pipes and is linked to one Hot Water System. A System may have several |
| Role | What a Pipe does in its System: **Trunk**, **Branch**, **Twig** or **Recirculation**. Connected Pipes with one Role, Pipe Type and role values in one Piping group form one run; a Branch hangs from the Trunk it touches and a Twig from the Branch it touches, so a tree lives in one Piping group. Recirculation is summed per System, with no tree |
| Twig | The Role of a fixture run, the last pipe to a tap, as METr names it. honeybee-ph calls it a fixture |
| Pipe-Segment | honeybee-ph's pipe segment, one per Pipe at export, carrying the Pipe Type's values and the line as its geometry. Always written with its qualifier, as Building-Segment is |
| Duct Type | A named ventilation duct specification kept in the Model: a **Shape**, Round (the default) or Rectangular, with a **Diameter** for Round (160 mm by default) or a **Width** and **Height** for Rectangular, never both, and its **Insulation**: thickness, conductivity and reflective facing. A duct's direction and length are not on it. Not a library kind |
| Duct | One drawn SketchUp line inside a Ducting group that carries a Duct Type, a Direction and a quantity. Only the two cold runs between a ventilator and the outside are drawn |
| Ducting group | A SketchUp group at the Model root, or in a plain wrapper, never inside a Zone, that holds drawn Ducts and is linked to one Ventilator. A copy keeps its Ventilator |
| Direction | Which cold run a Duct belongs to: **Outdoor air** or **Exhaust air**. honeybee-ph's `duct_type` 1 (supply) and 2 (exhaust); "supply" is not used, since room supply air is another duct |
| Outdoor air | The Direction of the intake run, from the outside to the ventilator |
| Exhaust air | The Direction of the discharge run, from the ventilator to the outside |
| Duct run | The Ducts of one Ducting group placement with one Direction, one Duct Type and one quantity, whether they touch or not. A run of quantity N exports as N duct elements |
| Duct-Segment | honeybee-ph's duct segment, one per Duct at export, carrying the Duct Type's values in metres and the line as its geometry. Always written with its qualifier, as Pipe-Segment is |

## Export

| Term | Meaning |
| --- | --- |
| Export | Write canonical HBJSON and its companion report |
| HBJSON | Honeybee model serialization. The canonical artifact carries the supported honeybee-ph data |
| Exporter | A consumer that writes a downstream format from HBJSON. The planned METr exporter uses PHX |
| METr model | The WUFI-shaped document produced by the planned PHX export path |
| Export report | Human-readable account of emitted content, omissions, approximations and failures |
| Model validation | Checks of Model integrity and supported export inputs |
| Export contributor | A feature's registration with the export run: what it prepares, which contract section it supplies, which result fields it declares and renders |
| Export preflight | The checks the Export tab runs before writing: each feature's findings, blocking or not. A finding's **Locate** frames its geometry in the view, or opens the tab and record it names |
| Left out | Not written to the HBJSON and named in the report: a Zone in no Building-Segment with its Faces, Spaces, Edges and Window Units, or an empty Building-Segment |

## Evidence and handoff

| Term | Meaning |
| --- | --- |
| Linked file | Optional association from a record to external evidence bytes |
| Datasheet / Photo | Roles for optional external evidence linked from a definition |
| Folder root | Proposed shared logical location resolved to each user's local filesystem |
| Relink | Repair an evidence location by choosing the file it should point to |
| Transmission package | Proposed fixed handoff of Model artifacts and selected evidence, distinct from ordinary Export |

## Delivery terminology

| Term | Meaning |
| --- | --- |
| Feature interview | Paced product discovery; seed stories become agreed only through recorded answers |
| Delivery phase | An approved unit of implementation after discovery |
| Host gate | Real-SketchUp verification required in addition to offline tests |
| Release Gate A | Whole-candidate proof and the explicit public-distribution decision |
| Contribution seam | A registered entry point for a feature, provider, exporter, tool or view contribution |

## Relationships to preserve

A Zone hosts Spaces and contains envelope faces; a Space contains Volumes; each Volume directly contains
Floor Segments. A Space is in a Zone because its record names that Zone, wherever its Group or its floors
sit in the scene, and nothing tests geometric containment. A Space cannot span Zones. A Floor Segment is never the same face as an envelope
Floor. A valid Space has at least one Volume and a valid Volume at least one Floor
Segment, all joined by shared Edges. Empty structures are visible recovery states, and a Volume whose Floor
Segments come apart is a warning that does not block export.

Layer thickness is independent of shared material conductivity, density and specific heat.
Different layer thicknesses do not create different material records.

A given material has one record in the Model. Properties and datasheet references are shared
across its assembly uses. Installation photo collections belong to a material within an Assembly
definition and are shared across faces using that assembly.

The SKP owns local definitions and assignments. Imported and hand-entered records have the same
local editing rights. Renaming must not sever references. Shared edits, duplication, delete-in-use
and cross-Model copying are decisions to settle per feature.

A definition has one identity across the Model and the export. Duplicate Material creates a new
identity with a derived-from note. Datasheet links copy only by explicit choice, off by default.

Linked PDFs and photos stay in user-managed folders. The SKP holds the building data and the references.
