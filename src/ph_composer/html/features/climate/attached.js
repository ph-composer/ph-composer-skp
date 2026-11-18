/* The Phius climate data pane while the Model holds a climate (boards 5, 6, 15, 17 and 19). It paints from
   `climate.get`, read when the pane is shown and again whenever the Model's revision moves while it shows, so the
   limit check follows a site change (J7); and from `climate.source_status`, which reads the climate data folders on
   disk, so it is read only when the pane is shown, when the attached station changes and when asked (after the
   picker or the data dialog closes). Nothing it reads is a notice: a source not on this computer is one line in
   Where this lives (J6).
     header        the name, the dataset and the station's place, and its tags: the verdict, Edited, Incomplete and
                   Source changed;
     limit check   distance and elevation against Phius's limits, or why it was not checked; a failing station
                   says Phius asks for a custom dataset;
     values        monthly temperatures and radiation, the peak loads, the station elevation and daily swing, each
                   edited cell marked with the file's value on hover; Ground and Cooling 2 read as not part of a
                   Phius station file;
     wind          the average wind speed, typed in place and saved by `save_values`; never an edit (W8);
     where         what the Model holds, whether the source is on this computer (with Update from File when it
                   changed) and what the climate is ready for.
   The page header carries the actions (section.js): Edit Values, Replace as the primary and Clear in the overflow;
   Restore Original Values sits with the edited line it acts on. Restore, Clear and the wind speed are each one
   Undo step guarded by the values last read. Every rule is the host's; this formats and routes. */
