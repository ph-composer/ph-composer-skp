/* The assign bar at the top of the Ducting pill, on the shared line-group bar (html/line_groups/assign_bar.js): a
   Duct Type, the direction as two setting choices (Outdoor air, Exhaust air) and a quantity, 1 by default, Assign
   and Clear. Assign always sends all three. */
PhComposerUI.define("features/ducting/assign_bar", ["workspace", "line_groups/assign_bar", "features/ducting/shared"],
function (ui, lineBars, shared) {
  "use strict";
  var Bar = lineBars.Bar;

  /* `newGroup()` opens New Ducting group; `notify(message, tone)` raises the panel's notice. */
  function AssignBar(session, send, guard, notify, newGroup) {
    var self = this;
    Bar.call(this, session, send, shared.SPEC, guard, notify, newGroup);
    this.direction = "outdoor_air";
    this.directions = ui.element("div", "ducting-directions");
    this.directions.setAttribute("role", "group");
    this.directions.setAttribute("aria-label", "Direction for selected lines");
    this.choices = shared.DIRECTIONS.map(function (entry) {
      var button = ui.button(entry.label, function () { self.direction = entry.value; self.paint(); });
      button.className = "phc-setting-choice";
      button.value = entry.value;
      self.directions.appendChild(button);
      return button;
    });
    this.quantity = ui.element("input", "line-group-number");
    this.quantity.setAttribute("inputmode", "numeric");
    this.quantity.setAttribute("aria-label", "Quantity");
    ui.tooltip(this.quantity, "How many identical ducts each line stands for");
    this.quantity.value = "1";
    this.quantity.addEventListener("input", function () { self.paint(); });
    this.quantity.addEventListener("keydown", function (event) {
      if (event.key !== "Enter") return;
      event.preventDefault();
      self.submit("assign");
    });
    this.place([this.directions, lineBars.labelled("Quantity", this.quantity)], []);
  }
  AssignBar.prototype = Object.create(Bar.prototype);
  AssignBar.prototype.constructor = AssignBar;
  AssignBar.prototype.problem = function () {
    var text = this.quantity.value.trim();
    return /^\d+$/.test(text) && Number(text) >= 1 && Number(text) <= 10000 ? null :
      "Enter a whole quantity from 1 to 10,000.";
  };
  /* Why Assign cannot run now, or null. */
  AssignBar.prototype.blocked = function () {
    return this.selectionBlocked() || this.typeBlocked() || this.problem();
  };
  AssignBar.prototype.params = function () {
    return { duct_type_id: this.type.value, direction: this.direction, quantity: Number(this.quantity.value.trim()) };
  };
  AssignBar.prototype.done = function (params, type, lines) {
    return "Assigned " + type + " as " + shared.directionLabel(params.direction).toLowerCase() + " to " + lines + ".";
  };
  /* `types` are the Model's Duct Type rows. A new selection whose lines share a type, direction or quantity starts
     from it; otherwise the user's choice stands. */
  AssignBar.prototype.render = function (state, types) {
    if (this.disposed) return;
    this.read(state, types);
    var key = this.selectionKey();
    if (key !== this.key) {
      this.key = key;
      var type = this.common("duct_type_id"), direction = this.common("direction"), quantity = this.common("quantity");
      if (type !== undefined) this.chosen = type;
      if (direction === "outdoor_air" || direction === "exhaust_air") this.direction = direction;
      if (quantity !== undefined && document.activeElement !== this.quantity) this.quantity.value = String(quantity);
    }
    this.paintTypes();
    this.paint();
  };
  AssignBar.prototype.paint = function () {
    var self = this, busy = this.requests.busy();
    this.paintBase(busy);
    this.choices.forEach(function (button) {
      button.setAttribute("aria-pressed", String(button.value === self.direction));
      button.disabled = busy;
    });
    this.quantity.disabled = busy;
    this.quantity.setAttribute("aria-invalid", String(Boolean(this.problem())));
  };
  return { AssignBar: AssignBar };
});
