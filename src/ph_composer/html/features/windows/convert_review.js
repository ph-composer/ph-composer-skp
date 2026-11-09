/* Convert to Window Type's review: SketchUp's menus hand the panel what `units.convert_review` takes and leaves
 * out (the `ph_composer.windows.convert_dialog` snapshot section), and this shows it in the shared form dialog
 * with a Type, a name and a Copy from for each size. Convert sends `units.convert` at the revision the review was
 * read at, so a Model changed since refuses; Cancel, Escape and the close control change nothing. Either way the
 * review is closed by its token, so a newer review is never closed by an older dialog.
 */
PhComposerUI.define("features/windows/convert_review", ["panel", "request", "snapshot",
  "features/windows/editor_shared", "workspace"], function (panel, requests, snapshot, shared, ui) {
  "use strict";
  var SECTION = shared.PREFIX + "convert_dialog", DIMENSION = shared.WINDOW_DIMENSION, NEW_TYPE = "";

  function copy(value) { return JSON.parse(JSON.stringify(value)); }

  function count(number, word) { return number + " " + word + (number === 1 ? "" : "s"); }

  function total(bands) { return bands.reduce(function (sum, value) { return sum + value; }, 0); }

  /* The groups of one size and layout, the first of each in review order: they share one Type choice. */
  function layouts(groups) {
    var found = [];
    groups.forEach(function (group) {
      var row = found.filter(function (item) { return item.index === group.layout_index; })[0];
      if (!row) found.push(row = { index: group.layout_index, groups: [] });
      row.groups.push(group);
    });
    return found;
  }

  /* The Types every group of a layout may take, so nothing is offered that one of them would refuse. */
  function commonTypes(groups) {
    return groups[0].matching_types.filter(function (type) {
      return groups.every(function (group) {
        return group.matching_types.some(function (other) { return other.id === type.id; });
      });
    });
  }

  function ConvertReview(owner) {
    var self = this;
    this.owner = owner;
    this.review = null;
    this.token = null;
    this.creating = requests.channel(owner.session, function (type, payload) {
      owner.send(type, Object.assign({}, payload, { expected_revision: self.review.revision }));
    }, "window-convert");
    this.closing = requests.channel(owner.session, function (type, payload) { owner.send(type, payload); },
      "window-convert-review", "view.invoke");
  }

  ConvertReview.prototype.consume = function (state) {
    this.closing.consume(state);
    var outcome = this.creating.consume(state);
    if (outcome) this.settle(outcome);
    // A submitted review settles before any other is shown, so its result closes only its own token.
    if (this.creating.busy()) return;
    var pending = snapshot.value(state, SECTION), token = pending && pending.token;
    // Closed elsewhere, or replaced by a newer review: this dialog no longer stands for anything.
    if (this.review && token !== this.token) this.dismiss();
    if (!token || token === this.token) return;
    var reason = this.owner.guard();
    if (reason) {
      // Marked first: the refusal repaints, and that repaint consumes this same snapshot again.
      var fresh = this.waiting !== token;
      this.waiting = token;
      if (fresh) this.owner.notice.show(reason);
      return;
    }
    if (state.ui && state.ui.activeTab !== "windows") {
      if (this.revealing === token) return;
      this.revealing = token;
      panel.showTab("windows");
      // Kept through the repaint the switch itself runs; a refused switch is retried on a later snapshot.
      if (panel.state.ui.activeTab !== "windows") this.revealing = null;
      return;
    }
    this.waiting = null;
    this.token = pending.token;
    this.review = copy(pending);
    this.render(state);
  };

  ConvertReview.prototype.render = function (state) {
    var self = this, review = this.review;
    var dialog = this.dialog || (this.dialog = ui.formDialog("phc-convert-window", function () { self.cancel(); }));
    if (!dialog.parentNode) document.body.appendChild(dialog);
    var form = ui.element("form");
    form.addEventListener("submit", function (event) { event.preventDefault(); self.submit(); });
    form.appendChild(ui.element("p", "", this.summary()));
    var sources = this.copySources(state);
    this.rows = layouts(review.groups);
    if (this.rows.length) {
      var list = ui.element("div", "phc-convert-window-groups");
      this.rows.forEach(function (row) { list.appendChild(self.row(row, sources)); });
      form.appendChild(list);
    }
    if (review.left_out.length) form.appendChild(this.leftOut());
    // The shared form dialog's error line, as record forms use it.
    this.error = ui.element("div", "cell-error");
    this.error.setAttribute("role", "status");
    this.cancelButton = ui.button("Cancel", function () { self.cancel(); });
    this.convertButton = ui.button("Convert", function () { self.submit(); });
    this.convertButton.disabled = !review.groups.length;
    dialog.replaceChildren(ui.element("h2", "", "Convert to Window Type"), form, this.error,
      ui.actionRow(this.cancelButton, this.convertButton));
    dialog.openModal();
    (this.rows.length ? this.rows[0].type : this.cancelButton).focus();
  };

  ConvertReview.prototype.summary = function () {
    var groups = this.review.groups;
    if (!groups.length) return "None of the selected Faces can become a Window.";
    var rectangles = groups.reduce(function (sum, group) { return sum + group.sources.length; }, 0);
    return count(rectangles, "rectangle") + (rectangles === 1 ? " becomes " : " become ") +
      count(groups.length, "Window") + ".";
  };

  /* The Types a new one can copy from: those with a glazed element, by name. */
  ConvertReview.prototype.copySources = function (state) {
    return shared.records(state, "types").filter(function (record) {
      return record.values.elements.some(function (element) { return element.kind === "glazed"; });
    }).sort(function (left, right) { return ui.compareText(left.values.name, right.values.name); });
  };

  /* One size: what it is, the Type it becomes, and the new Type's name and Copy from while that is the choice. */
  ConvertReview.prototype.row = function (row, sources) {
    var first = row.groups[0], root = ui.element("div", "phc-convert-window-group");
    var size = shared.bare(total(first.columns_m), DIMENSION) + " x " + shared.format(total(first.rows_m), DIMENSION);
    var detail = [count(row.groups.length, "Window")];
    if (first.sources.length > 1) detail.push(count(first.sources.length, "element"));
    root.appendChild(ui.element("p", "phc-convert-window-size", size + ", " + detail.join(", ")));
    var matching = commonTypes(row.groups);
    row.type = this.select("Window Type", [[NEW_TYPE, "New Window Type"]].concat(matching.map(function (type) {
      return [type.id, type.name];
    })));
    var preselected = matching.some(function (type) { return type.id === first.preselected_type_id; });
    row.type.value = preselected ? first.preselected_type_id : NEW_TYPE;
    row.name = this.field("Name", first.default_name);
    row.copy = this.select("Copy from", [[NEW_TYPE, "None"]].concat(sources.map(function (record) {
      return [record.id, record.values.name];
    })));
    ui.tooltip(row.copy, "Copies the glazing, frames, installs and operation of that Type's first glazed element " +
      "into each element. None leaves them to set afterwards.");
    function paint() {
      row.name.parentNode.hidden = row.copy.parentNode.hidden = row.type.value !== NEW_TYPE;
    }
    row.type.addEventListener("change", paint);
    [row.type, row.name, row.copy].forEach(function (control) { root.appendChild(control.parentNode); });
    paint();
    return root;
  };

  ConvertReview.prototype.select = function (text, options) {
    var label = ui.element("label", "", text), select = ui.element("select");
    select.setAttribute("aria-label", text);
    options.forEach(function (entry) { select.appendChild(ui.option(entry[0], entry[1])); });
    label.appendChild(select);
    return select;
  };

  /* One labelled text field; Enter in it converts, as the Convert button does. */
  ConvertReview.prototype.field = function (text, value) {
    var self = this, label = ui.element("label", "", text), input = ui.element("input");
    input.setAttribute("aria-label", text);
    input.value = value;
    input.addEventListener("keydown", function (event) {
      if (event.key !== "Enter") return;
      event.preventDefault();
      self.submit();
    });
    label.appendChild(input);
    return input;
  };

  ConvertReview.prototype.leftOut = function () {
    var reasons = Object.create(null), order = [];
    this.review.left_out.forEach(function (row) {
      if (!reasons[row.message]) { reasons[row.message] = 0; order.push(row.message); }
      reasons[row.message] += row.paths.length;
    });
    var list = ui.element("ul", "phc-convert-window-left-out");
    order.forEach(function (message) {
      list.appendChild(ui.element("li", "", count(reasons[message], "Face") + ": " + message));
    });
    var root = ui.element("div");
    root.appendChild(ui.element("p", "", "Left out:"));
    root.appendChild(list);
    return root;
  };

  ConvertReview.prototype.submit = function () {
    if (!this.review || !this.review.groups.length || this.creating.busy()) return;
    var groups = [];
    this.rows.forEach(function (row) {
      var type = row.type.value, name = row.name.value.trim(), copyFrom = row.copy.value;
      row.groups.forEach(function (group) {
        var entry = { sources: group.sources.map(function (source) {
          return { path: copy(source.path), digest: source.digest };
        }) };
        if (type !== NEW_TYPE) entry.type_id = type;
        else {
          if (name) entry.name = name;
          if (copyFrom) entry.copy_from_type_id = copyFrom;
        }
        groups.push(entry);
      });
    });
    this.error.textContent = "";
    this.creating.run(shared.PREFIX + "units.convert", { groups: groups });
    this.busy(true);
  };

  ConvertReview.prototype.settle = function (outcome) {
    this.busy(false);
    if (outcome.status !== "completed") {
      if (this.error) this.error.textContent = outcome.message || "Nothing was converted.";
      return;
    }
    this.finish();
    var value = outcome.value || {}, created = (value.created_type_ids || [])[0];
    var first = created || (value.units && value.units[0] && value.units[0].type_id);
    if (first) this.owner.showConverted(first);
    panel.notify(outcome.message || "Converted to Window Type.", "success");
  };

  ConvertReview.prototype.busy = function (busy) {
    if (!this.convertButton) return;
    this.convertButton.disabled = busy || !this.review || !this.review.groups.length;
    this.cancelButton.disabled = busy;
    this.dialog.closeButton.disabled = busy;
  };

  /* Cancel, Escape and the close control: nothing is written. Refused while Convert is in flight. */
  ConvertReview.prototype.cancel = function () {
    if (this.creating.busy()) return;
    this.finish();
  };

  ConvertReview.prototype.finish = function () {
    if (this.dialog) this.dialog.closeModal();
    var token = this.token;
    this.review = null;
    if (token && !this.owner.disposed) this.closing.send(shared.PREFIX + "convert_dialog.close", { token: token });
    panel.repaint();
  };

  /* The dialog closes without a close command: the review it showed is already gone. */
  ConvertReview.prototype.dismiss = function () {
    if (this.dialog) this.dialog.closeModal();
    this.review = null;
  };

  ConvertReview.prototype.active = function () { return Boolean(this.review); };

  ConvertReview.prototype.dispose = function () {
    this.creating.reset();
    this.closing.reset();
    if (this.dialog) {
      this.dialog.closeModal();
      if (this.dialog.parentNode) this.dialog.parentNode.removeChild(this.dialog);
    }
  };

  return ConvertReview;
});
