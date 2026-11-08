/* Authored definitions, canonical thermal results and the unit descriptors shared by Window screens. */
PhComposerUI.define("features/windows/editor_shared", ["fields", "snapshot", "units"], function (fields, snapshot,
  units) {
  "use strict";
  var PREFIX = "ph_composer.windows.";
  var DIMENSION = fields.with(fields.LENGTH_M, { scope: "ph_composer.windows.types", label: "Dimension",
    allowBlank: true, allowZero: false });
  function records(state, kind) { return (snapshot.value(state, PREFIX + kind) || {}).records || []; }
  function flat(record) { return Object.assign({ id: record.id }, record.values); }
  function windowsState(state) {
    var products = {};
    ["frames", "glazings", "psi_install_types"].forEach(function (kind) {
      products[kind] = records(state, kind).map(flat);
    });
    return { constituents: products };
  }
  /* Position is free text on a Frame. These are the words that say a Frame belongs on a slot: a jamb serves either
     side, which also holds through the Interior view's mirrored labels. */
  var POSITION_WORDS = { top: /\b(head|top)\b/i, bottom: /\b(sill|bottom)\b/i, left: /\b(jamb|side|left|right)\b/i,
    right: /\b(jamb|side|left|right)\b/i };
  function framePositionFits(side, position) { return POSITION_WORDS[side].test(position || ""); }
  function format(value, field, options) {
    return value == null ? "Unavailable" : units.format(value, field, units.profile(field), options);
  }
  function bare(value, field) {
    return value == null ? "—" : field ? units.format(value, field, units.profile(field), { showUnit: false }) :
      Number(value).toFixed(3);
  }
  return { PREFIX: PREFIX, sides: ["top", "right", "bottom", "left"], WINDOW_DIMENSION: DIMENSION,
    VIEW_SIDES: [{ id: "exterior", label: "Exterior view" }, { id: "interior", label: "Interior view" }],
    U_VALUE: fields.U_VALUE, AREA: fields.AREA_M2, LENGTH: fields.LENGTH_M, LINEAR_PSI: fields.LINEAR_PSI,
    HEAT_LOSS: fields.HEAT_LOSS, AUDIT_DETAIL: { precision: 6 }, records: records,
      flat: flat,
    clone: function (value) { return JSON.parse(JSON.stringify(value)); }, format: format, bare: bare,
    windowsState: windowsState, framePositionFits: framePositionFits,
    unitless: function (value) { return bare(value); },
    INSTALL_SOURCES: { "default": "Model default", shared: "Shared edge", partial: "Partly shared edge" },
    CARD_COLUMNS: [["U-Value", fields.U_VALUE], ["Width", DIMENSION], ["g-Value", null],
      ["ψ-install", fields.LINEAR_PSI]] };
});
