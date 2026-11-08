/* The view of model-owned Zone choices. IDs remain the values; labels and colours are presentation. */
PhComposerUI.define("features/zones/zone_options", ["snapshot", "workspace"], function (snapshot, ui) {
  "use strict";
  var COLLECTIONS = { building_segment: "building_segments", level: "levels" };
  /* The colours the options dialog offers: each reads at 4.5:1 or better with its chip ink, clear of the point
     where white and the near-black ink are equally poor (dom.js, chipInk). */
  var PALETTE = ["#1F7478", "#5588BB", "#9977AA", "#CB7854", "#A49C42", "#56936A", "#A95C78", "#7C8694"];
  function read(state) {
    return snapshot.value(state, "ph_composer.zones.options") || {
      building_segments: [], levels: [], default_segment_id: null, adoption: { required: false, sources: [] }
    };
  }
  function list(options, field) { return options[COLLECTIONS[field]] || []; }
  function find(options, field, id) {
    return list(options, field).filter(function (choice) { return choice.id === id; })[0];
  }
  function managed(zone) { return zone.schema_version === 2 || Object.prototype.hasOwnProperty.call(zone.values,
    "building_segment_id"); }
  function value(zone, field) { return zone.values[managed(zone) && COLLECTIONS[field] ? field + "_id" : field]; }
  function label(options, zone, field) {
    if (!managed(zone)) return zone.values[field] || "Not set";
    var id = value(zone, field), choice = find(options, field, id);
    if (choice) return choice.values.name;
    return (zone.display || {})[field] || (id ? "Choose a replacement" : "Not set");
  }
  function colour(options, zone, field) {
    var choice = find(options, field, value(zone, field));
    return choice ? choice.values.colour : (zone.display || {})[field + "_colour"];
  }
  function key(name) { return name.trim().toLowerCase().replace(/[\s_-]+/g, " "); }
  return { read: read, list: list, find: find, managed: managed, value: value, label: label, colour: colour,
    paint: ui.paintChip, PALETTE: PALETTE, key: key, title: function (field) {
      return field === "building_segment" ? "Building Segments" : "Levels"; } };
});
