/* Shared unit-bearing text input. Owners retain commands, pending state and transaction rules.

   The field shows its stored SI value in the current display units and parses what the user types. The first
   keystroke or paste fixes the unit context the draft is read in: a unit switch during an unfinished edit
   keeps the draft text and its starting unit until Enter or Escape. Presentation is one-way: focus,
   blur, a repaint and a switch never hand a rounded display value back to the owner. */
PhComposerUI.define("unit_field", ["unit_preferences", "units", "workspace"], function (preferences, units, ui) {
  "use strict";

  var sequence = 0;

  function cloneProfile(field) {
    var resolved = units.profile(field);
    return {
      system: resolved.system,
      numberFormat: Object.assign({}, resolved.numberFormat || {}, {
        groupSizes: ((resolved.numberFormat || {}).groupSizes || [3]).slice()
      }),
      dimensionFormat: resolved.dimensionFormat
    };
  }

  function Field(options) {
    var self = this;
    options = options || {};
    this.field = options.field || {};
    this.baseline = options.value === undefined ? null : options.value;
    this.onCommit = options.onCommit || function () {};
    this.onCancel = options.onCancel || function () {};
    this.commitOnBlur = Boolean(options.commitOnBlur);
    this.root = ui.element("span", "phc-unit-field");
    this.input = options.input || ui.element("input");
    this.unit = ui.element("span", "phc-unit-label");
    this.error = ui.element("small", "cell-error phc-unit-error");
    this.error.id = "phc-unit-error-" + (++sequence);
    this.error.setAttribute("id", this.error.id);
    this.error.setAttribute("role", "alert");
    this.input.type = "text";
    this.input.setAttribute("type", "text");
    this.input.setAttribute("inputmode", "decimal");
    this.input.setAttribute("spellcheck", "false");
    this.input.setAttribute("autocomplete", "off");
    this.input.setAttribute("aria-describedby", this.error.id);
    if (this.field.label) this.input.setAttribute("aria-label", this.field.label);
    if (options.forms) this.buildFormChoice();
    this.root.appendChild(this.input); this.root.appendChild(this.formChoice || this.unit);
    this.root.appendChild(this.error);
    this.input.addEventListener("input", function () { self.begin(); self.clearError(); });
    this.input.addEventListener("paste", function () { self.begin(); });
    // Escape is the field's only while a draft is open; otherwise it reaches the dialog or bubble around it.
    this.input.addEventListener("keydown", function (event) {
      if (event.key === "Escape" && self.editing) { event.preventDefault(); self.cancel(); }
      if (event.key === "Enter") { event.preventDefault(); self.commit(); }
    });
    // Leaving the field applies the draft, but a blur caused by the page removing or moving the input (a
    // repaint, a Model switch) is not the user leaving it: the draft stays and nothing is sent.
    this.input.addEventListener("blur", function () {
      if (self.commitOnBlur && self.input.isConnected) self.commit();
    });
    this.unsubscribe = preferences.subscribe(function () { if (!self.editing) self.repaint(); });
    this.repaint();
  }

  /* The input-form selector, in the unit label's place: the number typed is read in the chosen form. Choosing
     another form keeps the text and rereads it, so a value typed before the choice is not converted. Until the
     user chooses, the form follows the unit system. The field holds its own copy of the descriptor, because
     owners share theirs with a table. */
  Field.prototype.buildFormChoice = function () {
    var self = this;
    this.field = Object.assign({}, this.field);
    this.root.classList.add("has-input-form");
    this.formChoice = ui.element("select", "phc-choice-pill phc-unit-form");
    this.formChoice.setAttribute("aria-label", (this.field.label || "Value") + " input form");
    units.inputForms(this.field).forEach(function (entry) {
      self.formChoice.appendChild(ui.option(entry.id, entry.label));
    });
    this.formChoice.addEventListener("change", function () {
      self.formChosen = true; self.field.inputForm = self.formChoice.value; self.clearError();
      // The number on screen now means something else, so it is a draft even if it was committed a moment ago.
      self.editing = false;
      if (self.input.value !== "" || self.baseline !== null) self.begin();
    });
    this.followSystem();
  };
  Field.prototype.followSystem = function () {
    if (!this.formChoice || this.formChosen) return;
    this.field.inputForm = this.formChoice.value = units.defaultInputForm(this.field);
  };

  Field.prototype.begin = function () {
    if (this.editing) return;
    this.editing = true; this.startProfile = cloneProfile(this.field);
    this.seed = units.formatEdit(this.baseline, this.field, this.startProfile);
    this.unit.textContent = units.displayUnit(this.field, this.startProfile);
  };

  Field.prototype.clearError = function () {
    this.error.textContent = ""; this.error.hidden = true; this.input.setAttribute("aria-invalid", "false");
  };

  Field.prototype.repaint = function () {
    var current = cloneProfile(this.field);
    this.followSystem();
    this.input.value = units.formatEdit(this.baseline, this.field, current);
    this.unit.textContent = units.displayUnit(this.field, current);
    this.seed = this.input.value; this.clearError();
  };

  Field.prototype.parse = function () {
    var start = this.startProfile || cloneProfile(this.field);
    return units.parse(this.input.value, this.field, units.parseContext(this.field, start));
  };

  Field.prototype.commit = function () {
    var parsed;
    if (this.disposed) return { ok: true, changed: false, value: this.baseline };
    if (!this.editing || this.input.value === this.seed) {
      this.editing = false; this.startProfile = null; this.repaint();
      return { ok: true, changed: false, value: this.baseline };
    }
    parsed = this.parse();
    if (!parsed.ok) {
      this.error.textContent = parsed.message;
      this.error.hidden = false;
      this.input.setAttribute("aria-invalid", "true");
      return parsed;
    }
    this.editing = false; this.startProfile = null; this.clearError();
    if (parsed.value === this.baseline) { this.repaint(); return { ok: true, changed: false, value: this.baseline }; }
    this.baseline = parsed.value; this.repaint(); this.onCommit(parsed.value);
    return { ok: true, changed: true, value: parsed.value };
  };

  Field.prototype.cancel = function () {
    this.editing = false; this.startProfile = null; this.repaint(); this.onCancel(this.baseline);
  };

  Field.prototype.setValue = function (value) {
    this.baseline = value === undefined ? null : value;
    if (!this.editing) this.repaint();
  };

  Field.prototype.setDisabled = function (disabled) { this.input.disabled = Boolean(disabled); };
  /* A disposed field belongs to a view that is gone (another Model, a removed record): it never commits. */
  Field.prototype.dispose = function () {
    this.disposed = true;
    if (this.unsubscribe) this.unsubscribe();
    this.unsubscribe = null;
  };

  /* The dimension format chooser for one declared dimension scope. The owning toolbar chooses placement; this
     helper owns the active-system choices, accessible state and focus return. `choose(format, system)` records
     the choice (the panel's `setPreference("dimension_format", ...)`). */
  function DimensionFormatControl(scope, choose, menu) {
    var system = preferences.current().unitSystem;
    var active = preferences.dimensionFormat(scope, system);
    var available = units.dimensionFormats.filter(function (entry) { return entry.system === system; });
    var selected = available.filter(function (entry) { return entry.id === active; })[0] || available[0];
    active = selected.id;
    var label = "Dimension format: " + selected.label;
    // Given a "…" menu the control is a submenu row; otherwise a toolbar icon.
    var trigger = menu ? ui.button("") : ui.iconButton(label, "ruler");
    if (menu) {
      trigger.className = "phc-action-menu-item"; ui.tooltip(trigger, label); trigger.setAttribute("aria-label", label);
      trigger.replaceChildren(ui.glyph("ruler"), ui.element("span", "", "Dimension format"),
        ui.element("small", "phc-menu-state", selected.id));
      menu.trigger.setAttribute("data-dimension-format-menu", scope);
    }
    var bubble = new ui.Bubble(trigger, "Dimension format", menu ? { parent: menu.bubble, hover: true } : undefined);
    trigger.setAttribute("data-dimension-format-scope", scope);
    trigger.setAttribute("data-editor-local", "");
    available.forEach(function (entry) {
      var choice = ui.button(entry.label, function () {
        bubble.close(false); if (menu) menu.bubble.close(false);
        choose(entry.id, system);
        var replacement = document.querySelector(menu ? "[data-dimension-format-menu='" + scope + "']" :
          "[data-dimension-format-scope='" + scope + "']");
        if (replacement) replacement.focus({ preventScroll: true });
      });
      choice.setAttribute("aria-pressed", String(entry.id === active));
      choice.setAttribute("data-dimension-format", entry.id);
      bubble.content.appendChild(choice);
    });
    return bubble;
  }

  /* One quantity draft in an anchored bubble. Owners retain the command and its pending state;
     all entry/leave routes share commit, and only an accepted callback releases the draft. */
  function ValueBubble(options) {
    var self = this;
    this.options = options; this.sequence = 0; this.disposed = false;
    this.bubble = options.bubble || new ui.Bubble(options.trigger, options.title, options.bubbleOptions);
    this.originalClose = this.bubble.close;
    this.field = new Field({ field: options.field, value: options.value, onCancel: function () {
      if (self.disposed) return;
      if (options.onCancel) options.onCancel(); self.close(true);
    } });
    this.field.input.setAttribute("aria-label", options.title);
    this.field.commit = function () { return self.commit(true); };
    this.field.input.addEventListener("blur", function () {
      if (self.field.input.isConnected) self.commit(Boolean(options.blurFocus));
    });
    this.bubble.close = function (focus) { return self.close(focus); };
    this.bubble.content.appendChild(this.field.root);
  }
  ValueBubble.prototype.busy = function () { return Boolean(this.options.busy && this.options.busy()); };
  ValueBubble.prototype.active = function () {
    return !this.disposed && (!this.options.active || this.options.active());
  };
  ValueBubble.prototype.refuse = function (message, focus) {
    if (!this.active()) return;
    this.field.error.textContent = message; this.field.error.hidden = false;
    this.field.input.setAttribute("aria-invalid", "true"); this.field.setDisabled(this.busy());
    if (focus) this.field.input.focus();
  };
  ValueBubble.prototype.accept = function (value, focus) {
    if (!this.active()) return;
    this.field.editing = false; this.field.startProfile = null;
    this.field.setValue(value); this.field.setDisabled(false);
    this.finish(focus);
  };
  ValueBubble.prototype.commit = function (focus) {
    if (!this.active() || this.busy()) return false;
    var field = this.field;
    if (!field.editing || field.input.value === field.seed) {
      this.accept(field.baseline, focus); return true;
    }
    var parsed = field.parse();
    if (!parsed.ok) { this.refuse(parsed.message); return false; }
    if (parsed.value === field.baseline) { this.accept(field.baseline, focus); return true; }
    var self = this, sequence = ++this.sequence;
    try {
      this.options.apply(parsed.value, function () {
        if (sequence === self.sequence) self.accept(parsed.value, focus);
      });
    } catch (error) { this.refuse(error.message); return false; }
    if (this.active()) field.setDisabled(this.busy());
    return !field.editing;
  };
  ValueBubble.prototype.close = function (focus) {
    if (this.disposed) return false;
    if (!this.active()) return this.finish(focus);
    if (this.busy()) return false;
    if (this.field.editing) return this.commit(focus);
    return this.finish(focus);
  };
  ValueBubble.prototype.finish = function (focus) {
    var closed = this.originalClose.call(this.bubble, focus);
    if (closed && this.options.once) this.dispose();
    if (closed && this.options.onClose) this.options.onClose();
    return closed;
  };
  ValueBubble.prototype.dispose = function () {
    if (this.disposed) return;
    this.disposed = true; this.sequence += 1; this.field.editing = false; this.field.dispose();
    this.originalClose.call(this.bubble, false);
  };

  return { UnitField: Field, ValueBubble: ValueBubble, DimensionFormatControl: DimensionFormatControl };
});
