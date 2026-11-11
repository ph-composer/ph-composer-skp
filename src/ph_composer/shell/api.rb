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
    MINOR = 43
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
                    "releases its idempotency_key for the retry." }
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

    # `location` is `{"id" => ..., "replace" => true, "expected_destination" => ...}`: a destination the
    # user approved, never a path (ph_composer.locations.list).
    def start_export(context:, location:)
      Dispatch.new.export_task(context, :start, :location => location)
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
