/* The Zones / Programs view's checked Zones and the selection bar that assigns to them together.

   A box checks one Zone; a Zone of a single dwelling has none, since its Segment's setting decides its values,
   and is never checked when another view hands its checked Zones over. The bar holds the Building Segment (the
   Zones screen's own control, `host.segmentMove`), then Program, Dwelling (one shared, one each, not a dwelling,
   or add to an existing one) and Equipment Set. Each choice applies at once to every checked Zone, hidden by a
   filter or not, as one request and one Undo step, and a notice names what changed; the choice then shows what the
   checked Zones share, or "Mixed". */
PhComposerUI.define("features/programs/zones_selection", ["panel", "workspace", "selection_bar"],
function (panel, ui, selectionBars) {
  "use strict";
  var MIXED = "__mixed";

  function ZoneSelection(cells, data) {
    this.cells = cells; this.data = data;
    this.keys = Object.create(null);
    this.rows = [];
  }

  function checkable(row) { return Boolean(row.record.programs && !row.record.programs.single_dwelling); }

  ZoneSelection.prototype.prepare = function (rows) {
    var self = this, live = Object.create(null);
    this.rows = rows.filter(function (row) { return !row.parent && row.record.zone; });
    this.rows.forEach(function (row) { live[row.key] = row; });
    Object.keys(this.keys).forEach(function (key) { if (!live[key] || !checkable(live[key])) delete self.keys[key]; });
    if (this.pending) {
      var handed = this.pending;
      this.pending = null;
      this.keys = Object.create(null);
      handed.forEach(function (key) { if (live[key] && checkable(live[key])) self.keys[key] = true; });
    }
  };

  ZoneSelection.prototype.checked = function () {
    return this.rows.filter(function (row) { return this.keys[row.key]; }, this);
  };

  ZoneSelection.prototype.checkedZones = function () {
    return this.checked().map(function (row) { return row.key; });
  };

  ZoneSelection.prototype.clear = function () {
    var had = this.checked().length > 0;
    this.keys = Object.create(null);
    return had;
  };

  ZoneSelection.prototype.check = function (context) {
    var self = this, shown = context.visible.filter(function (row) { return !row.parent && checkable(row); });
    function stateOf(rows) {
      var count = rows.filter(function (row) { return self.keys[row.key]; }).length;
      return !rows.length ? false : count === rows.length ? true : count ? "mixed" : false;
    }
    return {
      state: function (row) { return row.parent || !checkable(row) ? null : Boolean(self.keys[row.key]); },
      toggle: function (row) {
        if (self.keys[row.key]) delete self.keys[row.key]; else self.keys[row.key] = true;
        panel.repaint();
      },
      header: function () { return stateOf(shown); },
      toggleAll: function () {
        var on = stateOf(shown) !== true;
        shown.forEach(function (row) { if (on) self.keys[row.key] = true; else delete self.keys[row.key]; });
        panel.repaint();
      },
      label: function (row) { return (self.keys[row.key] ? "Uncheck " : "Check ") + row.record.name; },
      headerLabel: function (value) {
        return (value === true ? "Uncheck" : "Check") + " every Zone the filter shows that is not a single dwelling";
      },
      any: function () { return self.checked().length > 0; }
    };
  };

  /* A choice in the bar: a select whose first entry says what the checked Zones share. */
  function choice(label) {
    var root = ui.element("label", "phc-selection-field"), select = ui.element("select");
    select.setAttribute("aria-label", label + " for checked Zones");
    root.appendChild(ui.element("span", "", label));
    root.appendChild(select);
    return { root: root, select: select };
  }

  function fill(select, shared, groups) {
    var signature = JSON.stringify([shared, groups]);
    if (select._signature === signature) return;
    select._signature = signature;
    var first = ui.option(MIXED, shared);
    first.disabled = true;
    select.replaceChildren(first);
    groups.forEach(function (entry) {
      if (entry.group) {
        var group = ui.element("optgroup"); group.label = entry.group;
        entry.options.forEach(function (pair) { group.appendChild(ui.option(pair[0], pair[1])); });
        select.appendChild(group);
      } else select.appendChild(ui.option(entry[0], entry[1]));
    });
  }

  /* The text every checked Zone shares for one value, or "Mixed". */
  function common(zones, read) {
    var first = read(zones[0]);
    return zones.every(function (zone) { return read(zone) === first; }) ? first : "Mixed";
  }

  function words(zones) {
    return zones.length === 1 ? zones[0].name : zones.length + " Zones";
  }

  ZoneSelection.prototype.bar = function (overview) {
    var self = this;
    if (!this.root) {
      this.root = new selectionBars.SelectionBar("Checked Zones", function () {
        if (self.clear()) panel.repaint();
      });
      this.segment = this.cells.host.segmentMove(function () {
        return self.checked().map(function (row) { return row.record.zone; });
      });
      this.program = choice("Program");
      this.dwelling = choice("Dwelling");
      this.equipment = choice("Equipment Set");
      [this.program, this.dwelling, this.equipment].forEach(function (part) {
        part.select.addEventListener("change", function () { self.apply(part, part.select.value); });
      });
      var group = ui.element("div", "phc-selection-controls");
      group.setAttribute("role", "group");
      group.setAttribute("aria-label", "Zones");
      [this.segment.root, this.program.root, this.dwelling.root, this.equipment.root].forEach(function (node) {
        group.appendChild(node);
      });
      this.root.controls.appendChild(group);
    }
    if (this.root.root.parentNode !== overview) overview.appendChild(this.root.root);
    var checked = this.checked(), zones = checked.map(function (row) { return row.record.programs; });
    if (!checked.length) { this.root.hide(); return this.root; }
    var busy = this.cells.writes.busy();
    fill(this.program.select, common(zones, function (zone) {
      return zone.assignment.program_id ? zone.program_name : "Default (" + zone.program_name + ")";
    }), this.cells.programChoices("Building Segment default").map(function (entry) {
      return entry.group ? entry : ["pgm:", entry[1]];
    }));
    // A Dwelling lies in one Building Segment, so "Add to" offers those of the checked Zones' Segment, and none
    // while they span two.
    var segments = zones.map(function (zone) { return zone.building_segment_id; }).filter(function (id, index, all) {
      return all.indexOf(id) === index;
    });
    var dwellings = segments.length !== 1 ? [] : this.data.segmentDwellings(segments[0], null)
      .map(function (dwelling) { return [dwelling.id, dwelling.name]; });
    fill(this.dwelling.select, common(zones, function (zone) { return zone.dwelling_name || "Not a dwelling"; }),
      [["shared", "One shared dwelling"], ["each", "One dwelling each"], ["none", "Not a dwelling"]]
        .concat(dwellings.length ? [{ group: "Add to", options: dwellings }] : []));
    fill(this.equipment.select, common(zones, function (zone) { return self.cells.setName(zone.equipment_set_id); }),
      this.cells.setChoices().map(function (pair) { return [pair[0] || "default", pair[1]]; }));
    [this.program, this.dwelling, this.equipment].forEach(function (part) {
      part.select.value = MIXED; part.select.disabled = busy;
    });
    this.segment.paint();
    this.root.show(checked.length + (checked.length === 1 ? " Zone" : " Zones") + " checked", true);
    return this.root;
  };

  /* One choice for every checked Zone. */
  ZoneSelection.prototype.apply = function (part, value) {
    var zones = this.checked().map(function (row) { return row.record.programs; });
    part.select.value = MIXED;
    if (!zones.length || value === MIXED) return;
    if (part === this.program) {
      this.cells.assignProgram(zones, value === "pgm:" ? "" : value, words(zones));
    } else if (part === this.dwelling) this.cells.assignDwelling(zones, value, words(zones));
    else this.cells.assignSet(zones, value === "default" ? null : value);
  };

  ZoneSelection.prototype.hide = function () { if (this.root) this.root.hide(); };

  ZoneSelection.prototype.dispose = function () {
    if (this.root && this.root.root.parentNode) this.root.root.parentNode.removeChild(this.root.root);
  };

  return ZoneSelection;
});
