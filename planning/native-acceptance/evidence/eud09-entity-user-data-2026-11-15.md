# EUD09: entity user data native acceptance, 2026-11-15

Packet: [entity user data](../../archive/entity-user-data/STATUS.md), stage EUD-09, PRD row UD-07.
Host: SketchUp 26.1.188, Ruby 3.2.2, macOS. Build: RBZ from `codex/entity-user-data` at `2ba77060`
(PR #508), installed and checked byte for byte by `acceptance_case.py begin`. Fixture: a synthetic Model
built by a private helper from the blank template: one Zone with six classified Faces and Assemblies (a
single Layer and a divided Layer of two Layer-Segments), one Window Unit, one Space with a Volume, Floor
and Floor Segment, one assigned thermal-bridge Edge, one Level and one Building Segment. Raw Models,
transcripts and step output stay under the gitignored `_private/host/eud09/`.

## EUD09X: export of every written map (bridge only)

Seven public metadata writes (Model, Spaces, Edge, Face, Zone, Window Unit, and `records.update_metadata`
for catalog records and parts), then an export to an approved synthetic destination, reloaded in the
pinned honeybee stack.

| Assertion | Result | Observation |
| --- | --- | --- |
| export-complete | Pass | `export.complete`, 0 blocking findings; the file's SHA-256 equals the receipt |
| carried-maps | Pass | Model, Room, Face, Aperture, Space, SpaceVolume, SpaceFloor, SpaceFloorSegment, construction, single-Layer material, divided-Layer hybrid host and both cell materials reload with exactly the written map |
| omitted-maps | Pass | Material, Window Type, Window Element, Frame, Glazing, Thermal Bridge Type, Edge, Level, Building Segment and a single-Layer Layer-Segment stay out of the HBJSON, each with exactly one `export.metadata_omitted` finding |

The preparation run on `c8097d2a` found the Material reported twice, once per export section that reads
it; `2ba77060` fixed it and this run is on that build.

## EUD09: Undo/Redo, reopen, copy and adoption (combined control)

Bridge writes and readbacks through public operations; native Edit menu clicks (Undo, Redo, Copy, Paste
In Place) through System Events from the conductor session, with SketchUp in front. No computer-use
grant, no viewport click and no pixel claim: these are records claims, read back after each click.

| Assertion | Result | Observation |
| --- | --- | --- |
| undo-redo | Pass | Seven metadata writes are seven Undo steps; seven native Undos remove one write group each in reverse order, seven Redos restore them in order |
| reopen | Pass | After save, a fresh process reads every map equal to what was written, with unchanged ids |
| copy-same-model | Pass | Copy and Paste In Place: copies carry every map under new ids (a copied Edge shares its id by design); changing each copy's map leaves the originals unchanged |
| paste-adopt | Pass | Paste In Place into a second Model; adoption rebuilds the Level and Building Segment with their maps and every pasted entity keeps its map |

Restoration: `host_bridge.py quit` closed both case documents without saving; no fault or development
patch was used, so normal composition held throughout.
