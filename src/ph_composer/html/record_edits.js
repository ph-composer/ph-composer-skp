/* Inline record drafts. A commit sends one registered action and remains pending until its correlated
   outcome and authoritative snapshot agree. Refusals retain typed text until the user cancels.
   Required options: action, fields. Catalog rows are { key, record: { id, values } } by default.
   Optional: params, rawValue(row, field), eligible(row, field), enabled(state), readOnly(cell),
   quantities, numericFields, requiredFields, selectFields ({ value, label, fill? } or strings), validate(field, value),
   normalize(field, text),
   send(cell) -> { action, params }, label(row, field, cell), recordLabel, fieldAttribute,
   presentation ("overlay" or "inline"), statusText(cell), textInputs, navigateOnCommit,
   cancelControl (a visible Cancel beside a draft that needs one, for mouse users),
   refusalText(outcome) (the user's words for a refused or failed outcome, or null for the host's).
   The default action params are { id, values, expected_values }; custom send owns its public action shape. */
PhComposerUI.define("record_edits", ["request", "snapshot", "unit_preferences", "units", "workspace"],
  function (request, snapshot, preferences, units, ui) {
    "use strict";
    var errorSequence = 0;

    function Controller(session, send, notice, options) {
      if (!options || !options.action || !Array.isArray(options.fields)) {
        throw new Error("Record edits require an action and a field list.");
      }
      this.params = options.params || {};
      this.validate = options.validate;
      this.normalizeValue = options.normalize;
      this.readOnly = options.readOnly;
      this.quantities = options.quantities || {};
      this.featureEnabled = options.enabled || function () { return true; };
      this.rawValue = options.rawValue || function (row, field) { return row.record.values[field]; };
      this.eligible = options.eligible || function (row, field) { return this.fields.indexOf(field) >= 0; };
      this.requestFor = options.send;
      this.label = options.label;
      this.statusText = options.statusText;
      this.inline = options.presentation === "inline";
      this.textInputs = Boolean(options.textInputs);
      this.navigateOnCommit = options.navigateOnCommit !== false;
      this.cancelControl = Boolean(options.cancelControl);
      this.refusalText = options.refusalText || function () { return null; };
      this.requiredFields = options.requiredFields || [];
      this.notice = notice || function () {};
      this.action = options.action;
      this.fields = options.fields.slice();
      this.fieldAttribute = options.fieldAttribute || "data-record-field";
      this.recordLabel = options.recordLabel || "record";
      this.requests = request.channel(session, send, this.recordLabel);
      this.selectFields = options.selectFields || {};
      this.numericFields = options.numericFields || [];
      this.cells = Object.create(null);
      this.queue = [];
      this.pending = null;
      this.enabled = true;
      this.disposed = false;
      var self = this;
      this.unsubscribePreferences = Object.keys(this.quantities).length ? preferences.subscribe(function () {
        Object.keys(self.cells).forEach(function (key) {
          var cell = self.cells[key];
          if (!self.quantities[cell.field] || cell.status !== "clean") return;
          cell.display = self.display(cell.field, cell.current);
          cell.input.value = cell.display;
          paint(cell);
        });
      }) : null;
    }
    function isSelect(owner, field) { return Boolean(owner.selectFields[field]); }
    function paintOptions(cell) {
      var choices = cell.owner.selectFields[cell.field];
      var value = cell.display;
      cell.input.replaceChildren();
      choices.forEach(function (entry) {
        cell.input.appendChild(ui.option(typeof entry === "string" ? entry : entry.value,
          typeof entry === "string" ? entry : entry.label));
      });
      cell.input.value = value;
    }
    /* A choice may carry a `fill`, the colour its value has across the app (a boundary condition's hue);
       the shared enum pill reads it from --category-fill. */
    function paintFill(cell) {
      var chosen = cell.owner.selectFields[cell.field].filter(function (entry) {
        return typeof entry !== "string" && entry.value === cell.input.value;
      })[0];
      if (chosen && chosen.fill) cell.input.style.setProperty("--category-fill", chosen.fill);
      else cell.input.style.removeProperty("--category-fill");
    }
    Controller.prototype.profile = function (field, supplied) {
      return units.profile(this.quantities[field] || {}, supplied);
    };
    Controller.prototype.display = function (field, value) {
      var quantity = this.quantities[field];
      return quantity ? units.formatEdit(value, quantity, this.profile(field)) : display(value);
    };
    Controller.prototype.normalize = function (field, rawValue, options) {
      if (options && options.canonical) return rawValue;
      var text = rawValue === null || rawValue === undefined ? "" : String(rawValue).trim();
      if (this.normalizeValue) {
        var custom = this.normalizeValue(field, text);
        if (custom !== undefined) return custom;
      }
      var quantity = this.quantities[field];
      if (quantity) {
        var settings = this.profile(field, options && options.profile);
        var parsed = units.parse(text, quantity, units.parseContext(quantity, settings));
        return parsed.ok ? parsed.value : parsed;
      }
      return this.numericFields.indexOf(field) >= 0 ? (text === "" ? null : Number(text)) : text;
    };
    Controller.normalizationError = normalizationError;
    function normalizationError(value) {
      return value && typeof value === "object" && value.ok === false ? value.message : "";
    }
    Controller.prototype.validationError = function (field, value) {
      var error = normalizationError(value);
      if (error) return error;
      if (this.requiredFields.indexOf(field) >= 0 && (value === "" || value === null || value === undefined)) {
        return ui.titleCase(field) + " is required.";
      }
      if (this.numericFields.indexOf(field) >= 0 && value !== null && !Number.isFinite(value)) {
        return "Enter a finite number or leave it blank.";
      }
      return this.validate ? this.validate(field, value) : "";
    };
    function beginDraft(owner, cell) {
      // Typing or paste freezes the units; a display preference never reinterprets existing text.
      if (owner.quantities[cell.field] && !cell.startProfile) cell.startProfile = owner.profile(cell.field);
    }
    function same(a, b) {
      return (a === null || a === undefined ? "" : a) === (b === null || b === undefined ? "" : b);
    }
    function display(value) { return value === null || value === undefined ? "" : String(value); }
    function busy(cell) { return cell.status === "pending" || cell.status === "queued"; }
    Controller.prototype.isReadOnly = function (cell) {
      return this.disposed || cell.disposed || Boolean(this.readOnly && this.readOnly(cell));
    };
    function paint(cell) {
      var owner = cell.owner;
      cell.input.disabled = !owner.enabled || owner.disposed || cell.disposed || Boolean(owner.batchPending);
      cell.input.readOnly = busy(cell) || owner.isReadOnly(cell);
      cell.input.setAttribute("aria-busy", String(busy(cell)));
      cell.input.setAttribute("aria-invalid", String(cell.status === "error"));
      if (isSelect(owner, cell.field)) {
        cell.input.disabled = cell.input.disabled || busy(cell) || owner.isReadOnly(cell);
        paintFill(cell);
      }
      cell.error.textContent = cell.message || (owner.inline && owner.statusText ? owner.statusText(cell) : "");
      cell.error.hidden = !cell.error.textContent;
      // Cancel stays usable on a read-only cell: it writes nothing and only drops the draft.
      if (cell.cancelButton) {
        // A refused or invalid draft needs it; so does a typed one its row turned read only underneath.
        var stranded = cell.status === "error" || cell.status === "dirty" && owner.isReadOnly(cell);
        cell.cancelButton.hidden = !stranded || owner.disposed || Boolean(cell.disposed);
      }
      var td = cell.input.parentNode;
      if (td) td.classList.toggle("has-cell-error", !cell.error.hidden);
    }
    Controller.prototype.cancel = function (cell) {
      if (this.disposed || cell.disposed || cell.status === "pending") return;
      this.queue = this.queue.filter(function (entry) { return entry !== cell; });
      cell.baseline = cell.current;
      cell.display = this.display(cell.field, cell.current);
      cell.input.value = cell.display;
      cell.startProfile = null;
      cell.status = "clean";
      cell.requiresCancel = false;
      cell.message = "";
      paint(cell);
    };
    /* Drops every draft that is not in flight: an owner's "cancel the edit" route. */
    Controller.prototype.cancelAll = function () {
      Object.keys(this.cells).forEach(function (key) {
        if (this.cells[key].status !== "clean") this.cancel(this.cells[key]);
      }, this);
    };
    Controller.prototype.commit = function (cell) {
      if (!this.enabled || this.isReadOnly(cell) || busy(cell) || cell.status === "error") return;
      if (cell.input.value === cell.display) { this.cancel(cell); return; }
      var value = this.normalize(cell.field, cell.input.value, { profile: cell.startProfile });
      var error = this.validationError(cell.field, value);
      if (error) { cell.status = "error"; cell.message = error; paint(cell); return; }
      if (same(value, cell.baseline)) { this.cancel(cell); return; }
      cell.submitted = value;
      cell.status = "queued";
      this.queue.push(cell);
      paint(cell);
      this.flush();
    };
    Controller.prototype.changeFor = function (cell, value) {
      var values = {}, expected = {};
      values[cell.field] = value;
      expected[cell.field] = cell.baseline === undefined ? null : cell.baseline;
      return { id: cell.row.record.id, values: values, expected_values: expected };
    };
    Controller.prototype.flush = function () {
      if (this.disposed || this.pending || !this.enabled || !this.queue.length) return;
      var cell = this.queue.shift();
      if (cell.status !== "queued" || this.isReadOnly(cell)) { this.flush(); return; }
      this.pending = cell;
      cell.status = "pending";
      paint(cell);
      var outgoing = this.requestFor ? this.requestFor(cell) : {
        action: this.action, params: Object.assign({}, this.params, this.changeFor(cell, cell.submitted))
      };
      cell.request = this.requests.nextId();
      this.requests.dispatch(cell.request, outgoing.action, outgoing.params);
    };
    Controller.prototype.refresh = function (rows, state) {
      if (this.disposed) return;
      var self = this, live = Object.create(null), result = snapshot.actionResult(state);
      this.enabled = Boolean(this.featureEnabled(state));
      rows.forEach(function (row) {
        self.fields.forEach(function (field) {
          live[row.key + ":" + field] = { row: row, value: self.rawValue(row, field) };
        });
      });
      Object.keys(this.cells).forEach(function (key) {
        var cell = self.cells[key], next = live[key];
        if (!next) {
          if (cell.status !== "clean") self.notice("An edited " + self.recordLabel + " was removed.");
          cell.disposed = true;
          paint(cell);
          if (self.pending === cell) self.pending = null;
          self.queue = self.queue.filter(function (entry) { return entry !== cell; });
          delete self.cells[key];
          return;
        }
        if (!same(next.value, cell.current)) cell.display = self.display(cell.field, next.value);
        cell.row = next.row;
        cell.current = next.value;
        if (cell.status === "pending" && self.requests.matches(result, cell.request)) {
          self.pending = null;
          if (result.outcome.status !== "completed") {
            cell.status = "error";
            cell.requiresCancel = true;
            cell.message = self.refusalText(result.outcome) ||
              snapshot.message(result.outcome, "The edit was not applied.");
          } else if (same(next.value, cell.submitted)) {
            cell.status = "dirty";
            self.cancel(cell);
          }
          else {
            cell.status = "error";
            cell.requiresCancel = true;
            cell.message = "The Model differs from this draft. Escape to cancel and re-edit.";
          }
        } else if (cell.status !== "pending" && !same(next.value, cell.baseline)) {
          if (cell.status === "clean") { cell.baseline = next.value; cell.input.value = cell.display; }
          else {
            cell.status = "error";
            cell.requiresCancel = true;
            cell.message = "Changed in the Model. Escape to cancel and re-edit.";
          }
        }
        paint(cell);
      });
      this.flush();
    };
    Controller.prototype.render = function (td, row, field) {
      if (this.disposed || !this.eligible(row, field)) return false;
      var key = row.key + ":" + field, cell = this.cells[key], self = this;
      if (!cell) {
        var value = this.rawValue(row, field);
        cell = { owner: this, row: row, field: field, baseline: value, current: value,
          display: this.display(field, value), status: "clean", message: "",
          input: ui.element(isSelect(this, field) ? "select" : "input"),
          error: ui.element("small", this.inline ? "phc-cell-status" : "cell-error") };
        this.cells[key] = cell;
        cell.input.value = cell.display;
        if (isSelect(this, field)) { cell.input.className = "phc-enum-cell"; paintOptions(cell); }
        if (!isSelect(this, field)) {
          cell.input.setAttribute("type", "text");
          if (this.quantities[field] || this.textInputs) cell.input.setAttribute("inputmode", "decimal");
          cell.input.setAttribute("spellcheck", "false");
          cell.input.setAttribute("autocomplete", "off");
        }
        cell.input.classList.add("phc-cell-input");
        cell.error.setAttribute("id", "phc-cell-error-" + (++errorSequence));
        cell.error.setAttribute("role", "alert");
        cell.input.setAttribute("aria-describedby", cell.error.id);
        cell.input.setAttribute(this.fieldAttribute, field);
        if (this.cancelControl) {
          cell.cancelButton = ui.iconButton("Cancel edit", "clear", function () {
            self.cancel(cell);
          });
          cell.cancelButton.classList.add("phc-cell-cancel");
          cell.cancelButton.hidden = true;
        }
        cell.input.addEventListener("input", function () {
          if (self.isReadOnly(cell) || busy(cell)) return;
          if (!cell.requiresCancel) {
            beginDraft(self, cell);
            cell.status = "dirty";
            cell.message = "";
            paint(cell);
          }
        });
        cell.input.addEventListener("paste", function () {
          if (!self.isReadOnly(cell) && !busy(cell)) beginDraft(self, cell);
        });
        if (isSelect(this, field)) cell.input.addEventListener("change", function () {
          if (self.isReadOnly(cell) || busy(cell) || cell.requiresCancel) return;
          cell.status = "dirty";
          self.commit(cell);
        });
        cell.input.addEventListener("keydown", function (event) {
          if (event.defaultPrevented) return;
          if (event.key === "Escape") { event.preventDefault(); self.cancel(cell); }
          if (isSelect(self, field) || (event.key !== "Enter" && event.key !== "Tab")) return;
          if (event.key === "Enter") event.preventDefault();
          self.commit(cell);
          if (event.key !== "Tab" || !self.navigateOnCommit) return;
          var inputs = Object.keys(self.cells).map(function (entry) { return self.cells[entry].input; })
            .filter(function (input) {
              for (var node = input; node && node !== document; node = node.parentNode) {
                if (node.hidden || input.disabled) return false;
              }
              return input.isConnected;
            });
          var next = inputs[inputs.indexOf(cell.input) + (event.shiftKey ? -1 : 1)];
          if (next) { event.preventDefault(); next.focus(); }
        });
        cell.input.addEventListener("blur", function () { self.commit(cell); });
      }
      if (cell.input.parentNode !== td) {
        td.replaceChildren.apply(td, [cell.input].concat(cell.cancelButton ? [cell.cancelButton] : [], [cell.error]));
      }
      td.classList.add("phc-editable-cell");
      cell.row = row;
      cell.input.setAttribute("aria-label", this.label ? this.label(row, field, cell) :
        ((row.record.values || {}).name || row.record.id) + " " + ui.titleCase(field));
      if (cell.cancelButton) ui.paintIconButton(cell.cancelButton, "Cancel " + cell.input.getAttribute("aria-label") +
        " edit", "clear");
      paint(cell);
      return true;
    };
    Controller.prototype.dispose = function () {
      this.disposed = true;
      this.queue = [];
      this.pending = null;
      if (this.unsubscribePreferences) this.unsubscribePreferences();
      this.unsubscribePreferences = null;
      Object.keys(this.cells).forEach(function (key) { paint(this.cells[key]); }, this);
    };
    return Controller;
  });
