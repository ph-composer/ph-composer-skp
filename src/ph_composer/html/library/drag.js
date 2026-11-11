/* The pointer drag from a sidebar row onto the placement's drop host. Every move resolves the target afresh. */
PhComposerUI.define("library/drag", ["workspace"], function (ui) {
  "use strict";
  var el = ui.element;

  function Drag(sidebar) {
    var self = this;
    this.sidebar = sidebar;
    this.entry = null;
    this.ghost = null;
    this.hint = null;
    this.hovered = null;
    this.x = 0;
    this.y = 0;
    this.move = function (event) { self.update(event); };
    this.up = function (event) {
      var entry = self.entry, found = self.ghost ? self.hitAt(event) : null;
      self.end();
      if (found) {
        sidebar.closeDetails();
    sidebar.use(entry.row, sidebar.adapter.dropSelection(found.hit));
        entry.button.focus({ preventScroll: true });
      }
    };
    this.key = function (event) {
      if (event.key !== "Escape" || !self.ghost) return;
      event.preventDefault(); event.stopImmediatePropagation(); self.end();
    };
    this.blur = function () { self.end(); };
  }
  Drag.prototype.active = function () { return this.sidebar.enabled && !this.sidebar.busy(); };
  Drag.prototype.start = function (entry, event) {
    entry.suppressClick = false;
    if (event.button !== 0 || !this.sidebar.adapter.dropSelector || !this.active() ||
      this.sidebar.copyLocked(entry.row)) return;
    this.end();
    this.entry = entry;
    this.x = event.clientX;
    this.y = event.clientY;
    document.addEventListener("mousemove", this.move);
    document.addEventListener("mouseup", this.up);
    document.addEventListener("keydown", this.key, true);
    window.addEventListener("blur", this.blur);
  };
  /* The hit target under the pointer inside the drop host, with the import params it stands for, or null. */
  Drag.prototype.hitAt = function (event) {
    var sidebar = this.sidebar, host = sidebar.dropHost;
    var node = document.elementFromPoint(event.clientX, event.clientY);
    var hit = node && node.closest(sidebar.adapter.dropSelector);
    if (!this.active() || !host || host.hidden || !hit || !host.contains(hit)) return null;
    var target = sidebar.adapter.target({ record: sidebar.context.record,
      selection: sidebar.adapter.dropSelection(hit) });
    return target.hint ? null : { hit: hit, params: target.params };
  };
  Drag.prototype.highlight = function (hit) {
    if (hit === this.hovered) return;
    if (this.hovered) this.hovered.classList.remove("is-drop-target");
    if (hit) hit.classList.add("is-drop-target");
    this.hovered = hit;
  };
  Drag.prototype.update = function (event) {
    var dx = event.clientX - this.x, dy = event.clientY - this.y, sidebar = this.sidebar;
    if (!this.ghost && dx * dx + dy * dy <= 36) return;
    if (!this.active()) { this.end(); return; }
    if (!this.ghost) {
      this.entry.suppressClick = true;
      this.ghost = el("div", "library-drag-ghost");
    sidebar.adapter.decorate(this.ghost, this.entry.row);
      var label = el("span", "library-drag-label", sidebar.adapter.name(this.entry.row));
      this.hint = el("small", "library-drag-hint"); label.appendChild(this.hint);
    this.ghost.appendChild(label);
      document.body.appendChild(this.ghost);
    this.entry.root.classList.add("is-dragging");
    document.body.classList.add("library-dragging", "is-dragging");
      ui.Bubble.closeActive();
      if (sidebar.onDragChange) sidebar.onDragChange(true);
    }
    event.preventDefault(); // no text selection starts under the ghost
    var found = this.hitAt(event);
    this.highlight(found ? found.hit : null);
    this.hint.textContent = found ? "Release to assign" : "";
    this.ghost.style.left = event.clientX + 12 + "px";
    this.ghost.style.top = event.clientY + 12 + "px";
  };
  Drag.prototype.end = function () {
    if (!this.entry) return;
    var entry = this.entry;
    var dragged = Boolean(this.ghost);
    // The browser emits the trailing pointer click in this task. Keyboard activation afterwards
    // must work even when an outside drop did not produce a click on the source button.
    if (dragged) window.setTimeout(function () { entry.suppressClick = false; }, 0);
    this.highlight(null);
    this.entry.root.classList.remove("is-dragging");
    document.body.classList.remove("library-dragging", "is-dragging");
    if (this.ghost) document.body.removeChild(this.ghost);
    document.removeEventListener("mousemove", this.move);
    document.removeEventListener("mouseup", this.up);
    document.removeEventListener("keydown", this.key, true);
    window.removeEventListener("blur", this.blur);
    this.entry = null;
    this.ghost = null;
    this.hint = null;
    if (dragged && this.sidebar.onDragChange) this.sidebar.onDragChange(false);
  };

  return Drag;
});
