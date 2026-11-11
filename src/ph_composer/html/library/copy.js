/* Frozen copy/reuse decisions. A placement supplies an owner-shaped assignment; the coordinator owns the write. */
PhComposerUI.define("library/copy", ["request", "units", "workspace"], function (request, units, ui) {
  "use strict";
  var el = ui.element;
  var LOADING = "The library is still loading.";
  function freeze(value) { return JSON.parse(JSON.stringify(value)); }
  function Copy(session, send, adapter, changed) {
    var self = this;
    this.adapter = adapter; this.changed = changed; this.requests = request.channel(session, send, "library-copy");
    this.root = ui.formDialog("library-source-review", function () { self.close(); });
    this.title = el("h2", "", "Review library copy"); this.root.appendChild(this.title);
    this.explanation = el("p", "muted"); this.root.appendChild(this.explanation);
    this.candidates = el("select"); this.candidates.setAttribute("aria-label", "Local copy");
    this.candidates.addEventListener("change", function () { self.compare(); });
    this.root.appendChild(this.candidates);
    this.comparison = el("div", "library-source-comparison"); this.root.appendChild(this.comparison);
    this.error = el("p", "cell-error"); this.error.setAttribute("role", "status"); this.root.appendChild(this.error);
    this.cancel = ui.button("Cancel", function () { self.close(); });
    this.localButton = ui.button("Use local copy", function () { self.apply("keep_local"); });
    this.libraryButton = ui.button("Use library copy", function () { self.apply("use_library"); });
    this.libraryButton.className = "primary";
    this.cancel.setAttribute("aria-label", "Cancel");
    this.libraryButton.setAttribute("aria-label", "Use library copy");
    var choices = ui.actionRow(this.cancel, this.libraryButton); choices.classList.add("library-review-choices");
    choices.insertBefore(this.localButton, this.libraryButton); this.root.appendChild(choices);
  }
  Copy.prototype.busy = function () { return this.requests.busy(); };
  Copy.prototype.open = function (row, assignment) {
    if (this.disposed || this.enabled === false || this.busy()) return false;
    this.held = { row: freeze(row), assignment: assignment ? freeze(assignment) : null };
    this.title.textContent = "Review " + row.display_label;
    this.error.textContent = ""; this.candidates.replaceChildren();
    var candidates = row.resolution.candidates;
    this.explanation.textContent = row.resolution.outcome === "ambiguous_source" ||
      row.resolution.outcome === "ambiguous_name" ? "Choose a local definition. No copy is selected automatically." :
      "Keep local values or replace copied properties from this library. Local user data is preserved.";
    var blank = el("option", "", "Choose a local copy…"); blank.value = ""; this.candidates.appendChild(blank);
    candidates.forEach(function (candidate, index) {
      var label = candidate.display_label || "Unlabelled";
      if (candidates.filter(function (other) { return (other.display_label || "Unlabelled") === label;
      }).length > 1) label += " (local copy " + (index + 1) + ")";
      var option = el("option", "", label);
      option.value = candidate.id;
      this.candidates.appendChild(option);
    }, this);
    this.candidates.value = candidates.length === 1 ? candidates[0].id : "";
    this.compare(); this.root.openModal(); this.changed(); return true;
  };
  Copy.prototype.candidate = function () {
    var selected = this.candidates.value;
    return this.held && this.held.row.resolution.candidates.filter(function (row) { return row.id === selected; })[0];
  };
  Copy.prototype.compare = function () {
    var candidate = this.candidate(), self = this;
    this.comparison.replaceChildren();
    if (candidate) {
      this.comparison.appendChild(el("strong", "", "Local copy / Library copy"));
      (candidate.differences || []).forEach(function (difference) {
        var property = self.adapter.properties.filter(function (item) { return item[1] === difference.field; })[0];
        function display(value, present) {
          if (!present) return "Not supplied";
          if (difference.field === "datasheet_links" && Array.isArray(value)) {
            return value.length ? value.join("\n") : "None";
          }
          if (property && property[2]) return units.format(value, property[2], units.profile(property[2]));
          return ui.blank(value) ? "—" : (typeof value === "object" ? JSON.stringify(value) : String(value));
        }
        self.comparison.appendChild(ui.propertyRow(property ? property[0] : ui.titleCase(difference.field),
          display(difference.local, difference.local_present) + " / " +
          display(difference.incoming, difference.incoming_present), ""));
      });
      if (!candidate.differences.length) this.comparison.appendChild(el("p", "muted", "Copied properties match."));
    }
    // While the library reloads, a held review waits rather than copying from the catalog being replaced.
    var waiting = this.busy() || this.locked;
    if (this.locked && !this.busy()) this.error.textContent = LOADING;
    else if (this.error.textContent === LOADING) this.error.textContent = "";
    this.localButton.disabled = waiting || !candidate;
    this.libraryButton.disabled = waiting || !candidate || !candidate.expected_values;
    this.cancel.disabled = this.busy(); this.candidates.disabled = this.busy();
  };
  Copy.prototype.use = function (row, assignment) {
    if (this.disposed || this.enabled === false || this.busy() || !row.library || !row.resolution) return false;
    if (row.resolution.outcome === "create") return this.run(row, "create", null, assignment);
    if (row.resolution.outcome === "reuse" && row.resolution.candidates.length === 1) {
      return this.run(row, "keep_local", row.resolution.candidates[0], assignment);
    }
    return this.open(row, assignment);
  };
  Copy.prototype.run = function (row, choice, candidate, assignment) {
    if (this.disposed || this.enabled === false || this.busy()) return false;
    var library = row.library, params = { provider_id: library.provider_id, kind: library.kind,
      generation: library.generation, library_id: library.library_id, record_id: library.record_id, choice: choice };
    if (candidate) params.local_id = candidate.id;
    if (choice === "use_library") params.expected_values = candidate.expected_values;
    if (assignment) params.assignment = assignment;
    this.requests.run("ph_composer.library.copy", freeze(params));
    this.error.textContent = "Applying library copy…"; this.compare(); this.changed(); return true;
  };
  Copy.prototype.apply = function (choice) {
    var candidate = this.candidate();
    if (this.disposed || this.enabled === false || this.locked || !this.held || !candidate || this.busy() ||
      (choice === "use_library" && this.libraryButton.disabled)) return false;
    return this.run(this.held.row, choice, candidate, this.held.assignment);
  };
  Copy.prototype.refresh = function (state, enabled) {
    if (this.disposed) return;
    this.enabled = enabled !== false;
    if (!this.enabled) { this.withdraw(); return; }
    var outcome = this.requests.consume(state);
    if (!outcome) { if (this.held) this.compare(); return; }
    this.error.textContent = outcome.status === "completed" ? "" : outcome.message;
    if (outcome.status === "completed") { this.root.closeModal(); this.held = null; }
    this.compare(); this.changed(outcome);
  };
  Copy.prototype.close = function () {
    if (this.busy()) return;
    this.held = null; this.root.closeModal(); this.changed();
  };
  Copy.prototype.withdraw = function () {
    this.requests.reset(); this.held = null; this.root.closeModal(); this.compare();
  };
  Copy.prototype.dispose = function () { this.disposed = true; this.withdraw(); };
  return Copy;
});
