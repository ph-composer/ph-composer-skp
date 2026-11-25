/* The piping schedule on the Piping pill, on the shared line-group schedule (html/line_groups/schedule.js): one row
   per run, grouped by Hot Water System, each trunk followed by its branches and each branch by its twigs, indented
   beneath it; then totals by role and by System. */
PhComposerUI.define("features/piping/schedule", ["workspace", "fields", "line_groups/schedule",
  "features/piping/shared"],
function (ui, fields, lineSchedule, shared) {
  "use strict";
  var LENGTH = fields.LENGTH_M, TEMPERATURE = fields.TEMPERATURE_C, HOURS = fields.HOURS_PER_DAY;
  var number = lineSchedule.number, header = lineSchedule.header;
  var COLUMNS = [["display_name", "Run"], ["system", "Hot Water System"], ["group", "Piping group"],
    ["role", "Role"], ["parent_name", "Parent"], ["pipe_type_name", "Pipe Type"], ["length_m", "Length"],
    ["line_count", "Lines"], ["values", "Role values"]];

  /* A trunk's multiplier and demand recirculation, or a recirculation run's temperature and hours. */
  function roleValues(run) {
    var values = run.values || {};
    if (run.role === "trunk") {
      return "× " + values.multiplier + (values.demand_recirculation ? " · demand recirculation" : "");
    }
    if (run.role === "recirculation") {
      return number(values.water_temp_c, TEMPERATURE, true) + " · " + number(values.daily_period, HOURS, true);
    }
    return "";
  }
  function field(run, name) {
    if (name === "system") return run.hot_water_system_name || "No Hot Water System";
    if (name === "role") return shared.roleLabel(run.role);
    if (name === "values") return roleValues(run);
    return run[name];
  }
  /* The runs in schedule order with each trunk's branches and each branch's twigs moved beneath it, with depth. Two
     runs may share a derived identifier (two placements of one group), so each row is keyed by its place in the read;
     a child goes under the first run bearing its parent's identifier. */
  function treeOrder(runs) {
    var children = Object.create(null), placed = Object.create(null), first = Object.create(null), ordered = [];
    var keyed = runs.map(function (run, index) { return Object.assign({ key: run.identifier + "#" + index }, run); });
    keyed.forEach(function (run) { if (!first[run.identifier]) first[run.identifier] = run.key; });
    keyed.forEach(function (run) {
      var parent = run.parent && first[run.parent];
      if (parent) (children[parent] = children[parent] || []).push(run);
    });
    function place(run, depth) {
      if (placed[run.key]) return;
      placed[run.key] = true;
      ordered.push(Object.assign({ order: ordered.length, depth: depth }, run));
      (children[run.key] || []).forEach(function (child) { place(child, depth + 1); });
    }
    keyed.forEach(function (run) { if (!(run.parent && first[run.parent])) place(run, 0); });
    keyed.forEach(function (run) { place(run, 0); });
    return ordered;
  }
  function cell(td, run, name, schedule) {
    if (name === "display_name") {
      td.textContent = run.display_name;
      // A branch sits under its trunk and a twig under its branch while the rows keep the schedule's order.
      var tree = schedule.controls.orderBy.value === "order" && ["", "system", "group"].indexOf(
        schedule.controls.groupBy.value) >= 0;
      td.style.paddingLeft = tree && run.depth ? 8 + 16 * run.depth + "px" : "";
      return true;
    }
    if (name === "pipe_type_name" && !run.pipe_type_name) {
      td.textContent = "Missing type"; ui.tooltip(td, "Assign a Pipe Type to these lines"); return true;
    }
    return false;
  }
  function systemCell(td, record, name) {
    if (name === "system_name") { td.textContent = record.name; return true; }
    if (name === "recirculation_temperature_c") td.textContent = number(record[name], TEMPERATURE);
    else if (name === "recirculation_hours") td.textContent = number(record[name], HOURS);
    else td.textContent = number(name === "recirculation_length_m" ? record[name] :
      record.distribution_length_m[name], LENGTH);
    return true;
  }
  var VIEW = { columns: COLUMNS, field: field, cell: cell, order: treeOrder, initialGroup: "system",
    widths: { display_name: 150, system: 140, group: 130, role: 110, parent_name: 120, pipe_type_name: 120,
      length_m: 100, line_count: 70, values: 150 },
    groups: [["system", "Hot Water System"], ["group", "Piping group"], ["role", "Role"],
      ["pipe_type_name", "Pipe Type"]],
    placeholder: "Run, System or Pipe Type", toggles: { role: shared.BY_ROLE, pipe_type_name: shared.BY_TYPE },
    search: function (run) { return [run.display_name, field(run, "system"), run.pipe_type_name || ""].join(" "); },
    empty: "No pipes yet. Draw lines in a Piping group and assign them a Pipe Type and a role.",
    totals: [{ title: "By role", rows: function (value) { return value.totals.by_role; },
      key: function (row) { return row.role; }, widths: { role: 160, run_count: 80, line_count: 80 },
      columns: function () {
        return [["role", "Role"], ["run_count", "Runs"], ["line_count", "Lines"],
          ["length_m", header("Length", LENGTH)]];
      }, cell: function (td, row, name) {
        if (name === "role") { td.textContent = shared.roleLabel(row.role); return true; }
        if (name === "length_m") { td.textContent = number(row.length_m, LENGTH); return true; }
        return false;
      } },
    { title: "By Hot Water System", key: function (row) { return row.hot_water_system_id; },
      rows: function (value) {
        return (value.systems || []).filter(function (row) {
          var lengths = row.distribution_length_m;
          return lengths.trunk + lengths.branch + lengths.twig + row.recirculation_length_m > 0;
        });
      }, widths: { system_name: 160 }, cell: systemCell, columns: function () {
        return [["system_name", "Hot Water System"], ["trunk", header("Trunk", LENGTH)],
          ["branch", header("Branch", LENGTH)], ["twig", header("Twig", LENGTH)],
          ["recirculation_length_m", header("Recirculation", LENGTH)],
          ["recirculation_temperature_c", header("Recirc.", TEMPERATURE)],
          ["recirculation_hours", header("Recirc.", HOURS)]];
      } }] };

  return { VIEW: VIEW };
});
