/* What the piping screens share: the feature's names, the role words and the one read of the schedule and the
   Piping groups the Piping pill shows. */
PhComposerUI.define("features/piping/shared", ["request", "snapshot"], function (request, snapshot) {
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

  /* A Piping group's name, or for an unnamed one its place in the Model, so two never read alike. */
  function groupLabel(name, path) { return name || "Piping group " + path.join("/"); }

  /* The schedule and the groups walk the Model, so they are read on request and never on a panel refresh
     (context/TECH_STACK.md, "Edge-owned assignments"): when the Piping pill opens and on Refresh. The last completed
     read stays with the revision it was read at, so the screen can say when the Model has changed since. */
  function Read(session, send) {
    this.schedule = request.channel(session, send, "piping-schedule", "query.invoke");
    this.groups = request.channel(session, send, "piping-groups", "query.invoke");
    this.result = null; this.groupRows = null;
    this.error = "";
  }
  Read.prototype.read = function () {
    if (this.busy()) return false;
    this.schedule.run(PREFIX + "schedule.all", {});
    this.groups.run(PREFIX + "groups.all", {});
    return true;
  };
  Read.prototype.busy = function () { return this.schedule.busy() || this.groups.busy(); };
  /* Settles the pending reads from this state; true when either did. A refused read keeps the last good one. */
  Read.prototype.refresh = function (state) {
    var outcome = this.schedule.consume(state), groups = this.groups.consume(state);
    if (groups && groups.status === "completed") this.groupRows = groups.value.groups;
    if (outcome && outcome.status === "completed") {
      this.result = { value: outcome.value, revision: outcome.revision };
      this.error = "";
    } else if (outcome) this.error = snapshot.message(outcome, "The schedule could not be read.");
    if (groups && groups.status !== "completed") {
      this.error = snapshot.message(groups, "The Piping groups could not be read.");
    }
    return Boolean(outcome || groups);
  };
  Read.prototype.value = function () { return this.result ? this.result.value : null; };
  /* Whether the Model has changed since the last read; false with no read yet. */
  Read.prototype.stale = function (state) {
    return Boolean(this.result) && this.result.revision !== state.revision;
  };
  Read.prototype.dispose = function () { this.schedule.reset(); this.groups.reset(); };

  return { PREFIX: PREFIX, TYPES: PREFIX + "pipe_types", SELECTED: PREFIX + "pipes.selected",
    TOOL: PREFIX + "pipe_tool", SYSTEMS: PREFIX + "piping_systems", ROLES: ROLES, roleLabel: roleLabel,
    groupLabel: groupLabel,
    BY_ROLE: { mode: PREFIX + "by_role" }, BY_TYPE: { mode: PREFIX + "by_type" }, Read: Read };
});
