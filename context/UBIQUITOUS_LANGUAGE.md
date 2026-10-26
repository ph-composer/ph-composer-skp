# Ubiquitous language

**DATE:** 2026-09-30

Use these terms in product docs, interviews, the panel and code. A definition here is product
vocabulary. It does not claim that the corresponding editor exists. Terms carried over from the
predecessor, PH-Navigator for SketchUp, keep their meaning unless the row says otherwise; the
predecessor's designPH terms (adoption, push, origin row, designPH difference, TFA) are retired.

## Product and storage

| Term | Meaning |
| --- | --- |
| PH-Composer | The free, open-source SketchUp extension for authoring Phius passive building models |
| Predecessor | PH-Navigator for SketchUp, the designPH companion this project grew out of. Prior art and evidence, never a dependency |
| Model | The SKP file carrying the authored building and its local definitions |
| Project | The real building job. It does not imply a hosted project record |
| Model library | Definitions stored in this Model, including intentionally retained unused definitions |
| Library provider | An outside source of definitions the user can browse and copy from: a folder of files on disk, a firm's server, a vendor catalog. No provider is privileged and none is required |
| Library file | A library provider that is one JSON file, or a folder of them, on disk. The same envelope is the connection's wire format |
| Connection | A library provider reached over HTTPS at an address the user types, signed in by none, a static token or device-code approval as the server declares |
| Starter library | A small CC0 library file of generic records, downloaded separately. Never inside the extension |
| Library record | One definition as a provider publishes it, carrying a stable record id from that provider |
| Library kind | A kind of definition a library can carry, such as Materials or Frames, named by its wire kind id. The feature that owns the record kind registers how library rows map to and from its local records; a provider serves kinds and never learns which feature owns them |
| Catalog | The library records one provider serves for one library kind, as read into the open Model's session. Held in memory only and never stored in the SKP |
| Catalog generation | The number identifying one successful read of a catalog. A copy names the generation it was reviewed against and refuses if the catalog has been successfully read again since |
| Bookshelfing | Copying a library record and its needed dependencies into the Model so they remain usable and editable offline |
| In this file | Sidebar state resolved by source identity: provider kind, library id, record kind and record id. One match reuses the local copy even after rename; multiple matches require explicit resolution. Cross-source reuse follows the same-name/value rule |
| Source attribution | Where a Model-library record came from: hand entry, a named library provider, or another record in this Model. Recorded on the record. It is not a live dependency and grants the provider no authority |
| Definition source | The stored form of source attribution: `manual`, `derived` (duplicate or variant of another record), or `library` with the provider and record id |
| Source update review | Proposed per-record comparison of a copy against its provider's current record, with a per-field choice to take the source value, keep the local value or enter another |
| Type | A reusable definition stored in the Model |
| Instance | A particular use, placement, quantity or installed occurrence of a definition |
| Assignment | The relationship between an authored object and the definition or system it uses |
| Local override | A proposed explicit deviation from a shared definition; supported fields require the owning interview |
| Display units | The user's SI or IP choice for how the panel shows numbers and reads unsuffixed input. A local preference outside the SKP. It never changes stored values, geometry or SketchUp's own Model units |
| Dimension format | A builder's choice of how lengths appear within the active display units: mm, cm or m in SI; decimal inches, decimal feet, feet and inches, or fractional inches in IP |
| Canonical unit | The fixed SI unit a stored field is written in, named by the field (`thickness_mm`, `width_m`, `u_w_m2k`). Display units convert from it and never replace it |
| Table layout | A table's saved column visibility, widths and ordering. A local user preference outside the SKP; filter text and expansion are not part of it |
| Locate | An explicit row action that selects an entity in SketchUp and zooms the view to it, refusing hidden targets. Selecting a row without zooming is not Locate |

## Geometry units and the honeybee mapping

honeybee's names for its geometry units collide with ordinary building words, so this table is
exact. The left column is what PH-Composer says on screen, in code and in this repository; the
right column is what the export writes. The rules are in the zones-and-adjacency packet
(`planning/archive/phase-01-zones-and-adjacency/PRD.md`); Phase 1 implemented them.

