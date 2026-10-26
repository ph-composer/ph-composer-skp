/* What the Thermal Bridges screens share: the feature's names, the group words and the one schedule read
   both subtabs show. */
PhComposerUI.define("features/thermal_bridges/shared", ["request", "snapshot"], function (request, snapshot) {
  "use strict";
  var PREFIX = "ph_composer.thermal_bridges.";
  /* honeybee-ph's stored group strings, shown in METr's words (context/UBIQUITOUS_LANGUAGE.md, "Thermal bridge
     group"). */
  var GROUPS = [{ value: "15-Ambient", label: "Ambient" }, { value: "16-Perimeter", label: "Perimeter" },
    { value: "17-FS/BC", label: "Floor slab / basement ceiling" }];
  function groupLabel(value) {
    var group = GROUPS.filter(function (entry) { return entry.value === value; })[0];
    return group ? group.label : value || "No group";
  }

  /* The schedule walks the Model, about two seconds at 5,000 assigned Edges, so it is read on request and never
     on a panel refresh (context/TECH_STACK.md, "Edge-owned assignments"): the screen asks when it opens and on
     Refresh. The last completed read stays, with the revision it was read at, so a screen can say when the
     Model has changed since. */
  function ScheduleRead(session, send) {
    this.requests = request.channel(session, send, "thermal-bridge-schedule", "query.invoke");
    this.result = null;
    this.error = "";
  }
  ScheduleRead.prototype.read = function () {
    return Boolean(this.requests.run(PREFIX + "schedule.all", {}));
  };
  ScheduleRead.prototype.busy = function () { return this.requests.busy(); };
  /* Settles a pending read from this state; true when it did. A refused read keeps the last good one. */
  ScheduleRead.prototype.refresh = function (state) {
    var outcome = this.requests.consume(state);
    if (!outcome) return false;
    if (outcome.status === "completed") {
      this.result = { value: outcome.value, revision: outcome.revision };
      this.error = "";
    } else this.error = snapshot.message(outcome, "The schedule could not be read.");
    return true;
  };
  ScheduleRead.prototype.value = function () { return this.result ? this.result.value : null; };
  /* Whether the Model has changed since the last read; false with no read yet. */
  ScheduleRead.prototype.stale = function (state) {
    return Boolean(this.result) && this.result.revision !== state.revision;
  };
  /* A type's totals over every run as last read: a zero row for a type with no run, null before any read. */
  ScheduleRead.prototype.totals = function (typeId) {
    var value = this.value();
    if (!value) return null;
    return value.totals.by_type.filter(function (row) { return row.type_id === typeId; })[0] ||
      { type_id: typeId, run_count: 0, edge_count: 0, length_m: 0, heat_loss_w_k: 0 };
  };
  ScheduleRead.prototype.dispose = function () { this.requests.reset(); };

  return { PREFIX: PREFIX, TYPES: PREFIX + "types", SELECTED: PREFIX + "edges.selected", GROUPS: GROUPS,
    groupLabel: groupLabel, ScheduleRead: ScheduleRead };
});
