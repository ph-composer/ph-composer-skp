/* The U-value audit: every Window Type's calculation, term by term. */
PhComposerUI.define("features/windows/audit", ["units", "features/windows/editor_shared", "workspace"],
  function (units, shared, ui) {
  "use strict";
  var el = ui.element;
  var U_VALUE = shared.U_VALUE, AREA = shared.AREA, LENGTH = shared.LENGTH, LINEAR_PSI = shared.LINEAR_PSI,
    HEAT_LOSS = shared.HEAT_LOSS,
    AUDIT_DETAIL = shared.AUDIT_DETAIL, format = shared.format;
  var methods = {};
  /* The method's symbols take their PH subscripts: "U_w" is set as U with a subscript w. */
  function subscripted(node, text) {
    var buffer = "";
    text.split(/([A-Za-z\u03c8]_[a-z,]+)/).forEach(function (part) {
      var symbol = /^([A-Za-z\u03c8])_([a-z,]+)$/.exec(part);
      if (!symbol) { buffer += part; return; }
      node.appendChild(el("span", "", buffer + symbol[1])); node.appendChild(el("sub", "", symbol[2])); buffer = "";
    });
    if (buffer) node.appendChild(el("span", "", buffer));
    return node;
  }

  methods.paintAudit = function () {
    if (this.surface !== "audit") return;
    var profile = units.profile(HEAT_LOSS);
    // The windows section carries no generation, so the records themselves are the input.
    if (!ui.memoPaint(this, "audit", [this.entries, profile])) return;
    var expanded = Array.prototype.map.call(this.audit.querySelectorAll("details"), function (node) {
      return node.open; });
    this.audit.replaceChildren(); this.audit.appendChild(el("h2", "", "Window Type calculation audit"));
    this.audit.appendChild(subscripted(el("p", "window-audit-method"), "Uninstalled U_w = (A_g·U_g + ΣA_f·U_f + " +
      "ΣL_g·ψ_g) / A. Installed effective U adds ΣL·ψ_install / A. Coefficients are " +
      units.displayUnit(HEAT_LOSS, profile) + "; no intermediate rounding. Missing terms withhold dependent totals."));
    // One row per Window Type, its two results in columns under one heading row; the terms open beneath it.
    var heading = el("div", "window-audit-columns");
    var unit = units.displayUnit(U_VALUE, units.profile(U_VALUE));
    ["Window Type", "U_w " + unit, "Installed U_w " + unit].forEach(function (label) {
      heading.appendChild(subscripted(el("span"), label)); });
    var list = el("div", "window-audit-list"); list.appendChild(heading); this.audit.appendChild(list);
    this.entries.forEach(function (entry) {
      var calc = entry.calculation, group = el("details", "window-audit-type"), summary = el("summary");
      summary.appendChild(el("span", "window-audit-name", entry.record.name));
      summary.appendChild(el("span", "window-audit-value", shared.bare(calc.uw_w_m2k, U_VALUE)));
      summary.appendChild(el("span", "window-audit-value", shared.bare(calc.u_effective_w_m2k, U_VALUE)));
      group.appendChild(summary);
      group.appendChild(el("p", "", "Glazed gross area " + format(calc.area_m2, AREA) + " · Empty wall area " +
        format(calc.empty_area_m2, AREA)));
      (calc.elements || []).forEach(function (detail) {
        var cell = entry.record.elements.filter(function (c) { return c.id === detail.id; })[0];
          var child = el("details"); child.appendChild(el("summary", "", cell.name + " · Uw " + format(detail.uw_w_m2k,
          U_VALUE)));
        child.appendChild(el("p", "", "Ag " + format(detail.glazing_area_m2, AREA, AUDIT_DETAIL) + " · Af " +
          format(detail.frame_area_m2, AREA, AUDIT_DETAIL) + " · Hg " + format(detail.h_glazing_w_k, HEAT_LOSS,
          AUDIT_DETAIL)));
        (detail.edges || []).forEach(function (edge) { child.appendChild(el("p", "", edge.side + ": Af " +
          format(edge.frame_area_m2, AREA, AUDIT_DETAIL) + " · Lg " + format(edge.glass_edge_m, LENGTH,
          AUDIT_DETAIL) + " · Hf " + format(edge.h_frame_w_k, HEAT_LOSS, AUDIT_DETAIL) + " · Hψg " +
          format(edge.h_spacer_w_k, HEAT_LOSS, AUDIT_DETAIL) + " · installation " + edge.install.source + " · ψ " +
          format(edge.install.psi_w_mk, LINEAR_PSI, AUDIT_DETAIL) + " · L " + format(edge.length_m, LENGTH,
          AUDIT_DETAIL))); });
        var reasons = this.elementFindings(cell, detail);
        child.appendChild(el("p", "", Object.keys(reasons).map(function (key) {
          return reasons[key].length ? ui.titleCase(key) + ": " + reasons[key].join(", ") : "";
        }).filter(Boolean).join(" · "))); group.appendChild(child);
      }, this);
      entry.record.elements.filter(function (cell) { return cell.kind === "empty"; }).forEach(function (cell) {
        group.appendChild(el("p", "", cell.name + " · Empty, excluded wall area; no window thermal contribution."));
      });
      (calc.findings || []).forEach(function (finding) { group.appendChild(el("p", "", finding.message)); });
      list.appendChild(group);
    }, this);
    Array.prototype.forEach.call(this.audit.querySelectorAll("details"), function (node, index) {
      node.open = Boolean(expanded[index]); });
  };

  return methods;
});
