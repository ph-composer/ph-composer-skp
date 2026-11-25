/* What the ducting screens share: the feature's names, the direction words and its line group spec, which the shared
   line-group screens (html/line_groups/) read ducting by. */
PhComposerUI.define("features/ducting/shared", ["features/mechanical/ventilators"], function (ventilators) {
  "use strict";
  var PREFIX = "ph_composer.ducting.";
  /* The stored directions in the order every list of them keeps, and the words shown for them
     (context/UBIQUITOUS_LANGUAGE.md, "Direction"). */
  var DIRECTIONS = [{ value: "outdoor_air", label: "Outdoor air" }, { value: "exhaust_air", label: "Exhaust air" }];
  function directionLabel(value) {
    var direction = DIRECTIONS.filter(function (entry) { return entry.value === value; })[0];
    return direction ? direction.label : value || "No direction";
  }
  var SPEC = { prefix: PREFIX, key: "ducting", label: "Ducting group", noun: "duct", plural: "Ducts",
    typeLabel: "Duct Type", selected: PREFIX + "ducts.selected",
    link: { key: "ventilator_id", label: "Ventilator", section: ventilators.SECTION },
    words: { "ducting.group_in_zone": "A Zone holds it, so its ducts cannot be assigned or exported.",
      "ducting.group_nested": "It sits inside another Ducting group, so its ducts cannot be assigned or exported." } };

  return { PREFIX: PREFIX, TYPES: PREFIX + "duct_types", VENTILATORS: PREFIX + "ducting_ventilators", SPEC: SPEC,
    DIRECTIONS: DIRECTIONS, directionLabel: directionLabel,
    BY_DIRECTION: { mode: PREFIX + "by_direction" }, BY_TYPE: { mode: PREFIX + "by_type" } };
});
