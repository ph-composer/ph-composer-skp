/* Hot Water's piping pills on the Mechanical tab, after Tanks: Pipe Types (pipe_types.js) and Piping, the shared
   line-group pill (html/line_groups/pill.js) with piping's assign bar and schedule. */
PhComposerUI.define("features/piping/section", ["features/mechanical/systems", "features/mechanical/hot_water",
  "line_groups/pill", "features/piping/shared", "features/piping/assign_bar", "features/piping/schedule",
  "features/piping/pipe_types", "features/piping/systems_columns"],
function (systems, hotWater, pills, shared, bars, schedule) {
  "use strict";
  systems.table({ system: hotWater.SYSTEM, id: shared.PREFIX + "piping", label: "Piping", order: 50,
    build: function (surface, context) {
      return new pills.Pill(surface, context, shared.SPEC, { types: shared.TYPES, view: schedule.VIEW,
        bar: function (session, send, guard, notify, makeGroup) {
          return new bars.AssignBar(session, send, guard, notify, makeGroup);
        } });
    } });
  return {};
});
