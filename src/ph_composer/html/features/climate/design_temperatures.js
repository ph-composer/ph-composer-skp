/* The Design temperatures pane: the two ASHRAE dry bulbs and the source note, typed in place. Each field saves
   when it is committed (Enter or leaving it) as its own `design_temperatures.update`, one Undo step, guarded by
   the value the field showed when typing began, so a change made elsewhere meanwhile refuses rather than being
   overwritten; clearing a field unsets it. The panel stamps each write with the revision
   it rendered, so the writes go one at a time: a commit made while another is out waits for it and is then
   sent against the new revision, never refused as stale and never dropped. The fields are built once and
   repainted in place, so a repaint never sends or drops a half-typed draft. */
PhComposerUI.define("features/climate/design_temperatures", ["workspace", "request", "unit_field",
  "features/climate/shared"],
function (ui, requests, unitField, shared) {
  "use strict";
  var UPDATE = shared.PREFIX + "design_temperatures.update";
  var SOURCE = "design_temperature_source";
  var INTRO = "The ASHRAE design dry-bulb temperatures for the site. A Phius station file carries neither. Take " +
    "them from the ASHRAE Handbook of Fundamentals climatic design conditions for the nearest station.";
  var USE = "They stay in this Model. The Mechanical tab will use them for the blended heat pump. Export does " +
    "not wait on them. Clear a field to unset it.";
  var STATES = { not_set: "Not set", incomplete: "Incomplete: one of the two is typed.", set: "Set" };
  var CROSSED = "The heating temperature is at or above the cooling temperature. Both are saved; check them.";

  function Pane(session, send) {
    var self = this;
    this.channel = requests.channel(session, send, "climate_design");
    this.waiting = []; this.sending = null; this.values = null;
    // Each field's value when the user began typing in it: the guard its write is sent with.
    this.started = {};
    this.root = ui.element("section", "climate-pane climate-design");
    this.root.appendChild(ui.element("h2", "", "Design temperatures"));
    this.root.appendChild(ui.element("p", "climate-pane-intro", INTRO));
    var grid = ui.element("div", "climate-design-fields");
    this.heating = this.temperature(grid, "heating_99_c", "99% heating dry bulb");
    this.cooling = this.temperature(grid, "cooling_1_c", "1% cooling dry bulb");
    this.source = ui.element("input"); this.source.type = "text"; this.source.setAttribute("autocomplete", "off");
    this.source.setAttribute("aria-label", "Source (optional)");
    this.source.addEventListener("keydown", function (event) {
      if (event.key === "Enter") { event.preventDefault(); self.commitSource(); }
      if (event.key === "Escape" && self.sourceEditing) {
        event.preventDefault(); self.sourceEditing = false; delete self.started[SOURCE]; self.paintSource();
      }
    });
    this.source.addEventListener("input", function () { self.begin(SOURCE); self.sourceEditing = true; });
    // A blur caused by the page moving the input is not the user leaving it.
    this.source.addEventListener("blur", function () { if (self.source.isConnected) self.commitSource(); });
    var note = ui.element("label", "climate-field climate-field-wide");
    note.appendChild(ui.element("span", "climate-field-label", "Source (optional)"));
    note.appendChild(this.source);
    grid.appendChild(note);
    this.root.appendChild(grid);
    this.status = ui.element("p", "climate-design-state"); this.status.setAttribute("role", "status");
    this.warning = ui.element("p", "climate-design-warning"); this.warning.setAttribute("role", "alert");
    this.root.appendChild(this.status); this.root.appendChild(this.warning);
    this.root.appendChild(ui.element("p", "climate-pane-use", USE));
  }

  Pane.prototype.temperature = function (grid, key, title) {
    var self = this, label = ui.element("label", "climate-field");
    var field = new unitField.UnitField({ field: Object.assign({}, shared.TEMPERATURE, { label: title }),
      commitOnBlur: true, onCommit: function (value) { self.commit(key, value); },
      onCancel: function () { delete self.started[key]; } });
    field.input.addEventListener("input", function () { self.begin(key); });
    field.input.addEventListener("paste", function () { self.begin(key); });
    // An edit that ended with nothing to send (the same value, retyped) lets go of its guard, so the next edit
    // is guarded by what the field shows then. These run after the field's own Enter and blur handling.
    function settled() { if (!field.editing) delete self.started[key]; }
    field.input.addEventListener("keydown", function (event) { if (event.key === "Enter") settled(); });
    field.input.addEventListener("blur", settled);
    label.appendChild(ui.element("span", "climate-field-label", title));
    label.appendChild(field.root);
    grid.appendChild(label);
    return field;
  };

  Pane.prototype.begin = function (key) {
    if (this.values && !Object.prototype.hasOwnProperty.call(this.started, key)) this.started[key] = this.values[key];
  };
  /* A committed field waits its turn; a second commit of the same field replaces the one still waiting. */
  Pane.prototype.commit = function (key, value) {
    if (!this.values) return;
    var expected = Object.prototype.hasOwnProperty.call(this.started, key) ? this.started[key] : this.values[key];
    delete this.started[key];
    this.waiting = this.waiting.filter(function (item) { return item.key !== key; });
    this.waiting.push({ key: key, value: value, expected: expected });
    this.next();
    this.paintBusy();
  };
  /* Sends the first write waiting, guarded by the value its field showed when typing began. */
  Pane.prototype.next = function () {
    if (this.channel.busy() || !this.waiting.length || !this.values) return;
    var item = this.waiting.shift(), values = {}, expected = {};
    values[item.key] = item.value; expected[item.key] = item.expected;
    this.sending = item.key;
    this.channel.run(UPDATE, { values: values, expected_values: expected });
  };
  Pane.prototype.pending = function (key) {
    return this.sending === key || this.waiting.some(function (item) { return item.key === key; });
  };
  Pane.prototype.commitSource = function () {
    if (!this.sourceEditing) return;
    this.sourceEditing = false;
    var text = this.source.value.trim();
    var value = text === "" ? null : text;
    if (value === (this.values && this.values[SOURCE])) { delete this.started[SOURCE]; return; }
    this.commit(SOURCE, value);
  };
  Pane.prototype.paintSource = function () {
    if (this.sourceEditing || this.pending(SOURCE)) return;
    this.source.value = (this.values && this.values[SOURCE]) || "";
  };
  /* A field is read only while its own write is waiting or out, and keeps the focus Enter left it with; once the
     write settles, accepted or refused, the field shows the Model's value. */
  Pane.prototype.paintBusy = function () {
    var self = this;
    [["heating_99_c", this.heating], ["cooling_1_c", this.cooling]].forEach(function (pair) {
      var held = self.pending(pair[0]);
      pair[1].setDisabled(!self.values);
      pair[1].input.readOnly = held;
      if (self.values && !pair[1].editing && !held) pair[1].setValue(self.values[pair[0]]);
    });
    this.source.disabled = !this.values;
    this.source.readOnly = this.pending(SOURCE);
    this.paintSource();
  };

  /* `values` is the design-temperature read the snapshot carries. */
  Pane.prototype.render = function (state, values) {
    this.values = values;
    if (this.channel.consume(state)) this.sending = null;
    this.next();
    this.paintBusy();
    this.status.textContent = values ? "State: " + STATES[values.state] : "";
    this.warning.hidden = !(values && values.warning);
    this.warning.textContent = values && values.warning ? CROSSED : "";
  };

  Pane.prototype.dispose = function () {
    this.channel.reset(); this.waiting = []; this.sending = null; this.started = {};
    this.heating.dispose(); this.cooling.dispose();
  };

  return Pane;
});
