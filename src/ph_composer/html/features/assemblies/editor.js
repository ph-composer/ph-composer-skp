/* One Assembly work surface. Every authored gesture sends one registered action and awaits its outcome. */
PhComposerUI.define("features/assemblies/editor", ["features/assemblies/editor_shared", "features/assemblies/header",
  "features/assemblies/inspector", "features/assemblies/layer_drag", "features/assemblies/stage",
  "features/assemblies/form", "features/assemblies/material_form", "fields", "inventory_forms", "library/sidebar",
  "record_edits", "request", "snapshot", "unit_field", "workspace"],
function (shared, header, inspector, layerDrag, stage, AssemblyForm, MaterialForm, fields, forms, Sidebar, RecordEdits,
  request, snapshot, unitFields, ui) {
  "use strict";
  // A Material, local or a library row, is labelled by its name.
  function materialName(row) { return row.display_label || row.values.name; }
  var SECTION = "ph_composer.assemblies.assemblies", MATERIALS = "ph_composer.assemblies.materials";
  var el = ui.element;
  function Editor(session, send, notice, onClose, chooseDimensionFormat) {
    var self = this;
    this.session = session;
    this.notice = notice;
    this.onClose = onClose;
    this.chooseDimensionFormat = chooseDimensionFormat || function () {};
    this.root = el("div", "assembly-editor");
    this.main = el("div", "assembly-editor-main");
    this.requests = request.channel(session, send, "assembly-builder");
    this.dimensions = Object.create(null);
    this.selection = null;
    this.zoom = null;
    this.enabled = false;
    this.svg = document.createElementNS("http://www.w3.org/2000/svg", "svg");
    this.layerDrag = new layerDrag.LayerDrag(this);
    this.send = send;
    this.edits = new RecordEdits(session, send, notice, Object.assign({ action: SECTION + ".update",
      fields: ["name", "type", "exterior_condition", "notes"], requiredFields: ["name"],
      selectFields: { type: AssemblyForm.types, exterior_condition: AssemblyForm.exteriors },
      recordLabel: "Assembly", presentation: "inline", navigateOnCommit: false,
      label: function (_row, field) {
        return field === "exterior_condition" ? "Exterior condition" : ui.titleCase(field);
      },
      enabled: function () { return self.enabled; }, readOnly: function (cell) {
        return self.requests.busy() || self.color.requests.busy() ||
          (self.edits.pending && self.edits.pending !== cell) || self.hasDimensionDraft();
      }, normalize: function (field, value) {
        if ((field === "type" || field === "exterior_condition") && !value) return null;
      } }, AssemblyForm.exteriorEdits(SECTION + ".update")));
    this.color = new forms.ColorForm(session, send, SECTION + ".update", function () { self.repaint(); });
    // New Material lives on the Library pane too; here it saves the trip. Refresh finishes a create's repaint.
    this.newMaterial = new MaterialForm(session, send, function (created) {
      if (created && created.id) self.createdMaterial = created.id; else self.repaint();
    });
    this.sidebar = new Sidebar({ session: session, send: send, changed: function () { self.repaint();
    }, busy: function () { return self.busy() || Boolean(self.guard()); },
      create: { label: "+ New Material", run: function () { self.newMaterial.open(); } },
      adapter: { title: "Material Library", localLabel: "Materials in this file", wireKind: "materials",
        name: materialName, read: function (state) {
        var payload = snapshot.value(state, MATERIALS);
        return payload ? payload.records : [];
      }, categories: function (state) { return (snapshot.value(state, MATERIALS) || {}).categories || []; },
      properties: [["Conductivity", "conductivity_w_mk", fields.CONDUCTIVITY],
        ["Density", "density_kg_m3", fields.DENSITY], ["Specific heat", "specific_heat_j_kgk", fields.SPECIFIC_HEAT],
        ["Emissivity", "emissivity", fields.FRACTION]],
      decorate: function (node, row) {
        var swatch = el("span", "library-sidebar-swatch");
        swatch.style.backgroundColor = row.values.color || "#ffffff";
        node.appendChild(swatch);
      }, dropSelector: ".assembly-hit-target", dropSelection: function (hit) {
        return { layerId: hit.getAttribute("data-layer-id"), segmentId: hit.getAttribute("data-segment-id") };
      }, target: function (context) {
        var chosen = shared.selected(context.record, context.selection);
        return chosen ? { params: { layer_id: chosen.layer.id, segment_id: chosen.segment.id } } :
          { hint: "Select a Layer-Segment in the drawing first." };
      }, assignment: function (context, target) {
        return Object.assign({}, target, { id: context.record.id,
          expected_values: shared.clone(context.record.values) });
      } }, onUse: function (row, target) {
        return self.action("segments.set_material", Object.assign({}, target, { material_id: row.id }));
      } });
    this.sidebar.dropHost = this.main;
    // While a Material or a Layer is dragged, the edge insert control and the Layer tools stay out of the way.
    this.sidebar.onDragChange = function (dragging) { self.dragging = Boolean(dragging); };
    this.root.appendChild(this.main);
    this.root.appendChild(this.sidebar.root);
    this.root.appendChild(this.color.root);
    this.root.appendChild(this.newMaterial.root);
    this.removal = ui.formDialog("", function () { self.removal.closeModal(); });
    this.root.appendChild(this.removal);
    this.root.addEventListener("keydown", function (event) {
      if (event.defaultPrevented || event.key !== "Escape" || self.busy() ||
        !self.removal.hidden || !self.color.root.hidden || !self.newMaterial.root.hidden) return;
      var open = Object.keys(self.dimensions).filter(function (key) {
        return self.dimensions[key].inlineOpen;
      })[0];
      if (open) {
        event.preventDefault(); self.dimensions[open].returnFocus = true;
        self.dimensions[open].field.cancel(); return;
      }
      if (self.hasDimensionDraft() || self.hasRecordDraft()) return;
      // A tool another feature has on is ended first, by that feature; the selection waits for the next Escape.
      if (self.selection && !self.contributedToolOn()) { event.preventDefault(); self.select(null); }
    });
  }
  Editor.prototype.busy = function () {
    return this.requests.busy() || Boolean(this.edits.pending) || this.color.requests.busy() || this.newMaterial.busy();
  };
  Editor.prototype.contributedToolOn = function () {
    return this.contributions.actions({ key: this.record.id, record: this.record }).some(function (action) {
      return action.detail && action.pressed;
    });
  };
  Editor.prototype.hasRecordDraft = function () {
    return Object.keys(this.edits.cells).some(function (key) {
      return this.edits.cells[key].status !== "clean";
    }, this);
  };
  Editor.prototype.hasDimensionDraft = function () {
    return Object.keys(this.dimensions).some(function (key) {
      var field = this.dimensions[key].field;
      return field.editing && field.input.value !== field.seed;
    }, this);
  };
  Editor.prototype.guard = function () {
    if (this.disposed || !this.enabled) return "This Builder is no longer available.";
    // Not the shared dragging flag: the Material drag reads this guard on every move and would end itself.
    if (this.layerDrag.active()) return "Finish moving the Layer first.";
    if (this.sidebar && this.sidebar.guard()) return this.sidebar.guard();
    if (this.busy()) return "Wait for the Assembly change to finish.";
    if (!this.newMaterial.root.hidden) return "Finish or cancel the open form.";
    if (this.hasDimensionDraft() || this.hasRecordDraft() || !this.color.root.hidden || !this.removal.hidden) {
      return "Apply or cancel the Assembly draft before leaving.";
    }
    return null;
  };
  Editor.prototype.allowed = function () {
    var reason = this.guard();
    if (reason) this.notice(reason);
    return !reason;
  };
  Editor.prototype.expected = function () {
    var values = this.record.values;
    return { layers: shared.clone(values.layers || []), orientation: values.orientation,
      air_barrier: values.air_barrier || null };
  };
  Editor.prototype.remove = function (name, params, label, consequence) {
    if (!this.allowed()) return false;
    if (!consequence) return this.action(name, params);
    var self = this, expected = this.expected(), id = this.record.id;
    this.removal.replaceChildren(el("h2", "", label), el("p", "", consequence),
      ui.actionRow(ui.button("Cancel", function () { self.removal.closeModal(); }),
        ui.button(label, function () {
          self.removal.closeModal();
          if (!self.disposed && self.record.id === id) self.action(name, params, expected);
        }), true));
    this.removal.openModal();
    return true;
  };
  Editor.prototype.action = function (name, params, expected, dimensionKey) {
    if (this.disposed || !this.enabled || this.busy()) return false;
    if (!dimensionKey && !this.allowed()) return false;
    var self = this;
    var sent = this.requests.run(SECTION + "." + name, Object.assign({}, params,
      { id: this.record.id, expected_values: expected || this.expected() }), {
      onDone: function () {
        if (dimensionKey && self.dimensions[dimensionKey]) self.dimensions[dimensionKey].accepted = true;
      }, onFail: function (outcome) {
        self.pendingInsert = null;
        var message = snapshot.message(outcome, "The Assembly change was not applied.");
        if (dimensionKey && self.dimensions[dimensionKey]) {
          self.dimensions[dimensionKey].requiresCancel = true;
          self.dimensionError(self.dimensions[dimensionKey], message);
        }
        self.notice(message);
      }
    });
    this.paintPending();
    return Boolean(sent);
  };
  Editor.prototype.dimensionError = function (entry, message) {
    entry.field.error.textContent = message;
    entry.field.error.hidden = false;
    entry.field.input.setAttribute("aria-invalid", "true");
    if (!entry.inlineOpen || this.painting) return;
    // The drawing scrollport must not clip the explanation. Keep the input in place and use the same
    // detached, viewport-clamped bubble as the other drawing controls, without moving keyboard focus.
    if (!entry.errorBubble) {
      entry.errorBubble = new ui.Bubble(entry.field.input, entry.spec.label,
        { detachedTrigger: true, ownTrigger: true });
      entry.errorBubble.root.classList.add("assembly-dimension-error-anchor");
      entry.errorBubble.panel.classList.add("assembly-dimension-error");
      entry.errorBubble.content.appendChild(entry.field.error);
      this.root.appendChild(entry.errorBubble.root);
    }
    entry.errorBubble.open(false);
  };
  Editor.prototype.endInlineDimension = function (key, focus) {
    var entry = this.dimensions[key];
    if (!entry || !entry.inlineControl) return;
    entry.inlineOpen = false;
    if (entry.errorBubble) entry.errorBubble.close(false);
    entry.inlineControl.show(false, focus && !this.painting);
    if (focus && this.painting) this.inlineFocusKey = key;
  };
  Editor.prototype.dimension = function (key, spec) {
    var self = this, entry = this.dimensions[key];
    if (!entry) {
      entry = this.dimensions[key] = { spec: spec, expected: null };
      var descriptor = Object.assign({}, spec.optional ? shared.OPTIONAL_DIMENSION : shared.DIMENSION,
        { label: spec.label });
      entry.field = new unitFields.UnitField({ field: descriptor, value: spec.value,
        onCancel: function () {
          var returnFocus = entry.returnFocus !== false;
          entry.expected = null; entry.requiresCancel = false;
          self.endInlineDimension(key, returnFocus);
          entry.returnFocus = null; self.paintPending();
          if (entry.spec.unavailableReason && !self.painting) {
            self.repaint();
            var trigger = self.main.querySelector("[data-layer-thickness='" + entry.spec.params.layer_id + "']");
            if (returnFocus && trigger) trigger.focus({ preventScroll: true });
          }
        } });
      entry.field.input.setAttribute("data-builder-dimension", key);
      entry.field.input.addEventListener("input", function () {
        if (entry.errorBubble) entry.errorBubble.close(false);
        if (!entry.expected) entry.expected = self.expected();
      });
      // UnitField owns text, parsing and unit context. The owner keeps it editing until host acceptance, so
      // Enter is the owner's: caught while it travels down to the input, before UnitField's own listener on
      // the input runs (on the host floor's Chromium a capture listener on the target itself would not be).
      entry.field.root.addEventListener("keydown", function (event) {
        if (entry.inlineControl && event.key === "Escape" && event.target === entry.field.input) {
          event.preventDefault(); event.stopPropagation(); entry.returnFocus = true; entry.field.cancel(); return;
        }
        if (event.key !== "Enter" || event.target !== entry.field.input) return;
        event.preventDefault();
        event.stopPropagation();
        entry.returnFocus = true;
        self.commitDimension(key);
      }, true);
      // Leaving the field applies the draft, as Enter does. A blur during a repaint is the page moving the
      // input, not the user leaving it, so it sends nothing.
      // Switching to SketchUp mid-word blurs the input too; that is not leaving the field.
      entry.field.input.addEventListener("blur", function () {
        var windowActive = !document.hasFocus || document.hasFocus();
        if (!self.painting && windowActive && entry.field.input.isConnected && !self.busy()) {
          entry.returnFocus = false;
          self.commitDimension(key);
        }
      });
      entry.root = el("div", "assembly-dimension-editor");
      entry.root.appendChild(entry.field.root);
    }
    entry.spec = spec;
    entry.live = true;
    if (entry.accepted && spec.value !== entry.submitted) {
      entry.requiresCancel = true;
      this.dimensionError(entry, "The Model differs from this draft. Escape to cancel and re-edit.");
      entry.accepted = false;
    }
    if (entry.accepted) {
      entry.field.setValue(spec.value);
      entry.field.cancel();
      entry.accepted = false;
      entry.expected = null;
    } else entry.field.setValue(spec.value);
    if (entry.field.editing && entry.expected && JSON.stringify(entry.expected) !== JSON.stringify(this.expected())) {
      entry.requiresCancel = true;
      this.dimensionError(entry, "Changed in the Model. Escape to cancel and re-edit.");
    }
    entry.field.input.readOnly = Boolean(spec.unavailableReason);
    if (spec.unavailableReason && entry.field.editing && entry.field.input.value !== entry.field.seed) {
      entry.requiresCancel = true;
      this.dimensionError(entry, spec.unavailableReason);
    }
    return entry;
  };
  Editor.prototype.commitDimension = function (key) {
    var entry = this.dimensions[key];
    if (!entry || this.disposed || !this.enabled || this.busy() || entry.requiresCancel) {
      return false;
    }
    if (!entry.field.editing) { this.endInlineDimension(key, entry.returnFocus); return false; }
    if (entry.field.input.value === entry.field.seed) { entry.field.cancel(); return false; }
    if (entry.expected && JSON.stringify(entry.expected) !== JSON.stringify(this.expected())) {
      this.dimensionError(entry, "Changed in the Model. Escape to cancel and re-edit.");
      return false;
    }
    var parsed = entry.field.parse();
    if (!parsed.ok) { this.dimensionError(entry, parsed.message); return false; }
    if (parsed.value === entry.spec.value) { entry.field.cancel(); return false; }
    entry.submitted = parsed.value;
    var params = Object.assign({}, entry.spec.params);
    if (entry.spec.nested) { params.values = {}; params.values[entry.spec.nested] = parsed.value; }
    else params[entry.spec.field] = parsed.value;
    return this.action(entry.spec.action, params, entry.expected || this.expected(), key);
  };
  /* Before a dimension's bubble closes: an unchanged or already sent draft lets it close, a changed one is
     applied, and one that cannot be applied (invalid, or the Model moved) keeps the bubble open and says why. */
  Editor.prototype.settleDimension = function (key) {
    var entry = this.dimensions[key];
    // A Builder being torn down closes whatever is open; nothing is sent and nothing is refused.
    if (this.disposed || !this.enabled) return null;
    if (!entry || !entry.field.editing || this.busy()) return null;
    if (entry.field.input.value === entry.field.seed) { entry.field.cancel(); return null; }
    if (entry.requiresCancel) return "Press Escape to restore " + entry.spec.label.toLowerCase() + ".";
    // A retyped value equal to the stored one ends the draft without a request; that is settled too.
    if (this.commitDimension(key) || this.busy() || !entry.field.editing) return null;
    return entry.field.error.textContent || "Enter a valid value, or press Escape.";
  };
  /* An edge's insert: one action with a round default size, then what it made is selected, so the next step
     (resize it, give it a Material) is right there. */
  Editor.prototype.insert = function (target) {
    var layers = this.record.values.layers || [];
    var before = target.kind === "layer" ? layers.map(function (layer) { return layer.id; }) :
      (layers.filter(function (layer) { return layer.id === target.params.layer_id; })[0] || { segments: [] })
        .segments.map(function (segment) { return segment.id; });
    // Set before sending: a host that answers at once settles it within the call.
    this.pendingInsert = { kind: target.kind, layerId: target.params.layer_id, before: before };
    if (this.action(target.action, target.params)) return true;
    this.pendingInsert = null;
    return false;
  };
  Editor.prototype.selectInserted = function (record) {
    var pending = this.pendingInsert, layers = record.values.layers || [];
    if (!pending || this.busy()) return;
    this.pendingInsert = null;
    if (pending.kind === "layer") {
      var layer = layers.filter(function (candidate) { return pending.before.indexOf(candidate.id) < 0; })[0];
      if (layer && layer.segments.length) this.selection = { layerId: layer.id, segmentId: layer.segments[0].id };
      this.focusSelection = Boolean(layer && layer.segments.length);
      return;
    }
    var host = layers.filter(function (candidate) { return candidate.id === pending.layerId; })[0];
    var segment = host && host.segments.filter(function (candidate) {
      return pending.before.indexOf(candidate.id) < 0;
    })[0];
    if (segment) this.selection = { layerId: host.id, segmentId: segment.id };
    this.focusSelection = Boolean(segment);
  };
  Editor.prototype.paintPending = function () {
    var busy = this.busy();
    this.main.querySelectorAll("button, select, input").forEach(function (control) {
      if (control.getAttribute("data-editor-local") === null) {
        if (busy) control.disabled = true;
      }
    });
    Object.keys(this.dimensions).forEach(function (key) {
      this.dimensions[key].field.setDisabled(busy || !this.enabled || this.disposed);
    }, this);
    this.sidebar.paintActions();
  };
  Editor.prototype.select = function (selection) {
    if (!this.allowed()) return false;
    if (selection && !shared.selected(this.record, selection)) return false;
    this.selection = selection;
    this.repaint();
    return true;
  };
  Editor.prototype.setZoom = function (zoom) {
    if (this.disposed) return;
    this.zoom = zoom;
    this.repaint();
  };
  Editor.prototype.repaint = function () {
    if (this.state && !this.disposed) this.refresh(this.state, this.assemblyId);
  };
  Editor.prototype.close = function () {
    if (!this.allowed()) return false;
    this.onClose();
    return true;
  };
  Editor.prototype.refresh = function (state, id) {
    if (this.disposed) return false;
    // A held Layer was measured against the drawing this repaint replaces.
    this.layerDrag.end();
    var payload = snapshot.value(state, SECTION);
    var record = payload && payload.records.filter(function (row) { return row.id === id; })[0];
    if (!record) {
      this.enabled = false;
      this.requests.reset();
      this.dispose();
      this.onClose(null, payload ? "The open Assembly was removed." : "Assemblies are unavailable.");
      return false;
    }
    this.state = state;
    this.record = record;
    this.assemblyId = id;
    this.enabled = true;
    this.requests.consume(state);
    this.selectInserted(record);
    var row = { key: id, record: record };
    // What other features offer on an Assembly's table row; the inspector shows those marked for its own page.
    this.contributions = ui.composeTable(SECTION, { columns: [], value: function () {} }, state, this.send);
    this.edits.refresh([row], state);
    this.color.refresh(state, true, payload.records);
    this.newMaterial.refresh(state);
    var materials = shared.lookup((snapshot.value(state, MATERIALS) || {}).records);
    if (this.selection && !shared.selected(record, this.selection)) this.selection = null;
    var oldScroll = this.main.querySelector(".assembly-stage-scroll");
    var position = oldScroll ? { top: oldScroll.scrollTop, left: oldScroll.scrollLeft } : null;
    var focus = document.activeElement;
    var focusedHit = focus && focus.classList.contains("assembly-hit-target") ? {
      layerId: focus.getAttribute("data-layer-id"), segmentId: focus.getAttribute("data-segment-id") } : null;
    var bubbleTitle = ui.Bubble.activeTitle(this.main);
    var layerToolsKey = Array.prototype.filter.call(this.main.querySelectorAll("[data-layer-tools-key]"),
      function (panel) { return !panel.hidden; }).map(function (panel) {
      return panel.getAttribute("data-layer-tools-key");
    })[0];
    this.painting = true;
    ui.Bubble.closeActive(this.main);
    Object.keys(this.dimensions).forEach(function (key) { this.dimensions[key].live = false; }, this);
    this.main.replaceChildren(this.header(record, row),
      this.inspector(record, materials, shared.selected(record, this.selection)), this.stage(record, materials));
    Object.keys(this.dimensions).forEach(function (key) {
      if (this.dimensions[key].live) return;
      if (this.dimensions[key].errorBubble) {
        this.dimensions[key].errorBubble.close(false); this.dimensions[key].errorBubble.root.remove();
      }
      this.dimensions[key].field.dispose();
      delete this.dimensions[key];
    }, this);
    this.painting = false;
    Object.keys(this.dimensions).forEach(function (key) {
      var entry = this.dimensions[key];
      if (entry.inlineOpen && !entry.field.error.hidden) this.dimensionError(entry, entry.field.error.textContent);
    }, this);
    this.sidebar.refresh(state, { record: record, selection: this.selection },
      Boolean(snapshot.value(state, MATERIALS)));
    if (this.createdMaterial) {
      this.sidebar.revealLocal(this.createdMaterial);
      this.createdMaterial = null;
    }
    this.paintPending();
    var scroll = this.main.querySelector(".assembly-stage-scroll");
    if (scroll && position) { scroll.scrollTop = position.top; scroll.scrollLeft = position.left; }
    if (bubbleTitle) this.main.querySelectorAll(".phc-bubble").forEach(function (panel) {
      var same = layerToolsKey ? panel.getAttribute("data-layer-tools-key") === layerToolsKey :
        panel.getAttribute("aria-label") === bubbleTitle;
      if (same) panel._bubble.open(false);
    });
    // After an insert the control that made it is gone; the new Layer-Segment takes the focus, so Escape and
    // the keyboard still reach the Builder.
    if (this.focusSelection && this.selection) {
      this.focusSelection = false;
      focusedHit = this.selection; focus = null;
    }
    if (focus && this.root.contains(focus)) focus.focus({ preventScroll: true });
    else if (focusedHit) {
      var restored = Array.prototype.filter.call(this.main.querySelectorAll(".assembly-hit-target"), function (hit) {
        return hit.getAttribute("data-layer-id") === focusedHit.layerId &&
          hit.getAttribute("data-segment-id") === focusedHit.segmentId;
      })[0];
      if (restored) restored.focus({ preventScroll: true });
    }
    if (this.inlineFocusKey && !this.busy()) {
      var returned = this.dimensions[this.inlineFocusKey];
      this.inlineFocusKey = null;
      if (returned && returned.inlineControl) returned.inlineControl.trigger.focus({ preventScroll: true });
    }
    return true;
  };
  Editor.prototype.dispose = function () {
    this.layerDrag.end();
    this.disposed = true;
    this.enabled = false;
    this.requests.reset();
    this.edits.dispose();
    this.color.dispose();
    this.newMaterial.dispose();
    this.sidebar.dispose();
    this.removal.closeModal();
    Object.keys(this.dimensions).forEach(function (key) {
      if (this.dimensions[key].errorBubble) this.dimensions[key].errorBubble.close(false);
      this.dimensions[key].field.dispose();
    }, this);
    ui.Bubble.closeActive(this.root);
  };
  Object.assign(Editor.prototype, header, inspector, stage);
  return { Editor: Editor };
});
