# frozen_string_literal: true

module PhComposer
  # The public application interface (context/CONTRACTS.md, "Public interface";
  # context/AGENT_INTERFACE.md). The panel, Ruby scripts and future external adapters all call these
  # methods; none of them needs the panel open.
  #
  #   found = PhComposer::API.discover
  #   context = PhComposer::API.connect(session_id: found["sessions"].first["id"])
  #   page = PhComposer::API.query(context: context, name: "ph_composer.records.list",
  #                                params: { "kind" => "example.foundation.part" })
  #   result = PhComposer::API.invoke(context: context, name: "example.foundation.update_parts",
  #                                   params: { "edits" => [...] },
  #                                   request: { "sequence" => 1, "expected_revision" => page["revision"] })
  #
  # Every call except `discover`, `describe` and `connect` answers with the Outcome shape
  # (shell/outcome.rb). Values cross this boundary as JSON: string keys, SI numbers, record ids,
  # never live SketchUp objects.
  module API
    MAJOR = 1
    MINOR = 87
    # One line per shape change under this major, newest last (context/CONTRACTS.md, "Public
    # interface"); the generated reference lists them.
    CHANGES = [
      { "minor" => 1, "date" => "2026-10-18",
        "change" => "describe adds capability, preview_capability, a view command's side_effects, preconditions " \
                    "and a query's response and while_busy; discover adds schemas; ph_composer.context.read is new." },
      { "minor" => 2, "date" => "2026-10-18",
        "change" => "ph_composer.spaces.list answers bounded summaries with fields, the Model's sums before any " \
                    "filter and the sums of the page's Zones and Building-Segments; spaces.volumes.list, " \
                    "spaces.floor_segments.list and spaces.findings.list are new, Floor Segment loops only when " \
                    "fields asks." },
      { "minor" => 3, "date" => "2026-10-18",
        "change" => "ph_composer.spaces.candidate_faces.list is new; spaces.update and spaces.batch_update type " \
                    "values and expected_values by field, with units, and refuse unknown keys at the schema." },
      { "minor" => 4, "date" => "2026-10-18",
        "change" => "ph_composer.context.open and ph_composer.context.root are new view commands; the Spaces context " \
                    "commands and both locate commands declare side_effects." },
      { "minor" => 5, "date" => "2026-10-18",
        "change" => "ph_composer.context.read answers the camera; the view generation also advances when the " \
                    "camera changes." },
      { "minor" => 6, "date" => "2026-10-18",
        "change" => "The Outcome schema gains an optional sequence, set only by the agent connection's invoke and " \
                    "outcome results." },
      { "minor" => 7, "date" => "2026-10-18",
        "change" => "export_status and latest_export give the caller that started a task its written pair's paths, " \
                    "SHA-256 and sizes as outcome.value.artifacts." },
      { "minor" => 8, "date" => "2026-10-18",
        "change" => "The capture capability and ph_composer.view.capture are new; describe names the grant a view " \
                    "command declares when it is not view." },
      { "minor" => 9, "date" => "2026-10-21",
        "change" => "ph_composer.view.capture no longer answers window_state: every window state measured gives the " \
                    "current view." },
      { "minor" => 10, "date" => "2026-10-25",
        "change" => "ph_composer.thermal_bridges is new: the Thermal Bridge Type kind, types.list, types.all and its " \
                    "snapshot section, and types.create, types.update, types.duplicate and types.delete." },
      { "minor" => 11, "date" => "2026-10-25",
        "change" => "ph_composer.zones.containment is new. ph_composer.thermal_bridges.edges.assign, edges.clear, " \
                    "edges.selection (bounded), edges.selection_all and the edges.selected snapshot section are " \
                    "new, over the ph_composer.thermal_bridges.edge reference target; types.delete takes " \
                    "replacement_id." },
      { "minor" => 12, "date" => "2026-10-25",
        "change" => "ph_composer.thermal_bridges.schedule.list (bounded) and schedule.all are new: thermal-bridge " \
                    "runs with lengths, heat loss, findings and totals. " \
                    "ph_composer.thermal_bridges.runs.locate is a new view command. ph_composer.zones.containment, " \
                    "and so ph_composer.thermal_bridges.edges.selection, answers each Zone's name." },
      { "minor" => 13, "date" => "2026-10-26",
        "change" => "ph_composer.thermal_bridges.edge_tool.choose and edge_tool.stop are new view commands, with " \
                    "edge_tool.state and the edge_tool snapshot section: the pointer route to edges.assign." },
      { "minor" => 14, "date" => "2026-10-26",
        "change" => "ph_composer.windows.units.outlines (bounded) is new: each placed Window's world outline. " \
                    "ph_composer.thermal_bridges.export_preflight is new, with the " \
                    "ph_composer.thermal_bridges.export.thermal_bridges export section and the " \
                    "thermal_bridge.on_window_perimeter code." },
      { "minor" => 15, "date" => "2026-10-26",
        "change" => "The definition lists (ph_composer.assemblies.materials.list and assemblies.list, the Window " \
                    "product and Type lists, ph_composer.thermal_bridges.types.list) take fields, keeping kind, id " \
                    "and schema_version on every row, and cut each page by size as well as by limit." },
      { "minor" => 16, "date" => "2026-11-07",
        "change" => "A Face record gains assembly_reversed, true on the counterpart side of a Surface pair. " \
                    "ph_composer.zones.faces.assign_assembly, and classify with an assembly_id intent, also write " \
                    "the counterpart (its face_ids include it). face.assembly_pair_mismatch now blocks export; " \
                    "construction.missing no longer applies to a Surface Face whose pair is within one " \
                    "Building-Segment." },
      { "minor" => 17, "date" => "2026-11-08",
        "change" => "An unexpected failure's detail gains error_class beside incident. " \
                    "ph_composer.zones.solve_adjacency's result gains already_paired. An Assembly's Layer, " \
                    "Layer-Segment and air-barrier ids and its Material references state their pattern in every " \
                    "schema that names them." },
      { "minor" => 18, "date" => "2026-11-08",
        "change" => "ph_composer.windows.units.return_to_host is new. It puts a Window that has left its Face back " \
                    "on the nearest Face of its Zone, and adds window.no_host_face." },
      { "minor" => 19, "date" => "2026-11-08",
        "change" => "ph_composer.windows.settings gains default_psi_install_w_mk, 0.04 W/mK unless set: what an " \
                    "edge with no Psi-Install Type inherits when the Model has no default Type." },
      { "minor" => 20, "date" => "2026-11-08",
        "change" => "The thermal-bridge schedule and export count one Type on Edges two Zones of one " \
                    "Building-Segment share once. thermal_bridge.coincident_conflict replaces " \
                    "thermal_bridge.counted_twice for coincident Edges that differ." },
      { "minor" => 21, "date" => "2026-11-08",
        "change" => "ph_composer.spaces.all no longer answers a Zone's imbalanced or findings, and " \
                    "space.airflow_imbalance is gone: supply and extract balance per ventilator, not per Zone." },
      { "minor" => 22, "date" => "2026-11-08",
        "change" => "A Frame gains brand, an optional text field, in ph_composer.windows.frames and the frames " \
                    "library kind." },
      { "minor" => 23, "date" => "2026-11-08",
        "change" => "A Window Unit reads its native name in ph_composer.windows.units.list and .all; " \
                    "ph_composer.windows.units.rename and ph_composer.windows.units.selection are new." },
      { "minor" => 24, "date" => "2026-11-09",
        "change" => "ph_composer.windows.units.convert_review is new: which drawn rectangles Convert to Window Type " \
                    "would take, as Type layouts, and why it leaves the others out." },
      { "minor" => 25, "date" => "2026-11-09",
        "change" => "ph_composer.windows.units.convert is new: reviewed drawn rectangles become Window Types and " \
                    "placed Windows in one Undo step." },
      { "minor" => 26, "date" => "2026-11-09",
        "change" => "ph_composer.windows.units.convert_review's groups gain default_name, and it leaves out " \
                    "rectangles overlapping across Groups as window.overlap; convert's groups take " \
                    "copy_from_type_id. ph_composer.windows.convert_dialog.open, close and state are new, with " \
                    "the convert_dialog snapshot section and the convert_menu menu item." },
      { "minor" => 27, "date" => "2026-11-09",
        "change" => "A Space's Zone is the record's zone_id, a core reference; ph_composer.spaces.move_to_zone is a " \
                    "record edit and no longer refuses space.context_open. ph_composer.spaces.unhost and the " \
                    "space.zone_missing finding are new; ph_composer.zones.make_independent takes copy_added and " \
                    "ph_composer.zones.isolate_copied_group is new, for a plain Group copied whole." },
      { "minor" => 28, "date" => "2026-11-09",
        "change" => "ph_composer.spaces.create and create_preview take faces as root-to-Face paths and work in any " \
                    "edit context; create takes an optional zone; create_preview answers zone and height_m, and " \
                    "left_out rows carry path. create_review.open takes faces and revision and the review carries " \
                    "zones and height_m. ph_composer.zones.stamp_container and the nested_container reason are gone; " \
                    "zones export rows lose container_paths." },
      { "minor" => 29, "date" => "2026-11-09",
        "change" => "The ph_composer.spaces.labels readout is now ph_composer.spaces.show, on by default in every " \
                    "Model session; it draws each Volume's preview outline with the Space labels." },
      { "minor" => 30, "date" => "2026-11-09",
        "change" => "ph_composer.spaces.remove is new: a Space's records go and its floor Faces stay as plain " \
                    "geometry, in one Undo step." },
      { "minor" => 31, "date" => "2026-11-09",
        "change" => "A Volume whose Floor Segments overlap in plan reads the space.floor_overlap finding, a warning " \
                    "that does not block export." },
      { "minor" => 32, "date" => "2026-11-09",
        "change" => "ph_composer.spaces.create and volumes.create make one Volume per set of Faces joined by shared " \
                    "Edges and answer volumes, a list of volume_id and floor_segment_ids, in place of volume_id and " \
                    "floor_segment_ids. A Volume whose Floor Segments are not all joined reads the " \
                    "space.floor_disconnected finding, a warning that does not block export. The add_volume_menu " \
                    "menu item is new, and create_menu is no longer offered inside a Space." },
      { "minor" => 33, "date" => "2026-11-10",
        "change" => "ph_composer.spaces.volumes.delete is new: it erases one Volume and its floor Faces in one Undo " \
                    "step, where volumes.remove keeps the Faces. The delete_volume_menu menu item is new." },
      { "minor" => 34, "date" => "2026-11-10",
        "change" => "ph_composer.spaces.create answers accepted and left_out as create_preview does, and each new " \
                    "Volume of create and volumes.create answers faces, its source Face paths. spaces.delete, " \
                    "remove, volumes.delete and volumes.remove refuse target.foreign_records while another " \
                    "feature's records are on or inside the Group. Make Zone refuses a Group holding a claimed " \
                    "object at any depth (target.wrong_hierarchy) and Restore a claimed member (target.wrong_kind); " \
                    "zones.list, zones.all and export preflight read the zone.ownership_conflict finding, which " \
                    "does not block export. A Face reference with a null entity_id refuses target.changed on every " \
                    "Face write once the Face has a record, and zones.update and update_metadata refuse a locked " \
                    "Zone (target.locked) as update_field does." },
      { "minor" => 35, "date" => "2026-11-10",
        "change" => "discover adds library_kinds, and describe answers a library kind by name (its wire kind and " \
                    "version, and its assignment target schema and examples or that it has none) and an installed " \
                    "extension by namespace. The agent connection's discover takes section, owner, limit, cursor " \
                    "and topic for bounded pages of operations, record kinds, reference targets, extensions, " \
                    "library kinds, common refusals with their meanings, contracts and the operating guide; " \
                    "initialize names the guide. ph_composer.library.copy's generation says it is required, as " \
                    "its schema already did." },
      { "minor" => 36, "date" => "2026-11-10",
        "change" => "Selection-free reads at an explicit path: ph_composer.context.children pages the entities " \
                    "directly in the root or one Group or component, with their state and records; " \
                    "zones.make_candidates, windows.units.convert_candidates and windows.units.restore_candidates " \
                    "list what Make Zone, Convert and Restore could take there; thermal_bridges.edges.at and " \
                    "edges.candidates read Edges by path in edges.selection's rows plus endpoints_m; and " \
                    "spaces.candidate_faces.list takes context for a first Space. A name over 256 characters is " \
                    "cut and named in the row's truncated. edges.selection's copied flag no longer refuses for an " \
                    "unreadable record on another Edge." },
      { "minor" => 37, "date" => "2026-11-10",
        "change" => "Complete reads of large definitions and metadata: ph_composer.records.detail answers one value " \
                    "of a record exactly in fragments with its size and SHA-256; records.list pages by size and " \
                    "takes metadata summary; assemblies.assemblies.layers.list and segments.list, " \
                    "windows.types.elements.list, assemblies.materials.uses.list and windows.<collection>.uses.list " \
                    "page a definition's parts and derived results; and preview takes within and preview_part, so " \
                    "a preview larger than a reply keeps its proposal_digest and is read by part." },
      { "minor" => 38, "date" => "2026-11-10",
        "change" => "Complete reads of large occurrence, geometry and schedule data: windows.units.list takes fields " \
                    "and metadata summary and windows.units.detail reads one Unit's part in fragments; " \
                    "units.host_extent takes geometry summary beside host_extent.holes and .points; " \
                    "units.face_areas.list and units.unhosted.list page the glazed area table; convert_review " \
                    "takes compact and convert_review.detail reads a group's sources; zones.list takes overview " \
                    "summary beside zones.restorable.list, restorable.detail and zones.findings.list; " \
                    "zones.options.adoption_sources.list and .detail, zones.faces.assembly_usage.list and .faces; " \
                    "thermal_bridges.schedule.list takes compact beside runs.members.list, " \
                    "schedule.by_type.list, schedule.edge_findings.list and schedule.unreadable.list; and " \
                    "spaces.detail reads a Space's, Volume's or Floor Segment's part, loops included." },
      { "minor" => 39, "date" => "2026-11-10",
        "change" => "Complete reads of library catalogs and exports: library.load, catalog, in_file, export_preview " \
                    "and export_file take compact, which counts notes and omissions and summarizes rows; " \
                    "library.warnings.list and unavailable.list page a catalog's notes; library.catalog.detail and " \
                    "in_file.detail read one row's part in fragments; library.export_preview.omissions pages an " \
                    "export's omissions against its projection_digest; export_file answers destination_state." },
      { "minor" => 40, "date" => "2026-11-10",
        "change" => "Complete export QA and repair: export_preflight takes compact (counts by owner and code) and " \
                    "part (a filtered page of findings or repairs, or one row whole); preflights report the " \
                    "metadata extraction refuses; export_status and latest_export take compact, every task names " \
                    "its source and diagnostics, and export_status with part reads an ended task's findings, " \
                    "report and result, refusing task.running before it ends; " \
                    "thermal_bridges.edges.repair_candidates and edges.repair remove an unreadable or stranded " \
                    "Edge assignment." },
      { "minor" => 41, "date" => "2026-11-10",
        "change" => "The Agent Access dialog's catalog adds agent_access.connection_changed, refused when a " \
                    "connection profile is bound to another token than the one shown; no operation changes." },
      { "minor" => 42, "date" => "2026-11-10",
        "change" => "ph_composer.spaces.context.open declares session.inactive: it, context.open, " \
                    "spaces.context.close and spaces.locate refuse to move the edit path of a Model SketchUp is " \
                    "not showing. An agent call whose client closed the connection before it ran is not run." },
      { "minor" => 43, "date" => "2026-11-11",
        "change" => "Every action refuses session.busy, before it takes a sequence, while the user is partway " \
                    "through a Move in SketchUp, which its commit would cancel; context readiness and discover's " \
                    "session busy say so. Reads and the Line tool are unaffected. An agent invoke answered busy " \
                    "releases its idempotency_key for the retry." },
      { "minor" => 44, "date" => "2026-11-11",
        "change" => "Every invoke refused before acceptance releases the idempotency_key it bound; access.revoked " \
                    "joins every kind's common refusals. thermal_bridges.edges.clear and types.delete pass over " \
                    "Edges whose text is not a JSON object, leave it and name them in a " \
                    "thermal_bridge.unreadable_skipped finding. zones.repair_identity refuses a locked Zone." },
      { "minor" => 45, "date" => "2026-11-11",
        "change" => "A create or duplicate names its records from the session, revision, action and params, so a " \
                    "preview run again and its invoke name the same ids and a create's preview parts read across " \
                    "calls. Registration refuses a feature id, name, wire kind or code longer than 1,024 bytes " \
                    "as registration.schema_invalid." },
      { "minor" => 46, "date" => "2026-11-11",
        "change" => "Every action also refuses session.busy while the user is partway through a Scale in " \
                    "SketchUp, as for a Move; context readiness and discover's session busy say so." },
      { "minor" => 47, "date" => "2026-11-11",
        "change" => "Every action also refuses session.busy while the Rotate tool is selected in SketchUp, idle " \
                    "or partway, since SketchUp does not report a turn in progress; context readiness and " \
                    "discover's session busy say so." },
      { "minor" => 48, "date" => "2026-11-12",
        "change" => "With more than one Model open, a change no PH-Composer operation owns advances every open " \
                    "session's revision, since SketchUp does not say which Model an outside script changed; " \
                    "an invoke resting on an earlier read of any of them refuses revision.stale." },
      { "minor" => 49, "date" => "2026-11-12",
        "change" => "start_export takes expected_revision: a Model at another revision refuses revision.stale and " \
                    "starts nothing, and one that changes before the run has read it fails the task " \
                    "revision.stale." },
      { "minor" => 50, "date" => "2026-11-12",
        "change" => "API.outcomes is new: the caller's own retained change outcomes, newest first and paged, " \
                    "each with its sequence, operation, status, effect, code, revision, recorded time and first " \
                    "affected references, never its value or params. The agent outcome tool lists them when " \
                    "given neither sequence nor idempotency_key, with each row's key." },
      { "minor" => 51, "date" => "2026-11-12",
        "change" => "ph_composer.view.capture takes inline and then answers the PNG itself as inline_image, which " \
                    "the agent connection sends as an image content block outside the reply budget; " \
                    "capture.too_large names a smaller width and height. export_status takes part file for a " \
                    "completed task: the written HBJSON's text in fragments with the receipt's hash, refusing " \
                    "artifact.none for a task that wrote no file and artifact.changed for a file that no longer " \
                    "matches its receipt." },
      { "minor" => 52, "date" => "2026-11-14",
        "change" => "ph_composer.records.update_metadata is new: it replaces the user_data and installed extension " \
                    "payloads of records of any kind records.list reads, in one Undo step, guarded by " \
                    "expected_metadata, refusing target.wrong_kind for Building Segments, Levels and Zone option " \
                    "settings. The update actions of Materials, Assemblies, Frames, Glazings, Psi-Install Types, " \
                    "Window Types and Thermal Bridge Types, the update rows of windows.types.installs.save and an " \
                    "attached_zone.save with id no longer take user_data; their create actions still do." },
      { "minor" => 53, "date" => "2026-11-14",
        "change" => "Assembly Layers and Layer-Segments take an optional user_data map. A " \
                    "ph_composer.records.update_metadata reference takes part_ids to write the map of one part, such " \
                    "as [Layer id, Layer-Segment id]; a part takes user_data only. describe on a record kind lists " \
                    "its parts. Assembly gestures keep each surviving part's map, a new part starts without one, " \
                    "and Duplicate copies the maps under new part ids." },
      { "minor" => 54, "date" => "2026-11-14",
        "change" => "Window Elements take an optional user_data map, written by " \
                    "ph_composer.records.update_metadata with part_ids [element id] and read by " \
                    "windows.types.elements.list. windows.types.grid.merge keeps the top-left element's map and " \
                    "returns removed_user_data, each other merged element whose map was not empty with its " \
                    "top-level keys, and removed_user_data_total. Split copies the map into every piece, a kind " \
                    "change, flip, installs save, Duplicate and new_flipped_type keep it, and an inserted element " \
                    "starts without one." },
      { "minor" => 55, "date" => "2026-11-14",
        "change" => "ph_composer.records.update_metadata writes Building Segment and Level maps and rewrites the " \
                    "copy each adopted Zone and member stamp keeps in the same Undo step; it may refuse " \
                    "target.locked. Zone option settings still refuse as target.wrong_kind. " \
                    "zones.options.manage, remove and merge keep the survivor's map and return removed_user_data, " \
                    "each removed option whose map was not empty with its top-level keys, and " \
                    "removed_user_data_total. A RecordKind may declare metadata_follow_up." },
      { "minor" => 56, "date" => "2026-11-14",
        "change" => "thermal_bridges.edges.selection, selection_all, at and candidates rows carry user_data, " \
                    "extension_data and extension_status. New ph_composer.thermal_bridges.edges.update_metadata " \
                    "replaces the metadata of assigned Edges by occurrence, guarded by expected_metadata, at most " \
                    "250 Edges in one Undo step; an Edge with no assignment refuses." },
      { "minor" => 57, "date" => "2026-11-14",
        "change" => "ph_composer.model.detail and ph_composer.model.update_metadata are new: the Model's own " \
                    "user_data and extension_data, in the ph_composer.model dictionary, read as {} until written and " \
                    "replaced under expected_metadata in one Undo step. Volume rows carry floor, the Space Floor's " \
                    "reference and its own user_data (a ph_composer.spaces.volumes.list field, not a default), and " \
                    "spaces.update_metadata writes that map by floor_id. Clearing a map a record never stored writes " \
                    "nothing in every owner's update_metadata." },
      { "minor" => 58, "date" => "2026-11-14",
        "change" => "Export carries the Model's user_data to the HBJSON Model, a Space Floor's to its SpaceFloor, " \
                    "an Assembly Layer's to its material (the hybrid host when divided) and a divided Layer's " \
                    "Layer-Segments' to their cell materials; a ph_composer key in any of them blocks the export, " \
                    "and the new ph_composer.model.export_preflight reports it for the Model. The extraction gains " \
                    "the ph_composer.model.export.model section and a Volume's floor_user_data. Window Element, " \
                    "Attached zone, membrane Layer and undivided Layer-Segment maps stay in the Model with an " \
                    "export.metadata_omitted finding, and each finding is listed once." },
      { "minor" => 59, "date" => "2026-11-14",
        "change" => "An export.metadata_omitted finding about a record part (an Assembly Layer or Layer-Segment, " \
                    "or a Window Element) gains reference, the {kind, id, part_ids} " \
                    "ph_composer.records.update_metadata takes, and its message names the record that holds the " \
                    "part. A contributor's " \
                    "Engine#propose_update no longer takes user_data: ph_composer.records.update_metadata " \
                    "(Engine#propose_metadata_update) is the one write route for an existing record's map." },
      { "minor" => 60, "date" => "2026-11-14",
        "change" => "An update that rebuilds a record's parts, such as windows.types.update with elements, keeps " \
                    "each surviving part's user_data by id whether or not it sends it, starts a new part without " \
                    "one, and refuses params.invalid for a part map that differs from the stored one. The deletes of " \
                    "Materials, Assemblies, Frames, Glazings, Psi-Install Types, Window Types, Thermal Bridge Types " \
                    "and Attached zones return removed_user_data and removed_user_data_total, each part listed by " \
                    "part_ids. ph_composer.model.detail takes metadata summary, ph_composer.model.fragment is new, " \
                    "and ph_composer.model.update_metadata returns extension_status only. thermal_bridges.edges." \
                    "selection, at and candidates take metadata summary, and thermal_bridges.edges.detail is new. " \
                    "Export reports an unused Building Segment's or Level's map as omitted. A part declaration " \
                    "needs a required string id and an optional object user_data. Engine#propose_update takes " \
                    "derived_part_maps and Engine#propose_delete returns the removal report." },
      { "minor" => 61, "date" => "2026-11-14",
        "change" => "Every delete and merge that returns removed_user_data also returns " \
                    "removed_user_data_truncated, and its rows stay within 8192 bytes: each listed map keeps its " \
                    "address and user_data_key_total, and its keys fill in while they fit. The new reference " \
                    "target ph_composer.model.metadata puts the Model's extension payloads in the incoming-reference " \
                    "check, so a record a Model payload names refuses deletion as reference.in_use. A membrane " \
                    "Layer's Layer-Segment map stays in the Model with an export.metadata_omitted finding even " \
                    "with a steel stud spacing." },
      { "minor" => 62, "date" => "2026-11-17",
        "change" => "The ph_composer.climate feature is new, requiring ph_composer.zones. " \
                    "ph_composer.climate.site.get and site.update read and set the Model's site (latitude, " \
                    "longitude and elevation together, a climate-zone code and hours from UTC); " \
                    "ph_composer.climate.design_temperatures.get and design_temperatures.update read and set the " \
                    "ASHRAE 99% heating and 1% cooling dry bulbs and a source note, any field alone; " \
                    "ph_composer.climate.summary.get backs the ph_composer.climate.summary snapshot section. " \
                    "climate.heating_not_below_cooling is new, a warning the design-temperature read carries." },
      { "minor" => 63, "date" => "2026-11-17",
        "change" => "The ph_composer.climate.climate record kind is new, one climate per Model. " \
                    "ph_composer.climate.climate.get reads it with its state, what is missing, the edited cells " \
                    "and the Phius limit check against the site; climate.enter_values enters one by hand with " \
                    "gaps allowed, climate.save_values edits its values and rewrites its provenance, " \
                    "climate.restore_original copies the station file's values back, and climate.clear deletes " \
                    "it, each guarded by the editable fields last read. ph_composer.climate.site.update's " \
                    "result gains limit_check, ph_composer.climate.site.preview_limit_check is new, and the " \
                    "summary gains the climate card. climate.not_found and climate.no_original are new." },
      { "minor" => 64, "date" => "2026-11-18",
        "change" => "The climate data folders on this computer, kept in PH-Composer's own settings file: " \
                    "ph_composer.climate.folders.list reads them with a display location that is never an " \
                    "absolute path; the setup commands folders.add and folders.locate take a folder the user " \
                    "chooses, and folders.rename, folders.remove and folders.remember_dataset take its id. " \
                    "climate.settings_unreadable, climate.settings_unavailable, climate.folder_not_found and " \
                    "climate.folder_overlaps are new." },
      { "minor" => 65, "date" => "2026-11-18",
        "change" => "The Phius station reader. ph_composer.climate.folders.list gives each folder's format, station " \
                    "and state counts and files not read by extension; ph_composer.climate.stations.list pages one " \
                    "folder's stations nearest the site first with each one's Phius limit check; " \
                    "climate.attach_station and climate.replace_station take a folder id and a station key and " \
                    "read the file in Ruby; climate.source_status says whether the attached station's file is on " \
                    "this computer. climate.site_not_set, climate.station_not_found and climate.station_unreadable " \
                    "are new. A station climate's provenance station_name is its file name's stem." },
      { "minor" => 66, "date" => "2026-11-18",
        "change" => "The Site export section. ph_composer.climate.export_preflight is new and answers the export " \
                    "findings climate.incomplete, climate.zone_not_set, climate.utc_offset_not_set, " \
                    "climate.outside_phius_limits and climate.not_checked, which are new, and " \
                    "climate.site_not_set; none blocks the export. The export writes the site and a complete " \
                    "climate as honeybee-ph's Site on every Building Segment." },
      { "minor" => 67, "date" => "2026-11-18",
        "change" => "ph_composer.climate.site.geolocation is new: what SketchUp reports for the Model's " \
                    "geolocation, latitude and longitude only when SketchUp reports the Model geolocated, and no " \
                    "elevation or offset. The snapshot sections ph_composer.climate.site and " \
                    "ph_composer.climate.design_temperatures carry the site and design-temperature reads for the " \
                    "Climate tab." },
      { "minor" => 68, "date" => "2026-11-18",
        "change" => "ph_composer.climate.stations.all is new: one climate data folder's stations in one unbounded " \
                    "read, nearest the site first, in stations.list's rows, for the station picker; scripts page " \
                    "stations.list." },
      { "minor" => 69, "date" => "2026-11-19",
        "change" => "The Shading feature. ph_composer.shading.assign and ph_composer.shading.clear mark and unmark " \
                    "explicit Faces, Groups and components by root-to-entity path, each one Undo step, answering " \
                    "assigned or cleared, unchanged and left_out; ph_composer.shading.selection and " \
                    "ph_composer.shading.list read the selection and every mark and shading component. " \
                    "shading.face_classified, shading.zone_target, shading.inherited and shading.cutting_component " \
                    "are new." },
      { "minor" => 70, "date" => "2026-11-19",
        "change" => "A Face inside a Zone that is shading, or inside a shading Group or component there, is not part " \
                    "of the Zone's envelope: Zones reads, writes, Solve, Colour-by and export leave it out, and an " \
                    "explicit reference to it refuses face.outside_envelope; zones.containment answers it with the " \
                    "reason outside_envelope. ph_composer.zones.faces.clear_classification is new: it removes Face " \
                    "records in one Undo step, refusing face.surface_paired and face.aperture_host. " \
                    "ph_composer.shading.export_preflight is new and notes shading.zone_inside and " \
                    "shading.classified_inside. shading.assign refuses a Group inside a Zone that holds classified " \
                    "Faces with shading.face_classified; a classified Face leaves the envelope only by its own mark." },
      { "minor" => 71, "date" => "2026-11-19",
        "change" => "Export writes each Shading Face as an orphaned honeybee Shade in the new optional section " \
                    "ph_composer.shading.export.shades, named for its shading component, with the section's result " \
                    "fields shading_components, shade_count and area_m2 and a Shading report section. " \
                    "ph_composer.shading.export_preflight now runs with every export and also lists the Faces export " \
                    "leaves out (shading.geometry_invalid, target.ambiguous), unreadable marks (record.unreadable) " \
                    "and a mark's extension data the left-out rules refuse; every row names its path and carries the " \
                    "object id the export's note uses. A shading component name that reads as a local file path " \
                    "counts as no name." },
      { "minor" => 72, "date" => "2026-11-19",
        "change" => "ph_composer.shading.export_preflight gives a marked Group or component inside a Zone both " \
                    "shading.zone_inside and shading.classified_inside when it holds a Zone, a claimed object or a " \
                    "cutting component beside classified Faces; before, the first note hid the second." },
      { "minor" => 73, "date" => "2026-11-20",
        "change" => "Zone schema 3: building_segment_id may be null, No Building Segment; Zones write schema 3 and " \
                    "schema 2 still reads. ph_composer.zones.update_field and ph_composer.zones.update accept a null " \
                    "building_segment. ph_composer.zones.options.manage and remove accept a null replacement for a " \
                    "used Building Segment, which moves its Zones to No Building Segment; removing the default moves " \
                    "it to the replacement, else to the first remaining Segment; removing the last Segment refuses " \
                    "zone.option_last_segment. manage, remove and merge results add removed_extensions and " \
                    "removed_extensions_total. Colour-by Building Segment shows Zones in no Segment as one neutral " \
                    "No Building Segment row. Until export leaves them out, such a Zone blocks export." },
      { "minor" => 74, "date" => "2026-11-20",
        "change" => "ph_composer.zones.save_segment_settings is new: one Building Segment's name, colour, default " \
                    "and a settings payload per extension namespace in one Undo step, emitting " \
                    "ph_composer.zones.segment_settings_saved. ph_composer.zones.create_segment is new: a Segment " \
                    "under the first free default name with named Zones moved in. A Zone's choice evidence keeps " \
                    "its Building Segment's values only, so a Segment metadata write no longer rewrites its Zones " \
                    "and adoption brings no Segment settings. ph_composer.zones.all adds building_segments, each " \
                    "Segment's Face area; ph_composer.spaces.all and list add airflows and inheriting_count to " \
                    "each building_segments row." },
      { "minor" => 75, "date" => "2026-11-20",
        "change" => "Export leaves a Zone in no Building Segment out with its Faces, Spaces, assigned Edges and the " \
                    "Window Units on its Faces, and a Building Segment no Zone names; export preflight refuses " \
                    "zone.no_segment when Zones exist and none is in a Segment, no longer refuses such a Zone with " \
                    "reference.invalid, refuses face.partner_left_out on a Surface pair across that boundary, and " \
                    "adds the info rows zone.left_out, zone.segment_empty, space.zone_left_out, " \
                    "thermal_bridge.zone_left_out and window.zone_left_out. " \
                    "ph_composer.zones.faces.attached_zone.offer is new: the Faces a Zone moved out shares with " \
                    "exported Zones, both sides, for create_and_assign or classify. An AttachedZone Face exports as " \
                    "honeybee-ph PhAdditionalZone." },
      { "minor" => 76, "date" => "2026-11-20",
        "change" => "ph_composer.certification is a new feature: the ph_composer.certification.segment extension on " \
                    "each Building Segment (category, program, use, status, type), saved through " \
                    "zones.save_segment_settings, read by ph_composer.certification.segment.get with its defaults, " \
                    "and exported to the BldgSegment's phius_certification. An export contributor may claim an " \
                    "extension on a catalog record kind; its rows carry a null path, and Zones' export and preflight " \
                    "now check a claimed envelope on every valid Building Segment instead of leaving it out. The " \
                    "Zones section's projection rows add building_segment_id and building_segment_export_identifier, " \
                    "and translation sections may attach at the segment host." },
      { "minor" => 77, "date" => "2026-11-20",
        "change" => "A Space's airflow mode is its Zone's: by_program until any Space in the Zone has a rate, then " \
                    "detailed, when every Space exports its own rates with 0 for a blank. ph_composer.spaces.all " \
                    "and list add airflow_mode to each Zone row; all's Zone rows drop inheriting_count, and each " \
                    "building_segments row replaces inheriting_count with by_program_zone_count. A Space row's " \
                    "airflow_mode takes by_program or detailed (was inheriting or user_specified), a copy of its " \
                    "Zone's kept for this minor version; read the Zone row's. " \
                    "ph_composer.spaces.clear_zone_airflows is new: From Program, every Space's rates in the named " \
                    "Zones cleared in one Undo step. The Spaces export section moves to version 2, each record " \
                    "carrying airflow_mode, and its preflight adds space.zone_without_spaces, a warning that does " \
                    "not block." },
      { "minor" => 78, "date" => "2026-11-20",
        "change" => "ph_composer.programs is a new feature: the ph_composer.programs.airtightness extension on each " \
                    "Building Segment (basis n50 or q50, value or null, wind_exposure), saved through " \
                    "zones.save_segment_settings, read by ph_composer.programs.airtightness.get with its defaults, " \
                    "and exported to each Zone's Infiltration and the BldgSegment's wind exposure. Export refuses " \
                    "airtightness.no_net_volume and airtightness.no_exposed_face. The Spaces export section " \
                    "registers a projection of each Zone's net volume." },
      { "minor" => 79, "date" => "2026-11-20",
        "change" => "ph_composer.programs adds the Program, Schedule and Equipment Set record kinds with create, " \
                    "update, duplicate, delete, list and all reads; equipment_sets.add_device, update_device, " \
                    "delete_device and device_types; schedules.profile; settings.get and settings.update for the " \
                    "Model's default Program and Equipment Set; and reset_default. Reads answer PH-Composer's " \
                    "residential default Program, its Schedules and the default Equipment Set until a write stores " \
                    "them. Deleting a default without a replacement refuses programs.default_in_use." },
      { "minor" => 80, "date" => "2026-11-20",
        "change" => "The programs, schedules and equipment_sets library kinds: ph_composer.library.copy copies a " \
                    "library Program with every Schedule it names, reusing a local copy of each from the same " \
                    "source, in one Undo step, and a Program or Equipment Set copy may assign itself as the " \
                    "Model's default (mode model_default). A library kind may declare dependencies, which describe " \
                    "names; copy answers dependencies, each record of another kind it copied or reused, and refuses " \
                    "library.dependency_missing when the loaded catalog of that kind does not hold one. Library " \
                    "export writes each dependency of a written row, whatever kinds or records select, and refuses " \
                    "library.dependency_missing for one it cannot write; its omissions list a declared part's map " \
                    "the file leaves out as <path>.user_data, such as devices[].user_data." },
      { "minor" => 81, "date" => "2026-11-20",
        "change" => "Dwellings and occupancy. The ph_composer.programs.dwelling kind with dwellings.list, all, " \
                    "create, update, duplicate and delete; the ph_composer.programs.zone_assignment extension on " \
                    "Zones and ph_composer.programs.segment on Building Segments, both local_only; " \
                    "programs.assign_program, assign_dwelling (shared, each, none or existing; an emptied Dwelling " \
                    "is deleted and its map reported), set_counts and assign_equipment_set, each one Undo step, " \
                    "refusing programs.single_dwelling and programs.dwelling_across_segments; the programs.zones, " \
                    "programs.dwellings and programs.single_dwelling_preview reads with their findings. Switching " \
                    "Single dwelling in zones.save_segment_settings clears or writes the Segment's Zone assignments " \
                    "and Dwellings in the same Undo step. The proposal participant ph_composer.zones.stage_extension " \
                    "stages a feature's payload on Zones and Segments; save_segment_settings names it for its " \
                    "transition's contributors. An Equipment Set delete with a replacement moves Dwellings to it." },
      { "minor" => 82, "date" => "2026-11-20",
        "change" => "The Zones / Programs view's reads and the library Program on Zones. " \
                    "programs.assign_library_program copies a library Program with its Schedules, or reuses its " \
                    "local copy, through ph_composer.library.copy_into_proposal and assigns it to Zones in one Undo " \
                    "step; the programs feature now requires ph_composer.library. programs.zones answers every " \
                    "Dwelling (dwellings, as programs.dwellings answers them, each with its floor_area_m2 and " \
                    "icfa_m2), each Zone's dwelling_units and missing (why each null people, lighting_w or " \
                    "ventilation_m3h is unknown), and each Building Segment's sums for its heading row." },
      { "minor" => 83, "date" => "2026-11-20",
        "change" => "The Program export. Four export sections, programs.export.rooms, schedules, program_types and " \
                    "set_points, write each exported Zone's ProgramType, People counts, Dwelling and Equipment Set " \
                    "devices and each Building Segment's set points; the programs.zone_assignment and " \
                    "programs.segment extensions are now required, claimed by programs.export.rooms. " \
                    "programs.export_preflight is new, with codes programs.value_missing, " \
                    "programs.set_points_inverted, programs.rule_without_dwelling, programs.counts_missing, " \
                    "programs.equipment_set_non_residential and programs.text_left_out, and the view command " \
                    "programs.locate opens the Zones / Programs view with Zones checked. The Spaces export " \
                    "projection adds each Zone's floor_area_m2 and weighted_area_m2; the certification export " \
                    "section registers its records as its projection." },
      { "minor" => 84, "date" => "2026-11-20",
        "change" => "The Programs tab's reads and a delete with a replacement. programs.delete and " \
                    "equipment_sets.delete with a replacement_id move every Zone assignment and Building Segment " \
                    "setting naming the record to the replacement, through ph_composer.zones.stage_extension, in " \
                    "the same Undo step, and refuse as a Zone write does (target.locked, " \
                    "target.shared_definition). The snapshot sections ph_composer.programs.programs, schedules and " \
                    "equipment_sets carry each collection's all read. A programs.list and programs.all row adds " \
                    "missing: each value its ProgramType would lack, by load and field, as the export preflight " \
                    "reports it." },
      { "minor" => 85, "date" => "2026-11-21",
        "change" => "A Schedule's profile (programs.schedules.profile and each schedules row's profile) adds " \
                    "weekdays, the days its operating day applies on, Monday first. An " \
                    "equipment_sets.device_types field adds applies_when where it means something only under " \
                    "another field's values: a clothes dryer's gas_consumption and gas_efficiency_factor, under " \
                    "dryer_type gas_exhaust_air." },
      { "minor" => 86, "date" => "2026-11-21",
        "change" => "ph_composer.zones.save_segment_settings also emits ph_composer.zones.segment_settings_saving, " \
                    "before it stages the payloads, with building_segment_id and extension_payloads; a Segment's " \
                    "occupancy settings naming an unwritten default Program or Equipment Set store it in the same " \
                    "step." },
      { "minor" => 87, "date" => "2026-11-23",
        "change" => "The ph_composer.mechanical feature and its Ventilator kind (ph_composer.mechanical.ventilator, " \
                    "vnt_). ph_composer.mechanical.ventilators.create, update, duplicate and delete are new, with " \
                    "the reads ventilators.list and ventilators.all, whose rows carry export_ready and " \
                    "export_blockers, and the snapshot section ph_composer.mechanical.ventilators." }
    ].freeze
    # A mutation's `request` envelope.
    REQUEST_SCHEMA = {
      "type" => "object", "additionalProperties" => false, "required" => %w[sequence expected_revision],
      "properties" => {
        "sequence" => { "type" => "integer", "minimum" => 1,
                        "description" => "This caller's mutation count from 1; a retry repeats it." },
        "expected_revision" => { "type" => "integer", "description" => "The revision the caller last read." },
        "proposal_digest" => { "type" => %w[string null], "description" => "From a preview of the same change." }
      }
    }.freeze

    module_function

    # Versions, open Model sessions and everything registered, by name. Full schemas come from
    # `describe`, so discovery stays small however many operations are installed. `common_refusals`
    # holds the codes every operation of a kind can answer, once (shell/refusals.rb). Like `describe`,
    # it answers with a copy: a caller that edits what it was given changes nothing registered.
    def discover
      registry = Registry.current
      DeepCopy.call(
        "api" => { "major" => MAJOR, "minor" => MINOR },
        "schemas" => { "outcome" => Outcome::SCHEMA, "request" => REQUEST_SCHEMA },
        "extension" => { "id" => EXTENSION_ID, "version" => VERSION },
        "contract_versions" => [Declarations::CONTRACT_VERSION],
        "capabilities" => CallerRegistry::CAPABILITIES,
        "common_refusals" => Refusals::COMMON,
        "refusal_documentation" =>
          "https://github.com/ph-composer/ph-composer-skp/blob/main/context/CONTRACTS.md#outcomes-and-codes",
        "tasks" => { "export" => { "preflight" => "export_preflight", "start" => "start_export",
                                   "status" => "export_status", "cancel" => "cancel_export",
                                   "latest" => "latest_export", "retention_limit" => Export::Tasks::LIMIT,
                                   "retention_seconds" => Export::Tasks::RETENTION_SECONDS } },
        "sessions" => Sessions.all.map { |session| session_summary(session) },
        "features" => registry.features.values.map do |feature|
          { "id" => feature.id, "contract_version" => feature.contract_version, "requires" => feature.requires }
        end,
        "queries" => registry.queries.values.map { |query| summary(query) },
        "view_commands" => registry.view_commands.values.map { |command| summary(command) },
        "setup_commands" => registry.setup_commands.values.map { |command| summary(command) },
        "file_exports" => registry.file_exports.values.map { |command| summary(command) },
        "actions" => registry.actions.values.map do |action|
          summary(action).merge("side_effects" => action.side_effects)
        end,
        # Steps an action of a dependent feature composes into its own proposal; no client calls one.
        "participants" => registry.proposal_participants.values.map { |participant| summary(participant) },
        "record_kinds" => registry.record_kinds.values.map do |kind|
          { "id" => kind.id, "owner" => registry.owner_of(kind.id), "label" => kind.label,
            "schema_version" => kind.schema_version }
        end,
        "reference_targets" => registry.reference_targets.values.map do |target|
          { "id" => target.id, "owner" => registry.owner_of(target.id), "label" => target.label }
        end,
        "extensions" => registry.extensions.values.map do |extension|
          { "namespace" => extension.namespace, "owner" => registry.owner_of(extension.namespace),
            "schema_version" => extension.schema_version, "export_relevance" => extension.export_relevance }
        end,
        "library_kinds" => registry.library_kinds.values.map { |kind| Library::KindDescriptor.summary(kind) },
        "snapshot_sections" => registry.snapshot_sections.values.map { |section| section.name }
      )
    end

    # The full declaration of one registered query, action, view command, setup command, file export,
    # record kind, entity kind, library kind or extension namespace, or of one export task method, or nil
    # when none has the name. The schemas are copies; validation keeps its own.
    def describe(name:)
      registry = Registry.current
      if (operation = registry.queries[name] || registry.actions[name] || registry.view_commands[name] ||
                      registry.setup_commands[name] || registry.file_exports[name] ||
                      registry.proposal_participants[name])
        return DeepCopy.call(operation_description(registry, operation))
      end

      if (task = Export::TaskContract.describe(name))
        return task
      end

      # A catalog kind and an entity-owned target describe themselves the same way (Records::Descriptor).
      if (target = registry.reference_targets[name])
        return DeepCopy.call({ "kind" => "reference_target", "owner" => registry.owner_of(name) }
                               .merge(target.descriptor.to_h))
      end

      if (kind = registry.record_kinds[name])
        return DeepCopy.call({ "kind" => "record_kind", "owner" => registry.owner_of(name) }
                               .merge(kind.descriptor.to_h))
      end

      described_contribution(registry, name)
    end

    # A library kind by its registered name, or an installed extension by its namespace.
    def described_contribution(registry, name)
      if (library_kind = registry.library_kinds[name])
        return DeepCopy.call(Library::KindDescriptor.call(library_kind))
      end

      extension = registry.extensions[name]
      extension && DeepCopy.call({ "kind" => "extension", "owner" => registry.owner_of(name) }
                                   .merge(extension.descriptor))
    end

    # Issues a caller handle for an open Model session and returns the context to call with. This is
    # the trusted in-process entry; a future external adapter must authenticate before calling it.
    # `view` grants the viewport-state commands: selection, camera and the active Colour-by mode. It is
    # separate from `read` because a read never moves either (context/AGENT_INTERFACE.md), and separate
    # from `model_write` because nothing it does reaches the SKP. `setup` grants the session- and
    # machine-state commands, such as adding a library on this machine; like `export`, it is never in
    # the default set and is granted explicitly.
    def connect(session_id:, capabilities: %w[read view model_write])
      session = Sessions.find(session_id)
      raise CodedError.new("session.unknown", "That Model session is closed or was never opened.") unless session

      OperationContext.new(:api_major => MAJOR, :session_id => session.id,
                           :caller => session.callers.issue(capabilities)).freeze
    end

    def query(context:, name:, params: {})
      Dispatch.new.query(context, name, params)
    end

    # Changes what the host shows and never the Model, so it takes no request: see Declarations::ViewCommand.
    def view(context:, name:, params: {})
      Dispatch.new.view(context, name, params)
    end

    # Changes session or machine state and never the Model: see Declarations::SetupCommand.
    def setup(context:, name:, params: {})
      Dispatch.new.setup(context, name, params)
    end

    def export_file(context:, name:, params: {})
      Dispatch.new.file_export(context, name, params)
    end

    # `within`, a byte budget, answers a larger completed preview compact: its proposal_digest, revision and
    # each part's size and digest, the parts themselves read with preview_part.
    def preview(context:, name:, params: {}, within: nil)
      outcome = Dispatch.new.preview(context, name, params)
      within ? PreviewParts.compact(outcome, within, -> { Dispatch.new.preview(context, name, params) }) : outcome
    end

    # One part of a preview (`value`, `affected` or `findings`) as canonical JSON text in fragments, the
    # preview run again for each (PreviewParts.read); `cursor` is the previous fragment's next_cursor.
    def preview_part(context:, name:, part:, params: {}, cursor: nil)
      outcome = Dispatch.new.preview(context, name, params)
      return outcome unless outcome["status"] == "completed"

      PreviewParts.read(Sessions.find(context.session_id), outcome, name, params, part, cursor)
    end

    # `request` is `{"sequence" => n, "expected_revision" => r}`: `n` counts this caller's mutations
    # from 1 and a retry repeats it; `r` is the revision the caller last read.
    def invoke(context:, name:, params:, request:)
      Dispatch.new.invoke(context, name, params, request)
    end

    def outcome(context:, request:)
      Dispatch.new.outcome(context, request)
    end

    # This caller's retained change outcomes, newest first, a bounded page at a time: what each change was and
    # how it ended, never its value or params. `keys`, the caller's own names for its sequences
    # (sequence => key), come back on their rows as idempotency_key.
    def outcomes(context:, limit: nil, cursor: nil, keys: {})
      Dispatch.new.outcomes(context, { "limit" => limit, "cursor" => cursor }.compact, keys)
    end

    # `location` is `{"id" => ..., "replace" => true, "expected_destination" => ...}`: a destination the
    # user approved, never a path (ph_composer.locations.list). `expected_revision`, the revision the caller
    # last read, refuses revision.stale when the Model is at another one (Export::Tasks#start).
    def start_export(context:, location:, expected_revision: nil)
      Dispatch.new.export_task(context, :start, :location => location, :expected_revision => expected_revision)
    end

    # `location`, an approved destination's id, adds what that destination holds to the result. `compact`
    # counts the findings and repairs in place of the lists; `part` pages one of them, filtered by `owner`,
    # `codes`, `blocks_export` or `object_id`, and `row` reads one row whole (Export::TaskContract).
    def export_preflight(context:, location: nil, compact: nil, part: nil, owner: nil, codes: nil,
                         blocks_export: nil, object_id: nil, row: nil, limit: nil, cursor: nil)
      options = { "compact" => compact, "part" => part, "owner" => owner, "codes" => codes,
                  "blocks_export" => blocks_export, "object_id" => object_id, "row" => row, "limit" => limit,
                  "cursor" => cursor }
      Dispatch.new.export_preflight(context, location, options)
    end

    # `compact` leaves the findings, result and report out of the outcome; once the task ended, `part` reads
    # what it kept: a page of `findings` (filtered by `codes`, `blocks_export` or `object_id`, or one by
    # `row`), or the `report` or `result` in fragments.
    def export_status(context:, task_id:, compact: nil, part: nil, codes: nil, blocks_export: nil, object_id: nil,
                      row: nil, limit: nil, cursor: nil)
      options = { "compact" => compact, "part" => part, "codes" => codes, "blocks_export" => blocks_export,
                  "object_id" => object_id, "row" => row, "limit" => limit, "cursor" => cursor }
      Dispatch.new.export_task(context, :status, :task_id => task_id, :options => options)
    end

    def cancel_export(context:, task_id:)
      Dispatch.new.export_task(context, :cancel, :task_id => task_id)
    end

    def latest_export(context:, compact: nil)
      Dispatch.new.export_task(context, :latest, :options => { "compact" => compact })
    end

    def session_summary(session)
      {
        "id" => session.id, "revision" => session.revision, "file_name" => File.basename(session.model.path.to_s),
        "active" => session.model.equal?(Sketchup.active_model),
        "busy" => !(session.busy_reason || session.gesture_reason).nil?
      }
    end

    def summary(operation)
      { "name" => operation.name, "owner" => operation.owner, "description" => operation.description }
    end

    # `refuses` is the operation's effective refusal codes, its own and those of the participants it
    # calls; `common_refusal_sets` names the sets of `discover`'s `common_refusals` it answers as well.
    def operation_description(registry, operation)
      kind = operation_kind(operation)
      {
        "kind" => kind, "capability" => kind && Declarations.capability_of(operation, kind),
        "name" => operation.name, "owner" => operation.owner, "description" => operation.description,
        "params" => operation.params, "result" => operation.result, "examples" => operation.examples,
        "refuses" => Refusals.declared(operation, registry).sort.map { |code| refusal(registry, code) },
        "common_refusal_sets" => Refusals.common_sets(operation)
      }.merge(
        operation.is_a?(Declarations::Action) ? { "preview_capability" => Declarations::PREVIEW_CAPABILITY,
                                                  "side_effects" => operation.side_effects,
                                                  "confirmation" => operation.confirmation,
                                                  "transitions" => Array(operation.transitions) } : {}
      ).merge(operation.respond_to?(:approval) && operation.approval ? { "approval" => operation.approval.to_h } : {})
        .merge(operation.respond_to?(:participants) ? { "participants" => operation.participants } : {})
        .merge(described_terms(operation))
    end

    # The optional terms a declaration publishes only when it has them.
    def described_terms(operation)
      terms = {}
      view = operation.is_a?(Declarations::ViewCommand)
      terms["side_effects"] = operation.side_effects if view && operation.side_effects
      preconditions = operation.respond_to?(:preconditions) ? Array(operation.preconditions) : []
      terms["preconditions"] = preconditions unless preconditions.empty?
      terms["response"] = operation.response if operation.is_a?(Declarations::Query) && operation.response
      terms["while_busy"] = true if operation.is_a?(Declarations::Query) && operation.while_busy
      terms
    end

    # A feature's code carries its owner and description; a foundation code is described in
    # context/CONTRACTS.md, "Outcomes and codes".
    def refusal(registry, code)
      declared = registry.codes[code]
      return { "code" => code, "owner" => "foundation", "description" => nil } unless declared

      { "code" => code, "owner" => declared.owner, "description" => declared.description }
    end

    def operation_kind(operation)
      return "participant" if operation.is_a?(Declarations::ProposalParticipant)

      Declarations::OPERATION_KINDS.fetch(operation.class)
    end
    private_class_method :session_summary, :summary, :operation_description, :refusal, :operation_kind,
                         :described_terms, :described_contribution
  end
end
