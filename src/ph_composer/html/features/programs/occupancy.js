/* The Occupancy section of the Building Segment settings dialog, and the Single dwelling tag and occupancy findings
   on every Segment heading (context/EXTENSIBILITY.md, "Building Segment settings" and "Zone views").

   The section edits a draft of the Segment's `ph_composer.programs.segment` payload, which Zones' Save sends with
   the other sections in one Undo step: Single dwelling, the default Program for its Zones, and while single the
   house's bedrooms, occupants and Equipment Set. Single dwelling applies only to a residential Segment, so the
   checkbox reads the Phius certification section's draft and is disabled, with the reason, while that says
   non-residential; this section never changes the category. Switching it on names what gives way (each Zone's own
   Program, its Dwellings and their Equipment Sets) and enters the Zones' summed bedrooms, both from Ruby's preview;
   Save is the confirmation. What switching does to the Zones is Ruby's (features/programs/single_dwelling.rb); the
   rows read `ph_composer.programs.zones` through its snapshot section.

   The Single dwelling tag on a heading, and every locked cell of the Zones / Programs view, opens the lock bubble:
   "<Segment> is a single dwelling", why its Zones are locked, and Open settings, which opens the Segment's settings
   dialog through the Zones tab's `segmentSettings` intent. */
PhComposerUI.define("features/programs/occupancy", ["panel", "workspace", "snapshot", "table_views"],
function (panel, ui, snapshot, tableViews) {
  "use strict";
  var NAMESPACE = "ph_composer.programs.segment";
  var CERTIFICATION = "ph_composer.certification.segment";
  var SECTION = "ph_composer.programs.occupancy";
  var FIELDS = ["single_dwelling", "default_program_id", "bedrooms", "occupants", "equipment_set_id"];
  var DEFAULTS = { single_dwelling: true, default_program_id: null, bedrooms: null, occupants: null,
    equipment_set_id: null };
  var RESIDENTIAL_ONLY = "Residential Building Segments only. Set the building category to Residential under " +
    "Phius certification first.";
  var SINGLE = "Its Zones are one dwelling with the residential default.";
  var NUMBER = /^\+?(\d+\.?\d*|\.\d+)$/;
  var LOCKED = "Its Zones are one dwelling with the residential default Program. Bedrooms, occupants and the " +
    "Equipment Set are entered once, on the Building Segment row. Switch Single dwelling off in its settings to " +
    "assign its Zones one by one.";
  var views = typeof WeakMap === "function" ? new WeakMap() : null;
  var lock = null;

  /* The lock bubble, anchored to the tag or cell that opened it; a second press on the same anchor closes it. Its
     root mounts in the workspace, outside the table, so the table's scroller never clips it. */
  function lockBubble(anchor, segment) {
    var open = lock && !lock.panel.hidden && lock.trigger === anchor;
    if (lock) { lock.close(false); if (lock.root.parentNode) lock.root.parentNode.removeChild(lock.root); }
    lock = null;
    if (open) return null;
    var bubble = lock = new ui.Bubble(anchor, segment.name + " is a single dwelling",
      { detachedTrigger: true, ownTrigger: true });
    bubble.root.classList.add("phc-lock-bubble");
    bubble.content.appendChild(ui.element("p", "phc-lock-bubble-text", LOCKED));
    var settings = ui.button("Open settings", function () {
      bubble.close(false);
      panel.navigate("overview", { segmentSettings: segment.id });
    });
    settings.className = "primary";
    var actions = ui.element("div", "phc-lock-bubble-actions");
    actions.appendChild(settings);
    bubble.content.appendChild(actions);
    (anchor.closest(".phc-workspace") || document.body).appendChild(bubble.root);
    bubble.open();
    return bubble;
  }

  function read(state) { return snapshot.value(state, SECTION) || { zones: [], building_segments: [], choices: {} }; }

  function segmentRow(state, id) {
    return read(state).building_segments.filter(function (row) { return row.id === id; })[0] || null;
  }

  /* The typed count: null when blank, the number when it is a decimal of at least 0, else undefined. */
  function parsed(value) {
    if (value === null || value === undefined) return null;
    if (typeof value === "number") return isFinite(value) && value >= 0 ? value : undefined;
    var text = String(value).trim();
    if (text === "") return null;
    return NUMBER.test(text) ? Number(text) : undefined;
  }

  /* Whether the certification draft, or the stored category, makes the Segment residential. */
  function residential(context, row) {
    var draft = context.draft ? context.draft(CERTIFICATION) : null;
    var category = draft && draft.category ? draft.category : (row ? row.category : "residential");
    return category !== "non_residential";
  }

  function field(label, control) {
    var part = ui.element("div", "phc-segment-settings-row");
    part.appendChild(ui.element("span", "phc-segment-settings-label", label));
    part.appendChild(control);
    return part;
  }

  function choice(label, options, value, disabled, changed) {
    var select = ui.element("select");
    select.setAttribute("aria-label", label);
    options.forEach(function (pair) {
      var option = ui.element("option", "", pair[1]);
      option.value = pair[0];
      select.appendChild(option);
    });
    select.value = value === null ? "" : value;
    select.disabled = disabled;
    select.addEventListener("change", function () { changed(select.value === "" ? null : select.value); });
    return select;
  }

  function count(label, value, placeholder, disabled, changed) {
    var input = ui.element("input");
    input.type = "text"; input.setAttribute("type", "text"); input.setAttribute("inputmode", "decimal");
    input.setAttribute("aria-label", label); input.size = 6;
    input.placeholder = placeholder;
    input.value = value === null || value === undefined ? "" : String(value);
    input.disabled = disabled;
    input.addEventListener("input", function () { changed(input.value); });
    return input;
  }

  /* Each pair of a choice list: the Model's default first as null, then the records by name. */
  function options(records, defaultId, defaultLabel) {
    var named = (records || []).filter(function (record) { return record.id === defaultId; })[0];
    return [["", defaultLabel + (named ? " (" + named.name + ")" : "")]].concat((records || [])
      .filter(function (record) { return record.id !== defaultId; })
      .map(function (record) { return [record.id, record.name]; }));
  }

  /* What switching on replaces, in words, from Ruby's preview; empty when nothing gives way. */
  function replaced(preview) {
    if (!preview) return "";
    var parts = [];
    if (preview.programs.length) parts.push(preview.programs.length + " Zone Program" +
      (preview.programs.length === 1 ? "" : "s"));
    if (preview.dwelling_ids.length) parts.push(preview.dwelling_ids.length + " Dwelling" +
      (preview.dwelling_ids.length === 1 ? "" : "s"));
    if (preview.equipment_set_ids.length) parts.push(preview.equipment_set_ids.length + " Equipment Set choice" +
      (preview.equipment_set_ids.length === 1 ? "" : "s"));
    if (!parts.length) return "";
    return "Saving replaces " + parts.join(", ") + " with the house. The Zones' bedrooms are summed into it.";
  }

  function paint(view) {
    var draft = view.draft, context = view.context, row = view.row, choices = view.choices;
    var disabled = Boolean(context.readOnly), allowed = view.allowed = residential(context, row);
    var single = Boolean(draft.single_dwelling) && allowed;
    var part = ui.element("div");

    var box = ui.element("input");
    box.type = "checkbox"; box.setAttribute("type", "checkbox"); box.checked = Boolean(draft.single_dwelling);
    box.setAttribute("aria-label", "Single dwelling");
    box.disabled = disabled || !allowed;
    box.addEventListener("change", function () {
      draft.single_dwelling = box.checked;
      var preview = row && row.single_dwelling_preview;
      // Switching on enters the Zones' summed counts in place of any the Segment kept from before it was switched
      // off, for the user to see and change before saving.
      if (box.checked && preview && !row.settings.single_dwelling) {
        draft.bedrooms = preview.bedrooms; draft.occupants = preview.occupants;
      }
      context.changed(); paint(view);
    });
    var label = ui.element("label", "phc-segment-joins");
    label.appendChild(box);
    label.appendChild(ui.element("span", "", allowed ? SINGLE : RESIDENTIAL_ONLY));
    part.appendChild(field("Single dwelling", label));
    if (single && row && !row.settings.single_dwelling) {
      var words = replaced(row.single_dwelling_preview);
      if (words) part.appendChild(ui.element("p", "phc-zone-option-help", words));
    }

    var program = choice("Default Program for its Zones", options(choices.programs, choices.default_program_id,
      "Model default"), draft.default_program_id, disabled || single, function (value) {
      draft.default_program_id = value; context.changed();
    });
    ui.tooltip(program, single ? "Single dwelling uses the residential default." :
      "Zones with no Program of their own use this one.");
    part.appendChild(field("Default Program for its Zones", program));

    if (single) {
      var name = row ? row.name : "the house";
      part.appendChild(field("Bedrooms in " + name, count("Bedrooms", draft.bedrooms, "?", disabled,
        function (value) { draft.bedrooms = value; context.changed(); })));
      var occupants = count("Occupants", draft.occupants, "Phius rule", disabled,
        function (value) { draft.occupants = value; context.changed(); });
      ui.tooltip(occupants, "Left empty, the Phius rule: bedrooms + 1 per dwelling unit.");
      part.appendChild(field("Occupants", occupants));
      part.appendChild(field("Equipment Set", choice("Equipment Set", options(choices.equipment_sets,
        choices.default_equipment_set_id, "Model default"), draft.equipment_set_id, disabled, function (value) {
        draft.equipment_set_id = value; context.changed();
      })));
      part.appendChild(field("Dwelling units", ui.element("span", "", "1")));
    } else {
      part.appendChild(field("Bedrooms and appliances", ui.element("span", "phc-zone-option-help",
        "Per dwelling, in the Zones table.")));
      part.appendChild(field("Dwelling units", ui.element("span", "", String(row ? row.dwelling_count : 0))));
    }
    view.node.replaceChildren(part);
  }

  panel.segmentSettingsSection(NAMESPACE, {
    title: "Occupancy", order: 20,
    // `draft` is the stored payload, or {} for a Segment with none: a field it lacks shows its default, so an
    // absent payload reads as a single dwelling.
    render: function (segment, draft, context) {
      var node = ui.element("div");
      if (!draft || typeof draft !== "object" || Array.isArray(draft)) {
        node.appendChild(field("Settings", ui.element("span", "", "These settings cannot be read, so they are kept " +
          "as stored.")));
        return node;
      }
      FIELDS.forEach(function (key) {
        if (!Object.prototype.hasOwnProperty.call(draft, key)) draft[key] = DEFAULTS[key];
      });
      var data = read(context.state);
      var view = { draft: draft, context: context, node: node, row: segmentRow(context.state, segment.id),
        choices: data.choices || {} };
      if (views) views.set(context, view);
      paint(view);
      return node;
    },
    // Another section changed: when the category did, the checkbox and its rows follow it. Nothing repaints
    // otherwise, so a field being typed in keeps its focus.
    refresh: function (draft, context) {
      var view = views && views.get(context);
      if (view && residential(context, view.row) !== view.allowed) paint(view);
    },
    validate: function (draft) {
      var problems = [];
      if (parsed(draft.bedrooms) === undefined) problems.push("Enter the bedrooms as a number of at least 0.");
      if (parsed(draft.occupants) === undefined) problems.push("Enter the occupants as a number of at least 0, or " +
        "leave them empty for the Phius rule.");
      return problems;
    },
    collect: function (draft) {
      return { single_dwelling: Boolean(draft.single_dwelling), default_program_id: draft.default_program_id || null,
        bedrooms: parsed(draft.bedrooms), occupants: parsed(draft.occupants),
        equipment_set_id: draft.equipment_set_id || null };
    }
  });

  // The Single dwelling tag and the occupancy findings on each Segment's heading, in every Zone view.
  tableViews.heading("ph_composer.zones", { id: "ph_composer.programs.occupancy", order: 20,
    segmentHeading: function (segment, state) {
      var row = segmentRow(state, segment.id);
      if (!row) return null;
      var bedrooms = row.dwelling ? row.dwelling.bedrooms : null;
      var tags = row.single_dwelling ? [{ text: "Single dwelling", label: segment.values.name + " is a single " +
        "dwelling: why its Zones are locked", tooltip: segment.values.name + " is a single dwelling: its Zones are " +
        "one house with the residential default." + (bedrooms === null ? " Its bedrooms are not entered yet." : ""),
        open: function (anchor) { lockBubble(anchor, { id: segment.id, name: segment.values.name }); } }] : [];
      return { tags: tags, findings: row.findings.map(function (finding) { return { message: finding.message }; }) };
    } });

  /* Closes the lock bubble, if open: a view that leaves, or Escape, takes it with it. Answers whether it was open. */
  function closeLock() {
    var open = Boolean(lock && !lock.panel.hidden);
    if (lock) { lock.close(false); if (lock.root.parentNode) lock.root.parentNode.removeChild(lock.root); }
    lock = null;
    return open;
  }

  return { NAMESPACE: NAMESPACE, FIELDS: FIELDS, DEFAULTS: DEFAULTS, parsed: parsed, read: read,
    lockBubble: lockBubble, closeLock: closeLock };
});
