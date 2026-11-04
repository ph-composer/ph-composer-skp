/* Visible-cell gestures share the record editor and one authoritative Model batch action.
   options: edits (RecordEdits), scroll, root or toolbarParent, hiddenColumns(), notify(message),
   isBusy(), submitBatch(changes), optional ensureCurrent() and changeFor(cell, value).
   Default changes are { id, values: { field: value }, expected_values: { field: current } }.
   The owner sends the batch through its request channel and owns its outcome and transaction. */
PhComposerUI.define("inventory_grid", ["record_edits", "workspace"], function (RecordEdits, ui) {
  "use strict";
  // Stop at the table container: document.hidden means the host window is occluded, not a hidden row.
  function visible(node, stop) {
    for (; node && node !== stop; node = node.parentNode) if (node.hidden) return false;
    return true;
  }
  function nativeSelect(cell) { return cell.input.tagName.toLowerCase() === "select"; }
  function escapeHTML(value) {
    return String(value).replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/"/g, "&quot;");
  }
  function encode(value) {
    var text = value === null || value === undefined ? "" : String(value);
    return /[\t\n\r"]/.test(text) ? '"' + text.replace(/"/g, '""') + '"' : text;
  }
  function parse(text) {
    var rows = [], row = [], cell = "", quoted = false;
    for (var i = 0; i < text.length; i += 1) {
      var char = text[i];
      if (char === '"' && (quoted || cell === "")) {
        if (quoted && text[i + 1] === '"') { cell += '"'; i += 1; }
        else quoted = !quoted;
      } else if (!quoted && (char === "\t" || char === "\n" || char === "\r")) {
        row.push(cell);
        cell = "";
        if (char !== "\t") {
          rows.push(row);
          row = [];
          if (char === "\r" && text[i + 1] === "\n") i += 1;
        }
      } else cell += char;
    }
    if (quoted) throw new Error("The pasted text has an unclosed quote.");
    if (cell || row.length || !rows.length) { row.push(cell); rows.push(row); }
    return rows;
  }
  function Grid(options) {
    this.options = options;
    this.disposed = false;
    this.anchor = null;
    this.end = null;
    this.editing = null;
    this.cells = [];
    options.edits.grid = this;
    var self = this;
    this.toolbar = ui.element("div", "phc-grid-toolbar");
    var tools = ui.element("div", "phc-grid-tool-group");
    tools.setAttribute("role", "group");
    tools.setAttribute("aria-label", "Selected cell actions");
    this.fillDown = ui.iconButton("Fill selected cells down", "fill_down", function () { self.fill(false); });
    this.fillRight = ui.iconButton("Fill selected cells right", "fill_right", function () { self.fill(true); });
    tools.appendChild(this.fillDown);
    tools.appendChild(this.fillRight);
    this.tools = tools;
    tools.classList.add("is-idle");
    // Help first: the fill tools keep their place while idle, and an empty place reads best after the help.
    var hint = "Select cells with Shift-click. Press Enter to edit; Escape to cancel.";
    var help = ui.helpButton("Editing cells", hint);
    help.classList.add("phc-icon-button");
    help.setAttribute("data-tooltip", hint);
    this.toolbar.appendChild(help);
    this.toolbar.appendChild(tools);
    if (options.toolbarParent) options.toolbarParent.appendChild(this.toolbar);
    else (options.scroll.parentNode || options.root).insertBefore(this.toolbar, options.scroll);
    this.copyListener = function (event) { self.copy(event); };
    this.pasteListener = function (event) {
      if (self.disposed || self.editing) return;
      event.preventDefault();
      try { self.paste(parse(event.clipboardData.getData("text/plain"))); }
      catch (error) { options.notify(error.message); }
    };
    options.scroll.addEventListener("copy", this.copyListener);
    options.scroll.addEventListener("paste", this.pasteListener);
  }
  Grid.prototype.copy = function (event) {
    if (this.disposed || this.editing || !this.anchor) return;
    this.sync();
    var selected = this.matrix(), edits = this.options.edits;
    if (!selected.length) return;
    event.preventDefault();
    var values = selected.map(function (row) {
      return row.map(function (cell) { return cell ? edits.display(cell.field, cell.current) : ""; });
    });
    event.clipboardData.setData("text/plain", values.map(function (row) {
      return row.map(encode).join("\t");
    }).join("\n"));
    event.clipboardData.setData("text/html", "<table>" + values.map(function (row) {
      return "<tr>" + row.map(function (value) { return "<td>" + escapeHTML(value) + "</td>"; }).join("") + "</tr>";
    }).join("") + "</table>");
  };
  Grid.prototype.sync = function () {
    if (this.disposed) return;
    if (this.options.ensureCurrent) this.options.ensureCurrent();
    this.refresh();
  };
  Grid.prototype.refresh = function () {
    if (this.disposed) return;
    var self = this, options = this.options, hidden = options.hiddenColumns() || {};
    var inputs = options.scroll.querySelectorAll("[" + options.edits.fieldAttribute + "]");
    this.cells = Array.prototype.slice.call(inputs).filter(function (input) {
      return visible(input, options.scroll);
    }).map(function (input) { return input._gridCell; }).filter(Boolean);
    this.fields = options.edits.fields.filter(function (field) { return !hidden[field]; });
    this.rows = [];
    this.positions = Object.create(null);
    this.lookup = Object.create(null);
    this.cells.forEach(function (cell) {
      var id = cell.row.key;
      if (self.positions[id] === undefined) { self.positions[id] = self.rows.length; self.rows.push(id); }
      self.lookup[id + ":" + cell.field] = cell;
    });
    if ((this.anchor && this.cells.indexOf(this.anchor) < 0) || (this.end && this.cells.indexOf(this.end) < 0)) {
      this.clear();
    }
    this.fillDown.disabled = this.fillRight.disabled = Boolean(options.isBusy() || !options.edits.enabled);
    this.cells.forEach(function (cell) { self.paintCell(cell); });
    this.paint();
  };
  Grid.prototype.position = function (cell) { return [this.positions[cell.row.key], this.fields.indexOf(cell.field)]; };
  Grid.prototype.at = function (row, column) { return this.lookup[this.rows[row] + ":" + this.fields[column]]; };
  Grid.prototype.range = function () {
    if (!this.anchor || !this.end) return { rows: [], mixed: false };
    var self = this, a = this.position(this.anchor), b = this.position(this.end);
    var fields = this.fields.slice(Math.min(a[1], b[1]), Math.max(a[1], b[1]) + 1), result = [], mixed = false;
    this.rows.slice(Math.min(a[0], b[0]), Math.max(a[0], b[0]) + 1).forEach(function (id) {
      if (!fields.some(function (field) { return Boolean(self.lookup[id + ":" + field]); })) return;
      var row = fields.map(function (field) { return self.lookup[id + ":" + field] || null; });
      if (row.some(function (cell) { return !cell; })) mixed = true;
      result.push(row);
    });
    return { rows: result, mixed: mixed };
  };
  Grid.prototype.matrix = function () { return this.range().rows; };
  Grid.prototype.paint = function () {
    var selected = Object.create(null), count = 0;
    this.matrix().forEach(function (row) {
      row.forEach(function (cell) { if (cell) { selected[cell.row.key + ":" + cell.field] = true; count += 1; } });
    });
    // The fill tools need a range to act on. Until there is one they are out of sight but keep their place,
    // so the row does not move when they appear.
    this.tools.classList.toggle("is-idle", count < 2);
    this.cells.forEach(function (cell) {
      cell.input.parentNode.classList.toggle("inventory-selected", Boolean(selected[cell.row.key + ":" + cell.field]));
    });
  };
  Grid.prototype.clear = function () { this.anchor = this.end = null; this.paint(); };
  Grid.prototype.select = function (cell, extend) {
    if (this.disposed) return;
    if (!extend || !this.anchor) this.anchor = cell;
    this.end = cell;
    this.paint();
  };
  Grid.prototype.draftBlocked = function () {
    var edits = this.options.edits;
    return Boolean(edits.pending || edits.queue.length || Object.keys(edits.cells).some(function (key) {
      return ["dirty", "queued", "pending", "error"].indexOf(edits.cells[key].status) >= 0;
    }));
  };
  Grid.prototype.locked = function (cell) {
    var edits = this.options.edits;
    return this.disposed || edits.disposed || !edits.enabled || cell.input.disabled ||
      Boolean(edits.isReadOnly && edits.isReadOnly(cell));
  };
  Grid.prototype.paintCell = function (cell) {
    var edits = this.options.edits;
    var immutable = Boolean(edits.isReadOnly && edits.isReadOnly(cell));
    var pending = ["pending", "queued"].indexOf(cell.status) >= 0;
    cell.input.disabled = Boolean(cell.gridDisabled || this.disposed || edits.disposed || cell.disposed ||
      !edits.enabled || edits.batchPending || (nativeSelect(cell) && (immutable || pending)));
    cell.input.readOnly = this.editing !== cell || this.locked(cell) || pending;
  };
  Grid.prototype.beginEdit = function (cell, replacement) {
    if (this.locked(cell) || ["pending", "queued"].indexOf(cell.status) >= 0) return;
    this.editing = cell;
    // Native selects own activation, type-ahead and option navigation; text-selection APIs do not exist there.
    if (nativeSelect(cell)) { cell.input.focus(); return; }
    cell.input.readOnly = false;
    if (replacement === undefined) { cell.input.select(); return; }
    cell.input.value = replacement;
    cell.input.dispatchEvent(window.Event ? new window.Event("input", { bubbles: true }) : { type: "input" });
    if (cell.input.setSelectionRange) cell.input.setSelectionRange(replacement.length, replacement.length);
  };
  Grid.prototype.bind = function (td, row, field, disabled) {
    var self = this, edits = this.options.edits, cell = edits.cells[row.key + ":" + field], input = cell.input;
    cell.gridDisabled = Boolean(disabled);
    this.paintCell(cell);
    if (input._gridCell) return;
    input._gridCell = cell;
    input.addEventListener("mousedown", function (event) {
      // Shift extends the cell range, not the browser's text selection, which would pull focus back to the anchor.
      self.select(cell, event.shiftKey);
      if (event.shiftKey && event.preventDefault) { event.preventDefault(); input.focus(); }
    });
    input.addEventListener("focus", function () { if (self.end !== cell) self.select(cell, false); });
    input.addEventListener("dblclick", function () { self.beginEdit(cell); });
    input.addEventListener("blur", function () {
      if (self.editing === cell) { self.editing = null; input.readOnly = true; }
    });
    input.addEventListener("keydown", function (event) { self.keydown(cell, event); }, true);
  };
  Grid.prototype.keydown = function (cell, event) {
    if (this.disposed) return;
    var key = event.key, p = this.position(cell), next, step, index;
    function stop() { event.preventDefault(); event.stopImmediatePropagation(); }
    if (["pending", "queued"].indexOf(cell.status) >= 0 && key !== "Tab") { stop(); return; }
    if (nativeSelect(cell)) {
      if (key === "Escape") {
        this.clear();
        this.options.edits.cancel(cell);
        this.editing = null;
      } else if (this.locked(cell)) { if (key !== "Tab") stop(); }
      else if (key === "Enter") this.beginEdit(cell);
      else if (key === "Tab") this.editing = null;
      return;
    }
    if (this.editing === cell) {
      if (key === "Escape") {
        stop();
        this.options.edits.cancel(cell);
        this.editing = null;
        cell.input.readOnly = true;
      } else if (key === "Enter" || key === "Tab") {
        this.editing = null;
        cell.input.readOnly = true;
      }
      return;
    }
    if (key === "Enter") { stop(); this.beginEdit(cell); return; }
    if (key === "Escape") { this.clear(); this.options.edits.cancel(cell); return; }
    if (key === " " && event.shiftKey) {
      event.preventDefault();
      this.anchor = this.at(p[0], 0);
      this.end = this.at(p[0], this.fields.length - 1);
      this.paint();
      return;
    }
    if (key.length === 1 && !event.metaKey && !event.ctrlKey && !event.altKey) {
      stop();
      this.beginEdit(cell, key);
      return;
    }
    if (["ArrowUp", "ArrowDown", "ArrowLeft", "ArrowRight", "Tab"].indexOf(key) < 0) return;
    if (key === "Tab") {
      index = this.cells.indexOf(cell) + (event.shiftKey ? -1 : 1);
      next = this.cells[index];
    } else if (key === "ArrowUp" || key === "ArrowDown") {
      step = key === "ArrowUp" ? -1 : 1;
      for (p[0] += step; p[0] >= 0 && p[0] < this.rows.length && !next; p[0] += step) next = this.at(p[0], p[1]);
    } else {
      step = key === "ArrowLeft" ? -1 : 1;
      for (p[1] += step; p[1] >= 0 && p[1] < this.fields.length && !next; p[1] += step) next = this.at(p[0], p[1]);
    }
    if (next && !next.input.disabled) {
      stop();
      this.select(next, event.shiftKey && key !== "Tab");
      next.input.focus();
    }
  };
  Grid.prototype.write = function (targets, canonical) {
    var options = this.options, edits = options.edits;
    if (this.disposed || options.isBusy() || !edits.enabled || edits.disposed) return;
    var changes = [];
    var error = this.draftBlocked() ? "Cancel or finish the existing cell draft before a range edit." : "";
    targets.forEach(function (target) {
      var cell = target.cell;
      if (!cell) {
        error = error || "This range includes cells that can't be edited here. Nothing was changed.";
        return;
      }
      if (this.locked(cell)) error = error || "This range includes read-only cells. Nothing was changed.";
      var value = edits.normalize(cell.field, target.value, canonical ? { canonical: true } : null);
      error = error || RecordEdits.normalizationError(value) || (edits.validationError ?
        edits.validationError(cell.field, value) : (edits.validate ? edits.validate(cell.field, value) : ""));
      if (cell.current === value) return;
      changes.push(options.changeFor ? options.changeFor(cell, value) : {
        id: cell.row.record.id, values: { [cell.field]: value }, expected_values: { [cell.field]: cell.current }
      });
    }, this);
    if (error) { options.notify(error); return; }
    if (changes.length) options.submitBatch(changes);
  };
  Grid.prototype.paste = function (values) {
    if (this.disposed) return;
    this.sync();
    if (!this.anchor) return;
    var self = this, p = this.position(this.anchor), targets = [];
    var width = values.reduce(function (maximum, row) { return Math.max(maximum, row.length); }, 0);
    var fields = this.fields.slice(p[1], p[1] + width);
    var rowIds = this.rows.slice(p[0]).filter(function (id) {
      return fields.some(function (field) { return Boolean(self.lookup[id + ":" + field]); });
    });
    if (rowIds.length < values.length || p[1] + width > this.fields.length) {
      this.options.notify("Paste exceeds the visible rows or editable columns. Nothing was changed.");
      return;
    }
    rowIds = rowIds.slice(0, values.length);
    values.forEach(function (row, r) {
      row.forEach(function (value, c) {
        targets.push({ cell: self.lookup[rowIds[r] + ":" + fields[c]], value: value });
      });
    });
    this.write(targets, false);
  };
  Grid.prototype.fill = function (right) {
    if (this.disposed) return;
    this.sync();
    var range = this.range(), rows = range.rows, targets = [];
    if (range.mixed) {
      this.options.notify("This range includes cells that can't be edited here. Nothing was changed.");
      return;
    }
    rows.forEach(function (row) {
      row.forEach(function (cell, c) {
        targets.push({ cell: cell, value: right ? row[0].current : rows[0][c].current });
      });
    });
    this.write(targets, true);
  };
  Grid.prototype.dispose = function () {
    this.disposed = true;
    this.editing = null;
    this.fillDown.disabled = this.fillRight.disabled = true;
    this.options.scroll.removeEventListener("copy", this.copyListener);
    this.options.scroll.removeEventListener("paste", this.pasteListener);
  };
  Grid.parse = parse;
  Grid.encode = encode;
  return Grid;
});
