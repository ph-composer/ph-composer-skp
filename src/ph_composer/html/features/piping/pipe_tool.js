/* The pipe tool's two controls in the assign bar, in the shape of an edge feature's tool controls. "Assign by
   clicking" arms the tool in SketchUp with the bar's type, role and values and stays pressed while the tool has the
   viewport, when a second click stops it; Stop shows only then. The tool's state comes from the `pipe_tool` snapshot
   section, so a tool ended in SketchUp (Escape, another tool) releases both. Each gesture is one pipes.assign. */
PhComposerUI.define("features/piping/pipe_tool", ["request", "snapshot", "workspace", "features/piping/shared"],
function (request, snapshot, ui, shared) {
  "use strict";
  function PipeToolControls(session, send, refused) {
    var self = this;
    this.refused = refused;
    this.channel = request.channel(session, send, "piping-pipe-tool", "view.invoke");
    this.arm = ui.button("");
    this.arm.className = "piping-tool-arm";
    this.arm.setAttribute("aria-label", "Assign by clicking lines");
    this.arm.appendChild(ui.glyph("paint_bucket"));
    this.arm.appendChild(ui.element("span", "piping-tool-label", "Assign by clicking"));
    this.stop = ui.button("Stop", function () { self.stopTool(); });
    this.stop.setAttribute("aria-label", "Stop assigning pipes by clicking");
    this.state = { active: false };
  }
  PipeToolControls.prototype.active = function () { return Boolean(this.state.active); };
  PipeToolControls.prototype.render = function (state) {
    var value = snapshot.value(state, shared.TOOL);
    this.enabled = Boolean(value);
    this.state = value || { active: false };
    var outcome = this.channel.consume(state);
    if (outcome && outcome.status !== "completed") this.refused(outcome.message || "The pipe tool did not start.");
  };
  /* Arms the tool, or re-arms a running one for its next gesture. `params` are pipe_type_id, role and its values. */
  PipeToolControls.prototype.choose = function (params) {
    if (this.disposed || !this.enabled || this.channel.busy()) return false;
    return this.channel.run(shared.TOOL + ".choose", params);
  };
  PipeToolControls.prototype.stopTool = function () {
    if (this.disposed || !this.active() || this.channel.busy()) return false;
    return this.channel.run(shared.TOOL + ".stop", {});
  };
  /* `blocked` is why the bar cannot arm the tool, or null; `what` names what it assigns. */
  PipeToolControls.prototype.paint = function (blocked, what) {
    var busy = this.channel.busy(), active = this.active();
    this.arm.disabled = !this.enabled || busy || !active && Boolean(blocked);
    this.arm.setAttribute("aria-pressed", String(active));
    ui.tooltip(this.arm, active ? "Assigning " + what + " by clicking in SketchUp. Click again, or press Escape " +
      "there, to stop" : blocked || "Click or drag across lines in a Piping group to assign " + what +
      ", one Undo step a gesture");
    this.stop.hidden = !active;
    this.stop.disabled = busy;
  };
  PipeToolControls.prototype.busy = function () { return this.channel.busy(); };
  PipeToolControls.prototype.dispose = function () { this.disposed = true; this.channel.reset(); };
  return { PipeToolControls: PipeToolControls };
});