| Term | Meaning | honeybee object | Note |
| --- | --- | --- | --- |
| Zone | The fundamental geometry unit: one SketchUp Group, at Model root or inside plain wrapper groups and never inside another Zone, carrying envelope faces, Spaces, loads and schedules. A building may be one Zone; a Zone is required before export | `honeybee.room.Room` | honeybee calls this a Room. PH-Composer never uses Room for it, and honeybee's own `Room.zone` text tag is a different thing that PH-Composer does not surface |
| Building-Segment | A tag on one or more Zones naming the part of the building that becomes one METr model. Every Zone belongs to exactly one Building-Segment; a Model with one Building-Segment never shows the field | honeybee-ph `BldgSegment` | PHX builds one variant per Building-Segment and merges its Zones |
| Level | An optional classifier tag on a Zone for query, sort and group. A Space inherits its Zone's Level and has none of its own | `Room.story` | Replaces the predecessor's Space-owned Floor level (zones packet, Q6) |
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

Face vocabulary follows honeybee, because the export writes honeybee objects. PH-Composer does
not coin a third vocabulary between SketchUp and honeybee. Faces belong to a Zone.

| Term | Meaning |
| --- | --- |
| Envelope face | A SketchUp face the user has classified as part of the thermal envelope. Classification is PH-Composer's own record in its own attribute namespace; the face carries no designPH data |
| Face type | The honeybee face type of an envelope face: `Wall`, `RoofCeiling`, `Floor` or `AirBoundary` |
| Boundary condition | What is on the other side of an envelope face: honeybee's `Outdoors`, `Ground`, `Adiabatic`, `Surface`, and honeybee-ph's `PhAdditionalZone`. Shown as Outdoors, Ground, To neighbour, Surface (set only by Solve adjacencies) and Attached zone |
| Attached zone | A named unconditioned space outside the envelope (garage, attic, crawlspace) with one temperature reduction factor, default 0.95 per Phius guidebook 6.9.1. A model-local record kind owned by Zones, which a library can supply later, assigned to faces as a boundary condition. Maps to honeybee-ph `PhAdditionalZone` |
| Ground depth | A per-Zone height, default the Model's z=0, below which the Classify tool suggests Ground |
| Face record | The classification record on one face: face type, boundary condition, assembly id and Zone stamp. A retired pair can leave the boundary condition absent. Payload preservation and endpoint validity are distinct requirements, subject to native-host acceptance |
| Face assignment | The act and the packet: writing face records with the Classify tool, the faces table or Suggest classification (`planning/archive/face-assignment/`) |
| Classify tool | The modal viewport tool that writes face records: palette in the panel, click, drag, Shift-click for connected coplanar faces, one Undo step per gesture |
| Suggested classification | The face type and boundary condition the tool proposes for a hovered face from its normal and position, using honeybee's thresholds; shown, never written without a click |
| Unclassified face | A face inside a Zone with no face record. Ignored in a single-Zone model; a finding in a multi-Zone one |
| Incomplete face | A face record missing a required type, boundary reference or assembly, or naming an invalid or unavailable referenced record. Face assignment's consumer matrix determines blocking versus reported omission |
| Colour-by | The shared visualization component: one viewport overlay, one panel legend with counts, Locate and Isolate (fade every other row in the viewport), and one viewport HUD legend drawn while a mode is active. Features register modes; it is the fourth contribution seam. Never writes a SketchUp material |
| Colour-by mode | One registered way of colouring the model: a name, an entity kind (a face, a Zone, a Volume or another kind a feature names), a colour function, a label and optionally derived geometry such as the Volume preview. A readout, such as Space labels or Selection totals, registers separately and does not depend on the active mode. Face type, boundary condition and assembly come from face assignment; Zone, Building-Segment and Level from the zones packet |
| HUD legend | The compact text legend the Colour-by overlay draws in the upper left of the viewport while a mode is active, so a screenshot carries its own key |
| Classification overlay | The Colour-by overlay in its face modes: face type and boundary condition now, assembly when Assemblies arrive |
| Faces table | The panel inventory of face records with editable type, boundary condition and assembly cells, area, state and Locate |
| Material | Physical and product properties used by assembly layers. METr's own screen word. Maps to honeybee `EnergyMaterial`. Distinct from SketchUp display materials |
| Material category | A preset classification shown as a colored chip. Independent of display color. User-created categories are not supported |
| Material variant | A separately named material with independent properties, created through Duplicate Material. Never created automatically by reuse |
| Assembly | A reusable construction definition of ordered layers. METr's own screen word. Maps to honeybee `OpaqueConstruction` |
| Layer | A position in an assembly owning thickness and containing one or more Layer-Segments. Exports as one honeybee `EnergyMaterial` |
| Layer-Segment | One side-by-side strip of a Layer: a Material and a width. Always written with its qualifier, as Building-Segment is. Exports as one column of the layer's honeybee-ph `PhDivisionGrid` |
| SD assembly | A placeholder assembly for early design: three real layers sized to a target U-value, after honeybee-grasshopper-ph's SD constructions. Planned, not in the first assemblies phase. PH-Composer has no assembly without layers |
| Assembly usage | The set of envelope faces assigned to a Model-library assembly, measured by a scan and reported as of the scan time |
| Thermal Bridge Type | A reusable junction detail stored in the Model: a name, one psi-value, a group, a colour and a link to the psi-value calculation report. A different psi-value is a different type. Maps to the psi-value and group of honeybee-ph's `PhThermalBridge` |
| Thermal bridge | One run of assigned edges with a measured length and its type's psi-value. The exported object, honeybee-ph's `PhThermalBridge`, held by the Building-Segment of the Zone that contains the edges. Point bridges and chi-values are outside the MVP because honeybee-ph has no canonical carrier |
| Thermal bridge assignment | The record on one SketchUp edge naming its Thermal Bridge Type and a quantity. The edge is the record: a split or a copy carries it, and deleting the edge removes it. The MVP has no point assignment |
| Run | Connected assigned edges with the same Zone, type and quantity, ending at a free end or at a junction of three or more. A closed loop is one run. Derived each time the Model is read, never stored |
| Thermal bridge group | Ambient, Perimeter or Basement floor, METr's words for its three groups. Stored as honeybee-ph's `15-Ambient`, `16-Perimeter` and `17-FS/BC`; shown in METr's words |

