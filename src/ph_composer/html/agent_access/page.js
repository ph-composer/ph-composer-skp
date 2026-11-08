/* The Agent Access dialog (agent_access/dialog.rb): the user issues, reads and revokes the tokens an agent
   connects with. It is its own window and talks only to its own callback, `ph_composer_agent_access`; it is
   not the panel and sends no panel message. A token is shown once, in the dialog that created it, and never
   again: the host keeps only its digest. */
PhComposerUI.define("agent_access/page", ["dom", "icons", "overlay", "page_header"],
  function (dom, icons, overlay, header) {
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

    function day(iso) { return iso ? new Date(iso).toLocaleDateString() : ""; }
    function time(iso) { return new Date(iso).toLocaleTimeString([], { hour: "2-digit", minute: "2-digit" }); }
    function capabilityNames(list) {
      return list.map(function (name) {
        return (CAPABILITIES[name] || { label: dom.titleCase(name) }).label;
      }).join(", ");
    }

    function Page(post) {
      var self = this;
      this.post = post; this.tokens = []; this.offered = ["read"]; this.unreadable = false; this.pending = false;
      this.connectButtons = []; this.connectStatus = {};
      this.model = null;
      this.revoking = null;
      this.root = el("div", "agent-access");
      this.notice = overlay.floatingNotice(this.root);
      var layer = el("div", "phc-notice-layer"); layer.appendChild(this.notice); this.root.appendChild(layer);
      this.create = dom.button("New token", function () { self.openCreate(); });
      this.help = overlay.helpButton("Disconnecting an agent", "Revoke its token here; the agent can no longer " +
        "connect, and the copy saved for a client is deleted. To remove PH-Composer from a client as well, run " +
        "claude mcp remove --scope user ph-composer, or delete the [mcp_servers.ph-composer] block from " +
        "~/.codex/config.toml.");
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
      this.list = el("div", "agent-access-list"); this.list.setAttribute("role", "list");
      this.list.setAttribute("aria-label", "Agent tokens");
      this.root.appendChild(this.list);
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
        this.model = payload.model || null;
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
      this.list.replaceChildren();
      this.tokens.forEach(function (token) { self.list.appendChild(self.row(token)); });
      if (!this.tokens.length && !this.unreadable) {
        this.list.appendChild(el("p", "muted agent-access-empty", "No agent tokens. A token lets one agent, such as " +
          "Claude Code or Codex, connect to PH-Composer with the access you choose."));
      }
      this.unreadableNotice.hidden = !this.unreadable;
      this.reset.disabled = this.pending;
      // A token issued while the port is taken would carry snippets for a port nothing listens on.
      this.create.disabled = this.pending || this.unreadable || server.state === "unavailable";
      this.createSubmit.disabled = this.pending;
      this.connectButtons.forEach(function (button) { button.disabled = self.pending; });
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
      this.modelOnlyText.textContent = this.model ? "Reaches " + this.model.name + " and no other Model." :
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
      this.issuedDialog.appendChild(el("p", "", "Connect your client with this token below, or copy it for another " +
        "one. It is not shown again; if it is lost, revoke it and create another."));
      this.issuedDialog.appendChild(el("p", "muted", "Connect saves the token in a file only your account can read " +
        "and sets the client up, once, to read it there. Connecting it again later with a new token changes " +
        "only that file."));
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
        self.copyText(value, label);
      });
      root.appendChild(value); root.appendChild(copy);
      return { root: root, value: value, copy: copy };
    };
    /* Each client's Connect, the line that says what it did, and its setup to run or paste by hand, with
       the command that checks it. */
    Page.prototype.showClients = function (clients) {
      var self = this;
      this.clients.replaceChildren(); this.connectButtons = []; this.connectStatus = {};
      clients.forEach(function (client) {
        var section = el("section", "agent-access-client");
        section.appendChild(el("h3", "", client.client));
        var connect = dom.button("Connect " + client.client, function () {
          if (self.pending) return;
          self.connecting = client.id;
          self.connectStatus[client.id].textContent = "Connecting " + client.client + "…";
          self.send("access.connect", { client: client.id, token: self.secret.value });
        });
        connect.className = "agent-access-connect";
        var status = el("p", "agent-access-connected"); status.setAttribute("role", "status");
        self.connectButtons.push(connect); self.connectStatus[client.id] = status;
        section.appendChild(connect); section.appendChild(status);
        client.forms.forEach(function (form) {
          section.appendChild(el("p", "muted", form.title));
          var field = self.copyField(client.client + " setup", "textarea");
          field.value.value = form.text; section.appendChild(field.root);
        });
        section.appendChild(el("p", "muted", "Check it with " + client.check + "."));
        self.clients.appendChild(section);
      });
    };
    /* What Connect did, under that client's button: always ends with starting a new client session. */
    Page.prototype.connected = function (payload) {
      var status = this.connectStatus[payload.client];
      if (!status) return;
      status.textContent = payload.message;
      status.setAttribute("data-state", payload.state);
    };
    Page.prototype.showIssued = function (token, row, clients) {
      this.issuedTitle.textContent = "Token created: " + row.label;
      this.secret.value = token; this.copyStatus.textContent = "";
      this.showClients(clients);
      this.issuedDialog.openModal(); this.secret.select();
    };
    /* Copies the selected text within the click, which a file page needs; the clipboard API is the second
       try. Either way the text stays selected, so Command-C works when both are refused. The answer is said
       inside the dialog, which holds the focus. */
    Page.prototype.copyText = function (field, label) {
      var clipboard = window.navigator && window.navigator.clipboard, self = this;
      var copied = function () {
        self.copyStatus.textContent = label.charAt(0).toUpperCase() + label.slice(1) + " copied.";
      };
      var manual = function () { self.copyStatus.textContent = "Copy the selected text with Command-C."; };
      field.select();
      if (document.execCommand && document.execCommand("copy")) copied();
      else if (clipboard && clipboard.writeText) clipboard.writeText(field.value).then(copied, manual);
      else manual();
    };
    /* Nothing that holds the token outlives this dialog. */
    Page.prototype.closeIssued = function () {
      this.secret.value = ""; this.clients.replaceChildren(); this.connectButtons = []; this.connectStatus = {};
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
