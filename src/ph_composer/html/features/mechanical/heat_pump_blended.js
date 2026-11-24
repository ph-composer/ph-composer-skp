/* Heat Pumps › Blended result: read only, one block per exported Building Segment whose Zones an indoor unit serves,
   laid out in the Phius Heat Pump Performance Estimator's sections and labels: Inputs for Energy
   Model, Climate Information, Pumps or Fans, Performance Data and Weighted Value Calculations, in the estimator's IP
   units. Every number is the host's (features/mechanical/heat_pumps/blend.rb); this view formats them. The page
   header's action copies the rows in the estimator's layout, tab separated, to paste beside the estimator.

   The heat pump findings (a climate it cannot read, a model it leaves out, cooling over 200 kW) sit above the blocks,
   each sentence once. */
PhComposerUI.define("features/mechanical/heat_pump_blended", ["panel", "snapshot", "workspace",
  "features/mechanical/systems", "features/mechanical/heat_pumps"],
function (panel, snapshot, ui, systems, heatPumps) {
  "use strict";
  var SECTION = heatPumps.SECTIONS.blended;
  var DASH = "—";

  /* A number as the estimator shows it, `digits` after the point, or a dash for none. `plain` leaves out the
     thousands separator, for the copied rows. */
  function number(value, digits, plain) {
    if (typeof value !== "number" || !isFinite(value)) return plain ? "" : DASH;
    return plain ? value.toFixed(digits) : value.toLocaleString("en-US", { minimumFractionDigits: digits,
      maximumFractionDigits: digits });
  }
  function percent(value) { return typeof value === "number" ? number(value * 100, 0) + " %" : DASH; }

  /* The rows of one Segment's blend, section by section: each section a title, its column labels (or none for a
     label-value list) and its rows of [label or name, value...] cells already formatted, each with its plain copy. */
  function sections(blend) {
    var result = blend.result, model = result.energy_model, climate = result.climate;
    function cell(value, digits, unit) {
      return { text: number(value, digits) + (unit && typeof value === "number" ? " " + unit : ""),
        copy: number(value, digits, true) };
    }
    function text(value) { return { text: value === null || value === undefined ? DASH : String(value),
      copy: value === null || value === undefined ? "" : String(value) }; }
    return [
      { title: "Inputs for Energy Model", groups: [
        { caption: "Combined Cooling System Inputs · Cooling via Recirculation Air", rows: [
          [text("Number of Systems Needed"), text(model.systems_needed === null ? "N/A" : model.systems_needed)],
          [text("Space Cooling Coverage"), { text: percent(model.cooling_coverage),
            copy: number(model.cooling_coverage, 2, true) }],
          [text("Minimum Temperature of Cooling Coil"), cell(model.min_coil_temp_f, 1, "°F")],
          [text("Recirculation Air Flow Rate"), cell(model.flow_rate_cfm, 0, "cfm")],
          [text("Recirculation Air Cooling Capacity"), cell(model.cooling_capacity_kbtuh, 1, "kBtu/h")],
          [text("Weighted Recirculation Cooling COP"), cell(model.cooling_cop, 2)]] },
        { caption: "Heat Pump · rated monthly COP: ASHP", rows: [
          [text("Space Heating Coverage"), { text: percent(model.heating_coverage),
            copy: number(model.heating_coverage, 2, true) }],
          [text("Weighted ASHP Heating COP 1"), cell(model.cop_1, 2)],
          [text("Ambient Temperature 1"), cell(model.ambient_1_f, 0, "°F")],
          [text("Weighted ASHP Heating COP 2"), cell(model.cop_2, 2)],
          [text("Ambient Temperature 2"), cell(model.ambient_2_f, 0, "°F")]] }] },
      { title: "Climate Information", groups: [{ caption: "From the Model's climate", rows: [
        [text("99% Dry Bulb Temp."), cell(climate.heating_99_f, 1, "°F")],
        [text("1% Dry Bulb Temp."), cell(climate.cooling_1_f, 1, "°F")],
        [text("Heating Months"), text(climate.heating_months)],
        [text("% Months <17F"), { text: percent(climate.share_below_17f),
          copy: number(climate.share_below_17f, 2, true) }],
        [text("% Months <47F"), { text: percent(climate.share_below_47f),
          copy: number(climate.share_below_47f, 2, true) }]] }] },
      { title: "Pumps or Fans", note: "Not included: fans and pumps tied to the heat pump system are left out of " +
        "this version, so no run-time estimate is needed." },
      { title: "Performance Data", groups: [{ caption: "Air Source Heat Pump Performance Data",
        columns: ["Device(s)", "Qty", "Heating Data Type", "Capacity 17 °F kBtu/h", "Capacity 47 °F kBtu/h",
          "COP 17 °F", "COP 47 °F", "HSPF", "Cooling Data Type", "Capacity 95 °F kBtu/h", "EER", "SEER", "IEER"],
        rows: result.devices.map(function (device) {
          return [text(device.name), text(device.quantity), text(device.heating_data_type),
            cell(device.capacity_17f_kbtuh, 1), cell(device.capacity_47f_kbtuh, 1), cell(device.cop_17f, 2),
            cell(device.cop_47f, 2), cell(device.hspf, 1), text(device.cooling_data_type),
            cell(device.cooling_data_type ? device.capacity_95f_kbtuh : null, 1), cell(device.eer, 1),
            cell(device.seer, 1), cell(device.ieer, 1)];
        }) }] },
      { title: "Weighted Value Calculations", groups: [
        { caption: "Capacity fractions and weighted performance (informative)",
          columns: ["Device Name", "Recirc", "Capacity 17 °F", "Capacity 47 °F", "COP 17 °F", "COP 47 °F", "HSPF",
            "Derated HSPF", "EER", "SEER", "Derated SEER", "IEER", "COP"],
          rows: result.weighted.map(function (row) {
            return [text(row.name), cell(row.recirc, 2), cell(row.capacity_17f, 2), cell(row.capacity_47f, 2),
              cell(row.cop_17f, 2), cell(row.cop_47f, 2), cell(row.hspf, 1), cell(row.derated_hspf, 2),
              cell(row.eer, 2), cell(row.seer, 2), cell(row.derated_seer, 2), cell(row.ieer, 2), cell(row.cop, 2)];
          }) },
        { caption: "Totals", columns: ["", "Total Capacity kBtu/h", "Input Power kBtu/h", "COP"],
          rows: [["cooling", "Cooling"], ["heating_17f", "Heating at 17 °F"], ["heating_47f", "Heating at 47 °F"]]
            .map(function (entry) {
              var total = result.totals[entry[0]];
              return [text(entry[1]), cell(total.capacity_kbtuh, 1), cell(total.input_kbtuh, 1), cell(total.cop, 2)];
            }) }] }];
  }

  /* Every row of every Segment, tab separated, in the estimator's order. */
  function copyText(blends) {
    var lines = [];
    blends.forEach(function (blend) {
      lines.push("Building Segment\t" + blend.segment);
      sections(blend).forEach(function (section) {
        lines.push(section.title);
        if (section.note) lines.push(section.note);
        (section.groups || []).forEach(function (group) {
          lines.push(group.caption);
          if (group.columns) lines.push(group.columns.join("\t"));
          group.rows.forEach(function (row) {
            lines.push(row.map(function (cell) { return cell.copy; }).join("\t"));
          });
        });
      });
      lines.push("");
    });
    return lines.join("\n");
  }

  function Blended(root) {
    var self = this;
    this.root = root;
    this.notes = ui.element("div", "mech-blend-notes");
    this.notes.setAttribute("role", "status");
    this.body = ui.element("div", "mech-blend");
    root.appendChild(this.notes);
    root.appendChild(this.body);
    this.blends = [];
    this.create = ui.button("Copy for the estimator", function () { self.copy(); });
    this.create.setAttribute("aria-label", "Copy the blended result's rows for the Phius estimator");
  }
  /* Copies within the click, which the HtmlDialog needs; the clipboard API is the second try. */
  Blended.prototype.copy = function () {
    if (!this.blends.length) return;
    var text = copyText(this.blends), field = ui.element("textarea", "mech-copy-buffer");
    field.value = text;
    field.setAttribute("aria-hidden", "true");
    document.body.appendChild(field);
    field.select();
    var copied = false;
    try { copied = document.execCommand && document.execCommand("copy"); } catch (error) { copied = false; }
    document.body.removeChild(field);
    var done = function () { panel.notify("Copied the blended result for the Phius estimator.", "success"); };
    var clipboard = window.navigator && window.navigator.clipboard;
    if (copied) done();
    else if (clipboard && clipboard.writeText) {
      clipboard.writeText(text).then(done, function () {
        panel.notify("The clipboard refused the rows; copy them from the tables.", "warning");
      });
    } else panel.notify("The clipboard refused the rows; copy them from the tables.", "warning");
  };
  Blended.prototype.render = function (state) {
    var value = snapshot.value(state, SECTION);
    this.blends = value ? value.segments : [];
    var signature = JSON.stringify(value || null);
    this.create.disabled = !this.blends.length;
    if (signature === this.signature) return;
    this.signature = signature;
    var seen = Object.create(null), lines = [];
    ((value || {}).findings || []).forEach(function (found) {
      if (seen[found.message]) return;
      seen[found.message] = true;
      var line = ui.element("p", "mech-blend-note is-" + found.severity, found.message);
      lines.push(line);
    });
    this.notes.replaceChildren.apply(this.notes, lines);
    if (!value) { this.body.replaceChildren(ui.element("p", "mech-muted", "Reading the heat pumps...")); return; }
    if (!this.blends.length) {
      this.body.replaceChildren(ui.element("p", "mech-blend-empty", value.climate.state === "missing" ?
        "No blend while the Model's climate is incomplete." :
        "No blend yet: an indoor unit serves no Zone in a Building Segment, or its outdoor model lacks values."));
      return;
    }
    this.body.replaceChildren.apply(this.body, this.blends.map(function (blend) { return segmentBlock(blend); }));
  };
  Blended.prototype.guard = function () { return null; };
  Blended.prototype.dispose = function () {};

  function segmentBlock(blend) {
    var block = ui.element("section", "mech-blend-segment");
    block.setAttribute("aria-label", "Blended heat pump of " + blend.segment);
    block.appendChild(ui.element("h3", "mech-blend-title", blend.segment));
    var zones = blend.zones.map(function (zone) { return zone.name; });
    block.appendChild(ui.element("p", "mech-blend-lede", "One heat pump, written to " + zones.length +
      (zones.length === 1 ? " Zone: " : " Zones: ") + zones.join(", ") + ". Values in the estimator's IP units."));
    sections(blend).forEach(function (section) {
      block.appendChild(ui.element("h4", "mech-blend-section", section.title));
      if (section.note) block.appendChild(ui.element("p", "mech-muted", section.note));
      if (!section.groups) return;
      var groups = ui.element("div", "mech-blend-groups");
      section.groups.forEach(function (group) { groups.appendChild(groupTable(group)); });
      block.appendChild(groups);
    });
    return block;
  }
  function groupTable(group) {
    var wrap = ui.element("div", "mech-blend-scroll"), table = ui.element("table", "phc-table mech-blend-table");
    table.appendChild(ui.element("caption", "", group.caption));
    if (group.columns) {
      var head = ui.element("thead"), headRow = ui.element("tr");
      group.columns.forEach(function (label, index) {
        var th = ui.element("th", index ? "is-number" : "", label);
        th.setAttribute("scope", "col");
        headRow.appendChild(th);
      });
      head.appendChild(headRow);
      table.appendChild(head);
    }
    var body = ui.element("tbody");
    group.rows.forEach(function (row) {
      var tr = ui.element("tr");
      row.forEach(function (cell, index) {
        var td = ui.element(index || !group.columns ? "td" : "th", index ? "is-number" : "", cell.text);
        if (!index) td.setAttribute("scope", "row");
        tr.appendChild(td);
      });
      body.appendChild(tr);
    });
    table.appendChild(body);
    wrap.appendChild(table);
    return wrap;
  }

  systems.table({ system: heatPumps.SYSTEM, id: SECTION, label: "Blended result", order: 50,
    build: function (surface) { return new Blended(surface); } });
  return { Blended: Blended, copyText: copyText, sections: sections };
});