## Windows

| Term | Meaning |
| --- | --- |
| Frame | One reusable head, jamb, sill or mullion profile with its product properties. A window element references four. The predecessor said Frame segment |
| Glazing | A reusable glazing definition with its product properties |
| Psi-Install Type | A reusable installation-junction definition assigned to Window Type perimeter edges. Unset edges visibly inherit the user-selected Model default. It is an authoring layer over the Frame, so one Frame product serves every wall it is installed in without a copy per wall. On export its value is written to that side of the frame, honeybee-ph's `PhWindowFrameElement.psi_install` |
| Window Type | A reusable exact-size and layout configuration defined by size, glazing, frames, operation and handedness, and perimeter Psi-Install Type assignments. Installation differences use explicit named variants; placements follow their type with no per-instance overrides |
| Element | One cell of a Window Type's layout, possibly merged across rows or columns. A glazed element names a Glazing, a Frame and a Psi-Install Type for each of its four sides, and an operation, any of which may still be unset (an unset install edge inherits the Model default); an empty element is an Empty panel |
| Window unit | One placed use of a Window Type: an instance of the type's flat component, which PH-Composer generates with one face per glazed element, glued to and cutting an envelope face. Each unit has its own identity, and a copied unit receives its own the next time the feature changes the Model |
| Install depth | The reveal depth from the wall's outer surface to the glass. A model default with a Window Type override. Exports to honeybee-ph `install_depth` |
| Window occurrence | A placed window reached through its full SketchUp parent path. Repeated parents expose the same child through different occurrences, and its stored attributes are not independent per occurrence. Independent edits require explicit parent uniqueness; PH-Composer never makes a parent unique automatically |
| Primary definition | The one generated SketchUp component definition a Window Type's Units use. Make Unique creates a detached copy that the Type no longer updates; Reset to type puts a Unit back on its Type's primary definition, regenerating that definition from the Type |
| Window anchor | The fixed point for placement and resize, named by row and column on the opening: `sill_left`, `sill_center`, `sill_right`, `center_left`, `center`, `center_right`, `head_left`, `head_center`, `head_right`. Sill center is the default |
| Empty panel | A layout cell representing excluded wall area. Retained for layout editing and excluded from window thermal contributions |
| Install edge source | Where one element edge's installation value comes from: `explicit`, `default`, `derived_zero` (an edge shared with a neighbouring element), `unsupported_partial`, `dangling` or `missing` |
| Shading | Not authored. METr and WUFI-Passive handle window shading after export. The predecessor's designPH shading relay is retired |

