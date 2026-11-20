/* The Building Segment heading rows of the Zones screen (context/EXTENSIBILITY.md, "Zone views"). In every view
   the Zones sit under the heading of their Segment: the Model's Segments by name, each shown even while empty,
   then Zones whose Segment this Model has not adopted, then No Building Segment, muted and shown only while it
   holds a Zone. The views' own top-level group rows (records outside every Zone) follow, under no heading.

   A heading row is a host row: it holds no Zone and is never checked. Its Name cell takes two lines, the name
   (cut, with the whole name in its tooltip) and a findings flag, then the tags features contribute through
   `table_views.heading` (Zones adds Default); the shown view fills its columns from `segmentSums`. Settings and
   Delete sit in its Actions cell. New Building Segment is an icon in the control row; it makes a Segment under a
   free default name and opens that name in place. Moving Zones happens in a view's selection bar through
   `moveControl`. Moving a Zone to No Building Segment offers, in one confirmation, to make it the Attached zone of
   the Surface pairs it shares with Zones still exported; moving one back says Solve adjacencies pairs them
   again. Every write is one request and one Undo step. */
PhComposerUI.define("features/zones/segment_rows", ["panel", "workspace", "request", "table_views",
  "features/zones/zone_options", "features/zones/segment_settings"],
function (panel, ui, requests, tableViews, zoneOptions, SegmentSettings) {
  "use strict";
  var HOST = "ph_composer.zones";
  var registry = tableViews.host(HOST);
  var NONE = "";
  var NEW = "__new", OUT = "__none";
  var LAST = "The Model keeps at least one Building Segment, so the last one cannot be deleted.";
  var LEFT_OUT = "Zones in no Building Segment are left out of export.";
  var OFFER = "ph_composer.zones.faces.attached_zone.offer";

  // Zones' own contribution to every heading: the Segment new Zones join.
  tableViews.heading(HOST, { id: "ph_composer.zones.default_segment", order: 10,
    segmentHeading: function (segment, state) {
      if (zoneOptions.read(state).default_segment_id !== segment.id) return null;
      return { tags: [{ text: "Default", tooltip: "New Zones join this Building Segment." }] };
    } });

  function headingKey(key) { return JSON.stringify(["BuildingSegment", key]); }

  /* Which heading a Zone sits under: its Segment's id, "" for none, or an adoption group for a Zone whose
     Segment this Model has not adopted (a legacy Zone, or one copied from another Model). */
  function groupKey(options, zone) {
    if (!zoneOptions.managed(zone)) return "adopt:" + (zone.values.building_segment || "");
    var id = zoneOptions.value(zone, "building_segment");
    if (!id) return NONE;
    return zoneOptions.find(options, "building_segment", id) ? id : "adopt:" + id;
  }

  function SegmentRows(session, send, guard, refuse, adopt) {
    var self = this;
    this.guard = guard; this.refuse = refuse; this.adopt = adopt;
    this.channel = requests.channel(session, function (type, payload) {
      send(type, Object.assign({}, payload, { expected_revision: self.revision }));
    }, "segments");
    this.settings = new SegmentSettings(session, send, function (message, tone) { panel.notify(message, tone); });
    this.reads = requests.channel(session, function (type, payload) { send(type, payload); }, "segment-offer",
      "query.invoke");
    this.offers = []; this.offering = null;
    this.options = zoneOptions.read({});
    this.renaming = null;
    this.newButton = ui.iconButton("New Building Segment", "add", function () { self.create([]); });
    this.newButton.classList.add("phc-new-segment");
  }

  SegmentRows.prototype.consume = function (state) {
    this.snapshot = state; this.revision = state.revision; this.options = zoneOptions.read(state);
    this.settings.consume(state, this.options);
    this.channel.consume(state);
    this.reads.consume(state);
    // A Segment named in place that has been read and is gone again (Undo took it) leaves nothing to rename. The
    // create's result can arrive before the snapshot that lists the new Segment. The values the field first read
    // are its guard, so a name changed elsewhere meanwhile is never overwritten.
    var named = this.renaming && this.segment(this.renaming.id);
    if (named && !this.renaming.seen) {
      this.renaming.seen = true;
      this.renaming.expected = { name: named.values.name, colour: named.values.colour };
    } else if (this.renaming && !named && this.renaming.seen) this.renaming = null;
    this.newButton.disabled = this.channel.busy();
  };

  SegmentRows.prototype.segment = function (id) {
    return zoneOptions.find(this.options, "building_segment", id);
  };

  SegmentRows.prototype.segments = function () {
    return zoneOptions.list(this.options, "building_segment").slice().sort(function (a, b) {
      return ui.compareText(a.values.name, b.values.name) || ui.compareText(a.id, b.id);
    });
  };

  /* Work a filter, a switch or a tab change must not hide: an open settings dialog or delete confirmation, a
     write in flight. */
  SegmentRows.prototype.draftReason = function () {
    if (this.settings.active()) return "Finish the Building Segment settings first.";
    if (this.deleting) return "Finish deleting the Building Segment first.";
    if (this.offering) return "Answer the Attached zone offer first.";
    return null;
  };

  /* ---------------------------------------------------------------- rows */

  /* `rows` in the order the controls settled on, with a heading before each group. `hidden(row)` is the
     controls' answer for a row; `filtering` whether a text or column filter applies. Answers the rows for the
     table and the heading rows' own hidden test. */
  SegmentRows.prototype.arrange = function (rows, hidden, filtering) {
    var options = this.options, buckets = Object.create(null), extra = [], current = null, self = this;
    rows.forEach(function (row) {
      if (!row.parent) current = row.record.zone ? groupKey(options, row.record.zone) : null;
      if (current === null) { extra.push(row); return; }
      (buckets[current] = buckets[current] || []).push(row);
    });
    var headings = this.segments().map(function (segment) {
      return self.heading(segment.id, segment.values.name, "segment", segment, buckets[segment.id] || []);
    });
    Object.keys(buckets).filter(function (key) { return key.indexOf("adopt:") === 0; }).map(function (key) {
      var zone = buckets[key][0].record.zone;
      return self.heading(key, zoneOptions.label(options, zone, "building_segment"), "adopt", null, buckets[key]);
    }).sort(function (a, b) { return ui.compareText(a.record.name, b.record.name); })
      .forEach(function (heading) { headings.push(heading); });
    if (buckets[NONE]) headings.push(this.heading(NONE, "No Building Segment", "none", null, buckets[NONE]));
    var arranged = [];
    headings.forEach(function (heading) {
      arranged.push(heading);
      arranged.push.apply(arranged, buckets[heading.record.id] || []);
    });
    var renaming = this.renaming && this.renaming.id;
    function headingHidden(row) {
      var zones = row.record.zones;
      // A Segment being named stays in view under any filter, so its field is never stranded.
      if (row.record.id === renaming) return false;
      // A Segment's heading shows while nothing filters, even empty; under a filter, while a Zone of its shows.
      if (!filtering && row.record.kind === "segment") return false;
      return !zones.some(function (zone) { return !hidden(zone); });
    }
    return { rows: arranged.concat(extra), hidden: headingHidden };
  };

  SegmentRows.prototype.heading = function (key, name, kind, segment, rows) {
    return { key: headingKey(key), parent: null, tier: "Building Segment", depth: 0, heading: true,
      record: { id: key, name: name, kind: kind, building_segment: segment,
        zones: rows.filter(function (row) { return !row.parent; }) } };
  };

  /* The group a view's `segmentSums` reads: its key as the Zones and Spaces reads key their `building_segments`
     sums (the Segment's id, a legacy Zone's Segment name, or "" for none), the Segment record (null for none or
     one not adopted) and its Zone rows. */
  SegmentRows.group = function (row) {
    var key = row.record.id, legacy = row.record.kind === "adopt";
    return { key: legacy ? key.slice("adopt:".length) : key, segment: row.record.building_segment,
      rows: row.record.zones };
  };

  /* Tags and findings the registered contributions give a Segment. */
  SegmentRows.prototype.contributions = function (segment) {
    var state = this.snapshot, tags = [], findings = [];
    registry.headings().forEach(function (entry) {
      var given = entry.segmentHeading ? entry.segmentHeading(segment, state) : null;
      if (!given) return;
      tags = tags.concat(given.tags || []);
      findings = findings.concat(given.findings || []);
    });
    return { tags: tags, findings: findings };
  };

  /* The heading's Name cell: name and findings flag, then its tags; a name being renamed is a field. */
  SegmentRows.prototype.cell = function (td, row, field) {
    if (field !== "name") return false;
    var record = row.record, parts = td._segmentHeading;
    if (!parts) {
      parts = td._segmentHeading = { root: ui.element("div", "phc-segment-heading"),
        line: ui.element("div", "phc-segment-line"), name: ui.element("span", "phc-segment-name"),
        flag: ui.element("span", "phc-segment-flag"), tags: ui.element("div", "phc-segment-tags") };
      parts.line.appendChild(parts.name); parts.line.appendChild(parts.flag);
      parts.root.appendChild(parts.line); parts.root.appendChild(parts.tags);
    }
    var given = record.kind === "segment" ? this.contributions(record.building_segment) :
      { tags: record.kind === "adopt" ? [{ text: "Copied", tooltip: "This Building Segment came with Zones from " +
        "another Model or an earlier version. Adopt it from the row's actions to use it here." }] : [],
      findings: [] };
    td.classList.toggle("is-muted", record.kind !== "segment");
    if (this.renaming && record.kind === "segment" && this.renaming.id === record.id) {
      if (parts.root.parentNode === td) td.removeChild(parts.root);
      this.renameField(td, record);
      return true;
    }
    parts.name.textContent = record.name;
    ui.tooltip(parts.name, record.kind === "none" ? LEFT_OUT : record.name);
    parts.flag.hidden = !given.findings.length;
    if (given.findings.length) {
      parts.flag.replaceChildren(ui.glyph("alert"));
      var words = given.findings.map(function (finding) { return finding.message || finding.text || finding; })
        .join(" ");
      parts.flag.setAttribute("role", "img"); parts.flag.setAttribute("aria-label", words);
      ui.tooltip(parts.flag, words);
    }
    parts.tags.replaceChildren.apply(parts.tags, given.tags.map(function (tag) {
      var node = ui.element("span", "phc-segment-tag", tag.text);
      if (tag.tooltip) ui.tooltip(node, tag.tooltip);
      return node;
    }));
    parts.tags.hidden = !given.tags.length;
    if (parts.root.parentNode !== td || td.children.length !== 1) td.replaceChildren(parts.root);
    ui.tooltip(td, "");
    return true;
  };

  SegmentRows.prototype.actions = function (row) {
    var record = row.record, busy = this.channel.busy();
    if (record.kind === "adopt") {
      return [{ id: "adopt", icon: "assign", label: "Adopt " + record.name, disabled: busy }];
    }
    if (record.kind !== "segment") return [];
    var last = zoneOptions.list(this.options, "building_segment").length < 2;
    return [{ id: "settings", icon: "settings", label: "Settings for " + record.name, disabled: busy },
      { id: "delete", icon: "delete", label: "Delete " + record.name, disabled: busy,
        unavailable: last ? LAST : null }];
  };

  SegmentRows.prototype.action = function (row, item, control) {
    var reason = this.guard();
    if (reason) return this.refuse(reason);
    if (item.id === "adopt") return this.adopt();
    var segment = row.record.building_segment;
    if (item.id === "settings") return this.settings.open(segment, this.usage(segment));
    if (item.id === "delete") return this.confirmDelete(segment, row.record.zones);
    return null;
  };

  SegmentRows.prototype.usage = function (segment) {
    return (segment.usage || {}).live || 0;
  };

  /* ---------------------------------------------------------------- new and rename */

  /* A free colour from the palette, so a new Segment reads apart from the others. */
  SegmentRows.prototype.colour = function () {
    var used = zoneOptions.list(this.options, "building_segment").map(function (choice) {
      return String(choice.values.colour).toUpperCase();
    });
    var free = zoneOptions.PALETTE.filter(function (colour) { return used.indexOf(colour.toUpperCase()) < 0; });
    return free[0] || zoneOptions.PALETTE[used.length % zoneOptions.PALETTE.length];
  };

  /* Makes a Segment, with `targets` (Zones as `{ reference, expected_values }`) moved in, and opens its name;
     `created`, if given, runs once it is made. */
  SegmentRows.prototype.create = function (targets, created) {
    var reason = this.guard(), self = this;
    if (reason) return this.refuse(reason);
    if (this.channel.busy()) return null;
    this.channel.run("ph_composer.zones.create_segment", { colour: this.colour(), targets: targets }, {
      onDone: function (outcome) {
        self.renaming = { id: outcome.value.id, draft: outcome.value.name };
        if (created) created();
      }
    });
    panel.repaint();
    return null;
  };

  /* The name field a new Segment opens with: Enter, leaving or the check applies; Escape or the cross keeps
     the name it was given. */
  SegmentRows.prototype.renameField = function (td, record) {
    var self = this, renaming = this.renaming;
    if (!renaming.root) {
      renaming.root = ui.element("div", "phc-segment-rename");
      renaming.input = ui.element("input");
      renaming.input.type = "text"; renaming.input.setAttribute("type", "text");
      renaming.input.value = renaming.draft;
      renaming.input.setAttribute("aria-label", "Building Segment name");
      renaming.input.addEventListener("input", function () { renaming.draft = renaming.input.value; });
      renaming.input.addEventListener("keydown", function (event) {
        if (event.key === "Enter") { event.preventDefault(); self.applyRename(); }
        if (event.key === "Escape") { event.preventDefault(); self.stopRename(); }
      });
      // Leaving the field applies the name, unless focus went to its own check or cross, which decide instead.
      renaming.input.addEventListener("blur", function (event) {
        var next = event && event.relatedTarget;
        if (next && renaming.root.contains(next)) return;
        if (self.renaming === renaming && !renaming.leaving) self.applyRename();
      });
      var apply = ui.iconButton("Apply name", "check", function () { self.applyRename(); });
      var cancel = ui.iconButton("Keep the name " + record.name, "clear", function () { self.stopRename(); });
      // A press on either icon would blur the field first; it decides instead.
      [apply, cancel].forEach(function (button) {
        button.addEventListener("pointerdown", function () { renaming.leaving = true; });
      });
      renaming.root.appendChild(renaming.input); renaming.root.appendChild(apply); renaming.root.appendChild(cancel);
      renaming.focus = true;
    }
    renaming.input.disabled = this.channel.busy();
    if (renaming.root.parentNode !== td) td.replaceChildren(renaming.root);
    if (renaming.focus) {
      renaming.focus = false;
      renaming.input.focus();
      if (renaming.input.select) renaming.input.select();
    }
  };

  SegmentRows.prototype.applyRename = function () {
    var renaming = this.renaming, self = this;
    if (!renaming || this.channel.busy()) return;
    renaming.leaving = false;
    var segment = this.segment(renaming.id), name = String(renaming.draft || "").trim();
    var expected = renaming.expected;
    if (!segment || !expected || !name || name === expected.name) { this.stopRename(); return; }
    if (segment.values.name !== expected.name || segment.values.colour !== expected.colour) {
      this.stopRename();
      this.refuse("This Building Segment changed while it was being named. Rename it from its settings.");
      return;
    }
    this.channel.run("ph_composer.zones.options.update", { collection: "building_segment", id: segment.id,
      values: { name: name, colour: segment.values.colour }, expected_values: expected }, {
      onDone: function () { if (self.renaming === renaming) self.renaming = null; },
      // A refused name keeps the field open with what was typed; the notice says why.
      onFail: function () { renaming.focus = true; }
    });
    panel.repaint();
  };

  SegmentRows.prototype.stopRename = function () {
    if (!this.renaming) return;
    this.renaming = null;
    panel.repaint();
  };

  /* ---------------------------------------------------------------- delete */

  /* Names the Zones that move and where, and the settings that go with the Segment. `zones` are its Zone rows. */
  SegmentRows.prototype.confirmDelete = function (segment, zones) {
    var self = this, others = this.segments().filter(function (choice) { return choice.id !== segment.id; });
    var used = (segment.usage || {}).live || 0, recoverable = (segment.usage || {}).recoverable || 0;
    var dialog = this.deleting = ui.formDialog("phc-segment-delete-dialog", function () { self.closeDelete(); });
    dialog.appendChild(ui.element("h2", "", "Delete " + segment.values.name + "?"));
    var destination = null;
    if (used || recoverable) {
      destination = ui.element("select");
      others.forEach(function (choice) { destination.appendChild(ui.option(choice.id, choice.values.name)); });
      destination.appendChild(ui.option(OUT, "No Building Segment"));
      var label = ui.element("label", "phc-segment-destination");
      label.appendChild(ui.element("span", "", used ? "Its " + used + (used === 1 ? " Zone moves" : " Zones move") +
        " to" : "Zones it can restore move to"));
      label.appendChild(destination);
      dialog.appendChild(label);
      if (zones.length) dialog.appendChild(ui.element("p", "phc-segment-zones", zoneNames(zones)));
    }
    var consequence = ui.element("p", "phc-segment-consequence");
    dialog.appendChild(consequence);
    function paint() {
      var target = destination ? destination.value : null, words = [];
      var titles = settingsTitles(segment);
      if (titles.length) words.push("Its settings go with it: " + titles + ".");
      if (self.options.default_segment_id === segment.id) {
        var next = target && target !== OUT ? self.segment(target) : others.slice().sort(function (a, b) {
          return a.id < b.id ? -1 : 1;
        })[0];
        words.push("New Zones will join " + (next ? next.values.name : "the first remaining Segment") + ".");
      }
      if (target === OUT) words.push(LEFT_OUT);
      consequence.textContent = words.join(" ");
      consequence.hidden = !words.length;
    }
    if (destination) destination.addEventListener("change", paint);
    paint();
    var cancel = ui.button("Cancel", function () { self.closeDelete(); });
    // The confirmation names the Zones and settings of the Model it opened on; once the Model moves, what it
    // names may no longer be what Delete would take, so it sends nothing and asks for a fresh look.
    var revision = this.revision;
    var remove = ui.button("Delete", function () {
      var params = { collection: "building_segment", id: segment.id };
      if (destination) params.replacement_id = destination.value === OUT ? null : destination.value;
      self.closeDelete();
      if (self.revision !== revision) {
        self.refuse("The Model changed since Delete opened. Open it again to see where the Zones go.");
        return;
      }
      if (self.channel.busy()) return;
      self.channel.run("ph_composer.zones.options.remove", params, { onDone: function () {
        panel.notify(segment.values.name + " deleted.", "success");
      } });
      panel.repaint();
    });
    dialog.appendChild(ui.actionRow(cancel, remove, true));
    document.body.appendChild(dialog);
    dialog.openModal();
    (destination || cancel).focus();
  };

  /* The Zones a deleted Segment holds, by name: the first few, then how many more. */
  function zoneNames(rows) {
    var names = rows.map(function (row) { return row.record.name; }), shown = names.slice(0, 5);
    var more = names.length - shown.length;
    return "Zones: " + shown.join(", ") + (more ? " and " + more + " more" : "") + ".";
  }

  /* The titles of the settings sections a Segment holds data for, in words. */
  function settingsTitles(segment) {
    var stored = Object.keys(segment.extension_data || {});
    if (!stored.length) return "";
    var sections = panel.segmentSettingsSections(), titles = [];
    sections.forEach(function (spec) { if (stored.indexOf(spec.namespace) >= 0) titles.push(spec.title); });
    if (stored.length > titles.length) titles.push("settings other features keep");
    return titles.length < 2 ? titles.join("") : titles.slice(0, -1).join(", ") + " and " + titles[titles.length - 1];
  }

  SegmentRows.prototype.closeDelete = function () {
    if (!this.deleting) return;
    this.deleting.closeModal(); this.deleting.remove(); this.deleting = null;
  };

  /* ---------------------------------------------------------------- moving Zones from a selection bar */

  /* A Building Segment control for a view's selection bar: `zones()` answers the Zone records the bar acts on
     (each with `reference`, `values` and `state`), `gated(zone)` whether one is read only. Choosing a Segment,
     New Building Segment or No Building Segment moves them all in one Undo step. */
  SegmentRows.prototype.moveControl = function (zones, gated) {
    var self = this, root = ui.element("label", "phc-selection-field phc-segment-move");
    var select = ui.element("select");
    select.setAttribute("aria-label", "Building Segment for checked Zones");
    root.appendChild(ui.element("span", "", "Building Segment"));
    root.appendChild(select);
    function targets(list) {
      return list.map(function (zone) {
        return { reference: JSON.parse(JSON.stringify(zone.reference)),
          expected_values: JSON.parse(JSON.stringify(zone.values)) };
      });
    }
    function blocked(list) {
      if (list.some(gated)) return "A checked Zone is shared with another occurrence and read only. Uncheck it " +
        "to move the others.";
      if (list.some(function (zone) { return groupKey(self.options, zone).indexOf("adopt:") === 0; })) {
        return "Adopt this Model's Zone options before moving these Zones.";
      }
      return null;
    }
    select.addEventListener("change", function () {
      var list = zones(), chosen = select.value, reason = self.guard() || blocked(list);
      paint();
      if (!chosen || !list.length) return;
      if (reason) { self.refuse(reason); return; }
      if (chosen === NEW) {
        var back = list.filter(function (zone) { return groupKey(self.options, zone) === NONE; });
        self.create(targets(list), function () {
          self.review(targets(back).map(function (target) { return target.reference; }), false);
        });
        return;
      }
      if (self.channel.busy()) return;
      var segment = chosen === OUT ? null : self.segment(chosen), moved = targets(list);
      // Zones moved out are offered as Attached zones; Zones moved back from none are told about Solve.
      var reviewed = moved.filter(function (target, index) {
        return (groupKey(self.options, list[index]) === NONE) !== (chosen === OUT);
      });
      self.channel.run("ph_composer.zones.update_field", { field: "building_segment",
        value: segment ? segment.values.name : null, targets: moved }, { onDone: function () {
        self.review(reviewed.map(function (target) { return target.reference; }), chosen === OUT);
      } });
      panel.repaint();
    });
    function paint() {
      var list = zones(), keys = list.map(function (zone) { return groupKey(self.options, zone); });
      var shared = keys.every(function (key) { return key === keys[0]; }) ? keys[0] : null;
      var first = shared === null ? "Mixed" : shared === NONE ? "No Building Segment" :
        (self.segment(shared) || { values: { name: "Choose a Segment" } }).values.name;
      var signature = JSON.stringify([first, self.segments().map(function (choice) {
        return [choice.id, choice.values.name];
      })]);
      if (select._signature !== signature) {
        var placeholder = ui.option("", first);
        placeholder.disabled = true;
        select.replaceChildren(placeholder);
        self.segments().forEach(function (choice) { select.appendChild(ui.option(choice.id, choice.values.name)); });
        select.appendChild(ui.option(NEW, "New Building Segment"));
        select.appendChild(ui.option(OUT, "No Building Segment"));
        select._signature = signature;
      }
      select.value = "";
      var reason = blocked(list);
      select.disabled = self.channel.busy() || !list.length || Boolean(reason);
      ui.tooltip(select, reason || "");
      root.hidden = !list.length;
    }
    return { root: root, paint: paint };
  };

  /* ---------------------------------------------------------------- the Attached zone offer */

  /* After a move, reads each Zone's offer in turn: one moved `out` with Surface pairs shared with exported Zones
     is offered as their Attached zone; one moved back that has Faces on an Attached zone gets a notice. */
  SegmentRows.prototype.review = function (references, out) {
    var self = this;
    references.forEach(function (reference) { self.offers.push({ reference: reference, out: out }); });
    this.nextOffer();
  };

  SegmentRows.prototype.nextOffer = function () {
    var self = this;
    if (this.offering || this.reads.busy() || !this.offers.length) return;
    var item = this.offers.shift();
    this.reads.run(OFFER, { zone: item.reference }, {
      onDone: function (outcome) {
        var offer = outcome.value;
        if (item.out && offer.faces.length) { self.confirmOffer(offer, outcome.revision); return; }
        if (!item.out && offer.attached_face_count) {
          panel.notify(offer.name + " keeps " + offer.attached_face_count + (offer.attached_face_count === 1 ?
            " Face" : " Faces") + " on an Attached zone. Run Solve adjacencies to pair the Faces it shares with " +
            "other Zones again.", "info");
        }
        self.nextOffer();
      },
      // A Zone that cannot be read any more has nothing to offer.
      onFail: function () { self.nextOffer(); }
    });
  };

  /* One confirmation names the Zones on the other side and how many Faces change; Make reclassifies both sides
     of each pair as one Undo step through the Attached zone actions, reusing an Attached zone of the name. The
     offer holds for the revision it was read at; the next Zone's offer is read once this write settles. */
  SegmentRows.prototype.confirmOffer = function (offer, read) {
    var self = this, shared = offer.faces.length / 2;
    var dialog = this.offering = ui.formDialog("phc-segment-offer-dialog", function () { self.closeOffer(); });
    dialog.appendChild(ui.element("h2", "", "Make " + offer.name + " an Attached zone?"));
    dialog.appendChild(ui.element("p", "phc-segment-consequence", offer.name + " is in no Building Segment, so " +
      "export leaves it out, and the " + shared + (shared === 1 ? " Face" : " Faces") + " it shares with " +
      listed(offer.shared_with) + " would refuse export as Surface pairs. Make " + offer.name +
      (offer.attached_zone_id ? ", the Attached zone already in this Model," : " a new Attached zone and") +
      " their boundary instead, on both sides."));
    var later = ui.button("Not now", function () { self.closeOffer(); });
    var make = ui.button("Make Attached zone", function () {
      var settled = { onDone: function () { self.nextOffer(); }, onFail: function () { self.nextOffer(); } };
      self.closeOffer(true);
      if (typeof read === "number" && self.revision > read) {
        self.refuse("The Model changed since the offer opened. Assign the Attached zone from Classify instead.");
        self.nextOffer();
        return;
      }
      if (self.channel.busy()) {
        self.refuse("Another change is still being written. Assign the Attached zone from Classify instead.");
        self.nextOffer();
        return;
      }
      var expected = { boundary_condition: "Surface" };
      if (offer.attached_zone_id) {
        self.channel.run("ph_composer.zones.faces.classify", { faces: offer.faces, expected_values: expected,
          intent: { boundary_condition: { mode: "set", value: "AttachedZone" },
            attached_zone_id: { mode: "set", value: offer.attached_zone_id } } }, settled);
      } else {
        self.channel.run("ph_composer.zones.faces.attached_zone.create_and_assign", { faces: offer.faces,
          values: { name: offer.name, kind: "other" }, expected_values: expected }, settled);
      }
      panel.repaint();
    });
    dialog.appendChild(ui.actionRow(later, make, true));
    document.body.appendChild(dialog);
    dialog.openModal();
    make.focus();
  };

  /* Closes the offer; the next Zone's is read at once unless `waiting`, when the write it sent reads it. */
  SegmentRows.prototype.closeOffer = function (waiting) {
    if (!this.offering) return;
    this.offering.closeModal(); this.offering.remove(); this.offering = null;
    if (!waiting) this.nextOffer();
  };

  /* "A", "A and B", "A, B and C". */
  function listed(names) {
    if (names.length < 2) return names.join("");
    return names.slice(0, -1).join(", ") + " and " + names[names.length - 1];
  }

  SegmentRows.prototype.dispose = function () {
    this.channel.reset(); this.reads.reset(); this.settings.dispose(); this.closeDelete(); this.renaming = null;
    this.offers = []; if (this.offering) { this.offering.closeModal(); this.offering.remove(); this.offering = null; }
  };

  SegmentRows.headingKey = headingKey;
  return SegmentRows;
});
