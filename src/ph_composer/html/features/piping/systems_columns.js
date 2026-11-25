/* The recirculation columns piping contributes to Hot Water › Systems (html/table_contributions.js): each System's
   length-weighted recirculation temperature and hours as honeybee-ph works them out from its recirculation pipes,
   read only, from the `piping_systems` snapshot section. Muted, with the source in the tooltip, while they are
   honeybee-ph's 60 °C and 24 h because no recirculation pipe sets them. */
PhComposerUI.define("features/piping/systems_columns", ["snapshot", "workspace", "fields", "units",
  "unit_preferences", "features/mechanical/hot_water", "features/piping/shared"],
function (snapshot, ui, fields, units, preferences, hotWater, shared) {
  "use strict";
  var QUANTITIES = { recirculation_temperature_c: fields.TEMPERATURE_C, recirculation_hours: fields.HOURS_PER_DAY };

  function systemRow(state, id) {
    return ((snapshot.value(state, shared.SYSTEMS) || {}).systems || []).filter(function (row) {
      return row.hot_water_system_id === id;
    })[0] || null;
  }
  var contribution = { id: shared.PREFIX + "recirculation",
    available: function (state) { return Boolean(snapshot.value(state, shared.SYSTEMS)); },
    value: function (row, field, state) {
      var found = systemRow(state, row.record.id);
      return found ? found[field] : null;
    },
    cell: function (td, row, field, value, state) {
      var found = systemRow(state, row.record.id), descriptor = QUANTITIES[field];
      td.textContent = value === null || value === undefined ? "—" : units.format(value, descriptor,
        units.profile(descriptor, preferences.current()), { showUnit: false });
      td.classList.add("mech-read-only", "piping-recirculation");
      td.classList.toggle("mech-muted", !(found && found.from_piping));
      ui.tooltip(td, found && found.from_piping ? "Read from the recirculation pipes." :
        "honeybee-ph's default until a recirculation pipe is drawn; read only.");
      return true;
    } };
  // The headers carry the unit the user reads in, so they are named again on every compose.
  Object.defineProperty(contribution, "columns", { enumerable: true, get: function () {
    return [["recirculation_temperature_c", units.header("Recirc.", QUANTITIES.recirculation_temperature_c,
      preferences.current())],
    ["recirculation_hours", units.header("Recirc.", QUANTITIES.recirculation_hours, preferences.current())]];
  } });
  ui.contributeTable(hotWater.SECTIONS.systems, contribution);
  return { contribution: contribution };
});
