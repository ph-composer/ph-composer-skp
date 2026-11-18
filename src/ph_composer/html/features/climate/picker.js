/* Set Phius Climate Data, the station picker: every station of one dataset on the outline map and in a list, read
   whole by `stations.all` (no station value but name, place and elevation reaches the panel). It opens on the dataset
   shared.openingDataset names, sorted by distance, State on All, the map framed on the 50 mi ring around the site and
   the nearest station selected; `preselect` (Update from File) selects another. Map and list select together; the
   footer gives the verdict against both limits, and a failing station attaches with no confirm step. With a climate in
   the Model it compares the current station with the selected one, counts the edited values Replace discards
   (`climate.get`) and sends `replace_station`, one Undo step. Every rule is the host's; this formats and routes. */
PhComposerUI.define("features/climate/picker", ["workspace", "record_form", "request", "snapshot", "table",
  "view_controls", "outline_map", "map_projection", "features/climate/shared"],
function (ui, RecordForm, requests, snapshot, tables, controls, outlineMap, projection, shared) {
  "use strict";
  var el = ui.element, P = shared.PREFIX;
  // [the chip's word, its tone, the hover tip's words]
  var VERDICT = { pass: ["Pass", "is-ok", "Pass"], fail: ["Fail", "is-warning", "Outside Phius limits"],
    not_checked: ["Not checked", "", "Not checked"] };
  var COLUMNS = [["station", "Station"], ["state", "State"], ["distance", "Distance"], ["elevation", "Elevation"],
    ["verdict", "Result"]];
  var WIDTHS = { station: 120, state: 56, distance: 72, elevation: 72, verdict: 64 };
  var PARTIAL = "This folder was not read whole: it is too large or too deep, or part of it could not be listed. " +
    "Stations past that point are not shown, and a nearer one may be among them.";
  var NARROW_PX = 500; // below it the State column gives way to the station's name; the State filter stays

  function count(value) { return Number(value).toLocaleString("en-US"); }
  function distance(check) { return shared.formatted(check.distance_km, shared.DISTANCE); }
  /* "+11 m" when the station is above the site: Ruby's difference, signed by which is higher. */
  function rise(check, stationElevation, site) {
    var sign = stationElevation > site.elevation_m ? "+" : stationElevation < site.elevation_m ? "−" : "";
    return sign + shared.formatted(check.elevation_difference_m, shared.ELEVATION);
  }
  function verdict(check) { return VERDICT[(check && check.verdict) || "not_checked"]; }
  function chip(check) { var words = verdict(check); return el("span", "climate-data-chip " + words[1], words[0]); }

  /* `options`: { site, replacing, preselect: { folder_id, station_key } or null }; `closed()` runs when it closes. */
  function Picker(session, send, options, closed) {
    var self = this;
    RecordForm.call(this, session, send, { title: "", action: P + "climate.attach_station", label: "climate_picker",
      submitLabel: "Attach", pendingText: "Attaching the station…", failureText: "The station was not attached.",
      className: "climate-picker", changed: function () { self.dispose(); closed(); } });
    this.title.className = "climate-picker-title";
    this.site = options.site; this.preselect = options.preselect || null; this.replacing = null;
    this.reads = {};
    ["folders", "stations", "source", "climate"].forEach(function (name) {
      self.reads[name] = requests.channel(session, send, "climate_picker_" + name, "query.invoke");
    });
    this.remember = requests.channel(session, send, "climate_picker_remember", "setup.invoke");
    this.listed = null; this.folderId = null; this.stations = []; this.byKey = {}; this.selected = null;
    this.failure = null; this.source = null; this.current = null; this.revision = null; this.buttons = {};
    this.siteKey = siteKey(this.site);
    this.summary = el("p", "climate-dialog-note climate-picker-summary");
    var bar = el("div", "climate-picker-controls");
    bar.appendChild(ui.button("Find Nearest", function () { self.nearest(); }));
    this.dataset = this.choice(bar, "Dataset", function () { self.changeDataset(); });
    this.stateChoice = this.choice(bar, "State", function () { self.paintList(); });
    this.view = new controls.ViewControls({ label: "stations", placeholder: "Search stations", columnSort: true,
      fields: [["distance", "Distance"]], initialOrder: "distance", count: false }, function () { self.paintList(); });
    // Enter in the search narrows, as typing does; it never submits the form, which would attach.
    this.view.filter.addEventListener("keydown", function (event) {
      if (event.key === "Enter") event.preventDefault();
    });
    bar.appendChild(this.view.root);
    this.notice = el("p", "climate-picker-notice"); this.notice.setAttribute("role", "status");
    this.map = outlineMap({ label: "Outline map of the stations", hint: "Click a station to select it. Drag to pan.",
      onSelect: function (key) { self.select(key, true); }, onHover: function (key) { return self.tip(key); } });
    this.list = el("div", "climate-picker-list");
    var body = el("div", "climate-picker-body");
    body.appendChild(this.map.root); body.appendChild(this.list);
    this.selection = el("div", "climate-picker-selection"); this.selection.setAttribute("aria-live", "polite");
    [this.summary, bar, this.notice, body, this.selection].forEach(function (node) { self.form.appendChild(node); });
    this.finish();
    this.resized = function () { if ((window.innerWidth <= NARROW_PX) !== self.narrow) self.paintList(); };
    window.addEventListener("resize", this.resized);
    document.body.appendChild(this.root);
    this.show();
    this.setMode(Boolean(options.replacing));
    this.reads.folders.run(P + "folders.list", {});
    this.paint();
  }
  RecordForm.extend(Picker);

  Picker.prototype.choice = function (bar, label, changed) {
    var wrap = el("label", "phc-view-control", label), input = el("select", "phc-choice-pill");
    input.setAttribute("aria-label", label); input.addEventListener("change", changed);
    wrap.appendChild(input); bar.appendChild(wrap);
    return input;
  };

  /* Attach or Replace, from whether the Model holds a climate now; Replace reads where the attached station is and
     how many of its values were edited. */
  Picker.prototype.setMode = function (replacing) {
    if (replacing === this.replacing) return false;
    this.replacing = replacing;
    this.title.textContent = replacing ? "Replace Phius climate data" : "Set Phius climate data";
    this.submitButton.textContent = replacing ? "Replace" : "Attach";
    this.spec.action = P + (replacing ? "climate.replace_station" : "climate.attach_station");
    this.spec.pendingText = replacing ? "Replacing the station…" : "Attaching the station…";
    this.source = null; this.current = null;
    if (replacing) {
      this.reads.source.reset(); this.reads.source.run(P + "climate.source_status", {});
      this.readClimate();
    }
    return true;
  };
  Picker.prototype.readClimate = function () {
    this.reads.climate.reset(); this.reads.climate.run(P + "climate.get", {});
  };

  Picker.prototype.consume = function (state) {
    var summary = snapshot.value(state, shared.SUMMARY), site = snapshot.value(state, shared.SITE);
    var moved = Boolean(site) && siteKey(site) !== this.siteKey;
    if (site) { this.site = site; this.siteKey = siteKey(site); }
    var switched = Boolean(summary) && this.setMode(summary.climate.state !== "none");
    var listed = this.reads.folders.consume(state), source = this.reads.source.consume(state);
    var climate = this.reads.climate.consume(state), stations = this.reads.stations.consume(state);
    var remembered = this.remember.consume(state);
    if (remembered) {
      this.unsaved = remembered.status === "completed" ? null : "The dataset was not remembered for next time: " +
        (remembered.message || "PH-Composer did not answer.");
    }
    if (listed) this.listed = listed.status === "completed" ? listed.value : { folders: [], failure: listed.message };
    if (source) this.source = source.status === "completed" ? source.value : { status: "unknown" };
    if (climate) {
      this.current = climate.status === "completed" && climate.value.climate ? climate.value : null;
      if (climate.status !== "completed") this.failure = climate.message;
    }
    if (stations) this.loaded(stations);
    if ((listed || source) && this.folderId === null) this.openDataset();
    // A site change moves every distance; another change to the Model may change its climate. Either is read
    // again, and one that arrives while Attach or Replace is out is read once it answers.
    if (moved) this.staleStations = true;
    this.followRevision(state);
    var units = shared.formatted(1, shared.DISTANCE) + shared.formatted(1, shared.ELEVATION);
    if ((switched || source || units !== this.units) && !stations) { this.units = units; this.paintList(); }
    this.units = units;
    var outcome = this.settle(state);
    if (outcome && outcome.status === "completed") { this.hide(); return; }
    this.refresh();
    this.paint();
  };
  Picker.prototype.refresh = function () {
    if (this.busy()) return;
    if (this.staleStations && this.folderId) { this.staleStations = false; this.read(this.folderId); }
    if (this.staleClimate && this.replacing) {
      this.staleClimate = false; this.readClimate();
      this.reads.source.reset(); this.reads.source.run(P + "climate.source_status", {});
    }
  };
  function siteKey(site) {
    return site && site.state === "set" ? [site.latitude_deg, site.longitude_deg, site.elevation_m].join() : "";
  }

  /* Once the folders and, in Replace, the attached station's place are known: the opening dataset, or the one
     named. */
  Picker.prototype.openDataset = function () {
    if (!this.listed || (this.replacing && !this.source)) return;
    var found = (this.listed.folders || []).filter(function (folder) { return folder.found; });
    var attached = this.source && (this.source.status === "found" || this.source.status === "changed") ?
      this.source.folder_id : null;
    var dataset = shared.openingDataset(this.listed, (this.preselect && this.preselect.folder_id) || attached);
    this.dataset.replaceChildren.apply(this.dataset, found.map(function (folder) {
      return ui.option(folder.id, folder.name);
    }));
    if (!dataset) {
      this.failure = this.listed.failure || "No climate data folder is on this computer.";
      this.paintList();
      return;
    }
    this.dataset.value = dataset.id;
    this.opening = true;
    this.read(dataset.id);
  };
  Picker.prototype.read = function (folderId) {
    this.folderId = folderId; this.failure = null;
    this.reads.stations.reset(); this.reads.stations.run(P + "stations.all", { folder_id: folderId });
  };
  Picker.prototype.changeDataset = function () {
    this.remember.reset(); this.remember.run(P + "folders.remember_dataset", { id: this.dataset.value });
    this.preselect = null; this.opening = true; this.stations = []; this.byKey = {}; this.buttons = {};
    this.selected = null; this.value = null;
    this.read(this.dataset.value);
    this.paintList();
  };

  /* A new list. Opening, or after Dataset, it starts from the opening view; a re-read keeps the selection. */
  Picker.prototype.loaded = function (outcome) {
    var self = this;
    if (outcome.status !== "completed") {
      this.failure = outcome.message; this.stations = []; this.byKey = {}; this.buttons = {}; this.value = null;
      this.selected = null; this.paintList();
      return;
    }
    this.failure = null; this.value = outcome.value;
    this.stations = outcome.value.stations.slice().sort(function (a, b) {
      return a.limit_check.distance_km - b.limit_check.distance_km || (a.key < b.key ? -1 : 1);
    });
    this.byKey = {}; this.buttons = {};
    this.stations.forEach(function (station) { self.byKey[station.key] = station; });
    var states = this.stations.map(function (station) { return station.state; }).filter(function (name, index, list) {
      return list.indexOf(name) === index;
    }).sort();
    var kept = this.stateChoice.value;
    this.stateChoice.replaceChildren.apply(this.stateChoice, [ui.option("", "All")].concat(states.map(function (name) {
      return ui.option(name, name);
    })));
    this.stateChoice.value = states.indexOf(kept) >= 0 ? kept : "";
    var wanted = this.preselect && this.byKey[this.preselect.station_key] ? this.preselect.station_key : null;
    this.preselect = null;
    if (this.opening) { this.opening = false; this.nearest(wanted); return; }
    if (!this.byKey[this.selected]) this.selected = null;
    this.paintList();
  };

  /* Find Nearest: State on All, no search, the nearest station (or `key`) selected, the map on the site's ring. */
  Picker.prototype.nearest = function (key) {
    this.stateChoice.value = ""; this.view.filter.value = "";
    this.selected = key || (this.stations[0] && this.stations[0].key) || null;
    this.paintList();
    if (this.site && this.site.state === "set") {
      this.map.frame(projection.ringBounds(this.site.latitude_deg, this.site.longitude_deg, shared.DISTANCE_LIMIT_KM));
    }
    this.reveal();
    this.paint();
  };

  /* In Replace, a change to the Model (an agent editing or replacing the climate) is read again. */
  Picker.prototype.followRevision = function (state) {
    var revision = state && state.revision;
    if (revision === undefined || revision === null || revision === this.revision) return;
    var first = this.revision === null;
    this.revision = revision;
    if (!first) this.staleClimate = true;
  };

  Picker.prototype.select = function (key, fromMap) {
    if (!this.byKey[key] || this.busy()) return;
    var previous = this.buttons[this.selected];
    this.selected = key;
    if (previous) { previous.setAttribute("tabindex", "-1"); previous.closest("tr").classList.remove("host-selected"); }
    var button = this.buttons[key];
    if (button) { button.setAttribute("tabindex", "0"); button.closest("tr").classList.add("host-selected"); }
    this.map.update({ selected: key });
    if (fromMap) this.reveal();
    this.error.textContent = "";
    this.paint();
  };
  Picker.prototype.reveal = function () {
    var button = this.buttons[this.selected], row = button && button.closest("tr");
    if (row && row.scrollIntoView) row.scrollIntoView({ block: "nearest" });
  };

  /* Arrow keys move the selection along the rows the list shows; only the selected row takes Tab. */
  Picker.prototype.step = function (event, key) {
    if (event.key !== "ArrowDown" && event.key !== "ArrowUp") return;
    event.preventDefault();
    var visible = this.visible || [], index = visible.indexOf(key);
    var next = visible[index + (event.key === "ArrowDown" ? 1 : -1)];
    if (!next) return;
    this.select(next, true);
    this.buttons[next].focus();
  };

  Picker.prototype.paintList = function () {
    var self = this, state = this.stateChoice.value, attached = this.attachedKey();
    var projected = this.view.project(this.stations, { id: function (s) { return s.key; },
      value: function (s) { return s.limit_check.distance_km; }, search: function (s) { return s.name; },
      include: function (s) { return !state || s.state === state; },
      tie: function (a, b) { return a.key < b.key ? -1 : 1; } });
    var rows = projected.records.map(function (s) { return { key: s.key, record: s, tier: "Station", depth: 0 }; });
    this.visible = rows.filter(function (row) { return !projected.hidden(row); }).map(function (row) {
      return row.key;
    });
    this.shown = this.visible.length;
    // A filter that hides the selected station selects the first it leaves, so Attach never takes a hidden one.
    if (this.visible.indexOf(this.selected) < 0) this.selected = this.visible[0] || null;
    this.narrow = window.innerWidth <= NARROW_PX;
    tables.table(this.list, this.stations, { rows: rows, columns: COLUMNS, defaultWidths: WIDTHS,
      stickyWidths: {}, hiddenColumns: { state: this.narrow }, rowHidden: projected.hidden, visibleCount: this.shown,
      selected: function (row) { return row.key === self.selected; },
      empty: this.failure ? "" : this.value ? "No stations match this view." : "Reading the stations…",
      value: function (row, field) { return field; },
      cell: function (td, row, field) { self.cell(td, row.record, field, row.key === attached); return true; } });
    var points = this.stations.filter(function (s) { return !projected.hidden({ key: s.key, record: s }); });
    this.map.update({ selected: this.selected, points: points.map(function (s) {
      return { id: s.key, latitude_deg: s.latitude_deg, longitude_deg: s.longitude_deg,
        tone: s.limit_check.verdict === "pass" ? "ok" : "warning" };
    }), pin: this.site && this.site.state === "set" ? { latitude_deg: this.site.latitude_deg,
      longitude_deg: this.site.longitude_deg, label: "Site" } : null,
    rings: this.site && this.site.state === "set" ? [{ latitude_deg: this.site.latitude_deg,
      longitude_deg: this.site.longitude_deg, radius_km: shared.DISTANCE_LIMIT_KM,
      label: "50 mi from the site" }] : [] });
    this.paint();
  };

  /* A row's cells are written once per station; the Station cell is the row's button. */
  Picker.prototype.cell = function (td, station, field, attached) {
    var self = this, marked = (attached ? "1" : "0") + this.units;
    if (td._station === station && td._attached === marked && field !== "station") return;
    var rebuilt = td._attached !== marked;
    td._station = station; td._attached = marked;
    var check = station.limit_check;
    if (field === "station") {
      var button = td._button;
      if (!button || rebuilt) {
        button = td._button = ui.button(station.name, function () { self.select(station.key, false); });
        button.className = "climate-picker-station";
        button.addEventListener("keydown", function (event) { self.step(event, station.key); });
        td.replaceChildren(button);
        if (attached) td.appendChild(el("span", "climate-data-chip is-ok", "Attached"));
      }
      this.buttons[station.key] = button;
      if (button.textContent !== station.name) button.textContent = station.name;
      button.setAttribute("tabindex", station.key === this.selected ? "0" : "-1");
      return;
    }
    td.replaceChildren();
    if (field === "verdict") td.appendChild(chip(check));
    else td.textContent = field === "state" ? station.state : field === "distance" ? distance(check) :
      rise(check, station.elevation_m, this.site);
    if (field === "distance" || field === "elevation") td.classList.add("is-numeric");
  };

  Picker.prototype.attachedKey = function () {
    var source = this.source;
    return this.replacing && source && source.folder_id === this.folderId && source.status === "found" ?
      source.station_key : null;
  };

  /* The hover tip: name, distance, elevation difference and verdict. */
  Picker.prototype.tip = function (key) {
    var station = this.byKey[key];
    if (!station) return null;
    var node = el("span", "climate-picker-tip");
    node.appendChild(el("strong", "", station.name));
    node.appendChild(el("span", "", distance(station.limit_check) + " · " + rise(station.limit_check,
      station.elevation_m, this.site)));
    node.appendChild(el("span", "", verdict(station.limit_check)[2]));
    return node;
  };

  Picker.prototype.paint = function () {
    this.summary.textContent = this.value ? this.value.dataset_name + " · " + count(this.value.total) + " station" +
      (this.value.total === 1 ? "" : "s") + " on this computer · " + count(this.shown || 0) + " shown" : "";
    var notes = [this.failure, this.value && !this.value.complete ? PARTIAL : null, this.unsaved].filter(Boolean);
    this.notice.textContent = notes.join(" ");
    this.notice.hidden = !notes.length;
    // Attach and Replace wait for every read out, so neither acts on a list or a climate read before a change.
    this.submitButton.disabled = this.busy() || !this.byKey[this.selected] || (this.replacing && !this.current) ||
      this.reads.stations.busy() || this.reads.climate.busy();
    this.paintSelection();
  };

  /* The selected station against both limits; in Replace, the current and the selected side by side. */
  Picker.prototype.paintSelection = function () {
    var station = this.byKey[this.selected], nodes = [];
    if (station) {
      var check = station.limit_check, failing = check.verdict === "fail";
      if (this.replacing) nodes.push(this.comparison(station));
      nodes.push(el("p", failing ? "climate-picker-warning" : "climate-picker-verdict", sentence(station,
        this.site)));
      if (this.replacing) {
        var edited = this.current ? this.current.edited_cells.length : 0;
        if (edited) {
          nodes.push(el("p", "climate-picker-warning", this.current.climate.values.name + " has " + edited +
            " edited value" + (edited === 1 ? "" : "s") + ". Replacing it discards them."));
        }
        nodes.push(el("p", "climate-dialog-note", "Replacing is one Undo step. The average wind speed is prefilled " +
          "again from the new file."));
      } else {
        nodes.push(el("p", "climate-dialog-note", failing ? "It can still be attached. The Model and the Export " +
          "report will show it as outside the Phius limits." : "Attaching copies this station's values into the " +
          "Model."));
      }
    }
    this.selection.replaceChildren.apply(this.selection, nodes);
  };

  Picker.prototype.comparison = function (station) {
    var table = el("table", "phc-table climate-picker-compare"), head = el("tr"), site = this.site;
    var scroll = el("div", "climate-picker-compare-scroll");
    scroll.appendChild(table);
    ["", "Station", "Dataset", "Distance", "Elevation", "Result"].forEach(function (word) {
      head.appendChild(el("th", "", word));
    });
    table.appendChild(head);
    var current = this.current && this.current.climate.values, check = this.current && this.current.limit_check;
    function line(label, name, dataset, limit, elevation) {
      var row = el("tr");
      row.appendChild(el("th", "", label));
      [name, dataset].forEach(function (word) { row.appendChild(el("td", "", word)); });
      row.appendChild(el("td", "", limit && limit.distance_km !== null ? distance(limit) : "—"));
      row.appendChild(el("td", "", limit && limit.elevation_difference_m !== null ? rise(limit, elevation, site) :
        "—"));
      var result = el("td"); result.appendChild(chip(limit)); row.appendChild(result);
      table.appendChild(row);
    }
    if (current) {
      line("Now", current.name, current.origin === "hand" ? "Entered by hand" : (current.provenance || {}).dataset_name,
        check, current.station_elevation_m);
    }
    line("New", station.name, this.value.dataset_name, station.limit_check, station.elevation_m);
    return scroll;
  };

  /* "Alder Field is 18 km from the site and 11 m higher. Within the Phius limits of 50 mi and 400 ft." The limits
     are said as Phius states them, in miles and feet, as Set Location says them. */
  function sentence(station, site) {
    var check = station.limit_check, apart = station.elevation_m - site.elevation_m;
    var height = apart === 0 ? "at the same elevation" : shared.formatted(check.elevation_difference_m,
      shared.ELEVATION) + (apart > 0 ? " higher" : " lower");
    var opening = station.name + " is " + distance(check) + " from the site and " + height + ". ";
    if (check.verdict === "pass") return opening + "Within the Phius limits of 50 mi and 400 ft.";
    var limits = !check.distance_ok && !check.elevation_ok ? "distance and elevation limits of 50 mi and 400 ft" :
      !check.distance_ok ? "distance limit of 50 mi" : "elevation limit of 400 ft";
    return opening + "Outside the Phius " + limits + ". Phius asks for a custom dataset here unless an exception " +
      "applies.";
  }

  Picker.prototype.submit = function () {
    if (this.busy() || this.submitButton.disabled) return;
    if (this.run({ folder_id: this.folderId, station_key: this.selected })) this.paint();
  };

  Picker.prototype.dispose = function () {
    var reads = this.reads;
    this.withdraw();
    Object.keys(reads).forEach(function (name) { reads[name].reset(); });
    this.remember.reset();
    window.removeEventListener("resize", this.resized);
    this.map.dispose();
    if (this.root.parentNode) this.root.parentNode.removeChild(this.root);
  };

  return { open: function (session, send, options, closed) { return new Picker(session, send, options, closed); } };
});
