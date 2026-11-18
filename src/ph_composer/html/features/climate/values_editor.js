/* The values editor behind Enter Values by Hand and Edit Values (boards 12 and 15): the name, the station values
   and coordinates above one grid in the order of a Phius climate file, eight series rows by twelve months and the
   three design columns. One paste of tab-separated rows fills it from the focused cell (owed check 5: a label
   column copied with the rows is left out); any cell can be typed, and the arrow keys move between cells. The grid's
   units follow the preference until the first key or paste, then hold for the draft. A value whose text is as it
   opened sends the value it opened with, so Edit Values marks only what changed. Save sends one `enter_values`, or
   `save_values` guarded by the values opened, one Undo step; it saves with gaps, and a refusal keeps the draft.
   Completeness and edited cells are the host's. */
PhComposerUI.define("features/climate/values_editor", ["workspace", "record_form", "unit_field", "unit_numbers",
  "unit_preferences", "units", "fields", "inventory_grid", "features/climate/shared"],
function (ui, RecordForm, unitField, numbers, preferences, units, fields, Grid, shared) {
  "use strict";
  var el = ui.element, P = shared.PREFIX + "climate.";
  // The Phius file's series order: each row's monthly and peak-load keys and its words.
  var ROWS = [["air_c", "air_c", "Outdoor temperature"], ["rad_north_kwh_m2", "rad_north_w_m2", "North"],
    ["rad_east_kwh_m2", "rad_east_w_m2", "East"], ["rad_south_kwh_m2", "rad_south_w_m2", "South"],
    ["rad_west_kwh_m2", "rad_west_w_m2", "West"], ["rad_global_kwh_m2", "rad_global_w_m2", "Global"],
    ["dewpoint_c", "dewpoint_c", "Dewpoint"], ["sky_c", "sky_c", "Sky temperature"]];
  var WIDTH = 15, MONTH_WORDS = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"];
  var DESIGN = ["Heating 1", "Heating 2", "Cooling"];

  function Editor(session, send, record, closed) {
    var self = this, station = Boolean(record && record.origin === "station");
    RecordForm.call(this, session, send, { title: record ? "Edit climate values" : "Enter Phius climate values",
      action: P + (record ? "save_values" : "enter_values"), label: "climate_values", submitLabel: "Save",
      pendingText: "Saving the climate…", failureText: "The climate was not saved.", className: "climate-values",
      changed: function () { self.dispose(); closed(); } });
    this.record = record; this.station = station; this.profile = null;
    this.form.appendChild(el("p", "climate-dialog-note", "Type the values, or copy the eight series rows from a " +
      "Phius climate workbook or station file and paste them into a cell. A label column is left out."));
    var top = el("div", "climate-values-fields");
    this.name = this.text(top, "Name", "");
    this.elevation = this.unit(top, "Station elevation", shared.ELEVATION);
    this.swing = this.unit(top, "Daily temperature swing", fields.TEMPERATURE_DIFFERENCE_K);
    this.wind = this.unit(top, "Average wind speed", fields.WIND_SPEED_M_S);
    this.latitude = this.text(top, "Latitude", "°");
    this.longitude = this.text(top, "Longitude", "°");
    this.form.appendChild(top);
    var values = record || {};
    this.name.value = values.name || "";
    var place = [[this.latitude, values.station_latitude_deg], [this.longitude, values.station_longitude_deg]];
    place.forEach(function (pair) {
      pair[0].value = pair[0]._shown = coordinate(pair[1]); pair[0]._original = pair[1] === undefined ? null : pair[1];
    });
    this.elevation.setValue(values.station_elevation_m);
    this.swing.setValue(values.daily_temp_swing_k);
    this.wind.setValue(values.wind_speed_m_s);
    [this.name, this.latitude, this.longitude].forEach(function (input) { input.readOnly = station; });
    this.form.appendChild(el("p", "climate-dialog-note", station ? "The station's name and coordinates come from " +
      "its file; Replace changes the station." : "Latitude and longitude are optional. Without them the Phius " +
      "limit check reads Not checked, entered by hand."));
    this.notice = el("p", "climate-dialog-note climate-values-notice");
    this.notice.setAttribute("role", "status");
    this.form.appendChild(this.notice);
    this.form.appendChild(this.buildGrid(values));
    this.unitNote = el("p", "climate-dialog-note");
    this.unitNote.id = "climate-values-units";
    this.form.appendChild(this.unitNote);
    this.form.appendChild(el("p", "climate-dialog-note", "Gaps may be saved: the climate then reads Incomplete, " +
      "and export leaves it out until it is complete."));
    this.finish();
    this.fill();
    this.paint();
    this.unsubscribe = preferences.subscribe(function () { if (!self.profile) self.fill(); });
    document.body.appendChild(this.root);
    this.show();
    (station ? this.cells[0][0] : this.name).focus();
  }
  RecordForm.extend(Editor);

  function format() { return numbers.normalizeNumberFormat(preferences.current().numberFormat); }
  function coordinate(value) {
    return value === null || value === undefined ? "" : String(value).replace(".", format().decimal);
  }

  Editor.prototype.labelled = function (parent, title, control) {
    var label = el("label", "climate-field");
    label.appendChild(el("span", "climate-field-label", title));
    label.appendChild(control);
    parent.appendChild(label);
  };
  Editor.prototype.text = function (parent, title, unit) {
    var self = this, input = el("input"), wrap = el("span", "phc-unit-field");
    input.type = "text"; input.setAttribute("autocomplete", "off"); input.setAttribute("aria-label", title);
    input.addEventListener("input", function () { self.paint(); });
    wrap.appendChild(input);
    if (unit) wrap.appendChild(el("span", "phc-unit-label", unit));
    this.labelled(parent, title, wrap);
    return input;
  };
  Editor.prototype.unit = function (parent, title, field) {
    var self = this, unit = new unitField.UnitField({ field: fields.with(field, { label: title, allowBlank: true }),
      onCommit: function () { self.paint(); }, onCancel: function () { self.paint(); } });
    unit.input.addEventListener("input", function () { self.paint(); });
    this.labelled(parent, title, unit.root);
    return unit;
  };

  Editor.prototype.buildGrid = function (values) {
    var self = this, table = el("table", "phc-table climate-attached-grid climate-values-grid"), head = el("tr");
    var body = el("tbody"), thead = el("thead"), monthly = values.monthly || {}, peaks = values.peak_loads || {};
    table.setAttribute("aria-label", "Climate values");
    ["Series"].concat(MONTH_WORDS, DESIGN).forEach(function (word, index) {
      var th = el("th", index ? (index > 12 ? "is-design" : "") : "climate-attached-rowname", word);
      th.setAttribute("scope", "col"); head.appendChild(th);
    });
    thead.appendChild(head); table.appendChild(thead); table.appendChild(body);
    this.heads = [];
    this.cells = ROWS.map(function (row, r) {
      var tr = el("tr"), th = el("th", "climate-attached-rowname");
      th.setAttribute("scope", "row"); tr.appendChild(th); self.heads.push(th);
      var inputs = [];
      for (var c = 0; c < WIDTH; c += 1) {
        var design = c >= 12, input = el("input", "phc-cell-input"), td = el("td", design ? "is-design" : "");
        var original = design ? (peaks[shared.CASES[c - 12][0]] || {})[row[1]] : (monthly[row[0]] || [])[c];
        input.type = "text"; input.setAttribute("autocomplete", "off");
        input.setAttribute("aria-describedby", "climate-values-units");
        input.setAttribute("aria-label", row[2] + ", " + (design ? DESIGN[c - 12] : MONTH_WORDS[c]));
        input._at = [r, c]; input._field = shared.rowField(design ? row[1] : row[0]);
        input._original = original === undefined ? null : original; input._shown = "";
        td.appendChild(input); tr.appendChild(td); inputs.push(input);
      }
      body.appendChild(tr);
      return inputs;
    });
    table.addEventListener("input", function (event) {
      if (!event.target._at) return;
      self.begin(); event.target.setAttribute("aria-invalid", "false"); self.paint();
    });
    table.addEventListener("paste", function (event) { self.paste(event); });
    table.addEventListener("keydown", function (event) { self.move(event); });
    var scroll = el("div", "climate-attached-scroll climate-values-scroll");
    scroll.appendChild(table);
    return scroll;
  };

  /* The draft's units: the preference until the first key or paste in the grid, then held. */
  Editor.prototype.profileNow = function () { return this.profile || units.profile({}); };
  Editor.prototype.begin = function () { if (!this.profile) this.profile = units.profile({}); };

  /* Each cell as it opened shows its opening value, and the headings their units, in the draft's units. */
  Editor.prototype.fill = function () {
    var self = this, profile = this.profileNow();
    this.cells.forEach(function (row) {
      row.forEach(function (input) {
        if (input.value === input._shown) {
          input.value = input._shown = input._original === null ? "" :
            units.formatEdit(input._original, input._field, profile);
        }
      });
    });
    ROWS.forEach(function (row, r) {
      self.heads[r].textContent = /_c$/.test(row[0]) ? units.header(row[2], shared.TEMPERATURE, profile) : row[2];
    });
    this.unitNote.textContent = "Radiation rows: " + units.displayUnit(shared.RADIATION, profile) + " for each " +
      "month, " + units.displayUnit(shared.PEAK, profile) + " in the three design columns.";
  };

  /* A typed or pasted text read as the cell's value: a number, null when empty, undefined when not a number. */
  Editor.prototype.read = function (input, text) {
    var parsed = units.parse(text.replace(/\u2212/g, "-"), input._field,
      units.parseContext(input._field, this.profileNow()));
    return parsed.ok ? parsed.value : undefined;
  };

  /* One tab-separated block fills the grid from the focused cell, as one draft change; nothing is saved. A block
     larger than the grid from there fills nothing; a cell that is not a number is left empty and counted. */
  Editor.prototype.paste = function (event) {
    var self = this, at = event.target._at, rows, text = event.clipboardData.getData("text/plain");
    if (!at) return;
    event.preventDefault();
    if (!text.trim()) return;
    try { rows = Grid.parse(text); } catch (error) { this.say(error.message); return; }
    // A leading column of words on every row, beside values, is a label column.
    var probe = this.cells[0][0];
    function label(row) { var word = row[0].trim(); return word && self.read(probe, word) === undefined; }
    if (rows.some(function (row) { return row.length > 1; }) && rows.every(label)) {
      rows = rows.map(function (row) { return row.slice(1); });
    }
    var width = Math.max.apply(null, rows.map(function (row) { return row.length; }));
    if (at[0] + rows.length > ROWS.length || at[1] + width > WIDTH) {
      this.say("The pasted block is " + rows.length + " rows by " + width + " values; from this cell the grid " +
        "holds " + (ROWS.length - at[0]) + " by " + (WIDTH - at[1]) + ". Nothing was filled.");
      return;
    }
    this.begin();
    var skipped = 0;
    rows.forEach(function (row, r) {
      row.forEach(function (text, c) {
        var input = self.cells[at[0] + r][at[1] + c], value = text.trim();
        if (value && self.read(input, value) === undefined) { skipped += 1; value = ""; }
        input.value = value; input.setAttribute("aria-invalid", "false");
      });
    });
    this.say("Pasted " + rows.length + " row" + (rows.length === 1 ? "" : "s") + "." + (skipped ? " " + skipped +
      (skipped === 1 ? " value was not a number and was" : " values were not numbers and were") + " left empty." : ""));
    this.paint();
  };
  Editor.prototype.say = function (message) { this.notice.textContent = message; };

  /* The arrow keys move between cells (left and right at the text's ends), Enter moves down; Tab is the page's. */
  Editor.prototype.move = function (event) {
    var input = event.target, at = input._at, r, c, end = input.value.length;
    if (!at || event.shiftKey || event.altKey || event.ctrlKey || event.metaKey || event.isComposing) return;
    r = at[0]; c = at[1];
    if (event.key === "ArrowUp") r -= 1;
    else if (event.key === "ArrowDown" || event.key === "Enter") r += 1;
    else if (event.key === "ArrowLeft" && input.selectionStart === 0 && input.selectionEnd === 0) c -= 1;
    else if (event.key === "ArrowRight" && input.selectionStart === end) c += 1;
    else return;
    event.preventDefault();
    var next = (this.cells[r] || [])[c];
    if (next) { next.focus(); next.select(); }
  };

  /* A field whose text is as it opened answers its opening value, not the rounded text. */
  function fieldValue(unit) {
    if (!unit.editing || unit.input.value === unit.seed) return unit.baseline;
    var parsed = unit.parse();
    if (!parsed.ok) unit.commit();
    return parsed.ok ? parsed.value : undefined;
  }
  function number(input) {
    var text = input.value.trim().replace(/\u2212/g, "-");
    if (input.value === input._shown) return input._original;
    if (!text) return null;
    var parsed = numbers.parseRegionalNumber(text, format());
    input.setAttribute("aria-invalid", String(!parsed.ok));
    return parsed.ok ? parsed.value : undefined;
  }

  /* Save waits for a name and a station elevation; an elevation that is not a number says so on Save. */
  Editor.prototype.ready = function () {
    var elevation = this.elevation.editing ? this.elevation.input.value.trim() : this.elevation.baseline;
    return Boolean(this.name.value.trim()) && elevation !== null && elevation !== "";
  };
  Editor.prototype.paint = function () { this.submitButton.disabled = this.busy() || !this.ready(); };

  /* The eight editable fields, or a sentence counting the values that are not numbers, each marked. */
  Editor.prototype.values = function () {
    var self = this, record = this.record || {}, bad = 0;
    function check(value) { if (value === undefined) bad += 1; return value === undefined ? null : value; }
    function cell(input) {
      if (input.value === input._shown) return input._original;
      var value = self.read(input, input.value);
      input.setAttribute("aria-invalid", String(value === undefined));
      return check(value);
    }
    var out = { name: this.station ? record.name : this.name.value.trim(),
      station_latitude_deg: this.station ? record.station_latitude_deg : check(number(this.latitude)),
      station_longitude_deg: this.station ? record.station_longitude_deg : check(number(this.longitude)),
      station_elevation_m: check(fieldValue(this.elevation)), daily_temp_swing_k: check(fieldValue(this.swing)),
      wind_speed_m_s: check(fieldValue(this.wind)), monthly: {}, peak_loads: {} };
    shared.CASES.forEach(function (pair) { out.peak_loads[pair[0]] = {}; });
    ROWS.forEach(function (row, r) {
      out.monthly[row[0]] = self.cells[r].slice(0, 12).map(cell);
      shared.CASES.forEach(function (pair, i) { out.peak_loads[pair[0]][row[1]] = cell(self.cells[r][12 + i]); });
    });
    if (!bad) return out;
    return bad + (bad === 1 ? " value is not a number" : " values are not numbers") + ". Correct or clear the " +
      "marked field" + (bad === 1 ? "." : "s.");
  };

  Editor.prototype.submit = function () {
    if (this.busy() || !this.ready()) return;
    var values = this.values();
    if (typeof values === "string") { this.error.textContent = values; return; }
    var params = { values: values };
    if (this.record) params.expected_values = shared.editable(this.record);
    if (this.run(params)) this.paint();
  };

  /* A saved climate closes the editor; a refusal (a stale record, a value the host rejects) keeps the draft. */
  Editor.prototype.consume = function (state) {
    var outcome = this.settle(state);
    if (!outcome) return;
    if (outcome.status === "completed") this.hide(); else this.paint();
  };

  Editor.prototype.dispose = function () {
    this.withdraw();
    if (this.unsubscribe) this.unsubscribe();
    [this.elevation, this.swing, this.wind].forEach(function (unit) { unit.dispose(); });
    if (this.root.parentNode) this.root.parentNode.removeChild(this.root);
  };

  return { open: function (session, send, record, closed) { return new Editor(session, send, record, closed); } };
});
