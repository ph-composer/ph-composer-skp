/* What the piping screens share: the feature's names, the role words and its line group spec, which the shared
   line-group screens (html/line_groups/) read piping by. */
PhComposerUI.define("features/piping/shared", ["features/mechanical/hot_water"], function (hotWater) {
  "use strict";
  var PREFIX = "ph_composer.piping.";
  /* The stored role words in the order every list of them keeps, and the words shown for them
     (context/UBIQUITOUS_LANGUAGE.md, "Pipe role"). */
  var ROLES = [{ value: "trunk", label: "Trunk" }, { value: "branch", label: "Branch" },
    { value: "twig", label: "Twig" }, { value: "recirculation", label: "Recirculation" }];
  function roleLabel(value) {
    var role = ROLES.filter(function (entry) { return entry.value === value; })[0];
    return role ? role.label : value || "No role";
  }
  var SPEC = { prefix: PREFIX, key: "piping", label: "Piping group", noun: "pipe", plural: "Pipes",
    typeLabel: "Pipe Type", selected: PREFIX + "pipes.selected",
    link: { key: "hot_water_system_id", label: "Hot Water System", section: hotWater.SECTIONS.systems },
    words: { "piping.group_in_zone": "A Zone holds it, so its pipes cannot be assigned or exported.",
      "piping.group_nested": "It sits inside another Piping group, so its pipes cannot be assigned or exported." } };

  return { PREFIX: PREFIX, TYPES: PREFIX + "pipe_types", TOOL: PREFIX + "pipe_tool",
    SYSTEMS: PREFIX + "piping_systems", ROLES: ROLES, roleLabel: roleLabel, SPEC: SPEC,
    BY_ROLE: { mode: PREFIX + "by_role" }, BY_TYPE: { mode: PREFIX + "by_type" } };
});
