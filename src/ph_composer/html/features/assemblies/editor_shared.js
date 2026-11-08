/* Drawing facts and record lookup only. Canonical thermal results come from the Assembly snapshot. */
PhComposerUI.define("features/assemblies/editor_shared", ["fields", "snapshot", "units", "unit_preferences",
  "workspace"],
  function (fields, snapshot, units, preferences, ui) {
    "use strict";
    var DIMENSION = fields.with(fields.LENGTH_MM, { scope: "ph_composer.assemblies.assemblies", label: "Dimension",
      allowBlank: false, allowZero: false });
    var OPTIONAL_DIMENSION = fields.with(DIMENSION, { allowBlank: true });
    function lookup(records) {
      var result = Object.create(null);
      (records || []).forEach(function (record) {
        result[record.id] = Object.assign({ id: record.id }, record.values);
      });
      return result;
    }
    function selected(record, selection) {
      var found;
      if (!record || !selection) return null;
      (record.values.layers || []).some(function (layer, layerIndex) {
        if (layer.id !== selection.layerId) return false;
        return (layer.segments || []).some(function (segment, segmentIndex) {
          if (segment.id !== selection.segmentId) return false;
          found = { layer: layer, layerIndex: layerIndex, segment: segment, segmentIndex: segmentIndex };
          return true;
        });
      });
      return found || null;
    }
    function reason(record) {
      var thermal = (record.display || {}).thermal || {};
      return (thermal.message_parts || []).map(function (line) { return units.formatParts(line); })
        .filter(Boolean).join(" ") || (thermal.warnings || []).join(" ") ||
        (record.findings || []).map(function (finding) { return snapshot.message(finding, ""); }).join(" ") ||
        "Complete every Layer-Segment before a U-value can be shown.";
    }
    function format(value, field) { return units.format(value, field, units.profile(field)); }
    function field(label, control) {
      var root = ui.element("label", "assembly-inline-field", label);
      root.appendChild(control);
      return root;
    }
    function clone(value) { return JSON.parse(JSON.stringify(value)); }
    /* A new Layer or Layer-Segment starts at a round size in the units on screen (100 mm or 4 in thick,
       500 mm or 20 in wide), so it draws at once; the user resizes it afterwards. */
    function newSize(kind) {
      var ip = preferences.current().unitSystem === "IP";
      return kind === "layer" ? (ip ? 101.6 : 100) : (ip ? 508 : 500);
    }
    return { DIMENSION: DIMENSION, OPTIONAL_DIMENSION: OPTIONAL_DIMENSION, U_VALUE: fields.U_VALUE,
      R_VALUE: fields.R_VALUE, lookup: lookup, selected: selected, reason: reason, format: format,
      field: field, clone: clone, newSize: newSize };
  });
