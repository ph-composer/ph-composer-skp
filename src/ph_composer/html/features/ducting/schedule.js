/* The ducting schedule on the Ducting pill, on the shared line-group schedule (html/line_groups/schedule.js): one row
   per run in schedule order, grouped by Ventilator, with its drawn length, quantity and line count; then totals by
   direction and by Ventilator, each line times its quantity, with a Ventilator's missing-run finding beside it. */
PhComposerUI.define("features/ducting/schedule", ["workspace", "fields", "line_groups/schedule",
  "features/ducting/shared"],
function (ui, fields, lineSchedule, shared) {
  "use strict";
  var LENGTH = fields.LENGTH_M, number = lineSchedule.number, header = lineSchedule.header;

  function field(run, name) {
    if (name === "ventilator") return run.ventilator_name || "No Ventilator";
    if (name === "direction") return shared.directionLabel(run.direction);
    if (name === "duct_type_name") return run.duct_type_name || "Missing type";
    return run[name];
  }
  function lengthCell(td, value) { td.textContent = number(value, LENGTH); return true; }
  var VIEW = { field: field, initialGroup: "ventilator",
    cell: function (td, run, name) {
      if (name !== "duct_type_name" || run.duct_type_name) return false;
      td.textContent = "Missing type"; ui.tooltip(td, "Assign a Duct Type to these lines");
      return true;
    },
    columns: [["display_name", "Run"], ["ventilator", "Ventilator"], ["group", "Ducting group"],
      ["direction", "Direction"], ["duct_type_name", "Duct Type"], ["length_m", "Length"], ["quantity", "Quantity"],
      ["line_count", "Lines"]],
    widths: { display_name: 150, ventilator: 130, group: 140, direction: 120, duct_type_name: 120, length_m: 100,
      quantity: 90, line_count: 70 },
    groups: [["ventilator", "Ventilator"], ["group", "Ducting group"], ["direction", "Direction"],
      ["duct_type_name", "Duct Type"]],
    order: function (runs) {
      return runs.map(function (run, index) {
        return Object.assign({ key: run.identifier + "#" + index, order: index }, run);
      });
    },
    placeholder: "Run, Ventilator or Duct Type",
    toggles: { direction: shared.BY_DIRECTION, duct_type_name: shared.BY_TYPE },
    search: function (run) { return [run.display_name, field(run, "ventilator"), run.duct_type_name || ""].join(" "); },
    empty: "No ducts yet. Draw lines in a Ducting group and assign them a Duct Type and a direction.",
    totals: [{ title: "By direction", rows: function (value) { return value.totals.by_direction; },
      key: function (row) { return row.direction; }, widths: { direction: 160, run_count: 80, line_count: 80 },
      columns: function () {
        return [["direction", "Direction"], ["run_count", "Runs"], ["line_count", "Lines"],
          ["length_m", header("Length", LENGTH)]];
      }, cell: function (td, row, name) {
        if (name === "direction") { td.textContent = shared.directionLabel(row.direction); return true; }
        return name === "length_m" && lengthCell(td, row.length_m);
      } },
    { title: "By Ventilator", rows: function (value) { return value.ventilators || []; },
      key: function (row) { return row.ventilator_id; }, widths: { ventilator_name: 160, note: 320 },
      columns: function () {
        return [["ventilator_name", "Ventilator"], ["outdoor_air_length_m", header("Outdoor air", LENGTH)],
          ["exhaust_air_length_m", header("Exhaust air", LENGTH)], ["note", "Note"]];
      }, cell: function (td, row, name) {
        if (name === "ventilator_name") { td.textContent = row.name; return true; }
        if (name !== "note") return lengthCell(td, row[name]);
        td.textContent = (row.findings || []).map(function (finding) { return finding.message; }).join(" ");
        td.classList.toggle("line-group-warning", Boolean(td.textContent));
        return true;
      } }] };

  return { VIEW: VIEW };
});
