/* The Program editor's body: the headline values, then one full-width accordion card per load in the
   order program_loads.js gives, the two EnergyPlus-only loads under their own caption. A closed card shows its
   values and first Schedule on one line, with an amber flag naming what is missing; an open card shows the load's
   values on the left and its Schedules on the right. A rule load shows its rule and inputs, and switches to a fixed
   value and back.

   Every edit is one `programs.update` of the whole load it changes, guarded by that load as the field was drawn
   (`expected_values`), so one Undo step each, and a value changed meanwhile refuses: the panel's notice says why
   and the field shows the Model's value again on the next paint. Typing is held while the field has focus; a
   commit, Escape or a refusal lets the Model's value back in. The host (features/programs/tab.js) owns the
   request and the Schedules: `host.update(row, load, values, expected)`, `host.schedules()` (by id),
   `host.newSchedule(type, done)`, `host.openSchedule(id)` and `host.refuse(text)`. */
PhComposerUI.define("features/programs/program_editor", ["workspace", "features/programs/program_loads"],
function (ui, loads) {
  "use strict";
  var el = ui.element;

  function ProgramEditor(host) {
    this.host = host;
    this.root = el("div", "pgm-editor");
    this.metrics = el("div", "pgm-metrics");
    this.list = el("div", "pgm-loads");
    this.root.appendChild(this.metrics); this.root.appendChild(this.list);
    this.open = Object.create(null);
    this.cards = Object.create(null);
    this.inputs = Object.create(null);
    var self = this;
    this.caption = el("p", "pgm-group", "EnergyPlus only");
    loads.LOADS.forEach(function (definition) {
      if (definition.energyPlus && !self.caption.parentNode) self.list.appendChild(self.caption);
      self.list.appendChild(self.card(definition).root);
    });
  }

  /* ---------------------------------------------------------------- headline values */

  ProgramEditor.prototype.paintMetrics = function (row, zones) {
    var values = row.values, metrics = [["Used by", zones === 1 ? "1 Zone" : zones + " Zones"]];
    [["people", "People", 0], ["lighting", "Lighting", 0], ["electric_equipment", "Equipment", 0]]
      .forEach(function (item) {
        var definition = loads.load(item[0]), entry = definition.values[item[2]], load = values[item[0]];
        metrics.push([item[1] + (load.rule ? "" : " [" + loads.unit(entry) + "]"),
          load.rule ? loads.RULE_LABELS[load.rule] : loads.number(entry, load[entry.key])]);
      });
    var root = this.metrics;
    ui.memoPaint(this, "metrics", metrics, function () {
      root.replaceChildren.apply(root, metrics.map(function (item) {
        var node = el("div", "pgm-metric");
        node.appendChild(el("small", "", item[0])); node.appendChild(el("strong", "", item[1]));
        return node;
      }));
    });
  };

  /* ---------------------------------------------------------------- cards */

  ProgramEditor.prototype.card = function (definition) {
    var self = this, card = { definition: definition, root: el("section", "pgm-card") };
    card.root.setAttribute("data-load", definition.key);
    card.head = ui.button("", function () { self.toggle(definition.key); });
    card.head.className = "pgm-card-head";
    card.head.setAttribute("aria-controls", "pgm-card-body-" + definition.key);
    card.chevron = ui.glyph("chevron"); card.chevron.classList.add("pgm-chev");
    card.title = el("strong", "", definition.label);
    card.head.appendChild(card.chevron); card.head.appendChild(card.title);
    card.tags = el("span", "pgm-tags"); card.head.appendChild(card.tags);
    card.flag = ui.glyph("alert"); card.flag.classList.add("pgm-flag"); card.head.appendChild(card.flag);
    card.summary = el("span", "pgm-sum"); card.head.appendChild(card.summary);
    // The heads read as one list: the arrow keys move between them.
    card.head.addEventListener("keydown", function (event) {
      if (event.key !== "ArrowDown" && event.key !== "ArrowUp") return;
      var heads = loads.LOADS.map(function (entry) { return self.cards[entry.key].head; });
      var next = heads[heads.indexOf(card.head) + (event.key === "ArrowDown" ? 1 : -1)];
      if (next) { event.preventDefault(); next.focus(); }
    });
    card.body = el("div", "pgm-card-body");
    card.body.id = "pgm-card-body-" + definition.key;
    card.body.setAttribute("role", "region");
    card.body.setAttribute("aria-label", definition.label);
    card.root.appendChild(card.head); card.root.appendChild(card.body);
    this.cards[definition.key] = card;
    return card;
  };

  ProgramEditor.prototype.toggle = function (key) {
    this.open[key] = !this.open[key];
    if (this.row) this.paintCard(this.cards[key]);
  };

  ProgramEditor.prototype.render = function (row, context) {
    var record = this.row && this.row.id;
    this.row = row; this.context = context;
    // Another Program starts with its cards as the user left them, its fields drawn afresh.
    if (record !== row.id) this.inputs = Object.create(null);
    this.missing = loads.missingByLoad(row);
    this.paintMetrics(row, context.zones);
    Object.keys(this.cards).forEach(function (key) { this.paintCard(this.cards[key]); }, this);
  };

  ProgramEditor.prototype.paintCard = function (card) {
    var definition = card.definition, values = this.row.values[definition.key], missing = this.missing[definition.key];
    var schedules = this.context.schedules, open = Boolean(this.open[definition.key]);
    card.root.classList.toggle("is-open", open);
    card.head.setAttribute("aria-expanded", String(open));
    card.body.hidden = !open;
    var tags = [];
    if (definition.tag) tags.push(definition.tag);
    if (definition.key === "electric_equipment" && this.row.values.people.rule) {
      tags.push("Devices come from the Equipment Set");
    }
    ui.memoPaint(card, "tags", tags, function () {
      card.tags.replaceChildren.apply(card.tags, tags.map(function (text) { return el("span", "pgm-tag", text); }));
    });
    card.flag.hidden = !missing;
    ui.tooltip(card.flag, missing ? "Missing: " + missing.map(function (key) {
      return loads.fieldLabel(definition, key);
    }).join(", ") : "");
    card.flag.setAttribute("aria-label", missing ? card.flag.getAttribute("data-tooltip") : "");
    card.summary.textContent = loads.summary(definition, values, schedules);
    card.summary.classList.toggle("is-missing", Boolean(missing));
    if (!open) return;
    // Rebuilt only when the card's shape changes; a field the user is in keeps its focus across a rebuild.
    var signature = [this.row.id, values.rule || null, Object.keys(schedules).map(function (id) {
      return id + ":" + schedules[id].values.name + ":" + schedules[id].values.type;
    }).join("|"), values.source || null, loads.system()];
    if (ui.memoPaint(card, "body", signature, null)) {
      // A value field is reused, so it comes back itself; a Schedule select is made anew, so its slot finds it.
      var focused = card.body.contains(document.activeElement) ? document.activeElement : null;
      var slot = focused && focused.getAttribute("data-slot");
      this.buildBody(card);
      var again = slot ? Array.prototype.filter.call(card.body.querySelectorAll("[data-slot]"), function (node) {
        return node.getAttribute("data-slot") === slot;
      })[0] : focused;
      if (again && again !== document.activeElement && card.body.contains(again)) again.focus({ preventScroll: true });
    }
    this.fill(card);
  };

  /* The open card's two columns, built when its shape changes; values are filled in place on every paint. */
  ProgramEditor.prototype.buildBody = function (card) {
    var self = this, definition = card.definition, values = this.row.values[definition.key];
    var left = el("div", "pgm-col"), right = el("div", "pgm-col");
    left.appendChild(el("div", "pgm-col-head", "Load"));
    var rows = el("div", "pgm-rows");
    if (definition.rule && values.rule) {
      var rule = el("div", "pgm-rule");
      rule.appendChild(el("span", "", definition.ruleText));
      rule.appendChild(this.switchButton(card, "Use a fixed value", null));
      rows.appendChild(rule);
      (definition.ruleInputs || []).forEach(function (entry) {
        rows.appendChild(self.valueRow(card, entry));
      });
    } else {
      definition.values.forEach(function (entry) { rows.appendChild(self.valueRow(card, entry)); });
      if (definition.rule) {
        var back = el("div", "pgm-rule is-fixed");
        back.appendChild(this.switchButton(card, "Use the " + loads.RULE_LABELS[definition.rule], definition.rule));
        rows.appendChild(back);
      }
    }
    (definition.more || []).forEach(function (entry) { rows.appendChild(self.valueRow(card, entry)); });
    left.appendChild(rows);
    if (values.source) left.appendChild(el("p", "pgm-src", "From the base program " + values.source + "."));
    right.appendChild(el("div", "pgm-col-head", "Schedules"));
    definition.slots.forEach(function (slot) { right.appendChild(self.slotRow(card, slot)); });
    if (definition.note) right.appendChild(el("p", "pgm-src", definition.note));
    card.body.replaceChildren(left, right);
  };

  ProgramEditor.prototype.switchButton = function (card, label, rule) {
    var self = this, button = ui.button(label, function () {
      var values = self.row.values[card.definition.key];
      self.host.update(self.row, card.definition.key, loads.patched(card.definition, values, "rule", rule), values);
    });
    button.className = "pgm-rule-switch";
    button.disabled = !this.context.enabled;
    return button;
  };

  /* One value: its label with its unit, and an input that commits on Enter or leaving it. */
  ProgramEditor.prototype.valueRow = function (card, entry) {
    var self = this, definition = card.definition, key = definition.key + "." + entry.key;
    var row = el("div", "pgm-row");
    var label = el("label", "", entry.label);
    var unit = loads.unit(entry);
    if (unit && unit !== "1") label.appendChild(el("span", "unit", unit));
    var input = this.inputs[key];
    if (!input) {
      input = this.inputs[key] = el("input", "pgm-input");
      input.type = "text"; input.setAttribute("inputmode", "decimal");
      input.setAttribute("autocomplete", "off"); input.setAttribute("spellcheck", "false");
      input.addEventListener("input", function () {
        // The entry is guarded by the load as it was when typing began.
        // The entry is read in the units it began in, as every unit field's draft is.
        if (!input.typed) {
          input.baseline = JSON.parse(JSON.stringify(self.row.values[definition.key]));
          input.profile = loads.profile(input.entry);
        }
        input.typed = true;
      });
      input.addEventListener("keydown", function (event) {
        if (event.key === "Enter") { event.preventDefault(); self.commit(card, entry, input); }
        if (event.key === "Escape" && input.typed) {
          event.preventDefault(); event.stopPropagation(); input.typed = false; self.fill(card);
        }
      });
      input.addEventListener("blur", function () { self.commit(card, entry, input); });
    }
    input.id = "pgm-input-" + key.replace(".", "-");
    label.setAttribute("for", input.id);
    input.setAttribute("aria-label", definition.label + " " + entry.label.toLowerCase());
    if (entry.blank) input.placeholder = entry.blank;
    else input.placeholder = "—";
    input.entry = entry; input.row = row;
    row.appendChild(label);
    var cell = el("span", "pgm-value");
    cell.appendChild(input);
    row.appendChild(cell);
    return row;
  };

  ProgramEditor.prototype.commit = function (card, entry, input) {
    if (!input.typed) return;
    input.typed = false;
    var definition = card.definition, parsed = loads.parse(entry, input.value, input.profile);
    if (parsed.error) { this.host.refuse(parsed.error); this.fill(card); return; }
    var baseline = input.baseline;
    if (parsed.value === baseline[entry.key] || input.value.trim() === input.seed) { this.fill(card); return; }
    this.host.update(this.row, definition.key, loads.patched(definition, baseline, entry.key, parsed.value),
      baseline);
  };

  /* One Schedule slot: a select of the Schedules of its type, a way to open the one chosen, and + New Schedule. */
  ProgramEditor.prototype.slotRow = function (card, slot) {
    var self = this, definition = card.definition, values = this.row.values[definition.key];
    var row = el("div", "pgm-sched");
    var select = el("select", "phc-choice-pill pgm-slot");
    select.setAttribute("aria-label", definition.label + " " + slot.label.toLowerCase());
    select.setAttribute("data-slot", slot.key);
    select.appendChild(ui.option("", loads.NONE[slot.type]));
    var schedules = this.context.schedules;
    Object.keys(schedules).map(function (id) { return schedules[id]; }).filter(function (schedule) {
      return schedule.values.type === slot.type;
    }).sort(function (a, b) { return ui.compareText(a.values.name, b.values.name); }).forEach(function (schedule) {
      select.appendChild(ui.option(schedule.id, schedule.values.name));
    });
    var current = values[slot.key];
    if (current && !schedules[current]) select.appendChild(ui.option(current, "Missing Schedule"));
    select.disabled = !this.context.enabled;
    select.addEventListener("change", function () {
      var live = self.row.values[definition.key];
      self.host.update(self.row, definition.key, loads.patched(definition, live, slot.key, select.value || null),
        live);
    });
    var label = el("label", "", slot.label);
    select.id = "pgm-slot-" + definition.key + "-" + slot.key;
    label.setAttribute("for", select.id);
    row.appendChild(label); row.appendChild(select);
    var open = ui.iconButton("Open " + slot.label.toLowerCase(), "pencil", function () {
      if (select.value) self.host.openSchedule(select.value);
    });
    open.classList.add("pgm-slot-open");
    row.appendChild(open);
    var add = ui.button("+ New Schedule", function () {
      var program = self.row.id;
      self.host.newSchedule(slot.type, function (id) {
        // The Schedule goes on the Program that asked for it; one opened meanwhile is left alone.
        if (!self.row || self.row.id !== program) return;
        var live = self.row.values[definition.key];
        self.host.update(self.row, definition.key, loads.patched(definition, live, slot.key, id), live);
      });
    });
    add.className = "pgm-slot-new"; add.disabled = !this.context.enabled;
    add.setAttribute("aria-label", "New " + slot.type + " Schedule for " + slot.label.toLowerCase());
    row.appendChild(add);
    row.select = select; row.open = open;
    return row;
  };

  /* Values into the open card's fields, except one being typed into, and the amber of each missing one: a missing
     ventilation rate flags all four terms, since any one sets it. */
  ProgramEditor.prototype.fill = function (card) {
    var definition = card.definition, values = this.row.values[definition.key], enabled = this.context.enabled;
    var missing = this.missing[definition.key] || [];
    function flagged(key) { return missing.indexOf(key) >= 0 || (definition.key === "ventilation" && missing.length &&
      definition.values.some(function (entry) { return entry.key === key; })); }
    Array.prototype.forEach.call(card.body.querySelectorAll(".pgm-input"), function (input) {
      var text = loads.editText(input.entry, values[input.entry.key]);
      // A field being typed into keeps the seed it began with, in the units its draft is read in.
      if (!input.typed || document.activeElement !== input) {
        input.value = text; input.typed = false; input.seed = text;
      }
      input.disabled = !enabled;
      input.row.classList.toggle("is-missing", Boolean(flagged(input.entry.key)));
    });
    Array.prototype.forEach.call(card.body.querySelectorAll(".pgm-sched"), function (row) {
      var slot = row.select.getAttribute("data-slot");
      row.select.value = values[slot] || "";
      row.select.disabled = !enabled;
      row.open.disabled = !row.select.value;
      row.classList.toggle("is-missing", missing.indexOf(slot) >= 0);
    });
    Array.prototype.forEach.call(card.body.querySelectorAll(".pgm-rule-switch, .pgm-slot-new"), function (button) {
      button.disabled = !enabled;
    });
  };

  /* Whether a field holds typing the Model has not taken yet. */
  ProgramEditor.prototype.typing = function () {
    // Typing back to the Model's value holds nothing, as its commit sends nothing.
    return Object.keys(this.inputs).some(function (key) {
      var input = this.inputs[key];
      return input.typed && input.value.trim() !== input.seed;
    }, this);
  };

  return ProgramEditor;
});
