/* The values an equipment row keeps behind a disclosure (a Ventilator's subsoil heat exchanger and preheated
   intake temperature, a Pump's internal heat gain values, a Fan's electric values), so they stay off the row. The
   row's action opens them in a bubble anchored to it, one field each; the action is pressed while any of them is
   set, and its tooltip names them, so a closed row still shows they are there. A value is set while it is present
   and, for a field with a `defaultValue`, differs from it.

   A field is a unit field (`field`, a unit descriptor; `placeholder(record)` is what its empty input shows, such as
   the value a blank stands for, and describes the field to assistive technology beside its error) or a choice
   (`choices(record)`, [{ value, label }], whose value "" stands for null and `parse(text)` gives the stored value). A
   unit field applies on Enter or leaving, a
   choice when it changes, each as its own guarded update (`expected_values` the value it showed), one Undo step; a
   blank removes the value. Escape restores a unit field, and Escape again closes. A refusal stays in the bubble
   beside its field until the next edit, through a repaint or a unit switch; a refused unit field keeps the text
   typed, still guarded by the value it was sent against. One value is out at a time.

   new OptionalValues(session, send, { action, family, title, unset, fields: [{ key, label, field | choices, parse,
   placeholder, defaultValue }], notify }): `title` heads the bubble before the record's name ("Optional values"),
   `unset` is the summary while none is set ("None set"); with set(record), summary(record), open(record, trigger,
   layer), refresh(state, records), guard(), dispose(). */
