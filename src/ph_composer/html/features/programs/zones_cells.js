/* The Zones / Programs view's cells, the house row and the Dwelling bubble (context/CONTRACTS.md, "Occupancy").

   Every value comes from `ph_composer.programs.zones` (features/programs/occupancy_reads.rb); the panel works out
   nothing. Each control applies at once as one request and one Undo step through Programs' own actions:
   `assign_program`, `assign_library_program`, `assign_dwelling`, `set_counts`, `assign_equipment_set`, and a
   Dwelling's `dwellings.update`. The house row of a single dwelling writes its Segment's occupancy payload through
   Zones' settings Save, the same request the settings dialog sends. Every request carries the revision its cell
   was painted from, so a value read before the Model changed refuses; the panel's notice says why and the cell
   shows the Model's value again on the next paint, holding no draft.

   Under Single dwelling a Zone's Program, Dwelling, counts and Equipment Set are locked: each shows its value in the
   kit's locked pill, which opens the lock bubble (features/programs/occupancy.js). */
PhComposerUI.define("features/programs/zones_cells", ["panel", "workspace", "request", "snapshot", "units",
  "unit_preferences", "fields", "features/programs/occupancy"],
function (panel, ui, requests, snapshot, units, preferences, fields, occupancy) {
  "use strict";
  var PREFIX = "ph_composer.programs";
  var OPTIONS = "ph_composer.zones.options";
  var NUMBER = /^\+?(\d+\.?\d*|\.\d+)$/;
  var NON_RESIDENTIAL = "Non-residential Building Segment: PHX reads the Program's equipment watts here, not " +
    "Equipment Set devices.";
  var NO_DWELLING = "Only Zones in a Dwelling hold bedrooms and occupants.";
  var RULE = "Left empty, the Dwelling uses the Phius rule: bedrooms + 1 per dwelling unit.";

  function copy(value) { return JSON.parse(JSON.stringify(value)); }

  /* The typed count: null when blank, the number when it is a decimal of at least 0, else undefined. */
  function parsed(text) {
    var trimmed = String(text).trim();
    if (trimmed === "") return null;
    return NUMBER.test(trimmed) ? Number(trimmed) : undefined;
  }

  function countText(value) {
    return value === null || value === undefined ? "" : String(Math.round(value * 100) / 100);
  }

  /* Every write this view makes: one in flight, each carrying the revision the view last painted, or the one a
     typed entry began at. `failures` counts refusals, so a surface that holds a focused field repaints after one. */
  function Writes(host) {
    var self = this;
    this.host = host; this.failures = 0;
    this.channel = requests.channel(host.session, function (type, payload) {
      var revision = self.pinned !== undefined ? self.pinned : self.revision;
      host.send(type, Object.assign({}, payload, { expected_revision: revision }));
    }, "programs-zones");
  }

  Writes.prototype.consume = function (state) {
    this.revision = state.revision;
    this.channel.consume(state);
  };

  Writes.prototype.busy = function () { return this.channel.busy(); };

  /* Sends one action; `done(outcome)` names what changed in a notice. A refusal is the panel's notice. `revision`,
     when given, is the one the entry was read at: a Model that has moved on since refuses it. */
  Writes.prototype.run = function (name, params, done, revision) {
    if (this.channel.busy()) { this.host.refuse("Wait for the last change to finish."); return false; }
    var self = this;
    this.pinned = revision;
    this.channel.run(name, params, { onDone: function (outcome) {
      var words = done ? done(outcome) : null;
      if (words) panel.notify(words, "success");
    }, onFail: function () { self.failures += 1; } });
    this.pinned = undefined;
    panel.repaint();
    return true;
  };

  /* ---------------------------------------------------------------- the cells */

  function ZoneCells(host, data, library) {
    this.host = host; this.data = data; this.library = library;
    this.writes = new Writes(host);
    this.cells = Object.create(null);
    this.chips = Object.create(null);
    this.bubble = null;
    this.layer = null;
  }

  ZoneCells.prototype.consume = function (state) { this.writes.consume(state); };

  ZoneCells.prototype.attach = function (place) {
    this.layer = place.surface;
  };

  ZoneCells.prototype.disabled = function (row) {
    // A Zone shared with another occurrence is read only; the host keys those by the occurrence's path.
    var path = row.record.zone && JSON.stringify(row.record.zone.reference.zone_path || []);
    return this.writes.busy() || Boolean(this.host.draftReason()) || Boolean(path && this.host.gated[path]);
  };

  /* A locked value: the kit's locked pill, which explains the lock. */
  function locked(td, text, segment, label) {
    var pill = td._programsLock;
    if (!pill) {
      pill = td._programsLock = ui.button("", function () { occupancy.lockBubble(pill, pill._segment); });
      pill.className = "phc-enum-pill phc-programs-locked";
    }
    pill.textContent = text;
    pill._segment = { id: segment.id, name: segment.name };
    pill.setAttribute("aria-label", label + ": " + text + ". " + segment.name + " is a single dwelling");
    ui.tooltip(pill, segment.name + " is a single dwelling. Click to see why.");
    td.classList.add("phc-pill-cell");
    if (pill.parentNode !== td || td.children.length !== 1) td.replaceChildren(pill);
    return true;
  }

  function muted(td, text, tip) {
    var node = td._programsMuted || (td._programsMuted = ui.element("span", "phc-programs-muted"));
    node.textContent = text;
    ui.tooltip(node, tip || "");
    if (node.parentNode !== td || td.children.length !== 1) td.replaceChildren(node);
    return true;
  }

  /* The amber "?" of a value still missing, naming why. */
  ZoneCells.missing = function (td, reason, label) {
    var node = td._programsMissing || (td._programsMissing = ui.element("span", "phc-programs-missing", "?"));
    node.setAttribute("role", "img");
    node.tabIndex = 0;
    node.setAttribute("aria-label", label + " unknown: " + reason);
    ui.tooltip(node, reason);
    if (node.parentNode !== td || td.children.length !== 1) td.replaceChildren(node);
    return true;
  };

  ZoneCells.prototype.render = function (td, row, field) {
    var zone = row.record.programs;
    if (!zone) return false;
    var segment = this.data.segment(zone.building_segment_id);
    if (field === "program") return this.program(td, row, zone, segment);
    if (field === "dwelling") return this.dwelling(td, row, zone, segment);
    if (field === "bedrooms" || field === "occupants") return this.count(td, row, zone, segment, field);
    if (field === "equipment_set") return this.equipmentSet(td, row, zone, segment);
    var reasons = zone.missing || {};
    var key = { people: "people", lighting_w: "lighting_w", ventilation_m3h: "ventilation_m3h" }[field];
    if (key && zone[key] === null && reasons[key]) return ZoneCells.missing(td, reasons[key], row.record.name);
    return false;
  };

  /* One select per cell, rebuilt only when its choices change, so a repaint keeps focus and the open list. */
  ZoneCells.prototype.select = function (td, key, label, choices, value) {
    var cell = this.cells[key];
    if (!cell) {
      cell = this.cells[key] = { input: ui.element("select", "phc-enum-cell phc-cell-input") };
      var self = this;
      cell.input.addEventListener("change", function () { if (cell.changed) cell.changed(cell.input.value, self); });
    }
    var signature = JSON.stringify(choices);
    if (signature !== cell.signature) {
      cell.input.replaceChildren();
      choices.forEach(function (choice) {
        if (choice.group) {
          var group = ui.element("optgroup"); group.label = choice.group;
          choice.options.forEach(function (pair) { group.appendChild(ui.option(pair[0], pair[1])); });
          cell.input.appendChild(group);
        } else cell.input.appendChild(ui.option(choice[0], choice[1]));
      });
      cell.signature = signature;
    }
    cell.input.value = value;
    cell.input.setAttribute("aria-label", label);
    td.classList.add("phc-pill-cell", "phc-editable-cell");
    if (cell.input.parentNode !== td || td.children.length !== 1) td.replaceChildren(cell.input);
    return cell;
  };

  /* The Program choices: this file's Programs, then each library source's, which copy into this file. */
  ZoneCells.prototype.programChoices = function (unassigned) {
    var choices = [["", unassigned]];
    var local = (this.data.read().choices.programs || []).map(function (program) {
      return ["pgm:" + program.id, program.name];
    });
    if (local.length) choices.push({ group: "In this file", options: local });
    this.library.groups().forEach(function (group) {
      choices.push({ group: group.label + ", copies into this file", options: group.rows.map(function (row) {
        return ["lib:" + row.id, row.display_label];
      }) });
    });
    return choices;
  };

  /* Assigns what a Program choice names to `zones`: a local Program, the Segment's default (""), or a library
     Program copied with its Schedules first, in the same Undo step. */
  ZoneCells.prototype.assignProgram = function (zones, value, words) {
    var references = zones.map(function (zone) { return copy(zone.reference); });
    if (value.indexOf("lib:") === 0) {
      var row = this.library.find(value.slice(4));
      if (!row) { this.host.refuse("That library Program is no longer offered. Choose again."); return false; }
      var made = this.library.copy(row);
      if (!made.params) { this.host.refuse(made.reason); panel.repaint(); return false; }
      return this.writes.run(PREFIX + ".assign_library_program", { zones: references, copy: made.params },
        function () {
          return "Copied " + row.display_label + " into this file with its Schedules and assigned it to " +
            words + ".";
        });
    }
    var id = value ? value.slice(4) : null;
    var program = (this.data.read().choices.programs || []).filter(function (entry) { return entry.id === id; })[0];
    return this.writes.run(PREFIX + ".assign_program", { zones: references, program_id: id }, function () {
      if (program) return program.name + " assigned to " + words + ".";
      return words + " now " + (zones.length === 1 ? "uses its" : "use their") + " Building Segment's default " +
        "Program.";
    });
  };

  ZoneCells.prototype.program = function (td, row, zone, segment) {
    if (zone.single_dwelling) return locked(td, zone.program_name || "Residential default", segment, "Program");
    var own = zone.assignment.program_id, self = this;
    var cell = this.select(td, row.key + ":program", "Program for " + row.record.name,
      this.programChoices(zone.program_name || "No Program"), own ? "pgm:" + own : "");
    cell.input.classList.toggle("is-default", !own);
    cell.input.disabled = this.disabled(row);
    ui.tooltip(cell.input, own ? "" : "Unassigned: uses its Building Segment's default Program, else the Model's.");
    cell.changed = function (value) { self.assignProgram([zone], value, row.record.name); };
    return true;
  };

  /* ---------------------------------------------------------------- Dwelling */

  ZoneCells.prototype.dwelling = function (td, row, zone, segment) {
    if (zone.single_dwelling) return locked(td, zone.dwelling_name, segment, "Dwelling");
    var self = this, chip = td._programsChip;
    if (!chip) {
      chip = td._programsChip = ui.button("", function () { self.openDwelling(chip._rowKey, chip); });
    }
    chip._rowKey = row.key;
    chip.className = "phc-dwelling-chip" + (zone.dwelling_id ? "" : " is-none");
    chip.textContent = zone.dwelling_id ? zone.dwelling_name + (zone.dwelling_units > 1 ? " ×" +
      zone.dwelling_units : "") : "None";
    chip.setAttribute("aria-label", "Dwelling of " + row.record.name + ": " + chip.textContent);
    chip.disabled = this.disabled(row);
    this.chips[row.key] = chip;
    if (chip.parentNode !== td || td.children.length !== 1) td.replaceChildren(chip);
    return true;
  };

  ZoneCells.prototype.count = function (td, row, zone, segment, field) {
    var dwelling = this.data.dwelling(zone.dwelling_id);
    if (zone.single_dwelling) return locked(td, "—", segment, (field === "bedrooms" ? "Bedrooms" : "Occupants") +
      " in " + zone.dwelling_name);
    if (!zone.dwelling_id) return muted(td, "—", NO_DWELLING);
    var own = dwelling && dwelling[field === "bedrooms" ? "own_bedrooms" : "own_occupants"];
    if (own !== null && own !== undefined) {
      return muted(td, "in " + zone.dwelling_name, "Entered once for the whole Dwelling. Open " +
        zone.dwelling_name + " to change it.");
    }
    var self = this, key = row.key + ":" + field, cell = this.cells[key];
    if (!cell) {
      cell = this.cells[key] = { input: ui.element("input", "phc-cell-input") };
      cell.input.type = "text"; cell.input.setAttribute("inputmode", "decimal");
      cell.input.addEventListener("change", function () { self.commitCount(cell); });
      // An entry is read against the revision its first keystroke saw, so a change made meanwhile refuses it.
      cell.input.addEventListener("input", function () {
        if (!cell.typed) cell.revision = self.writes.revision;
        cell.typed = true;
      });
      cell.input.addEventListener("keydown", function (event) {
        if (event.key === "Enter") { event.preventDefault(); self.commitCount(cell); }
        // Escape ends the entry and the revision it was pinned to, even when its text is back at the seed.
        if (event.key === "Escape" && cell.input.value !== cell.seed) {
          event.preventDefault(); cell.input.value = cell.seed;
        }
        if (event.key === "Escape") cell.typed = false;
      });
    }
    cell.row = row; cell.zone = zone; cell.field = field;
    var value = countText(zone.assignment[field]);
    if (document.activeElement !== cell.input || !cell.typed) { cell.input.value = value; cell.typed = false; }
    cell.seed = value;
    cell.input.placeholder = field === "bedrooms" ? "0" : (dwelling && dwelling.occupants_rule ? "Phius rule" : "");
    cell.input.setAttribute("aria-label", (field === "bedrooms" ? "Bedrooms" : "Occupants") + " in " +
      row.record.name);
    ui.tooltip(cell.input, field === "occupants" ? RULE : "Counted in " + zone.dwelling_name + ", with its other " +
      "Zones'.");
    cell.input.disabled = this.disabled(row);
    td.classList.add("phc-editable-cell", "is-numeric");
    if (cell.input.parentNode !== td || td.children.length !== 1) td.replaceChildren(cell.input);
    return true;
  };

  ZoneCells.prototype.commitCount = function (cell) {
    var value = parsed(cell.input.value), revision = cell.typed ? cell.revision : undefined;
    cell.typed = false;
    if (cell.input.value.trim() === cell.seed) return;
    if (value === undefined) {
      this.host.refuse("Enter the " + cell.field + " as a number of at least 0, or leave it empty.");
      cell.input.value = cell.seed;
      return;
    }
    var counts = { bedrooms: cell.zone.assignment.bedrooms, occupants: cell.zone.assignment.occupants };
    counts[cell.field] = value;
    // Enter and the change that follows on leaving send once.
    cell.seed = cell.input.value.trim();
    this.writes.run(PREFIX + ".set_counts", { zone: copy(cell.zone.reference), bedrooms: counts.bedrooms,
      occupants: counts.occupants }, null, revision);
  };

  /* The Equipment Set choices: "Model default" (none of its own), then every Set by name, the default's own
     record among them, so a Set chosen explicitly stays selectable even when it is also the default. */
  ZoneCells.prototype.setChoices = function () {
    var sets = this.data.read().choices.equipment_sets || [];
    return [["", "Model default"]].concat(sets.map(function (set) { return [set.id, set.name]; }));
  };

  /* A Set's name; null names the Model's default Set. */
  ZoneCells.prototype.setName = function (id) {
    var choices = this.data.read().choices, target = id || choices.default_equipment_set_id;
    var set = (choices.equipment_sets || []).filter(function (entry) { return entry.id === target; })[0];
    return set ? set.name : "Model default";
  };

  ZoneCells.prototype.equipmentSet = function (td, row, zone, segment) {
    if (segment && segment.category === "non_residential") return muted(td, "—", NON_RESIDENTIAL);
    if (zone.single_dwelling) {
      return locked(td, this.setName(segment.dwelling && segment.dwelling.equipment_set_id), segment,
        "Equipment Set");
    }
    var self = this;
    var cell = this.select(td, row.key + ":equipment_set", "Equipment Set for " + row.record.name,
      this.setChoices(), zone.equipment_set_id || "");
    cell.input.classList.toggle("is-default", !zone.equipment_set_id);
    cell.input.disabled = this.disabled(row);
    ui.tooltip(cell.input, (zone.dwelling_id ? "Shared by " + zone.dwelling_name + ": one Set per Dwelling." :
      "This Zone's own Set: it is not in a Dwelling.") + (zone.equipment_set_id ? "" : " The Model's default Set."));
    cell.changed = function (value) { self.assignSet([zone], value || null); };
    return true;
  };

  /* An Equipment Set on Zones: their Dwellings' Set for those in one, their own for the others, one request. */
  ZoneCells.prototype.assignSet = function (zones, id) {
    var dwellings = [], loose = [];
    zones.forEach(function (zone) {
      if (zone.dwelling_id) { if (dwellings.indexOf(zone.dwelling_id) < 0) dwellings.push(zone.dwelling_id); }
      else loose.push(copy(zone.reference));
    });
    var name = this.setName(id), data = this.data;
    var named = dwellings.map(function (dwellingId) { return data.dwelling(dwellingId).name; })
      .concat(zones.filter(function (zone) { return !zone.dwelling_id; }).map(function (zone) { return zone.name; }));
    return this.writes.run(PREFIX + ".assign_equipment_set", { equipment_set_id: id, dwelling_ids: dwellings,
      zones: loose }, function () {
      return name + " is now the Equipment Set of " + (named.length <= 2 ? named.join(" and ") : named.length +
        " Dwellings and Zones") + ".";
    });
  };

  /* Puts `zones` in a Dwelling: `choice` is shared, each, none, or a Dwelling's id. */
  ZoneCells.prototype.assignDwelling = function (zones, choice, words) {
    var params = { zones: zones.map(function (zone) { return copy(zone.reference); }) };
    var target = this.data.dwelling(choice);
    if (target) { params.choice = "existing"; params.dwelling_id = choice; } else params.choice = choice;
    return this.writes.run(PREFIX + ".assign_dwelling", params, function () {
      if (target) return words + " added to " + target.name + ".";
      if (choice === "none") return words + (zones.length === 1 ? " is" : " are") + " no longer in a Dwelling.";
      if (choice === "each") return words + (zones.length === 1 ? " is now a Dwelling." :
        " are now one Dwelling each.");
      return words + (zones.length === 1 ? " is now a Dwelling." : " now share one Dwelling.");
    });
  };

  /* ---------------------------------------------------------------- the Dwelling bubble */

  /* "Dwelling of <Zone>": its Dwelling, applied at once, then that Dwelling's units, Zones, bedrooms, occupants
     and iCFA. It follows every repaint while open and closes when its Zone goes. */
  ZoneCells.prototype.openDwelling = function (rowKey, chip) {
    var open = this.bubble && !this.bubble.bubble.panel.hidden && this.bubble.key === rowKey;
    this.closeDwelling();
    if (open) return;
    var row = this.data.row(rowKey);
    if (!row) return;
    var bubble = new ui.Bubble(chip, "Dwelling of " + row.record.name, { detachedTrigger: true, ownTrigger: true });
    bubble.root.classList.add("phc-dwelling-bubble");
    (this.layer || chip.closest(".phc-workspace") || document.body).appendChild(bubble.root);
    this.bubble = { key: rowKey, bubble: bubble, parts: null };
    this.paintDwelling();
    bubble.open();
  };

  ZoneCells.prototype.closeDwelling = function () {
    if (!this.bubble) return;
    this.bubble.bubble.close(false);
    if (this.bubble.bubble.root.parentNode) this.bubble.bubble.root.parentNode.removeChild(this.bubble.bubble.root);
    this.bubble = null;
  };

  ZoneCells.prototype.paintDwelling = function () {
    var held = this.bubble;
    if (!held) return;
    var row = this.data.row(held.key), zone = row && row.record.programs;
    if (!zone || zone.single_dwelling) { this.closeDwelling(); return; }
    var self = this, bubble = held.bubble, dwelling = this.data.dwelling(zone.dwelling_id);
    if (this.chips[held.key] && this.chips[held.key].isConnected) bubble.trigger = this.chips[held.key];
    if (!held.parts) {
      held.parts = { choose: ui.element("select"), detail: ui.element("dl", "phc-dwelling-detail") };
      var label = ui.element("label", "phc-dwelling-choose");
      label.appendChild(ui.element("span", "", "Dwelling of " + row.record.name));
      label.appendChild(held.parts.choose);
      held.parts.choose.setAttribute("aria-label", "Dwelling of " + row.record.name);
      held.parts.choose.addEventListener("change", function () {
        var value = held.parts.choose.value;
        var current = self.data.row(held.key).record.programs;
        if (value === (current.dwelling_id || "none")) return;
        self.assignDwelling([current], value === "new" ? "shared" : value, current.name);
      });
      bubble.content.replaceChildren(label, held.parts.detail);
    }
    var options = this.data.segmentDwellings(zone.building_segment_id, zone.dwelling_id).map(function (entry) {
      return [entry.id, entry.name];
    }).concat([["new", "New dwelling"], ["none", "Not a dwelling"]]);
    var signature = JSON.stringify(options);
    if (signature !== held.signature) {
      held.parts.choose.replaceChildren.apply(held.parts.choose, options.map(function (pair) {
        return ui.option(pair[0], pair[1]);
      }));
      held.signature = signature;
    }
    held.parts.choose.value = zone.dwelling_id || "none";
    held.parts.choose.disabled = this.writes.busy();
    var detail = held.parts.detail;
    if (!dwelling) {
      if (held.detailFor !== "none") {
        detail.replaceChildren(ui.element("p", "phc-programs-muted", "Not part of a Dwelling: no bedrooms, " +
          "occupants or Equipment Set of a Dwelling."));
        held.detailFor = "none";
      }
      return;
    }
    // A focused field holds while its Dwelling is unchanged; a write sent or refused repaints it from the Model.
    var focused = detail.contains(document.activeElement);
    var key = JSON.stringify([dwelling, this.writes.busy(), this.writes.failures]);
    if (focused && held.detailFor === key) return;
    held.detailFor = key;
    var parts = [];
    function line(label, value) { parts.push(ui.element("dt", "", label)); parts.push(value); }
    line("Units", this.dwellingField(dwelling, "units", "Units of " + dwelling.name, String(dwelling.units)));
    line("Zones", ui.element("dd", "", this.data.zoneNames(dwelling.zone_ids).join(", ")));
    line("Bedrooms", dwelling.own_bedrooms !== null && dwelling.own_bedrooms !== undefined ?
      this.dwellingField(dwelling, "bedrooms", "Bedrooms of " + dwelling.name, countText(dwelling.own_bedrooms)) :
      ui.element("dd", "", dwelling.bedrooms === null ? "—" : countText(dwelling.bedrooms)));
    var occupants = ui.element("dd", "", dwelling.occupants === null ? "—" : countText(dwelling.occupants));
    if (dwelling.occupants_rule) {
      var info = ui.element("span", "phc-dwelling-rule");
      info.replaceChildren(ui.glyph("info"));
      info.setAttribute("role", "img");
      info.setAttribute("aria-label", "Phius rule: bedrooms + 1 per dwelling unit");
      ui.tooltip(info, "No occupants entered, so the Phius rule applies: bedrooms + 1 per dwelling unit.");
      occupants.appendChild(info);
    }
    line("Occupants", occupants);
    var area = fields.AREA_M2;
    line("iCFA", ui.element("dd", "", units.format(dwelling.icfa_m2, area, units.profile(area,
      preferences.current()))));
    detail.replaceChildren.apply(detail, parts);
  };

  /* A Dwelling's own number in the bubble: Enter or leaving writes it, at the revision the field was drawn from,
     which it keeps while focused; Escape restores it. */
  ZoneCells.prototype.dwellingField = function (dwelling, key, label, seed) {
    var self = this, dd = ui.element("dd"), input = ui.element("input", "phc-dwelling-input");
    var revision = this.writes.revision;
    input.type = "text"; input.setAttribute("inputmode", "decimal"); input.setAttribute("aria-label", label);
    input.value = seed;
    function commit() {
      var value = parsed(input.value);
      if (input.value.trim() === seed) return;
      if (value === undefined || value === null && key === "units" ||
          key === "units" && (value < 1 || Math.round(value) !== value)) {
        self.host.refuse(key === "units" ? "Enter the units as a whole number of at least 1." :
          "Enter the bedrooms as a number of at least 0.");
        input.value = seed;
        return;
      }
      var values = {}, expected = {};
      values[key] = value; expected[key] = dwelling[key === "units" ? "units" : "own_bedrooms"];
      seed = input.value.trim();
      self.writes.run(PREFIX + ".dwellings.update", { id: dwelling.id, values: values, expected_values: expected },
        function () { return dwelling.name + " now has " + value + " " + (key === "units" ? "unit" : "bedroom") +
          (value === 1 ? "" : "s") + "."; }, revision);
    }
    input.addEventListener("change", commit);
    input.addEventListener("keydown", function (event) {
      if (event.key === "Enter") { event.preventDefault(); commit(); }
      if (event.key === "Escape" && input.value !== seed) {
        event.preventDefault(); event.stopPropagation(); input.value = seed;
      }
    });
    input.disabled = this.writes.busy();
    dd.appendChild(input);
    return dd;
  };

  /* ---------------------------------------------------------------- the house row */

  /* A single dwelling's heading takes the house's bedrooms, occupants and Equipment Set, written to the Segment's
     occupancy payload as the settings dialog's Save writes it. */
  ZoneCells.prototype.houseCell = function (td, group, field) {
    var segment = group.segment && this.data.segment(group.segment.id);
    if (!segment || !segment.single_dwelling || !segment.dwelling) return false;
    var house = segment.dwelling, self = this, key = "house:" + segment.id + ":" + field;
    var held = this.writes.busy() || Boolean(this.host.draftReason());
    if (field === "equipment_set") {
      var cell = this.select(td, key, "Equipment Set for " + house.name, this.setChoices(),
        house.equipment_set_id || "");
      cell.input.classList.toggle("is-default", !house.equipment_set_id);
      cell.input.disabled = held;
      ui.tooltip(cell.input, "The house's appliances and Phius devices." + (house.equipment_set_id ? "" :
        " The Model's default Set."));
      cell.changed = function (value) { self.saveHouse(group, { equipment_set_id: value || null }); };
      return true;
    }
    if (field !== "bedrooms" && field !== "occupants") return false;
    var entry = this.cells[key];
    if (!entry) {
      entry = this.cells[key] = { input: ui.element("input", "phc-cell-input phc-house-input") };
      entry.input.type = "text"; entry.input.setAttribute("inputmode", "decimal");
      entry.input.addEventListener("change", function () { self.commitHouse(entry); });
      entry.input.addEventListener("keydown", function (event) {
        if (event.key === "Enter") { event.preventDefault(); self.commitHouse(entry); }
        // Escape ends the entry and the revision it was pinned to, even when its text is back at the seed.
        if (event.key === "Escape" && entry.input.value !== entry.seed) {
          event.preventDefault(); entry.input.value = entry.seed;
        }
        if (event.key === "Escape") entry.typed = false;
      });
      entry.input.addEventListener("input", function () {
        if (!entry.typed) entry.revision = self.writes.revision;
        entry.typed = true;
      });
    }
    entry.group = group; entry.field = field;
    var stored = segment.settings[field], seed = countText(stored);
    if (document.activeElement !== entry.input || !entry.typed) { entry.input.value = seed; entry.typed = false; }
    entry.seed = seed;
    var needed = field === "bedrooms" && stored === null;
    entry.input.classList.toggle("is-needed", needed);
    entry.input.placeholder = needed ? "?" : field === "occupants" && house.occupants !== null ?
      countText(house.occupants) : "";
    entry.input.setAttribute("aria-label", (field === "bedrooms" ? "Bedrooms" : "Occupants") + " in " + house.name);
    ui.tooltip(entry.input, needed ? "Enter the bedrooms of the house: the Phius rules count occupants, lighting " +
      "and appliances from them." : field === "occupants" ? "Average occupants. " + RULE : "Bedrooms in the " +
      "whole house.");
    entry.input.disabled = held;
    td.classList.add("phc-editable-cell", "is-numeric");
    if (entry.input.parentNode !== td || td.children.length !== 1) td.replaceChildren(entry.input);
    return true;
  };

  ZoneCells.prototype.commitHouse = function (entry) {
    var value = parsed(entry.input.value), revision = entry.typed ? entry.revision : undefined;
    entry.typed = false;
    if (entry.input.value.trim() === entry.seed) return;
    if (value === undefined) {
      this.host.refuse("Enter the " + entry.field + " as a number of at least 0, or leave it empty.");
      entry.input.value = entry.seed;
      return;
    }
    var change = {};
    change[entry.field] = value;
    entry.seed = entry.input.value.trim();
    this.saveHouse(entry.group, change, revision);
  };

  ZoneCells.prototype.saveHouse = function (group, change, revision) {
    var record = group.segment, segment = this.data.segment(record.id);
    var options = snapshot.value(this.host.snapshot, OPTIONS) || {}, defaultId = options.default_segment_id || null;
    var payload = Object.assign({}, occupancy.DEFAULTS, segment.settings, change), payloads = {};
    payloads[occupancy.NAMESPACE] = payload;
    var values = { name: record.values.name, colour: record.values.colour };
    return this.writes.run("ph_composer.zones.save_segment_settings", { id: record.id, values: values,
      expected_values: copy(values), default: defaultId === record.id, expected_default_segment_id: defaultId,
      extension_payloads: payloads, expected_extension_data: copy(record.extension_data || {}) }, function () {
      return segment.name + " saved.";
    }, revision);
  };

  /* After a paint: the Dwelling bubble follows the Model, and cells of rows that left are forgotten. */
  ZoneCells.prototype.painted = function (keys) {
    var self = this;
    Object.keys(this.chips).forEach(function (key) { if (!keys[key]) delete self.chips[key]; });
    this.paintDwelling();
  };

  ZoneCells.prototype.dispose = function () { this.closeDwelling(); this.writes.channel.reset(); };

  return ZoneCells;
});
