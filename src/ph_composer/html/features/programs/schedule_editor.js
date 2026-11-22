/* The Schedule editor's body: its type, full-load hours and users as headline values, then the PH form by type,
   the 24-hour strip and the week row, the Programs' loads that use it, and the hourly editor, planned.

   Fractional and activity: the operating hours, the level while operating and otherwise, days per week and weeks per
   year. Temperature: one value, every day. Ventilation: four periods, high, standard, basic and minimum, each hours
   per day and a fraction of the design flow, with a running total that turns amber unless it is 24 h.

   Every value commits as one `schedules.update` of that field, guarded by it as the field was drawn
   (`expected_values`), so one Undo step each, and a value changed meanwhile refuses: the panel's notice says why and
   the field shows the Model's value again on the next paint. A ventilation Schedule's hours must total 24, so its
   periods are held as one draft while they do not, and go as one update of `periods` once they do; Escape restores
   them. The strip and the week row draw the row's `profile` (features/programs/schedule.rb `ScheduleProfile`), the
   Model's values, never the draft. The host (features/programs/tab.js) owns the request: `host.update(row, values,
   expected)` and `host.refuse(text)`. */
PhComposerUI.define("features/programs/schedule_editor", ["workspace", "fields", "features/programs/program_loads"],
function (ui, fields, loads) {
  "use strict";
  var el = ui.element, svg = ui.svg;
  var TYPES = { fractional: "Fractional", activity: "Activity level", temperature: "Temperature",
    ventilation: "Ventilation" };
  var PERIODS = { high: "High", standard: "Standard", basic: "Basic", minimum: "Minimum" };
  var WEEKDAYS = [["monday", "Mon"], ["tuesday", "Tue"], ["wednesday", "Wed"], ["thursday", "Thu"],
    ["friday", "Fri"], ["saturday", "Sat"], ["sunday", "Sun"]];
  var HOURS = 24;

  /* A number with a unit the units core has no quantity for, read in the user's number format. */
  function plain(key, label, unit, extra) {
    return Object.assign({ key: key, label: label, plain: unit, field: fields.with(fields.FRACTION, { label: label }) },
      extra);
  }
  /* A whole number from `min` to `max`. */
  function whole(key, label, min, max, unit) { return plain(key, label, unit, { min: min, max: max }); }
  function fraction(key, label) {
    return { key: key, label: label, field: fields.with(fields.FRACTION, { label: label, max: 1 }) };
  }

  var START = whole("start_h", "Starts at", 0, HOURS - 1, "h");
  var END = whole("end_h", "Ends at", 0, HOURS, "h");
  var FORMS = {
    fractional: [START, END, fraction("fraction_on", "Fraction while operating"),
      fraction("fraction_off", "Fraction otherwise")],
    activity: [START, END, plain("watts_on", "While operating", "W per person"),
      plain("watts_off", "Otherwise", "W per person")],
    temperature: [{ key: "value_c", label: "Temperature", field: fields.with(fields.TEMPERATURE_C,
      { label: "Temperature" }) }],
    ventilation: []
  };
  // A temperature Schedule applies every day: the export reads no days or weeks for it.
  var WEEK = [whole("days_per_week", "Days per week", 1, 7), whole("weeks_per_year", "Weeks per year", 1, 52)];
  var PERIOD_HOURS = whole("hours", "Hours per day", 0, HOURS);
  var PERIOD_FRACTION = fraction("fraction", "Fraction of design flow");
  var CAPTIONS = {
    fractional: "The operating day, applied on the days the week row shows.",
    activity: "The operating day, in W per person, applied on the days the week row shows.",
    temperature: "One value, every hour of every day.",
    ventilation: "Four periods, as WUFI-Passive and METr read them: hours at high, standard, basic and minimum " +
      "flow, each a fraction of the design flow. Drawn end to end from midnight, in that order."
  };

  function clone(value) { return JSON.parse(JSON.stringify(value)); }
  function total(periods) { return periods.reduce(function (sum, period) { return sum + period.hours; }, 0); }

  /* The stored value a typed entry gives, or `{ error }`; whole numbers stay inside their range. */
  function parse(entry, text, settings) {
    var parsed = loads.parse(entry, text, settings);
    if (parsed.error || entry.min === undefined) return parsed;
    if (parsed.value === null || Math.round(parsed.value) !== parsed.value || parsed.value < entry.min ||
      parsed.value > entry.max) {
      return { error: entry.label + " is a whole number from " + entry.min + " to " + entry.max + "." };
    }
    return parsed;
  }

  function ScheduleEditor(host) {
    this.host = host;
    this.root = el("div", "pgm-editor sch-editor");
    this.metrics = el("div", "pgm-metrics");
    this.form = el("div", "sch-form-area");
    this.caption = el("p", "sch-caption");
    this.strip = el("div", "sch-strip");
    this.week = el("div", "sch-week");
    this.week.setAttribute("role", "img");
    this.used = el("section", "pgm-used-by");
    var hourly = el("div", "sch-hourly");
    var button = ui.button("Hourly editor", null, true);
    ui.tooltip(button, "Planned: day profiles, weekday rules and date ranges, for Schedules the PH form cannot " +
      "describe.");
    hourly.appendChild(button);
    hourly.appendChild(el("span", "muted", "Planned: for Schedules the PH form cannot describe."));
    [this.metrics, this.form, this.caption, this.strip, this.week, this.used, hourly].forEach(function (node) {
      this.root.appendChild(node);
    }, this);
    this.inputs = Object.create(null);
    this.draft = null;
  }

  ScheduleEditor.prototype.render = function (row, context) {
    // Another record, or this one of another type (an Undo, an agent's edit), starts with its fields drawn afresh.
    if (!this.row || this.row.id !== row.id || this.row.values.type !== row.values.type) {
      this.inputs = Object.create(null); this.draft = null;
    }
    this.row = row; this.context = context;
    var type = row.values.type;
    this.paintMetrics(row);
    // Built when the record, its type or the unit system changes; values are filled in place on every paint, and a
    // field the user is in keeps its focus across a rebuild.
    if (ui.memoPaint(this, "form", [row.id, type, loads.system()], null)) {
      var focused = this.form.contains(document.activeElement) ? document.activeElement : null;
      this.buildForm(type);
      if (focused && focused !== document.activeElement && this.form.contains(focused)) {
        focused.focus({ preventScroll: true });
      }
    }
    this.fill();
    this.caption.textContent = CAPTIONS[type] || "";
    // A temperature Schedule is one value all day: the strip would say nothing the value does not.
    this.strip.hidden = type === "temperature";
    this.paintStrip(row);
    this.paintWeek(row);
    this.paintUses(row);
  };

  /* ---------------------------------------------------------------- headline values */

  ScheduleEditor.prototype.paintMetrics = function (row) {
    var profile = row.profile || {}, metrics = [["Type", TYPES[row.values.type] || row.values.type]];
    if (profile.annual_full_load_hours !== null && profile.annual_full_load_hours !== undefined) {
      metrics.push(["Full-load hours [h/a]", loads.number(PERIOD_HOURS, Math.round(profile.annual_full_load_hours))]);
    }
    metrics.push(["Used by", row.use_count === 1 ? "1 load" : row.use_count + " loads"]);
    var root = this.metrics;
    ui.memoPaint(this, "metrics", metrics, function () {
      root.replaceChildren.apply(root, metrics.map(function (item) {
        var node = el("div", "pgm-metric");
        node.appendChild(el("small", "", item[0])); node.appendChild(el("strong", "", item[1]));
        return node;
      }));
    });
  };

  /* ---------------------------------------------------------------- the form */

  ScheduleEditor.prototype.buildForm = function (type) {
    var self = this, parts = [];
    if (type === "ventilation") parts.push(this.periodTable());
    if (FORMS[type].length) {
      var grid = el("div", "sch-fields");
      FORMS[type].forEach(function (entry) { grid.appendChild(self.field(entry, entry.key)); });
      parts.push(grid);
    }
    if (type !== "temperature") {
      var week = el("div", "sch-fields");
      WEEK.forEach(function (entry) { week.appendChild(self.field(entry, entry.key)); });
      parts.push(week);
    }
    this.form.replaceChildren.apply(this.form, parts);
  };

  /* The ventilation periods: one row each, its hours and its fraction, then the running total. */
  ScheduleEditor.prototype.periodTable = function () {
    var self = this, root = el("div", "sch-periods");
    var table = el("table", "sch-period-table");
    var head = el("tr");
    ["Period", "Hours per day", "Fraction of design flow"].forEach(function (text) {
      head.appendChild(el("th", "", text));
    });
    var thead = el("thead"); thead.appendChild(head); table.appendChild(thead);
    var body = el("tbody");
    Object.keys(PERIODS).forEach(function (period, index) {
      var tr = el("tr");
      tr.appendChild(el("th", "", PERIODS[period]));
      [PERIOD_HOURS, PERIOD_FRACTION].forEach(function (entry) {
        var cell = el("td");
        cell.appendChild(self.input(entry, "periods." + index + "." + entry.key, PERIODS[period] + " " +
          entry.label.toLowerCase()));
        tr.appendChild(cell);
      });
      body.appendChild(tr);
    });
    table.appendChild(body);
    this.total = el("p", "sch-total");
    this.total.setAttribute("role", "status");
    root.appendChild(table); root.appendChild(this.total);
    return root;
  };

  /* One labelled value: its label with its unit, over its input. */
  ScheduleEditor.prototype.field = function (entry, path) {
    var label = el("label", "sch-field");
    var text = el("span", "", entry.label);
    var unit = loads.unit(entry);
    if (unit && unit !== "1") text.appendChild(el("span", "unit", " [" + unit + "]"));
    label.appendChild(text);
    label.appendChild(this.input(entry, path, entry.label));
    return label;
  };

  /* An input that commits on Enter or leaving it, and restores the Model's value on Escape. `path` is the value's
     key, or `periods.<index>.<key>` for a ventilation period's. */
  ScheduleEditor.prototype.input = function (entry, path, name) {
    var self = this, input = this.inputs[path];
    if (input) return input;
    input = this.inputs[path] = el("input", "pgm-input sch-input");
    input.type = "text"; input.setAttribute("inputmode", "decimal");
    input.setAttribute("autocomplete", "off"); input.setAttribute("spellcheck", "false");
    input.setAttribute("aria-label", name);
    input.entry = entry; input.path = path;
    input.addEventListener("input", function () {
      // The entry is guarded by the value as it was when typing began, and read in the units it began in.
      if (!input.typed) {
        input.baseline = self.stored(path); input.profile = loads.profile(entry); input.record = self.row.id;
        // A period's edit is guarded by all four periods as they were when typing began.
        if (/^periods\./.test(path)) input.periods = clone(self.draft ? self.draft.baseline : self.row.values.periods);
      }
      input.typed = true;
    });
    input.addEventListener("keydown", function (event) {
      if (event.key === "Enter") { event.preventDefault(); self.commit(input); }
      if (event.key !== "Escape") return;
      // One layer at a time: the typing, then a held draft of the periods.
      if (input.typed) { input.typed = false; self.fill(); }
      else if (self.draft && /^periods\./.test(path)) { self.draft = null; self.fill(); }
      else return;
      event.preventDefault(); event.stopPropagation();
    });
    input.addEventListener("blur", function () { self.commit(input); });
    return input;
  };

  /* The value at `path` as the Model holds it, or as the held draft does. */
  ScheduleEditor.prototype.stored = function (path) {
    var parts = path.split(".");
    if (parts[0] !== "periods") return this.row.values[path];
    var periods = this.draft ? this.draft.periods : this.row.values.periods || [];
    var period = periods[Number(parts[1])];
    return period ? period[parts[2]] : null;
  };

  ScheduleEditor.prototype.commit = function (input) {
    if (!input.typed) return;
    input.typed = false;
    // Typing began on a record no longer shown: it goes nowhere.
    if (input.record !== this.row.id) return;
    var parsed = parse(input.entry, input.value, input.profile);
    if (parsed.error) { this.host.refuse(parsed.error); this.fill(); return; }
    if (parsed.value === input.baseline || input.value.trim() === input.seed) { this.fill(); return; }
    var parts = input.path.split(".");
    if (parts[0] === "periods") { this.commitPeriod(Number(parts[1]), parts[2], parsed.value, input.periods); return; }
    var values = {}, expected = {};
    values[input.path] = parsed.value; expected[input.path] = input.baseline;
    this.host.update(this.row, values, expected);
  };

  /* A period's hours or fraction: one update of `periods` once the hours total 24, held as a draft until then. */
  ScheduleEditor.prototype.commitPeriod = function (index, key, value, began) {
    var baseline = this.draft ? this.draft.baseline : began;
    var periods = this.draft ? this.draft.periods : clone(began);
    periods[index][key] = value;
    if (JSON.stringify(periods) === JSON.stringify(baseline)) { this.draft = null; this.fill(); return; }
    if (total(periods) !== HOURS) { this.draft = { baseline: baseline, periods: periods }; this.fill(); return; }
    // Sent: the fields keep the periods until the next paint shows the Model's, saved or refused.
    if (this.host.update(this.row, { periods: periods }, { periods: baseline })) this.draft = null;
    else { this.draft = { baseline: baseline, periods: periods }; this.fill(); }
  };

  /* Values into the fields, except one being typed into, and the running total. */
  ScheduleEditor.prototype.fill = function () {
    var self = this, enabled = this.context.enabled;
    Object.keys(this.inputs).forEach(function (path) {
      var input = self.inputs[path], text = loads.editText(input.entry, self.stored(path));
      if (!input.typed || document.activeElement !== input) { input.value = text; input.typed = false; }
      input.seed = text;
      input.disabled = !enabled;
      input.classList.toggle("is-held", Boolean(self.draft) && /^periods\./.test(path));
    });
    if (this.row.values.type !== "ventilation" || !this.total) return;
    var hours = total(this.draft ? this.draft.periods : this.row.values.periods), off = hours !== HOURS;
    this.total.classList.toggle("is-missing", off);
    this.total.replaceChildren();
    if (off) {
      var flag = ui.glyph("alert"); flag.classList.add("pgm-flag");
      flag.setAttribute("role", "img"); flag.setAttribute("aria-label", "The four periods must total 24 hours.");
      ui.tooltip(flag, "The four periods must total 24 hours. Nothing is saved until they do; Escape restores them.");
      this.total.appendChild(flag);
    }
    this.total.appendChild(el("span", "", "Total " + hours + " of 24 h"));
  };

  /* Whether a field holds typing, or the periods a draft, the Model has not taken yet. */
  ScheduleEditor.prototype.typing = function () {
    // Typing back to the Model's value holds nothing, as its commit sends nothing.
    return Boolean(this.draft) || Object.keys(this.inputs).some(function (path) {
      var input = this.inputs[path];
      return input.typed && input.value.trim() !== input.seed;
    }, this);
  };

  /* Why the page may not move on: a held draft of the periods, or typing. */
  ScheduleEditor.prototype.guard = function () {
    if (this.draft) return "Make the ventilation periods total 24 h, or press Escape in one of them to restore them.";
    return this.typing() ? "Finish or cancel the value being typed." : null;
  };

  /* ---------------------------------------------------------------- strip, week and uses */

  /* The 24-hour profile as bars: a fraction against 1, a level against the day's highest. */
  ScheduleEditor.prototype.paintStrip = function (row) {
    var hours = (row.profile || {}).hours || [], type = row.values.type;
    var root = this.strip;
    ui.memoPaint(this, "strip", [hours, type, loads.system()], function () {
      var fractional = type === "fractional" || type === "ventilation";
      var top = fractional ? 1 : Math.max.apply(null, hours.map(Math.abs).concat([0])) || 1;
      var width = 22, height = 70, left = 30;
      var node = svg("svg", { "class": "sch-strip-svg", viewBox: "0 0 " + (left + width * HOURS) + " " + (height + 18),
        role: "img", "aria-label": "24-hour profile" });
      node.appendChild(svg("line", { x1: left, y1: height, x2: left + width * HOURS, y2: height,
        "class": "sch-axis" }));
      hours.forEach(function (value, hour) {
        var bar = Math.max(0, Math.min(1, value / top)) * (height - 4);
        var rect = svg("rect", { x: left + 1 + hour * width, y: height - bar, width: width - 2, height: bar,
          "class": "sch-bar" });
        rect.appendChild(svg("title", {}, hour + ":00, " + loads.number(fractional ? PERIOD_FRACTION :
          FORMS.activity[2], value) + (type === "activity" ? " W per person" : "")));
        node.appendChild(rect);
        if (hour % 3 === 0) node.appendChild(svg("text", { x: left + 1 + hour * width, y: height + 14 }, String(hour)));
      });
      node.appendChild(svg("text", { x: 0, y: 10 }, fractional ? "1" : String(Math.round(top))));
      node.appendChild(svg("text", { x: 0, y: height }, "0"));
      root.replaceChildren(node);
    });
  };

  ScheduleEditor.prototype.paintWeek = function (row) {
    var on = (row.profile || {}).weekdays || [], root = this.week;
    ui.memoPaint(this, "week", on, function () {
      root.setAttribute("aria-label", "Applies on " + (on.length === 7 ? "every day" : on.length ?
        WEEKDAYS.filter(function (day) { return on.indexOf(day[0]) >= 0; }).map(function (day) { return day[1]; })
          .join(", ") : "no day"));
      root.replaceChildren.apply(root, [el("span", "sch-week-label", "Week")].concat(WEEKDAYS.map(function (day) {
        return el("span", "sch-day" + (on.indexOf(day[0]) >= 0 ? " is-on" : ""), day[1]);
      })));
    });
  };

  ScheduleEditor.prototype.paintUses = function (row) {
    var uses = (row.uses || []).map(function (use) {
      var load = loads.load(use.slot.split(".")[0]);
      return load ? use.name + " · " + load.label : use.name;
    }), root = this.used;
    ui.memoPaint(this, "uses", uses, function () {
      var nodes = [el("h3", "", "Used by")];
      if (!uses.length) nodes.push(el("p", "muted", "No Program uses this Schedule."));
      uses.forEach(function (text) { nodes.push(el("div", "pgm-use", text)); });
      root.replaceChildren.apply(root, nodes);
    });
  };

  ScheduleEditor.TYPES = TYPES;
  return ScheduleEditor;
});
