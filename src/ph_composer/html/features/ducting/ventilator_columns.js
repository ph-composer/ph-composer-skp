/* The two duct-length columns ducting contributes to Ventilation › Ventilators (html/table_contributions.js): each
   Ventilator's Outdoor air and Exhaust air duct lengths, each line times its quantity, read only, from the
   `ducting_ventilators` snapshot section; a dash while it has no duct of that direction. */
PhComposerUI.define("features/ducting/ventilator_columns", ["snapshot", "workspace", "fields", "units",
  "unit_preferences", "features/mechanical/ventilators", "features/ducting/shared"],
function (snapshot, ui, fields, units, preferences, ventilators, shared) {
  "use strict";
  var LENGTH = fields.LENGTH_M;
  var LABELS = { outdoor_air_length_m: "Outdoor air duct", exhaust_air_length_m: "Exhaust air duct" };

  function ventilatorRow(state, id) {
    return ((snapshot.value(state, shared.VENTILATORS) || {}).ventilators || []).filter(function (row) {
      return row.ventilator_id === id;
    })[0] || null;
  }
  var contribution = { id: shared.PREFIX + "duct_lengths",
    available: function (state) { return Boolean(snapshot.value(state, shared.VENTILATORS)); },
    value: function (row, field, state) {
      var found = ventilatorRow(state, row.record.id);
      return found ? found[field] : null;
    },
    cell: function (td, row, field, value) {
      td.textContent = value ? units.format(value, LENGTH, units.profile(LENGTH, preferences.current()),
        { showUnit: false }) : "—";
      td.classList.add("mech-read-only", "ducting-length");
      ui.tooltip(td, value ? "Read from the drawn ducts, each line times its quantity." :
        "No " + LABELS[field].toLowerCase() + " is drawn for it.");
      return true;
    } };
  // The headers carry the unit the user reads in, so they are named again on every compose.
  Object.defineProperty(contribution, "columns", { enumerable: true, get: function () {
    return Object.keys(LABELS).map(function (field) {
      return [field, units.header(LABELS[field], LENGTH, preferences.current())];
    });
  } });
  ui.contributeTable(ventilators.SECTION, contribution);
  return { contribution: contribution };
});
