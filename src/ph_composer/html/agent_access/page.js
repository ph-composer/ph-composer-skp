/* The Agent Access dialog (agent_access/dialog.rb): the user issues, reads and revokes the tokens an agent
   connects with. It is its own window and talks only to its own callback, `ph_composer_agent_access`; it is
   not the panel and sends no panel message. A token is shown once, in the dialog that created it, and never
   again: the host keeps only its digest. */
PhComposerUI.define("agent_access/page", ["dom", "icons", "overlay", "page_header", "subtabs"],
  function (dom, icons, overlay, header, Subtabs) {
    "use strict";
    var el = dom.element;
    /* What each capability lets a holder do, in the words the New token form shows beside its checkbox. */
    var CAPABILITIES = {
      read: { label: "Read", consent: "Reads the open Models: their Zones, Spaces, Assemblies and Window Types, " +
        "and the values PH-Composer calculates. Changes nothing." },
      view: { label: "View", consent: "Changes what SketchUp shows: the camera, the selection and the open Group. " +
        "Never changes authored data. Leaving a Volume can lock it again, as each command says." },
      model_write: { label: "Edit the Model", consent: "Edits the open Models through PH-Composer's actions. " +
        "Each action is one Undo step." },
      setup: { label: "Setup", consent: "Changes this computer's libraries and settings, for every Model, not " +
        "just this one." },
      export: { label: "Export", consent: "Writes exports to the folders you have approved." },
      capture: { label: "Capture the view", consent: "Writes an image of the current view, geometry only, to a " +
        "temporary file the agent reads. It can show anything in the viewport." }
    };
    /* The listener's state as the status line says it. */
    function serverLine(server) {
      if (server.state === "listening") {
        return "Listening on port " + server.port + ": agents with a live token can connect.";
      }
      if (server.state === "unavailable") return "Not listening: " + server.message;
      return "Not listening: agents can connect once a token is issued.";
    }

    /* What a revoke ended, as the acknowledgment says it. */
    function revokedLine(summary) {
      var line = "Token revoked. Calls it sends from now on are refused; one already running finishes.";
      if (summary.exports_completed) line += " " + summary.exports_completed + " export(s) it started had completed.";
      if (summary.exports_stopped) line += " " + summary.exports_stopped + " running export(s) stop without writing.";
      if (summary.changes_committed) line += " " + summary.changes_committed + " change(s) it made stay in the Model.";
      if (summary.calls_refused) line += " " + summary.calls_refused + " waiting call(s) were refused.";
      return line;
    }

    /* What a client's own settings say of a connection's entry (ClientSetup.entry), as a row says it. */
    var ENTRY = {
      configured: "set up",
      absent: "not in the client's settings",
      outdated: "set up for another port or file",
      inline: "its token is kept in the client's settings",
      other: "set up another way",
      no_client: "the client is not set up on this computer",
      unreadable: "the client's settings cannot be read"
    };
    var DEFAULT_PROFILE = "default";
    var NEW_PROFILE = "";
    function profileLabel(profile) { return profile === DEFAULT_PROFILE ? "Default" : profile; }
    /* A connection as the token list and the Revoke confirm name it: the client, and its profile unless it is
       the default. */
    function connectionName(row) {
      return row.client_name + (row.profile === DEFAULT_PROFILE ? "" : " (" + row.profile + ")");
    }

    /* Live tokens by when they were issued, newest first: the windows a user remembers a token by. */
    var PERIODS = ["Today", "Yesterday", "This week", "This year", "Earlier"];
    function period(iso, now) {
      // Calendar days, so a daylight-saving change never moves a boundary; the week starts on Monday.
      var at = new Date(iso), y = now.getFullYear(), m = now.getMonth(), d = now.getDate();
      if (at >= new Date(y, m, d)) return PERIODS[0];
      if (at >= new Date(y, m, d - 1)) return PERIODS[1];
      if (at >= new Date(y, m, d - (now.getDay() + 6) % 7)) return PERIODS[2];
      if (at.getFullYear() === now.getFullYear()) return PERIODS[3];
      return PERIODS[4];
    }

    function day(iso) { return iso ? new Date(iso).toLocaleDateString() : ""; }
    function time(iso) { return new Date(iso).toLocaleTimeString([], { hour: "2-digit", minute: "2-digit" }); }
    function capabilityNames(list) {
      return list.map(function (name) {
        return (CAPABILITIES[name] || { label: dom.titleCase(name) }).label;
      }).join(", ");
    }

    /* `options.now`, a clock for the token list's time groups; the real one when absent. */
    function Page(post, options) {
      var self = this;
      this.now = (options && options.now) || function () { return new Date(); };
      this.showRevoked = false; this.issuedState = { client: null };
      this.post = post; this.tokens = []; this.offered = ["read"]; this.unreadable = false; this.pending = false;
      this.connectButtons = []; this.connectStatus = {}; this.connections = []; this.replacements = {};
      this.openSetups = {};
      this.model = null;
      this.revoking = null;
      this.root = el("div", "agent-access");
      this.notice = overlay.floatingNotice(this.root);
      var layer = el("div", "phc-notice-layer"); layer.appendChild(this.notice); this.root.appendChild(layer);
      this.create = dom.button("New token", function () { self.openCreate(); });
      this.help = overlay.helpButton("Disconnecting an agent", "Revoke its token here; the agent can no longer " +
        "connect, and the copy saved for a client is deleted. To remove PH-Composer from a client as well, run " +
        "claude mcp remove --scope user ph-composer, or delete the [mcp_servers.ph-composer] block from " +
        "~/.codex/config.toml; a profile's entry is named ph-composer-<profile>.");
      this.header = header.pageHeader({ title: "Agent Access", actions: [this.help], primary: this.create });
      this.root.appendChild(this.header.root);
      this.server = el("p", "muted agent-access-server"); this.server.setAttribute("role", "status");
      this.root.appendChild(this.server);
      this.portRow = el("div", "agent-access-port"); this.portRow.hidden = true;
      this.portInput = el("input"); this.portInput.type = "number"; this.portInput.min = "1024";
      this.portInput.max = "65535"; this.portInput.setAttribute("aria-label", "Port");
      this.portApply = dom.button("Use this port", function () {
        self.send("access.port", { port: Number(self.portInput.value) });
      });
      this.portRow.appendChild(this.portInput); this.portRow.appendChild(this.portApply);
      this.root.appendChild(this.portRow);
      this.unreadableNotice = el("div", "phc-notice agent-access-unreadable");
      this.unreadableNotice.setAttribute("data-tone", "warning");
      this.unreadableNotice.appendChild(el("p", "", "The agent tokens stored on this computer cannot be read. " +
        "Reset them to issue tokens again; every agent then needs a new token."));
      this.reset = dom.button("Reset agent tokens", function () { self.send("access.reset", {}); });
      this.unreadableNotice.appendChild(this.reset);
      this.root.appendChild(this.unreadableNotice);
      // New token is the page's one job; the tokens already issued are folded away until asked for.
      this.tokensBox = el("details", "agent-access-tokens");
      this.tokensSummary = el("summary");
      this.tokensBox.appendChild(this.tokensSummary);
      this.list = el("div", "agent-access-list");
      this.tokensBox.appendChild(this.list);
      this.revokedToggle = dom.button("", function () { self.showRevoked = !self.showRevoked; self.paint(); });
      this.revokedToggle.className = "agent-access-revoked-toggle";
      this.tokensBox.appendChild(this.revokedToggle);
      this.root.appendChild(this.tokensBox);
      // Each saved connection: which token it uses, what the client's settings say, and whether a client has
      // contacted and verified through it, kept apart; Repair sets the client up again.
      this.connectionsBox = el("details", "agent-access-connections");
      this.connectionsSummary = el("summary");
      this.connectionsBox.appendChild(this.connectionsSummary);
      this.connectionList = el("div", "agent-access-items");
      this.connectionList.setAttribute("role", "list");
      this.connectionList.setAttribute("aria-label", "Client profiles");
      this.connectionsBox.appendChild(this.connectionList);
      this.root.appendChild(this.connectionsBox);
      this.empty = el("p", "muted agent-access-empty", "No agent tokens. A token lets one agent, such as " +
        "Claude Code or Codex, connect to PH-Composer with the access you choose.");
      this.root.appendChild(this.empty);
      this.buildCreateDialog(); this.buildIssuedDialog(); this.buildRevokeDialog();
      overlay.attachTooltip(this.root);
      this.paint();
    }

    Page.prototype.send = function (type, payload) {
      if (this.pending) return false;
      this.pending = true; this.post(type, payload); this.paint(); return true;
    };

    Page.prototype.receive = function (message) {
      var payload = message.payload || {};
      if (message.type === "access.state") {
        this.pending = false;
        this.tokens = payload.tokens || []; this.offered = payload.offered || ["read"];
        this.model = payload.model || null; this.connections = payload.connections || [];
        // The host's state is the binding from now on; a replacement it answered earlier is in it.
        this.replacements = {};
        this.unreadable = payload.state === "unreadable";
        this.serverStatus = payload.server || {};
        if (this.revoking && !this.tokens.some(function (row) { return row.id === this.revoking && !row.revoked_at; },
          this)) this.closeRevoke();
        this.paint();
      } else if (message.type === "access.issued") {
        this.pending = false; this.createDialog.closeModal();
        this.showIssued(payload.token, payload.row, payload.clients || []);
      } else if (message.type === "access.connected") {
        this.pending = false; this.connected(payload); this.paint();
      } else if (message.type === "access.replacement") {
        this.pending = false; this.replacementShown(payload); this.paint();
      } else if (message.type === "access.revoked") {
        this.notice.show(revokedLine(payload.summary || {}), { tone: "success" });
      } else if (message.type === "access.failure") {
        this.pending = false; this.fail(payload.message); this.paint();
      }
    };

    /* A refusal shows where the user is: inside the open dialog, whose modal backdrop would hide the page's
       notice and make its Dismiss unreachable, or as the page's notice when no dialog is open. */
    Page.prototype.fail = function (message) {
      var open = [[this.createDialog, this.createError], [this.revokeDialog, this.revokeError],
        [this.issuedDialog, this.copyStatus]]
        .filter(function (pair) { return !pair[0].hidden; })[0];
      // A refused Connect answers under that client's button, where "Connecting" was said.
      this.repairing = null; this.replacements = {};
      if (open && open[0] === this.issuedDialog && this.connectStatus[this.connecting]) {
        this.connectStatus[this.connecting].textContent = message;
        this.connectStatus[this.connecting].setAttribute("data-state", "failed");
      } else if (open) open[1].textContent = message;
      else this.notice.show(message, { tone: "warning" });
    };
    function inlineMessage(role) {
      var node = el("p", "cell-error agent-access-inline"); node.setAttribute("role", role); return node;
    }

    Page.prototype.row = function (token) {
      var self = this, row = el("div", "agent-access-row" + (token.revoked_at ? " is-revoked" : ""));
      row.setAttribute("role", "listitem");
      var text = el("div", "agent-access-row-text");
      text.appendChild(el("span", "agent-access-row-label", token.label));
      var facts = [capabilityNames(token.capabilities), "created " + day(token.created_at)];
      if (token.model_name) facts.splice(1, 0, "only " + token.model_name);
      if ((token.connected || []).length) facts.push("used by " + token.connected.join(" and "));
      if (token.revoked_at) facts.push("revoked " + day(token.revoked_at));
      else if (token.last_call) facts.push("last call " + time(token.last_call.at) + ", " + token.last_call.status);
      else facts.push("no calls since SketchUp started");
      text.appendChild(el("small", "muted", facts.join(" · ")));
      row.appendChild(text);
      if (!token.revoked_at) {
        var revoke = dom.button("Revoke", function () { self.openRevoke(token); });
        revoke.className = "agent-access-revoke"; revoke.setAttribute("aria-label", "Revoke " + token.label);
        revoke.disabled = this.pending || this.unreadable;
        row.appendChild(revoke);
      }
      return row;
    };

    Page.prototype.paint = function () {
      var self = this;
      var server = this.serverStatus || {};
      this.server.textContent = serverLine(server);
      this.portRow.hidden = server.state !== "unavailable";
      if (this.portRow.hidden || document.activeElement !== this.portInput) this.portInput.value = server.port || "";
      this.portApply.disabled = this.pending;
      this.paintTokens(); this.paintConnections();
      this.unreadableNotice.hidden = !this.unreadable;
      this.reset.disabled = this.pending;
      // A token issued while the port is taken would carry snippets for a port nothing listens on.
      this.create.disabled = this.pending || this.unreadable || server.state === "unavailable";
      this.createSubmit.disabled = this.pending;
      this.connectButtons.forEach(function (button) { button.disabled = self.pending; });
      if (this.clientTabs) this.paintProfiles();
    };

    /* The folded connection list, one row per saved connection, in the host's order. */
    Page.prototype.paintConnections = function () {
      var self = this;
      this.connectionList.replaceChildren.apply(this.connectionList, this.connections.map(function (row) {
        return self.connectionRow(row);
      }));
      this.connectionsSummary.textContent = "Client profiles · " + this.connections.length;
      this.connectionsBox.hidden = !this.connections.length;
    };
    Page.prototype.connectionRow = function (connection) {
      var self = this, row = el("div", "agent-access-row agent-access-connection");
      row.setAttribute("role", "listitem");
      var text = el("div", "agent-access-row-text"), token = connection.token;
      text.appendChild(el("span", "agent-access-row-label",
        connection.client_name + " · " + profileLabel(connection.profile)));
      var facts = [];
      if (token) {
        var scope = token.model_name ? ", only " + token.model_name +
          (token.model_open === false ? " (not open)" : "") : "";
        facts.push("uses " + token.label + scope);
      } else facts.push("no live token: create a token and connect it to this profile");
      var saved = connection.saved_token;
      // A token saved for the profile that its settings do not read yet, as after a refused edit.
      if (saved && (!token || saved.id !== token.id)) facts.push(saved.label + " is saved for it and waits for Repair");
      facts.push(ENTRY[connection.entry] || connection.entry);
      if (token) {
        // Contacted and verified are this profile's own when its client names it, else the token's.
        facts.push(connection.contacted ? "contacted by " + (connection.contacted.client || "a client") +
          " " + time(connection.contacted.at) : "not contacted since SketchUp started");
        if (connection.verified_at) facts.push("verified " + time(connection.verified_at));
      }
      text.appendChild(el("small", "muted", facts.join(" · ")));
      if (connection.entry !== "configured") {
        // Rows are rebuilt at every state the host sends, an agent's call included; an open one stays open.
        var key = connection.client + ":" + connection.profile, manual = el("details", "agent-access-other");
        manual.open = Boolean(this.openSetups[key]);
        manual.addEventListener("toggle", function () { self.openSetups[key] = manual.open; });
        manual.appendChild(el("summary", "", "Set up by hand"));
        var field = this.copyField(connection.client_name + " setup", "textarea");
        field.value.value = connection.setup; manual.appendChild(field.root);
        text.appendChild(manual);
      }
      row.appendChild(text);
      // Repair sets the client up with the live token saved for the profile, which never comes to the page.
      if (saved && connection.entry !== "configured") {
        var repair = dom.button("Repair", function () {
          if (self.pending) return;
          self.repairing = connection.client + ":" + connection.profile;
          self.send("access.repair", { client: connection.client, profile: connection.profile });
        });
        repair.className = "agent-access-revoke";
        repair.setAttribute("aria-label", "Repair " + connectionName(connection));
        repair.disabled = this.pending || this.unreadable;
        row.appendChild(repair);
      }
      return row;
    };

    /* The folded token list: live tokens under the period they were issued in, then, only when asked for,
       the revoked ones under their own heading. */
    Page.prototype.paintTokens = function () {
      var self = this, now = this.now(), groups = [], byPeriod = {};
      var live = this.tokens.filter(function (token) { return !token.revoked_at; });
      var revoked = this.tokens.filter(function (token) { return token.revoked_at; });
      function group(label) {
        var root = el("section", "agent-access-group"), items = el("div", "agent-access-items");
        items.setAttribute("role", "list"); items.setAttribute("aria-label", label + " tokens");
        root.appendChild(el("h3", "", label)); root.appendChild(items);
        return { root: root, items: items };
      }
      live.forEach(function (token) {
        var label = period(token.created_at, now);
        if (!byPeriod[label]) { byPeriod[label] = group(label); groups.push(byPeriod[label]); }
        byPeriod[label].items.appendChild(self.row(token));
      });
      if (this.showRevoked && revoked.length) {
        var gone = group("Revoked");
        revoked.forEach(function (token) { gone.items.appendChild(self.row(token)); });
        groups.push(gone);
      }
      this.list.replaceChildren.apply(this.list, groups.map(function (item) { return item.root; }));
      this.tokensSummary.textContent = "Tokens · " + (live.length ? live.length + " live" : "none live");
      this.tokensBox.hidden = !this.tokens.length;
      this.revokedToggle.hidden = !revoked.length;
      this.revokedToggle.textContent = this.showRevoked ? "Hide revoked tokens" :
        "Show revoked tokens (" + revoked.length + ")";
      this.revokedToggle.setAttribute("aria-pressed", String(this.showRevoked));
      this.empty.hidden = Boolean(this.tokens.length) || this.unreadable;
    };

    /* New token: a label and the capabilities, each with what it allows. Read is always held. */
    Page.prototype.buildCreateDialog = function () {
      var self = this, form = el("form", "agent-access-create");
      this.createDialog = overlay.formDialog("agent-access-create-dialog", function () { self.closeCreate(); });
      form.appendChild(el("h2", "", "New agent token"));
      var labelRow = el("label", "agent-access-field");
      labelRow.appendChild(el("span", "", "Name"));
      this.labelInput = el("input"); this.labelInput.setAttribute("maxlength", "80");
      this.labelInput.setAttribute("placeholder", "Agent token");
      labelRow.appendChild(this.labelInput); form.appendChild(labelRow);
      this.capabilityList = el("fieldset", "agent-access-capabilities");
      this.capabilityList.appendChild(el("legend", "", "Access"));
      form.appendChild(this.capabilityList);
      var only = el("label", "agent-access-capability");
      this.modelOnly = el("input"); this.modelOnly.type = "checkbox";
      this.modelOnlyText = el("small", "muted");
      var onlyText = el("span"); onlyText.appendChild(el("strong", "", "This Model only"));
      onlyText.appendChild(this.modelOnlyText);
      only.appendChild(this.modelOnly); only.appendChild(onlyText); form.appendChild(only);
      form.appendChild(el("p", "muted", "The token is the only secret. Anyone holding it has this access until " +
        "you revoke it here."));
      this.createError = inlineMessage("alert"); form.appendChild(this.createError);
      var cancel = dom.button("Cancel", function () { self.closeCreate(); });
      this.createSubmit = dom.button("Create");
      this.createSubmit.type = "submit";
      form.appendChild(overlay.actionRow(cancel, this.createSubmit));
      form.addEventListener("submit", function (event) { event.preventDefault(); self.submitCreate(); });
      this.createDialog.appendChild(form);
      this.root.appendChild(this.createDialog);
    };
    Page.prototype.openCreate = function () {
      var self = this;
      if (this.pending || this.unreadable) return;
      this.labelInput.value = ""; this.createError.textContent = "";
      this.capabilityList.querySelectorAll("label").forEach(function (node) { node.remove(); });
      this.checks = Object.keys(CAPABILITIES).filter(function (name) { return self.offered.indexOf(name) !== -1; })
        .map(function (name) {
          var row = el("label", "agent-access-capability"), box = el("input"), text = el("span");
          box.type = "checkbox"; box.value = name; box.checked = name === "read"; box.disabled = name === "read";
          text.appendChild(el("strong", "", CAPABILITIES[name].label));
          text.appendChild(el("small", "muted", CAPABILITIES[name].consent));
          row.appendChild(box); row.appendChild(text); self.capabilityList.appendChild(row);
          return box;
        });
      // The Model this form names, kept until it is submitted: a later state cannot change what it binds.
      this.formModel = this.model;
      this.modelOnly.checked = false; this.modelOnly.disabled = !this.model;
      this.modelOnlyText.textContent = this.model ? "Reaches " + this.model.name +
        " and no other Model. Save As keeps it on the renamed file." :
        "Save this Model first to limit a token to it.";
      this.createDialog.openModal(); this.labelInput.focus();
    };
    Page.prototype.closeCreate = function () { if (!this.pending) this.createDialog.closeModal(); };
    Page.prototype.submitCreate = function () {
      var label = this.labelInput.value.trim();
      var capabilities = this.checks.filter(function (box) { return box.checked; })
        .map(function (box) { return box.value; });
      this.send("access.issue", { label: label || null, capabilities: capabilities,
        model_only: this.modelOnly.checked && this.formModel ? this.formModel.key : false });
    };

    /* The token, shown once. Closing this dialog is the last time the page holds it. */
    Page.prototype.buildIssuedDialog = function () {
      var self = this;
      this.issuedDialog = overlay.formDialog("agent-access-issued-dialog", function () { self.closeIssued(); });
      this.issuedTitle = el("h2", "", "Token created");
      this.issuedDialog.appendChild(this.issuedTitle);
      this.issuedDialog.appendChild(el("p", "", "Connect your client below. The token is not shown again; if it " +
        "is lost, revoke it and create another."));
      var field = this.copyField("token", "input");
      this.secret = field.value; this.copy = field.copy;
      this.issuedDialog.appendChild(field.root);
      this.clients = el("div", "agent-access-clients"); this.issuedDialog.appendChild(this.clients);
      this.copyStatus = inlineMessage("status"); this.issuedDialog.appendChild(this.copyStatus);
      var done = dom.button("Done", function () { self.closeIssued(); });
      done.className = "primary";
      var actions = el("div", "phc-dialog-actions"); actions.appendChild(done);
      this.issuedDialog.appendChild(actions);
      this.root.appendChild(this.issuedDialog);
    };
    /* A read-only field with its copy button; `tag` is "input" for one line or "textarea" for a command. */
    Page.prototype.copyField = function (label, tag) {
      var self = this, root = el("div", "agent-access-secret"), value = el(tag, "agent-access-secret-value");
      value.readOnly = true; value.setAttribute("aria-label", label);
      if (tag === "textarea") value.rows = 3;
      var copy = icons.iconButton("Copy " + label, "duplicate", function () {
        self.copyText(value, label, self.issuedDialog.hidden ? null : self.copyStatus);
      });
      root.appendChild(value); root.appendChild(copy);
      return { root: root, value: value, copy: copy };
    };
    /* One client at a time, each its own tab: Connect, the line that says what it did, and, behind "Other ways
       to connect", its setup to run or paste by hand and the command that checks it. */
    Page.prototype.showClients = function (clients) {
      var self = this, tabs = [];
      this.clients.replaceChildren(); this.connectButtons = []; this.connectStatus = {};
      this.connectSetup = {}; this.connectSetupValue = {}; this.pickers = {}; this.replacements = {};
      clients.forEach(function (client) {
        var section = el("section", "agent-access-client");
        var picker = self.profilePicker(client);
        var connect = dom.button("Connect " + client.client, function () {
          if (self.pending) return;
          var profile = picker.chosen();
          if (profile === null) { picker.name.focus(); return; }
          var held = self.heldBy(client.id, profile);
          self.connecting = client.id;
          self.connectStatus[client.id].textContent = "Connecting " + client.client + "…";
          self.connectSetup[client.id].hidden = true;
          self.send("access.connect", { client: client.id, token: self.secret.value, profile: profile,
            replace: held ? held.id : null });
        });
        connect.className = "agent-access-connect primary";
        picker.connect = connect; picker.client = client; self.pickers[client.id] = picker;
        var status = el("p", "agent-access-connected"); status.setAttribute("role", "status");
        // What to run or paste when Connect could not, for the profile it was asked for; never the token.
        var setup = self.copyField(client.client + " profile setup", "textarea"); setup.root.hidden = true;
        self.connectButtons.push(connect); self.connectStatus[client.id] = status;
        self.connectSetup[client.id] = setup.root; self.connectSetupValue[client.id] = setup.value;
        section.appendChild(picker.root); section.appendChild(connect); section.appendChild(status);
        section.appendChild(setup.root);
        section.appendChild(el("p", "muted", "Connect saves the token in a file only your account can read and " +
          "sets " + client.client + " up, once, to read it there. Connecting again later with a new token " +
          "changes only that file."));
        var other = el("details", "agent-access-other");
        other.appendChild(el("summary", "", "Other ways to connect the Default profile"));
        client.forms.forEach(function (form) {
          other.appendChild(el("p", "muted", form.title));
          var field = self.copyField(client.client + " setup", "textarea");
          field.value.value = form.text; other.appendChild(field.root);
        });
        other.appendChild(el("p", "muted", "Check it with " + client.check + "."));
        section.appendChild(other);
        tabs.push({ id: client.id, label: client.client, surface: section });
      });
      if (!tabs.length) return;
      this.clientTabs = new Subtabs({ label: "Client", state: this.issuedState, stateKey: "client",
        tabs: tabs });
      this.clients.appendChild(this.clientTabs.root);
      tabs.forEach(function (tab) { self.clients.appendChild(tab.surface); });
      this.paintProfiles();
    };
    /* The profile Connect sets up for one client: Default, a saved one, or a new one named here. */
    Page.prototype.profilePicker = function (client) {
      var self = this, root = el("div", "agent-access-profile");
      var label = el("label", "agent-access-field"); label.appendChild(el("span", "", "Profile"));
      var select = el("select"); select.setAttribute("aria-label", client.client + " profile");
      label.appendChild(select); root.appendChild(label);
      var nameRow = el("label", "agent-access-field"); nameRow.appendChild(el("span", "", "New profile name"));
      var name = el("input"); name.setAttribute("maxlength", "32"); name.setAttribute("placeholder", "house-b");
      name.setAttribute("aria-label", client.client + " new profile name");
      nameRow.appendChild(name); root.appendChild(nameRow);
      var replace = el("p", "agent-access-replace"); replace.setAttribute("role", "status");
      root.appendChild(replace);
      var picker = { root: root, select: select, name: name, nameRow: nameRow, replace: replace, touched: false };
      select.addEventListener("change", function () { picker.touched = true; self.paintProfiles(); });
      name.addEventListener("input", function () { self.paintProfiles(); });
      // The profile Connect would set up, or null while a new profile's name is not a valid one.
      picker.chosen = function () {
        if (select.value !== NEW_PROFILE) return select.value;
        var typed = name.value.trim();
        return /^[a-z0-9](?:[a-z0-9-]{0,30}[a-z0-9])?$/.test(typed) && typed !== DEFAULT_PROFILE ? typed : null;
      };
      return picker;
    };
    /* The live token a client's profile uses now, as the latest state or a replacement answer says. */
    Page.prototype.heldBy = function (client, profile) {
      var key = client + ":" + profile;
      if (Object.prototype.hasOwnProperty.call(this.replacements, key)) return this.replacements[key];
      var row = this.connections.find(function (item) { return item.client === client && item.profile === profile; });
      return row && row.token && row.token.id !== this.issuedId ? row.token : null;
    };
    /* Each client's profile choices from the saved connections, and what Connect would replace there. */
    Page.prototype.paintProfiles = function () {
      var self = this;
      Object.keys(this.pickers || {}).forEach(function (id) {
        var picker = self.pickers[id], kept = picker.touched ? picker.select.value : DEFAULT_PROFILE;
        var names = [DEFAULT_PROFILE].concat(self.connections.filter(function (row) {
          return row.client === id && row.profile !== DEFAULT_PROFILE;
        }).map(function (row) { return row.profile; }));
        // Rebuilt only when the profiles change, so a state the host sends never closes an open choice.
        if (picker.names !== names.join("\n")) {
          picker.names = names.join("\n");
          var options = names.map(function (profile) {
            var option = el("option", "", profileLabel(profile)); option.value = profile; return option;
          });
          var fresh = el("option", "", "New profile…"); fresh.value = NEW_PROFILE; options.push(fresh);
          picker.select.replaceChildren.apply(picker.select, options);
        }
        var next = kept !== NEW_PROFILE && names.indexOf(kept) === -1 ? DEFAULT_PROFILE : kept;
        if (picker.select.value !== next) picker.select.value = next;
        picker.nameRow.hidden = picker.select.value !== NEW_PROFILE;
        var profile = picker.chosen(), held = profile === null ? null : self.heldBy(id, profile);
        picker.replace.textContent = held ? profileLabel(profile) + " uses " + held.label + " now. Connecting " +
          "gives it this token; " + held.label + " stays live until you revoke it." : "";
        picker.connect.textContent = held ? "Replace and connect" : "Connect " + picker.client.client;
        picker.connect.disabled = self.pending || profile === null;
      });
    };
    /* Connect found another live token on the profile: nothing was written, and the page says which. */
    Page.prototype.replacementShown = function (payload) {
      this.replacements[payload.client + ":" + payload.profile] = payload.token;
      var status = this.connectStatus[payload.client];
      if (status) {
        status.textContent = "Nothing changed yet. Check the token this replaces, then press Replace and connect.";
        status.setAttribute("data-state", "manual");
      }
    };
    /* What Connect did, under that client's button: always ends with starting a new client session. */
    Page.prototype.connected = function (payload) {
      if (this.repairing) {
        this.repairing = null;
        this.notice.show(payload.message, { tone: payload.state === "configured" ? "success" : "warning" });
        return;
      }
      var status = this.connectStatus[payload.client];
      if (!status) return;
      delete this.replacements[payload.client + ":" + payload.profile];
      status.textContent = payload.message;
      status.setAttribute("data-state", payload.state);
      this.connectSetup[payload.client].hidden = !payload.setup;
      this.connectSetupValue[payload.client].value = payload.setup || "";
    };
    Page.prototype.showIssued = function (token, row, clients) {
      this.issuedTitle.textContent = "Token created: " + row.label; this.issuedId = row.id;
      this.secret.value = token; this.copyStatus.textContent = "";
      this.showClients(clients);
      this.issuedDialog.openModal(); this.secret.select();
    };
    /* Copies the selected text within the click, which a file page needs; the clipboard API is the second
       try. Either way the text stays selected, so Command-C works when both are refused. The answer is said
       inside the dialog, which holds the focus. */
    Page.prototype.copyText = function (field, label, status) {
      var clipboard = window.navigator && window.navigator.clipboard, self = this;
      var say = function (text, tone) {
        if (status) status.textContent = text; else self.notice.show(text, { tone: tone });
      };
      var copied = function () { say(label.charAt(0).toUpperCase() + label.slice(1) + " copied.", "success"); };
      var manual = function () { say("Copy the selected text with Command-C.", "info"); };
      field.select();
      if (document.execCommand && document.execCommand("copy")) copied();
      else if (clipboard && clipboard.writeText) clipboard.writeText(field.value).then(copied, manual);
      else manual();
    };
    /* Nothing that holds the token outlives this dialog. */
    Page.prototype.closeIssued = function () {
      if (this.clientTabs) { this.clientTabs.dispose(); this.clientTabs = null; }
      this.secret.value = ""; this.clients.replaceChildren(); this.connectButtons = []; this.connectStatus = {};
      this.pickers = {}; this.replacements = {}; this.issuedId = null;
      this.issuedDialog.closeModal();
    };

    /* Revoke confirms in the shared dialog, naming the token that goes. */
    Page.prototype.buildRevokeDialog = function () {
      var self = this;
      this.revokeDialog = overlay.formDialog("agent-access-revoke-dialog", function () { self.closeRevoke(); });
      this.revokeTitle = el("h2", "", "Revoke token");
      this.revokeDialog.appendChild(this.revokeTitle);
      this.revokeDialog.appendChild(el("p", "", "The agent holding this token can no longer connect. Work it has " +
        "already done in your Models stays."));
      this.revokeEffects = el("p", "agent-access-revoke-effects"); this.revokeDialog.appendChild(this.revokeEffects);
      this.revokeError = inlineMessage("alert"); this.revokeDialog.appendChild(this.revokeError);
      var cancel = dom.button("Cancel", function () { self.closeRevoke(); });
      this.revokeConfirm = dom.button("Revoke", function () {
        if (self.revoking) self.send("access.revoke", { id: self.revoking });
      });
      this.revokeDialog.appendChild(overlay.actionRow(cancel, this.revokeConfirm, true));
      this.root.appendChild(this.revokeDialog);
    };
    Page.prototype.openRevoke = function (token) {
      if (this.pending) return;
      this.revoking = token.id; this.revokeTitle.textContent = "Revoke " + token.label + "?";
      var losing = this.connections.filter(function (row) { return row.token && row.token.id === token.id; })
        .map(connectionName);
      this.revokeEffects.textContent = losing.length ? "These client profiles lose access: " + losing.join(", ") +
        "." : "";
      this.revokeError.textContent = "";
      this.revokeDialog.openModal();
    };
    Page.prototype.closeRevoke = function () {
      this.revoking = null; this.revokeDialog.closeModal();
    };

    var page = null;
    /* Mounts the page in this window and asks the host for the token list. */
    function ready() {
      page = new Page(function (type, payload) {
        if (window.sketchup && window.sketchup.ph_composer_agent_access) {
          window.sketchup.ph_composer_agent_access(JSON.stringify({ type: type, payload: payload }));
        }
      });
      document.body.appendChild(page.root);
      page.pending = true; page.post("access.ready", {});
      return page;
    }
    function receive(message) { if (page) page.receive(message); }

    return { Page: Page, ready: ready, receive: receive, CAPABILITIES: CAPABILITIES };
  });