## Spaces

| Term | Meaning |
| --- | --- |
| Space | One unique SketchUp Group inside a Zone, containing one or more Volumes and Space-level data: iCFA, ventilation airflows, occupancy. Maps to a honeybee-ph `Space` on its Zone's Room. Do not call it Room in product copy, and do not confuse it with honeybee's Room, which is a Zone |
| Volume | A protected structural Group directly inside a Space, holding one logical Space Floor |
| Space Floor | Logical grouping of Floor Segments in a Volume; not another SketchUp Group |
| Floor Segment | A face inside a Volume that the user has marked as floor area, carrying PH-Composer identity, a weighting factor and a net area factor. In the predecessor this identity sat on a designPH TFA face; here PH-Composer owns the classification. Maps to honeybee-ph `SpaceFloorSegment` |
| Weighting factor | The share of a Floor Segment's area that counts toward iCFA, a number from 0 to 1 (honeybee-ph's `weighting_factor`): 1 counts it whole, 0 not at all. What counts is the user's to decide from the Phius rule; nothing enforces it |
| Net area factor | The share of a Floor Segment's area that counts toward net volume, default 1 |
| Average clear ceiling height | The one height a Volume carries. Net volume is net floor area times this height, as honeybee-ph's `SpaceVolume` computes it |
| Volume preview | The overlay extrusion of a Volume's Floor Segments by its height. Drawn, never modeled |
| Height from solid | The helper that sets a Volume's height from a closed group the user drew: the group's volume divided by the Volume's net floor area |
| Space label | Viewport text at a Space's reference point: number, name, iCFA, net volume, airflows |
| Selection totals | The HUD readout of summed iCFA, net volume and airflows for the selected Spaces |
| Airflow balance | Each Zone row of the Spaces view: its Spaces' supply, extract and transfer sums, with a marker where supply and extract differ by more than 10 percent of the larger. A Zone holding a Space that inherits its airflow shows a dash. There is no separate balance view and no balance by ventilator |
| Move Space to Zone | The action that relocates one whole Space group into another Zone group, keeping world position and records |
| Mark floor | The Spaces tool that marks a face inside a Volume as a Floor Segment with a weighting factor, started from the Weighting factor column menu. A separate tool beside Classify, not a mode of it |
| Make independent | The repair for a copied Space, Volume or Floor Segment: the copy and everything inside it receive new identities, as one Undo step. Until it runs, the shared identity blocks export |
| iCFA | Interior conditioned floor area, Phius's reference floor area: drywall-to-drywall of the thermal boundary, including interior walls and stairs, at least 7 ft clear height, open-to-below excluded (guidebook 4.4.1.4). It replaces the predecessor's TFA and carries no PHI reduction factors |
| Net volume | Net floor area times average clear ceiling height, summed over Volumes. Shown as Vn50 where a consumer calls it that. Phius does not require it for certification (guidebook 6.4.3); METr and WUFI still take it |
| Space default height | Explicit Space value copied to new Volumes; not inferred from floor geometry |
| Floor level | Shown on a Space and read from its Zone's Level; see Level above. Not editable on the Space. A blank value is shown as Unassigned |
| Space Type | A reusable Space definition; labels, defaults and inheritance await their interview |
| Authoring context | The active Space or Volume editing path that determines structural ownership |
| Reconciliation | Updating PH-Composer structure and protection after external geometry changes |
| Volume protection | Contextual locking that prevents independent Volume movement outside its edit context |
| Supply, Extract and Transfer airflow | Separate optional Space inputs, stored so that unset is different from explicitly zero. When all three are unset the Zone's ventilation load applies. When any one is set the Space is user-specified: its values override the Zone's load and an unset rate counts as zero |
| Ventilation assignment | Relationship from a Space to serving ventilation equipment |

