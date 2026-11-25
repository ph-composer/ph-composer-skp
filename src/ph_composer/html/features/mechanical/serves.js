/* Serves on an equipment table: each item's cell shows the Zones it serves as chips, and opens the Zone picker.

   The picker lists every Zone occurrence under its Building Segment, as the Zone views do: the Model's Segments by
   name, then Zones whose Segment this Model has not adopted, then No Building Segment, last. A Segment's heading
   checks its every Zone at once. Each Zone another item fills is marked "will be replaced". The draft applies on
   the commit, labelled with what it does: newly checked Zones through serves.assign, then Zones left unchecked
   through serves.clear, each one Undo step. A Zone another item fills refuses the assign with
   mechanical.slot_filled, naming it; the draft stays, and the commit, now "Replace and assign", sends it again with
   `replace`. A list slot (a Zone's heat pump indoor units or electric heaters) holds several items, so nothing is
   replaced there and an unchecked Zone loses only this item (serves.clear with `item_id`). Cancel, the close and
   Escape write nothing; a click elsewhere or a scroll leaves a changed draft open.

   The draft holds only the Zones the user changed, each with the slot it showed then, which is what each write's
   `expected_values` carries; every other row follows the Model as snapshots arrive.

   new Picker(session, send, { slot, family, notify, many }) with open(record, trigger, layer), refresh(state),
   guard(), dispose(). chips(record, state) answers the cell's button; `record.zones` are its served Zones. */
