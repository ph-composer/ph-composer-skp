/* Window definitions use the public record/grid actions. Selection, viewing and order are panel state. */
PhComposerUI.define("features/windows/editor", ["panel", "request", "snapshot", "subtabs", "unit_field", "units",
  "features/windows/audit", "features/windows/canvas", "features/windows/cards", "features/windows/editor_shared",
  "features/windows/install_editor", "features/windows/type_list", "library/sidebar", "features/windows/library",
  "features/windows/placement", "features/windows/schedule", "fields", "workspace"], function (panel, request,
  snapshot, Subtabs, unitFields, units, audit, Canvas, cards, shared, InstallEditor, typeList, Sidebar, library,
  Placement, Schedule, fields, ui) {
  "use strict";
  var el = ui.element, clone = shared.clone, WINDOW_DIMENSION = shared.WINDOW_DIMENSION,
    VIEW_SIDES = shared.VIEW_SIDES;
  function View(root, session, send, page) {
    var self = this; this.root = root; this.session = session; this.send = send; this.page = page || {};
    this.requests = request.channel(session, send, "window-builder"); this.selected = [];
    this.zoom = this.page.zoom || 1; this.interior = Boolean(this.page.interior);
    this.cards = {}; this.order = this.page.order || []; this.groups = this.page.groups || {};
    this.groupNames = this.page.groupNames || [""]; this.manual = Boolean(this.page.manual);
    this.active = this.page.active; this.collapsed = this.page.collapsed; this.entries = [];
    root.replaceChildren(); root.classList.add("window-workspace");
    // The panel owns the one floating notice; a refused or failed request is already shown there by the panel.
    this.notice = { show: function (text, options) { panel.notify(text, options && options.tone); },
      clear: function () { panel.notify(""); } };
    this.layout = el("div", "window-layout"); this.audit = el("div", "window-audit");
    this.scheduleSurface = el("div");
    this.tabs = new Subtabs({ label: "Window Types sections", state: this.page, stateKey: "surface",
      tabs: [{ id: "builder", label: "Types", surface: this.layout },
        { id: "audit", label: "U-Values", surface: this.audit },
        { id: "schedule", label: "Schedule", surface: this.scheduleSurface }], guard: function () {
          return self.guard(); },
      refused: function (reason, id) {
        if (self.installEditor.root.hidden) self.notice.show(reason); else self.leaveInstalls(id);
      }, reselected: function (id) { if (!self.installEditor.root.hidden) self.leaveInstalls(id); },
      changed: function () { self.paint(); } });
    // One page header over the peer sub-tabs, as every tab opens.
    this.header = ui.pageHeader({ title: "Window Types" });
    root.appendChild(this.header.root);
    root.appendChild(this.tabs.root); root.appendChild(this.layout); root.appendChild(this.audit);
    root.appendChild(this.scheduleSurface);
    this.installEditor = new InstallEditor(session, send, function (message) {
      self.layout.hidden = self.tabs.active !== "builder"; self.notice.show(message); self.paint();
      self.installButton.focus();
    }); root.appendChild(this.installEditor.root);
    this.buildRail(); this.buildHeading(); this.buildWorkspace(); this.buildSidebar(); this.buildKeyboard();
    this.placement = new Placement.Controls(this); root.insertBefore(this.placement.root, this.layout);
    this.typeTools.insertBefore(this.placement.anchorRoot, this.readinessButton);
    this.schedule = new Schedule.Schedule(this); this.scheduleSurface.appendChild(this.schedule.root);
  }
  View.prototype.rawRecord = function (id) {
    return shared.records(this.state, "types").filter(function (row) { return row.id === (id || this.active); },
      this)[0];
  };
  View.prototype.authored = function (record) {
    var raw = this.rawRecord(record.id);
    // A baseline from an open editor remains detached even after another snapshot arrives.
    return clone(record._authored || raw.values);
  };
  View.prototype.record = function () {
    var entry = this.entries.filter(function (row) { return row.record.id === this.active; }, this)[0];
    return entry && entry.record;
  };
  View.prototype.product = function (kind, id) {
    var row = shared.records(this.state, kind).filter(function (record) { return record.id === id; })[0];
    return row && shared.flat(row);
  };
  View.prototype.length = function (value) { return shared.format(value, WINDOW_DIMENSION); };
  View.prototype.guard = function () {
    if (this.disposed) return null;
    if (this.requests.busy()) return "Wait for the Window Type edit.";
    if (this.dimensionField && this.dimensionField.editing) return "Apply or cancel the dimension draft.";
    if (this.renameDraft) return "Finish or cancel the name edit.";
    if (this.formDraft && this.formDraft.dirty()) return "Apply or cancel the name draft.";
    if (this.placement && this.placement.guard()) return this.placement.guard();
    if (this.schedule && this.schedule.guard()) return this.schedule.guard();
    var review = this.sidebars && Object.keys(this.sidebars).map(function (kind) {
      return this.sidebars[kind].guard();
    }, this).filter(Boolean)[0];
    if (review) return review;
    return this.installEditor.guard();
  };
  // A subtab chosen over an open Installs session ends it the way Cancel does, asking first when changes are staged.
  View.prototype.leaveInstalls = function (id) {
    var self = this, installs = this.installEditor;
    var open = installs.requests.busy() ? installs.guard() : !installs.form.hidden ?
      "Accept or cancel the Psi-Install Type edit first." : installs.sidebar.guard();
    if (open) { this.notice.show(open, { tone: "warning" }); return; }
    installs.cancelSession(false, function () { if (self.tabs.select(id)) self.tabs.buttons[id].focus(); });
  };
  View.prototype.request = function (action, params, done, allowDraft) {
    if (this.disposed || !this.enabled || this.requests.busy() || !this.installEditor.root.hidden) return false;
    if (!allowDraft && this.guard()) { this.notice.show(this.guard()); return false; }
    var self = this;
    var result = this.requests.run(action, params || {}, { onDone: done, onFail: function (outcome) {
      if (self.renameNodes) self.renameNodes.forEach(function (node) { node.disabled = false; });
      if (self.valueEditor) self.valueEditor.refuse(outcome.message || "Review and retry.");
    } });
    if (result) this.paintPending();
    return result;
  };
  View.prototype.buildHeading = function () {
    var self = this;
    this.main = el("div", "window-main"); this.layout.appendChild(this.main);
    // Shown in the Builder's place while there is no Window Type to build.
    this.emptyPrompt = el("p", "phc-empty window-empty-prompt",
      "No Window Types yet. Choose + in the Window Types list."); this.layout.appendChild(this.emptyPrompt);
    this.heading = el("div", "window-heading"); this.main.appendChild(this.heading);
    this.identity = el("div", "window-identity"); this.heading.appendChild(this.identity);
    this.title = ui.button("Select a Window Type", function () { self.renameInline(); });
    this.title.className = "window-title"; this.identity.appendChild(this.title);
    this.headerMetrics = el("div", "window-header-metrics"); this.heading.appendChild(this.headerMetrics);
    function metric(label) {
      var root = el("div", "window-header-metric"), caption = el("small", "", label), value = el("strong", "", "—");
      value.unit = el("span", "window-metric-unit"); caption.appendChild(value.unit);
      root.appendChild(caption); root.appendChild(value); self.headerMetrics.appendChild(root); return value;
    }
    this.uwMetric = metric("Uw"); this.installedMetric = metric("Uw,installed");
    this.typeActions = el("div", "window-type-actions"); this.heading.appendChild(this.typeActions);
    // The Window Type's tools read as one grouped control, then Place, then the overflow menu.
    this.typeTools = el("div", "phc-toolbar window-type-tools"); this.typeTools.setAttribute("role", "toolbar");
    this.typeTools.setAttribute("aria-label", "Window Type tools"); this.typeActions.appendChild(this.typeTools);
    this.installButton = ui.iconButton("Edit Window Type installs", "installs", function () {
      if (self.guard()) { self.notice.show(self.guard()); return; }
      var record = self.rawRecord(); if (record) { self.installEditor.open(record); self.paint(); }
    }); this.typeTools.appendChild(this.installButton);
    this.paintDimensionControl();
    this.readinessButton = ui.helpButton("Before placing", "Enter every row height and column width. " +
      "Choose a Face in a Zone; paired Surface Faces, overhangs and overlaps are refused. " +
      "For export, complete the products, operation and installs and classify the host Outdoors.");
    this.typeTools.appendChild(this.readinessButton);
    this.placeButton = ui.button("Place", function () { self.placement.choose(self.active); });
    this.placeButton.className = "primary";
    this.typeActions.appendChild(this.placeButton);
    this.moreActions = new ui.ActionMenu("More Window Type actions");
      this.typeActions.appendChild(this.moreActions.root);
    this.moreActions.add("Install depth…", function () { self.depthOverride(); }, { icon: "ruler" });
    this.moreActions.add("Use Model default install depth", function () {
      var record = self.record(); if (record) self.request(shared.PREFIX + "types.update", { id: record.id,
        values: { install_depth_m: null }, expected_values: self.authored(record) });
    });
    this.moreActions.add("Duplicate Window Type", function () { self.duplicateType(self.record()); }, {
      icon: "duplicate" });
    this.moreActions.add("Delete Window Type", function () { self.deleteType(self.record(),
      self.moreActions.trigger); },
      { icon: "delete", destructive: true });
  };
  View.prototype.paintDimensionControl = function () {
    var signature = JSON.stringify(units.profile(WINDOW_DIMENSION));
    if (signature === this.dimensionControlSignature) return;
    var next = unitFields.DimensionFormatControl("ph_composer.windows.types", function (format, system) {
      panel.setPreference("dimension_format", format, { scope: "ph_composer.windows.types", system: system });
    });
    if (this.dimensionControl) {
      this.dimensionControl.close(false);
      var old = this.dimensionControl.root;
      old.parentNode.insertBefore(next.root, old); old.parentNode.removeChild(old);
    } else this.typeTools.appendChild(next.root);
    this.dimensionControl = next; this.dimensionControlSignature = signature;
  };
  View.prototype.depthOverride = function () {
    if (this.guard() || !this.record()) return;
    var self = this, record = clone(this.record());
    this.editQuantity(this.moreActions.trigger, "Install depth", fields.with(fields.LENGTH_M,
      { label: "Install depth", min: 0, allowBlank: false }), this.rawRecord().display.install_depth_m,
      function (value, done) {
        self.request(shared.PREFIX + "types.update", { id: record.id, values: { install_depth_m: value },
          expected_values: self.authored(record) }, done, true);
      });
  };
  View.prototype.buildRail = function () {
    var self = this;
    this.rail = el("aside", "window-rail"); this.layout.appendChild(this.rail);
    this.railStrip = ui.button("", function () { self.toggleRail(); }); this.railStrip.className = "window-rail-strip";
    this.railStrip.replaceChildren(ui.glyph("sidebar"), el("span", "", "Window Types"));
    this.railStrip.setAttribute("aria-label", "Expand Window Types sidebar");
      this.railStrip.setAttribute("aria-expanded", "false"); this.rail.appendChild(this.railStrip);
    this.railContent = el("div", "window-rail-content"); this.rail.appendChild(this.railContent);
    // The page title names the list, so the rail opens straight on its tools, the collapse control at their end.
    this.railCollapse = ui.iconButton("Collapse Window Types sidebar", "sidebar", function () { self.toggleRail(); });
    this.railCollapse.setAttribute("aria-expanded", "true"); this.railCollapse.classList.add("window-rail-collapse");
    var railTools = el("div", "window-rail-tools"); this.railContent.appendChild(railTools);
    this.chooser = el("select"); this.chooser.setAttribute("aria-label", "Active Window Type");
      this.chooser.addEventListener("change", function () { self.choose(self.chooser.value); });
      railTools.appendChild(this.chooser);
    this.addType = ui.iconButton("Add Window Type", "add", function () { self.createType(); });
      railTools.appendChild(this.addType);
    this.sortTypes = ui.iconButton("Use manual Window Type order", "sort", function () { self.manual = !self.manual;
      self.paint(); }); railTools.appendChild(this.sortTypes);
    this.addGroup = ui.iconButton("Add display group", "group_add", function () { self.form(self.addGroup,
      "New display group", "", function (value) {
      if (self.groupNames.indexOf(value) < 0) self.groupNames.push(value); self.paint(); },
      "Group/order affect this view only."); }); railTools.appendChild(this.addGroup);
    railTools.appendChild(this.railCollapse);
    this.list = el("div", "window-type-list"); this.railContent.appendChild(this.list);
  };

  View.prototype.buildWorkspace = function () {
    var self = this;
    // Grouped by job, each group one outlined control: how the drawing is viewed; edits to the whole Window
    // Type; which product the library assigns (buildSidebar); and, while elements are selected, edits to them.
    this.tools = el("div", "window-toolbar"); this.main.appendChild(this.tools);
    var viewTools = el("div", "window-tool-group window-view-tools"); this.tools.appendChild(viewTools);
    viewTools.setAttribute("role", "group"); viewTools.setAttribute("aria-label", "View");
    // The viewing side is a choice between named states, so it is the shared choice pill.
    this.viewSide = el("select", "phc-choice-pill"); this.viewSide.setAttribute("aria-label", "Viewing side");
    this.viewSide.addEventListener("change", function () { self.interior = self.viewSide.value === "interior";
      self.paint(); }); viewTools.appendChild(this.viewSide);
    viewTools.appendChild(ui.iconButton("Zoom out", "zoom_out", function () { self.zoom = Math.max(0.5,
      self.zoom - 0.25); self.paint(); }));
    viewTools.appendChild(ui.iconButton("Fit drawing", "fit", function () { self.zoom = 1;
      self.canvas.fitKey = null; self.drawingSignature = null; self.paint(); }));
    viewTools.appendChild(ui.iconButton("Zoom in", "zoom_in", function () { self.zoom = Math.min(4, self.zoom +
      0.25); self.paint(); }));
    this.selectionTools = el("div", "window-tool-group window-selection-tools");
      this.tools.appendChild(this.selectionTools);
    this.selectionTools.setAttribute("role", "group");
    this.selectionTools.setAttribute("aria-label", "Selected elements");
    this.selectionTools.appendChild(ui.iconButton("Clear element selection", "clear", function () {
      self.select(null); }));
    // Single Undo steps with a visible result apply at once; only Empty, which clears products, asks first.
    this.merge = ui.iconButton("Merge selected elements", "merge", function () { self.change("merge", {
      ids: self.selected.slice() }); }); this.merge.setAttribute("data-window-action", "merge");
      this.selectionTools.appendChild(this.merge);
    this.selectionTools.appendChild(ui.iconButton("Split selected element", "split", function () {
      self.change("split", { id: self.selected[0] }); }));
    // One kind button offers whichever change the selection allows; paint names it from the first selected element.
    this.kindButton = ui.iconButton("Set selected elements to Empty", "empty", function () {
      self.setKind(self.kindTarget, self.kindButton); }); this.selectionTools.appendChild(this.kindButton);
    var definitionTools = el("div", "window-tool-group window-definition-tools");
      this.tools.insertBefore(definitionTools, this.selectionTools);
    definitionTools.setAttribute("role", "group"); definitionTools.setAttribute("aria-label", "Window Type");
    this.flip = ui.iconButton("Flip Window Type left to right", "mirror", function () { self.change("flip", {}); });
      this.flip.setAttribute("data-window-action", "flip"); definitionTools.appendChild(this.flip);
    this.pick = ui.iconButton("Copy element properties with eyedropper", "eyedropper", function () {
      self.togglePick(); }); definitionTools.appendChild(this.pick);
    definitionTools.appendChild(ui.iconButton("About Undo and Redo", "undo", function () {
      self.notice.show("Use SketchUp Edit > Undo to reverse the last complete Model gesture. " +
        "Redo is in the same menu."); }));
    this.drawing = el("div", "window-drawing"); this.canvas = new Canvas(this);
      this.drawing.appendChild(this.canvas.root); this.main.appendChild(this.drawing);
    this.cardFilter = el("div", "window-card-filter"); this.cardFilter.hidden = true;
      this.main.appendChild(this.cardFilter);
    this.cardFilterText = el("span"); this.cardFilter.appendChild(this.cardFilterText);
    this.cardFilter.appendChild(ui.button("Show all elements", function () { self.selected = []; self.paint(); }));
    this.cardStack = el("div", "window-cards"); this.main.appendChild(this.cardStack);

  };

  View.prototype.railCollapsed = function () {
    // At 900 and under, in step with the stylesheet that narrows the rail's column.
    return this.collapsed === undefined ? window.innerWidth <= 900 : this.collapsed;
  };
  View.prototype.toggleRail = function () { this.collapsed = !this.railCollapsed(); this.paint(); };
  View.prototype.buildSidebar = function () {
    var self = this; this.sidebarKind = "frames";
    this.sidebars = {};
    ["frames", "glazings"].forEach(function (kind) {
      var adapter = library.adapter(kind, function (context) { return library.elementTarget(kind, context); });
      adapter.dropSelector = kind === "frames" ? ".window-frame-target" : ".window-glazing-target";
      adapter.dropSelection = function (hit) { return { element_id: hit.getAttribute("data-element-id"),
        side: hit.getAttribute("data-frame-side") }; };
      var sidebar = new Sidebar({ session: self.session, send: self.send, changed: function () { self.paint(); },
        busy: function () { return Boolean(self.guard()); }, adapter: adapter, onUse: function (row, target) {
            var cell = self.record().elements.filter(function (entry) { return entry.id === target.element_id; })[0];
            return kind === "glazings" ?
              self.change("set_element_glazing", { element_id: cell.id, glazing_id: row.id }) :
              self.change("set_element_frame", { element_id: cell.id, side: target.side, frame_id: row.id });
          } });
      self.sidebars[kind] = sidebar; self.layout.appendChild(sidebar.root);
      sidebar.dropHost = self.cardStack;
    });
    this.sidebarChoice = el("select", "phc-choice-pill");
    this.sidebarChoice.setAttribute("aria-label", "Product Library");
    this.sidebarChoice.appendChild(ui.option("frames", "Frames"));
      this.sidebarChoice.appendChild(ui.option("glazings", "Glazings"));
    this.sidebarChoice.addEventListener("change", function () {
      if (self.guard()) { self.sidebarChoice.value = self.sidebarKind; self.notice.show(self.guard()); return; }
      self.sidebarKind = self.sidebarChoice.value;
      self.paint(); });
    this.frameSide = el("select", "phc-choice-pill");
    this.frameSide.setAttribute("aria-label", "Frame side to assign");
    shared.sides.forEach(function (side) { self.frameSide.appendChild(ui.option(side, ui.titleCase(side))); });
    // The library's settings sit together, named by what they do, before the selection's edits; the frame side
    // shows only while frames are assigned.
    var libraryTools = el("div", "window-tool-group window-library-tools");
    libraryTools.setAttribute("role", "group"); libraryTools.setAttribute("aria-label", "Assign from library");
    libraryTools.appendChild(el("small", "window-tool-caption", "Assign"));
    libraryTools.appendChild(this.sidebarChoice); libraryTools.appendChild(this.frameSide);
    this.tools.insertBefore(libraryTools, this.selectionTools);
  };
  View.prototype.buildKeyboard = function () {
    var self = this;
    this.onKeydown = function (event) {
      if (event.defaultPrevented || self.disposed || self.root.hidden) return;
      if (!self.installEditor.root.hidden) { self.installEditor.onKeydown(event); return; }
      if (self.guard()) return;
      if (/INPUT|SELECT|TEXTAREA/.test((event.target.tagName || "").toUpperCase())) return;
      if (event.key === "Escape") {
        if (self.picking || self.source) { self.picking = false; self.source = null; }
        else if (self.selected.length) self.selected = [];
        else if (self.placement.tool.active) self.placement.run("place_tool.stop", {});
        self.paint(); event.preventDefault();
      }
    };
    this.root.addEventListener("keydown", this.onKeydown);
    this.documentKey = function (event) {
      if (event.target !== document.body && event.target !== document.documentElement) return;
      for (var node = self.root; node; node = node.parentNode) if (node.hidden) return;
      self.onKeydown(event);
    }; document.addEventListener("keydown", this.documentKey);
    if (window.ResizeObserver) {
      this.resize = new window.ResizeObserver(function () { self.drawingSignature = null; self.paint(); });
      this.resize.observe(this.drawing);
    }
  };
  View.prototype.paintPending = function () {
    var disabled = !this.enabled || this.requests.busy() || !this.installEditor.root.hidden;
    [this.addType, this.installButton, this.merge, this.flip].forEach(function (button) {
      button.disabled = disabled; });
    if (this.dimensionField) this.dimensionField.setDisabled(this.requests.busy());
  };
  View.prototype.paint = function () {
    var self = this; if (this.disposed) return;
    this.paintDimensionControl();
    this.surface = this.tabs.active;
    this.layout.hidden = this.surface !== "builder" || !this.installEditor.root.hidden;
    this.audit.hidden = this.surface !== "audit" || !this.installEditor.root.hidden;
    this.scheduleSurface.hidden = this.surface !== "schedule" || !this.installEditor.root.hidden;
    this.renderList(); var record = this.record(); this.main.hidden = !record;
    this.emptyPrompt.hidden = Boolean(record) || !this.enabled;
    this.paintPending();
    this.placement.paint(); this.schedule.paint();
    this.installButton.disabled = this.installButton.disabled || !snapshot.value(this.state, shared.PREFIX +
      "settings");
    Object.assign(this.page, { active: this.active, order: this.order, groups: this.groups,
      groupNames: this.groupNames, manual: this.manual, interior: this.interior, zoom: this.zoom,
        collapsed: this.collapsed });
    // With no Window Type there is nothing to give a product to, so the product libraries stay out of the way.
    if (!record) { Object.keys(this.sidebars).forEach(function (kind) {
      self.sidebars[kind].root.hidden = true;
      self.sidebars[kind].refresh(self.state, {}, false);
    });
    // The empty audit keeps the table's frame, as every empty table does.
    var emptyAudit = el("div", "window-audit-list");
    emptyAudit.appendChild(el("p", "phc-empty", this.enabled ? "Add a Window Type." :
      "Window Type definitions are unavailable.")); this.audit.replaceChildren(emptyAudit); return; }
    this.title.textContent = record.name;
    if (!this.viewSide.children.length) VIEW_SIDES.forEach(function (side) {
      self.viewSide.appendChild(ui.option(side.id, side.label)); });
    this.viewSide.value = this.interior ? "interior" : "exterior";
    var entry = this.entries.filter(function (row) { return row.record.id === self.active; })[0];
    this.paintMetric(this.uwMetric, entry.calculation.uw_w_m2k, "Complete dimensions and products to calculate Uw.");
    this.paintMetric(this.installedMetric, entry.calculation.u_effective_w_m2k,
      "Complete perimeter installations to calculate installed Uw.");
    var ids = record.elements.map(function (cell) { return cell.id; });
    this.selected = this.selected.filter(function (id) { return ids.indexOf(id) >= 0; });
    if (this.revealInserted && this.revealInserted.type_id === record.id) {
      var fresh = ids.filter(function (id) { return self.revealInserted.known.indexOf(id) < 0; });
      if (fresh.length) { this.selected = fresh; this.revealInserted = null; }
    }
    var first = record.elements.filter(function (cell) { return cell.id === self.selected[0]; })[0];
    this.kindTarget = first && first.kind === "empty" ? "glazed" : "empty";
    ui.paintIconButton(this.kindButton, this.kindTarget === "empty" ? "Set selected elements to Empty" :
      "Set selected elements to Glazed", this.kindTarget);
    this.selectionTools.hidden = !this.selected.length;
    this.merge.disabled = this.requests.busy() || this.selected.length < 2;
    ui.paintIconButton(this.pick, this.source ? "Stop pasting element properties" :
      "Copy element properties with eyedropper", this.source ? "paint_bucket" : "eyedropper");
    this.pick.setAttribute("aria-pressed", String(Boolean(this.picking || this.source)));
    this.drawing.classList.toggle("is-picking", Boolean(this.picking));
    this.drawing.classList.toggle("is-pasting", Boolean(this.source));
    var signature = JSON.stringify([record, this.selected, this.source, this.zoom, this.interior,
      shared.windowsState(this.state), units.profile(WINDOW_DIMENSION)]);
    if (signature !== this.drawingSignature) { this.drawingSignature = signature; this.canvas.render(record); }
    Object.keys(this.cards).forEach(function (id) { if (ids.indexOf(id) < 0) {
      var node = self.cards[id].root; if (node.parentNode) node.parentNode.removeChild(node);
      delete self.cards[id];
    } });
    record.elements.forEach(function (cell, index) {
      var node = self.card(cell); node.hidden = self.selected.length > 0 && self.selected.indexOf(cell.id) < 0;
      if (self.cardStack.children[index] !== node) self.cardStack.insertBefore(node,
        self.cardStack.children[index] || null);
    });
    this.cardFilter.hidden = !this.selected.length;
    this.cardFilterText.textContent = "Showing " + this.selected.length + " of " + ids.length + " elements";
    Object.keys(this.sidebars).forEach(function (kind) {
      self.sidebars[kind].root.hidden = kind !== self.sidebarKind;
      var side = self.frameSide.value || "top";
      if (self.interior) side = { left: "right", right: "left" }[side] || side;
      self.sidebars[kind].refresh(self.state, { record: self.rawRecord(), selection: {
        element_id: self.selected[0], side: side } }, self.enabled);
    }); this.frameSide.hidden = this.sidebarKind !== "frames";
    this.paintAudit();
    if (this.renameAfter === record.id) { this.renameAfter = null; this.renameInline(); }
  };
  View.prototype.render = function (state) {
    if (this.disposed) return;
    this.state = state; this.enabled = Boolean(snapshot.value(state, shared.PREFIX + "types"));
    this.entries = shared.records(state, "types").map(function (raw) {
      return { record: Object.assign(shared.flat(raw), { _authored: clone(raw.values) }),
        calculation: (raw.display || {}).thermal || { elements: [], findings: [] },
        // Everything the Model says is unfinished about this Type, its elements included. A Frame whose operation
        // differs from its element's is advice, not a gap: Export does not block on it.
        findings: (raw.findings || ((raw.display || {}).thermal || {}).findings || []).filter(function (finding) {
          return finding.code !== "window_type.frame_operation_mismatch";
        }) };
    });
    if (this.renameTarget && !this.entries.some(function (entry) {
      return entry.record.id === this.renameTarget;
    }, this)) { this.requests.reset(); this.cancelRename(); }
    if (this.formDraft) {
      var target = this.rawRecord(this.formDraft.target.type_id);
      if (!target || this.formDraft.target.element_id && !target.values.elements.some(function (cell) {
        return cell.id === this.formDraft.target.element_id;
      }, this)) { this.requests.reset(); this.formDraft.cancel(false); }
    }
    if (!this.enabled) {
      this.requests.reset(); if (this.valueEditor) this.valueEditor.dispose();
      this.dimensionField = null;
      if (this.bubble) this.bubble.close(false);
    }
    if (!this.record()) this.active = this.entries.length ? this.entries[0].record.id : null;
    this.requests.consume(state); this.installEditor.render(state); this.placement.render(state);
    this.schedule.render(state); this.paint();
  };
  View.prototype.openUse = function (use) {
    if (this.guard()) return;
    this.tabs.select("builder"); this.choose(use.type_id); this.selected = use.element_id ? [use.element_id] : [];
    this.paint();
  };
  View.prototype.dispose = function () {
    this.disposed = true; this.enabled = false; this.requests.reset(); this.tabs.dispose();
    if (this.cancelRename) this.cancelRename();
    if (this.formDraft) this.formDraft.cancel(false);
    this.installEditor.dispose(); if (this.valueEditor) this.valueEditor.dispose();
    this.placement.dispose(); this.schedule.dispose();
    if (this.bubble) this.bubble.close(false);
    Object.keys(this.sidebars).forEach(function (kind) { this.sidebars[kind].dispose(); }, this);
    this.root.removeEventListener("keydown", this.onKeydown); document.removeEventListener("keydown", this.documentKey);
    if (this.resize) this.resize.disconnect();
  };
  Object.assign(View.prototype, typeList, cards, audit);
  return { View: View };
});
