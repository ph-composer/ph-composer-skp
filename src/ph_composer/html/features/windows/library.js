/* Windows supplies three product presentations and owner-shaped targets to the neutral sidebar. */
PhComposerUI.define("features/windows/library", ["features/windows/editor_shared", "fields", "workspace"],
  function (shared, fields, ui) {
  "use strict";
  var definitions = {
    frames: { title: "Frame Library", localLabel: "Frames in this file", wireKind: "frames",
      properties: [["Manufacturer", "manufacturer"], ["Product code", "product_code"], ["Position", "position"],
      ["Operation", "operation"],
      ["Width", "width_m", fields.WIDTH_M_AS_MM], ["Uf", "uf_w_m2k", fields.U_VALUE],
      ["ψ-g", "psi_g_w_mk", fields.LINEAR_PSI]] },
    glazings: { title: "Glazing Library", localLabel: "Glazings in this file", wireKind: "glazings",
      properties: [["Manufacturer", "manufacturer"], ["Product code", "product_code"],
      ["Ug", "ug_w_m2k", fields.U_VALUE],
      ["g-value", "g_value", fields.FRACTION], ["Description", "description"]] },
    psi_install_types: { title: "Psi-Install Library", localLabel: "Psi-Install Types in this file",
      wireKind: "psi_install_types",
      properties: [["ψ-install", "psi_w_mk", fields.LINEAR_PSI]] }
  };
  function adapter(kind, target) {
    return Object.assign({}, definitions[kind], { read: function (state) { return shared.records(state, kind); },
      name: function (row) { return row.display_label || row.values.name; },
      category: function (row) { return row.values.manufacturer || "manual"; },
      categories: function (state) {
        var seen = {};
        return shared.records(state, kind).map(function (row) { return row.values.manufacturer || "manual"; })
          .filter(function (name) { if (seen[name]) return false; seen[name] = true; return true; })
          .map(function (name) { return { id: name, label: name === "manual" ? "Manual" : name }; });
      }, searchText: function (row) {
        return [row.values.name, row.values.manufacturer, row.values.product_code, row.values.notes].join(" ");
      }, decorate: function (node, row) {
        if (!row.values.color) return;
        // A Frame's swatch is drawn as a frame (its colour as a band round an open centre), so a pale frame
        // colour never reads as an empty checkbox.
        var swatch = ui.element("span", "library-sidebar-swatch" + (kind === "frames" ? " is-frame" : ""));
        swatch.style[kind === "frames" ? "borderColor" : "backgroundColor"] = row.values.color;
        node.appendChild(swatch);
      }, target: target || function () { return { hint: "Choose a target first." }; } });
  }
  function elementTarget(kind, context) {
    var record = context.record, selection = context.selection || {};
    var cell = record && record.values.elements.filter(function (entry) {
      return entry.id === selection.element_id;
    })[0];
    if (!cell || cell.kind !== "glazed") return { hint: "Select a glazed element first." };
    if (kind === "frames" && shared.sides.indexOf(selection.side) < 0) return { hint: "Choose a Frame side." };
    var params = { id: record.id, element_id: cell.id, expected_values: shared.clone(record.values) };
    if (kind === "frames") params.side = selection.side;
    return { params: params };
  }
  return { adapter: adapter, elementTarget: elementTarget };
});
