/* Create Space's review: SketchUp's context menu hands the panel what `create_preview` accepts and leaves out
 * (the `ph_composer.spaces.create_review` snapshot section), and this shows it in the shared form dialog with
 * a Zone choice, preselected by `create_preview`, and an optional number and name. Create sends `create` with
 * the accepted Faces and the chosen Zone at the revision the review was read at, so a Model changed since
 * refuses; Cancel, Escape and the close control change nothing. Either way the review is closed by its token,
 * so a newer review is never closed by an older dialog.
 */
PhComposerUI.define("features/spaces/create_review", ["panel", "request", "snapshot", "workspace"],
function (panel, requests, snapshot, ui) {
  "use strict";
  var SECTION = "ph_composer.spaces.create_review", PREFIX = "ph_composer.spaces";
  var DEFINITION = "A 'Space' represents a bounded area within a 'Zone'. A Space is defined by its floor surface " +
    "plus a height. A Space may have more than one 'Volume' (ie: a bedroom with a main area plus a separate closet).";

  function copy(value) { return JSON.parse(JSON.stringify(value)); }

  function faces(count) { return count + (count === 1 ? " Face" : " Faces"); }

  /* `guard()` names held work the review must not interrupt, the Zones screen's and the Spaces view's;
     `reveal` shows the Spaces view (`shown(state)`, `show()`). */
  function CreateReview(host, guard, reveal) {
    var self = this;
    this.host = host;
    this.guard = guard;
    this.reveal = reveal;
    this.review = null;
    this.token = null;
    this.creating = requests.channel(host.session, function (type, payload) {
      host.send(type, Object.assign({}, payload, { expected_revision: self.review.revision }));
    }, "spaces-create");
    this.closing = requests.channel(host.session, function (type, payload) { host.send(type, payload); },
      "spaces-create-review", "view.invoke");
  }

  CreateReview.prototype.consume = function (state) {
    this.closing.consume(state);
    var outcome = this.creating.consume(state);
    if (outcome) this.settle(outcome);
    // A submitted review settles before any other is shown, so its result closes only its own token.
    if (this.creating.busy()) return;
    var pending = snapshot.value(state, SECTION), token = pending && pending.token;
    // Closed elsewhere, or replaced by a newer review: this dialog no longer stands for anything.
    if (this.review && token !== this.token) this.dismiss();
    if (!token || token === this.token) return;
    var reason = this.guard();
    if (reason) {
      // Marked first: the refusal repaints, and that repaint consumes this same snapshot again.
      var fresh = this.waiting !== token;
      this.waiting = token;
      if (fresh) this.host.refuse(reason);
      return;
    }
    if (!this.reveal.shown(state)) {
      if (this.revealing === token) return;
      this.revealing = token;
      this.reveal.show();
      // Kept through the repaint the switch itself runs; a refused switch is retried on a later snapshot.
      if (!this.reveal.shown(panel.state)) this.revealing = null;
      return;
    }
    this.waiting = null;
    this.token = pending.token;
    this.review = copy(pending);
    this.render();
  };

  CreateReview.prototype.render = function () {
    var self = this, review = this.review, accepted = review.accepted.length;
    var dialog = this.dialog || (this.dialog = ui.formDialog("phc-create-space", function () { self.cancel(); }));
    if (!dialog.parentNode) document.body.appendChild(dialog);
    // The shared form layout spaces the text and sets the fields side by side.
    var form = ui.element("form");
    form.addEventListener("submit", function (event) { event.preventDefault(); self.submit(); });
    form.appendChild(ui.element("p", "", DEFINITION));
    if (!accepted) form.appendChild(ui.element("p", "", "None of the selected Faces can become a Space."));
    if (review.left_out.length) {
      var reasons = Object.create(null), order = [];
      review.left_out.forEach(function (row) {
        if (!reasons[row.message]) { reasons[row.message] = 0; order.push(row.message); }
        reasons[row.message] += 1;
      });
      var list = ui.element("ul", "phc-create-space-left-out");
      order.forEach(function (message) {
        list.appendChild(ui.element("li", "", faces(reasons[message]) + ": " + message));
      });
      var leftOut = ui.element("div");
      leftOut.appendChild(ui.element("p", "", "Left out:"));
      leftOut.appendChild(list);
      form.appendChild(leftOut);
    }
    this.zone = this.zonePicker(review);
    this.number = this.field("Number", "Next free");
    this.name = this.field("Name", "");
    // The shared form dialog's error line, as record forms use it.
    this.error = ui.element("div", "cell-error");
    this.error.setAttribute("role", "status");
    this.cancelButton = ui.button("Cancel", function () { self.cancel(); });
    this.createButton = ui.button("Create", function () { self.submit(); });
    this.createButton.disabled = !accepted;
    form.appendChild(this.zone.label);
    form.appendChild(this.number.label);
    form.appendChild(this.name.label);
    dialog.replaceChildren(ui.element("h2", "", "Create Space from floor surface"), form, this.error,
      ui.actionRow(this.cancelButton, this.createButton));
    dialog.openModal();
    (accepted ? this.number.input : this.cancelButton).focus();
  };

  /* The Zone that hosts the new Space: No Zone, then each Zone, opened on the one `create_preview` preselects. */
  CreateReview.prototype.zonePicker = function (review) {
    var label = ui.element("label", "", "Zone"), select = ui.element("select");
    var chosen = review.zone && JSON.stringify(review.zone.zone_path);
    select.setAttribute("aria-label", "Zone");
    select.appendChild(ui.option("", "No Zone"));
    review.zones.forEach(function (zone, index) { select.appendChild(ui.option(String(index), zone.name || "Zone")); });
    review.zones.forEach(function (zone, index) {
      if (JSON.stringify(zone.zone_path) === chosen) select.value = String(index);
    });
    label.appendChild(select);
    return { label: label, input: select };
  };

  /* One labelled text field; Enter in it creates, as the Create button does. */
  CreateReview.prototype.field = function (text, placeholder) {
    var self = this, label = ui.element("label", "", text), input = ui.element("input");
    input.setAttribute("aria-label", text);
    if (placeholder) input.setAttribute("placeholder", placeholder);
    input.addEventListener("keydown", function (event) {
      if (event.key !== "Enter") return;
      event.preventDefault();
      self.submit();
    });
    label.appendChild(input);
    return { label: label, input: input };
  };

  CreateReview.prototype.submit = function () {
    if (!this.review || !this.review.accepted.length || this.creating.busy()) return;
    var picked = this.review.zones[this.zone.input.value];
    var params = { zone: picked ? { zone_id: picked.zone_id, zone_path: copy(picked.zone_path) } : null,
      faces: copy(this.review.accepted), name: this.name.input.value.trim() };
    var number = this.number.input.value.trim();
    if (number) params.number = number;
    this.error.textContent = "";
    this.creating.run(PREFIX + ".create", params);
    this.busy(true);
  };

  CreateReview.prototype.settle = function (outcome) {
    this.busy(false);
    if (outcome.status !== "completed") {
      if (this.error) this.error.textContent = outcome.message || "The Space was not created.";
      return;
    }
    this.finish();
    panel.notify(outcome.message || "Space created.", "success");
  };

  CreateReview.prototype.busy = function (busy) {
    if (!this.createButton) return;
    this.createButton.disabled = busy || !this.review.accepted.length;
    this.cancelButton.disabled = busy;
    this.dialog.closeButton.disabled = busy;
  };

  /* Cancel, Escape and the close control: nothing is written. Refused while Create is in flight. */
  CreateReview.prototype.cancel = function () {
    if (this.creating.busy()) return;
    this.finish();
  };

  CreateReview.prototype.finish = function () {
    if (this.dialog) this.dialog.closeModal();
    var token = this.token;
    this.review = null;
    if (token && !this.host.disposed) this.closing.send(PREFIX + ".create_review.close", { token: token });
    panel.repaint();
  };

  /* The dialog closes without a close command: the review it showed is already gone. */
  CreateReview.prototype.dismiss = function () {
    if (this.dialog) this.dialog.closeModal();
    this.review = null;
  };

  CreateReview.prototype.active = function () { return Boolean(this.review); };

  CreateReview.prototype.dispose = function () {
    this.creating.reset();
    this.closing.reset();
    if (this.dialog) {
      this.dialog.closeModal();
      if (this.dialog.parentNode) this.dialog.parentNode.removeChild(this.dialog);
    }
  };

  return CreateReview;
});
