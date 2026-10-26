/* The edge tool's two controls in the assign bar. "Assign by clicking" arms the tool in SketchUp with the bar's
   type and quantity and stays pressed while the tool has the viewport, when a second click stops it; Stop shows
   only then. The tool's state comes from the `edge_tool` snapshot section, so a tool ended in SketchUp (Escape,
   another tool) releases both. The panel sends only the two view commands; each gesture the tool completes is
   one edges.assign. */
PhComposerUI.define("features/thermal_bridges/edge_tool", ["request", "snapshot", "workspace",
  "features/thermal_bridges/shared"], function (request, snapshot, ui, shared) {
  "use strict";
  var SECTION = shared.PREFIX + "edge_tool";

  /* `refused(message)` shows a command the host refused. */
  function EdgeToolControls(session, send, refused) {
    var self = this;
    this.refused = refused;
    this.channel = request.channel(session, send, "thermal-bridge-edge-tool", "view.invoke");
    this.arm = ui.button("Assign by clicking");
    this.arm.className = "tb-edge-tool-arm";
    this.stop = ui.button("Stop", function () { self.stopTool(); });
    this.stop.setAttribute("aria-label", "Stop assigning by clicking");
    this.state = { active: false };
  }
  /* Whether the tool has the viewport, as the last snapshot said. */
  EdgeToolControls.prototype.active = function () { return Boolean(this.state.active); };
  EdgeToolControls.prototype.render = function (state) {
    var value = snapshot.value(state, SECTION);
    this.enabled = Boolean(value);
    this.state = value || { active: false };
    var outcome = this.channel.consume(state);
    if (outcome && outcome.status !== "completed") {
      this.refused(outcome.message || "The edge tool did not start.");
    }
  };
  /* Arms the tool, or re-arms a running one for its next gesture. */
  EdgeToolControls.prototype.choose = function (typeId, quantity) {
    if (this.disposed || !this.enabled || this.channel.busy()) return false;
    return this.channel.run(SECTION + ".choose", { thermal_bridge_type_id: typeId, quantity: quantity });
  };
  EdgeToolControls.prototype.stopTool = function () {
    if (this.disposed || !this.active() || this.channel.busy()) return false;
    return this.channel.run(SECTION + ".stop", {});
  };
  /* `blocked` is why the bar's type and quantity cannot arm the tool, or null; `name` the chosen type's name. */
  EdgeToolControls.prototype.paint = function (blocked, name) {
    var busy = this.channel.busy(), active = this.active();
    this.arm.disabled = !this.enabled || busy || !active && Boolean(blocked);
    this.arm.setAttribute("aria-pressed", String(active));
    ui.tooltip(this.arm, active ? "Assigning " + (name || "the type") + " by clicking in SketchUp. Click again, " +
      "or press Escape there, to stop" : blocked || "Click or drag across Edges in SketchUp to assign " +
      (name || "the type") + ", one Undo step a gesture");
    this.stop.hidden = !active;
    this.stop.disabled = busy;
  };
  EdgeToolControls.prototype.busy = function () { return this.channel.busy(); };
  EdgeToolControls.prototype.dispose = function () { this.disposed = true; this.channel.reset(); };
  return { EdgeToolControls: EdgeToolControls, SECTION: SECTION };
});
