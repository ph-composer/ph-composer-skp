/* View commands own the viewport tool. Choosing an anchor never writes a Window record. */
PhComposerUI.define("features/windows/placement", ["request", "snapshot", "workspace"], function (request, snapshot,
  ui) {
  "use strict";
  // The nine anchors as they sit on a window: the head row first, the sill row last.
  var PREFIX = "ph_composer.windows.", ANCHORS = ["head_left", "head_center", "head_right", "center_left",
    "center", "center_right", "sill_left", "sill_center", "sill_right"];
  /* `root` is the row an active Place tool needs: what is being placed, how it measures, and Stop. `anchorRoot`
     is the tool's one setting, an icon beside Place that opens the nine anchors. */
  function Controls(owner) {
    var self = this; this.owner = owner; this.anchorValue = owner.page.anchor || "sill_center";
    this.channel = request.channel(owner.session, owner.send, "window-placement", "view.invoke");
    this.root = ui.element("div", "window-placement");
    this.chosen = ui.element("span", "window-placement-chosen"); this.root.appendChild(this.chosen);
    this.anchorButton = ui.iconButton("Placement anchor", "anchor");
    this.anchorBubble = new ui.Bubble(this.anchorButton, "Placement anchor");
    this.anchorRoot = this.anchorBubble.root;
    var grid = ui.element("div", "window-anchor-grid"); this.anchorBubble.content.appendChild(grid);
    this.anchors = {};
    ANCHORS.forEach(function (id) {
      var choice = ui.button(ui.titleCase(id), function () { self.setAnchor(id); });
      choice.className = "phc-setting-choice"; self.anchors[id] = choice; grid.appendChild(choice);
    });
    this.hint = ui.element("div", "window-placement-hint");
    this.hint.appendChild(ui.element("span", "window-placement-hint-label", "Type in SketchUp's Measurements box"));
    [["sill=", "opening bottom above the host base"], ["offset=", "anchor inset from the nearest edge"]]
      .forEach(function (entry) {
        var line = ui.element("span", "window-placement-measure");
        line.appendChild(ui.element("code", "", entry[0])); line.appendChild(ui.element("span", "", entry[1]));
        self.hint.appendChild(line);
      });
    this.root.appendChild(this.hint);
    this.stop = ui.button("Stop placing", function () { self.run("place_tool.stop", {}); });
    this.root.appendChild(this.stop);
  }
  // A new anchor re-arms a tool that is already placing, so the next click uses it.
  Controls.prototype.setAnchor = function (id) {
    if (this.disposed || !this.enabled) return;
    this.anchorBubble.close(true);
    if (this.owner.guard()) { this.owner.notice.show(this.owner.guard()); return; }
    this.anchorValue = id; this.owner.page.anchor = id;
    if (this.tool.active) this.choose(this.tool.type_id); else this.paint();
  };
  Controls.prototype.available = function (typeId) {
    var raw = this.owner.rawRecord(typeId);
    return Boolean(raw && [raw.values.rows_m, raw.values.columns_m].every(function (bands) {
      return bands.length > 0 && bands.every(function (value) {
        return typeof value === "number" && isFinite(value) && value > 0;
      });
    }));
  };
  Controls.prototype.choose = function (typeId) {
    if (this.owner.guard()) { this.owner.notice.show(this.owner.guard()); return false; }
    if (!this.available(typeId)) { this.owner.notice.show("Enter every row height and column width before placing.");
      return false; }
    return this.run("place_tool.choose", { type_id: typeId, anchor: this.anchorValue });
  };
  Controls.prototype.run = function (name, params) {
    if (this.disposed || !this.enabled || name === "place_tool.stop" && !this.tool.active) return false;
    var result = this.channel.run(PREFIX + name, params);
    this.paint(); return result;
  };
  Controls.prototype.render = function (state) {
    this.state = state; this.tool = snapshot.value(state, PREFIX + "place_tool") || {};
    this.enabled = Boolean(snapshot.value(state, PREFIX + "place_tool"));
    if (!this.enabled) this.channel.reset();
    this.channel.consume(state);
    if (this.tool.active) { this.anchorValue = this.tool.anchor; this.owner.page.anchor = this.anchorValue; }
    this.paint();
  };
  Controls.prototype.paint = function () {
    var tool = this.tool || {}, raw = this.owner.rawRecord(tool.type_id || this.owner.active);
    var self = this, label = "Placement anchor: " + ui.titleCase(this.anchorValue);
    this.root.hidden = !this.enabled || !tool.active;
    this.chosen.textContent = tool.active ? "Placing " + (raw ? raw.values.name : "Window Type") : "";
    this.stop.disabled = this.channel.busy();
    this.anchorButton.setAttribute("aria-label", label); ui.tooltip(this.anchorButton, label);
    this.anchorButton.disabled = !this.enabled || this.channel.busy();
    Object.keys(this.anchors).forEach(function (id) {
      self.anchors[id].setAttribute("aria-pressed", String(id === self.anchorValue));
    });
    if (this.owner.placeButton) {
      this.owner.placeButton.disabled = !this.enabled || this.channel.busy() || !this.available(this.owner.active);
      ui.tooltip(this.owner.placeButton, this.available(this.owner.active) ? "Place this Window Type in SketchUp" :
        "Enter every row height and column width before placing.");
      this.owner.placeButton.setAttribute("aria-pressed", String(Boolean(tool.active &&
        tool.type_id === this.owner.active)));
    }
  };
  Controls.prototype.guard = function () { return this.channel.busy() ? "Wait for the placement command." : null; };
  Controls.prototype.dispose = function () { this.disposed = true; this.enabled = false; this.channel.reset(); };
  return { Controls: Controls };
});
