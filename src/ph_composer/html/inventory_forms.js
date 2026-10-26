/* Record forms shared by every inventory: the color picker, Duplicate and Delete with a replacement. Each takes
 * its action or section from the caller and names no feature. `labelled` and `refreshForm` are the
 * helpers a feature's own record forms use to match them. */
PhComposerUI.define("inventory_forms", ["record_form", "request", "snapshot", "workspace"],
function (RecordForm, request, snapshot, ui) {
  "use strict";
  function labelled(form, title, control) {
    var label = ui.element("label", "", title);
    control.setAttribute("aria-label", title);
    label.appendChild(control);
    form.appendChild(label);
    return control;
  }
  function refreshForm(form, state, section) {
    form.enabled = Boolean(snapshot.value(state, section));
    if (!form.enabled) {
      form.withdraw();
      return null;
    }
    return form.settle(state);
  }
  function ReplacementForm(session, send, changed, options) {
    var self = this;
    this.options = options;
    RecordForm.call(this, session, send, { title: "Delete " + this.options.label,
      action: this.options.section + ".delete", label: "delete-record", submitLabel: "Delete",
      pendingText: "Deleting...", failureText: "The record was not deleted.", destructive: true, changed: changed });
    this.uses = ui.element("p");
    this.root.appendChild(this.uses);
    this.select = labelled(this.form, "Replacement " + this.options.label.toLowerCase(), ui.element("select"));
    this.select.addEventListener("change", function () { self.error.textContent = "";
    self.updateButton(); });
    this.finish();
  }
  RecordForm.extend(ReplacementForm);
  ReplacementForm.prototype.updateButton = function () {
    this.submitButton.disabled = !this.enabled || this.busy() || (this.inUse && !this.select.value);
  };
  ReplacementForm.prototype.reconcile = function (record, records) {
    this.record = record;
    var usage = this.options.usage ? this.options.usage(this.state, record.id) : null;
    this.inUse = Boolean(this.options.replacement && (this.options.alwaysReplacement ||
      (usage ? usage.count : record.use_count)));
    this.title.textContent = (this.inUse ? "Replace and delete " : "Delete ") + record.values.name;
    var uses = (record.uses || []).map(function (use) { return use.name; }).join(", ");
    this.uses.textContent = this.inUse ? (usage ? usage.description : uses ? "Used by: " + uses :
      "Choose a replacement or clear existing uses.") :
      "Delete " + this.options.label + ' "' + record.values.name + '"?';
    this.select.parentNode.hidden = !this.inUse;
    var selected = this.select.value;
    this.select.setAttribute("aria-label", "Replacement " + this.options.label.toLowerCase());
    this.select.replaceChildren(ui.option("", "Choose a replacement"));
    if (this.options.allowClear) this.select.appendChild(ui.option("__clear__", "Clear existing uses"));
    records.filter(function (candidate) { return candidate.id !== record.id; }).forEach(function (candidate) {
      this.select.appendChild(ui.option(candidate.id, candidate.values.name));
    }, this);
    this.select.value = (selected === "__clear__" && this.options.allowClear) || records.some(function (candidate) {
      return candidate.id === selected;
    }) ? selected : "";
    this.submitButton.textContent = this.inUse ? "Replace and delete" : "Delete";
    this.updateButton();
  };
  ReplacementForm.prototype.open = function (record, records) {
    if (!this.enabled) return;
    this.select.value = "";
    this.reconcile(record, records);
    this.error.textContent = "";
    this.show();
    if (this.inUse) this.select.focus();
    else this.cancel.focus();
  };
  ReplacementForm.prototype.submit = function () {
    this.updateButton();
    if (!this.record || this.submitButton.disabled) return;
    var params = { id: this.record.id, expected_values: { name: this.record.values.name } };
    if (this.inUse) params.replacement_id = this.select.value === "__clear__" ? null : this.select.value;
    this.run(params);
  };
  ReplacementForm.prototype.refresh = function (state) {
    this.state = state;
    var payload = snapshot.value(state, this.options.section), records = payload ? payload.records : [];
    var outcome = refreshForm(this, state, this.options.section);
    if (outcome && outcome.status === "completed") this.hide(outcome.value);
    if (!this.root.hidden && this.record && payload) {
      var record = records.filter(function (entry) { return entry.id === this.record.id; }, this)[0];
      if (!record) this.hide();
      else this.reconcile(record, records);
    }
    this.select.disabled = this.busy();
    this.updateButton();
  };
  ReplacementForm.prototype.dispose = function () { this.enabled = false;
  this.withdraw(); };

  /* Duplicate for a record that draws nothing, so the copy's name is asked for first: a free "(copy)" name,
     selected, and whether to keep the datasheet links. `options`: { section, label }. */
  function DuplicateForm(session, send, changed, options) {
    var self = this;
    this.section = options.section;
    RecordForm.call(this, session, send, { title: "Duplicate " + options.label, action: options.section +
      ".duplicate", label: "duplicate-record", submitLabel: "Duplicate " + options.label,
      pendingText: "Duplicating " + options.label + "...", failureText: "The " + options.label +
      " was not duplicated.", changed: changed });
    this.name = labelled(this.form, options.label + " copy name", ui.element("input"));
    this.copyDatasheets = labelled(this.form, "Copy datasheet links", ui.element("input"));
    this.copyDatasheets.type = "checkbox";
    this.name.addEventListener("input", function () {
      self.submitButton.disabled = self.busy() || !self.name.value.trim();
      self.error.textContent = "";
    });
    this.name.addEventListener("keydown", function (event) {
      if (event.key === "Enter") { event.preventDefault();
      self.submit(); }
    });
    this.finish();
  }
  RecordForm.extend(DuplicateForm);
  DuplicateForm.prototype.open = function (record) {
    if (!this.enabled) return;
    this.record = record;
    var names = this.records.map(function (entry) { return entry.values.name.trim().toLowerCase(); });
    var baseName = record.values.name.trim();
    var number = 1, candidate = baseName + " (copy)";
    while (names.indexOf(candidate.toLowerCase()) >= 0) candidate = baseName + " (copy " + (++number) + ")";
    this.name.value = candidate;
    this.copyDatasheets.checked = false;
    this.submitButton.disabled = false;
    this.show();
    this.name.focus();
    this.name.select();
  };
  DuplicateForm.prototype.submit = function () {
    if (!this.enabled || !this.record || !this.name.value.trim() || this.busy()) return;
    this.run({ id: this.record.id, name: this.name.value.trim(), copy_datasheets: this.copyDatasheets.checked });
  };
  DuplicateForm.prototype.refresh = function (state) {
    this.records = (snapshot.value(state, this.section) || {}).records || [];
    var outcome = refreshForm(this, state, this.section);
    if (outcome && outcome.status === "completed") this.hide(outcome.value);
    this.name.disabled = this.copyDatasheets.disabled = this.busy();
    this.submitButton.disabled = !this.enabled || this.busy() || !this.name.value.trim();
  };
  DuplicateForm.prototype.dispose = function () { this.enabled = false;
  this.withdraw(); };

  function colorHSV(hex, previousHue) {
    var rgb = [1, 3, 5].map(function (offset) { return parseInt(hex.slice(offset, offset + 2), 16) / 255; });
    var max = Math.max.apply(null, rgb);
    var min = Math.min.apply(null, rgb);
    var delta = max - min;
    var hue = previousHue || 0;
    if (delta) {
      hue = max === rgb[0] ? (rgb[1] - rgb[2]) / delta : (max === rgb[1] ? (rgb[2] - rgb[0]) / delta +
        2 : (rgb[0] - rgb[1]) / delta + 4);
      hue = (hue * 60 + 360) % 360;
    }
    return { h: hue, s: max ? delta / max : 0, v: max };
  }
  function colorHex(hsv) {
    var chroma = hsv.v * hsv.s;
    var h = hsv.h / 60;
    var x = chroma * (1 - Math.abs(h % 2 - 1));
    var m = hsv.v - chroma;
    var rgb = [[chroma, x, 0], [x, chroma, 0], [0, chroma, x], [0, x, chroma], [x, 0, chroma], [chroma, 0,
      x]][Math.floor(h) % 6];
    return "#" + rgb.map(function (value) { return ("0" + Math.round((value +
      m) * 255).toString(16)).slice(-2); }).join("");
  }
  function ColorForm(session, send, action, changed) {
    var self = this;
    this.action = action;
    this.changed = changed;
    this.requests = request.channel(session, send, "color");
    this.root = ui.element("div", "phc-form phc-color-form");
    this.root.hidden = true;
    this.root.setAttribute("role", "dialog");
    this.dismissOutside = function (event) {
      if (self.root.hidden || self.root.contains(event.target) || event.target === self.trigger) return;
      if (!self.dirty() && !self.requests.busy()) self.hide(false);
      else if (event.preventDefault) event.preventDefault();
    };
    this.dismissScroll = function (event) {
      if (self.root.contains(event.target)) return;
      if (!self.dirty() && !self.requests.busy()) self.hide(false);
      else self.position();
    };
    this.resize = function () { self.position(); };
    this.title = ui.element("h2");
    this.root.appendChild(this.title);
    this.palette = ui.element("div", "phc-color-palette");
    this.palette.setAttribute("role", "group");
    this.palette.setAttribute("aria-label", "Color swatches");
    this.swatches = [];
    [
      ["White", "#ffffff"], ["Light gray", "#e0e0e0"], ["Gray", "#9e9e9e"], ["Charcoal", "#424242"],
      ["Cream", "#fff2cc"], ["Sand", "#e6c99c"], ["Wood", "#c69c6d"], ["Brown", "#8d6e63"],
      ["Light blue", "#bbdefb"], ["Blue", "#64a4d8"], ["Light green", "#c5e1a5"], ["Green", "#81a784"],
      ["Yellow", "#ffe082"], ["Orange", "#ffb480"], ["Rose", "#e6a5a5"], ["Lavender", "#c5b4dc"]
    ].forEach(function (entry) {
      var button = ui.button("", function () { self.hex.value = entry[1];
      self.paint(); });
      button.className = "phc-color-swatch";
      button.style.backgroundColor = entry[1];
      button.setAttribute("aria-label", entry[0] + " " + entry[1]);
      ui.tooltip(button, entry[0]);
      self.swatches.push({ button: button, color: entry[1] });
      self.palette.appendChild(button);
    });
    this.root.appendChild(this.palette);
    this.form = ui.element("form");
    this.hex = ui.element("input");
    this.hex.setAttribute("aria-label", "Custom color hex value");
    this.hex.setAttribute("placeholder", "#ffffff");
    this.hex.maxLength = 7;
    this.hsv = { h: 0, s: 0, v: 1 };
    this.custom = ui.element("div", "phc-custom-color");
    this.graphical = ui.element("div", "phc-graphical-color");
    this.square = ui.element("div", "phc-color-square");
    this.square.tabIndex = 0;
    this.square.setAttribute("role", "group");
    this.cursor = ui.element("span", "phc-color-cursor");
    this.cursor.setAttribute("aria-hidden", "true");
    this.square.appendChild(this.cursor);
    this.hue = ui.element("input", "phc-color-hue");
    this.hue.type = "range";
    this.hue.min = "0";
    this.hue.max = "359";
    this.hue.step = "1";
    this.hue.setAttribute("aria-label", "Hue");
    this.graphical.appendChild(this.square);
    this.graphical.appendChild(this.hue);
    this.custom.appendChild(this.graphical);
    var label = ui.element("label", "", "Custom color");
    label.appendChild(this.hex);
    this.preview = ui.element("span", "phc-color-preview");
    this.preview.setAttribute("aria-hidden", "true");
    label.appendChild(this.preview);
    this.custom.appendChild(label);
    this.form.appendChild(this.custom);
    function move(event) {
      var bounds = self.square.getBoundingClientRect();
      self.hsv.s = Math.max(0, Math.min(1, (event.clientX - bounds.left) / bounds.width));
      self.hsv.v = 1 - Math.max(0, Math.min(1, (event.clientY - bounds.top) / bounds.height));
      self.fromGraphical();
    }
    this.square.addEventListener("pointerdown", function (event) {
      if (self.requests.pending || self.enabled === false || event.button !== 0) return;
      event.preventDefault();
      self.square.focus();
      self.square.setPointerCapture(event.pointerId);
      self.dragging = true; move(event);
    });
    this.square.addEventListener("pointermove", function (event) { if (self.dragging) move(event); });
    this.square.addEventListener("pointerup", function () { self.dragging = false; });
    this.square.addEventListener("lostpointercapture", function () { self.dragging = false; });
    this.square.addEventListener("keydown", function (event) {
      if (self.requests.pending || self.enabled === false || ["ArrowLeft", "ArrowRight", "ArrowUp",
        "ArrowDown"].indexOf(event.key) === -1) return;
      event.preventDefault();
      var step = event.shiftKey ? 0.1 : 0.01;
      if (event.key === "ArrowLeft" || event.key === "ArrowRight") self.hsv.s = Math.max(0, Math.min(1,
        self.hsv.s + (event.key === "ArrowRight" ? step : -step)));
      else self.hsv.v = Math.max(0, Math.min(1, self.hsv.v + (event.key === "ArrowUp" ? step : -step)));
      self.fromGraphical();
    });
    this.hue.addEventListener("input", function () { self.hsv.h = Number(self.hue.value);
    self.fromGraphical(); });
    this.apply = ui.element("button", "primary", "Apply Color");
    this.apply.type = "submit";
    this.cancel = ui.button("Cancel", function () { self.hide(); });
    this.form.appendChild(ui.actionRow(this.cancel, this.apply));
    this.error = ui.element("div", "cell-error");
    this.error.setAttribute("role", "status");
    this.form.addEventListener("submit", function (event) { event.preventDefault();
    self.submit(); });
    this.hex.addEventListener("input", function () { self.paint(); });
    this.root.addEventListener("keydown", function (event) { if (event.key === "Escape") { event.preventDefault();
    self.hide(); } });
    this.root.appendChild(this.form);
    this.root.appendChild(this.error);
  }
  ColorForm.prototype.fromGraphical = function () {
    this.hex.value = colorHex(this.hsv);
    this.error.textContent = "";
    this.paint(true);
  };
  ColorForm.prototype.paint = function (keepHSV) {
    var value = this.hex.value.trim().toLowerCase();
    var disabled = this.enabled === false || this.requests.busy();
    this.swatches.forEach(function (swatch) {
      swatch.button.setAttribute("aria-pressed", String(swatch.color === value));
      swatch.button.disabled = disabled;
    });
    if (!keepHSV && /^#[0-9a-f]{6}$/.test(value)) this.hsv = colorHSV(value, this.hsv.h);
    this.square.style.backgroundColor = "hsl(" + this.hsv.h + ", 100%, 50%)";
    this.cursor.style.left = (this.hsv.s * 100) + "%";
    this.cursor.style.top = ((1 - this.hsv.v) * 100) + "%";
    this.square.setAttribute("aria-label", "Saturation " + Math.round(this.hsv.s * 100) + "%, brightness " +
      Math.round(this.hsv.v * 100) + "%. Left/right adjusts saturation; up/down adjusts brightness.");
    this.square.setAttribute("aria-disabled", String(disabled));
    this.square.tabIndex = disabled ? -1 : 0;
    this.hue.value = String(Math.round(this.hsv.h));
    this.hue.disabled = disabled;
    this.preview.style.backgroundColor = colorHex(this.hsv);
    this.hex.disabled = this.cancel.disabled = disabled;
    this.apply.disabled = disabled || !/^#[0-9a-f]{6}$/.test(value);
  };
  ColorForm.prototype.open = function (record, trigger) {
    if (this.enabled === false || this.requests.pending) return;
    if (!this.root.hidden && this.trigger === trigger) { this.hide(); return; }
    if (this.trigger) this.trigger.setAttribute("aria-expanded", "false");
    this.record = JSON.parse(JSON.stringify(record));
    this.trigger = trigger;
    this.hex.value = record.values.color || (record.display || {}).color || "#ffffff";
    this.initialColor = this.hex.value;
    this.title.textContent = "Color for " + record.values.name;
    this.error.textContent = "";
    this.root.setAttribute("aria-label", this.title.textContent);
    this.trigger.setAttribute("aria-expanded", "true");
    this.root.hidden = false;
    this.paint();
    this.position();
    document.body.addEventListener("mousedown", this.dismissOutside, true);
    document.body.addEventListener("focusin", this.dismissOutside, true);
    document.body.addEventListener("scroll", this.dismissScroll, true);
    if (window.addEventListener) window.addEventListener("resize", this.resize);
    this.hex.focus();
    this.hex.select && this.hex.select();
  };
  ColorForm.prototype.position = function () {
    if (this.root.hidden || !this.trigger) return;
    var place = ui.placeNear(this.trigger.getBoundingClientRect(), { width: this.root.offsetWidth || 336,
      height: this.root.offsetHeight || 230 }, 8, 12);
    this.root.style.left = place.left + "px";
    this.root.style.top = place.top + "px";
  };
  ColorForm.prototype.dirty = function () {
    return this.hex.value.trim().toLowerCase() !== this.initialColor || Boolean(this.error.textContent);
  };
  ColorForm.prototype.hide = function (restoreFocus) {
    if (this.requests.pending) return;
    this.root.hidden = true;
    this.record = null;
    this.error.textContent = "";
    document.body.removeEventListener("mousedown", this.dismissOutside, true);
    document.body.removeEventListener("focusin", this.dismissOutside, true);
    document.body.removeEventListener("scroll", this.dismissScroll, true);
    if (window.removeEventListener) window.removeEventListener("resize", this.resize);
    if (this.trigger) {
      this.trigger.setAttribute("aria-expanded", "false");
      if (restoreFocus !== false) this.trigger.focus();
    }
  };
  ColorForm.prototype.dispose = function () {
    this.enabled = false;
    this.requests.reset();
    this.hide(false);
  };
  ColorForm.prototype.submit = function () {
    var value = this.hex.value.trim().toLowerCase();
    if (!this.record || this.requests.pending || this.enabled === false) return;
    if (!/^#[0-9a-f]{6}$/.test(value)) { this.error.textContent = "Enter a color in #rrggbb format."; return; }
    if (value === this.record.values.color) { this.hide(); return; }
    this.requests.run(this.action, { id: this.record.id, values: { color: value },
      expected_values: { color: this.record.values.color || null } });
    this.paint();
    if (this.changed) this.changed();
  };
  ColorForm.prototype.refresh = function (state, enabled, records) {
    this.enabled = enabled;
    if (!enabled || (this.record && !records.some(function (record) {
      return record.id === this.record.id;
    }, this))) {
      this.requests.reset();
      this.hide(false);
      this.paint();
      return;
    }
    var result = this.requests.consume(state);
    if (result && result.status === "completed") this.hide();
    else if (result) this.error.textContent = result.message || "The color was not updated. Cancel and try again.";
    this.paint();
    this.position();
  };
  function colorCell(td, record, form, allowed) {
    if (!td._color) {
      td._color = ui.button("", function () { if (allowed()) form.open(td._record, td._color); });
      td._color.className = "phc-record-color";
      td.replaceChildren(td._color);
    }
    td._record = record;
    var raw = record.values.color || (record.display || {}).color;
    /* Only six-digit hex reaches the style: the schema enforces it on write, and this keeps a value that
       arrived some other way out of the attribute. */
    var color = /^#[0-9A-Fa-f]{6}$/.test(raw) ? raw : "#ffffff";
    td._color.style.backgroundColor = color;
    td._color.setAttribute("aria-label", "Color for " + record.values.name + ": " + color);
    td._color.disabled = !form.enabled || form.requests.busy();
  }
  return { ReplacementForm: ReplacementForm, DuplicateForm: DuplicateForm, ColorForm: ColorForm, colorCell: colorCell,
    labelled: labelled, required: RecordForm.required,
    refreshForm: refreshForm };
});
