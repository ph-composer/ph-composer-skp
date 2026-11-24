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
  var CLIMATE = "ph_composer.climate.";
  var MECHANICAL = "ph_composer.mechanical.";
  var ZONE_LABELS = { 1: "Not defined", 11: "1", 12: "2", 13: "3", 14: "4", 141: "4C", 15: "5", 16: "6", 17: "7",
    18: "8" };
  var NOTHING_WRITTEN = "Nothing was written.";

  function Host(window, options) {
    var settings = options || {};
    this.window = window;
    this.sent = [];
    this.libraryProviders = JSON.parse(JSON.stringify(settings.libraryProviders || []));
    this.libraryCatalogs = JSON.parse(JSON.stringify(settings.libraryCatalogs || {}));
    this.libraryGenerations = {}; this.libraryFailures = {};
    // A hosted (version 2) load's state while it runs or after Cancel; `holdLibraryLoads` keeps loads running
    // until `finishLibraryLoad` publishes them.
    this.libraryLoads = {}; this.holdLibraryLoads = false;
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
    // The occupancy read (ph_composer.programs.zones): the fixture's, or none.
    this.occupancy = settings.occupancy ? JSON.parse(JSON.stringify(settings.occupancy)) : null;
    // The Programs tab's catalogs (ph_composer.programs.programs, schedules, equipment_sets): the fixture's, or none.
    this.programCatalog = settings.programCatalog ? JSON.parse(JSON.stringify(settings.programCatalog)) : null;
    // Each Schedule's profile drawn from its values, as the host's read does.
    if (this.programCatalog) {
      this.programCatalog.schedules.forEach(function (row) { row.profile = scheduleProfile(row.values); });
    }
    // The Spaces read: the fixture's, or empty (the section is always published, as the host does).
    this.spaces = settings.spaces ? JSON.parse(JSON.stringify(settings.spaces)) : null;
    this.markTool = { active: false, weighting_factor: 1, gesture_limit: 250 };
    this.readoutsOn = ["ph_composer.spaces.show"];
    this.labelOptions = { weighted_area: true, net_volume: true, airflows: false };
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
    this.edgeTool = { active: false, thermal_bridge_type_id: null, quantity: 1, gesture_limit: 250 };
    // The Mechanical tab's Ventilators, what serves each Zone, and each Zone's supply and extract.
    this.mechanical = JSON.parse(JSON.stringify(settings.mechanical || { ventilators: [], serves: {}, flows: {} }));
    this.mechanical.hotWater = this.mechanical.hotWater || { systems: [], heaters: [], tanks: [], serves: {} };
    // The heat pumps: the four catalogs, each Zone's indoor units, and the Blended result as the host worked it out.
    this.mechanical.heatPumps = this.mechanical.heatPumps || { outdoor_equipment: [], indoor_equipment: [],
      outdoor_units: [], indoor_units: [], serves: {}, blended: null };
    // The Electric Heaters and each Zone's list of them.
    this.mechanical.electricHeaters = this.mechanical.electricHeaters || { heaters: [], serves: {} };
    // The Pumps and each Zone's list of them.
    this.mechanical.pumps = this.mechanical.pumps || { pumps: [], serves: {} };
    // The Model's site and design temperatures (features/climate/settings.rb) and what SketchUp would report
    // for its geolocation; `climate.geolocation` stands in for the host read.
    this.climate = JSON.parse(JSON.stringify(settings.climate || {}));
    this.climate.site = Object.assign({ latitude_deg: null, longitude_deg: null, elevation_m: null,
      climate_zone: null, hours_from_utc: null }, this.climate.site || {});
    this.climate.design = Object.assign({ heating_99_c: null, cooling_1_c: null, design_temperature_source: null },
      this.climate.design || {});
    this.climate.geolocation = this.climate.geolocation || { geolocated: false, latitude_deg: null,
      longitude_deg: null, hours_from_utc: null };
    // The climate data folders on this computer (features/climate/folders/), as `folders.list` answers them, and
    // the rows the folder chooser hands Add Folder and Locate in turn, then a cancel once they run out.
    this.climate.folders = this.climate.folders || [];
    this.climate.lastDatasetId = this.climate.lastDatasetId || null;
    this.climate.chooser = this.climate.chooser || [];
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

  /* Each Building Segment's Face area over its Zones, keyed as the Zones read keys it: the Segment's id, a legacy
     Zone's Segment name, or "" for none. */
  Host.prototype.segmentSums = function () {
    var sums = {};
    this.zoneRows().forEach(function (zone) {
      var values = zone.values, key = Object.prototype.hasOwnProperty.call(values, "building_segment_id") ?
        values.building_segment_id || "" : values.building_segment || "";
      var row = sums[key] = sums[key] || { key: key, zone_count: 0, face_area_m2: 0, unclassified_face_area_m2: 0 };
      row.zone_count++; row.face_area_m2 += zone.face_area_m2;
      row.unclassified_face_area_m2 += zone.unclassified_face_area_m2;
    });
    return Object.keys(sums).map(function (key) { return sums[key]; });
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
        ["ph_composer.programs.occupancy"]: this.occupancy ? { status: "completed",
          value: JSON.parse(JSON.stringify(this.occupancy)) } : undefined,
        ["ph_composer.programs.programs"]: this.catalogSection("programs"),
        ["ph_composer.programs.schedules"]: this.catalogSection("schedules"),
        ["ph_composer.programs.equipment_sets"]: this.catalogSection("equipment_sets"),
        [ZONES]: { status: "completed", code: "ok", revision: this.revision,
          value: { zones: this.zoneRows(), make_zone: this.makeZone, building_segments: this.segmentSums(),
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
            return Object.assign({}, face, { zone_name: zone ? zone.values.name : "Zone" });
          }, this), assembly_usage: this.usage() } },
        [LEGEND]: { status: "completed", code: "ok", revision: this.revision, value: this.legend() },
        [PALETTE]: { status: "completed", code: "ok", revision: this.revision,
          value: JSON.parse(JSON.stringify(this.palette)) },
        ["ph_composer.windows.types"]: { status: "completed", value: this.windowTypes() },
        ["ph_composer.windows.unit_areas"]: { status: "completed", value: JSON.parse(JSON.stringify(
          this.windows.unit_areas || { faces: [], unhosted_units: [] })) },
        ["ph_composer.windows.units"]: { status: "completed", value: JSON.parse(JSON.stringify(this.windows.units ||
          { units: [] })) },
        ["ph_composer.windows.units.selected"]: { status: "completed", value: {
          units: JSON.parse(JSON.stringify(this.selectedUnits || [])) } },
        ["ph_composer.windows.place_tool"]: { status: "completed", value: JSON.parse(JSON.stringify(
          this.windows.place_tool || { active: false, type_id: null, anchor: "sill_center", host: null })) },
        ["ph_composer.windows.frames"]: { status: "completed",
          value: JSON.parse(JSON.stringify(this.windows.frames || { records: [] })) },
        ["ph_composer.windows.glazings"]: { status: "completed",
          value: JSON.parse(JSON.stringify(this.windows.glazings || { records: [] })) },
        ["ph_composer.windows.psi_install_types"]: { status: "completed",
          value: JSON.parse(JSON.stringify(this.windows.psi_install_types || { records: [] })) },
        ["ph_composer.windows.convert_dialog"]: { status: "completed", value: JSON.parse(JSON.stringify(
          this.windows.convert_dialog || { token: null, revision: null, groups: [], left_out: [] })) },
        ["ph_composer.windows.settings"]: { status: "completed",
          value: JSON.parse(JSON.stringify(this.windows.settings || {
          default_psi_install_id: null, default_psi_install_w_mk: 0.04, default_install_depth_m: 0 })) },
        ["ph_composer.spaces.spaces"]: { status: "completed", value: JSON.parse(JSON.stringify(this.spaces || {
          spaces: [], zones: [], findings: [], units: { area: "m2", height: "m", volume: "m3", airflow: "m3/h" } })) },
        ["ph_composer.spaces.mark_tool"]: { status: "completed", value: JSON.parse(JSON.stringify(this.markTool)) },
        ["ph_composer.spaces.label_options"]: { status: "completed",
          value: JSON.parse(JSON.stringify(this.labelOptions)) },
        ["ph_composer.spaces.create_review"]: { status: "completed", value: JSON.parse(JSON.stringify(
          this.createReview || { token: null, revision: null, zone: null, zones: [], accepted: [],
            left_out: [] })) },
        [MATERIALS]: { status: "completed", value: JSON.parse(JSON.stringify(this.materials)) },
        [ASSEMBLIES]: { status: "completed", value: JSON.parse(JSON.stringify(this.assemblies)) },
        [TB + "types"]: { status: "completed", value: { records: JSON.parse(JSON.stringify(
          this.thermalBridges.types)), unreadable: [] } },
        [TB + "edges.selected"]: { status: "completed", value: { edges: JSON.parse(JSON.stringify(
          this.thermalBridges.selected)), ignored: [], ignored_total: 0 } },
        [TB + "edge_tool"]: { status: "completed", value: JSON.parse(JSON.stringify(this.edgeTool)) },
        [MECHANICAL + "ventilators"]: { status: "completed", value: { records: this.ventilatorRows(),
          unreadable: [] } },
        [MECHANICAL + "serves"]: { status: "completed", value: { zones: this.servesRows() } },
        [MECHANICAL + "hot_water_systems"]: { status: "completed", value: { records: this.hotWaterSystemRows(),
          unreadable: [] } },
        [MECHANICAL + "hot_water_heaters"]: { status: "completed", value: { records: JSON.parse(JSON.stringify(
          this.mechanical.hotWater.heaters)), unreadable: [] } },
        [MECHANICAL + "hot_water_tanks"]: { status: "completed", value: { records: this.hotWaterTankRows(),
          unreadable: [] } },
        [MECHANICAL + "heat_pumps.outdoor_equipment"]: { status: "completed", value: {
          records: this.heatPumpRows("outdoor_equipment"), unreadable: [] } },
        [MECHANICAL + "heat_pumps.indoor_equipment"]: { status: "completed", value: {
          records: this.heatPumpRows("indoor_equipment"), unreadable: [] } },
        [MECHANICAL + "heat_pumps.outdoor_units"]: { status: "completed", value: {
          records: this.heatPumpRows("outdoor_units"), unreadable: [] } },
        [MECHANICAL + "heat_pumps.indoor_units"]: { status: "completed", value: {
          records: this.heatPumpRows("indoor_units"), unreadable: [] } },
        [MECHANICAL + "electric_heaters"]: { status: "completed", value: { records: this.electricHeaterRows(),
          unreadable: [] } },
        [MECHANICAL + "pumps"]: { status: "completed", value: { records: this.pumpRows(), unreadable: [] } },
        [MECHANICAL + "heat_pumps_blended"]: { status: "completed", value: JSON.parse(JSON.stringify(
          this.mechanical.heatPumps.blended || { climate: { state: "missing", reason: "No climate." },
            segments: [], findings: [] })) },
        [CLIMATE + "site"]: { status: "completed", value: this.climateSite() },
        [CLIMATE + "design_temperatures"]: { status: "completed", value: this.climateDesign() },
        [CLIMATE + "summary"]: { status: "completed", value: { site: this.climateSite().state,
          design_temperatures: { state: this.climateDesign().state, warning: this.climateDesign().warning },
          climate: this.climate.station ? { state: "complete", origin: "station",
            verdict: this.limitCheck(this.climate.site).verdict,
            edited: this.climateRecord().edited_cells.length > 0 } :
            { state: "none", origin: null, verdict: null, edited: false } } },
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
        { name: "ph_composer.thermal_bridges.by_type", label: "Thermal Bridge Type", entity_kind: "edge", group: null },
        { name: "ph_composer.thermal_bridges.by_group", label: "Thermal bridge group", entity_kind: "edge",
          group: null },
        { name: "ph_composer.mechanical.by_ventilator", label: "Ventilator", entity_kind: "zone", group: null },
        { name: "ph_composer.mechanical.by_hot_water_system", label: "Hot Water System", entity_kind: "zone",
          group: null }],
      readouts: [["ph_composer.spaces.show", "Show Spaces", false],
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
      else if (message.payload.name === "ph_composer.programs.equipment_sets.device_types") {
        this.deviceTypesQuery(message.payload);
      } else if (message.payload.name.indexOf(CLIMATE) === 0) this.climateQuery(message.payload);
      else this.libraryQuery(message.payload);
    }
    if (message.type === "file_export.invoke") this.publish("file_export.result", {
      request_id: message.payload.request_id, session: message.payload.session,
      outcome: refused("export.unavailable", "File writes are unavailable in this browser preview.", this.revision)
    });
    if (message.type === "view.invoke") this.viewCommand(message.payload);
    if (message.type === "setup.invoke") {
      if (message.payload.name.indexOf(CLIMATE) === 0) this.climateSetup(message.payload);
      else this.librarySetup(message.payload);
    }
    // The Setup view's entries (shell/setup_entries.rb). Agent Access opens a native window the preview has not;
    // Climate Data on This Computer asks the panel for its dialog (Panel.open_at).
    if (message.type === "panel.setup_open" && message.payload.name === CLIMATE + "data.open") {
      this.publish("panel.navigate", { session: this.session, owner: "ph_composer.climate",
        intent: { open: "climate_data" } });
    }
    if (message.type === "panel.setup_entries" || message.type === "panel.setup_open") {
      var folders = this.climate.folders.length;
      this.publish("panel.setup", { entries: [{ name: "ph_composer.agent_access.open", menu: "Agent Access",
        label: "Agent Access…", summary: "Listening on port 46110 · 1 live token" },
      { name: CLIMATE + "data.open", menu: "Climate", label: "Climate Data on This Computer…",
        summary: folders ? folders + " folder" + (folders === 1 ? "" : "s") : "No climate data folder" }] });
    }
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
      // The edge tool arms, re-arms and stops; gestures happen only in SketchUp.
      if (payload.name === TB + "edge_tool.choose") {
        this.edgeTool = { active: true, thermal_bridge_type_id: payload.params.thermal_bridge_type_id,
          quantity: payload.params.quantity || 1, gesture_limit: 250 };
        this.colourBy = { mode: TB + "by_type", isolated: null };
      }
      if (payload.name === TB + "edge_tool.stop") this.edgeTool.active = false;
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
      if (payload.name === "ph_composer.windows.convert_dialog.close" && this.windows.convert_dialog &&
        this.windows.convert_dialog.token === payload.params.token) this.windows.convert_dialog = null;
      if (payload.name === "ph_composer.spaces.create_review.close" && this.createReview &&
        this.createReview.token === payload.params.token) this.createReview = null;
      outcome = { status: "completed", code: "ok", message: "Done.", effect: "none", revision: this.revision,
        value: {}, affected: [], findings: [], detail: null };
      this.snapshot();
    }
    this.publish("view.result", { request_id: payload.request_id, session: payload.session, outcome: outcome });
  };

  /* The device types, from the golden the Ruby suite keeps equal to features/programs/equipment_types.rb's catalog
     (tests/fixtures/programs/device_types.json), so the device dialog lays out what Ruby declares. */
  Host.prototype.deviceTypesQuery = function (payload) {
    var host = this;
    host.window.fetch("../../tests/fixtures/programs/device_types.json").then(function (response) {
      return response.json();
    }).then(function (types) {
      host.publish("query.result", { request_id: payload.request_id, session: payload.session,
        outcome: { status: "completed", code: "ok", revision: host.revision, value: { types: types } } });
    });
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

  /* The Mechanical reads as features/mechanical/ answers them: each Zone occurrence with its slots, and each
     Ventilator with the Zones it serves and the balance over them, summed from the fixture's flows by the host's
     rule (more than a tenth of the larger is out of balance). */
  Host.prototype.servesRows = function () {
    var data = this.mechanical, hotWater = data.hotWater, heatPumps = data.heatPumps, names = {}, segments = {};
    var electric = data.electricHeaters, pumps = data.pumps;
    data.ventilators.concat(hotWater.systems, heatPumps.indoor_units, electric.heaters, pumps.pumps)
      .forEach(function (record) {
      names[record.id] = record.values.name;
    });
    this.zoneOptions.building_segments.forEach(function (segment) { segments[segment.id] = segment.values.name; });
    return this.zones.map(function (zone) {
      var item = data.serves[zone.id] || null, system = hotWater.serves[zone.id] || null;
      var segment = zone.values.building_segment_id || null, items = [];
      if (item) items.push({ slot: "ventilator_id", id: item, name: names[item] || null });
      if (system) items.push({ slot: "hot_water_system_id", id: system, name: names[system] || null });
      var units = (heatPumps.serves[zone.id] || []).slice();
      units.forEach(function (unit) {
        items.push({ slot: "hp_indoor_unit_ids", id: unit, name: names[unit] || null });
      });
      var heaters = (electric.serves[zone.id] || []).slice();
      heaters.forEach(function (heater) {
        items.push({ slot: "heater_ids", id: heater, name: names[heater] || null });
      });
      var pumpIds = (pumps.serves[zone.id] || []).slice();
      pumpIds.forEach(function (pump) { items.push({ slot: "pump_ids", id: pump, name: names[pump] || null }); });
      return { zone_id: zone.id, reference: zone.reference, name: zone.values.name,
        building_segment_id: segment,
        building_segment: segment ? segments[segment] || null : zone.values.building_segment || null,
        slots: { ventilator_id: item, hot_water_system_id: system, hp_indoor_unit_ids: units, heater_ids: heaters,
          pump_ids: pumpIds },
        payload_status: item || system || units.length || heaters.length || pumpIds.length ? "understood" : null,
        items: items, findings: [] };
    });
  };
  /* Each Hot Water System with the Zones it serves, its Heater and Tank counts, honeybee-ph's recirculation
     defaults and the host's findings: serving nothing, a calculation method the pinned honeybee-ph cannot carry,
     and two Systems serving one Building Segment. */
  Host.prototype.hotWaterSystemRows = function () {
    var hotWater = this.mechanical.hotWater, zones = this.zones, segments = {};
    this.zoneOptions.building_segments.forEach(function (segment) { segments[segment.id] = segment.values.name; });
    var bySegment = {};
    zones.forEach(function (zone) {
      var system = hotWater.serves[zone.id], segment = zone.values.building_segment_id;
      if (!system || !segment) return;
      bySegment[segment] = bySegment[segment] || [];
      if (bySegment[segment].indexOf(system) < 0) bySegment[segment].push(system);
    });
    function named(id) {
      return hotWater.systems.filter(function (record) { return record.id === id; })[0].values.name;
    }
    function finding(code, severity, message) {
      return { code: code, severity: severity, message: message, blocks_export: severity === "error" };
    }
    return hotWater.systems.map(function (record) {
      var served = zones.filter(function (zone) { return hotWater.serves[zone.id] === record.id; });
      var count = function (rows) {
        return rows.filter(function (row) { return row.values.hot_water_system_id === record.id; }).length;
      };
      var found = [];
      if (!served.length) found.push(finding("mechanical.item_unserved", "warning",
        record.values.name + " serves no Zone, so nothing exports it."));
      Object.keys(bySegment).sort().forEach(function (segment) {
        var ids = bySegment[segment];
        if (ids.length < 2 || ids.indexOf(record.id) < 0) return;
        found.push(finding("mechanical.hot_water_pooled", "info", ids.map(named).sort().join(", ") +
          " serve Building Segment " + segments[segment] + "; WUFI-Passive and METr pool their tanks and heaters " +
          "and keep one tap point count."));
      });
      if (record.values.piping_calc_method !== undefined && record.values.piping_calc_method !== null) {
        found.push(finding("mechanical.method_not_exported", "info", record.values.name + " sets piping " +
          "calculation method " + record.values.piping_calc_method + ", and the pinned honeybee-ph has no field " +
          "for it, so the export leaves it out."));
      }
      return Object.assign(JSON.parse(JSON.stringify(record)), { findings: found,
        heater_count: count(hotWater.heaters), tank_count: count(hotWater.tanks),
        recirculation: { temperature_c: 60, hours: 24, from_piping: false },
        zones: served.map(function (zone) {
          return { zone_id: zone.id, reference: zone.reference, name: zone.values.name };
        }) });
    });
  };
  /* Each Tank with the slot the host's slotting gives it: storage Tanks fill tank 1 then tank 2, a buffer Tank the
     buffer slot, a solar Tank the solar slot, each role's Tanks in name order; the rest have none. */
  Host.prototype.hotWaterTankRows = function () {
    var tanks = this.mechanical.hotWater.tanks, slots = {};
    var ROLES = { storage: ["tank_1", "tank_2"], buffer: ["tank_buffer"], solar: ["tank_solar"] };
    tanks.slice().sort(function (a, b) {
      var left = a.values.name.toLowerCase(), right = b.values.name.toLowerCase();
      return left < right ? -1 : left > right ? 1 : a.id < b.id ? -1 : 1;
    }).forEach(function (record) {
      var taken = slots[record.values.hot_water_system_id] = slots[record.values.hot_water_system_id] || {};
      var free = ROLES[record.values.role].filter(function (slot) { return !taken[slot]; })[0];
      if (free) taken[free] = record.id;
    });
    return tanks.map(function (record) {
      var taken = slots[record.values.hot_water_system_id] || {}, slot = null;
      Object.keys(taken).forEach(function (key) { if (taken[key] === record.id) slot = key; });
      return Object.assign(JSON.parse(JSON.stringify(record)), { slot: slot, findings: slot ? [] : [{
        code: "mechanical.tank_unslotted", severity: "warning", blocks_export: false,
        message: record.values.name + " is a " + record.values.role + " tank with no free " + record.values.role +
          " slot on its System, so the export leaves it out." }] });
    });
  };
  /* Each heat pump record with what its table shows beside it: the count of records naming it, an indoor unit's
     Zones, and the findings the host gives a unit with nothing to pair. The blend itself is the fixture's. */
  var HEAT_PUMP_COUNTS = { outdoor_equipment: ["unit_count", "outdoor_units", "outdoor_equipment_id"],
    indoor_equipment: ["unit_count", "indoor_units", "indoor_equipment_id"],
    outdoor_units: ["indoor_unit_count", "indoor_units", "outdoor_unit_id"] };
  Host.prototype.heatPumpRows = function (collection) {
    var heatPumps = this.mechanical.heatPumps, zones = this.zones, counter = HEAT_PUMP_COUNTS[collection];
    function served(id) {
      return zones.filter(function (zone) { return (heatPumps.serves[zone.id] || []).indexOf(id) >= 0; });
    }
    return heatPumps[collection].map(function (record) {
      var row = Object.assign(JSON.parse(JSON.stringify(record)), { findings: [] });
      if (counter) row[counter[0]] = heatPumps[counter[1]].filter(function (other) {
        return other.values[counter[2]] === record.id;
      }).length;
      if (collection === "indoor_units") {
        var zonesOf = served(record.id);
        row.zones = zonesOf.map(function (zone) {
          return { zone_id: zone.id, reference: zone.reference, name: zone.values.name };
        });
        if (!zonesOf.length) row.findings.push({ code: "mechanical.hp_unit_unpaired", severity: "warning",
          blocks_export: false, message: record.values.name + " serves no Zone, so the blend leaves it out." });
      }
      if (collection === "outdoor_units" && !heatPumps.indoor_units.some(function (unit) {
        return unit.values.outdoor_unit_id === record.id && served(unit.id).length;
      })) row.findings.push({ code: "mechanical.hp_unit_unpaired", severity: "warning", blocks_export: false,
        message: record.values.name + " has no indoor unit serving a Zone, so the blend leaves it out." });
      return row;
    });
  };
  /* Each Electric Heater with the Zones it serves, and the host's finding for one that serves none. */
  Host.prototype.electricHeaterRows = function () {
    var electric = this.mechanical.electricHeaters, zones = this.zones;
    return electric.heaters.map(function (record) {
      var served = zones.filter(function (zone) { return (electric.serves[zone.id] || []).indexOf(record.id) >= 0; });
      return Object.assign(JSON.parse(JSON.stringify(record)), { findings: served.length ? [] :
        [{ code: "mechanical.item_unserved", severity: "warning", blocks_export: false,
          message: record.values.name + " serves no Zone, so nothing exports it." }],
      zones: served.map(function (zone) {
        return { zone_id: zone.id, reference: zone.reference, name: zone.values.name };
      }) });
    });
  };
  /* Each Pump with the Zones it serves, the usage profile its type gives, and the host's finding for one that serves
     none. */
  var PUMP_PROFILES = { 4: 2, 6: 4, 7: 4, 10: 1 };
  Host.prototype.pumpRows = function () {
    var pumps = this.mechanical.pumps, zones = this.zones;
    return pumps.pumps.map(function (record) {
      var served = zones.filter(function (zone) { return (pumps.serves[zone.id] || []).indexOf(record.id) >= 0; });
      return Object.assign(JSON.parse(JSON.stringify(record)), { findings: served.length ? [] :
        [{ code: "mechanical.item_unserved", severity: "warning", blocks_export: false,
          message: record.values.name + " serves no Zone, so nothing exports it." }],
      ihg_usage_profile_default: PUMP_PROFILES[record.values.device_type],
      zones: served.map(function (zone) {
        return { zone_id: zone.id, reference: zone.reference, name: zone.values.name };
      }) });
    });
  };
  Host.prototype.ventilatorRows = function () {
    var data = this.mechanical, zones = this.zones;
    return data.ventilators.map(function (record) {
      var served = zones.filter(function (zone) { return data.serves[zone.id] === record.id; });
      var flows = served.map(function (zone) { return data.flows[zone.id]; }), balance;
      if (!served.length) balance = { supply_m3h: null, extract_m3h: null, imbalanced: false,
        missing: "It serves no Zone the export writes, so it moves no air." };
      else if (flows.some(function (flow) { return !flow; })) balance = { supply_m3h: null, extract_m3h: null,
        imbalanced: false, missing: "A Zone it serves is By Program, and its Program's ventilation cannot be " +
          "worked out yet." };
      else {
        var supply = flows.reduce(function (sum, flow) { return sum + flow[0]; }, 0);
        var extract = flows.reduce(function (sum, flow) { return sum + flow[1]; }, 0);
        var larger = Math.max(supply, extract);
        balance = { supply_m3h: supply, extract_m3h: extract, missing: null,
          imbalanced: larger > 0 && Math.abs(supply - extract) > 0.1 * larger };
      }
      return Object.assign(JSON.parse(JSON.stringify(record)), { balance: balance, findings: served.length ? [] :
        [{ code: "mechanical.item_unserved", severity: "warning", blocks_export: false,
          message: record.values.name + " serves no Zone, so nothing exports it." }],
      zones: served.map(function (zone) {
        return { zone_id: zone.id, reference: zone.reference, name: zone.values.name };
      }) });
    });
  };
  /* The equipment actions and Assign and Clear, with their guards: a changed expected value, a Zone another item
     fills without `replace`, a Heater whose Type and efficiency values disagree, and a System still named by a Zone,
     Heater or Tank all refuse and write nothing. The kinds' own range and enum checks are not repeated here; the
     panel's tests and the Ruby suite cover them. */
  var MECHANICAL_KINDS = {
    ventilators: { label: "Ventilator", prefix: "vnt", kind: "ventilator", defaults: { quantity: 1,
      sensible_heat_recovery: 0, latent_heat_recovery: 0, electric_efficiency_wh_m3: 0.55,
      frost_protection_reqd: true, temperature_below_defrost_used_c: -5, in_conditioned_space: true } },
    hot_water_systems: { label: "Hot Water System", prefix: "hws", kind: "hot_water_system", defaults: {} },
    hot_water_heaters: { label: "Hot Water Heater", prefix: "hwh", kind: "hot_water_heater", parent: true,
      defaults: { variant: "electric", percent_coverage: 1, in_conditioned_space: true } },
    hot_water_tanks: { label: "Hot Water Tank", prefix: "hwt", kind: "hot_water_tank", parent: true,
      defaults: { role: "storage", tank_type: "2-DHW ONLY", quantity: 1, in_conditioned_space: true,
        solar_connection: false, solar_losses_w: 0, storage_loss_rate_w_k: 0, storage_capacity_l: 300,
        standby_losses_w_k: 4, standby_fraction: 0.3, room_temp_c: 20, water_temp_c: 60 } },
    "heat_pumps.outdoor_equipment": { label: "Heat Pump Outdoor Equipment", prefix: "hpo",
      kind: "hp_outdoor_equipment", defaults: { heating_rating_mode: "cop_pair", cop_17f: 2.5, cop_47f: 2.5,
        hspf_version: "hspf2", seer_version: "seer2" } },
    "heat_pumps.indoor_equipment": { label: "Heat Pump Indoor Equipment", prefix: "hpi",
      kind: "hp_indoor_equipment", defaults: {} },
    "heat_pumps.outdoor_units": { label: "Heat Pump Outdoor Unit", prefix: "hou", kind: "hp_outdoor_unit",
      refs: { outdoor_equipment_id: "outdoor_equipment" }, defaults: { quantity: 1, in_conditioned_space: false } },
    "heat_pumps.indoor_units": { label: "Heat Pump Indoor Unit", prefix: "hiu", kind: "hp_indoor_unit",
      refs: { indoor_equipment_id: "indoor_equipment", outdoor_unit_id: "outdoor_units" },
      defaults: { quantity: 1, in_conditioned_space: true } },
    electric_heaters: { label: "Electric Heater", prefix: "ehr", kind: "electric_heater",
      defaults: { percent_coverage: 1 } },
    pumps: { label: "Pump", prefix: "pmp", kind: "pump", defaults: { device_type: 6, quantity: 1,
      in_conditioned_space: true, norm_energy_demand_w: 0, annual_period_operation_khrs: 8.76,
      ihg_utilization_factor: 1 } }
  };
  /* What names each heat pump collection's records, by collection and key. */
  var HEAT_PUMP_REFERRERS = { outdoor_equipment: [["outdoor_units", "outdoor_equipment_id"]],
    indoor_equipment: [["outdoor_equipment", "paired_indoor_equipment_id"], ["indoor_units", "indoor_equipment_id"]],
    outdoor_units: [["indoor_units", "outdoor_unit_id"]], indoor_units: [] };
  var HEATER_FIELDS = { electric: [], heat_pump_annual: ["total_system_perf_ratio"],
    heat_pump_monthly: ["cop_1", "ambient_temp_1_c", "cop_2", "ambient_temp_2_c"],
    heat_pump_inside: ["annual_energy_factor"] };
  /* A Heater's Type rule, as the kind validates it: its own values numbers, every other Type's absent. */
  function heaterProblem(values) {
    var own = HEATER_FIELDS[values.variant] || [], problem = "";
    Object.keys(HEATER_FIELDS).forEach(function (variant) {
      HEATER_FIELDS[variant].forEach(function (field) {
        var mine = own.indexOf(field) >= 0;
        if (mine && typeof values[field] !== "number") problem = problem || "A " + values.variant + " heater needs " +
          field + ".";
        if (!mine && values[field] !== undefined) problem = problem || "A " + values.variant + " heater takes no " +
          field + ".";
      });
    });
    return problem;
  }
  Host.prototype.mechanicalAction = function (payload) {
    var data = this.mechanical, hotWater = data.hotWater, params = payload.params;
    var name = payload.name.slice(MECHANICAL.length), id, dot = name.lastIndexOf(".");
    var collection = name.slice(0, dot), verb = name.slice(dot + 1), spec = MECHANICAL_KINDS[collection];
    var heatPumps = data.heatPumps, pumpCollection = collection.indexOf("heat_pumps.") === 0 ?
      collection.slice("heat_pumps.".length) : null;
    var records = pumpCollection ? heatPumps[pumpCollection] : { ventilators: data.ventilators,
      hot_water_systems: hotWater.systems, hot_water_heaters: hotWater.heaters, hot_water_tanks: hotWater.tanks,
      electric_heaters: data.electricHeaters.heaters, pumps: data.pumps.pumps }[collection];
    // Each list slot's Zone lists: a Zone may hold several of its items.
    var listSlots = { hp_indoor_unit_ids: heatPumps.serves, heater_ids: data.electricHeaters.serves,
      pump_ids: data.pumps.serves };
    // The flat catalogs whose items a list slot names, by collection.
    var listed = { electric_heaters: data.electricHeaters.serves, pumps: data.pumps.serves };
    var target = records && records.filter(function (record) { return record.id === params.id; })[0];
    var zones = this.zones;
    function copy(value) { return JSON.parse(JSON.stringify(value)); }
    function zoneOf(row) {
      return zones.filter(function (zone) {
        return JSON.stringify(zone.reference) === JSON.stringify(row.reference);
      })[0];
    }
    if (spec && params.id && !target) {
      return refused("target.not_found", "That " + spec.label + " is unavailable.", this.revision);
    }
    if (target && params.expected_values && Object.keys(params.expected_values).some(function (field) {
      var current = target.values[field];
      return JSON.stringify(current === undefined ? null : current) !== JSON.stringify(params.expected_values[field]);
    })) return refused("target.changed", "The " + spec.label + " changed. " + NOTHING_WRITTEN, this.revision);
    if (spec && (verb === "create" || verb === "duplicate")) {
      var values = verb === "create" ? copy(params.values) :
        Object.assign(copy(target.values), { name: params.name || target.values.name + " (copy)" });
      if (spec.parent && !hotWater.systems.some(function (system) {
        return system.id === values.hot_water_system_id;
      })) return refused("reference.invalid", "Choose an existing Hot Water System. " + NOTHING_WRITTEN, this.revision);
      if (spec.refs && Object.keys(spec.refs).some(function (key) {
        return !heatPumps[spec.refs[key]].some(function (other) { return other.id === values[key]; });
      })) return refused("reference.invalid", "Choose existing records to name. " + NOTHING_WRITTEN, this.revision);
      id = spec.prefix + "_preview" + String(++this.sequence).padStart(5, "0");
      var made = { id: id, kind: MECHANICAL + spec.kind, schema_version: 1, user_data: {}, extension_data: {},
        extension_status: {}, export_ready: true, export_blockers: [], findings: [], zones: [], balance: null,
        values: Object.assign({ notes: "", datasheet_links: [], source: { kind: "manual" } }, spec.defaults, values) };
      records.push(made);
    } else if (spec && verb === "update") {
      var next = copy(target.values);
      Object.keys(params.values).forEach(function (field) {
        if (params.values[field] === null) delete next[field]; else next[field] = params.values[field];
      });
      var problem = collection === "hot_water_heaters" ? heaterProblem(next) : "";
      if (problem) return refused("validation.failed", problem + " " + NOTHING_WRITTEN, this.revision);
      target.values = next;
    } else if (spec && verb === "delete" && pumpCollection) {
      var namers = [], replacement = params.replacement_id;
      HEAT_PUMP_REFERRERS[pumpCollection].forEach(function (entry) {
        heatPumps[entry[0]].forEach(function (other) {
          if (other.values[entry[1]] === target.id) namers.push([other, entry[1], entry[0] !== "outdoor_equipment"]);
        });
      });
      var zonesUsing = Object.keys(heatPumps.serves).filter(function (zone) {
        return heatPumps.serves[zone].indexOf(target.id) >= 0;
      });
      // No replacement refuses while anything names it; null empties a pairing and the Zones' lists, and a unit
      // still naming it (a required reference) refuses; an id must name a record of the same kind.
      if (replacement === undefined && (namers.length || zonesUsing.length) ||
        replacement === null && namers.some(function (entry) { return entry[2]; })) {
        return refused("reference.in_use", target.values.name + " is in use. " + NOTHING_WRITTEN, this.revision);
      }
      if (replacement && !records.some(function (record) { return record.id === replacement; })) {
        return refused("target.not_found", "That replacement is unavailable. " + NOTHING_WRITTEN, this.revision);
      }
      namers.forEach(function (entry) {
        if (replacement) entry[0].values[entry[1]] = replacement; else delete entry[0].values[entry[1]];
      });
      zonesUsing.forEach(function (zone) {
        var list = heatPumps.serves[zone].filter(function (id) { return id !== target.id; });
        if (replacement && list.indexOf(replacement) < 0) list.push(replacement);
        heatPumps.serves[zone] = list;
      });
      records.splice(records.indexOf(target), 1);
    } else if (spec && verb === "delete" && listed[collection]) {
      var itemLists = listed[collection], itemZones = Object.keys(itemLists).filter(function (zone) {
        return itemLists[zone].indexOf(target.id) >= 0;
      });
      if (params.replacement_id === undefined && itemZones.length) {
        return refused("reference.in_use", target.values.name + " is in use. " + NOTHING_WRITTEN, this.revision);
      }
      itemZones.forEach(function (zone) {
        var list = itemLists[zone].filter(function (id) { return id !== target.id; });
        if (params.replacement_id && list.indexOf(params.replacement_id) < 0) list.push(params.replacement_id);
        itemLists[zone] = list;
      });
      records.splice(records.indexOf(target), 1);
    } else if (spec && verb === "delete") {
      var served = collection === "hot_water_systems" ? hotWater.serves : data.serves;
      var using = Object.keys(served).filter(function (zone) { return served[zone] === target.id; });
      var members = collection === "hot_water_systems" ? hotWater.heaters.concat(hotWater.tanks).filter(
        function (member) { return member.values.hot_water_system_id === target.id; }) : [];
      if ((using.length || members.length) && params.replacement_id === undefined) {
        return refused("reference.in_use", target.values.name + " is in use. " + NOTHING_WRITTEN, this.revision);
      }
      if (members.length && !params.replacement_id) {
        return refused("reference.in_use", members.map(function (member) { return member.values.name; }).join(", ") +
          " name " + target.values.name + ". " + NOTHING_WRITTEN, this.revision);
      }
      using.forEach(function (zone) {
        if (params.replacement_id) served[zone] = params.replacement_id; else delete served[zone];
      });
      members.forEach(function (member) { member.values.hot_water_system_id = params.replacement_id; });
      records.splice(records.indexOf(target), 1);
    } else if ((name === "serves.assign" || name === "serves.clear") && listSlots[params.slot]) {
      var lists = listSlots[params.slot], chosen = params.zones.map(zoneOf);
      if (chosen.some(function (zone) { return !zone; })) {
        return refused("target.not_found", "A Zone is unavailable. " + NOTHING_WRITTEN, this.revision);
      }
      // Any slot read before another write refuses the whole command, as the host's guard does.
      if (params.zones.some(function (row, index) {
        var zone = chosen[index].id, expected = row.expected_values || {};
        var current = { ventilator_id: data.serves[zone] || null, hot_water_system_id: hotWater.serves[zone] || null,
          hp_indoor_unit_ids: heatPumps.serves[zone] || [], heater_ids: data.electricHeaters.serves[zone] || [],
          pump_ids: data.pumps.serves[zone] || [] };
        return Object.keys(expected).some(function (slot) {
          return JSON.stringify(expected[slot]) !== JSON.stringify(current[slot]);
        });
      })) return refused("target.changed", "A Zone changed since it was read. " + NOTHING_WRITTEN, this.revision);
      chosen.forEach(function (zone) {
        var list = (lists[zone.id] || []).filter(function (id) {
          return name === "serves.assign" ? id !== params.item_id : params.item_id && id !== params.item_id;
        });
        if (name === "serves.assign") list.push(params.item_id);
        lists[zone.id] = list;
      });
    } else if (name === "serves.assign" || name === "serves.clear") {
      var slot = params.slot, map = slot === "hot_water_system_id" ? hotWater.serves : data.serves;
      var items = slot === "hot_water_system_id" ? hotWater.systems : data.ventilators;
      var picked = params.zones.map(zoneOf);
      if (picked.some(function (zone) { return !zone; })) {
        return refused("target.not_found", "A Zone is unavailable. " + NOTHING_WRITTEN, this.revision);
      }
      if (params.zones.some(function (row, index) {
        return (row.expected_values || {})[slot] !== undefined &&
          (map[picked[index].id] || null) !== row.expected_values[slot];
      })) return refused("target.changed", "A Zone changed since it was read. " + NOTHING_WRITTEN, this.revision);
      if (name === "serves.assign" && !params.replace) {
        var filled = picked.filter(function (zone) {
          return map[zone.id] && map[zone.id] !== params.item_id;
        })[0];
        if (filled) {
          var other = items.filter(function (record) { return record.id === map[filled.id]; })[0];
          return refused("mechanical.slot_filled", "Zone " + filled.values.name + " is served by " +
            (other ? other.values.name : "another item") + ". Replace it to assign. " + NOTHING_WRITTEN,
          this.revision);
        }
      }
      picked.forEach(function (zone) {
        if (name === "serves.assign") map[zone.id] = params.item_id; else delete map[zone.id];
      });
    } else return refused("request.unknown_operation", "Unavailable fixture action.", this.revision);
    this.revision += 1;
    return { status: "completed", code: "ok", message: "Done.", effect: "committed", revision: this.revision,
      value: { id: id || params.id }, affected: [], findings: [], detail: null };
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
    // Convert answers that it ran; the synthetic Types and Units are not changed.
    if (name === "units.convert") return Object.assign(completed({ units: [], created_type_ids: [] }),
      { code: "ok", message: "Converted to Window Type.", affected: [], findings: [], detail: null });
    if (name === "units.rename") {
      var named = this.windows.units.units.filter(function (unit) {
        return JSON.stringify(unit.reference) === JSON.stringify(params.unit);
      })[0];
      if (!named || (named.name || "") !== params.expected_name) {
        return refused("target.changed", "This Window's name changed in the Model.", this.revision);
      }
      named.name = params.name; return completed({ unit_id: named.id, name: params.name });
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
        payload.name.indexOf("ph_composer.zones.faces.attached_zone.") === 0 ||
        // The device dialog's own request (record_form.js) is answered later, as SketchUp answers it.
        /^ph_composer\.programs\.equipment_sets\.(add|update)_device$/.test(payload.name)) {
      this.window.setTimeout(apply, 0);
    } else apply();
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
    if (payload.name.indexOf(MECHANICAL) === 0) return this.mechanicalAction(payload);
    if (payload.name.indexOf(CLIMATE) === 0) return this.climateAction(payload);
    if (payload.name === "ph_composer.library.copy") return this.libraryCopy(payload);
    if (payload.name.indexOf("ph_composer.assemblies.") === 0 ||
        payload.name.indexOf("ph_composer.zones.faces.attached_zone.") === 0) return this.inventoryAction(payload);
    if (payload.name === "ph_composer.zones.options.manage") return this.manageZoneOptions(payload.params);
    var catalogOutcome = this.programCatalogAction(payload);
    if (catalogOutcome) return catalogOutcome;
    var programsOutcome = this.programsAction(payload);
    if (programsOutcome) return programsOutcome;
    var segmentOutcome = this.segmentAction(payload);
    if (segmentOutcome) return segmentOutcome;
    var airflowOutcome = this.spacesAirflowAction(payload);
    if (airflowOutcome) return airflowOutcome;
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

  /* Synthetic Spaces airflow writes: a cell edit or a batch that changes only Space rates, and From Program. The
     rates land on the Space rows and the section is summed again by the fixtures' rule, so a Zone's airflow mode
     follows its Spaces' rates as Ruby's does. Null for any other write. */
  Host.prototype.spacesAirflowAction = function (payload) {
    var section = this.spaces, keys = ["v_sup_m3h", "v_eta_m3h", "v_tran_m3h"];
    if (!section || !section.spaces) return null;
    function find(reference) {
      return section.spaces.filter(function (space) {
        return JSON.stringify(space.reference) === JSON.stringify(reference);
      })[0];
    }
    if (payload.name === "ph_composer.spaces.clear_zone_airflows") {
      var ids = payload.params.zones.map(function (zone) { return zone.zone_id; });
      section.spaces.forEach(function (space) {
        if (!space.zone || ids.indexOf(space.zone.zone_id) < 0) return;
        keys.forEach(function (key) { delete space.values[key]; });
      });
    } else if (payload.name === "ph_composer.spaces.update" || payload.name === "ph_composer.spaces.batch_update") {
      var edits = payload.params.edits || [payload.params];
      var rates = edits.every(function (edit) {
        return find(edit.reference) && Object.keys(edit.values).every(function (key) {
          return keys.indexOf(key) >= 0;
        });
      });
      if (!rates) return null;
      edits.forEach(function (edit) {
        var space = find(edit.reference);
        Object.keys(edit.values).forEach(function (key) {
          if (edit.values[key] === null) delete space.values[key];
          else space.values[key] = edit.values[key];
        });
      });
    } else return null;
    this.spaces = this.window.PhComposerPreviewFixtures.spacesSection(section.spaces, this.zones);
    this.revision += 1;
    return { status: "completed", code: "ok", message: "Done.", effect: "committed", revision: this.revision,
      value: {}, affected: [], findings: [], detail: null };
  };

  /* The Programs the occupancy read offers, as library resolution reads local records: a copied one carries its
     source. */
  Host.prototype.programRecords = function () {
    var sources = this.programSources || {};
    var chosen = ((this.occupancy || {}).choices || { programs: [] }).programs.map(function (program) {
      return { id: program.id, values: { name: program.name, source: sources[program.id] || null } };
    });
    // The Programs tab's catalog adds what the occupancy choices do not name, such as a copy made from its sidebar.
    return chosen.concat(((this.programCatalog || {}).programs || []).filter(function (row) {
      return !chosen.some(function (program) { return program.id === row.id; });
    }));
  };

  Host.prototype.catalogSection = function (collection) {
    if (!this.programCatalog) return undefined;
    return { status: "completed", value: { records: JSON.parse(JSON.stringify(this.programCatalog[collection])),
      unreadable: [] } };
  };

  /* Synthetic Programs tab writes over the three catalogs: create, update, duplicate, delete with a replacement,
     and reset. It refuses a changed expected value with nothing written, a used record's delete without a
     replacement, and a taken name, as features/programs/operations.rb does; the rest of Ruby's rules (the
     Schedule a slot names, the fraction caps) are not modelled. A Program's `missing` is worked out again only for
     its main values. Null for any other action. */
  Host.prototype.programCatalogAction = function (payload) {
    var host = this, catalog = this.programCatalog, params = payload.params || {};
    var match = new RegExp("^ph_composer\\.programs\\.(programs|schedules|equipment_sets)\\." +
      "(create|update|duplicate|delete|add_device|update_device|delete_device)$").exec(payload.name);
    var reset = payload.name === "ph_composer.programs.reset_default";
    if (!catalog || (!match && !reset)) return null;
    function clone(value) { return JSON.parse(JSON.stringify(value)); }
    function completed(value) { host.revision++; return { status: "completed", code: "ok", effect: "committed",
      revision: host.revision, value: value, affected: [], findings: [], detail: null }; }
    if (reset) {
      var id = params.kind === "program" ? "pgm_PHCDEFAULT01" : "eqs_PHCDEFAULT01";
      var row = (catalog[params.kind === "program" ? "programs" : "equipment_sets"]).filter(function (entry) {
        return entry.id === id; })[0];
      var pristine = (host.window.PhComposerPreviewFixtures.fromQuery("?fixture=programs").programCatalog ||
        {})[params.kind === "program" ? "programs" : "equipment_sets"].filter(function (entry) {
          return entry.id === id; })[0];
      if (row && pristine) row.values = clone(pristine.values);
      return completed({ id: id, removed_user_data: [] });
    }
    var collection = match[1], verb = match[2], rows = catalog[collection];
    var label = { programs: "Program", schedules: "Schedule", equipment_sets: "Equipment Set" }[collection];
    function find(id) { return rows.filter(function (entry) { return entry.id === id; })[0]; }
    function taken(name, except) {
      return rows.some(function (entry) { return entry.id !== except &&
        entry.values.name.trim().toLowerCase() === String(name).trim().toLowerCase(); });
    }
    function freeName(stem) {
      for (var n = 1; ; n++) { var name = stem + " " + n; if (!taken(name)) return name; }
    }
    function stale(row, expected) {
      return Object.keys(expected || {}).some(function (key) {
        return JSON.stringify(row.values[key] === undefined ? null : row.values[key]) !== JSON.stringify(expected[key]);
      });
    }
    function remissing(row) {
      if (collection !== "programs") return;
      var values = row.values, gaps = [];
      [["people", "people_per_area"], ["lighting", "watts_per_area"], ["electric_equipment", "watts_per_area"],
        ["gas_equipment", "watts_per_area"], ["service_hot_water", "flow_per_area"],
        ["infiltration", "flow_per_exterior_area"], ["setpoint", "heating_c"], ["setpoint", "cooling_c"]]
        .forEach(function (pair) {
          var load = values[pair[0]];
          var schedule = pair[0] === "setpoint" && load[pair[1].replace("_c", "_schedule_id")];
          if (!load.rule && !schedule && (load[pair[1]] === null || load[pair[1]] === undefined)) {
            gaps.push({ load: pair[0], field: pair[1] });
          }
        });
      if (["flow_per_person", "flow_per_area", "flow_per_zone", "air_changes_per_hour"].every(function (key) {
        return values.ventilation[key] === null || values.ventilation[key] === undefined;
      })) gaps.splice(gaps.length - 2, 0, { load: "ventilation", field: "flow_per_person" });
      row.missing = gaps;
    }
    var row = params.id && find(params.id);
    if (verb !== "create" && !row) return refused("target.not_found", "That " + label + " is gone.", host.revision);
    if (/_device$/.test(verb)) return this.deviceAction(row, verb, params, completed);
    if (verb === "create") {
      var values = clone(params.values || {});
      values.name = values.name || freeName(label);
      var template = rows.filter(function (entry) { return !entry.default; })[0] || rows[0];
      row = clone(template);
      row.id = collection.slice(0, 3) + "_preview" + (++host.sequence);
      row.default = false; row.use_count = 0; row.stored = true;
      if (row.uses) row.uses = [];
      row.values = Object.assign(clone(template.values), { source: { kind: "manual" } }, values);
      if (collection === "programs") {
        Object.keys(row.values).forEach(function (key) {
          var load = row.values[key];
          if (load && typeof load === "object" && !Array.isArray(load) && key !== "source") {
            Object.keys(load).forEach(function (field) {
              if (field !== "radiant_fraction" && !/fraction|target_temperature/.test(field)) load[field] = null;
            });
          }
        });
      }
      if (collection === "equipment_sets") row.values.devices = [];
      if (collection === "schedules") {
        // The type's own form, as features/programs/schedule.rb's FORM_DEFAULTS gives it.
        var type = values.type || "fractional";
        row.values = Object.assign({ name: values.name, notes: "", datasheet_links: [], source: { kind: "manual" },
          type: type, days_per_week: 7, weeks_per_year: 52 }, clone(SCHEDULE_FORMS[type]), values);
        row.profile = scheduleProfile(row.values);
      }
      remissing(row); rows.push(row);
      return completed({ id: row.id });
    }
    if (verb === "update") {
      if (stale(row, params.expected_values)) {
        return refused("target.changed", label + " " + row.values.name + " has changed since it was read.",
          host.revision);
      }
      if (params.values.name !== undefined && taken(params.values.name, row.id)) {
        return refused("validation.failed", "Another " + label + " is named " + params.values.name + ".",
          host.revision);
      }
      if (params.values.periods && params.values.periods.reduce(function (sum, period) {
        return sum + period.hours; }, 0) !== 24) {
        return refused("validation.failed", "Ventilation period hours must total 24.", host.revision);
      }
      Object.assign(row.values, clone(params.values)); row.stored = true; remissing(row);
      if (collection === "schedules") row.profile = scheduleProfile(row.values);
      return completed({ id: row.id });
    }
    if (verb === "duplicate") {
      var copy = clone(row);
      copy.id = row.id.slice(0, 3) + "_preview" + (++host.sequence);
      copy.values.name = row.values.name + " (copy)";
      for (var n = 2; taken(copy.values.name); n++) copy.values.name = row.values.name + " (copy " + n + ")";
      copy.values.source = { kind: "derived" }; copy.default = false; copy.use_count = 0; copy.stored = true;
      if (copy.uses) copy.uses = [];
      rows.push(copy);
      return completed({ id: copy.id });
    }
    if (stale(row, params.expected_values)) {
      return refused("target.changed", label + " " + row.values.name + " has changed since it was read.",
        host.revision);
    }
    if ((row.use_count > 0 || row.default) && !params.replacement_id) {
      return refused(row.default ? "programs.default_in_use" : "reference.in_use", label + " " + row.values.name +
        " is in use; name a replacement to delete it.", host.revision);
    }
    var replacement = params.replacement_id && find(params.replacement_id);
    if (replacement) {
      replacement.use_count += row.use_count;
      if (row.default) replacement.default = true;
    }
    catalog[collection] = rows.filter(function (entry) { return entry.id !== row.id; });
    return completed({ id: row.id, removed_user_data: [] });
  };

  /* One device added, edited or deleted, as features/programs/operations.rb does it: a new device holds the values
     sent (the dialog sends them all); an edit or delete refuses a changed expected value with nothing written. Type
     rules are not checked. */
  Host.prototype.deviceAction = function (set, verb, params, completed) {
    var host = this, devices = set.values.devices;
    function clone(value) { return JSON.parse(JSON.stringify(value)); }
    if (verb === "add_device") {
      var id = "dev_preview" + (++host.sequence);
      devices.push(Object.assign({ id: id, type: params.type }, clone(params.values || {})));
      set.stored = true;
      return completed({ id: set.id, device_id: id });
    }
    var device = devices.filter(function (entry) { return entry.id === params.device_id; })[0];
    if (!device) return refused("target.not_found", "That device is gone.", host.revision);
    var expected = params.expected_values || {};
    if (Object.keys(expected).some(function (key) {
      return JSON.stringify(device[key] === undefined ? null : device[key]) !== JSON.stringify(expected[key]);
    })) {
      return refused("target.changed", "Device " + device.display_name + " has changed since it was read.",
        host.revision);
    }
    if (verb === "update_device") {
      Object.keys(params.values).forEach(function (key) {
        if (params.values[key] === null) delete device[key]; else device[key] = params.values[key];
      });
    } else set.values.devices = devices.filter(function (entry) { return entry !== device; });
    set.stored = true;
    return completed({ id: set.id, device_id: params.device_id, removed_user_data: [] });
  };

  /* A library Program copied from the Programs tab's sidebar: it arrives in the catalog with its source. */
  Host.prototype.programCatalogCopy = function (params) {
    var rows = this.libraryCatalogs[params.provider_id] || [];
    var incoming = rows.filter(function (row) {
      return row.kind === "programs" && row.library_id === params.library_id && row.record_id === params.record_id;
    })[0];
    if (!incoming || params.generation !== this.libraryGenerations[params.provider_id]) {
      return refused("library.generation_stale", "The catalog changed. Refresh and choose again.", this.revision);
    }
    var template = JSON.parse(JSON.stringify(this.programCatalog.programs.filter(function (row) {
      return row.id === "pgm_office"; })[0]));
    template.id = "pgm_library" + (++this.sequence); template.use_count = 0; template.default = false;
    template.values.name = incoming.snapshot.name;
    template.values.source = { kind: "library", library_id: incoming.library_id, record_id: incoming.record_id,
      library_name: incoming.library_name, snapshot: JSON.parse(JSON.stringify(incoming.snapshot)) };
    this.programCatalog.programs.push(template);
    this.revision += 1;
    return { status: "completed", effect: "committed", revision: this.revision, value: { local_id: template.id,
      assigned: false, dependencies: [] }, message: "Library copy applied." };
  };

  /* Synthetic Programs writes for the Zones / Programs view over the occupancy read: a Program (from this file or
     copied from a library row), a Dwelling, a Zone's counts, an Equipment Set and a Dwelling's own values. The
     rules they enforce are Ruby's (features/programs/assignments.rb); this answers only enough of them to drive
     the panel: it refuses a single dwelling's Zone, a Dwelling across two Segments and counts on a Zone in none, as
     Ruby does. It is a simulation, not the contract: a library copy only creates, its Schedules are not modelled,
     and the people and ventilation it fills in are illustrative. Null for any other action. */
  Host.prototype.programsAction = function (payload) {
    var host = this, section = this.occupancy, params = payload.params, name = payload.name;
    var prefix = "ph_composer.programs.";
    if (!section || name.indexOf(prefix) !== 0) return null;
    var verb = name.slice(prefix.length);
    function zoneOf(reference) {
      return section.zones.filter(function (row) { return row.zone_id === reference.zone_id; })[0];
    }
    function dwelling(id) { return section.dwellings.filter(function (row) { return row.id === id; })[0]; }
    function program(id) { return section.choices.programs.filter(function (row) { return row.id === id; })[0]; }
    function done(value) {
      host.recountDwellings();
      host.revision++;
      return { status: "completed", code: "ok", effect: "committed", revision: host.revision, value: value || {},
        affected: [], findings: [], detail: null };
    }
    var zones = (params.zones || []).map(zoneOf);
    if (params.zone) zones = [zoneOf(params.zone)];
    var locked = zones.filter(function (row) { return row && row.single_dwelling; })[0];
    if (locked) {
      return refused("programs.single_dwelling", locked.name + " is in a single dwelling: switch Single dwelling " +
        "off in its settings to assign its Zones. Nothing was written.", this.revision);
    }
    function assign(id) {
      zones.forEach(function (row) {
        var segment = section.building_segments.filter(function (entry) {
          return entry.id === row.building_segment_id;
        })[0];
        row.assignment.program_id = id;
        row.program_id = id || segment.settings.default_program_id || section.choices.default_program_id;
        row.program_name = program(row.program_id).name;
        row.findings = row.findings.filter(function (finding) { return finding.code !== "programs.unassigned_zone"; });
      });
      section.building_segments.forEach(function (segment) {
        segment.findings = segment.findings.filter(function (finding) {
          return finding.code !== "programs.unassigned_zone" || section.zones.some(function (row) {
            return row.building_segment_id === segment.id && row.findings.some(function (own) {
              return own.code === "programs.unassigned_zone";
            });
          });
        });
      });
    }
    if (verb === "assign_program") { assign(params.program_id); return done({ program_id: params.program_id }); }
    if (verb === "assign_library_program") {
      var copy = params.copy, row = (this.libraryCatalogs[copy.provider_id] || []).filter(function (entry) {
        return entry.kind === "programs" && entry.record_id === copy.record_id;
      })[0];
      if (!row || copy.generation !== this.libraryGenerations[copy.provider_id]) {
        return refused("library.catalog_stale", "The library changed. Choose again. Nothing was written.",
          this.revision);
      }
      var id = copy.local_id;
      if (copy.choice === "create") {
        id = "pgm_library" + (++this.sequence);
        section.choices.programs.push({ id: id, name: row.snapshot.name });
        section.choices.programs.sort(function (a, b) { return a.name.localeCompare(b.name); });
        this.programSources = this.programSources || {};
        this.programSources[id] = { kind: "library", library_id: row.library_id, record_id: row.record_id,
          snapshot: JSON.parse(JSON.stringify(row.snapshot)) };
      }
      assign(id);
      return done({ program_id: id, zone_ids: zones.map(function (entry) { return entry.zone_id; }),
        dependencies: [] });
    }
    if (verb === "assign_dwelling") {
      var target = params.choice === "existing" ? params.dwelling_id : null;
      var joined = target ? dwelling(target) : null;
      if (joined && zones.concat(section.zones.filter(function (row) {
        return row.assignment.dwelling_id === target;
      })).some(function (row) { return row.building_segment_id !== zones[0].building_segment_id; })) {
        return refused("programs.dwelling_across_segments", joined.name + " would hold Zones in two Building " +
          "Segments; a Dwelling lies in one. Nothing was written.", this.revision);
      }
      function make(stem) {
        var made = { id: "dwl_preview" + (++host.sequence), name: stem, units: 1, single_dwelling: false,
          own_bedrooms: null, own_occupants: null, bedrooms: null, occupants: null, occupants_rule: false,
          equipment_set_id: null, zone_ids: [], building_segment_ids: [], floor_area_m2: 0, icfa_m2: 0,
          findings: [] };
        section.dwellings.push(made);
        return made.id;
      }
      if (params.choice === "shared") target = make(zones[0].name);
      zones.forEach(function (row) {
        var id = params.choice === "each" ? make(row.name) : params.choice === "none" ? null : target;
        row.assignment.dwelling_id = id;
        if (!id) { row.assignment.bedrooms = null; row.assignment.occupants = null; }
      });
      return done({});
    }
    if (verb === "set_counts" && !zones[0].assignment.dwelling_id) {
      return refused("validation.failed", zones[0].name + " is in no Dwelling, so it holds no counts. Nothing was " +
        "written.", this.revision);
    }
    if (verb === "set_counts") {
      zones[0].assignment.bedrooms = params.bedrooms; zones[0].assignment.occupants = params.occupants;
      return done({ zone_id: zones[0].zone_id });
    }
    if (verb === "assign_equipment_set") {
      (params.dwelling_ids || []).forEach(function (id) { dwelling(id).equipment_set_id = params.equipment_set_id; });
      zones.forEach(function (row) { row.assignment.equipment_set_id = params.equipment_set_id; });
      return done({});
    }
    if (verb === "dwellings.update") {
      var record = dwelling(params.id);
      var key = Object.keys(params.values)[0], seen = key === "units" ? record.units : record.own_bedrooms;
      if (seen !== params.expected_values[key]) {
        return refused("target.changed", "The Dwelling changed since it was read. Nothing was written.",
          this.revision);
      }
      if (key === "units") record.units = params.values.units; else record.own_bedrooms = params.values.bedrooms;
      return done({ id: record.id });
    }
    return null;
  };

  /* What every Dwelling and Zone row reads after a write: each Dwelling's Zones, counts by the Phius rule, areas
     and Set, each Zone's Dwelling name, units, counts' findings, and each Segment's heading sums. An emptied
     Dwelling goes, as Ruby deletes it. */
  Host.prototype.recountDwellings = function () {
    var section = this.occupancy;
    section.dwellings = section.dwellings || [];
    // A single dwelling's house (a null id) stays while its Segment is single; any other Dwelling while a Zone
    // names it.
    section.dwellings = section.dwellings.filter(function (record) {
      if (record.single_dwelling) return section.building_segments.some(function (segment) {
        return segment.single_dwelling && record.building_segment_ids.indexOf(segment.id) >= 0;
      });
      return section.zones.some(function (row) { return row.assignment.dwelling_id === record.id; });
    });
    section.dwellings.forEach(function (record) {
      if (record.single_dwelling) return;
      var members = section.zones.filter(function (row) { return row.assignment.dwelling_id === record.id; });
      function sum(key) {
        var values = members.map(function (row) { return row.assignment[key]; }).filter(function (value) {
          return value !== null && value !== undefined;
        });
        return values.length ? values.reduce(function (a, b) { return a + b; }, 0) : null;
      }
      record.zone_ids = members.map(function (row) { return row.zone_id; });
      record.building_segment_ids = members.map(function (row) { return row.building_segment_id; })
        .filter(function (id, index, all) { return all.indexOf(id) === index; });
      record.bedrooms = record.own_bedrooms !== null ? record.own_bedrooms : sum("bedrooms");
      var occupants = record.own_occupants !== null ? record.own_occupants : sum("occupants");
      record.occupants_rule = occupants === null && record.bedrooms !== null;
      record.occupants = record.occupants_rule ? record.bedrooms + record.units : occupants;
      record.floor_area_m2 = members.reduce(function (a, row) { return a + row.floor_area_m2; }, 0);
      record.icfa_m2 = members.reduce(function (a, row) { return a + row.icfa_m2; }, 0);
    });
    section.zones.forEach(function (row) {
      if (row.single_dwelling) return;
      var record = section.dwellings.filter(function (entry) { return entry.id === row.assignment.dwelling_id; })[0];
      row.dwelling_id = record ? record.id : null; row.dwelling_name = record ? record.name : null;
      row.dwelling_units = record ? record.units : null;
      row.equipment_set_id = record ? record.equipment_set_id : row.assignment.equipment_set_id;
      if (record && record.occupants !== null && row.people === null) {
        row.people = Math.round(record.occupants * row.floor_area_m2 / record.floor_area_m2 * 100) / 100;
        delete row.missing.people;
      }
    });
    section.building_segments.forEach(function (segment) {
      var members = section.zones.filter(function (row) { return row.building_segment_id === segment.id; });
      var counted = segment.single_dwelling && segment.dwelling ? [segment.dwelling] :
        section.dwellings.filter(function (record) { return record.building_segment_ids.indexOf(segment.id) >= 0; });
      function total(rows, key) {
        var values = rows.map(function (row) { return row[key]; }).filter(function (value) { return value !== null; });
        return values.length ? values.reduce(function (a, b) { return a + b; }, 0) : null;
      }
      // A fixture written before the heading sums (zoneoptions) has none to keep.
      if (!segment.sums) return;
      segment.sums.bedrooms = total(counted, "bedrooms"); segment.sums.occupants = total(counted, "occupants");
      ["people", "lighting_w", "ventilation_m3h"].forEach(function (key) {
        segment.sums[key] = total(members, key);
        var index = segment.sums.incomplete.indexOf(key), lacking = members.some(function (row) {
          return row[key] === null;
        });
        if (lacking && index < 0) segment.sums.incomplete.push(key);
        if (!lacking && index >= 0) segment.sums.incomplete.splice(index, 1);
      });
      if (!segment.single_dwelling && segment.category === "residential") {
        var none = !counted.length;
        segment.findings = segment.findings.filter(function (finding) {
          return finding.code !== "programs.residential_without_dwelling";
        });
        if (none) segment.findings.push({ code: "programs.residential_without_dwelling", severity: "warning",
          message: segment.name + " is residential and has no Dwelling." });
      }
    });
  };

  /* The Segment's occupancy as a settings Save leaves it: the house's counts while single (occupants by the Phius
     rule when empty, and the Zones' people from them), and on switching off, one Dwelling named for the Segment
     holding them, which every Zone joins unlocked, as features/programs/single_dwelling.rb does. */
  Host.prototype.occupancySettingsSaved = function (id, payload) {
    var section = this.occupancy;
    if (!section) return;
    section.dwellings = section.dwellings || [];
    var segment = section.building_segments.filter(function (entry) { return entry.id === id; })[0];
    if (!segment) return;
    var members = section.zones.filter(function (row) { return row.building_segment_id === id; });
    var wasSingle = segment.single_dwelling;
    segment.settings = Object.assign({}, segment.settings, payload);
    segment.stored = true;
    if (segment.category !== "residential") return;
    if (wasSingle && !payload.single_dwelling) {
      var record = { id: "dwl_preview" + (++this.sequence), name: segment.name, units: 1, single_dwelling: false,
        own_bedrooms: payload.bedrooms, own_occupants: payload.occupants, bedrooms: null, occupants: null,
        occupants_rule: false, equipment_set_id: payload.equipment_set_id, zone_ids: [], building_segment_ids: [],
        floor_area_m2: 0, icfa_m2: 0, findings: [] };
      section.dwellings.push(record);
      segment.single_dwelling = false; segment.dwelling = null;
      members.forEach(function (row) {
        row.single_dwelling = false; row.assignment.dwelling_id = record.id;
      });
    } else if (segment.single_dwelling) {
      var bedrooms = payload.bedrooms, rule = payload.occupants === null && bedrooms !== null;
      var occupants = rule ? bedrooms + 1 : payload.occupants;
      segment.dwelling = { name: segment.name, units: 1, bedrooms: bedrooms, occupants: occupants,
        occupants_rule: rule, equipment_set_id: payload.equipment_set_id };
      section.dwellings.forEach(function (row) {
        if (!row.single_dwelling || row.building_segment_ids.indexOf(id) < 0) return;
        Object.assign(row, { bedrooms: bedrooms, occupants: occupants, occupants_rule: rule,
          equipment_set_id: payload.equipment_set_id });
      });
      var area = members.reduce(function (a, row) { return a + row.floor_area_m2; }, 0);
      members.forEach(function (row) {
        row.equipment_set_id = payload.equipment_set_id;
        if (occupants === null) return;
        row.people = Math.round(occupants * row.floor_area_m2 / area * 100) / 100;
        row.ventilation_m3h = Math.round(row.people * 30 + row.floor_area_m2 * 1.08);
        row.missing = {};
      });
    }
    this.recountDwellings();
  };

  /* Synthetic Building Segment writes for the Zones tab's heading rows and settings dialog: New (with Zones moved
     in), rename, delete with a destination, Save and moving Zones. The rules they enforce are Ruby's; this answers
     only enough of them to drive the panel. Null for any other action. */
  Host.prototype.segmentAction = function (payload) {
    var host = this, params = payload.params, segments = this.zoneOptions.building_segments;
    function find(id) { return segments.filter(function (entry) { return entry.id === id; })[0]; }
    function move(targets, id) {
      var moved = [];
      targets.forEach(function (target) {
        var zone = host.zones.filter(function (item) {
          return item.reference.zone_id === target.reference.zone_id;
        })[0];
        if (zone) { zone.values.building_segment_id = id; moved.push(zone.reference.zone_id); }
      });
      segments.forEach(function (entry) {
        entry.usage = { live: host.zones.filter(function (zone) {
          return zone.values.building_segment_id === entry.id;
        }).length, recoverable: 0 };
      });
      return moved;
    }
    function done(value) {
      host.revision++;
      return { status: "completed", code: "ok", effect: "committed", revision: host.revision, value: value || {},
        affected: [], findings: [], detail: null };
    }
    if (payload.name === "ph_composer.zones.create_segment") {
      var number = segments.length + 1;
      while (segments.some(function (entry) { return entry.values.name === "Building Segment " + number; })) number++;
      var id = "bsg_preview" + String(++this.sequence).padStart(5, "0");
      segments.push({ id: id, schema_version: 1, values: { name: "Building Segment " + number, colour: params.colour,
        export_identifier: "segment_" + id }, usage: { live: 0, recoverable: 0 }, extension_data: {} });
      return done({ id: id, name: "Building Segment " + number, zone_ids: move(params.targets || [], id) });
    }
    if (payload.name === "ph_composer.zones.update_field" && params.field === "building_segment") {
      var named = params.value === null ? null : segments.filter(function (entry) {
        return entry.values.name === params.value;
      })[0];
      if (params.value !== null && !named) {
        return refused("reference.invalid", "Choose an existing Segment.", this.revision);
      }
      return done({ zone_ids: move(params.targets, named ? named.id : null) });
    }
    if (payload.name === "ph_composer.zones.options.update" && params.collection === "building_segment") {
      var renamed = find(params.id);
      if (!renamed || renamed.values.name !== params.expected_values.name) {
        return refused("target.changed", "That Segment changed.", this.revision);
      }
      if (segments.some(function (entry) { return entry !== renamed && entry.values.name === params.values.name; })) {
        return refused("zone.option_duplicate", "An equivalent option already exists. Nothing was written.",
          this.revision);
      }
      renamed.values.name = params.values.name; renamed.values.colour = params.values.colour;
      return done({ id: renamed.id });
    }
    if (payload.name === "ph_composer.zones.options.remove" && params.collection === "building_segment") {
      if (segments.length < 2) {
        return refused("zone.option_last_segment", "Keep at least one Building Segment. Nothing was written.",
          this.revision);
      }
      var destination = params.replacement_id === undefined ? null : params.replacement_id;
      move(this.zones.filter(function (zone) { return zone.values.building_segment_id === params.id; })
        .map(function (zone) { return { reference: zone.reference }; }), destination);
      this.zoneOptions.building_segments = segments.filter(function (entry) { return entry.id !== params.id; });
      if (this.zoneOptions.default_segment_id === params.id) {
        this.zoneOptions.default_segment_id = destination || this.zoneOptions.building_segments[0].id;
      }
      return done({ removed_extensions: [] });
    }
    if (payload.name === "ph_composer.zones.save_segment_settings") {
      var saved = find(params.id);
      if (!saved || saved.values.name !== params.expected_values.name) {
        return refused("target.changed", "The Building Segment changed since its settings opened.", this.revision);
      }
      saved.values.name = params.values.name; saved.values.colour = params.values.colour;
      if (params.default) this.zoneOptions.default_segment_id = saved.id;
      saved.extension_data = saved.extension_data || {};
      Object.keys(params.extension_payloads).forEach(function (namespace) {
        saved.extension_data[namespace] = { schema_version: 1, payload: params.extension_payloads[namespace],
          references: [], export_relevance: "local_only" };
      });
      if (params.extension_payloads["ph_composer.programs.segment"]) {
        this.occupancySettingsSaved(saved.id, params.extension_payloads["ph_composer.programs.segment"]);
      }
      return done({ id: saved.id, namespaces: Object.keys(params.extension_payloads).sort() });
    }
    return null;
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
          this.libraryLoads[provider.id] ||
          (!generation ? "unloaded" : ((this.libraryCatalogs[provider.id] || []).length ? "loaded" : "empty")),
        failure: this.libraryFailures[provider.id] || null, age_seconds: generation ? 65 : null, freshness: {} };
      }, this) });
    }, this);
  };
  Host.prototype.libraryResolution = function (row, kind) {
    var source = function (record) { var s = record.values.source;
      return s && s.kind === "library" && s.library_id === row.library_id && s.record_id === row.record_id; };
    var records = kind === "programs" ? this.programRecords() : kind === "schedules" ? [] :
      kind && kind !== "materials" ? this.windows[kind].records : this.materials.records;
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
  /* The Climate tab's reads and writes, as features/climate/settings.rb answers them: the site's state, the
     design temperatures' state and warning, a guarded write of the fields given, and the geolocation read. */
  Host.prototype.climateSite = function () {
    var site = JSON.parse(JSON.stringify(this.climate.site));
    site.climate_zone_label = site.climate_zone === null ? null : ZONE_LABELS[site.climate_zone];
    site.state = site.latitude_deg !== null && site.longitude_deg !== null && site.elevation_m !== null ?
      "set" : "not_set";
    return site;
  };
  Host.prototype.climateDesign = function () {
    var design = JSON.parse(JSON.stringify(this.climate.design));
    var typed = [design.heating_99_c, design.cooling_1_c].filter(function (value) { return value !== null; });
    design.state = typed.length === 2 ? "set" : typed.length ? "incomplete" : "not_set";
    design.warning = typed.length === 2 && design.heating_99_c >= design.cooling_1_c ?
      "climate.heating_not_below_cooling" : null;
    return design;
  };
  Host.prototype.climateQuery = function (payload) {
    var host = this;
    this.window.setTimeout(function () {
      var value = payload.name === CLIMATE + "site.geolocation" ? JSON.parse(JSON.stringify(host.climate.geolocation)) :
        payload.name === CLIMATE + "climate.get" ? host.climateRecord() :
        payload.name === CLIMATE + "folders.list" ? host.climateFolders() :
          payload.name === CLIMATE + "site.preview_limit_check" ? { limit_check: host.limitCheck(payload.params) } :
            payload.name === CLIMATE + "stations.all" ? host.climateStations(payload.params.folder_id) :
              payload.name === CLIMATE + "climate.source_status" ? host.climateSource() : null;
      var outcome = value && value.status === "refused" ? value : value ? { status: "completed",
        revision: host.revision, value: value } :
        refused("operation.unknown", "The preview does not answer " + payload.name + ".", host.revision);
      host.publish("query.result", { request_id: payload.request_id, session: payload.session, outcome: outcome });
    }, 0);
  };
  Host.prototype.climateFolders = function () {
    return JSON.parse(JSON.stringify({ folders: this.climate.folders, last_dataset_id: this.climate.lastDatasetId }));
  };
  /* The climate data folder commands, as features/climate/folders/operations.rb answers them. Add and Locate take
     the chooser's next row, or cancel when there is none. Nothing is written anywhere. */
  Host.prototype.climateSetup = function (payload) {
    var host = this, verb = payload.name.split(".").pop(), params = payload.params || {};
    var folders = this.climate.folders;
    var row = folders.filter(function (folder) { return folder.id === params.id; })[0], outcome;
    var chosen = (verb === "add" || verb === "locate") ? this.climate.chooser.shift() : null;
    if ((verb === "add" || verb === "locate") && !chosen) {
      outcome = { status: "cancelled", code: "approval.cancelled", message: "No folder was chosen.", effect: "none" };
    } else if (verb !== "add" && !row) {
      outcome = refused("climate.folder_not_found", "No climate data folder with that id is set up on this " +
        "computer. Nothing was written.", this.revision);
    } else if (verb === "add") {
      folders.push(chosen); outcome = { status: "completed", value: JSON.parse(JSON.stringify(chosen)) };
    } else if (verb === "remember_dataset") {
      this.climate.lastDatasetId = row.id; outcome = { status: "completed", value: this.climateFolders() };
    } else if (verb === "remove") {
      this.climate.folders = folders.filter(function (folder) { return folder !== row; });
      outcome = { status: "completed", value: this.climateFolders() };
    } else {
      Object.assign(row, verb === "rename" ? { name: params.name } : Object.assign({}, chosen, { id: row.id,
        name: row.name }));
      outcome = { status: "completed", value: JSON.parse(JSON.stringify(row)) };
    }
    // `setupDelayMs` holds the answer back, as a slow disk or a chooser left open would.
    this.window.setTimeout(function () {
      host.publish("setup.result", { request_id: payload.request_id, session: payload.session,
        outcome: Object.assign({ revision: host.revision }, outcome) });
    }, this.climate.setupDelayMs || 0);
  };
  /* stations.all over the fixture's invented stations, each checked against the site, nearest first; refused as
     the host refuses with no site. */
  Host.prototype.climateStations = function (folderId) {
    var host = this, site = this.climate.site;
    var folder = this.climate.folders.filter(function (row) { return row.id === folderId; })[0];
    if (site.latitude_deg === null) return refused("climate.site_not_set", "Set the site first.", this.revision);
    if (!folder) return refused("climate.folder_not_found", "That folder is not on this computer.", this.revision);
    var rows = (this.climate.stations || []).map(function (station) {
      return Object.assign({}, station, { limit_check: host.limitCheck(site, station) });
    }).sort(function (a, b) { return a.limit_check.distance_km - b.limit_check.distance_km; });
    return { folder_id: folder.id, dataset_name: folder.name, complete: true, total: rows.length, stations: rows };
  };
  /* The attached station is found in the first folder when it came from the fixture's list; a fixture's `source`
     names another answer (changed, not on this computer). */
  Host.prototype.climateSource = function () {
    var station = this.climate.station, folder = this.climate.folders[0];
    if (!station) return { status: "not_applicable", folder_id: null, station_key: null };
    if (this.climate.source === "changed") return { status: "changed", folder_id: folder.id, station_key: station.key };
    return station.key && folder ? { status: "found", folder_id: folder.id, station_key: station.key } :
      { status: "not_on_this_computer", folder_id: null, station_key: null };
  };
  /* An invented station file's values: each monthly row a smooth year, each peak case a few round numbers. */
  var PREVIEW_MONTHLY = ["air_c", "dewpoint_c", "sky_c", "rad_north_kwh_m2", "rad_east_kwh_m2", "rad_south_kwh_m2",
    "rad_west_kwh_m2", "rad_global_kwh_m2"];
  var PREVIEW_PEAK = ["air_c", "dewpoint_c", "sky_c", "rad_north_w_m2", "rad_east_w_m2", "rad_south_w_m2",
    "rad_west_w_m2", "rad_global_w_m2"];
  var PREVIEW_MONTHS = ["jan", "feb", "mar", "apr", "may", "jun", "jul", "aug", "sep", "oct", "nov", "dec"];
  function previewFile() {
    var monthly = {}, peaks = {};
    PREVIEW_MONTHLY.forEach(function (row, r) {
      monthly[row] = PREVIEW_MONTHS.map(function (_, m) {
        var season = -Math.cos(m / 11 * 2 * Math.PI);
        return r < 3 ? Math.round((8 - r * 6 + season * 13) * 10) / 10 :
          Math.round(60 + r * 9 + season * (40 + r * 6));
      });
    });
    [["heat_1", -13.4], ["heat_2", -7.9], ["cool_1", 26.8]].forEach(function (pair, c) {
      peaks[pair[0]] = {};
      PREVIEW_PEAK.forEach(function (row, r) {
        peaks[pair[0]][row] = r === 0 ? pair[1] : r < 3 ? Math.round((pair[1] - r * 4) * 10) / 10 :
          20 + c * 60 + r * 15;
      });
    });
    return { station_elevation_m: null, daily_temp_swing_k: 11.2, monthly: monthly, peak_loads: peaks };
  }
  /* The fixture's station as climate.get gives it, with the values its invented file reads and `edited` of them
     changed (January, February, ... of the air temperature), or none. */
  Host.prototype.climateRecord = function () {
    var station = this.climate.station;
    if (!station) return { state: "none", climate: null, missing: [], edited_cells: [], limit_check: null };
    if (!this.climate.values) {
      var file = previewFile();
      file.station_elevation_m = station.elevation_m;
      var now = JSON.parse(JSON.stringify(file));
      for (var i = 0; i < (this.climate.edited || 0); i += 1) {
        now.monthly.air_c[i] = Math.round((now.monthly.air_c[i] - 0.9) * 10) / 10;
      }
      this.climate.values = { name: station.name, origin: "station", station_latitude_deg: station.latitude_deg,
        station_longitude_deg: station.longitude_deg, station_elevation_m: station.elevation_m,
        daily_temp_swing_k: file.daily_temp_swing_k, wind_speed_m_s: 3.9, monthly: now.monthly,
        peak_loads: now.peak_loads, as_read: file,
        provenance: { dataset_name: station.key && this.climate.folders[0] ? this.climate.folders[0].name :
          "Preview Stations", station_name: String(station.name).toUpperCase().replace(/ /g, "_"),
        state: station.state || "XA", source_type: "phius_approved", source_checksum: "0".repeat(64) } };
    }
    // Every value that differs from the file, in features/climate/climate/edits.rb's order.
    var values = this.climate.values, read = values.as_read, edited = [];
    ["station_elevation_m", "daily_temp_swing_k"].forEach(function (row) {
      if (values[row] !== read[row]) edited.push({ row: row, column: null });
    });
    PREVIEW_MONTHLY.forEach(function (row) {
      PREVIEW_MONTHS.forEach(function (month, m) {
        if (values.monthly[row][m] !== read.monthly[row][m]) edited.push({ row: row, column: month });
      });
    });
    PREVIEW_PEAK.forEach(function (row) {
      ["heat_1", "heat_2", "cool_1"].forEach(function (name) {
        if (values.peak_loads[name][row] !== read.peak_loads[name][row]) edited.push({ row: row, column: name });
      });
    });
    return { state: "complete", missing: [], edited_cells: edited, limit_check: this.limitCheck(this.climate.site),
      climate: { id: "preview-climate", values: JSON.parse(JSON.stringify(values)) } };
  };
  /* Restore, Clear and Edit Values (the wind speed), guarded by the editable fields as the host guards them. */
  Host.prototype.climateWrite = function (payload) {
    var record = this.climateRecord().climate, verb = payload.name.slice((CLIMATE + "climate.").length);
    var expected = payload.params.expected_values || {};
    if (!record) return refused("climate.not_found", "The Model holds no climate. " + NOTHING_WRITTEN, this.revision);
    var guard = ["daily_temp_swing_k", "monthly", "name", "peak_loads", "station_elevation_m", "station_latitude_deg",
      "station_longitude_deg", "wind_speed_m_s"];
    if (Object.keys(expected).sort().join() !== guard.join()) {
      return refused("validation.failed", "expected_values names the eight editable fields. " + NOTHING_WRITTEN,
        this.revision);
    }
    var stale = Object.keys(expected).some(function (key) {
      return JSON.stringify(record.values[key]) !== JSON.stringify(expected[key]);
    });
    if (stale) return refused("target.changed", "The climate changed since it was read. " + NOTHING_WRITTEN,
      this.revision);
    var values = this.climate.values;
    if (verb === "clear") { this.climate.station = null; this.climate.values = null; this.climate.edited = 0; }
    if (verb === "restore_original") {
      values.monthly = JSON.parse(JSON.stringify(values.as_read.monthly));
      values.peak_loads = JSON.parse(JSON.stringify(values.as_read.peak_loads));
    }
    if (verb === "save_values") Object.assign(values, payload.params.values);
    this.revision++;
    return { status: "completed", effect: "committed", revision: this.revision, value: {} };
  };
  /* Phius's limit check at a site, as features/climate/climate/limit_check.rb works it out. */
  Host.prototype.limitCheck = function (site, of) {
    var station = of || this.climate.station, radians = Math.PI / 180;
    if (!station) return null;
    if (site.latitude_deg === null || site.longitude_deg === null || site.elevation_m === null) {
      return { verdict: "not_checked", reason: "no_site", distance_km: null, elevation_difference_m: null,
        distance_ok: null, elevation_ok: null };
    }
    var halfLat = (station.latitude_deg - site.latitude_deg) * radians / 2;
    var halfLon = (station.longitude_deg - site.longitude_deg) * radians / 2;
    var h = Math.pow(Math.sin(halfLat), 2) + Math.cos(site.latitude_deg * radians) *
      Math.cos(station.latitude_deg * radians) * Math.pow(Math.sin(halfLon), 2);
    var distance = 2 * 6371.0088 * Math.asin(Math.sqrt(Math.min(h, 1)));
    var elevation = Math.abs(site.elevation_m - station.elevation_m);
    // The same limits and floating-point slack as the Ruby.
    var distanceOk = distance <= 80.4672 + 1e-12, elevationOk = elevation <= 121.92 + 1e-9;
    return { verdict: distanceOk && elevationOk ? "pass" : "fail", reason: null, distance_km: distance,
      elevation_difference_m: elevation, distance_ok: distanceOk, elevation_ok: elevationOk };
  };
  Host.prototype.climateAction = function (payload) {
    if (/\.(attach|replace)_station$/.test(payload.name)) return this.climateAttach(payload);
    if (/\.climate\.(clear|restore_original|save_values)$/.test(payload.name)) return this.climateWrite(payload);
    var target = payload.name === CLIMATE + "site.update" ? this.climate.site :
      payload.name === CLIMATE + "design_temperatures.update" ? this.climate.design : null;
    var values = payload.params.values || {}, expected = payload.params.expected_values || {};
    if (!target) {
      return refused("operation.unknown", "The preview does not answer " + payload.name + ".", this.revision);
    }
    var stale = Object.keys(expected).some(function (key) {
      return JSON.stringify(target[key]) !== JSON.stringify(expected[key]);
    });
    if (stale) return refused("target.changed", "The values changed since they were read. " + NOTHING_WRITTEN,
      this.revision);
    var given = ["latitude_deg", "longitude_deg", "elevation_m"].filter(function (key) {
      return values[key] !== undefined && values[key] !== null;
    });
    if (target === this.climate.site && given.length && given.length < 3) {
      return refused("validation.failed", "Latitude, longitude and elevation are set together. " + NOTHING_WRITTEN,
        this.revision);
    }
    Object.keys(values).forEach(function (key) { target[key] = values[key]; });
    this.revision++;
    return { status: "completed", effect: "committed", revision: this.revision,
      value: target === this.climate.site ? this.climateSite() : this.climateDesign() };
  };

  /* Attach and Replace: the named station becomes the Model's climate, refused as the host refuses. */
  Host.prototype.climateAttach = function (payload) {
    var replacing = /replace_station$/.test(payload.name), key = payload.params.station_key;
    var station = (this.climate.stations || []).filter(function (row) { return row.key === key; })[0];
    if (Boolean(this.climate.station) !== replacing) {
      return refused(replacing ? "climate.not_found" : "target.changed", "The Model's climate changed. " +
        NOTHING_WRITTEN, this.revision);
    }
    if (!station) return refused("climate.station_not_found", "No station file with that key is in the climate " +
      "data folder now. " + NOTHING_WRITTEN, this.revision);
    this.climate.station = station; this.climate.edited = 0; this.climate.values = null; this.climate.source = null;
    this.revision++;
    return { status: "completed", effect: "committed", revision: this.revision, value: {} };
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
    if (verb === "cancel_load") {
      var running = this.libraryLoads[params.provider_id] === "loading";
      if (running) this.libraryLoads[params.provider_id] = "cancelled";
      this.snapshot();
      this.publish("setup.result", { request_id: payload.request_id, session: payload.session,
        outcome: { status: "completed", effect: "none", revision: this.revision, value: { cancelled: running } } });
      return;
    }
    if (verb === "load" && this.holdLibraryLoads) this.libraryLoads[params.provider_id] = "loading";
    else if (verb === "load") {
      delete this.libraryLoads[params.provider_id];
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
  /* Ends a held hosted load the way a published snapshot does: the next generation, ready to read. */
  Host.prototype.finishLibraryLoad = function (providerId) {
    delete this.libraryLoads[providerId];
    this.libraryGenerations[providerId] = (this.libraryGenerations[providerId] || 0) + 1;
    this.snapshot();
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
    if (payload.params.kind === "programs" && this.programCatalog) return this.programCatalogCopy(payload.params);
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

  /* A new Schedule's form by type, as features/programs/schedule.rb's FORM_DEFAULTS. */
  var SCHEDULE_FORMS = {
    fractional: { start_h: 0, end_h: 24, fraction_on: 1, fraction_off: 0 },
    activity: { start_h: 0, end_h: 24, watts_on: 120, watts_off: 120 },
    temperature: { value_c: 20 },
    ventilation: { periods: [{ period: "high", hours: 0, fraction: 1 }, { period: "standard", hours: 24, fraction: 1 },
      { period: "basic", hours: 0, fraction: 0.5 }, { period: "minimum", hours: 0, fraction: 0.3 }] }
  };

  /* A Schedule's profile as features/programs/schedule.rb's ScheduleProfile draws it, for the preview's writes. */
  function scheduleProfile(values) {
    var hours = [], type = values.type, hour;
    function on(start, stop, at) { return start < stop ? at >= start && at < stop : start > stop ?
      at >= start || at < stop : false; }
    if (type === "ventilation") {
      values.periods.forEach(function (period) {
        for (hour = 0; hour < period.hours; hour++) hours.push(period.fraction);
      });
    } else {
      for (hour = 0; hour < 24; hour++) {
        if (type === "temperature") hours.push(values.value_c);
        else hours.push(on(values.start_h, values.end_h, hour) ? values[type === "activity" ? "watts_on" :
          "fraction_on"] : values[type === "activity" ? "watts_off" : "fraction_off"]);
      }
    }
    var fraction = type === "fractional" || type === "ventilation";
    var daily = fraction ? hours.reduce(function (sum, value) { return sum + value; }, 0) : null;
    var days = ["monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday"];
    return { hours: hours, daily_full_load_hours: daily,
      annual_full_load_hours: daily === null ? null : daily * values.days_per_week * values.weeks_per_year,
      weekdays: days.slice(0, type === "temperature" ? 7 : values.days_per_week) };
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
