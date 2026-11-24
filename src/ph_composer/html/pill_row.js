/* A row of pills beneath a page's subtabs that picks one table inside the shown subtab, one work surface at a
   time (Mechanical: Ventilation's Ventilators, later its Ducting). It works as Subtabs does: the owner supplies
   session-scoped state and a key, and the pill it names is shown.
   new PillRow({ label, state, stateKey, pills: [{ id, label, surface }], guard, refused, changed })
   guard(nextId) returns a refusal while a draft or a request must stay visible; refused(reason, nextId) then runs.
   Each pill is a setting choice, pressed while its table shows. Choosing one writes nothing to the Model. */
PhComposerUI.define("pill_row", ["dom"], function (ui) {
  "use strict";
  var sequence = 0;

  function PillRow(options) {
    if (!options.label || !options.pills.length) throw new Error("A pill row requires a label and work surfaces.");
    if (!options.state || !options.stateKey) throw new Error("A pill row requires session-owned state and a stateKey.");
    var self = this, prefix = "phc-pill-row-" + (++sequence);
    this.options = options;
    this.state = options.state;
    this.stateKey = options.stateKey;
    this.pills = options.pills.slice();
    this.buttons = Object.create(null);
    this.root = ui.element("div", "phc-pill-row");
    this.root.setAttribute("role", "group");
    this.root.setAttribute("aria-label", options.label);
    this.pills.forEach(function (pill, index) {
      if (!pill.id || self.buttons[pill.id]) throw new Error("Pill ids must be present and unique.");
      var button = ui.button(pill.label, function () { self.select(pill.id); });
      button.className = "phc-setting-choice phc-pill";
      button.setAttribute("id", prefix + "-pill-" + index);
      if (!pill.surface.id) pill.surface.setAttribute("id", prefix + "-surface-" + index);
      button.setAttribute("aria-controls", pill.surface.id);
      self.buttons[pill.id] = button;
      self.root.appendChild(button);
    });
    this.active = this.buttons[this.state[this.stateKey]] ? this.state[this.stateKey] : this.pills[0].id;
    this.paint();
  }
  PillRow.prototype.select = function (id) {
    if (!this.buttons[id]) return false;
    if (id === this.active) return true;
    var reason = this.options.guard && this.options.guard(id);
    if (reason) {
      if (this.options.refused) this.options.refused(reason, id);
      return false;
    }
    this.active = id;
    this.paint();
    if (this.options.changed) this.options.changed(id);
    return true;
  };
  PillRow.prototype.paint = function () {
    var self = this;
    this.state[this.stateKey] = this.active;
    this.pills.forEach(function (pill) {
      var active = pill.id === self.active;
      pill.surface.hidden = !active;
      self.buttons[pill.id].setAttribute("aria-pressed", String(active));
    });
  };
  return PillRow;
});