PhComposerUI.define("features/mechanical/optional_values", ["workspace", "unit_field", "units", "unit_preferences",
  "request", "snapshot"],
function (ui, unitFields, units, preferences, request, snapshot) {
  "use strict";
  var hints = 0;

  function present(value) { return value !== null && value !== undefined; }
  function stored(record, key) { return present(record.values[key]) ? record.values[key] : null; }
  function isSet(record, entry) {
    var value = record.values[entry.key];
    return present(value) && (entry.defaultValue === undefined || value !== entry.defaultValue);
  }

  /* A choice in the bubble with what OptionalValues uses of a unit field: it applies when it changes, and nothing is
     ever left half typed in it. */
  function ChoiceField(entry, record, onCommit) {
    var self = this;
    this.entry = entry;
    this.editing = false;
    this.root = ui.element("span", "mech-optional-choice");
    this.input = ui.element("select", "phc-enum-cell");
    this.error = ui.element("small", "cell-error phc-unit-error");
    this.error.hidden = true;
    this.error.setAttribute("role", "alert");
    this.root.appendChild(this.input);
    this.root.appendChild(this.error);
    this.paint(record);
    this.input.addEventListener("change", function () {
      self.error.hidden = true;
      self.input.setAttribute("aria-invalid", "false");
      onCommit(self.input.value === "" ? null : entry.parse(self.input.value));
    });
  }
  /* Its choices for `record`, whose labels can name the record's own values ("From type (Winter)"), drawn again
     only when they change, so a repaint leaves an open list as it is. */
  ChoiceField.prototype.paint = function (record) {
    var input = this.input, choices = this.entry.choices(record), listed = JSON.stringify(choices);
    if (this.listed !== listed) {
      this.listed = listed;
      input.replaceChildren();
      choices.forEach(function (choice) { input.appendChild(ui.option(choice.value, choice.label)); });
    }
    this.setValue(record.values[this.entry.key]);
  };
  ChoiceField.prototype.setValue = function (value) { this.input.value = present(value) ? String(value) : ""; };
  ChoiceField.prototype.setDisabled = function (disabled) { this.input.disabled = Boolean(disabled); };
  ChoiceField.prototype.commit = function () {};
  ChoiceField.prototype.begin = function () {};
  ChoiceField.prototype.dispose = function () {};

  function OptionalValues(session, send, options) {
    this.options = options;
    this.requests = request.channel(session, send, "mechanical-optional-values");
    this.held = null;
  }
  OptionalValues.prototype.set = function (record) {
    return this.options.fields.some(function (entry) { return isSet(record, entry); });
  };
  /* "Subsoil heat exchanger 0.2; Preheated intake temperature 5 °C", or what the action offers while none is set. */
  OptionalValues.prototype.summary = function (record) {
    var parts = this.options.fields.filter(function (entry) { return isSet(record, entry); })
      .map(function (entry) {
        var value = record.values[entry.key];
        if (entry.choices) {
          var chosen = entry.choices(record).filter(function (choice) { return choice.value === String(value); })[0];
          return entry.label + " " + (chosen ? chosen.label : value);
        }
        return entry.label + " " + units.format(value, entry.field, units.profile(entry.field, preferences.current()));
      });
    return parts.length ? parts.join("; ") : this.options.unset || "None set";
  };
  OptionalValues.prototype.busy = function () { return this.requests.busy(); };
  OptionalValues.prototype.guard = function () {
    if (this.busy()) return "Wait for the " + this.options.family + " value to be saved.";
    var editing = this.held && this.held.fields.some(function (entry) { return entry.unit.editing; });
    return editing ? "Finish the optional value, or press Escape." : null;
  };
  OptionalValues.prototype.open = function (record, trigger, layer) {
    if (this.held && this.held.record.id === record.id) { this.close(true); return; }
    if (!this.close(false)) return;
    var self = this, bubble = new ui.Bubble(trigger, (this.options.title || "Optional values") + " of " +
      record.values.name,
      { detachedTrigger: true, ownTrigger: true });
    bubble.root.classList.add("mech-optional-values");
    var originalClose = bubble.close;
    // Closing applies a field's draft, as leaving it does; an invalid one, or the write it sends, keeps it open.
    // While a value is out nothing else is sent: the bubble waits for its answer.
    bubble.close = function (focus) {
      if (self.held && !self.busy()) {
        self.held.fields.forEach(function (entry) { if (entry.unit.editing) entry.unit.commit(); });
      }
      // A draft the close just sent closes the bubble once its write lands; an invalid one keeps it open.
      if (self.busy() && self.held) self.held.closing = focus !== false;
      if (self.guard()) return false;
      var closed = originalClose.call(bubble, focus);
      if (closed !== false) self.release();
      return closed;
    };
    var fields = this.options.fields.map(function (entry) {
      var label = ui.element("label", "mech-optional-field"), held = { key: entry.key, entry: entry };
      if (entry.choices) {
        held.unit = new ChoiceField(entry, record, function (value) { held.refusal = null; self.apply(held, value); });
        held.unit.input.setAttribute("aria-label", entry.label);
        label.appendChild(ui.element("span", "", entry.label));
        label.appendChild(held.unit.root);
        held.label = label;
        return held;
      }
      held.unit = new unitFields.UnitField({ field: entry.field, value: record.values[entry.key], commitOnBlur: true,
        onCommit: function (value, draft) { self.apply(held, value, draft); },
        onCancel: function () { held.base = undefined; held.refusal = null; } });
      held.unit.input.setAttribute("aria-label", entry.label);
      if (entry.placeholder) {
        held.hint = ui.element("span", "", entry.placeholder(record));
        held.hint.id = "mech-optional-hint-" + (hints += 1);
        held.hint.setAttribute("id", held.hint.id);
        held.hint.hidden = true;
        held.unit.input.placeholder = held.hint.textContent;
        held.unit.input.setAttribute("aria-describedby", held.unit.error.id + " " + held.hint.id);
        held.unit.root.appendChild(held.hint);
      }
      // The value the draft started from is its guard, whatever a snapshot shows meanwhile. A draft that ends
      // without a write (typed back, Escape) drops it, and typing clears a refusal shown on the field.
      held.unit.input.addEventListener("input", function () {
        held.refusal = null;
        if (held.base === undefined && self.held) held.base = stored(self.held.record, entry.key);
      });
      function ended() { if (!held.unit.editing && self.pending !== held) held.base = undefined; }
      held.unit.input.addEventListener("keydown", function (event) { if (event.key === "Enter") ended(); });
      held.unit.input.addEventListener("blur", ended);
      label.appendChild(ui.element("span", "", entry.label));
      label.appendChild(held.unit.root);
      held.label = label;
      return held;
    });
    bubble.content.replaceChildren.apply(bubble.content, fields.map(function (held) { return held.label; }));
    (layer || document.body).appendChild(bubble.root);
    this.held = { record: record, bubble: bubble, fields: fields };
    // A unit switch repaints each field, which clears its message, so the refusals are shown again after it.
    this.held.unsubscribe = preferences.subscribe(function () { self.paint(); });
    bubble.open();
  };
  OptionalValues.prototype.close = function (focus) {
    if (!this.held) return true;
    return this.held.bubble.close(focus) !== false;
  };
  OptionalValues.prototype.release = function () {
    var held = this.held;
    this.held = null;
    if (!held) return;
    held.unsubscribe();
    held.fields.forEach(function (entry) { entry.unit.dispose(); });
    if (held.bubble.root.parentNode) held.bubble.root.parentNode.removeChild(held.bubble.root);
  };
  /* One value, guarded by what the field showed before the edit; `draft` is what a unit field had typed. A value
     committed while another is out is not sent: it stays a draft. */
  OptionalValues.prototype.apply = function (held, value, draft) {
    var record = this.held.record, values = {}, expected = {};
    values[held.key] = value;
    expected[held.key] = held.base !== undefined ? held.base : stored(record, held.key);
    if (this.busy()) { this.redraft(held, draft, expected[held.key]); return; }
    held.base = undefined; held.refusal = null;
    held.sent = { guard: expected[held.key], draft: draft };
    this.pending = held;
    this.requests.run(this.options.action, { id: record.id, values: values, expected_values: expected });
    this.paint();
    if (this.options.changed) this.options.changed();
  };
  /* A unit field's draft back over the Model's value, guarded by `guard`; a choice holds no draft, so it shows the
     Model's value. */
  OptionalValues.prototype.redraft = function (held, draft, guard) {
    var record = this.held.record, model = record.values[held.key];
    if (held.entry.choices) { held.unit.paint(record); return; }
    held.unit.baseline = present(model) ? model : null;
    held.unit.restore(draft);
    held.base = guard;
  };
  OptionalValues.prototype.paint = function () {
    var self = this, held = this.held;
    if (!held) return;
    held.fields.forEach(function (entry) {
      entry.unit.setDisabled(self.busy());
      // The value being written shows until its answer arrives.
      if (self.pending === entry && self.busy()) return;
      // A choice holds no draft, so it always shows the Model's value; its refusal message stays beside it.
      if (entry.entry.choices) { entry.unit.paint(held.record); refuse(entry); return; }
      if (entry.hint) {
        entry.hint.textContent = entry.entry.placeholder(held.record);
        entry.unit.input.placeholder = entry.hint.textContent;
      }
      // A refusal stays on a unit field, with what the user typed, until they edit or cancel it. A field holding no
      // draft follows the snapshot, so its next write is guarded by the value it shows; its message stays.
      if (!entry.unit.editing) entry.unit.setValue(held.record.values[entry.key]);
      refuse(entry);
    });
  };
  /* A field's refusal beside it, from the bubble's own record of it. */
  function refuse(entry) {
    if (!entry.refusal) return;
    entry.unit.error.textContent = entry.refusal;
    entry.unit.error.hidden = false;
    entry.unit.input.setAttribute("aria-invalid", "true");
  }
  OptionalValues.prototype.refresh = function (state, records) {
    var outcome = this.requests.consume(state), held = this.held, pending = this.pending;
    if (outcome) this.pending = null;
    if (!held) return;
    var record = (records || []).filter(function (entry) { return entry.id === held.record.id; })[0];
    if (!record && !this.busy()) { this.dismiss(); return; }
    if (record) held.record = record;
    if (outcome && outcome.status !== "completed" && pending) {
      held.closing = false;
      // The value changed meanwhile: start again from the Model's. Anything else keeps the typed text as a draft,
      // still guarded by the value it was sent against, so a retry over a value changed since refuses too.
      if (outcome.code === "target.changed") pending.unit.setValue(held.record.values[pending.key]);
      else this.redraft(pending, pending.sent.draft, pending.sent.guard);
      pending.refusal = snapshot.message(outcome, "The value was not saved.");
      this.paint();
      return;
    }
    this.paint();
    if (outcome && held.closing) this.close(true);
  };
  /* A Ventilator or a view that is gone sends nothing: a field's draft is dropped, not applied. */
  OptionalValues.prototype.dismiss = function () {
    if (!this.held) return;
    this.held.fields.forEach(function (entry) { entry.unit.editing = false; });
    this.release();
  };
  OptionalValues.prototype.dispose = function () {
    this.requests.reset();
    this.dismiss();
  };
  /* The row action the bubble hangs from is drawn again with its row; the open bubble follows it. */
  OptionalValues.prototype.retarget = function (trigger) {
    if (this.held && trigger) this.held.bubble.trigger = trigger;
  };
  return { OptionalValues: OptionalValues };
});
