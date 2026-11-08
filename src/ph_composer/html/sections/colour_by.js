/* The panel's Colour by, as parts a pane places:
 *
 * - `HeaderToggle(binding)`, a column header's toggle for the mode that colours by what the column shows. A
 *   binding names one mode (`{ mode }`) or a group of modes (`{ group }`), which a mode declares when it
 *   registers. One mode is on at a time: pressing an unpressed toggle turns its mode on and releases any
 *   other, and pressing the pressed one turns Colour by Off. A group with several modes opens a menu of them.
 * - `HeaderToggles(bindings)`, one toggle per bound column for a table: `actions(state, field)` answers the
 *   column's `headerActions` entries.
 * - `modes(state)` and `activate(state, name)`, so a screen can offer a mode no column binds (an options
 *   menu) through the same command.
 * - `readouts(state)` and `showReadout(state, name, on)`, so a screen can offer the readouts its feature
 *   registers, each on or off with any mode or none.
 *
 * Nothing here names a mode, a face type or a Zone. The modes, rows, labels, colours and counts all come from
 * the shared service's legend, so a feature that registers a mode reaches the panel without a line added here.
 * Every control sends a view command: none writes to the Model, so none leaves an Undo entry. Hover-to-
 * highlight is not built: it would send one command per pointer move, and its cost has to be measured first.
 */
