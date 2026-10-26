/* A stand-in host for the preview page and the editor tests: it answers the panel's messages the way
   shell/panel.rb does, for the example feature's parts only. It keeps one synthetic Model session with a
   revision, refuses a stale revision or a changed expected value with nothing written, and remembers
   display preferences. It is not the contract: tests/panel_test.rb checks the real host.

   PhComposerPreviewHost.install(window, { parts, locale, decimal }) sets `window.sketchup` and returns the
   host, whose `sent` lists every message the page sent. */
(function (global) {
  "use strict";

  var PARTS = "example.foundation.parts";
  var LEGEND = "ph_composer.colour_by.legend";
  var PALETTE = "ph_composer.zones.faces.palette";
  var ATTACHED = "ph_composer.zones.faces.attached_zone.list";
  var ZONES = "ph_composer.zones.overview";
  var FACES = "ph_composer.zones.faces.faces";
  var SETTINGS = "ph_composer.zones.settings";
  var MATERIALS = "ph_composer.assemblies.materials";
  var ASSEMBLIES = "ph_composer.assemblies.assemblies";
  var TB = "ph_composer.thermal_bridges.";
  var NOTHING_WRITTEN = "Nothing was written.";

  function Host(window, options) {
    var settings = options || {};
    this.window = window;
    this.sent = [];
    this.libraryProviders = JSON.parse(JSON.stringify(settings.libraryProviders || []));
    this.libraryCatalogs = JSON.parse(JSON.stringify(settings.libraryCatalogs || {}));
    this.libraryGenerations = {}; this.libraryFailures = {};
    this.librarySetupState = settings.librarySetupState || "readable";
    this.approvedLocations = JSON.parse(JSON.stringify(settings.approvedLocations || [
      { id: "location_PreviewDest01", kind: "save_file", label: "Library export", use: "reusable",
        approved_at: "2026-10-01T09:00:00Z", last_used_at: "2026-10-02T15:30:00Z", available: true },
      { id: "location_PreviewFold01", kind: "open_folder", label: "Office library folder", use: "single",
        approved_at: "2026-10-02T10:00:00Z", last_used_at: null, available: false }]));
    this.windows = JSON.parse(JSON.stringify(settings.windows || {}));
    this.session = "preview-session";
    this.revision = 1;
    this.sequence = 0;
    this.parts = (settings.parts || []).map(function (part) { return JSON.parse(JSON.stringify(part)); });
    this.zones = JSON.parse(JSON.stringify(settings.zones || []));
    this.zoneOptions = JSON.parse(JSON.stringify(settings.zoneOptions || {
      building_segments: [], levels: [], default_segment_id: null, adoption: { required: false, sources: [] }
    }));
    this.faces = JSON.parse(JSON.stringify(settings.faces || []));
    // The Spaces read: the fixture's, or empty (the section is always published, as the host does).
    this.spaces = settings.spaces ? JSON.parse(JSON.stringify(settings.spaces)) : null;
    this.markTool = { active: false, weighting_factor: 1, gesture_limit: 250 };
    this.readoutsOn = [];
    this.labelOptions = { weighted_area: false, net_volume: false, airflows: false };
    this.createReview = settings.createReview ? JSON.parse(JSON.stringify(settings.createReview)) : null;
    this.selectedFaces = JSON.parse(JSON.stringify(settings.selectedFaces || []));
    this.makeZone = settings.makeZone || null;
    this.zoneSettings = { suggest_on_make: true, roof_angle_deg: 60, floor_angle_deg: 130 };
    this.colourBy = { mode: null, isolated: null };
    this.palette = { active: false, palette: {},
      face_types: ["Wall", "RoofCeiling", "Floor"],
      boundary_conditions: ["Outdoors", "Ground", "Adiabatic", "AttachedZone", "Surface"] };
    this.materials = JSON.parse(JSON.stringify(settings.materials || { records: [], unreadable: [], categories: [] }));
    this.assemblies = JSON.parse(JSON.stringify(settings.assemblies || { records: [], unreadable: [] }));
    this.attachedZones = JSON.parse(JSON.stringify(settings.attachedZones || []));
    this.thermalBridges = JSON.parse(JSON.stringify(settings.thermalBridges ||
      { types: [], selected: [], runs: [], edgeFindings: [] }));
    this.preferences = { unit_system: settings.unitSystem || "SI", dimension_formats: {},
      number_format: { decimal: settings.decimal || ".", locale: settings.locale || "en-US" } };
  }

  /* Each Zone row with the totals the host's Zones read publishes: its Faces' area, and the part with no values. */
  Host.prototype.zoneRows = function () {
    var faces = this.faces;
    return JSON.parse(JSON.stringify(this.zones)).map(function (zone) {
      var own = faces.filter(function (face) {
        return JSON.stringify(face.reference.zone_path) === JSON.stringify(zone.reference.zone_path);
      });
      zone.face_area_m2 = own.reduce(function (sum, face) { return sum + face.area_m2; }, 0);
      zone.unclassified_face_area_m2 = own.reduce(function (sum, face) {
        return sum + (Object.keys(face.values || {}).length ? 0 : face.area_m2);
      }, 0);
      return zone;
    });
  };

  Host.prototype.publish = function (type, payload) {
    this.window.PhComposerUI.get("panel").receive({ type: type, payload: payload });
  };

  Host.prototype.snapshot = function () {
    var records = this.parts.map(function (part) {
      return { kind: "example.foundation.part", id: part.id, values: { label: part.label, length_mm: part.length_mm } };
    });
    this.publish("panel.snapshot", {
      product: "PH-Composer", version: "preview", session: this.session, revision: this.revision,
      file_name: "preview.skp", edit_path: [], preferences: JSON.parse(JSON.stringify(this.preferences)),
      sections: {
        ["ph_composer.library.provider_catalogs"]: { status: "completed", value: this.libraryMetadata() },
        ["ph_composer.library.provider_setup"]: { status: "completed", value: { state: this.librarySetupState } },
        ["ph_composer.locations.approved"]: { status: "completed",
          value: { state: "readable", locations: JSON.parse(JSON.stringify(this.approvedLocations)) } },
        [SETTINGS]: { status: "completed", code: "ok", revision: this.revision,
          value: JSON.parse(JSON.stringify(this.zoneSettings)) },
        [PARTS]: { status: "completed", code: "ok", revision: this.revision,
          value: { records: records, units: { length_mm: "mm" }, next_cursor: null, total: records.length } },
        ["ph_composer.zones.options"]: { status: "completed", value: JSON.parse(JSON.stringify(this.zoneOptions)) },
        [ZONES]: { status: "completed", code: "ok", revision: this.revision,
          value: { zones: this.zoneRows(), make_zone: this.makeZone,
            units: { ground_depth_mm: "mm", face_area_m2: "m2", unclassified_face_area_m2: "m2" } } },
        [FACES]: { status: "completed", code: "ok", revision: this.revision,
          value: { faces: JSON.parse(JSON.stringify(this.faces)), units: { area_m2: "m2" } } },
        ["ph_composer.zones.faces.selected"]: { status: "completed", value: {
          faces: this.selectedFaces, targets: this.faces.filter(function (face) {
            return this.selectedFaces.some(function (reference) {
              return JSON.stringify(reference) === JSON.stringify(face.reference);
            });
          }, this).map(function (face) { return { reference: face.reference, expected_values: face.values }; }) } },
        ["ph_composer.zones.faces.assemblies"]: { status: "completed", value: {
          assemblies: this.assemblies.records.map(function (record) { return { id: record.id,
            name: record.values.name, type: record.values.type || null, color: record.values.color }; }) } },
        ["ph_composer.zones.faces.usage"]: { status: "completed", value: {
          faces: this.faces.map(function (face) {
            var zone = this.zones.filter(function (candidate) { return candidate.id === face.reference.zone_id; })[0];
            return Object.assign({ zone_name: zone ? zone.values.name : "Zone" }, face);
          }, this), assembly_usage: this.usage() } },
        [LEGEND]: { status: "completed", code: "ok", revision: this.revision, value: this.legend() },
        [PALETTE]: { status: "completed", code: "ok", revision: this.revision,
          value: JSON.parse(JSON.stringify(this.palette)) },
        ["ph_composer.windows.types"]: { status: "completed", value: this.windowTypes() },
        ["ph_composer.windows.unit_areas"]: { status: "completed", value: JSON.parse(JSON.stringify(
          this.windows.unit_areas || { faces: [], unhosted_units: [] })) },
        ["ph_composer.windows.units"]: { status: "completed", value: JSON.parse(JSON.stringify(this.windows.units ||
          { units: [] })) },
        ["ph_composer.windows.place_tool"]: { status: "completed", value: JSON.parse(JSON.stringify(
          this.windows.place_tool || { active: false, type_id: null, anchor: "sill_center", host: null })) },
        ["ph_composer.windows.frames"]: { status: "completed",
          value: JSON.parse(JSON.stringify(this.windows.frames || { records: [] })) },
        ["ph_composer.windows.glazings"]: { status: "completed",
          value: JSON.parse(JSON.stringify(this.windows.glazings || { records: [] })) },
        ["ph_composer.windows.psi_install_types"]: { status: "completed",
          value: JSON.parse(JSON.stringify(this.windows.psi_install_types || { records: [] })) },
        ["ph_composer.windows.settings"]: { status: "completed",
          value: JSON.parse(JSON.stringify(this.windows.settings || {
          default_psi_install_id: null, default_install_depth_m: 0 })) },
        ["ph_composer.spaces.spaces"]: { status: "completed", value: JSON.parse(JSON.stringify(this.spaces || {
          spaces: [], zones: [], findings: [], units: { area: "m2", height: "m", volume: "m3", airflow: "m3/h" } })) },
        ["ph_composer.spaces.mark_tool"]: { status: "completed", value: JSON.parse(JSON.stringify(this.markTool)) },
        ["ph_composer.spaces.label_options"]: { status: "completed",
          value: JSON.parse(JSON.stringify(this.labelOptions)) },
        ["ph_composer.spaces.create_review"]: { status: "completed", value: JSON.parse(JSON.stringify(
          this.createReview || { token: null, revision: null, zone: null, zone_name: "", accepted: [],
            left_out: [] })) },
        [MATERIALS]: { status: "completed", value: JSON.parse(JSON.stringify(this.materials)) },
        [ASSEMBLIES]: { status: "completed", value: JSON.parse(JSON.stringify(this.assemblies)) },
        [TB + "types"]: { status: "completed", value: { records: JSON.parse(JSON.stringify(
          this.thermalBridges.types)), unreadable: [] } },
        [TB + "edges.selected"]: { status: "completed", value: { edges: JSON.parse(JSON.stringify(
          this.thermalBridges.selected)), ignored: [], ignored_total: 0 } },
        [ATTACHED]: { status: "completed", code: "ok", revision: this.revision,
          value: { records: JSON.parse(JSON.stringify(this.attachedZones)), next_cursor: null,
            total: this.attachedZones.length } }
      }
    });
  };

  /* The legend the shared service would build, counted from the preview's own Faces so the rows move
     when the panel classifies one. */
  Host.prototype.usage = function () {
    var rows = Object.create(null);
    this.faces.forEach(function (face) {
      var id = face.values.assembly_id;
      if (!id) return;
      var row = rows[id] || (rows[id] = { assembly_id: id, face_count: 0, gross_area_m2: 0, faces: [] });
      row.face_count += 1; row.gross_area_m2 += face.area_m2; row.faces.push(face.reference);
    });
    return Object.keys(rows).map(function (id) { return rows[id]; });
  };

  Host.prototype.legend = function () {
    var isolated = this.colourBy.isolated, rows = [];
    var counts = {};
    if (this.colourBy.mode) {
      this.faces.forEach(function (face) {
        var value = face.values.face_type || null;
        var state = value ? (face.state === "incomplete" ? "incomplete" : "classified") : "unclassified";
        var key = value + "|" + state;
        counts[key] = counts[key] || { value: value, label: value || "Unclassified", state: state, count: 0,
          colour: value ? [230, 180, 60] : [130, 130, 130] };
        counts[key].count += 1;
      });
      rows = Object.keys(counts).map(function (key) {
        var row = counts[key];
        row.isolated = Boolean(isolated && isolated.value === row.value && isolated.state === row.state);
        return row;
      });
    }
    return { mode: this.colourBy.mode, label: this.colourBy.mode ? "Face type" : null,
      entity_kind: this.colourBy.mode ? "face" : null, isolated: isolated, rows: rows,
      filter_paths: this.colourBy.filter_paths || null,
      modes: [{ name: "ph_composer.zones.faces.by_face_type", label: "Face type", entity_kind: "face", group: null },
        { name: "ph_composer.zones.by_zone", label: "Zone", entity_kind: "zone", group: null },
        { name: "ph_composer.zones.faces.by_assembly", label: "Assembly", entity_kind: "face", group: "construction" },
        { name: "ph_composer.windows.by_type", label: "Window Type", entity_kind: "window_unit",
          group: "construction" },
        { name: "ph_composer.spaces.by_space", label: "Space", entity_kind: "volume", group: null },
        { name: "ph_composer.spaces.by_ventilation", label: "Ventilation", entity_kind: "volume",
          group: "ventilation" },
        { name: "ph_composer.spaces.by_weighting_factor", label: "Weighting factor", entity_kind: "volume",
          group: null },
        { name: "ph_composer.spaces.by_height", label: "Height", entity_kind: "volume", group: null },
        { name: "ph_composer.thermal_bridges.by_type", label: "Thermal bridges", entity_kind: "edge", group: null }],
      readouts: [["ph_composer.spaces.labels", "Space labels", false],
        ["ph_composer.spaces.selection_totals", "Spaces selection totals", true]].map(function (readout) {
        return { name: readout[0], label: readout[1], selection: readout[2],
          on: this.readoutsOn.indexOf(readout[0]) >= 0 };
      }, this) };
  };

  Host.prototype.receive = function (message) {
    this.sent.push(message);
    if (message.type === "panel.ready") this.snapshot();
    if (message.type === "action.invoke") this.invoke(message.payload);
    if (message.type === "query.invoke") {
      if (message.payload.name.indexOf(TB) === 0) this.scheduleQuery(message.payload);
      else this.libraryQuery(message.payload);
    }
    if (message.type === "file_export.invoke") this.publish("file_export.result", {
      request_id: message.payload.request_id, session: message.payload.session,
      outcome: refused("export.unavailable", "File writes are unavailable in this browser preview.", this.revision)
    });
    if (message.type === "view.invoke") this.viewCommand(message.payload);
    if (message.type === "setup.invoke") this.librarySetup(message.payload);
    if (message.type === "preferences.set") this.setPreference(message.payload);
    if (message.type === "export.start") this.exportStart(message.payload);
    if (message.type === "export.preflight" || message.type === "export.latest") {
      var value = message.type === "export.latest" ? null : { repairs: [], findings: [{
        code: "preview.export_unavailable", blocks_export: true,
        message: "Export writes are unavailable in this browser preview."
      }] };
      this.publish("export.result", { request_id: message.payload.request_id, session: message.payload.session,
        outcome: { status: "completed", value: value, findings: [], revision: this.revision } });
    }
  };

  /* This development preview has no filesystem or runtime; it never performs an export. */
  Host.prototype.exportStart = function (payload) {
    this.publish("export.result", { request_id: payload.request_id, session: payload.session,
      outcome: refused("export.unavailable", "No exporter is installed in this build, so nothing was written.",
        this.revision) });
  };

  /* A viewport-state command: nothing to write and no revision to guard, so the preview answers that it
     ran and leaves its Model alone. There is no viewport here to move. */
  Host.prototype.viewCommand = function (payload) {
    var outcome;
    if (payload.session !== this.session) {
      outcome = refused("session.inactive", "The panel now shows a different Model.", null);
    } else {
      if (payload.name === "ph_composer.colour_by.activate") {
        this.colourBy = { mode: payload.params.mode, isolated: null };
      }
      if (payload.name === "ph_composer.colour_by.filter") {
        this.colourBy.filter_paths = JSON.parse(JSON.stringify(payload.params.paths));
        this.colourBy.isolated = null;
      }
      if (payload.name === "ph_composer.colour_by.isolate") this.colourBy.isolated = payload.params.row || null;
      if (payload.name === "ph_composer.zones.faces.choose") {
        this.palette.active = true;
        if (payload.params.value) {
          var paintModes = { face_type: "ph_composer.zones.faces.by_face_type",
            boundary_condition: "ph_composer.zones.faces.by_boundary_condition",
            attached_zone_id: "ph_composer.zones.faces.by_boundary_condition",
            assembly_id: "ph_composer.zones.faces.by_assembly" };
          this.colourBy.mode = paintModes[payload.params.field];
          this.colourBy.isolated = null;
        }
        if (payload.params.reset) this.palette.palette = {};
        if (payload.params.value === null) delete this.palette.palette[payload.params.field];
        else this.palette.palette[payload.params.field] = payload.params.value;
        if (payload.params.field === "attached_zone_id") {
          if (payload.params.value) this.palette.palette.boundary_condition = "AttachedZone";
          else if (this.palette.palette.boundary_condition === "AttachedZone") {
            delete this.palette.palette.boundary_condition;
          }
        }
        if (payload.params.field === "boundary_condition" && payload.params.value !== "AttachedZone") {
          delete this.palette.palette.attached_zone_id;
        }
      }
      if (payload.name === "ph_composer.zones.faces.select") this.selectedFaces = payload.params.faces;
      if (payload.name === "ph_composer.zones.faces.stop_classifying") this.palette.active = false;
      if (payload.name === "ph_composer.windows.place_tool.choose") {
        this.windows.place_tool = { active: true, type_id: payload.params.type_id,
          anchor: payload.params.anchor || "sill_center", host: payload.params.host || null };
      }
      if (payload.name === "ph_composer.windows.place_tool.stop") this.windows.place_tool.active = false;
      if (payload.name === "ph_composer.windows.units.locate") this.selectedUnits = payload.params.units;
      if (payload.name === TB + "runs.locate") this.locatedEdges = payload.params.edge_paths;
      if (payload.name === "ph_composer.spaces.mark_tool.start") {
        this.markTool = { active: true, weighting_factor: payload.params.weighting_factor, gesture_limit: 250 };
        this.colourBy = { mode: "ph_composer.spaces.by_weighting_factor", isolated: null };
      }
      if (payload.name === "ph_composer.spaces.mark_tool.stop") this.markTool.active = false;
      if (payload.name === "ph_composer.colour_by.readout") {
        this.readoutsOn = this.readoutsOn.filter(function (name) { return name !== payload.params.readout; });
        if (payload.params.on) this.readoutsOn.push(payload.params.readout);
      }
      if (payload.name === "ph_composer.spaces.labels.set_options") {
        Object.assign(this.labelOptions, payload.params);
      }
      if (payload.name === "ph_composer.spaces.create_review.close" && this.createReview &&
        this.createReview.token === payload.params.token) this.createReview = null;
      outcome = { status: "completed", code: "ok", message: "Done.", effect: "none", revision: this.revision,
        value: {}, affected: [], findings: [], detail: null };
      this.snapshot();
    }
    this.publish("view.result", { request_id: payload.request_id, session: payload.session, outcome: outcome });
  };

  /* Height from solid's two reads, as SketchUp would answer them with a 36 m3 solid selected over a 12 m2 floor. */
  Host.prototype.spacesQuery = function (payload) {
    var value = payload.name === "ph_composer.spaces.selected_solid" ? { solid: [100, 101, 900] } :
      { height_m: 3, solid_volume_m3: 36, net_floor_area_m2: 12, current_height_m: 2.5 };
    this.publish("query.result", { request_id: payload.request_id, session: payload.session,
      outcome: { status: "completed", code: "ok", revision: this.revision, value: value } });
  };

  /* The schedule read, answered on the next turn as the host does: the fixture's runs with each type's current
     name, group and psi-value, and totals over them. Synthetic; Ruby builds the runs from the Model. */
  Host.prototype.scheduleQuery = function (payload) {
    var host = this, data = this.thermalBridges;
    this.window.setTimeout(function () {
      var runs = data.runs.map(function (run) {
        var type = data.types.filter(function (entry) { return entry.id === run.type_id; })[0];
        var psi = type ? type.values.psi_w_mk : null;
        return Object.assign({}, JSON.parse(JSON.stringify(run)), { type_name: type ? type.values.name : null,
          group: type ? type.values.group : null, psi_w_mk: psi,
          heat_loss_w_k: psi === null ? null : Math.round(psi * run.length_m * run.quantity * 1000) / 1000 });
      });
      var byType = data.types.map(function (type) {
        var own = runs.filter(function (run) { return run.type_id === type.id; });
        return { type_id: type.id, type_name: type.values.name, group: type.values.group, run_count: own.length,
          edge_count: own.reduce(function (sum, run) { return sum + run.edge_paths.length; }, 0),
          length_m: own.reduce(function (sum, run) { return sum + run.length_m; }, 0),
          heat_loss_w_k: own.reduce(function (sum, run) { return sum + (run.heat_loss_w_k || 0); }, 0) };
      }).filter(function (row) { return row.run_count; });
      var byGroup = ["15-Ambient", "16-Perimeter", "17-FS/BC"].map(function (group) {
        return { group: group, heat_loss_w_k: runs.filter(function (run) { return run.group === group; })
          .reduce(function (sum, run) { return sum + (run.heat_loss_w_k || 0); }, 0) };
      });
      host.publish("query.result", { request_id: payload.request_id, session: payload.session,
        outcome: { status: "completed", code: "ok", revision: host.revision, value: { runs: runs,
          edge_findings: data.edgeFindings.map(function (finding) {
            return { path: finding.path, code: finding.code, message: finding.message,
              blocks_export: finding.blocks_export, locate: finding.locate };
          }), edge_finding_total: data.edgeFindings.length, unreadable: [], unreadable_total: 0,
          totals: { by_type: byType, by_group: byGroup, run_count: runs.length,
            heat_loss_w_k: byGroup.reduce(function (sum, row) { return sum + row.heat_loss_w_k; }, 0) },
          units: { length_m: "m", psi_w_mk: "W/mK", heat_loss_w_k: "W/K" } } } });
    }, 0);
  };

  /* Thermal Bridge Type records and Edge assignment, kept to what the tab sends. Synthetic outcomes. */
  Host.prototype.thermalBridgeAction = function (payload) {
    var data = this.thermalBridges, params = payload.params, name = payload.name.slice(TB.length), id;
    var target = data.types.filter(function (record) { return record.id === params.id; })[0];
    function copy(value) { return JSON.parse(JSON.stringify(value)); }
    if (params.id && !target) return refused("target.not_found", "That type is unavailable.", this.revision);
    if (params.expected_values && Object.keys(params.expected_values).some(function (field) {
      var current = target.values[field];
      return JSON.stringify(current === undefined ? null : current) !== JSON.stringify(params.expected_values[field]);
    })) return refused("target.changed", "The type changed. " + NOTHING_WRITTEN, this.revision);
    if (name === "types.create" || name === "types.duplicate") {
      id = "tbt_preview" + String(++this.sequence).padStart(5, "0");
      var values = name === "types.create" ? Object.assign({ notes: "", datasheet_links: [], psi_w_mk: null,
        group: "15-Ambient" }, copy(params.values)) : Object.assign(copy(target.values),
        { name: params.name || target.values.name + " (copy)" });
      data.types.push({ id: id, kind: TB + "type", schema_version: 1, user_data: {}, extension_data: {},
        findings: [], values: values, display: { color: "#8a6fb0" }, export_ready: values.psi_w_mk !== null,
        export_blockers: [] });
    } else if (name === "types.update") {
      Object.keys(params.values).forEach(function (field) { target.values[field] = params.values[field]; });
    } else if (name === "types.delete") {
      data.runs.forEach(function (run) {
        if (run.type_id === target.id && params.replacement_id) run.type_id = params.replacement_id;
      });
      data.runs = data.runs.filter(function (run) { return run.type_id !== target.id; });
      data.types.splice(data.types.indexOf(target), 1);
    } else if (name === "edges.assign" || name === "edges.clear") {
      params.targets.forEach(function (row) {
        data.selected.forEach(function (edge) {
          if (JSON.stringify(edge.reference) !== JSON.stringify(row.reference)) return;
          edge.values = name === "edges.clear" ? {} : { thermal_bridge_type_id: params.thermal_bridge_type_id,
            quantity: params.quantity };
        });
      });
    } else return refused("request.unknown_operation", "Unavailable fixture action.", this.revision);
    this.revision += 1;
    return { status: "completed", code: "ok", message: "Done.", effect: "committed", revision: this.revision,
      value: { id: id }, affected: [], findings: [], detail: null };
  };

  /* Synthetic Window outcomes exercise panel transport only; thermal values are fixture projections. */
  Host.prototype.windowAction = function (payload) {
    var host = this, params = payload.params, name = payload.name.replace("ph_composer.windows.", "");
    function clone(value) { return JSON.parse(JSON.stringify(value)); }
    function completed(value) { host.revision++; return { status: "completed", effect: "committed",
      revision: host.revision, value: value || {} }; }
    function matches(record, expected) {
      return record && Object.keys(expected || {}).every(function (key) {
        return JSON.stringify(record.values[key] === undefined ? null : record.values[key]) ===
          JSON.stringify(expected[key]);
      });
    }
    function emptySides() { return { top: null, right: null, bottom: null, left: null }; }
    function invalidate(record) {
      record.display = Object.assign({}, record.display, { thermal: { uw_w_m2k: null, u_effective_w_m2k: null,
        findings: ["Preview changed definition: canonical thermal results require the Ruby host."], elements: [] } });
    }
    if (name === "settings.update") {
      if (JSON.stringify(params.expected_values) !== JSON.stringify(this.windows.settings)) {
        return refused("target.changed", "Defaults changed.", this.revision);
      }
      this.windows.settings = clone(params.values); return completed(params.values);
    }
    if (name === "types.installs.save") {
      if (JSON.stringify(params.expected_settings) !== JSON.stringify(this.windows.settings) ||
        params.types.some(function (target) {
        return !matches(host.windows.types.records.filter(function (row) { return row.id === target.id; })[0],
          target.expected_values);
      })) return refused("target.changed", "The Installs baseline changed. Reopen the session.", this.revision);
      var mapping = {};
      for (var importIndex = 0; importIndex < (params.imports || []).length; importIndex++) {
        var imported = params.imports[importIndex], copied = this.windowLibraryCopy(imported.copy, true);
        if (copied.status !== "completed") return copied;
        mapping[imported.client_id] = copied.value.local_id;
      }
      params.psi_install_types.create.forEach(function (row) {
        var id = "psi_preview" + (++host.sequence); mapping[row.client_id] = id;
        host.windows.psi_install_types.records.push({ id: id, values: clone(row.values), uses: [], use_count: 0 });
      });
      params.psi_install_types.update.forEach(function (patch) {
        var row = host.windows.psi_install_types.records.filter(function (record) { return record.id === patch.id;
          })[0];
        if (row) Object.assign(row.values, patch.values);
      });
      params.types.forEach(function (patch) {
        var row = host.windows.types.records.filter(function (record) { return record.id === patch.id; })[0];
        patch.installs.forEach(function (edge) {
          var cell = row.values.elements.filter(function (element) { return element.id === edge.element_id; })[0];
          Object.keys(edge.sides).forEach(function (side) { cell.installs[side] = mapping[edge.sides[side]] ||
            edge.sides[side]; });
        }); invalidate(row);
      }); return completed({ type_ids: params.types.map(function (row) { return row.id; }) });
    }
    var parts = name.split("."), kind = parts[0], operation = parts[parts.length - 1];
    var records = (this.windows[kind] || {}).records || [];
    var row = records.filter(function (record) { return record.id === params.id; })[0];
    if (params.id && !matches(row, params.expected_values)) return refused("target.changed",
      "The definition changed.", this.revision);
    if (parts[1] === "grid") {
      var values = row.values, cell = values.elements.filter(function (entry) {
        return entry.id === params.element_id; })[0];
      if (operation === "dimension") values[params.axis][params.index] = params.value;
      else if (operation === "set_element_name") cell.name = params.name;
      else if (operation === "set_element_glazing") cell.glazing_id = params.glazing_id;
      else if (operation === "set_element_frame") cell.frames[params.side] = params.frame_id;
      else if (operation === "set_element_operation") cell.operation = clone(params.operation);
      else if (operation === "kind") values.elements.forEach(function (element) {
        if (params.ids.indexOf(element.id) < 0) return;
        element.kind = params.kind;
        if (params.kind === "empty") { element.frames = emptySides(); element.installs = emptySides();
          element.glazing_id = null; element.operation = null; }
      });
      else if (operation === "paste") {
        var source = values.elements.filter(function (entry) { return entry.id === params.source_id; })[0];
        values.elements.forEach(function (entry) { if (params.ids.indexOf(entry.id) >= 0) {
          ["frames", "installs", "operation", "glazing_id"].forEach(function (field) {
            entry[field] = clone(source[field]); });
        } });
      } else if (operation === "flip") {
        values.columns_m.reverse(); values.elements.forEach(function (entry) {
          entry.column_span = [values.columns_m.length - entry.column_span[1] - 1,
            values.columns_m.length - entry.column_span[0] - 1];
          ["frames", "installs"].forEach(function (field) {
            var left = entry[field].left; entry[field].left = entry[field].right; entry[field].right = left;
          });
        });
      } else if (operation === "merge") {
        var selected = values.elements.filter(function (entry) { return params.ids.indexOf(entry.id) >= 0; });
        var merged = clone(selected[0]);
        merged.row_span = [Math.min.apply(null, selected.map(function (entry) { return entry.row_span[0]; })),
          Math.max.apply(null, selected.map(function (entry) { return entry.row_span[1]; }))];
        merged.column_span = [Math.min.apply(null, selected.map(function (entry) { return entry.column_span[0]; })),
          Math.max.apply(null, selected.map(function (entry) { return entry.column_span[1]; }))];
        values.elements = values.elements.filter(function (entry) { return params.ids.indexOf(entry.id) < 0;
          }).concat(merged);
      } else if (operation === "split") {
        values.elements = values.elements.filter(function (entry) { return entry.id !== cell.id; });
        for (var r = cell.row_span[0]; r <= cell.row_span[1]; r++) for (var c = cell.column_span[0];
          c <= cell.column_span[1]; c++) {
          var part = clone(cell); part.id = "wel_preview" + (++host.sequence); part.row_span = [r, r];
            part.column_span = [c, c];
          values.elements.push(part);
        }
      } else if (operation === "insert") {
        var axis = params.axis, span = axis === "rows_m" ? "row_span" : "column_span", other = axis === "rows_m" ?
          "columns_m" : "rows_m";
        values[axis].splice(params.index, 0, params.value);
        values.elements.forEach(function (entry) { entry[span] = entry[span].map(function (at) {
          return at >= params.index ? at + 1 : at; }); });
        values[other].forEach(function (_value, index) {
          var element = { id: "wel_preview" + (++host.sequence), name: "New element", kind: "glazed",
            row_span: axis === "rows_m" ? [params.index, params.index] : [index, index],
            column_span: axis === "columns_m" ? [params.index, params.index] : [index, index], glazing_id: null,
            frames: emptySides(), installs: emptySides(), operation: null }; values.elements.push(element);
        });
      } else if (operation === "remove") {
        var removedSpan = params.axis === "rows_m" ? "row_span" : "column_span";
        values[params.axis].splice(params.index, 1);
        values.elements = values.elements.filter(function (entry) {
          return !(entry[removedSpan][0] === params.index && entry[removedSpan][1] === params.index);
        });
        values.elements.forEach(function (entry) { entry[removedSpan] = entry[removedSpan].map(function (at) {
          return at > params.index ? at - 1 : at;
        }); });
      }
      invalidate(row); return completed({ id: row.id });
    }
    if (operation === "update") {
      Object.keys(params.values).forEach(function (key) {
        if (params.values[key] === null) delete row.values[key]; else row.values[key] = clone(params.values[key]);
      }); if (kind === "types") invalidate(row); return completed({ id: row.id });
    }
    if (operation === "create" || operation === "duplicate") {
      var id = kind.slice(0, 3) + "_preview" + (++this.sequence);
      var created = operation === "duplicate" ? clone(row) : { id: id, values: clone(params.values), uses: [],
        use_count: 0 };
      created.id = id;
      if (operation === "duplicate") created.values.name = params.name || row.values.name + " (copy)";
      if (kind === "types") {
        if (operation === "create") { created.values.rows_m = [1.5]; created.values.columns_m = [1];
          created.values.elements = [{ id: "wel_preview" + (++host.sequence), name: "Element 1", kind: "glazed",
            row_span: [0, 0], column_span: [0, 0], frames: emptySides(), installs: emptySides(), glazing_id: null,
              operation: null }]; }
        else created.values.elements.forEach(function (entry) { entry.id = "wel_preview" + (++host.sequence); });
        created.display = { install_depth_m: host.windows.settings.default_install_depth_m }; invalidate(created);
      } records.push(created); return completed({ id: id });
    }
    if (operation === "delete") {
      if (row.use_count && !params.replacement_id) return refused("reference.used", "Choose a replacement.",
        this.revision);
      var replacement = params.replacement_id;
      if (replacement) this.windows.types.records.forEach(function (type) {
        type.values.elements.forEach(function (entry) {
        if (kind === "glazings" && entry.glazing_id === row.id) entry.glazing_id = replacement;
        ["frames", "installs"].forEach(function (field) { Object.keys(entry[field]).forEach(function (side) {
          if (entry[field][side] === row.id) entry[field][side] = replacement;
        }); });
      }); });
      records.splice(records.indexOf(row), 1); return completed({ id: row.id });
    }
    return refused("request.unknown_operation", "Window fixture does not handle this action.", this.revision);
  };

  Host.prototype.invoke = function (payload) {
    var host = this;
    function apply() {
      var outcome = host.apply(payload);
      host.snapshot();
      host.publish("action.result", { request_id: payload.request_id, session: payload.session, outcome: outcome });
    }
    if (payload.name.indexOf("ph_composer.zones.options.") === 0 ||
        payload.name.indexOf("ph_composer.windows.") === 0 ||
        payload.name.indexOf("ph_composer.assemblies.") === 0 || payload.name.indexOf(TB) === 0 ||
        payload.name.indexOf("ph_composer.zones.faces.attached_zone.") === 0) this.window.setTimeout(apply, 0);
    else apply();
  };

  Host.prototype.apply = function (payload) {
    var host = this;
    if (payload.session !== this.session) {
      return refused("session.inactive", "The panel now shows a different Model. " + NOTHING_WRITTEN, null);
    }
    if (payload.expected_revision !== this.revision) {
      return refused("revision.stale", "The Model changed since it was read. " + NOTHING_WRITTEN, this.revision);
    }
    if (payload.name.indexOf("ph_composer.windows.") === 0) return this.windowAction(payload);
    if (payload.name.indexOf(TB) === 0) return this.thermalBridgeAction(payload);
    if (payload.name === "ph_composer.library.copy") return this.libraryCopy(payload);
    if (payload.name.indexOf("ph_composer.assemblies.") === 0 ||
        payload.name.indexOf("ph_composer.zones.faces.attached_zone.") === 0) return this.inventoryAction(payload);
    if (payload.name === "ph_composer.zones.options.manage") return this.manageZoneOptions(payload.params);
    // Create Space answers that it ran; the synthetic Spaces section is not regrouped.
    if (payload.name === "ph_composer.spaces.create") {
      this.revision++;
      return { status: "completed", code: "ok", message: "Created a Space.", effect: "committed",
        revision: this.revision, value: {}, affected: [], findings: [], detail: null };
    }
    var resultValue = {};
    if (payload.name === "ph_composer.zones.faces.assign_assembly") {
      var targets = payload.params.targets, affected = targets.map(function (target) {
        return host.faces.filter(function (face) {
          return JSON.stringify(face.reference) === JSON.stringify(target.reference);
        })[0];
      });
      if (affected.some(function (face, index) {
        return !face || JSON.stringify(face.values) !== JSON.stringify(targets[index].expected_values);
      })) return refused("target.changed", "A selected Face changed. " + NOTHING_WRITTEN, this.revision);
      affected.forEach(function (face) {
        if (payload.params.assembly_id === null) delete face.values.assembly_id;
        else face.values.assembly_id = payload.params.assembly_id;
      });
    } else if (payload.name === "ph_composer.zones.settings.update") {
      var values = payload.params.values, expected = payload.params.expected_values;
      var keys = Object.keys(this.zoneSettings);
      if (keys.some(function (key) { return expected[key] !== host.zoneSettings[key]; })) {
        return refused("target.changed", "Zone settings changed. " + NOTHING_WRITTEN, this.revision);
      }
      if (typeof values.suggest_on_make !== "boolean" || !Number.isFinite(values.roof_angle_deg) ||
          !Number.isFinite(values.floor_angle_deg) || values.roof_angle_deg < 0 ||
          values.floor_angle_deg > 180 || values.roof_angle_deg >= values.floor_angle_deg) {
        return refused("request.invalid", "Check the angle thresholds. " + NOTHING_WRITTEN, this.revision);
      }
      this.zoneSettings = JSON.parse(JSON.stringify(values));
      resultValue = JSON.parse(JSON.stringify(values));
    } else if (payload.name === "ph_composer.zones.solve_adjacency") {
      return { status: "completed", code: "ok", message: "No adjacency changes in this preview.",
        effect: "none", revision: this.revision, value: {}, affected: [], findings: [], detail: null };
    } else if (payload.name === "example.foundation.update_parts") {
      var edits = payload.params.edits;
      var conflict = edits.filter(function (edit) {
        var part = host.find(edit.id);
        return !part || (edit.expected_values && edit.expected_values.length_mm !== part.length_mm);
      })[0];
      if (conflict) return refused("target.changed", "The part changed since it was read. " + NOTHING_WRITTEN,
        this.revision);
      edits.forEach(function (edit) { host.find(edit.id).length_mm = edit.values.length_mm; });
    } else if (payload.name === "example.foundation.create_parts") {
      payload.params.parts.forEach(function (values) {
        host.sequence += 1;
        host.parts.push({ id: "exp_preview" + String(host.sequence).padStart(5, "0"), label: values.label,
          length_mm: values.length_mm });
      });
    } else if (payload.name === "ph_composer.zones.update") {
      var zone = this.zones.filter(function (item) {
        return item.reference.zone_id === payload.params.reference.zone_id;
      })[0];
      if (!zone) return refused("target.not_found", "That Zone is unavailable. " + NOTHING_WRITTEN, this.revision);
      zone.values = JSON.parse(JSON.stringify(payload.params.values));
    } else if (payload.name === "ph_composer.zones.faces.classify") {
      var reference = payload.params.faces[0];
      var face = this.faces.filter(function (item) {
        return item.reference.entity_path.join(",") === reference.entity_path.join(",");
      })[0];
      if (!face) return refused("target.not_found", "That Face is unavailable. " + NOTHING_WRITTEN, this.revision);
      Object.keys(payload.params.intent).forEach(function (field) {
        var intent = payload.params.intent[field];
        if (intent.mode === "set") face.values[field] = intent.value;
        if (intent.mode === "clear") delete face.values[field];
      });
      face.state = face.values.face_type && face.values.boundary_condition ? "classified" : "incomplete";
    } else if (payload.name === "ph_composer.zones.faces.auto_classify") {
      this.faces.filter(function (item) {
        return item.reference.zone_id === payload.params.zone.zone_id && item.state === "unclassified";
      }).forEach(function (item) {
        item.values = JSON.parse(JSON.stringify(item.suggested));
        item.state = "classified";
      });
    } else {
      return refused("request.unknown_operation", "The preview host does not run " + payload.name + ".", this.revision);
    }
    this.revision += 1;
    return { status: "completed", code: "ok", message: "Done.", effect: "committed", revision: this.revision,
      value: resultValue, affected: [], findings: [], detail: null };
  };

  /* Synthetic UI-only choice management. Production reference/adoption behavior belongs to Ruby. */
  Host.prototype.manageZoneOptions = function (params) {
    var host = this, key = params.collection === "level" ? "levels" : "building_segments";
    var before = this.zoneOptions[key].map(function (entry) {
      return { id: entry.id, name: entry.values.name, colour: entry.values.colour };
    });
    if (JSON.stringify(params.expected_options) !== JSON.stringify(before) ||
        params.expected_default_segment_id !== this.zoneOptions.default_segment_id) {
      return refused("target.changed", "The options changed.", this.revision);
    }
    var created = {}, records = params.options.map(function (choice) {
      var previous = host.zoneOptions[key].filter(function (entry) { return entry.id === choice.id; })[0];
      var id = choice.id;
      if (id.indexOf("new:") === 0) { id = (params.collection === "level" ? "lvl_" : "bsg_") + ++host.sequence;
        created[choice.id] = id; }
      return { id: id, schema_version: 1, values: { name: choice.name, colour: choice.colour,
        export_identifier: previous ? previous.values.export_identifier : "segment_" + id },
        usage: { live: 0, recoverable: previous ? previous.usage.recoverable : 0 } };
    });
    var replacements = {};
    Object.keys(params.replacements).forEach(function (id) {
      replacements[id] = created[params.replacements[id]] || params.replacements[id];
    });
    var field = params.collection + "_id";
    this.zones.forEach(function (zone) {
      if (Object.prototype.hasOwnProperty.call(replacements, zone.values[field])) {
        zone.values[field] = replacements[zone.values[field]];
      }
      var used = records.filter(function (entry) { return entry.id === zone.values[field]; })[0];
      if (used) used.usage.live++;
    });
    this.zoneOptions[key] = records;
    this.zoneOptions.default_segment_id = created[params.default_segment_id] || params.default_segment_id;
    this.revision++;
    return { status: "completed", code: "ok", effect: "committed", revision: this.revision,
      value: { replacement_ids: replacements, created_ids: created } };
  };

  /* Definition fixture actions preserve transport and draft semantics; no PH calculation runs here. */
  Host.prototype.inventoryAction = function (payload) {
    var section = payload.name.slice(0, payload.name.lastIndexOf("."));
    var operation = payload.name.slice(payload.name.lastIndexOf(".") + 1);
    var material = section === MATERIALS, attached = section === ATTACHED.replace(/\.list$/, "");
    var records = attached ? this.attachedZones : (material ? this.materials.records : this.assemblies.records);
    var params = payload.params, target = records.filter(function (record) { return record.id === params.id; })[0];
    function copy(value) { return JSON.parse(JSON.stringify(value)); }
    if (params.id && !target) return refused("target.not_found", "That record is unavailable.", this.revision);
    if (params.expected_values && Object.keys(params.expected_values).some(function (field) {
      var current = target.values[field];
      return JSON.stringify(current === undefined ? null : current) !== JSON.stringify(params.expected_values[field]);
    })) return refused("target.changed", "The record changed. " + NOTHING_WRITTEN, this.revision);
    if (section === ASSEMBLIES + ".layers" || section === ASSEMBLIES + ".segments") {
      return this.builderAction(section, operation, target, params);
    }
    var prefix = material ? "mat" : (attached ? "atz" : "asm"), id = params.id;
    if (operation === "create" || (operation === "save" && !target)) {
      id = prefix + "_preview" + String(++this.sequence).padStart(5, "0");
      target = { id: id, schema_version: 1, user_data: {}, extension_data: {}, findings: [],
        values: copy(params.values) };
      if (material) {
        target.uses = [];
        target.use_count = 0;
        target.values.color = "#ffffff";
      } else if (!attached) {
        target.values.layers = [{ id: "lyr_preview" + this.sequence, thickness_mm: 100,
          segments: [{ id: "seg_preview" + this.sequence, width_mm: 100, material_id: null }] }];
        target.display = { color: "#bbdefb", total_thickness_mm: 100, thermal: { complete: false,
          u_effective_w_m2k: null, warnings: ["Choose a Material for every Layer-Segment."] } };
      }
      records.push(target);
    } else if (operation === "update" || operation === "save") {
      Object.keys(params.values).forEach(function (field) {
        var value = params.values[field];
        if (value === null && (field === "type" || field === "exterior_condition")) delete target.values[field];
        else target.values[field] = value;
      });
    } else if (operation === "duplicate") {
      var duplicate = copy(target);
      id = prefix + "_preview" + String(++this.sequence).padStart(5, "0");
      duplicate.id = id;
      duplicate.values.name = params.name || target.values.name + " (copy)";
      if (material) {
        duplicate.uses = [];
        duplicate.use_count = 0;
        if (!params.copy_datasheets) duplicate.values.datasheet_links = [];
      }
      records.push(duplicate);
    } else if (operation === "delete") {
      if (material && target.use_count) {
        var replacement = records.filter(function (record) { return record.id === params.replacement_id; })[0];
        if (!replacement || replacement === target) return refused("replacement.required",
          "Choose a replacement Material. " + NOTHING_WRITTEN, this.revision);
        replacement.uses = replacement.uses.concat(target.uses);
        replacement.use_count = replacement.uses.length;
      }
      if (attached && !params.replacement) {
        return refused("replacement.required", "Choose a destination.", this.revision);
      }
      if (!material && !attached) {
        var uses = this.faces.filter(function (face) { return face.values.assembly_id === target.id; });
        if (uses.length && !Object.prototype.hasOwnProperty.call(params, "replacement_id")) {
          return refused("replacement.required", "Choose a replacement Assembly.", this.revision);
        }
        uses.forEach(function (face) {
          if (params.replacement_id === null) delete face.values.assembly_id;
          else face.values.assembly_id = params.replacement_id;
        });
      }
      records.splice(records.indexOf(target), 1);
    } else return refused("request.unknown_operation", "Unavailable fixture action.", this.revision);
    if (!material && !attached && operation === "update" && params.values.ventilated_cladding !== undefined) {
      // Synthetic canonical responses, not a thermal calculation in the preview host.
      target.display.thermal.rse_m2k_w = params.values.ventilated_cladding ? 0.13 : 0.04;
      target.display.thermal.u_effective_w_m2k = params.values.ventilated_cladding ? 0.195 : 0.2;
    }
    this.revision += 1;
    return { status: "completed", code: "ok", message: "Done.", effect: "committed", revision: this.revision,
      value: { id: id }, affected: [], findings: [], detail: null };
  };

  /* Synthetic topology responses exercise gestures and IDs; Ruby owns physical validation and calculations. */
  Host.prototype.builderAction = function (section, operation, target, params) {
    var values = target.values, layers = values.layers;
    var layer = layers.filter(function (row) { return row.id === params.layer_id; })[0];
    var segment = layer && layer.segments.filter(function (row) { return row.id === params.segment_id; })[0];
    var isLayer = section === ASSEMBLIES + ".layers";
    if (params.layer_id && !layer) return refused("target.not_found", "Layer unavailable.", this.revision);
    if (params.segment_id && !segment) return refused("target.not_found", "Layer-Segment unavailable.", this.revision);
    function freshSegment(id) {
      return { id: "seg_builder" + id, width_mm: 600, material_id: null,
        is_continuous_insulation: false, steel_stud_spacing_mm: null };
    }
    if (isLayer) {
      if (operation === "add") {
        var index = params.index === undefined ? layers.length : params.index;
        if (params.anchor_layer_id) {
          var anchor = layers.filter(function (row) { return row.id === params.anchor_layer_id; })[0];
          if (!anchor) return refused("target.not_found", "Anchor unavailable.", this.revision);
          var outside = values.orientation === "first_layer_outside" ? 0 : 1;
          index = layers.indexOf(anchor) + (params.side === "outside" ? outside : 1 - outside);
        }
        layers.splice(index, 0, { id: "lyr_builder" + (++this.sequence),
          thickness_mm: params.thickness_mm || 100, segments: [freshSegment(this.sequence)] });
      } else if (operation === "update") layer.thickness_mm = params.thickness_mm;
      else if (operation === "remove") {
        if (layers.length === 1) return refused("validation.failed", "An Assembly needs a Layer.", this.revision);
        layers.splice(layers.indexOf(layer), 1);
      } else if (operation === "move") {
        var position = layers.indexOf(layer), outward = values.orientation === "first_layer_outside" ? -1 : 1;
        var destination = position + (params.direction === "outward" ? outward : -outward);
        if (destination >= 0 && destination < layers.length) {
          layers[position] = layers[destination]; layers[destination] = layer;
        }
      } else if (operation === "reorder") {
        if (params.index < 0 || params.index >= layers.length) {
          return refused("params.invalid", "Layer index out of range.", this.revision);
        }
        layers.splice(layers.indexOf(layer), 1);
        layers.splice(params.index, 0, layer);
      } else if (operation === "flip") layers.reverse();
      else if (operation === "flip_orientation") values.orientation = values.orientation === "first_layer_outside" ?
        "last_layer_outside" : "first_layer_outside";
      else if (operation === "set_air_barrier") values.air_barrier = params.layer_id ?
        { layer_id: params.layer_id, face: params.face } : null;
      else return refused("request.unknown_operation", "Unknown Layer action.", this.revision);
    } else if (operation === "add") {
      layer.segments.splice(params.index === undefined ? layer.segments.length : params.index, 0,
        Object.assign(freshSegment(++this.sequence), { width_mm: params.width_mm || 600 }));
    } else if (operation === "remove") {
      if (layer.segments.length === 1) return refused("validation.failed", "A Layer needs a segment.", this.revision);
      layer.segments.splice(layer.segments.indexOf(segment), 1);
    } else if (operation === "update") Object.assign(segment, params.values);
    else if (operation === "set_material") segment.material_id = params.material_id;
    else if (operation === "mirror") layers.forEach(function (row) { row.segments.reverse(); });
    else return refused("request.unknown_operation", "Unknown Layer-Segment action.", this.revision);
    this.revision += 1;
    return { status: "completed", code: "ok", message: "Done.", effect: "committed", revision: this.revision,
      value: { id: target.id }, affected: [], findings: [], detail: null };
  };

  Host.prototype.libraryMetadata = function () {
    return this.libraryProviders.map(function (provider) {
      var generation = this.libraryGenerations[provider.id] || null;
      return Object.assign({}, provider, { catalogs: provider.kinds.map(function (kind) {
        return { kind: kind, generation: generation, state: this.libraryFailures[provider.id] ? "failed" :
          (!generation ? "unloaded" : ((this.libraryCatalogs[provider.id] || []).length ? "loaded" : "empty")),
        failure: this.libraryFailures[provider.id] || null, age_seconds: generation ? 65 : null, freshness: {} };
      }, this) });
    }, this);
  };
  Host.prototype.libraryResolution = function (row, kind) {
    var source = function (record) { var s = record.values.source;
      return s && s.kind === "library" && s.library_id === row.library_id && s.record_id === row.record_id; };
    var records = kind && kind !== "materials" ? this.windows[kind].records : this.materials.records;
    var exact = records.filter(source);
    var candidates = exact.length ? exact : records.filter(function (record) {
      return record.values.name === row.snapshot.name;
    });
    var result = { outcome: exact.length > 1 ? "ambiguous_source" : exact.length ? "reuse" :
      candidates.length > 1 ? "ambiguous_name" : candidates.length ? "review_required" : "create", candidates: [] };
    candidates.forEach(function (record) {
      var differences = Object.keys(row.snapshot).filter(function (key) { return key !== "id" &&
        JSON.stringify(record.values[key]) !== JSON.stringify(row.snapshot[key]); }).map(function (key) {
        return { field: key, local: record.values[key], incoming: row.snapshot[key],
          local_present: Object.prototype.hasOwnProperty.call(record.values, key), incoming_present: true };
      });
      result.candidates.push({ id: record.id, display_label: record.values.name, differences: differences,
        expected_values: JSON.parse(JSON.stringify(record.values)), comparison_available: source(record),
        source_changed: source(record) ? record.values.source.snapshot.notes !== row.snapshot.notes : null });
    });
    return result;
  };
  Host.prototype.libraryQuery = function (payload) {
    if (payload.name === "ph_composer.library.export_preview") { this.libraryExportPreview(payload); return; }
    if (payload.name.indexOf("ph_composer.spaces.") === 0) { this.spacesQuery(payload); return; }
    var params = payload.params, rows = this.libraryCatalogs[params.provider_id] || [];
    rows = rows.filter(function (row) { return (row.kind || "materials") === params.kind; });
    var generation = this.libraryGenerations[params.provider_id], outcome;
    if (payload.session !== this.session) outcome = refused("session.inactive", "The Model changed.", null);
    else if (params.generation !== generation) outcome = refused("library.generation_stale", "Refresh this library.",
      this.revision);
    else {
      var metadata = this.libraryMetadata().filter(function (row) { return row.id === params.provider_id; })[0];
      var offset = Number(params.cursor || 0), end = Math.min(rows.length, offset + (params.limit || 100));
      var catalog = metadata.catalogs.filter(function (row) { return row.kind === params.kind; })[0];
      var page = Object.assign({}, catalog, { rows: rows.slice(offset, end).map(function (row) {
        // Admission's label: every preview kind's adapter projects its `name` (Admission.label_for).
        return Object.assign({}, row, { display_label: row.snapshot.name,
          resolution: this.libraryResolution(row, params.kind) });
      }, this), total: rows.length, next_cursor: end < rows.length ? String(end) : null,
      warnings: [], unavailable: [] });
      outcome = { status: "completed", value: page, revision: this.revision };
    }
    var self = this;
    this.window.setTimeout(function () {
      self.publish("query.result", { request_id: payload.request_id, session: payload.session, outcome: outcome });
    }, 0);
  };
  Host.prototype.libraryExportPreview = function (payload) {
    var params = payload.params, selected = params.records || [], sources = [
      ["materials", "ph_composer.assemblies.material", this.materials, "Material"],
      ["frames", "ph_composer.windows.frame", this.windows.frames, "Frame"],
      ["glazings", "ph_composer.windows.glazing", this.windows.glazings, "Glazing"],
      ["psi_install_types", "ph_composer.windows.psi_install_type", this.windows.psi_install_types, "Psi-Install Type"]
    ];
    var kinds = sources.filter(function (entry) { return entry[2]; }).map(function (entry) {
      return { kind: entry[0], record_kind_label: entry[3], count: (entry[2].records || []).filter(function (record) {
        return params.scope !== "selected" || selected.some(function (row) {
          return row.record_kind === entry[1] && row.id === record.id;
        });
      }).length };
    });
    this.publish("query.result", { request_id: payload.request_id, session: payload.session,
      outcome: payload.session !== this.session ? refused("session.inactive", "The Model changed.", null) : {
        status: "completed", revision: this.revision,
        value: { kinds: kinds, omissions: this.libraryExportOmissions(), projection_digest: "preview",
          revision: this.revision }
      } });
  };
  // Synthetic omissions in the real projection's shape: Window Types are not library records, and Frames without
  // a library origin drop their source attribution.
  Host.prototype.libraryExportOmissions = function () {
    var types = ((this.windows.types || {}).records || []).map(function (record) {
      return { record_kind: "ph_composer.windows.window_type", record_kind_label: "Window Type", id: record.id,
        fields: [], reason: "unsupported_kind" };
    });
    return types.concat(((this.windows.frames || {}).records || []).map(function (record) {
      return { record_kind: "ph_composer.windows.frame", record_kind_label: "Frame", id: record.id,
        fields: ["source"], reason: "fields_not_in_wire_schema" };
    }));
  };
  /* There is no native dialog here, so an approval adds a synthetic location under its default label. */
  Host.prototype.approvedLocation = function (payload) {
    var params = payload.params, verb = payload.name.split(".").pop(), value;
    var kinds = { approve_destination: ["save_file", "Export destination"], approve_file: ["open_file", "Library file"],
      approve_folder: ["open_folder", "Library folder"] };
    if (kinds[verb]) {
      value = { id: "location_Preview" + String(++this.sequence).padStart(5, "0"), kind: kinds[verb][0],
        label: params.label || kinds[verb][1] + " " + (this.approvedLocations.length + 1),
        use: verb === "approve_destination" ? "reusable" : "single", approved_at: new Date().toISOString(),
        last_used_at: null, available: true };
      this.approvedLocations.push(value);
    }
    this.approvedLocations.forEach(function (row) {
      if (verb === "rename" && row.id === params.id) row.label = params.label;
    });
    if (verb === "revoke") {
      this.approvedLocations = this.approvedLocations.filter(function (row) { return row.id !== params.id; });
    }
    this.snapshot();
    this.publish("setup.result", { request_id: payload.request_id, session: payload.session, outcome: {
      status: "completed", effect: "none", revision: this.revision, value: value || this.approvedLocations } });
  };

  Host.prototype.librarySetup = function (payload) {
    if (payload.name.indexOf("ph_composer.locations.") === 0) return this.approvedLocation(payload);
    var params = payload.params, verb = payload.name.split(".").pop();
    if (verb === "remove") this.libraryProviders = this.libraryProviders.filter(function (row) {
      return row.id !== params.provider_id;
    });
    if (verb === "load") {
      if (this.failLibraryRefresh) this.libraryFailures[params.provider_id] =
        { code: "library.file_unreadable", message: "The configured library could not be read." };
      else { this.libraryGenerations[params.provider_id] = (this.libraryGenerations[params.provider_id] || 0) + 1;
        delete this.libraryFailures[params.provider_id]; }
    }
    var provider = this.libraryMetadata().filter(function (row) { return row.id === params.provider_id; })[0];
    var value = provider ? provider.catalogs.filter(function (row) { return row.kind === params.kind; })[0] :
      this.libraryMetadata();
    this.snapshot();
    this.publish("setup.result", { request_id: payload.request_id, session: payload.session,
      outcome: { status: "completed", effect: "none", revision: this.revision, value: value } });
  };
  // A synthetic preview of Window copy targets. Ruby owns real transactions, provenance and thermal results.
  Host.prototype.windowLibraryCopy = function (params, staged) {
    var incoming = (this.libraryCatalogs[params.provider_id] || []).filter(function (row) {
      return row.kind === params.kind && row.library_id === params.library_id && row.record_id === params.record_id;
    })[0];
    if (!incoming || params.generation !== this.libraryGenerations[params.provider_id]) {
      return refused("library.generation_stale", "Refresh and choose again.", this.revision);
    }
    var target = params.assignment, type, cell;
    if (target && target.mode === "model_default") {
      if (JSON.stringify(target.expected_settings) !== JSON.stringify(this.windows.settings)) {
        return refused("record.stale", "The defaults changed.", this.revision);
      }
    } else if (target) {
      type = this.windows.types.records.filter(function (row) { return row.id === target.id; })[0];
      cell = type && type.values.elements.filter(function (row) { return row.id === target.element_id; })[0];
      if (!cell || cell.kind === "empty" || JSON.stringify(type.values) !== JSON.stringify(target.expected_values)) {
        return refused("record.stale", "The target changed.", this.revision);
      }
    }
    var records = this.windows[params.kind].records, local = records.filter(function (row) {
      return row.id === params.local_id;
    })[0];
    if (params.choice === "use_library" && (!local ||
      JSON.stringify(local.values) !== JSON.stringify(params.expected_values))) {
      return refused("record.stale", "The local product changed.", this.revision);
    }
    if (params.choice === "create") {
      local = { id: params.kind + "_preview_" + (++this.sequence), values: {}, uses: [], use_count: 0 };
      records.push(local);
    }
    if (!local) return refused("library.choice_invalid", "Choose a local product.", this.revision);
    if (params.choice !== "keep_local") local.values = JSON.parse(JSON.stringify(incoming.snapshot));
    if (target && target.mode === "model_default") this.windows.settings.default_psi_install_id = local.id;
    else if (cell) {
      if (params.kind === "frames") cell.frames[target.side] = local.id;
      else cell.glazing_id = local.id;
      type.display.thermal = { uw_w_m2k: null, u_effective_w_m2k: null, elements: [],
        findings: ["Preview changed definition: canonical thermal results require the Ruby host."] };
    }
    if (!staged) this.revision++;
    return { status: "completed", effect: "committed", revision: this.revision,
      value: { local_id: local.id, assigned: Boolean(target) } };
  };
  Host.prototype.libraryCopy = function (payload) {
    if (payload.params.kind !== "materials") return this.windowLibraryCopy(payload.params, false);
    var params = payload.params, rows = this.libraryCatalogs[params.provider_id] || [];
    var incoming = rows.filter(function (row) {
      return row.library_id === params.library_id && row.record_id === params.record_id;
    })[0];
    if (!incoming || params.generation !== this.libraryGenerations[params.provider_id]) {
      return refused("library.generation_stale", "The catalog changed. Refresh and choose again.", this.revision);
    }
    var assignment = params.assignment, assembly, layer, segment;
    if (assignment) {
      assembly = this.assemblies.records.filter(function (row) { return row.id === assignment.id; })[0];
      layer = assembly && assembly.values.layers.filter(function (row) { return row.id === assignment.layer_id; })[0];
      segment = layer && layer.segments.filter(function (row) { return row.id === assignment.segment_id; })[0];
      if (!segment || JSON.stringify(assignment.expected_values) !== JSON.stringify(assembly.values)) {
        return refused("record.stale", "The assignment target changed. Nothing was written.", this.revision);
      }
    }
    var local = this.materials.records.filter(function (record) { return record.id === params.local_id; })[0];
    if (params.choice === "use_library" && (!local ||
      JSON.stringify(local.values) !== JSON.stringify(params.expected_values))) {
      return refused("record.stale", "The local values changed. Nothing was written.", this.revision);
    }
    if (params.choice === "create") {
      local = { id: "mat_library_" + (++this.sequence), values: {}, user_data: {}, uses: [], use_count: 0 };
      this.materials.records.push(local);
    }
    if (params.choice === "create" || params.choice === "use_library") {
      Object.assign(local.values, JSON.parse(JSON.stringify(incoming.snapshot))); delete local.values.id;
      local.values.source = { kind: "library", provider_kind: "ph_composer.library.file",
        record_kind: "materials", library_id: incoming.library_id, record_id: incoming.record_id,
        fingerprint_version: 1, fingerprint: "0".repeat(64), copied_at: "2026-10-01T12:00:00Z",
        snapshot: JSON.parse(JSON.stringify(incoming.snapshot)) };
    }
    if (!local) return refused("library.choice_invalid", "Choose a local copy.", this.revision);
    if (segment) segment.material_id = local.id;
    this.revision += 1;
    return { status: "completed", effect: "committed", revision: this.revision, value: {
      local_id: local.id, assigned: Boolean(segment) }, message: "Library copy applied." };
  };

  Host.prototype.find = function (id) {
    return this.parts.filter(function (part) { return part.id === id; })[0];
  };

  Host.prototype.setPreference = function (payload) {
    if (payload.key === "unit_system") this.preferences.unit_system = payload.value;
    if (payload.key === "dimension_format") {
      var formats = this.preferences.dimension_formats[payload.scope] || { SI: "mm", IP: "in" };
      formats[payload.system] = payload.value;
      this.preferences.dimension_formats[payload.scope] = formats;
    }
    if (payload.key === "table_view") {
      this.preferences.table_views = this.preferences.table_views || {};
      this.preferences.table_views[payload.scope] = payload.value;
    }
    this.publish("preferences.result", { request_id: payload.request_id, status: "completed",
      message: "Display preference saved.", preferences: JSON.parse(JSON.stringify(this.preferences)) });
  };

  // Each Type row with display.install_topology derived on every read, as Installs.topology_facts derives it:
  // an edge is shared or partly shared by the non-empty elements beyond it, and only a perimeter edge paints.
  // tests/support/window_fixtures.js builds the same facts for the offline editor tests.
  Host.prototype.windowTypes = function () {
    var types = JSON.parse(JSON.stringify(this.windows.types || { records: [] }));
    types.records.forEach(function (type) {
      type.display = Object.assign({}, type.display, { install_topology: installTopology(type.values) });
    });
    return types;
  };
  function installTopology(values) {
    var SIDES = ["top", "right", "bottom", "left"];
    function occupied(row, column) {
      return values.elements.some(function (cell) { return cell.kind !== "empty" && row >= cell.row_span[0] &&
        row <= cell.row_span[1] && column >= cell.column_span[0] && column <= cell.column_span[1]; });
    }
    function classify(cell, side) {
      var r = cell.row_span, c = cell.column_span, points = [], index;
      if (side === "top" || side === "bottom") {
        for (index = c[0]; index <= c[1]; index++) points.push([side === "top" ? r[0] - 1 : r[1] + 1, index]);
      } else {
        for (index = r[0]; index <= r[1]; index++) points.push([index, side === "left" ? c[0] - 1 : c[1] + 1]);
      }
      var count = points.filter(function (point) { return occupied(point[0], point[1]); }).length;
      return count === 0 ? "perimeter" : count === points.length ? "shared" : "partial";
    }
    var edges = {}, slots = {};
    values.elements.forEach(function (cell) {
      slots[cell.id] = JSON.stringify([cell.kind, cell.row_span, cell.column_span]);
      if (cell.kind === "empty") return;
      edges[cell.id] = {};
      SIDES.forEach(function (side) {
        var classification = classify(cell, side);
        edges[cell.id][side] = { classification: classification, paintable: classification === "perimeter" };
      });
    });
    // The copy key is opaque; equal grids and edge topologies give equal keys.
    var shape = values.elements.map(function (cell) {
      return [cell.kind, cell.row_span, cell.column_span, SIDES.map(function (side) {
        return cell.kind === "empty" ? null : classify(cell, side); })];
    }).sort(function (a, b) { return JSON.stringify(a).localeCompare(JSON.stringify(b)); });
    return { edges: edges, copy_key: JSON.stringify([values.rows_m, values.columns_m, shape]), copy_slots: slots };
  }

  function refused(code, message, revision) {
    return { status: "refused", code: code, message: message, effect: "none", revision: revision, value: null,
      affected: [], findings: [], detail: null };
  }

  global.PhComposerPreviewHost = {
    install: function (window, options) {
      var host = new Host(window, options);
      window.sketchup = { ph_composer_message: function (text) { host.receive(JSON.parse(text)); } };
      return host;
    }
  };
}(typeof window !== "undefined" ? window : this));
