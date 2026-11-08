/* The words any screen shows for honeybee's face types and boundary conditions. honeybee's own strings
 * are the contract; these are what a user reads (context/UBIQUITOUS_LANGUAGE.md, ui-polish "Words on
 * screen"). One place in the kit, so the faces table, the Classify palette and the Window schedule
 * cannot disagree, and a feature that shows a face type need not reach into Zones.
 */
PhComposerUI.define("face_words", [], function () {
  "use strict";

  var FACE_TYPES = { Wall: "Wall", RoofCeiling: "Roof or ceiling", Floor: "Floor",
    AirBoundary: "Air boundary" };
  var BOUNDARIES = { Outdoors: "Outdoors", Ground: "Ground", Adiabatic: "To neighbour",
    Surface: "Surface", AttachedZone: "Attached zone" };
  // Boundary conditions a chip cannot set on its own, and why. The Classify palette leaves them out
  // and says why once, in its help; a Face that already holds one shows it read only.
  var UNCHOOSABLE = { Surface: "set by Solve adjacencies", AttachedZone: "choose a record below" };
  // honeybee's display hues, the same ones the viewport's Colour-by modes draw
  // (features/zones/faces/colour_modes.rb; tests/face_words_test.js keeps the two equal). A chip takes a
  // light tint of its value's hue, so a table and the viewport say the same thing in the same colour.
  var HUES = {
    face_type: { Wall: [230, 180, 60], RoofCeiling: [128, 20, 20], Floor: [128, 128, 128],
      AirBoundary: [255, 255, 200] },
    boundary_condition: { Outdoors: [64, 180, 255], Ground: [165, 82, 0], Adiabatic: [255, 128, 128],
      Surface: [0, 128, 0], AttachedZone: [255, 255, 200] }
  };
  var TINT = 0.26;

  function label(table, value) {
    if (value === null || value === undefined || value === "") return "";
    return Object.prototype.hasOwnProperty.call(table, value) ? table[value] : String(value);
  }

  /* The chip fill for a face type ("face_type") or boundary condition ("boundary_condition"), as an opaque
     CSS colour, or "" for a value with no hue of its own. Opaque, so a sticky or hovered row cannot show
     through it. */
  function fill(field, value) {
    var hue = HUES[field] && Object.prototype.hasOwnProperty.call(HUES[field], value) ? HUES[field][value] : null;
    if (!hue) return "";
    return "rgb(" + hue.map(function (channel) { return Math.round(255 - (255 - channel) * TINT); }).join(", ") + ")";
  }

  /* Paints a chip's fill for the value it shows: the shared enum pill reads --category-fill. */
  function paintFill(node, field, value) {
    var colour = fill(field, value);
    if (colour) node.style.setProperty("--category-fill", colour);
    else node.style.removeProperty("--category-fill");
  }

  /* A Face is named by what it is and its number among the Faces of that type in `all`, every Face of its Zone:
     Wall 1, Wall 2, Floor 1. Faces with no type yet number among themselves. The name is words on a row and keys
     nothing, so a neighbour's change of type may renumber it without touching a selection or an edit in progress. */
  function faceName(face, all) {
    function typeOf(one) { return (one.values || {}).face_type || ""; }
    var type = typeOf(face);
    var number = all.slice(0, all.indexOf(face) + 1).filter(function (other) { return typeOf(other) === type; }).length;
    return (type ? label(FACE_TYPES, type) : "Face") + " " + number;
  }

  return {
    FACE_TYPES: FACE_TYPES, BOUNDARIES: BOUNDARIES, UNCHOOSABLE: UNCHOOSABLE, HUES: HUES,
    faceType: function (value) { return label(FACE_TYPES, value); },
    faceName: faceName,
    boundary: function (value) { return label(BOUNDARIES, value); },
    fill: fill, paintFill: paintFill
  };
});