PhComposerUI.define("features/mechanical/serves", ["snapshot", "workspace", "request"],
function (snapshot, ui, request) {
  "use strict";
  var SERVES = "ph_composer.mechanical.serves", OPTIONS = "ph_composer.zones.options";
  var CHIPS_SHOWN = 2, NONE = "none";

  function zoneRows(state) { var value = snapshot.value(state, SERVES); return value ? value.zones : []; }
  function key(row) { return JSON.stringify(row.reference.zone_path); }
  /* Whether a slot's value names `id`: a single slot holds one id, a list slot several. */
  function names(value, id) { return Array.isArray(value) ? value.indexOf(id) >= 0 : value === id; }
  function plural(count, word) { return count + " " + word + (count === 1 ? "" : "s"); }

  /* The Zones under their headings, in the Zone views' order. */
  function grouped(state, rows) {
    var options = snapshot.value(state, OPTIONS) || { building_segments: [] }, names = Object.create(null);
    options.building_segments.forEach(function (segment) { names[segment.id] = segment.values.name; });
    var groups = Object.create(null);
    rows.forEach(function (row) {
      var id = row.building_segment_id, adopted = !id && row.building_segment;
      var groupKey = id ? "segment:" + id : adopted ? "adopt:" + row.building_segment : NONE;
      var label = id ? names[id] || row.building_segment || "Building Segment" :
        adopted ? row.building_segment + " (not adopted)" : "No Building Segment";
      var rank = id ? 0 : adopted ? 1 : 2;
      (groups[groupKey] = groups[groupKey] || { key: groupKey, label: label, rank: rank, rows: [] }).rows.push(row);
    });
    return Object.keys(groups).map(function (name) { return groups[name]; }).sort(function (a, b) {
      return a.rank - b.rank || ui.compareText(a.label, b.label);
    }).map(function (group) {
      group.rows.sort(function (a, b) {
        return ui.compareText(a.name || "", b.name || "") || (key(a) < key(b) ? -1 : 1);
      });
      return group;
    });
  }

  /* The cell: the first Zones as chips, a count of the rest, or an amber "Serves no Zone". */
  function chips(record, open) {
    var zones = record.zones || [], button = ui.element("button", "mech-serves-cell");
    button.type = "button";
    if (!zones.length) button.appendChild(ui.element("span", "mech-zone-chip is-empty", "Serves no Zone"));
    zones.slice(0, CHIPS_SHOWN).forEach(function (zone) {
      button.appendChild(ui.element("span", "mech-zone-chip", zone.name || zone.zone_id));
    });
    if (zones.length > CHIPS_SHOWN) {
      button.appendChild(ui.element("span", "mech-zone-chip is-more", "+" + (zones.length - CHIPS_SHOWN)));
    }
    var names = zones.map(function (zone) { return zone.name || zone.zone_id; });
    var label = "Zones served by " + record.values.name + ": " + (names.length ? names.join(", ") : "none");
    button.setAttribute("aria-label", label + ". Choose Zones");
    ui.tooltip(button, names.length ? names.join(", ") : "Serves no Zone, so nothing exports it.");
    button.addEventListener("click", function () { open(button); });
    return button;
  }

  function Picker(session, send, options) {
    this.options = options;
    this.requests = request.channel(session, send, "mechanical-serves");
    this.held = null;
  }
  Picker.prototype.busy = function () { return this.requests.busy(); };
  Picker.prototype.guard = function () {
    if (this.busy()) return "Wait for the Zones to be assigned.";
    return this.held && this.changes().count ? "Apply or cancel the Zone picker first." : null;
  };
  /* Whether a Zone shows checked: as the user left it, else as the Model has it. */
  Picker.prototype.isChecked = function (row) {
    var touched = this.held.touched[key(row)];
    return touched ? touched.checked : names(row.slots[this.options.slot], this.held.record.id);
  };
  /* A change the user made: the Zone's reference and slot as they saw them. Putting a box back as it started
     drops the change, so later snapshots drive that Zone again. */
  Picker.prototype.touch = function (row, checked) {
    var touched = this.held.touched, previous = touched[key(row)];
    var entry = previous || { reference: JSON.parse(JSON.stringify(row.reference)),
      base: JSON.parse(JSON.stringify(row.slots)) };
    this.held.filled = false;
    if (checked === names(entry.base[this.options.slot], this.held.record.id)) { delete touched[key(row)]; return; }
    entry.checked = checked;
    touched[key(row)] = entry;
  };
  /* What the draft would change: Zones the user checked that the item does not serve, and Zones it serves that the
     user unchecked. */
  Picker.prototype.changes = function () {
    var held = this.held, slot = this.options.slot, add = [], clear = [];
    if (!held) return { add: add, clear: clear, count: 0 };
    zoneRows(held.state).forEach(function (row) {
      var touched = held.touched[key(row)];
      if (!touched) return;
      // Another Zone now stands at that path: the change was made to a Zone that is gone, so it lapses.
      if (touched.reference.zone_id !== row.reference.zone_id) { delete held.touched[key(row)]; return; }
      var serves = names(row.slots[slot], held.record.id);
      if (touched.checked && !serves) add.push(row);
      if (!touched.checked && serves) clear.push(row);
    });
    return { add: add, clear: clear, count: add.length + clear.length };
  };
  Picker.prototype.open = function (record, trigger, layer) {
    if (this.held && this.held.record.id === record.id) { this.close(true); return; }
    if (!this.close(false)) return;
    var self = this, state = this.state;
    var bubble = new ui.Bubble(trigger, "Zones served by " + record.values.name,
      { detachedTrigger: true, ownTrigger: true });
    bubble.root.classList.add("mech-zone-picker");
    var originalClose = bubble.close;
    // An implicit close (a click elsewhere, a scroll) keeps a changed draft; Cancel, the close and Escape drop it.
    bubble.close = function (focus) {
      if (self.busy() || (focus === false && self.changes().count)) return false;
      var closed = originalClose.call(bubble, focus);
      if (closed !== false) self.release();
      return closed;
    };
    var find = ui.element("input", "mech-zone-find");
    find.type = "search"; find.setAttribute("type", "search"); find.placeholder = "Find a Zone";
    find.setAttribute("aria-label", "Find a Zone");
    find.addEventListener("input", function () { self.paint(); });
    var list = ui.element("div", "mech-zone-list"), status = ui.element("p", "mech-zone-status");
    status.setAttribute("role", "status");
    var cancel = ui.button("Cancel", function () { bubble.close(true); });
    var apply = ui.button("Assign", function () { self.apply(Boolean(self.held && self.held.filled)); });
    bubble.content.replaceChildren(find, list, status, ui.actionRow(cancel, apply));
    (layer || document.body).appendChild(bubble.root);
    this.held = { record: record, bubble: bubble, touched: Object.create(null), state: state, find: find,
      list: list, status: status, apply: apply, cancel: cancel, filled: false, assigned: 0 };
    this.paint();
    bubble.open(false);
    find.focus({ preventScroll: true });
  };
  Picker.prototype.release = function () {
    var held = this.held;
    this.held = null;
    if (held && held.bubble.root.parentNode) held.bubble.root.parentNode.removeChild(held.bubble.root);
  };
  Picker.prototype.close = function (focus) {
    if (!this.held) return true;
    return this.held.bubble.close(focus) !== false;
  };
  /* The list, from the Model as it is now, with the draft's checks. */
  Picker.prototype.paint = function () {
    var self = this, held = this.held;
    if (!held) return;
    // A change to a Zone that is gone lapses before any box is drawn: its replacement shows as the Model has it.
    this.changes();
    var slot = this.options.slot, record = held.record, words = held.find.value.trim().toLowerCase();
    var rows = zoneRows(held.state).filter(function (row) {
      return !words || String(row.name || "").toLowerCase().indexOf(words) >= 0;
    }), busy = this.busy();
    // The list is drawn again on every change; the box that had focus keeps it.
    var focused = document.activeElement, focusKey = focused && held.list.contains(focused) ?
      focused.getAttribute("data-zone-path") || focused.getAttribute("data-zone-group") : null;
    var nodes = [];
    grouped(held.state, rows).forEach(function (group) {
      var heading = ui.element("label", "mech-zone-group" + (group.key === NONE ? " is-muted" : ""));
      var all = ui.element("input");
      all.type = "checkbox"; all.setAttribute("type", "checkbox");
      var count = group.rows.filter(function (row) { return self.isChecked(row); }).length;
      all.checked = count === group.rows.length;
      all.indeterminate = count > 0 && count < group.rows.length;
      all.disabled = busy;
      all.setAttribute("data-zone-group", group.key);
      all.setAttribute("aria-label", (words ? "Every shown Zone in " : "Every Zone in ") + group.label);
      all.addEventListener("change", function () {
        group.rows.forEach(function (row) { self.touch(row, all.checked); });
        self.paint();
      });
      heading.appendChild(all); heading.appendChild(ui.element("span", "", group.label));
      nodes.push(heading);
      group.rows.forEach(function (row) {
        var line = ui.element("label", "mech-zone-row"), box = ui.element("input");
        box.type = "checkbox"; box.setAttribute("type", "checkbox");
        box.checked = self.isChecked(row); box.disabled = busy;
        box.setAttribute("data-zone-path", key(row));
        box.addEventListener("change", function () {
          self.touch(row, box.checked); self.paint();
        });
        line.appendChild(box);
        line.appendChild(ui.element("span", "mech-zone-name", row.name || row.zone_id));
        var value = row.slots[slot];
        var other = value && !Array.isArray(value) && value !== record.id ? (row.items || []).filter(function (item) {
          return item.slot === slot;
        })[0] : null;
        if (other) {
          line.appendChild(ui.element("small", "mech-zone-note", (other.name || "Missing " + self.options.family) +
            (box.checked ? ", will be replaced" : "")));
        }
        nodes.push(line);
      });
    });
    if (!nodes.length) nodes.push(ui.element("p", "mech-zone-empty", words ? "No Zone matches." : "No Zones yet."));
    held.list.replaceChildren.apply(held.list, nodes);
    if (focusKey) {
      var again = Array.prototype.filter.call(held.list.querySelectorAll("input"), function (input) {
        return input.getAttribute("data-zone-path") === focusKey || input.getAttribute("data-zone-group") === focusKey;
      })[0];
      if (again) again.focus({ preventScroll: true });
    }
    var changes = this.changes();
    held.apply.textContent = held.filled ? "Replace and assign" : changes.add.length && changes.clear.length ?
      "Save" : changes.clear.length ? "Clear " + plural(changes.clear.length, "Zone") : changes.add.length ?
        "Assign " + plural(changes.add.length, "Zone") : "Assign";
    held.apply.disabled = busy || !changes.count;
    held.cancel.disabled = busy;
    held.bubble.closeButton.disabled = busy;
    if (!held.filled && !busy && held.status.classList.contains("is-filled")) {
      held.status.textContent = ""; held.status.classList.remove("is-error", "is-filled");
    }
  };
  /* Each Zone with the slot the user saw when they changed it, so a Zone changed since refuses. */
  Picker.prototype.targets = function (rows) {
    var touched = this.held.touched;
    return rows.map(function (row) {
      var entry = touched[key(row)];
      return { reference: entry.reference, expected_values: entry.base };
    });
  };
  /* Unchecked Zones lose the item: a single slot empties, a list slot gives up only this item. */
  Picker.prototype.clearParams = function (rows) {
    var params = { zones: this.targets(rows), slot: this.options.slot };
    if (this.options.many) params.item_id = this.held.record.id;
    return params;
  };
  /* Assigns the newly checked Zones, then clears those left unchecked: two requests, one after the other, so the
     second reads the Model the first left. `replace` answers a mechanical.slot_filled refusal. */
  Picker.prototype.apply = function (replace) {
    var held = this.held;
    if (!held || this.busy()) return;
    var changes = this.changes(), slot = this.options.slot;
    if (!changes.count) return;
    held.status.textContent = ""; held.status.classList.remove("is-error", "is-filled");
    if (changes.add.length) {
      var params = { zones: this.targets(changes.add), slot: slot, item_id: held.record.id };
      if (replace) params.replace = true;
      held.step = "assign";
      this.requests.run("ph_composer.mechanical.serves.assign", params);
    } else {
      held.step = "clear";
      this.requests.run("ph_composer.mechanical.serves.clear", this.clearParams(changes.clear));
    }
    this.paint();
    // The owner's table locks while a write is out, so nothing else leaves on the same revision.
    if (this.options.changed) this.options.changed();
  };
  Picker.prototype.refresh = function (state, records) {
    this.state = state;
    var outcome = this.requests.consume(state), held = this.held;
    if (!held) return;
    var record = (records || []).filter(function (entry) { return entry.id === held.record.id; })[0];
    if (!record && !this.busy()) { this.dismiss(); return; }
    if (record) held.record = record;
    held.state = state;
    if (outcome) this.settle(outcome);
    if (this.held) this.paint();
  };
  Picker.prototype.settle = function (outcome) {
    var held = this.held;
    if (outcome.status !== "completed") {
      held.filled = outcome.code === "mechanical.slot_filled";
      // A refused clear follows an assign that landed: say both, since that half stays written.
      held.status.textContent = (held.step === "clear" && held.assigned ? "Assigned " +
        plural(held.assigned, "Zone") + "; clearing the unchecked Zones was refused. " : "") +
        snapshot.message(outcome, "The Zones were not changed.");
      held.status.classList.add("is-error");
      held.status.classList.toggle("is-filled", held.filled);
      return;
    }
    held.filled = false;
    if (held.step === "assign") held.assigned = outcome.value && outcome.value.zone_ids ?
      outcome.value.zone_ids.length : 1;
    var changes = this.changes();
    if (held.step === "assign" && changes.clear.length) {
      // The assign landed; the Zones left unchecked are cleared next, from the Model as the assign left it.
      held.step = "clear";
      this.requests.run("ph_composer.mechanical.serves.clear", this.clearParams(changes.clear));
      return;
    }
    var name = held.record.values.name;
    this.close(true);
    if (this.options.notify) this.options.notify("Saved the Zones " + name + " serves.", "success");
  };
  /* Drops the picker without writing: its item is gone, or its view is. */
  Picker.prototype.dismiss = function () {
    var held = this.held;
    if (!held) return;
    held.touched = Object.create(null);
    held.bubble.close(false);
    this.release();
  };
  Picker.prototype.dispose = function () {
    this.requests.reset();
    this.dismiss();
  };

  return { Picker: Picker, chips: chips, grouped: grouped };
});
