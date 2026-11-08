/* Peer work surfaces share one navigation control. The owning page supplies its session-scoped state;
   rebuilding the view preserves that state's selected surface without touching Model data.
   new Subtabs({ label, state, stateKey, tabs: [{ id, label, surface }], guard, refused, changed, reselected })
   guard(nextId) returns a refusal message while a draft or operation must remain visible; refused(reason, nextId)
   then runs. reselected(id) runs when the shown tab is chosen again, for an owner whose surface is covered. */
PhComposerUI.define("subtabs", ["dom", "icons"], function (ui, icons) {
  "use strict";
  var sequence = 0;
  var OVERFLOW_INSET = 32; // The narrow strip's 24 px cue and 8 px gutter.

  function Subtabs(options) {
    if (!options.label || !options.tabs.length) throw new Error("Subtabs require a label and work surfaces.");
    this.options = options;
    this.state = options.state;
    this.stateKey = options.stateKey;
    if (!this.state || !this.stateKey) throw new Error("Subtabs require session-owned page state and a stateKey.");
    this.tabs = options.tabs.slice();
    this.buttons = Object.create(null);
    this.disposed = false;
    this.root = ui.element("nav", "phc-subtabs");
    this.root.setAttribute("role", "tablist");
    this.root.setAttribute("aria-label", options.label);
    var self = this;
    var prefix = "phc-subtabs-" + (++sequence);
    this.tabs.forEach(function (tab, index) {
      if (!tab.id || self.buttons[tab.id]) throw new Error("Subtab ids must be present and unique.");
      var button = ui.button(tab.label, function () { self.select(tab.id); });
      button.setAttribute("id", prefix + "-tab-" + index);
      button.setAttribute("role", "tab");
      if (!tab.surface.id) tab.surface.setAttribute("id", prefix + "-surface-" + index);
      button.setAttribute("aria-controls", tab.surface.id);
      tab.surface.setAttribute("role", "tabpanel");
      tab.surface.setAttribute("aria-labelledby", button.id);
      button.addEventListener("mousedown", function (event) {
        // Preserve input focus before a pointer click can blur and hide its work surface.
        if (tab.id !== self.active && self.focusedInput()) event.preventDefault();
      });
      button.addEventListener("keydown", function (event) { self.keydown(event, index); });
      self.buttons[tab.id] = button;
      self.root.appendChild(button);
    });
    this.active = this.buttons[this.state[this.stateKey]] ? this.state[this.stateKey] : this.tabs[0].id;
    this.overflow = ui.element("span", "phc-subtabs-overflow");
    this.overflow.setAttribute("aria-hidden", "true");
    this.overflow.appendChild(icons.glyph("chevron"));
    this.root.appendChild(this.overflow);
    this.onScroll = function () { self.updateOverflow(); };
    this.root.addEventListener("scroll", this.onScroll);
    if (window.ResizeObserver) {
      this.resize = new window.ResizeObserver(function () { self.reveal(); });
      this.resize.observe(this.root);
    }
    this.paint();
  }

  Subtabs.prototype.updateOverflow = function () {
    if (this.disposed || !this.root.clientWidth) return;
    var first = this.buttons[this.tabs[0].id].getBoundingClientRect();
    var last = this.buttons[this.tabs[this.tabs.length - 1].id].getBoundingClientRect();
    var padding = parseFloat(window.getComputedStyle(this.root).paddingLeft) || 0;
    this.root.classList.toggle("has-overflow", last.right - first.left > this.root.clientWidth - 2 * padding);
    var atEnd = last.right <= this.root.getBoundingClientRect().right - OVERFLOW_INSET + 1;
    this.overflow.classList.toggle("is-at-end", atEnd);
  };

  // Selection and resize keep the active label clear of the cue. A manual pan remains the user's view.
  Subtabs.prototype.reveal = function () {
    if (this.disposed || !this.root.clientWidth) return;
    // Mount the cue before scrolling, so a newly narrow strip includes its trailing space in the range.
    this.updateOverflow();
    if (this.root.scrollWidth > this.root.clientWidth) {
      var frame = this.root.getBoundingClientRect(), box = this.buttons[this.active].getBoundingClientRect();
      if (box.right > frame.right - OVERFLOW_INSET) this.root.scrollLeft += box.right - frame.right + OVERFLOW_INSET;
      else if (box.left < frame.left + 8) this.root.scrollLeft -= frame.left + 8 - box.left;
    }
    this.updateOverflow();
  };

  /* A field that a blur would commit or lose, inside the shown surface. A search field, checkbox or radio holds
     no draft: its value already applies, so it never holds a switch. */
  Subtabs.prototype.focusedInput = function () {
    var focused = document.activeElement;
    var active = this.tabs.filter(function (tab) { return tab.id === this.active; }, this)[0];
    if (!focused || !active || !active.surface.contains(focused)) return false;
    if (/^input$/i.test(focused.tagName) && /^(search|checkbox|radio)$/i.test(focused.type || "")) return false;
    // A read-only field (a setup to copy) holds no edit, so focus in it never holds the tab.
    if (focused.readOnly) return false;
    return /^(input|select|textarea)$/i.test(focused.tagName) || Boolean(focused.isContentEditable);
  };
  Subtabs.prototype.select = function (id) {
    if (this.disposed || !this.buttons[id]) return false;
    if (id === this.active) {
      if (this.options.reselected) this.options.reselected(id);
      this.reveal();
      return true;
    }
    var reason = this.options.guard && this.options.guard(id);
    if (!reason && this.focusedInput()) reason = "Finish editing the focused field before changing sections.";
    if (reason) {
      if (this.options.refused) this.options.refused(reason, id);
      return false;
    }
    this.active = id;
    this.paint();
    if (this.options.changed) this.options.changed(id);
    this.reveal();
    return true;
  };
  Subtabs.prototype.paint = function () {
    var self = this;
    this.state[this.stateKey] = this.active;
    this.tabs.forEach(function (tab) {
      var active = tab.id === self.active;
      tab.surface.hidden = !active;
      self.buttons[tab.id].setAttribute("aria-selected", String(active));
      self.buttons[tab.id].setAttribute("aria-pressed", String(active));
      self.buttons[tab.id].tabIndex = active ? 0 : -1;
    });
  };
  Subtabs.prototype.keydown = function (event, index) {
    var target;
    if (event.key === "ArrowRight") target = (index + 1) % this.tabs.length;
    else if (event.key === "ArrowLeft") target = (index + this.tabs.length - 1) % this.tabs.length;
    else if (event.key === "Home") target = 0;
    else if (event.key === "End") target = this.tabs.length - 1;
    else return;
    event.preventDefault();
    var id = this.tabs[target].id;
    if (this.select(id)) {
      var button = this.buttons[id];
      button.focus({ preventScroll: true });
    }
  };
  Subtabs.prototype.dispose = function () {
    this.disposed = true;
    this.root.removeEventListener("scroll", this.onScroll);
    if (this.resize) this.resize.disconnect();
  };
  return Subtabs;
});
