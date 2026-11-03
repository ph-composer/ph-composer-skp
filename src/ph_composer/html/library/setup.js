/* Machine-level library setup. Native pickers own addresses; this dialog only sees provider ids and labels.
   It leads with the first task, adding a library, and keeps agent access folded away beneath it. */
PhComposerUI.define("library/setup", ["library/locations", "request", "snapshot", "workspace"],
  function (Locations, request, snapshot, ui) {
  "use strict";
  var PREFIX = "ph_composer.library.providers", SECTION = "ph_composer.library.provider_catalogs",
    SETUP_SECTION = "ph_composer.library.provider_setup", CONNECTIONS = "ph_composer.library.connection_states",
    CONNECTION_PREFIX = "ph_composer.library.connections", el = ui.element;
  /* A hosted library's connection state in the user's words. The extension signs in; this dialog only
     starts its lifecycle actions and shows the state and label the host reports. */
  var STATE_WORDS = { disconnected: "Not connected", authorizing: "Signing in…", connected: "Connected",
    reauthorization_required: "Sign in again", unavailable: "Unavailable" };
  /* The two ways to add a library, each one native picker. The choice is shown at once while there is no
     library yet, because adding one is then the whole job; afterwards it waits behind "Add a library…". */
  var ROUTES = [
    { verb: "add_file", label: "Library file…", detail: "One library file, such as one exported from PH-Composer." },
    { verb: "add_folder", label: "Library folder…", detail: "A folder of library files, read together." }];
  function Setup(session, send, changed) {
    var self = this;
    this.changed = changed; this.providers = []; this.connections = []; this.enabled = false;
    this.unreadable = false;
    this.choosing = false; this.added = null;
    this.requests = request.channel(session, send, "library-setup", "setup.invoke");
    this.root = ui.formDialog("library-setup", function () { self.close(); });
    this.root.appendChild(el("h2", "", "Libraries"));
    this.intro = el("p", "muted", "Add a library to copy its Materials and window products into this file. " +
      "Libraries stay on this computer; nothing is shared.");
    this.root.appendChild(this.intro);
    this.list = el("div", "library-setup-list"); this.root.appendChild(this.list);
    this.unreadableNotice = el("div", "library-setup-unreadable");
    this.unreadableNotice.appendChild(el("p", "", "The library setup stored on this machine cannot be read. " +
      "Reset it to add libraries again; the libraries it held must be added again."));
    this.reset = ui.button("Reset library setup", function () { self.run("reset", {}); });
    this.unreadableNotice.appendChild(this.reset); this.root.appendChild(this.unreadableNotice);
    this.routes = el("div", "library-setup-routes"); this.routes.setAttribute("role", "group");
    this.routes.setAttribute("aria-label", "Add a library");
    this.routeButtons = ROUTES.map(function (route) {
      var choice = ui.button("", function () { self.run(route.verb, {}); });
      choice.className = "library-setup-route";
      choice.appendChild(el("strong", "", route.label)); choice.appendChild(el("small", "muted", route.detail));
      choice.setAttribute("aria-label", "Add a " + route.label.toLowerCase());
      self.routes.appendChild(choice);
      return choice;
    });
    this.file = this.routeButtons[0]; this.folder = this.routeButtons[1];
    this.root.appendChild(this.routes);
    this.error = el("p", "cell-error"); this.error.setAttribute("role", "status"); this.root.appendChild(this.error);
    // Agent access is a separate job: what an agent may open by id. Folded away until someone needs it.
    this.agentAccess = el("details", "library-agent-access");
    var summary = el("summary", "", "Agent access");
    this.agentAccess.appendChild(summary);
    // Close waits for a pending approval too, so a location request repaints this dialog as well.
    this.locations = new Locations(session, send, function () { self.paint(); changed(); });
    this.agentAccess.appendChild(this.locations.root);
    this.root.appendChild(this.agentAccess);
    this.add = ui.button("Add a library…", function () { self.choosing = !self.choosing; self.paint(); });
    this.add.setAttribute("aria-expanded", "false");
    // Every change here applies at once, so the dialog ends with Done, never a Cancel that would undo nothing.
    this.cancel = ui.button("Done", function () { self.close(); });
    this.cancel.setAttribute("aria-label", "Done");
    var footer = ui.element("div", "phc-dialog-actions library-setup-adds");
    footer.appendChild(this.add); footer.appendChild(this.cancel);
    this.root.appendChild(footer);
  }
  Setup.prototype.refresh = function (state) {
    if (this.disposed) return;
    var providers = state.session === this.requests.session && snapshot.value(state, SECTION);
    this.enabled = Boolean(providers); this.providers = providers || [];
    this.connections = (this.enabled && snapshot.value(state, CONNECTIONS)) || [];
    var setupState = this.enabled && snapshot.value(state, SETUP_SECTION);
    this.unreadable = Boolean(setupState) && setupState.state === "unreadable";
    if (!this.enabled) { this.requests.reset(); this.root.closeModal(); }
    var outcome = this.requests.consume(state);
    if (outcome) this.settle(outcome);
    this.locations.refresh(state);
    this.paint();
  };
  /* A finished request: an added library is named, marked in the list and the choice folds away, so the
     result and the next step (Done) are plain. A cancelled picker changes nothing. */
  Setup.prototype.settle = function (outcome) {
    var before = this.pendingIds || [];
    this.pendingIds = null; this.added = null;
    this.error.className = "cell-error";
    if (outcome.status === "cancelled") { this.error.textContent = ""; return; }
    if (outcome.status !== "completed") { this.error.textContent = outcome.message; return; }
    var added = (Array.isArray(outcome.value) ? outcome.value : []).filter(function (row) {
      return before.indexOf(row.id) < 0;
    })[0];
    this.added = added ? added.id : null;
    if (added) this.choosing = false;
    this.error.className = "library-setup-success";
    // A completed add that brings nothing new picked a library already in the list.
    this.error.textContent = added ? "Added " + added.label + ". Choose it under the library list in the " +
      "Library sidebar to copy its records into this file." : before.length && Array.isArray(outcome.value) &&
      outcome.value.length === before.length ? "That library is already in the list." : "";
  };
  Setup.prototype.paint = function () {
    var self = this, busy = this.requests.busy(), empty = !this.providers.length && !this.connections.length;
    var hosted = this.connections.map(function (row) { return row.provider_kind; });
    this.list.replaceChildren();
    this.connections.forEach(function (row) { self.list.appendChild(self.connectionRow(row, busy)); });
    // A hosted library's catalogs appear under its connection row above, not again as a provider.
    var listed = this.providers.filter(function (row) { return hosted.indexOf(row.provider_kind) < 0; });
    listed.forEach(function (provider) {
      var row = el("div", "library-setup-row" + (provider.id === self.added ? " is-added" : ""));
      row.appendChild(el("span", "", provider.label));
      if (provider.provider_kind === "ph_composer.library.file") {
        var remove = ui.iconButton("Remove " + provider.label, "delete", function () {
          self.run("remove", { provider_id: provider.id });
        });
        remove.classList.add("library-setup-remove"); remove.disabled = busy || !self.enabled;
        row.appendChild(remove);
      } else row.appendChild(el("small", "muted", "Added by another tool"));
      self.list.appendChild(row);
    });
    this.intro.hidden = !empty || this.unreadable;
    this.unreadableNotice.hidden = !this.unreadable; this.reset.disabled = busy || !this.enabled;
    var blocked = busy || !this.enabled || this.unreadable;
    this.routes.hidden = this.unreadable || !(empty || this.choosing);
    this.routeButtons.forEach(function (button) { button.disabled = blocked; });
    // One primary: adding while there is nothing to use, Done once there is.
    this.add.hidden = empty || this.unreadable;
    this.add.disabled = blocked;
    this.add.setAttribute("aria-expanded", String(!this.routes.hidden));
    this.cancel.classList.toggle("primary", !empty);
    this.cancel.disabled = busy || this.locations.busy();
    this.root.closeButton.disabled = this.cancel.disabled;
    // A control that just went away (a folded choice, a removed row) leaves the focus on Done.
    var active = document.activeElement;
    if (active && this.root.contains && !this.root.hidden && active !== document.body &&
        (!active.isConnected || hiddenWithin(active, this.root))) this.cancel.focus();
  };
  /* One hosted library: its label, its state, and the lifecycle actions it declares that fit that state.
     Remove signs out and forgets the connection; copies already in the file stay. */
  Setup.prototype.connectionRow = function (row, busy) {
    var self = this, offers = row.lifecycle || [], state = row.state;
    var line = el("div", "library-setup-row library-setup-connection");
    line.appendChild(el("span", "", row.label));
    line.appendChild(el("small", "muted", STATE_WORDS[state] || STATE_WORDS.unavailable));
    // While signing in, the code the browser's sign-in page also shows: matching them is the check.
    if (state === "authorizing" && row.pairing_display) {
      var code = el("code", "library-setup-pairing", row.pairing_display);
      code.setAttribute("title", "Check that the sign-in page shows the same code.");
      code.setAttribute("aria-label", "Sign-in code " + row.pairing_display);
      line.appendChild(code);
    }
    var actions = [];
    if (offers.indexOf("connect") >= 0 && (state === "disconnected" || state === "unavailable")) {
      actions.push(["connect", "Connect"]);
    }
    if (offers.indexOf("reauthorize") >= 0 && state === "reauthorization_required") {
      actions.push(["reauthorize", "Reconnect"]);
    }
    if (offers.indexOf("disconnect") >= 0 && state !== "disconnected") actions.push(["disconnect", "Disconnect"]);
    if (offers.indexOf("settings") >= 0) actions.push(["settings", "Settings…"]);
    actions.forEach(function (action) {
      var button = ui.button(action[1], function () {
        self.request(CONNECTION_PREFIX + "." + action[0], { provider_kind: row.provider_kind });
      });
      button.setAttribute("aria-label", action[1] + " " + row.label);
      button.disabled = busy || !self.enabled;
      line.appendChild(button);
    });
    var remove = ui.iconButton("Remove " + row.label, "delete", function () {
      self.request(CONNECTION_PREFIX + ".remove", { provider_kind: row.provider_kind });
    });
    remove.classList.add("library-setup-remove"); remove.disabled = busy || !this.enabled;
    line.appendChild(remove);
    return line;
  };
  function hiddenWithin(node, root) {
    for (var current = node; current && current !== root; current = current.parentNode) {
      if (current.hidden) return true;
    }
    return false;
  }
  Setup.prototype.open = function () {
    if (this.disposed || !this.enabled || this.requests.busy()) return;
    this.error.textContent = ""; this.added = null; this.choosing = false;
    this.paint(); this.root.openModal();
    // The first thing to do takes the focus, not the dialog's close control.
    (this.routes.hidden ? this.cancel : this.file).focus();
    this.changed();
  };
  Setup.prototype.run = function (verb, params) {
    return this.request(PREFIX + "." + verb, params, /^add_/.test(verb) ?
      "Choose the library in the window that opened…" : "Waiting for library setup…");
  };
  Setup.prototype.request = function (name, params, waiting) {
    if (this.disposed || !this.enabled || this.requests.busy()) return false;
    this.pendingIds = this.providers.map(function (row) { return row.id; }); this.added = null;
    this.requests.run(name, params);
    this.error.className = "cell-error library-setup-waiting";
    this.error.textContent = waiting || "Waiting for library setup…";
    this.paint(); this.changed(); return true;
  };
  Setup.prototype.close = function () {
    if (this.requests.busy() || this.locations.busy()) return;
    this.root.closeModal(); this.changed();
  };
  Setup.prototype.dispose = function () {
    this.disposed = true; this.enabled = false; this.requests.reset(); this.locations.dispose(); this.root.closeModal();
  };
  return Setup;
});
