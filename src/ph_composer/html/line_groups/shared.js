/* What every line group's screens share, naming no feature (the panel side of src/ph_composer/line_groups/): the
   one read of the schedule and the groups a feature's pill shows, a group occurrence's label, and the used-length
   parts of its type table. A feature describes itself once, in a spec:

     { prefix: "ph_composer.<feature>.", key (its request labels), label (its group's word, "<Kind> group"),
       noun (an assigned line's word, singular), plural (the same, capitalised), typeLabel (its type kind's word),
       selected (the selection section), link: { key (the group's linked id), label (that kind's word), section
       (its snapshot section) }, words: { finding code: sentence } } */
PhComposerUI.define("line_groups/shared", ["request", "snapshot", "workspace", "fields", "units", "unit_preferences"],
function (request, snapshot, ui, fields, units, preferences) {
  "use strict";
  var USED = fields.with(fields.LENGTH_M, { label: "Used length" });

  /* A group's name, or for an unnamed one its place in the Model, so two never read alike. */
  function groupLabel(spec, name, path) { return name || spec.label + " " + path.join("/"); }

  /* The schedule and the groups walk the Model, so they are read on request and never on a panel refresh
     (context/TECH_STACK.md, "Edge-owned assignments"): when the pill opens and on Refresh. The last completed
     read stays with the revision it was read at, so the screen can say when the Model has changed since. */
  function Read(session, send, spec) {
    this.spec = spec;
    this.schedule = request.channel(session, send, spec.key + "-schedule", "query.invoke");
    this.groups = request.channel(session, send, spec.key + "-groups", "query.invoke");
    this.result = null; this.groupRows = null;
    this.error = "";
  }
  Read.prototype.read = function () {
    if (this.busy()) return false;
    this.schedule.run(this.spec.prefix + "schedule.all", {});
    this.groups.run(this.spec.prefix + "groups.all", {});
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
      this.error = snapshot.message(groups, "The " + this.spec.label + "s could not be read.");
    }
    return Boolean(outcome || groups);
  };
  Read.prototype.value = function () { return this.result ? this.result.value : null; };
  /* Whether the Model has changed since the last read; false with no read yet. */
  Read.prototype.stale = function (state) {
    return Boolean(this.result) && this.result.revision !== state.revision;
  };
  Read.prototype.dispose = function () { this.schedule.reset(); this.groups.reset(); };

  /* A type table's Colour cell form, held as an equipment table part so an open one holds the tab. */
  function ColourPart(form) { this.form = form; }
  ColourPart.prototype.busy = function () { return this.form.requests.busy(); };
  ColourPart.prototype.guard = function () { return this.form.root.hidden ? null : "Finish or cancel the open form."; };
  ColourPart.prototype.refresh = function (state, records) { this.form.refresh(state, true, records); };
  ColourPart.prototype.dispose = function () { this.form.dispose(); };
  /* The colour a type returns to once its own is cleared: the one it took when it was made, for the colour form's
     Reset to default. */
  function assignedColor(record) { return record.values.assigned_color || null; }

  function length(value, showUnit) {
    return units.format(value || 0, USED, units.profile(USED, preferences.current()), { showUnit: showUnit });
  }
  /* The lines a type's Delete moves or clears, from the used length the snapshot measured. */
  function usage(spec, records, id) {
    var record = records.filter(function (entry) { return entry.id === id; })[0];
    var used = record ? record.used_length_m || 0 : 0;
    return { count: used > 0 ? 1 : 0, description: spec.plural + " " + length(used, true) + " long use it." };
  }
  /* A type's used length, read only, with what it counts in the tooltip. */
  function usedCell(td, record, tooltip) {
    td.textContent = length(record.used_length_m, false);
    td.classList.add("line-group-read-only");
    ui.tooltip(td, tooltip);
  }

  return { groupLabel: groupLabel, Read: Read, ColourPart: ColourPart, assignedColor: assignedColor, USED: USED,
    usage: usage, usedCell: usedCell };
});
