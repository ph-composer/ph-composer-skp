/* Help & Diagnostics (shell/support_dialog.rb): what is installed, what the log recorded, the support report
   and the two recoveries this build has. It is its own window on its own callback, `ph_composer_support`;
   it needs no Model, no panel and no Python, and it never writes the Model.

   The report is captured once in Ruby and shown here before anything leaves the window. Copy takes the text
   on screen; Save asks Ruby to write the same capture's bytes; Refresh captures again. */
PhComposerUI.define("support/page", ["dom", "overlay", "page_header"], function (dom, overlay, header) {
  "use strict";
  var el = dom.element;
  var PUBLIC_ISSUE = "This opens a public GitHub issue. Paste or attach your support report there, and leave out " +
    "anything you do not want to be public.";
  var RECORDED = "PH-Composer keeps a small diagnostic log on this computer: when something fails, which part " +
    "of PH-Composer it was, and the build that was running. It never records Model names or geometry, file " +
    "paths, library contents, tokens or what you typed. Entries older than seven days are removed when " +
    "SketchUp starts.";

  function when(iso) {
    var date = new Date(iso);
    return isNaN(date.getTime()) ? "" : date.toLocaleDateString([], { month: "short", day: "numeric" }) + " " +
      date.toLocaleTimeString([], { hour: "2-digit", minute: "2-digit" });
  }

  function row(label, value, tone) {
    var node = el("div", "support-row");
    var text = el("span", "support-row-value", value);
    if (tone) text.setAttribute("data-tone", tone);
    node.appendChild(el("span", "support-row-label", label)); node.appendChild(text);
    return node;
  }

  function Page(post) {
    var self = this;
    this.post = post; this.capture = null; this.incident = null;
    this.root = el("div", "support");
    this.notice = overlay.floatingNotice(this.root);
    var layer = el("div", "phc-notice-layer"); layer.appendChild(this.notice); this.root.appendChild(layer);

    this.copy = dom.button("Copy diagnostics", function () { self.request("copy"); });
    this.save = dom.button("Save support report…", function () { self.request("save"); });
    this.menu = new overlay.ActionMenu("More actions");
    this.menu.add("Reopen panel…", function () { self.confirmReopen(); });
    this.menu.add("Reset display preferences…", function () { self.confirmReset(); });
    this.menu.add("Clear diagnostic history…", function () { self.confirmClear(); }, { destructive: true });
    this.header = header.pageHeader({ title: "Help & Diagnostics", actions: [this.save], primary: this.copy,
      menu: this.menu.root });
    this.root.appendChild(this.header.root);
    this.identity = el("p", "muted support-identity"); this.root.appendChild(this.identity);

    this.installation = this.section("This installation");
    this.problems = this.section("Recent problems");
    var help = this.section("Get help");
    var links = el("div", "support-links");
    links.appendChild(dom.button("Open help", function () { self.send("support.open_help", {}); }));
    links.appendChild(dom.button("Online help", function () { self.send("support.open_online_help", {}); }));
    links.appendChild(dom.button("Report a problem…", function () { self.confirmReport(); }));
    links.appendChild(dom.button("Open log folder", function () { self.send("support.open_log_folder", {}); }));
    help.appendChild(links);

    var details = el("details", "support-details");
    details.appendChild(el("summary", "", "What the log holds"));
    details.appendChild(el("p", "", RECORDED));
    this.root.appendChild(details);

    this.buildPreview(); this.buildConfirm();
    document.body.appendChild(this.root);
  }

  Page.prototype.section = function (title) {
    var node = el("section", "support-section");
    node.appendChild(el("h2", "", title));
    var body = el("div", "support-section-body"); node.appendChild(body);
    this.root.appendChild(node);
    return body;
  };

  Page.prototype.send = function (type, payload) { this.post(type, payload); };
  Page.prototype.request = function (purpose) { this.send("support.capture", { purpose: purpose }); };

  Page.prototype.receive = function (message) {
    var payload = message.payload || {};
    if (message.type === "support.state") this.paint(payload);
    else if (message.type === "support.capture") this.showPreview(payload);
    else if (message.type === "support.result") this.result(payload);
  };

  Page.prototype.paint = function (state) {
    var about = state.about, host = about.host, log = about.log, self = this;
    this.incident = state.incident; this.resettable = state.resettable;
    this.identity.textContent = "PH-Composer " + about.version + "  ·  " +
      (about.development ? "Development build" : about.build === "unavailable" ? "Build unavailable" :
        "Build " + about.build);
    this.installation.replaceChildren(
      row("SketchUp " + host.sketchup + " on " + host.platform,
        host.supported ? "Supported" : "Not supported (" + host.supported_text + ")",
        host.supported ? null : "warning"),
      row("Diagnostic log", log.writing ? "Writing" : "Not writing (" + (log.last_error || "unknown error") +
        "). Recent events from this session are still shown.", log.writing ? null : "warning")
    );
    if (!state.problems.length) {
      this.problems.replaceChildren(el("p", "muted", "No problems were recorded in the last " +
        state.retention_days + " days."));
      return;
    }
    var list = el("ul", "support-problems");
    state.problems.forEach(function (problem) {
      var item = el("li", "support-problem");
      if (problem.incident && problem.incident === self.incident) item.classList.add("is-selected");
      item.appendChild(el("span", "support-problem-time", when(problem.time)));
      item.appendChild(el("span", "support-problem-label", problem.label));
      item.appendChild(el("span", "support-problem-incident", problem.incident || ""));
      list.appendChild(item);
    });
    this.problems.replaceChildren(list);
  };

  /* The report as it will leave the window. Refresh replaces it; Copy and Save act on what is shown. */
  Page.prototype.buildPreview = function () {
    var self = this;
    this.preview = overlay.formDialog("support-preview", function () { self.closePreview(); });
    this.preview.appendChild(el("h2", "", "Support report"));
    this.previewCaptured = el("p", "muted"); this.preview.appendChild(this.previewCaptured);
    this.previewText = el("textarea", "support-preview-text");
    this.previewText.readOnly = true; this.previewText.setAttribute("aria-label", "Support report");
    this.preview.appendChild(this.previewText);
    this.preview.appendChild(el("p", "muted", "It holds no Model names, file paths, tokens or project data."));
    this.previewStatus = el("p", "support-inline"); this.previewStatus.setAttribute("role", "status");
    this.preview.appendChild(this.previewStatus);
    var refresh = dom.button("Refresh", function () { self.request(self.purpose); });
    this.previewPrimary = dom.button("Copy", function () { self.commit(); });
    var actions = overlay.actionRow(dom.button("Cancel", function () { self.closePreview(); }), this.previewPrimary);
    actions.insertBefore(refresh, actions.firstChild);
    this.preview.appendChild(actions);
    this.root.appendChild(this.preview);
  };

  Page.prototype.showPreview = function (capture) {
    this.capture = capture; this.purpose = capture.purpose;
    this.previewCaptured.textContent = "Captured " + when(capture.captured_at) + ". Review it before you share it.";
    this.previewText.value = capture.text;
    this.previewPrimary.textContent = this.purpose === "save" ? "Save…" : "Copy";
    this.previewStatus.textContent = "";
    this.preview.openModal();
  };

  Page.prototype.closePreview = function () { this.capture = null; this.preview.closeModal(); };

  Page.prototype.commit = function () {
    if (!this.capture) return;
    if (this.purpose === "save") this.send("support.save", { capture_id: this.capture.capture_id });
    else this.copyText();
  };

  /* A copy that does not work leaves the preview open and offers Save instead. */
  Page.prototype.copyText = function () {
    var self = this, field = this.previewText, clipboard = window.navigator && window.navigator.clipboard;
    var copied = function () { self.closePreview(); self.say("Support report copied.", "success"); };
    var failed = function () {
      self.purpose = "save"; self.previewPrimary.textContent = "Save…";
      self.previewStatus.textContent = "Copying did not work here. Save the report instead.";
    };
    field.select();
    if (document.execCommand && document.execCommand("copy")) copied();
    else if (clipboard && clipboard.writeText) clipboard.writeText(field.value).then(copied, failed);
    else failed();
  };

  Page.prototype.result = function (result) {
    if (result.action === "support.save" && this.capture) {
      if (result.status === "completed") { this.closePreview(); this.say(result.message, "success"); }
      else this.previewStatus.textContent = result.message;
      return;
    }
    this.say(result.message, result.status === "completed" ? "success" :
      result.status === "failed" ? "error" : "warning");
  };

  Page.prototype.say = function (message, tone) {
    this.notice.show(message, { tone: tone, persistent: tone === "warning" || tone === "error" });
  };

  /* One confirmation dialog, filled for each action that needs one. */
  Page.prototype.buildConfirm = function () {
    var self = this;
    this.confirmDialog = overlay.formDialog("support-confirm", function () { self.confirmDialog.closeModal(); });
    this.confirmTitle = el("h2"); this.confirmBody = el("div", "support-confirm-body");
    this.confirmAction = dom.button("", function () {
      self.confirmDialog.closeModal(); if (self.onConfirm) self.onConfirm();
    });
    this.confirmCancel = dom.button("Cancel", function () { self.confirmDialog.closeModal(); });
    this.confirmDialog.appendChild(this.confirmTitle); this.confirmDialog.appendChild(this.confirmBody);
    this.confirmRow = el("div"); this.confirmDialog.appendChild(this.confirmRow);
    this.root.appendChild(this.confirmDialog);
  };

  Page.prototype.askFirst = function (title, body, action, destructive, onConfirm) {
    this.confirmTitle.textContent = title;
    this.confirmBody.replaceChildren.apply(this.confirmBody, body.map(function (node) {
      return typeof node === "string" ? el("p", "", node) : node;
    }));
    this.confirmAction.textContent = action; this.confirmAction.className = "";
    this.confirmCancel.className = "";
    this.confirmRow.replaceChildren(overlay.actionRow(this.confirmCancel, this.confirmAction, destructive));
    this.onConfirm = onConfirm;
    this.confirmDialog.openModal();
  };

  Page.prototype.confirmReport = function () {
    var self = this;
    this.askFirst("Report a problem", [PUBLIC_ISSUE], "Open GitHub", false, function () {
      self.send("support.report_problem", {});
    });
  };

  Page.prototype.confirmReopen = function () {
    var self = this;
    this.askFirst("Reopen the panel", ["The panel window closes and opens again. An edit you have not saved in " +
      "it is discarded; changes already applied to the Model are kept."], "Reopen panel", false, function () {
      self.send("support.reopen_panel", {});
    });
  };

  Page.prototype.confirmReset = function () {
    var self = this, list = el("ul");
    (this.resettable || []).forEach(function (name) { list.appendChild(el("li", "", name)); });
    this.askFirst("Reset display preferences", ["These return to their defaults:", list,
      "Libraries, approved locations, agent tokens and the Model are not changed."], "Reset", false, function () {
      self.send("support.reset_preferences", {});
    });
  };

  Page.prototype.confirmClear = function () {
    var self = this;
    this.askFirst("Clear diagnostic history", ["The diagnostic log on this computer is deleted, so it can no " +
      "longer help explain an earlier problem. Support reports you saved are kept, and the Model and your " +
      "settings are not changed."], "Clear history", true, function () {
      self.send("support.clear_history", {});
    });
  };

  var page = null;
  function ready() {
    page = new Page(function (type, payload) {
      if (window.sketchup && window.sketchup.ph_composer_support) {
        window.sketchup.ph_composer_support(JSON.stringify({ type: type, payload: payload }));
      }
    });
    page.send("support.ready", {});
    return page;
  }
  function receive(message) { if (page) page.receive(message); }

  return { Page: Page, ready: ready, receive: receive };
});
