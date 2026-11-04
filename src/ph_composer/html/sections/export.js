/* Export uses public preflight, native destination selection and Model-owned task handles.
   Closing this page stops polling; the host task continues and can be retrieved when reopened. */
PhComposerUI.define("sections/export", ["panel", "workspace"], function (panel, ui) {
  "use strict";
  var element = ui.element;
  var sequence = 0, session = null, revision = null, last = null, seen = null, timer = null;
  var pending = {}, checks = null, selected = {}, task = null, message = "", findings = [], retrieved = false;
  var blockedReport = null;
  var advisoriesOpen = false;
  var stages = { queued: "Preparing export…", reading: "Reading Model…", translating: "Translating Model…",
    checking: "Checking export…", writing: "Writing HBJSON and report…" };
  var CHANNELS = { start: "export.start", preflight: "export.preflight", status: "export.status",
    cancel: "export.cancel", latest: "export.latest" };

  function active() { return task && !task.outcome; }
  function waiting(operation) {
    return Object.keys(pending).some(function (id) { return pending[id] === operation; });
  }
  function request(operation, payload) {
    var id = "export:" + String(sequence += 1);
    pending[id] = operation;
    last.send(CHANNELS[operation], Object.assign({ request_id: id, session: session }, payload || {}));
  }
  function repaint() { panel.repaint(); }
  function choose() {
    if (active() || waiting("start") || waiting("preflight") || !checks ||
        checks.findings.some(function (f) { return f.blocks_export; })) return;
    message = ""; findings = [];
    request("start", { repairs: Object.keys(selected).filter(function (id) { return selected[id]; }) });
    repaint();
  }
  function cancel() {
    if (!active() || !task.cancellable || waiting("cancel")) return;
    request("cancel", { task_id: task.task_id });
    repaint();
  }
  function poll() {
    if (timer || !active() || waiting("status") || waiting("cancel")) return;
    var current = session;
    timer = window.setTimeout(function () {
      timer = null;
      if (current === session && active()) request("status", { task_id: task.task_id });
    }, 200);
  }
  function accept(result) {
    if (!result || result === seen || result.session !== session) return;
    seen = result;
    var operation = pending[result.request_id];
    if (!operation) return;
    delete pending[result.request_id];
    var outcome = result.outcome || {};
    if (operation === "preflight") {
      checks = outcome.status === "completed" ? outcome.value : {
        failed: true, findings: [{ message: outcome.message, blocks_export: true }], repairs: [] };
      checks.repairs.forEach(function (repair) {
        if (!Object.prototype.hasOwnProperty.call(selected, repair.id)) selected[repair.id] = repair.checked === true;
      });
      if (outcome.status !== "completed") { message = outcome.message; findings = outcome.findings || []; }
    } else if (outcome.status === "completed") {
      var next = outcome.value;
      if (!(task && task.outcome && next && next.task_id === task.task_id && !next.outcome)) task = next;
      if (operation !== "latest") { message = ""; findings = []; }
    } else {
      message = outcome.message || "The export request could not complete.";
      findings = outcome.findings || [];
      if (operation === "status") task = null;
    }
  }
  // A record id inside a finding's sentence: three letters, an underscore and twelve characters, such as
  // "fac_c3d5e3f176e1". The sentence reads without it; a name the user typed is never that shape by accident.
  var RECORD_ID = /\s*\b[a-z]{3}_[A-Za-z0-9]{12}\b/g;
  // The most records one Locate carries; a viewport command may refuse a longer list.
  var LOCATE_LIMIT = 500;
  function sentence(finding) {
    var text = String(finding.message || "");
    if (finding.object_id) text = text.split(" " + finding.object_id).join("");
    return text.replace(RECORD_ID, "");
  }
  function cause(finding) { return String(finding.code || "") + "|" + sentence(finding); }
  /* One group per cause: the same code and the same sentence once its record id is taken out. */
  function grouped(rows) {
    var list = [], byKey = Object.create(null);
    rows.forEach(function (finding) {
      var text = sentence(finding), key = cause(finding), group = byKey[key];
      if (!group) { group = byKey[key] = { text: text, findings: [] }; list.push(group); }
      group.findings.push(finding);
    });
    return list;
  }
  /* One Locate for a whole group: its findings' targets joined, when they all name the same command. */
  function locateAll(group) {
    var located = group.findings.filter(function (finding) { return finding.locate; });
    if (!located.length) return null;
    var name = located[0].locate.name, params = {};
    if (located.some(function (finding) { return finding.locate.name !== name; })) return null;
    located.forEach(function (finding) {
      Object.keys(finding.locate.params || {}).forEach(function (key) {
        var value = finding.locate.params[key];
        if (Array.isArray(value)) params[key] = (params[key] || []).concat(value);
        else if (!Object.prototype.hasOwnProperty.call(params, key)) params[key] = value;
      });
    });
    var total = 0;
    Object.keys(params).forEach(function (key) {
      if (!Array.isArray(params[key])) return;
      total = Math.max(total, params[key].length);
      params[key] = params[key].slice(0, LOCATE_LIMIT);
    });
    return { name: name, params: params, capped: total > LOCATE_LIMIT };
  }
  // Where a finding is looked into: the tab the feature that reported it said its records are worked on.
  function tabFor(group) { return panel.tabFor(group.findings[0].section); }
  function counted(count, noun) { return String(count) + " " + noun + (Number(count) === 1 ? "" : "s"); }
  function findingList(title, rows, collapsible) {
    var block = element(collapsible ? "details" : "section", "phc-export-group" +
      (collapsible ? " phc-export-advisories" : ""));
    block.appendChild(element(collapsible ? "summary" : "h2", "", collapsible ?
      title + " · " + counted(rows.length, "finding") : title));
    if (collapsible) {
      block.open = advisoriesOpen;
      block.addEventListener("toggle", function () { if (block.isConnected) advisoriesOpen = block.open; });
    }
    var list = element("ul", "phc-export-findings");
    grouped(rows).forEach(function (group) {
      var row = element("li"), count = group.findings.length, locate = locateAll(group), tab = tabFor(group);
      var text = element("span", "phc-export-finding", group.text);
      row.appendChild(text);
      if (count > 1) {
        var badge = element("span", "phc-export-count", "\u00d7 " + count);
        badge.setAttribute("aria-label", count + " findings");
        row.appendChild(badge);
      }
      // The records behind the sentence, by id, for diagnosis: on the sentence, never in it.
      var ids = group.findings.map(function (finding) {
        return finding.object_id || (String(finding.message || "").match(RECORD_ID) || [""])[0].trim();
      }).filter(function (id, index, all) { return id && all.indexOf(id) === index; });
      if (ids.length) ui.tooltip(text, ids.slice(0, 20).join(", ") + (ids.length > 20 ? " and more" : ""));
      if (locate) row.appendChild(ui.button(locate.capped ? "Locate first " + LOCATE_LIMIT :
        count > 1 ? "Locate all" : "Locate", function () {
        last.send("view.invoke", { request_id: "export-locate:" + String(sequence += 1), session: session,
          name: locate.name, params: locate.params });
      }));
      if (tab) row.appendChild(ui.button("Open " + tab.label, function () { panel.navigate(tab.tab); }));
      list.appendChild(row);
    });
    block.appendChild(list);
    return block;
  }
  function paint(root) {
    var blocking = checks ? checks.findings.filter(function (finding) { return finding.blocks_export; }) : [];
    var advisory = checks ? checks.findings.filter(function (finding) { return !finding.blocks_export; }) : [];
    var blocked = !checks || blocking.length > 0;
    var choosing = ui.button(waiting("start") ? "Choosing destination…" : "Choose destination…", choose,
      Boolean(active() || waiting("start") || waiting("preflight") || blocked));
    var secondary = active() ? [ui.button(waiting("cancel") ? "Cancelling…" : "Cancel export", cancel,
      !task.cancellable || waiting("cancel"))] : [];
    var status = element("p", "phc-export-status" + (active() ? " is-running" : ""), active() ?
      stages[task.stage] || "Export running…" : message);
    status.setAttribute("role", "status");
    var header = ui.pageHeader({ title: "Export", actions: secondary, primary: choosing });
    root.replaceChildren(header.root, element("p", "", "Export creates an HBJSON model and an HTML Export report."));
    if (active()) root.appendChild(status);
    if (!checks) root.appendChild(element("p", "phc-export-readiness", "Checking the Model…"));
    if (checks) {
      var causes = grouped(blocking).length;
      var ready = element("p", "phc-export-readiness" + (causes ? " is-blocked" : ""), checks.failed ?
        "The Model could not be checked." : causes ?
          "Finish " + causes + (causes === 1 ? " thing" : " things") + " before exporting." : "Ready to export.");
      if (!active()) root.appendChild(ready);
      checks.repairs.forEach(function (repair) {
        var label = element("label", "phc-export-repair"), input = element("input");
        input.type = "checkbox"; input.checked = Boolean(selected[repair.id]);
        input.disabled = Boolean(active() || waiting("start"));
        input.addEventListener("change", function () { selected[repair.id] = input.checked; });
        label.appendChild(input); label.appendChild(element("span", "", repair.label)); root.appendChild(label);
      });
      // Listed whenever the line above counts them, whether or not an earlier export is still on the page.
      if (!active()) {
        if (blocking.length) root.appendChild(findingList("Before exporting", blocking));
        if (advisory.length) root.appendChild(findingList("Worth checking", advisory, grouped(advisory).length > 5));
      }
    }
    if (!active() && (message || !task || !task.outcome)) root.appendChild(status);
    // A picker cancellation or request refusal does not create a task. Keep that message separate from
    // the preceding run: its outcome, counts, destination, report and findings all come from one handle.
    var history = element("section", "phc-export-last"), terminal = task && task.outcome;
    if (terminal) {
      var lastStatus = element("p", "phc-export-status", "Last export: " + terminal.message);
      lastStatus.setAttribute("role", "status");
      history.appendChild(lastStatus);
      root.appendChild(history);
    }
    if (task && task.outcome && task.outcome.value && task.outcome.value.result) {
      var canonical = task.outcome.value.result.canonical_model;
      if (canonical) history.appendChild(element("p", "", counted(canonical.rooms, "Room") + " · " +
        counted(canonical.faces, "Face") + " · " + counted(canonical.surface_pairs, "Surface pair")));
      if (task.outcome.value.location) {
        history.appendChild(element("p", "", "Written to " + task.outcome.value.location.label + "."));
      }
    }
    // A blocked run wrote nothing, but its report still holds the figures needed to clear the block. It is
    // built once per report, so a repaint keeps it open or shut as the user left it.
    var html = task && task.outcome && task.outcome.value && task.outcome.value.report_html;
    if (html) {
      if (!blockedReport || blockedReport.html !== html) {
        var details = element("details", "phc-export-blocked-report"), frame = element("iframe");
        details.appendChild(element("summary", "", "Last export report"));
        frame.setAttribute("sandbox", "");
        frame.setAttribute("title", "Last export report");
        frame.srcdoc = html;
        details.appendChild(frame);
        blockedReport = { html: html, node: details };
      }
      history.appendChild(blockedReport.node);
    }
    // What the last export reported and the checks above do not already say.
    var listed = Object.create(null);
    if (checks && !active()) checks.findings.forEach(function (finding) { listed[cause(finding)] = true; });
    var previous = terminal ? terminal.value && terminal.value.result ?
      terminal.value.result.findings || [] : terminal.findings || [] : [];
    var reported = previous.filter(function (finding) { return !listed[cause(finding)]; });
    if (reported.length) history.appendChild(findingList("From the last export", reported));
    var requestFindings = findings.filter(function (finding) { return !listed[cause(finding)]; });
    if (requestFindings.length) root.appendChild(findingList("From this request", requestFindings));
  }
  function render(root, state, send) {
    last = { root: root, state: state, send: send };
    if (state.session !== session) {
      window.clearTimeout(timer); timer = null; session = state.session; revision = null; seen = null;
      pending = {}; checks = null; selected = {}; task = null; message = ""; findings = []; retrieved = false;
      blockedReport = null;
      advisoriesOpen = false;
    }
    accept(state.ui.exportResult);
    if (state.ui.activeTab === "export") {
      if (revision !== state.revision && !active() && !waiting("start") && !waiting("preflight")) {
        revision = state.revision; request("preflight");
      }
      if (!retrieved) { retrieved = true; request("latest"); }
    }
    poll();
    ui.memoPaint(root, "export", [session, Boolean(waiting("start")), Boolean(waiting("cancel")),
      checks, task, message, findings], function () { paint(root); });
  }
  panel.navigationGuard("export", function () {
    return active() || waiting("start") ?
      "Export is running. Cancel it or wait for it to finish before changing tabs." : null;
  });
  window.addEventListener("beforeunload", function () { window.clearTimeout(timer); });
  panel.section("export", render, { pane: "export" });
});
