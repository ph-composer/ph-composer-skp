/* The device dialog: Add and Edit share it, one form dialog laid out from `equipment_sets.device_types`
   (features/programs/equipment_types.rb): Device (type, chosen on Add and fixed on Edit; name; quantity; in
   conditioned space; comment), Energy (the reference quantities the type allows; the energy demand and its period,
   or the Phius rule a rule device follows), the type's own fields (each shown only where the catalog says it
   applies, such as a gas dryer's gas fields), and PHPP only. Words for the codes and fields are this file's; which
   fields a type carries, what they allow and a new device's values are the catalog's.

   Add sends the whole device as `add_device`; Edit sends only the values changed, guarded by them as the dialog
   opened (`update_device`), so each is one Undo step and a device changed meanwhile refuses with the draft kept.
   The request is the form's own, one at a time (record_form.js); the owner settles it from its render. */
PhComposerUI.define("features/programs/device_dialog", ["record_form", "workspace", "fields",
  "features/programs/program_loads"],
function (RecordForm, ui, fields, loads) {
  "use strict";
  var el = ui.element;
  var PREFIX = "ph_composer.programs.equipment_sets.";
  var REFERENCE = { 1: "PH-case occupants", 2: "Zone occupants", 3: "Bedrooms", 4: "PH-case units",
    5: "User defined", 6: "PH-case floor area", 7: "Zone floor area", 8: "n.a." };
  var RULES = { phius_mel: "Phius rule: bedrooms and iCFA", phius_lighting_interior: "Phius rule: iCFA",
    phius_lighting_exterior: "Phius rule: iCFA", phius_lighting_garage: "Phius rule: per dwelling" };
  var ENERGY = ["reference_energy_norm", "energy_demand", "combined_energy_factor"];
  var PHPP = ["energy_demand_per_use"];
  function number(label, unit, extra) {
    return Object.assign({ label: label, plain: unit || "", field: fields.with(fields.FRACTION, { label: label }) },
      extra);
  }
  /* Each field's words: a number's label and unit, or a choice's options by stored value. */
  var WORDS = {
    quantity: number("Quantity", "", { whole: true, help: "The number of units; the energy demand is for one." }),
    energy_demand: number("Energy demand", "kWh"),
    energy_demand_per_use: number("Energy per use", "kWh", { help: "PHPP reads this; WUFI-Passive and METr " +
      "ignore it." }),
    capacity_type: { label: "Capacity, preselection", options: { 1: "Standard" } },
    capacity_place_settings: number("Capacity", "place settings"),
    capacity_m3: { label: "Capacity", field: fields.with(fields.VOLUME_M3, { label: "Capacity" }) },
    modified_energy_factor: number("MEF, modified energy factor"),
    utilization_factor: number("Utilization factor"),
    water_connection: { label: "Water connection", options: { dhw: "DHW connection",
      cold_water: "Cold water connection" } },
    dryer_type: { label: "Dryer type", options: { clothes_line: "Clothes line",
      drying_closet_cold: "Drying closet (cold)", drying_closet_cold_extract_air: "Drying closet (cold) in extract air",
      condensation: "Condensation dryer", electric_exhaust_air: "Electric exhaust air dryer",
      gas_exhaust_air: "Gas exhaust air dryer", heat_pump: "Heat pump dryer" } },
    combined_energy_factor: number("CEF, combined energy factor", "lb/kWh"),
    gas_consumption: number("Gas consumption", "kWh"),
    gas_efficiency_factor: number("Gas efficiency factor"),
    field_utilization_factor_type: { label: "Field utilization factor, preselection",
      options: { 1: "Timer controls" } },
    field_utilization_factor: number("Field utilization factor"),
    cooktop_type: { label: "Cooktop type", options: { electricity: "Electricity", natural_gas: "Natural gas",
      lpg: "LPG" } },
    high_efficacy_fraction: { label: "High-efficacy fraction", field: fields.with(fields.FRACTION,
      { label: "High-efficacy fraction", max: 1 }) },
    reference_energy_norm: { label: "Energy demand per", options: { 1: "Day", 2: "Year" } }
  };

  function clone(value) { return JSON.parse(JSON.stringify(value)); }

  /* The period an energy demand is given for, as its unit says it. */
  function demandUnit(type, device) {
    if (device.reference_energy_norm === 1) return type.type === "cooktop" ? "kWh/use" : "kWh/d";
    return "kWh/a";
  }

  /* A device's energy demand as the grid shows it. */
  function demand(type, device) {
    if (type && type.phius_rule) return { rule: RULES[type.type] || "Phius rule" };
    if (device.combined_energy_factor !== undefined && device.energy_demand === undefined) {
      return { text: "CEF " + loads.number(WORDS.combined_energy_factor, device.combined_energy_factor) + " lb/kWh" };
    }
    if (device.energy_demand === undefined || device.energy_demand === null) return { text: "—" };
    return { text: loads.number(WORDS.energy_demand, device.energy_demand) + " " + demandUnit(type || {}, device) };
  }

  /* Whether a field means something under the draft's values (`applies_when` in the catalog). */
  function applies(field, draft) {
    var when = field.applies_when;
    return !when || Object.keys(when).every(function (key) { return when[key].indexOf(draft[key]) >= 0; });
  }

  /* `options`: { session, send, set, types, device (null on Add), changed(outcome) }. */
  function DeviceDialog(options) {
    var adding = !options.device, set = options.set, self = this;
    this.types = options.types; this.set = set; this.adding = adding;
    this.opened = adding ? null : clone(options.device);
    var first = this.types[0];
    this.draft = adding ? Object.assign({ type: first.type }, clone(first.defaults)) : clone(options.device);
    this.typed = {};
    RecordForm.call(this, options.session, options.send, {
      title: adding ? "Add device to " + set.values.name : "Edit " + options.device.display_name,
      action: PREFIX + (adding ? "add_device" : "update_device"), label: adding ? "add-device" : "edit-device",
      submitLabel: adding ? "Add device" : "Save", pendingText: adding ? "Adding the device..." : "Saving...",
      failureText: adding ? "The device was not added." : "The device was not saved.", className: "pgm-device-dialog",
      changed: function (outcome) { options.changed(outcome, self); } });
    this.body = el("div", "pgm-device-body");
    this.form.appendChild(this.body);
    this.finish();
    this.layout();
  }
  RecordForm.extend(DeviceDialog);

  DeviceDialog.prototype.type = function () {
    var name = this.draft.type;
    return this.types.filter(function (entry) { return entry.type === name; })[0];
  };

  /* Lays the form out for the draft's type and values: a choice that shows or hides fields lays it out again. */
  DeviceDialog.prototype.layout = function () {
    var self = this, type = this.type(), draft = this.draft;
    var focusedKey = this.root.contains(document.activeElement) && document.activeElement.getAttribute("data-key");
    this.inputs = {};
    var sections = [];
    var device = this.section("Device");
    if (this.adding) {
      device.add("Type", this.select("type", this.types.map(function (entry) { return [entry.type, entry.label]; })));
    } else {
      var fixed = el("span", "pgm-device-type", type.label);
      fixed.appendChild(el("span", "muted", " To change the type, delete it and add another."));
      device.add("Type", fixed);
    }
    device.add("Name", this.text("display_name"));
    device.add(WORDS.quantity.label, this.number("quantity", WORDS.quantity));
    var inside = el("input"); inside.type = "checkbox"; inside.setAttribute("data-key", "in_conditioned_space");
    inside.checked = Boolean(draft.in_conditioned_space);
    inside.setAttribute("aria-label", "In conditioned space");
    this.inputs.in_conditioned_space = inside;
    var check = el("span", "pgm-device-check");
    check.appendChild(inside); check.appendChild(el("span", "muted", "Its waste heat counts as an internal gain."));
    device.add("In conditioned space", check, true);
    var comment = this.text("comment"); comment.placeholder = "Shown in WUFI-Passive and METr";
    device.add("Comment", comment);
    sections.push(device.root);

    var fieldsByKey = {};
    type.fields.forEach(function (field) { fieldsByKey[field.key] = field; });
    var energy = this.section("Energy");
    energy.add("Reference quantity", this.select("reference_quantity", type.reference_quantities.map(function (code) {
      return [code, REFERENCE[code] || String(code)];
    }), true));
    if (type.phius_rule) {
      var rule = el("span", "pgm-device-rule");
      rule.appendChild(el("span", "pgm-sigma", "Σ " + (RULES[type.type] || "Phius rule")));
      rule.appendChild(el("span", "muted", " Worked out by WUFI-Passive and METr from the reference quantity."));
      energy.add("Energy demand", rule);
    }
    ENERGY.forEach(function (key) {
      var field = fieldsByKey[key];
      if (!field || !applies(field, draft)) return;
      if (key === "reference_energy_norm") {
        if (type.energy_norms.length < 2) return;
        energy.add(WORDS[key].label, self.select(key, type.energy_norms.map(function (code) {
          return [code, code === 1 && type.type === "cooktop" ? "Use" : WORDS[key].options[code]];
        }), true));
        return;
      }
      var words = key === "energy_demand" ? number("Energy demand", demandUnit(type, draft)) : WORDS[key];
      energy.add(self.label(words), self.number(key, words));
    });
    sections.push(energy.root);

    var own = type.fields.filter(function (field) {
      return ENERGY.indexOf(field.key) < 0 && PHPP.indexOf(field.key) < 0 && applies(field, draft);
    });
    if (own.length) {
      var section = this.section(type.label);
      own.forEach(function (field) { section.add(self.label(WORDS[field.key]), self.control(field)); });
      sections.push(section.root);
    }
    var phpp = type.fields.filter(function (field) { return PHPP.indexOf(field.key) >= 0; });
    if (phpp.length) {
      var only = this.section("PHPP only");
      phpp.forEach(function (field) { only.add(self.label(WORDS[field.key]), self.control(field)); });
      sections.push(only.root);
    }
    this.body.replaceChildren.apply(this.body, sections);
    var again = focusedKey && this.inputs[focusedKey];
    if (again) again.focus({ preventScroll: true });
  };

  DeviceDialog.prototype.label = function (words) {
    var unit = words.field ? loads.unit(words) : "";
    return words.label + (unit && unit !== "1" ? " [" + unit + "]" : "");
  };

  /* A section: its heading, then label-beside-control rows. */
  DeviceDialog.prototype.section = function (title) {
    var root = el("section", "pgm-device-section");
    root.appendChild(el("h3", "", title));
    return { root: root, add: function (label, control, plainLabel) {
      var labelled = !plainLabel && /^(INPUT|SELECT)$/.test(control.tagName.toUpperCase());
      var row = el(labelled ? "label" : "div", "pgm-device-row");
      row.appendChild(el("span", "pgm-device-label", label));
      row.appendChild(control);
      root.appendChild(row);
    } };
  };

  DeviceDialog.prototype.control = function (field) {
    var words = WORDS[field.key];
    if (words.options) {
      var choices = (field.schema.enum || Object.keys(words.options)).map(function (value) {
        return [value, words.options[value] || String(value)];
      });
      return this.select(field.key, choices, field.schema.type === "integer");
    }
    return this.number(field.key, words);
  };

  DeviceDialog.prototype.text = function (key) {
    var self = this, input = el("input");
    input.type = "text"; input.value = this.draft[key] || ""; input.setAttribute("data-key", key);
    input.addEventListener("input", function () { self.clearStatus(); });
    this.inputs[key] = input;
    return input;
  };

  /* A number shows the draft's value as its seed; only text that differs from the seed is read back, so a value the
     user left alone is never rounded by its display. Typed text that does not read yet survives a layout with the
     units and number format it was typed in. */
  DeviceDialog.prototype.number = function (key, words) {
    var self = this, input = el("input", "pgm-device-number"), typed = this.typed, kept = typed[key];
    input.type = "text"; input.setAttribute("inputmode", "decimal"); input.setAttribute("autocomplete", "off");
    input.setAttribute("data-key", key);
    // Kept text keeps the seed it was compared with, drawn in the same units, so it is never mistaken for one.
    input.seed = kept ? kept.seed : loads.editText(words, this.draft[key]); input.seedValue = this.draft[key];
    input.value = kept ? kept.text : input.seed;
    input.entry = words; input.profile = kept ? kept.profile : loads.profile(words);
    if (words.help) ui.tooltip(input, words.help);
    input.addEventListener("input", function () {
      if (input.value === input.seed) delete typed[key];
      else typed[key] = { text: input.value, profile: input.profile, seed: input.seed };
      self.clearStatus();
    });
    this.inputs[key] = input;
    return input;
  };

  /* A choice; a change lays the form out again, since it can show or hide fields or change a unit. */
  DeviceDialog.prototype.select = function (key, choices, integer) {
    var self = this, select = el("select");
    select.setAttribute("data-key", key);
    choices.forEach(function (choice) { select.appendChild(ui.option(String(choice[0]), choice[1])); });
    select.value = String(this.draft[key]);
    select.integer = Boolean(integer);
    select.addEventListener("change", function () {
      if (key === "type") { self.retype(select.value); return; }
      // The choice applies at once; a number that does not read yet keeps its text for the submit to name.
      self.read(false);
      self.layout();
    });
    this.inputs[key] = select;
    return select;
  };

  /* On Add, another type starts from its own values; a name the user typed stays. */
  DeviceDialog.prototype.retype = function (name) {
    var before = this.type(), typed = this.inputs.display_name.value.trim();
    var next = this.types.filter(function (entry) { return entry.type === name; })[0];
    this.draft = Object.assign({ type: name }, clone(next.defaults));
    this.typed = {};
    if (typed && typed !== before.defaults.display_name) this.draft.display_name = typed;
    this.clearStatus();
    this.layout();
  };

  DeviceDialog.prototype.clearStatus = function () {
    if (!this.busy()) this.error.textContent = "";
  };

  /* The form's values into the draft, or `{ error }` naming the first that does not read; with `strict` false, a
     number that does not read is left out of the draft. */
  DeviceDialog.prototype.read = function (strict) {
    var self = this, draft = this.draft, inputs = this.inputs, error = null;
    strict = strict !== false;
    Object.keys(inputs).forEach(function (key) {
      var input = inputs[key];
      if (key === "type" || error) return;
      if (input.type === "checkbox") { draft[key] = input.checked; return; }
      if (input.tagName.toUpperCase() === "SELECT") {
        draft[key] = input.integer ? Number(input.value) : input.value;
        return;
      }
      if (!input.entry) { draft[key] = input.value.trim(); return; }
      // Text back at its seed is the value the field was drawn from, whatever an earlier read made of it.
      if (input.value === input.seed) { draft[key] = input.seedValue; return; }
      var parsed = loads.parse(input.entry, input.value, input.profile), problem = null;
      if (parsed.error) problem = parsed.error;
      else if (parsed.value === null) problem = input.entry.label + " needs a value.";
      else if (input.entry.whole && (Math.round(parsed.value) !== parsed.value || parsed.value < 1)) {
        problem = input.entry.label + " is a whole number of at least 1.";
      }
      // A value that reads goes into the draft, so a layout redraws it from there in the units shown then.
      if (!problem) { draft[key] = parsed.value; delete self.typed[key]; }
      else if (strict) error = problem;
    });
    if (!error && strict && !String(draft.display_name || "").trim()) error = "Enter a name.";
    return { error: error };
  };

  /* Add sends the device; Edit sends what changed, guarded by its values as the dialog opened. */
  DeviceDialog.prototype.submit = function () {
    var read = this.read();
    if (read.error) { this.error.textContent = read.error; return; }
    var draft = this.draft, values = {}, expected = {};
    if (this.adding) {
      Object.keys(draft).forEach(function (key) { if (key !== "type") values[key] = draft[key]; });
      this.sent(this.run({ id: this.set.id, type: draft.type, values: values }));
      return;
    }
    var opened = this.opened;
    Object.keys(draft).forEach(function (key) {
      if (["id", "type", "user_data"].indexOf(key) >= 0) return;
      if (JSON.stringify(draft[key]) === JSON.stringify(opened[key])) return;
      values[key] = draft[key];
      expected[key] = opened[key] === undefined ? null : opened[key];
    });
    if (!Object.keys(values).length) { this.hide(null); return; }
    this.sent(this.run({ id: this.set.id, device_id: opened.id, values: values, expected_values: expected }));
  };

  /* While the request is out the fields hold still, so what the dialog shows is what was sent; a refusal or failure
     gives them back, with the commit. */
  DeviceDialog.prototype.sent = function (running) {
    var inputs = this.inputs;
    Object.keys(inputs).forEach(function (key) { inputs[key].disabled = Boolean(running); });
  };

  /* Settles the request from the owner's render: a completed one closes the dialog; a refusal keeps the draft
     and says why in the status line. */
  DeviceDialog.prototype.refresh = function (state) {
    var outcome = this.settle(state);
    if (outcome && outcome.status === "completed") this.hide(outcome);
    else if (outcome) { this.sent(false); this.submitButton.disabled = false; }
  };

  DeviceDialog.prototype.open = function () {
    this.show();
    var first = this.inputs.type || this.inputs.display_name;
    if (first) first.focus({ preventScroll: true });
  };

  DeviceDialog.REFERENCE = REFERENCE;
  DeviceDialog.demand = demand;
  return DeviceDialog;
});
