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
| Bookshelfing | Copying a library record and its needed dependencies into the Model so they remain usable and editable offline |
| In this file | Sidebar state resolved by source identity: provider kind, library id, record kind and record id. One match reuses the local copy even after rename; multiple matches require explicit resolution. Cross-source reuse follows the same-name/value rule |
| Source attribution | The record of where a definition came from. The SKP owns the editable copy |
| Definition source | The stored form of source attribution: `manual`, `derived` (duplicate or variant of another record), or `library` with the provider and record id |
| Source update review | Proposed per-record comparison of a copy against its provider's current record, with a per-field choice to take the source value, keep the local value or enter another |
| Type | A reusable definition stored in the Model |
| Instance | A particular use, placement, quantity or installed occurrence of a definition |
| Assignment | The relationship between an authored object and the definition or system it uses |
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
| Building-Segment | A Model-owned option that groups Zones. Every Zone belongs to one Building-Segment | honeybee-ph `BldgSegment` | Supplies the grouping for the planned METr handoff |
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
| Geometry view | The Zones screen's view of each Zone's Faces and the Zone's own Building Segment and Level, under the tab labelled Geometry |
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
| Space | One unique SketchUp Group hosted in a Zone through the Zone reference on its record, containing one or more Volumes and Space-level data: iCFA, ventilation airflows, occupancy. Maps to a honeybee-ph `Space` on its Zone's Room. Do not call it Room in product copy, and do not confuse it with honeybee's Room, which is a Zone |
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
| Airflow balance | Each Zone row of the Spaces view: its Spaces' supply, extract and transfer sums. A Zone holding a Space that inherits its airflow shows a dash. Nothing compares supply with extract per Zone: balance is per ventilator, and that check belongs to the planned Zones / Ventilation view |
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
| Supply, Extract and Transfer airflow | Separate optional Space inputs, stored so that unset is different from explicitly zero. When all three are unset the Zone's ventilation load applies. When any one is set the Space is user-specified: its values override the Zone's load and an unset rate counts as zero |
| Ventilation assignment | Relationship from a Space to serving ventilation equipment |

## Systems and climate terminology for planned features

| Term | Meaning |
| --- | --- |
| Equipment | Model-local records of the ventilators, hot water systems, heat pumps, heaters, pumps, fans and appliances a Phius model needs. One record per item with a quantity; there is no separate product definition. An item serves one or more Zones |
| Piping / Ducting | Modeled runs, their segments and the systems they serve |

### Site and climate

| Term | Meaning |
| --- | --- |
| Climate snapshot | The model-owned monthly and, when supplied, peak-load climate values plus provenance. It remains readable without its source file or provider |
| EPW-derived monthly climate | Preliminary monthly climate produced by honeybee-ph from a user-selected annual EPW |
| Monthly-demand ready | The climate has the complete monthly values required by preliminary demand calculations and overlays |
| METr-climate ready | The climate has both monthly values and the user-supplied peak-load cases required by the planned METr export |

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