## Systems

| Term | Meaning |
| --- | --- |
| Equipment | Model-local records of the ventilators, hot water systems, heat pumps, heaters, pumps, fans and appliances a Phius model needs. One record per item with a quantity; there is no separate product definition. An item serves one or more Zones |
| Piping / Ducting | Authored runs, segments and system relationships guided by honeybee-ph; details await interviews |

## Site and climate

| Term | Meaning |
| --- | --- |
| Climate snapshot | The model-owned monthly and, when supplied, peak-load climate values plus provenance. It remains readable without its source file or provider |
| EPW-derived monthly climate | Preliminary monthly climate produced from a user-selected annual EPW by honeybee-ph. It is not certification approved and has no peak-load cases |
| Monthly-demand ready | The climate has the complete monthly values required by preliminary demand calculations and overlays |
| METr-climate ready | The climate has both monthly values and the user-supplied peak-load cases required by the current PHX METr exporter |

## Export

| Term | Meaning |
| --- | --- |
| Export | Produce the HBJSON artifact, the Export report and, when requested, the METr model, for independent consumers |
| HBJSON | Honeybee model serialization carrying the supported honeybee-ph data. The canonical interchange and the product's core promise |
| Exporter | A consumer of the HBJSON artifact that writes a second format. The METr exporter is the first; it runs PHX inside the shipped runtime |
| METr model | The WUFI-shaped JSON document METr reads, produced from HBJSON by PHX |
| Export report | Human-readable account of emitted content, omissions, approximations and failures |
| Model validation | Checks of Model integrity and supported export inputs. Not certification-document completeness |
| Export contributor | A feature's registration with the export run: what it prepares, which contract section it supplies, which result fields it declares and renders |

## Evidence and handoff

| Term | Meaning |
| --- | --- |
| Linked file | Optional association from a record to external evidence bytes |
| Datasheet / Photo | Roles of linked evidence, not hosted attachment stores |
| Folder root | Proposed shared logical location resolved to each user's local filesystem |
| Relink | Repair an evidence location or explicitly choose a replacement; never deletes source files |
| Transmission package | Proposed fixed handoff of Model artifacts and selected evidence, distinct from ordinary Export |

## Process

| Term | Meaning |
| --- | --- |
| Feature interview | Paced product discovery; seed stories become agreed only through recorded answers |
| Delivery phase | An approved unit of implementation after discovery |
| Host gate | Real-SketchUp verification required in addition to offline tests |
| Release Gate A | Whole-candidate proof and the explicit public-distribution decision |
| Contribution seam | One of the four places an outside contributor plugs in without touching the core: a feature folder, a library provider, an export contributor or exporter, a Colour-by mode |

## Relationships to preserve

A Zone contains Spaces and envelope faces; a Space contains Volumes; each Volume directly contains
Floor Segments. Group containment is authoritative: a Space is in a Zone because its group is
inside the Zone group, wherever its floors are drawn in the scene, and nothing tests geometric
containment. A Space cannot span Zones. A Floor Segment is never the same face as an envelope
Floor. A valid Space has at least one Volume and a valid Volume at least one Floor
Segment. Empty structures are visible recovery states.

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

External evidence is optional. A Model can be self-contained for building data while its linked
PDFs and photos require a mapped folder or transmission package. Export does not mean upload.
