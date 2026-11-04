/* The lifecycle every record form shares: its container (a modal dialog or an inline panel), title, submit and
   Cancel in the shared confirmation order, the status line, one single-flight request, and settling the result.
   A form constructor calls RecordForm with its spec, builds its own fields into `this.form`, then `finish()`.

   spec: { title, action, label (request id label), submitLabel, pendingText, failureText, changed(arg),
           dialog (default true), className, destructive } */
PhComposerUI.define("record_form", ["request", "workspace"], function (request, ui) {
  "use strict";

  function RecordForm(session, send, spec) {
    var self = this;
    this.session = session; this.send = send; this.spec = spec; this.changed = spec.changed;
    this.requests = request.channel(session, send, spec.label);
    if (spec.dialog === false) { this.root = ui.element("div", "phc-form"); this.root.hidden = true; }
    else this.root = ui.formDialog(spec.className || "", function () { self.hide(); });
    this.title = ui.element("h2", "", spec.title); this.root.appendChild(this.title);
    this.form = ui.element("form");
    this.submitButton = ui.element("button", "primary", spec.submitLabel); this.submitButton.type = "submit";
    this.cancel = ui.button("Cancel", function () { self.hide(); });
    this.error = ui.element("div", "cell-error"); this.error.setAttribute("role", "status");
    this.form.addEventListener("submit", function (event) { event.preventDefault(); self.submit(); });
    /* An inline panel has no Escape of its own; a dialog closes through its own cancel listener above. */
    if (spec.dialog === false) {
      this.form.addEventListener("keydown", function (event) {
        if (event.key === "Escape" && !self.requests.busy()) { event.preventDefault(); self.hide(); }
      });
    }
  }
  /* Appends the confirmation row after the owner's fields, its status line first in that row, so what a blocked
     commit waits for reads beside it. */
  RecordForm.prototype.finish = function () {
    var actions = ui.actionRow(this.cancel, this.submitButton, Boolean(this.spec.destructive));
    actions.insertBefore(this.error, actions.firstChild);
    this.form.appendChild(actions);
    this.root.appendChild(this.form);
  };
  RecordForm.prototype.show = function () {
    if (this.spec.dialog === false) this.root.hidden = false; else this.root.openModal();
  };
  RecordForm.prototype.close = function () {
    if (this.spec.dialog === false) this.root.hidden = true; else this.root.closeModal();
  };
  /* Refused while a request is pending; `arg` reaches the owner's changed callback. */
  RecordForm.prototype.hide = function (arg) {
    if (this.requests.busy()) return;
    this.close(); this.error.textContent = ""; this.changed(arg);
  };
  /* Sends the form's action once; the submit and Cancel buttons stay disabled until the result settles. */
  RecordForm.prototype.run = function (params) {
    if (!this.requests.run(this.spec.action, params)) return false;
    this.submitButton.disabled = true; this.cancel.disabled = true; this.error.textContent = this.spec.pendingText;
    return true;
  };
  /* This state's outcome for the pending request, once: re-enables Cancel and writes the status line, which
     keeps a refusal or failure visible until the user changes something or closes the form. */
  RecordForm.prototype.settle = function (state) {
    var outcome = this.requests.consume(state);
    if (!outcome) return null;
    this.cancel.disabled = false;
    this.error.textContent = outcome.status === "completed" ? "" : (outcome.message || this.spec.failureText);
    return outcome;
  };
  /* Marks a labelled control as one the form waits for: the label gains a muted "required" after its text,
     and the control says so to assistive technology. */
  RecordForm.required = function (label, control) {
    control.setAttribute("aria-required", "true");
    label.insertBefore(ui.element("small", "phc-required", "required"), label.children[0] || null);
    return control;
  };
  /* The feature went away: forget the request and close. */
  RecordForm.prototype.withdraw = function (message) {
    this.requests.reset(); this.close();
    this.cancel.disabled = false;
    if (message !== undefined) this.error.textContent = message;
  };
  RecordForm.prototype.busy = function () { return this.requests.busy(); };

  /* Makes Form a RecordForm: Form's constructor calls RecordForm.call(this, ...). */
  RecordForm.extend = function (Form) {
    Form.prototype = Object.create(RecordForm.prototype);
    Form.prototype.constructor = Form;
    return Form;
  };

  return RecordForm;
});