PhComposerUI.define("sections/colour_by", ["panel", "workspace", "request", "snapshot"],
function (panel, ui, requests, snapshot) {
  "use strict";
  var screen = null;

  function forSession(session) {
    if (screen && screen.session === session) return screen;
    screen = { session: session, view: requests.channel(session, panel.send, "colour_by", "view.invoke"),
      filter: requests.channel(session, panel.send, "colour_by_filter", "view.invoke") };
    return screen;
  }

  function legendOf(state) {
    return snapshot.value(state, "ph_composer.colour_by.legend") || { mode: null, modes: [], rows: [] };
  }

  function modes(state) { return legendOf(state).modes; }

  /* Turns `name` on, or Colour by off with null. Answers false while another request is in flight. */
  function activate(state, name) {
    var owner = forSession(state.session);
    owner.view.consume(state);
    return owner.view.run("ph_composer.colour_by.activate", { mode: name || null });
  }

  /* Every registered readout, `{ name, label, selection, on }`, as the legend lists them. */
  function readouts(state) { return legendOf(state).readouts || []; }

  /* Shows or hides one readout. Sent without waiting on another command: each names its own readout. */
  function showReadout(state, name, on) {
    forSession(state.session).view.send("ph_composer.colour_by.readout", { readout: name, on: Boolean(on) });
  }

  function HeaderToggle(binding) {
    this.binding = binding;
    this.node = ui.element("span", "phc-colour-toggle");
    this.signature = null;
    this.pressed = false;
  }

  HeaderToggle.prototype.matching = function (legend) {
    var binding = this.binding;
    return legend.modes.filter(function (mode) {
      return binding.mode ? mode.name === binding.mode : Boolean(binding.group) && mode.group === binding.group;
    });
  };

  /* Built when the modes it stands for change, and repainted in place otherwise, so a press keeps its focus
     through the snapshot that follows. Answers whether the column has a mode to offer. */
  HeaderToggle.prototype.paint = function (state) {
    var self = this, legend = legendOf(state), found = this.matching(legend), owner = forSession(state.session);
    owner.view.consume(state);
    var signature = found.map(function (mode) { return mode.name + ":" + mode.label; }).join("|");
    if (signature !== this.signature) {
      this.signature = signature;
      this.button = ui.iconButton("", "palette", found.length === 1 ? function () { self.press(); } : null);
      if (found.length > 1) {
        this.menu = new ui.Bubble(this.button, "Colour by", { onOpen: function () { self.fill(); } });
        this.menu.panel.classList.add("phc-action-menu");
        this.menu.root.classList.add("phc-action-menu-anchor");
        this.node.replaceChildren(this.menu.root);
      } else {
        this.menu = null;
        this.node.replaceChildren(found.length ? this.button : ui.element("span"));
      }
    }
    this.modes = found;
    var active = found.filter(function (mode) { return mode.name === legend.mode; })[0];
    this.pressed = Boolean(active);
    if (found.length) {
      var named = active ? active.label : found.map(function (mode) { return mode.label; }).join(" or ");
      ui.paintIconButton(this.button, "Colour by " + named, "palette");
      this.button.setAttribute("aria-pressed", String(this.pressed));
      this.button.disabled = owner.view.busy();
    }
    return found.length > 0;
  };

  HeaderToggle.prototype.press = function () {
    activate(panel.state, this.pressed ? null : this.modes[0].name);
  };

  /* A group's menu: one item per mode, the one on marked, and Off while one is. */
  HeaderToggle.prototype.fill = function () {
    var self = this, current = legendOf(panel.state).mode;
    this.menu.content.replaceChildren();
    function item(text, name, pressed) {
      var node = ui.button(text, function () { self.menu.close(true); activate(panel.state, name); });
      // The mode on is marked the way every setting list marks its current choice.
      node.className = "phc-action-menu-item phc-setting-choice";
      if (pressed !== undefined) node.setAttribute("aria-pressed", String(pressed));
      self.menu.content.appendChild(node);
    }
    this.modes.forEach(function (mode) { item(mode.label, mode.name, mode.name === current); });
    if (this.pressed) item("Off", null);
  };

  /* A table's toggles, field to binding. Each is kept across repaints, so a press keeps its focus. */
  function HeaderToggles(bindings) {
    this.bindings = bindings;
    this.toggles = Object.create(null);
  }
  HeaderToggles.prototype.actions = function (state, field) {
    var binding = this.bindings[field];
    if (!binding) return [];
    var toggle = this.toggles[field] || (this.toggles[field] = new HeaderToggle(binding));
    return toggle.paint(state) ? [{ node: toggle.node, persistent: toggle.pressed }] : [];
  };

  /* The active mode's key, disclosed alongside a matching column's Show choices. */
  function colour(state, binding, value) {
    if (!binding) return null;
    var legend = legendOf(state), active = legend.modes.some(function (mode) {
      return mode.name === legend.mode && (binding.mode ? mode.name === binding.mode : mode.group === binding.group);
    });
    if (!active) return null;
    var rows = legend.rows.filter(function (entry) {
      return String(entry.value === null || entry.value === undefined ? "" : entry.value) === value;
    });
    // One value can have classified and incomplete rows. A single swatch must not imply one hue
    // when the viewport paints several; omit it until the value has a consistent colour.
    if (!rows.length || rows.some(function (row) {
      return JSON.stringify(row.colour) !== JSON.stringify(rows[0].colour);
    })) return null;
    return rows[0].colour;
  }

  /* A screen supplies matching occurrence paths, independent of the active colour mode. Coalesce rapid
     filter edits: settle the in-flight request, then send the latest scope. Never replay a refused scope
     on every repaint; a new scope can retry and the user receives the failure notice. */
  function filter(state, paths) {
    var owner = forSession(state.session);
    if (owner.appliedFilter === undefined) {
      owner.appliedFilter = legendOf(state).isolated ? "isolated" :
        JSON.stringify(legendOf(state).filter_paths || null);
    }
    owner.filter.consume(state);
    var signature = JSON.stringify(paths);
    if (owner.filter.busy() || owner.appliedFilter === signature) return;
    owner.filter.run("ph_composer.colour_by.filter", { paths: paths }, {
      onDone: function () { owner.appliedFilter = signature; },
      onFail: function (outcome) {
        owner.appliedFilter = signature;
        panel.notify(outcome.message || "The viewport filter could not be applied.", "warning");
      }
    });
  }

  return { HeaderToggle: HeaderToggle, HeaderToggles: HeaderToggles, modes: modes, activate: activate,
    colour: colour, filter: filter,
    readouts: readouts, showReadout: showReadout };
});
