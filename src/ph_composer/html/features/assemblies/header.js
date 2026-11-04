/* Identity, typed hints and the two canonical Ruby thermal results. */
PhComposerUI.define("features/assemblies/header", ["features/assemblies/editor_shared", "snapshot", "unit_field",
  "units", "workspace"],
  function (shared, snapshot, unitFields, units, ui) {
    "use strict";
    var el = ui.element;
    /* A metric's label carries its unit, so its value line is just the number, as on every Builder. */
    function metric(label, value, field, withheld) {
      var root = el("div", "assembly-header-metric"), profile = units.profile(field);
      root.appendChild(el("small", "", label + " " + units.displayUnit(field, profile)));
      var shown = el("strong", "", withheld || ui.blank(value) ? "—" :
        units.format(value, field, profile, { showUnit: false }));
      if (withheld) { shown.setAttribute("data-u-withheld", "");
        shown.setAttribute("aria-label", label + " withheld. " + withheld); }
      root.appendChild(shown);
      return root;
    }
    /* How the U-values were reached, on request: the surface films used, the two results, and anything the
       calculation reported. Nothing here is editable. */
    function information(record, thermal, withheld) {
      var trigger = ui.iconButton("About this Assembly's U-value", "info");
      var bubble = new ui.Bubble(trigger, "About this Assembly's U-value");
      var films = el("p", "", "Surface films (ISO 6946): Rsi " + shared.format(thermal.rsi_m2k_w, shared.R_VALUE) +
        " · Rse " + shared.format(thermal.rse_m2k_w, shared.R_VALUE) +
        (thermal.direction ? " · " + thermal.direction + " heat flow" : "") + ".");
      bubble.content.appendChild(films);
      [["U-value with films", thermal.u_effective_w_m2k], ["U-value construction only", thermal.u_construction_w_m2k]]
        .forEach(function (item) {
          var row = el("div", "phc-property-row");
          row.appendChild(el("span", "", item[0]));
          row.appendChild(el("span", "phc-property-value", withheld || ui.blank(item[1]) ? "—" :
            shared.format(item[1], shared.U_VALUE)));
          bubble.content.appendChild(row);
        });
      var notes = (thermal.warnings || []).concat((record.findings || []).map(function (finding) {
        return snapshot.message(finding, "");
      })).filter(Boolean);
      if (withheld) notes.unshift(withheld);
      if (notes.length) {
        var list = el("ul", "assembly-information-notes");
        notes.forEach(function (note) { list.appendChild(el("li", "", note)); });
        bubble.content.appendChild(list);
      }
      bubble.root.classList.add("assembly-information");
      return bubble.root;
    }
    function header(record, row) {
      var self = this, values = record.values, display = record.display || {}, thermal = display.thermal || {};
      var root = el("header", "assembly-header"), identity = el("div", "assembly-identity");
      // A way back, not an action on the Assembly: a quiet link above the title, which starts at the gutter.
      var back = ui.button("Assemblies", function () { self.close(); });
      back.className = "assembly-back"; back.setAttribute("aria-label", "Back to Assemblies");
      back.setAttribute("data-editor-local", "");
      root.appendChild(back);
      var name = el("div", "assembly-name");
      this.edits.render(name, row, "name");
      identity.appendChild(name);
      var hints = el("div", "assembly-header-hints");
      ["type", "exterior_condition"].forEach(function (key) {
        var cell = el("div", "assembly-hint");
        self.edits.render(cell, row, key);
        hints.appendChild(cell);
      });
      var color = ui.button("", function () {
        if (!self.allowed()) return;
        self.color.open(record, color);
      });
      color.className = "assembly-color";
      color.style.backgroundColor = display.color || values.color || "#ffffff";
      color.setAttribute("aria-label", "Assembly color");
      hints.appendChild(color);
      var advanced = ui.button("Advanced"), bubble = new ui.Bubble(advanced, "Assembly properties");
      var ventilated = el("input");
      ventilated.type = "checkbox";
      ventilated.checked = Boolean(values.ventilated_cladding);
      ventilated.setAttribute("aria-label", "Ventilated cladding");
      ventilated.addEventListener("change", function () {
        self.action("update", { values: { ventilated_cladding: ventilated.checked } },
          { ventilated_cladding: Boolean(values.ventilated_cladding) });
      });
      bubble.content.appendChild(shared.field("Ventilated cladding", ventilated));
      bubble.content.appendChild(el("p", "muted",
        "The exterior film changes; construction resistance stays the same."));
      var notes = el("div");
      self.edits.render(notes, row, "notes");
      bubble.content.appendChild(shared.field("Notes", notes));
      hints.appendChild(bubble.root);
      identity.appendChild(hints);
      root.appendChild(identity);
      var metrics = el("div", "assembly-header-metrics");
      var withheld = thermal.complete !== true ? shared.reason(record) : null;
      metrics.appendChild(metric("Total thickness", display.total_thickness_mm, shared.DIMENSION));
      metrics.appendChild(metric("U-value with films", thermal.u_effective_w_m2k, shared.U_VALUE,
        withheld || (ui.blank(thermal.u_effective_w_m2k) ? shared.reason(record) : null)));
      var construction = metric("U-value construction only", thermal.u_construction_w_m2k, shared.U_VALUE,
        withheld || (ui.blank(thermal.u_construction_w_m2k) ? shared.reason(record) : null));
      construction.classList.add("assembly-construction-metric"); metrics.appendChild(construction);
      metrics.appendChild(information(record, thermal, withheld));
      root.appendChild(metrics);
      if (withheld) root.appendChild(el("p", "assembly-incomplete", withheld));
      return root;
    }
    return { header: header };
  });
