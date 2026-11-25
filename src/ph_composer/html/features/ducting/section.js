/* Ventilation's ducting pills on the Mechanical tab, after Ventilators: Duct Types (duct_types.js) and Ducting, the
   shared line-group pill (html/line_groups/pill.js) with ducting's assign bar and schedule, opening with the line that
   says which ducts are drawn. */
PhComposerUI.define("features/ducting/section", ["features/mechanical/systems", "features/mechanical/ventilators",
  "line_groups/pill", "features/ducting/shared", "features/ducting/assign_bar", "features/ducting/schedule",
  "features/ducting/duct_types", "features/ducting/ventilator_columns"],
function (systems, ventilators, pills, shared, bars, schedule) {
  "use strict";
  var INTRO = "Draw only the two cold runs between each ventilator and the outside: Outdoor air and Exhaust air.";
  systems.table({ system: ventilators.SYSTEM, id: shared.PREFIX + "ducting", label: "Ducting", order: 30,
    build: function (surface, context) {
      return new pills.Pill(surface, context, shared.SPEC, { types: shared.TYPES, view: schedule.VIEW, intro: INTRO,
        bar: function (session, send, guard, notify, newGroup) {
          return new bars.AssignBar(session, send, guard, notify, newGroup);
        } });
    } });
  return {};
});
