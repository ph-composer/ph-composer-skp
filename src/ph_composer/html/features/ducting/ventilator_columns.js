/* What ducting contributes to Ventilation › Ventilators, from the `ducting_ventilators` snapshot section: two
   duct-length columns (html/table_contributions.js), each Ventilator's Outdoor air and Exhaust air duct lengths,
   each line times its quantity, read only, a dash while it has no duct of that direction; and to its Delete, the
   Ducting groups linked to it (inventory_forms.js usage), which a replacement takes and clearing leaves with none. */
PhComposerUI.define("features/ducting/ventilator_columns", ["snapshot", "workspace", "fields", "units",
  "unit_preferences", "inventory_forms", "features/mechanical/ventilators", "features/ducting/shared"],
function (snapshot, ui, fields, units, preferences, forms, ventilators, shared) {
  "use strict";
  var LENGTH = fields.LENGTH_M;
  var LABELS = { outdoor_air_length_m: "Outdoor air duct", exhaust_air_length_m: "Exhaust air duct" };
  // A Delete names this many linked groups, then counts the rest.
  var NAMED = 5;

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

  /* "A", "A and B", "A, B and C", or the first NAMED and "and N more". */
  function listed(names, total) {
    var more = total - names.length;
    if (more > 0) return names.join(", ") + " and " + more + " more";
    return names.length < 2 ? names.join("") : names.slice(0, -1).join(", ") + " and " + names[names.length - 1];
  }
  /* The Ducting groups a Ventilator's Delete moves or unlinks, said for the choice made so far. */
  function linkedGroups(state, id, choice) {
    var row = ventilatorRow(state, id);
    if (!row) return null;
    var total = row.group_count || 0, one = total === 1;
    if (!total) return { count: 0, description: "" };
    var names = listed((row.group_names || []).slice(0, NAMED), total), lose = names + " will lose " +
      (one ? "its" : "their") + " Ventilator";
    if (choice === "clear") return { count: total, description: lose + "." };
    if (choice) return { count: total, description: names + (one ? " moves" : " move") + " to the replacement." };
    return { count: total, description: lose + " unless you choose a replacement." };
  }
  forms.contributeUsage(ventilators.SECTION, linkedGroups);
  return { contribution: contribution, linkedGroups: linkedGroups };
});