PhComposerUI.define("features/climate/attached", ["panel", "workspace", "request", "unit_field", "unit_preferences",
  "units", "fields", "features/climate/shared"],
function (panel, ui, requests, unitField, preferences, units, fields, shared) {
  "use strict";
  var el = ui.element, P = shared.PREFIX;
  var MONTHS = shared.MONTHS, CASES = shared.CASES, rowField = shared.rowField;
  var MONTH_WORDS = ["January", "February", "March", "April", "May", "June", "July", "August", "September",
    "October", "November", "December"];
  var TEMPERATURE_ROWS = [["air_c", "Air"], ["dewpoint_c", "Dewpoint"], ["sky_c", "Sky"]];
  var DIRECTIONS = [["north", "North"], ["east", "East"], ["south", "South"], ["west", "West"], ["global", "Global"]];
  var RADIATION = shared.RADIATION;
  var SWING = fields.TEMPERATURE_DIFFERENCE_K;
  var WIND = fields.with(fields.WIND_SPEED_M_S, { label: "Average wind speed", allowBlank: true });
  var NOT_IN_FILE = "Not part of a Phius station file";
  var CUSTOM = "Phius asks for a custom dataset here unless an exception applies.";
  var CLEAR_FIRST = "A Model holds one climate. Clear this one first, from More climate actions, then enter values " +
    "by hand.";
  var SCALARS = { station_elevation_m: ["Station elevation", shared.ELEVATION],
    daily_temp_swing_k: ["Daily temperature swing", SWING] };

  function rowWord(row) {
    var temperature = TEMPERATURE_ROWS.filter(function (pair) { return pair[0] === row; })[0];
    if (temperature) return temperature[1];
    var direction = DIRECTIONS.filter(function (pair) { return row.indexOf("rad_" + pair[0] + "_") === 0; })[0];
    return direction ? direction[1] + " radiation" : row;
  }
  function caseWord(name) {
    var found = CASES.filter(function (pair) { return pair[0] === name; })[0];
    return found ? found[1] : String(name);
  }
  function bare(value, field) {
    if (value === null || value === undefined) return "—";
    return units.format(value, field, units.profile(field), { showUnit: false });
  }
  function header(label, field) { return units.header(label, field, undefined); }
  function chip(text, tone) { return el("span", "climate-data-chip" + (tone ? " is-" + tone : ""), text); }
  /* `actions.replace()` opens the picker in Replace, `actions.update(source)` opens it on the source_status answer
     (Update from File), `actions.editValues(values)` the values editor, `actions.openData(add)` Climate Data on This
     Computer and `actions.setLocation()` Set Location. */
  function Pane(session, send, actions) {
    var self = this;
    this.actions = actions; this.record = null; this.source = null; this.revision = null; this.painted = null;
    this.reads = { get: requests.channel(session, send, "climate_attached_get", "query.invoke"),
      source: requests.channel(session, send, "climate_attached_source", "query.invoke") };
    this.writes = requests.channel(session, send, "climate_attached");
    this.root = el("div", "climate-attached");
    this.body = el("div", "climate-attached-body");
    // The wind speed is built once and moved into each repaint, so a repaint never drops a half-typed draft.
    // Its write is guarded by the values the pane showed when typing began, so a change made elsewhere meanwhile
    // refuses rather than being overwritten.
    this.wind = new unitField.UnitField({ field: WIND, commitOnBlur: true,
      onCommit: function (value) { self.saveWind(value); },
      onCancel: function () { self.settled(); } });
    function begin() { if (!self.windGuard && self.values()) self.windGuard = shared.editable(self.values()); }
    this.wind.input.addEventListener("input", begin);
    this.wind.input.addEventListener("paste", begin);
    // A draft that ended with nothing to save (the same value, retyped) lets a held repaint through. These run
    // after the field's own Enter and blur handling.
    function ended() { if (!self.wind.editing) self.settled(); }
    this.wind.input.addEventListener("blur", ended);
    this.wind.input.addEventListener("keydown", function (event) { if (event.key === "Enter") ended(); });
    this.wind.input.setAttribute("aria-label", "Average wind speed");
    this.root.appendChild(this.body);
    this.buildActions();
  }

  /* The page header's controls for this pane: Edit Values, Replace, and Clear in the overflow menu. A no-folder
     Replace opens an explanation anchored to it. */
  Pane.prototype.buildActions = function () {
    var self = this;
    // A wind speed saved on blur by this very click is read back first, so the editor opens on the Model's values.
    this.edit = ui.button("Edit Values…", function () { self.editQueued = true; self.openQueuedEdit(); });
    this.replace = ui.button("Replace…", function () { self.onReplace(); });
    // Replace stays enabled; with no folder or no site it explains here and offers the way on (J6).
    this.explain = new ui.Bubble(this.replace, "Replace", { ownTrigger: true, detachedTrigger: true });
    this.explain.root.classList.add("climate-attached-explain");
    this.root.appendChild(this.explain.root);
    this.menu = new ui.ActionMenu("More climate actions");
    this.menu.add("Clear", function () { self.clear(); }, { destructive: true });
    this.menu.root.hidden = true;
  };

  /* Why Replace cannot open the picker now, or null when it can. */
  Pane.prototype.blocked = function () {
    if (!this.siteSet) return "no_site";
    if (this.folders && this.folders.failure) return "unreadable";
    return this.noFolder() ? "no_folder" : null;
  };
  Pane.prototype.onReplace = function () {
    var self = this, content = this.explain.content, row = el("div", "climate-empty-actions");
    this.explained = this.blocked();
    if (this.explained === "unreadable") {
      content.replaceChildren(el("p", "", "The climate data folders on this computer could not be read: " +
        this.folders.failure), row);
      row.appendChild(this.handLater());
    } else if (this.explained === "no_site") {
      content.replaceChildren(el("p", "", "Set the site location first. The station list is sorted by distance " +
        "from it."), row);
      row.appendChild(this.choice("Set Location…", function () { self.actions.setLocation(); }));
    } else if (this.explained === "no_folder") {
      content.replaceChildren(el("p", "", "There is no climate data folder on this computer, so there are no " +
        "stations to choose from. The climate in this Model stays as it is."), row);
      row.appendChild(this.choice("Choose Climate Data Folder…", function () { self.actions.openData(true); }));
      row.appendChild(this.handLater());
    } else { this.actions.replace(); return; }
    this.explain.open();
  };
  Pane.prototype.handLater = function () {
    var hand = ui.button("Enter Values by Hand…", function () {}), later = el("span", "climate-later");
    hand.disabled = true;
    later.appendChild(hand); later.appendChild(ui.reasonButton("Enter Values by Hand", CLEAR_FIRST));
    return later;
  };
  /* A choice in the explanation closes it first, so what it opens takes the focus. */
  Pane.prototype.choice = function (label, run) {
    var self = this;
    return ui.button(label, function () { self.explain.close(false); run(); });
  };

  Pane.prototype.openQueuedEdit = function () {
    if (!this.editQueued || this.awaitingRead || this.writes.busy() || this.reads.get.busy() || !this.values()) return;
    this.editQueued = false; this.actions.editValues(this.values());
  };

  /* Reads the source again: after the picker or the data dialog closes, either may have changed it. */
  Pane.prototype.refreshSource = function () { this.sourceStale = true; };

  /* `shown` is whether the pane is on screen; `design` the design temperatures' card state; `folders` the
     folders.list answer, or undefined while it is read. */
  Pane.prototype.render = function (state, shown, design, folders) {
    var got = this.reads.get.consume(state), source = this.reads.source.consume(state);
    var written = this.writes.consume(state);
    if (got) this.received(got);
    if (source) {
      this.source = source.status === "completed" ? source.value : { status: "failed", message: source.message };
    }
    if (written && written.status !== "completed") {
      panel.notify(written.message || "The climate was not changed.", "error");
      this.queued = null;
    }
    // Any answer to a write is followed by a read; an action pressed while the write was out (Restore or Clear
    // just after a wind speed saved on blur) runs once that read answers, guarded by the new values.
    if (written) { this.stale = true; this.awaitingRead = true; }
    if (got) this.awaitingRead = false;
    if (this.queued && !this.awaitingRead && !this.writes.busy() && !this.reads.get.busy()) {
      var queued = this.queued; this.queued = null; this.write(queued);
    }
    this.openQueuedEdit();
    var opened = shown && !this.shown;
    this.shown = shown;
    this.menu.root.hidden = !shown;
    if (!shown) { if (!this.explain.panel.hidden) this.explain.close(false); return; }
    if (opened || (state.revision !== this.revision && !this.reads.get.busy())) this.stale = true;
    if (opened) this.sourceStale = true;
    if (this.stale && !this.reads.get.busy()) {
      this.stale = false; this.revision = state.revision; this.reads.get.run(P + "climate.get", {});
    }
    if (this.sourceStale && !this.reads.source.busy()) {
      this.sourceStale = false; this.reads.source.run(P + "climate.source_status", {});
    }
    this.design = design; this.folders = folders;
    this.replace.disabled = this.writes.busy();
    this.edit.disabled = this.writes.busy() || !this.values();
    // An explanation whose reason no longer holds (a folder added, the site set elsewhere) closes.
    if (!this.explain.panel.hidden && this.blocked() !== this.explained) this.explain.close(false);
    this.paint();
  };

  /* A new read; a different station (another checksum) means its source is looked for again. */
  Pane.prototype.received = function (outcome) {
    if (outcome.status !== "completed") { this.failure = outcome.message; return; }
    this.failure = null;
    var before = this.record && this.record.climate && this.record.climate.values.provenance;
    this.record = outcome.value;
    var after = this.record.climate && this.record.climate.values.provenance;
    if (before && after && before.source_checksum !== after.source_checksum) {
      this.sourceStale = true; this.source = null;
    }
  };

  /* The values as last read, or null. */
  Pane.prototype.values = function () {
    return this.record && this.record.climate ? this.record.climate.values : null;
  };

  /* Not while the wind speed is being typed: a rebuilt body would take its focus. It paints once the draft ends. */
  Pane.prototype.paint = function () {
    if (this.wind.editing) return;
    var values = this.values();
    var key = JSON.stringify([this.record, this.source, this.design, this.noFolder(), this.failure,
      this.writes.busy(), this.siteElevation, preferences.current()]);
    if (key === this.painted) return;
    this.painted = key;
    if (this.failure && !values) {
      this.body.replaceChildren(el("p", "climate-data-failure", "The climate could not be read: " + this.failure));
      return;
    }
    if (!values) { this.body.replaceChildren(el("p", "muted", "Reading the climate…")); return; }
    var edited = this.editedCells(), focused = document.activeElement === this.wind.input;
    this.body.replaceChildren.apply(this.body, [this.heading(values)].concat(this.notices(values, edited),
      [this.limitBlock(values), this.monthlyTemperatures(values, edited), this.monthlyRadiation(values, edited),
        this.peakLoads(values, edited), this.stationValues(values, edited), this.where(values)]));
    this.paintWind();
    // Moving the field into the new body drops its focus; Enter leaves the user in it.
    if (focused && this.wind.input.focus) this.wind.input.focus({ preventScroll: true });
  };

  /* With the folders read, whether none is found now: a Replace then explains instead of opening. */
  Pane.prototype.noFolder = function () {
    if (this.folders === undefined) return false;
    if (!this.folders || this.folders.failure) return true;
    return !(this.folders.folders || []).some(function (folder) { return folder.found; });
  };

  /* Each edited cell, keyed "row|column", with the file's value. */
  Pane.prototype.editedCells = function () {
    var values = this.values(), read = values.as_read, marks = {};
    (this.record.edited_cells || []).forEach(function (cell) {
      var original = null;
      if (read && cell.column === null) original = read[cell.row];
      else if (read && MONTHS.indexOf(cell.column) >= 0) {
        original = (read.monthly[cell.row] || [])[MONTHS.indexOf(cell.column)];
      }
      else if (read && read.peak_loads[cell.column]) original = read.peak_loads[cell.column][cell.row];
      marks[cell.row + "|" + cell.column] = { row: cell.row, column: cell.column, original: original };
    });
    return marks;
  };

  Pane.prototype.heading = function (values) {
    var provenance = values.provenance || {}, check = this.record.limit_check, tags = el("span", "climate-tags");
    var place = [];
    if (provenance.dataset_name) place.push(provenance.dataset_name);
    else if (values.origin === "hand") place.push("Entered by hand");
    if (values.station_latitude_deg !== null && values.station_latitude_deg !== undefined) {
      place.push(shared.coordinates({ state: "set", latitude_deg: values.station_latitude_deg,
        longitude_deg: values.station_longitude_deg, elevation_m: values.station_elevation_m }));
    }
    var verdict = !this.failure && check && check.verdict;
    if (verdict === "pass") tags.appendChild(chip("Pass", "ok"));
    if (verdict === "fail") tags.appendChild(chip("Outside Phius limits", "warning"));
    if (this.record.edited_cells && this.record.edited_cells.length) tags.appendChild(chip("Edited", "warning"));
    if (this.record.state === "incomplete") tags.appendChild(chip("Incomplete", "warning"));
    if (this.source && this.source.status === "changed") tags.appendChild(chip("Source changed"));
    var head = el("div", "climate-attached-heading");
    head.appendChild(el("h2", "", values.name));
    if (place.length) head.appendChild(el("span", "climate-attached-place", place.join(" · ")));
    head.appendChild(tags);
    return head;
  };

  /* The lines above the values: outside the limits (board 19), edited (board 15) and incomplete. */
  Pane.prototype.notices = function (values, edited) {
    var self = this, lines = [], check = this.failure ? null : this.record.limit_check, keys = Object.keys(edited);
    if (this.failure) {
      lines.push(el("p", "climate-attached-notice is-warning", "The climate could not be read again: " +
        this.failure + " What shows is the last read; the limit check is not shown until it reads."));
    }
    if (check && check.verdict === "fail") {
      lines.push(el("p", "climate-attached-notice is-warning", "Outside the Phius limits: " +
        this.failingParts(values, check).join(" and ") + ". " + CUSTOM + " The Export report says the same."));
    }
    if (keys.length) {
      var named = keys.slice(0, 3).map(function (key) { return self.editedWords(edited[key]); });
      var more = keys.length > 3 ? " and " + (keys.length - 3) + " more" : "";
      var line = el("div", "climate-attached-notice is-edited");
      line.setAttribute("role", "status");
      line.appendChild(el("p", "", keys.length + " value" + (keys.length === 1 ? " differs" : "s differ") +
        " from the station file: " + named.join(", ") + more + ". The Export report lists them."));
      var restore = ui.button("Restore Original Values", function () { self.restore(); });
      restore.disabled = this.writes.busy();
      line.appendChild(restore);
      lines.push(line);
    }
    if (this.record.state === "incomplete") {
      var gaps = this.record.missing || [], missing = gaps.slice(0, 4).map(function (gap) {
        return self.missingWords(gap);
      });
      var others = gaps.length > 4 ? "; and " + (gaps.length - 4) + " more" : "";
      lines.push(el("p", "climate-attached-notice is-warning", "Incomplete: " + missing.join("; ") + others +
        ". Export leaves the climate out until it is complete."));
    }
    return lines;
  };
  Pane.prototype.failingParts = function (values, check) {
    var parts = [], site = this.siteElevation;
    if (!check.distance_ok) parts.push(shared.formatted(check.distance_km, shared.DISTANCE) + " from the site");
    if (!check.elevation_ok) {
      var higher = site === null || site === undefined || values.station_elevation_m >= site;
      parts.push(shared.formatted(check.elevation_difference_m, shared.ELEVATION) + (higher ? " higher" : " lower") +
        " than the site");
    }
    return parts;
  };
  Pane.prototype.editedWords = function (cell) {
    var scalar = SCALARS[cell.row], field = scalar ? scalar[1] : rowField(cell.row), where;
    if (scalar) where = scalar[0];
    else if (cell.column && MONTHS.indexOf(cell.column) >= 0) {
      where = rowWord(cell.row) + ", " + MONTH_WORDS[MONTHS.indexOf(cell.column)];
    } else where = caseWord(cell.column) + " " + rowWord(cell.row).toLowerCase();
    return where + " (file " + (cell.original === null ? "empty" : shared.formatted(cell.original, field)) + ")";
  };
  Pane.prototype.missingWords = function (gap) {
    var scalar = SCALARS[gap.row];
    var word = scalar ? scalar[0] : gap.row === "wind_speed_m_s" ? "Average wind speed" : gap.row === "name" ?
      "Name" : rowWord(gap.row);
    if (!gap.columns.length) return word;
    return word + " (" + gap.columns.map(function (column) {
      var month = MONTHS.indexOf(column);
      return month >= 0 ? MONTH_WORDS[month].slice(0, 3) : caseWord(column);
    }).join(", ") + ")";
  };

  /* Distance and elevation against Phius's limits, said in mi and ft in both unit systems as the picker says
     them; or why the check did not run. */
  Pane.prototype.limitBlock = function (values) {
    var check = this.record.limit_check, block = el("div", "climate-attached-section");
    block.appendChild(el("h3", "", "Phius limit check"));
    if (this.failure) {
      block.appendChild(el("p", "climate-dialog-note", "Not shown: the climate could not be read again."));
      return block;
    }
    if (!check || check.verdict === "not_checked") {
      var why = check && check.reason === "no_site" ? "Not checked: set the site location to check the station." :
        "Not checked, entered by hand: the climate has no station coordinates.";
      block.appendChild(el("p", "climate-dialog-note", why));
      return block;
    }
    var table = el("table", "phc-table climate-attached-limits"), head = el("tr");
    table.setAttribute("aria-label", "Phius limit check");
    ["Metric", "Site and station differ by", "Phius limit", "Result"].forEach(function (word) {
      head.appendChild(el("th", "", word));
    });
    var thead = el("thead"); thead.appendChild(head); table.appendChild(thead);
    var tbody = el("tbody");
    [["Distance", shared.formatted(check.distance_km, shared.DISTANCE), "50 mi", check.distance_ok],
      ["Elevation", shared.formatted(check.elevation_difference_m, shared.ELEVATION), "400 ft",
        check.elevation_ok]].forEach(function (row) {
      var tr = el("tr"), result = el("td", "climate-attached-result");
      tr.appendChild(el("td", "", row[0])); tr.appendChild(el("td", "", row[1]));
      tr.appendChild(el("td", "muted", row[2]));
      result.appendChild(row[3] ? chip("Pass", "ok") : chip("Fail", "warning"));
      tr.appendChild(result); tbody.appendChild(tr);
    });
    table.appendChild(tbody);
    block.appendChild(scroller(table));
    return block;
  };

  /* A read-only table that scrolls sideways inside its own box, its row names held at the left. */
  function scroller(table) {
    var box = el("div", "climate-attached-scroll"); box.appendChild(table); return box;
  }
  function grid(title, columns, className) {
    var table = el("table", "phc-table climate-attached-grid " + (className || "")), head = el("tr");
    table.setAttribute("aria-label", title);
    columns.forEach(function (word, index) {
      var th = el("th", index ? "" : "climate-attached-rowname", word);
      th.setAttribute("scope", "col"); head.appendChild(th);
    });
    var thead = el("thead"); thead.appendChild(head); table.appendChild(thead);
    table.appendChild(el("tbody"));
    return table;
  }
  /* One value cell, marked when edited with the file's value on hover. */
  function cell(value, field, mark) {
    var td = el("td", "", bare(value, field));
    if (mark) {
      var file = mark.original === null ? "empty" : shared.formatted(mark.original, field);
      td.className = "is-edited";
      td.setAttribute("tabindex", "0");
      ui.tooltip(td, "Edited. The station file reads " + file + ".");
      td.setAttribute("aria-label", (value === null ? "empty" : shared.formatted(value, field)) + ", edited; the " +
        "station file reads " + file);
    }
    return td;
  }
  function nameCell(word) {
    var th = el("th", "climate-attached-rowname", word); th.setAttribute("scope", "row"); return th;
  }
  function absentRow(word, span) {
    var tr = el("tr", "climate-attached-absent"), td = el("td", "muted", NOT_IN_FILE);
    td.setAttribute("colspan", String(span));
    tr.appendChild(nameCell(word)); tr.appendChild(td);
    return tr;
  }
  function section(title, table) {
    var block = el("div", "climate-attached-section");
    block.appendChild(el("h3", "", title)); block.appendChild(scroller(table));
    return block;
  }
  function monthHeads(first) {
    return [first].concat(MONTH_WORDS.map(function (word) { return word.slice(0, 3); }));
  }

  Pane.prototype.monthlyTemperatures = function (values, edited) {
    var table = grid("Monthly temperatures", monthHeads(header("Temperature", shared.TEMPERATURE)));
    var body = table.querySelector("tbody");
    TEMPERATURE_ROWS.forEach(function (pair) { body.appendChild(monthRow(values, edited, pair[0], pair[1])); });
    body.appendChild(absentRow("Ground", 12));
    return section("Monthly temperatures", table);
  };
  Pane.prototype.monthlyRadiation = function (values, edited) {
    var table = grid("Monthly radiation", monthHeads(header("Radiation", RADIATION)));
    var body = table.querySelector("tbody");
    DIRECTIONS.forEach(function (pair) {
      body.appendChild(monthRow(values, edited, "rad_" + pair[0] + "_kwh_m2", pair[1]));
    });
    return section("Monthly radiation", table);
  };
  function monthRow(values, edited, row, word) {
    var tr = el("tr"), series = (values.monthly || {})[row] || [];
    tr.appendChild(nameCell(word));
    MONTHS.forEach(function (month, index) {
      tr.appendChild(cell(series[index], rowField(row), edited[row + "|" + month]));
    });
    return tr;
  }

  /* The three cases a Phius station file gives, then Cooling 2, which it does not (W8). */
  Pane.prototype.peakLoads = function (values, edited) {
    var rows = TEMPERATURE_ROWS.map(function (pair) { return pair[0]; }).concat(DIRECTIONS.map(function (pair) {
      return "rad_" + pair[0] + "_w_m2";
    }));
    var heads = rows.map(function (row) { return header(rowWord(row).replace(" radiation", ""), rowField(row)); });
    var table = grid("Peak loads", ["Case"].concat(heads), "climate-attached-peaks");
    var body = table.querySelector("tbody");
    CASES.forEach(function (pair) {
      var tr = el("tr"), peak = ((values.peak_loads || {})[pair[0]]) || {};
      tr.appendChild(nameCell(pair[1]));
      rows.forEach(function (row) { tr.appendChild(cell(peak[row], rowField(row), edited[row + "|" + pair[0]])); });
      body.appendChild(tr);
    });
    body.appendChild(absentRow("Cooling 2", rows.length));
    return section("Peak loads · design conditions", table);
  };

  /* The station elevation and daily swing, which an edit may mark, and the wind speed, typed in place. */
  Pane.prototype.stationValues = function (values, edited) {
    var block = el("div", "climate-attached-section"), list = el("dl", "climate-facts climate-attached-values");
    block.appendChild(el("h3", "", "Station values"));
    Object.keys(SCALARS).forEach(function (row) {
      var mark = edited[row + "|null"], field = SCALARS[row][1], value = values[row];
      var dd = el("dd", value === null ? "is-unset" : "", value === null ? "Not set" : shared.formatted(value, field));
      if (mark) {
        var file = mark.original === null ? "empty" : shared.formatted(mark.original, field);
        dd.className = "is-edited";
        ui.tooltip(dd, "Edited. The station file reads " + file + ".");
        dd.setAttribute("aria-label", dd.textContent + ", edited; the station file reads " + file);
      }
      list.appendChild(el("dt", "", SCALARS[row][0])); list.appendChild(dd);
    });
    list.appendChild(el("dt", "", "Average wind speed"));
    var wind = el("dd", "climate-attached-wind");
    wind.appendChild(this.wind.root);
    wind.appendChild(el("span", "climate-dialog-note", values.origin === "station" ?
      "Prefilled with the mean of the file's January and July wind speeds. A change here is not an edit." :
      "Typed; a station file does not give one."));
    list.appendChild(wind);
    block.appendChild(list);
    return block;
  };

  /* What the Model holds, whether the source is on this computer, and what the climate is ready for. */
  Pane.prototype.where = function (values) {
    var block = el("div", "climate-attached-section"), list = el("dl", "climate-attached-where");
    var station = values.origin === "station", edited = (this.record.edited_cells || []).length > 0;
    block.appendChild(el("h3", "", "Where this lives"));
    function row(term, nodes) {
      var dd = el("dd");
      nodes.forEach(function (node) { dd.appendChild(typeof node === "string" ? el("span", "", node) : node); });
      list.appendChild(el("dt", "", term)); list.appendChild(dd);
    }
    row("In this Model", [!station ? "The values above, entered by hand. The Model reads without any file." :
      edited ? "The values above and the values as read from the file, with the dataset name, station name and a " +
        "checksum. Restore Original Values works without the folder." :
        "A full copy of the values above, with the dataset name, station name and a checksum. The Model reads " +
        "without the folder."]);
    row("On this computer", this.sourceLine(values));
    var ready = [this.record.state === "complete" ? "Export" :
      "Not export yet: export leaves the climate out until it is complete"];
    ready.push(this.design === "set" ? "the blended heat pump, with the design temperatures" :
      "the blended heat pump once the design temperatures are set");
    row("Ready for", [ready.join("; ") + "."]);
    block.appendChild(list);
    return block;
  };
  Pane.prototype.sourceLine = function (values) {
    var self = this, source = this.source, dataset = (values.provenance || {}).dataset_name;
    if (values.origin !== "station") return ["Entered by hand; there is no station file to look for."];
    if (!source) return ["Looking for the station file…"];
    if (source.status === "found") {
      return [chip("Source found", "ok"), " " + dataset + " · the station file matches the values this Model read."];
    }
    if (source.status === "changed") {
      var update = ui.button("Update from File…", function () { self.actions.update(self.source); });
      update.disabled = this.writes.busy();
      return [chip("Source changed"), " " + dataset + " · the station file differs from the values this Model " +
        "read. Nothing updates on its own. ", update];
    }
    if (source.status === "not_on_this_computer") {
      return [chip("Not on this computer"), this.noFolder() ? " Nothing is missing from the Model. Replace will ask " +
        "for a climate data folder." : " Nothing is missing from the Model. No climate data folder on this computer " +
        "holds this station."];
    }
    if (source.status === "failed") {
      return ["The station file could not be looked for: " + (source.message || "PH-Composer did not answer.")];
    }
    return ["Looking for the station file…"];
  };

  /* The wind speed shows the Model's value unless it is being typed or saved. */
  Pane.prototype.paintWind = function () {
    var values = this.values();
    this.wind.setDisabled(!values || this.writes.busy());
    if (values && !this.wind.editing) this.wind.setValue(values.wind_speed_m_s);
  };

  /* Each write is one Undo step guarded by the eight editable fields as last read. */
  Pane.prototype.write = function (name, params) {
    var values = this.values();
    if (values && !params && this.writes.busy()) { this.queued = name; return false; }
    if (!values || this.writes.busy()) return false;
    this.writes.run(P + "climate." + name, Object.assign({ expected_values: shared.editable(values) }, params || {}));
    this.painted = null; this.paint();
    return true;
  };
  Pane.prototype.saveWind = function (value) {
    var guard = this.windGuard || (this.values() && shared.editable(this.values()));
    this.windGuard = null;
    if (!guard || this.writes.busy() || value === guard.wind_speed_m_s) { this.settled(); return; }
    var next = JSON.parse(JSON.stringify(guard)); next.wind_speed_m_s = value;
    // No repaint here: the blur that saves may be the first half of a click on another button, which a rebuilt
    // body would remove before the click lands. The answer repaints.
    this.writes.run(P + "climate.save_values", { values: next, expected_values: guard });
  };
  /* The draft is over without a write: its guard goes, and the Model's values show. */
  Pane.prototype.settled = function () {
    this.windGuard = null; this.paint(); this.paintWind();
  };
  Pane.prototype.restore = function () { this.write("restore_original"); };
  Pane.prototype.clear = function () { this.write("clear"); };

  /* The site's elevation, for the side of a failing elevation difference. */
  Pane.prototype.setSite = function (site) {
    this.siteSet = Boolean(site && site.state === "set");
    this.siteElevation = this.siteSet ? site.elevation_m : null;
  };

  /* The Model holds no climate now: what was read is not shown again when one is attached. */
  Pane.prototype.forget = function () {
    if (this.wind.editing) this.wind.cancel();
    this.wind.clearError();
    this.record = null; this.source = null; this.failure = null; this.painted = null; this.windGuard = null;
    this.editQueued = false;
  };

  Pane.prototype.dispose = function () {
    this.reads.get.reset(); this.reads.source.reset(); this.writes.reset(); this.wind.dispose();
  };

  return Pane;
});
