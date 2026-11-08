/* The panel page's one state and its message loop. The host sends the shown Model's snapshot, action
 * results, preference results and notices; a reducer folds each into the state and, when the state or the
 * display profile moved, every registered section re-renders from it. Presentation-only changes (the active
 * tab) never touch the host.
 *
 * Sections register through section(name, render, options). A section whose mount node is not in the page
 * is created in its pane, so a feature, or a development script, adds a section without editing index.html.
 * A section owns its local editing state and resets it when `state.session` changes.
 *
 * The panel acts only on the Model it shows: `action.invoke` carries the shown session and the revision the
 * panel last rendered, and a result or notice for another session is not painted.
 */
PhComposerUI.define("panel", ["unit_preferences", "workspace", "table_views", "request"], function (preferences, ui,
  tableViews, request) {
  "use strict";

  var sections = [];
  var navigationGuards = {};
  var DEFAULT_ORDER = 100;
  var state = initialState();
  var preferenceSequence = 0;
  // Preference choices the host has not confirmed yet, by name. Bookkeeping, not shown state: confirming one
  // changes nothing on screen unless the display profile moves.
  var pendingPreferences = {};
  var notice = null;
  var shownNotice = null;
  var api;

  var HANDLERS = {
    "panel.snapshot": reduceSnapshot,
    "action.result": reduceActionResult,
    "view.result": reduceViewResult,
    "setup.result": reduceSetupResult,
    "query.result": reduceQueryResult,
    "file_export.result": reduceFileExportResult,
    "preferences.result": reducePreferenceResult,
    "panel.notice": reduceNotice,
    "panel.failure": reduceFailure,
    "export.result": reduceExportResult,
    "panel.setup": reduceSetupEntries
  };

  function initialState() {
    return { session: null, revision: null, sections: {},
      ui: { activeTab: "overview", actionResult: null, viewResults: {}, setupResults: {}, queryResults: {},
        fileExportResults: {}, exportResult: null, notice: null } };
  }

  function copy(object) {
    var result = {};
    Object.keys(object || {}).forEach(function (key) { result[key] = object[key]; });
    return result;
  }

  function withUI(previous, changes) {
    var result = copy(previous);
    result.ui = copy(previous.ui);
    Object.keys(changes).forEach(function (key) { result.ui[key] = changes[key]; });
    return result;
  }

  /* A snapshot for another Model drops the previous Model's result and notice; the tab stays. */
  function reduceSnapshot(previous, payload) {
    var next = copy(payload);
    next.ui = copy(previous.ui);
    if (previous.session !== next.session) {
      next.ui.actionResult = null;
      next.ui.viewResults = {};
      next.ui.setupResults = {};
      next.ui.queryResults = {};
      next.ui.fileExportResults = {};
      next.ui.exportResult = null;
      next.ui.notice = null;
    }
    // A snapshot of no Model: the one shown closed and no other is active (PanelPresence).
    next.ui.noModel = next.session === null;
    preferences.replace(next.preferences, pendingPreferences);
    return next;
  }

  /* The owning view reads the outcome; a refusal or failure also stays on screen as a warning until the
     user dismisses it (context/CONTRACTS.md, "Public interface": the client shows the message). */
  function reduceActionResult(previous, payload) {
    var outcome = payload.outcome || {};
    var changes = { actionResult: payload };
    if (payload.session !== previous.session) return previous;
    if (outcome.status !== "completed") {
      changes.notice = { message: outcomeWords(payload) || outcome.message || "The change was not applied.",
        tone: outcome.status === "failed" ? "error" : "warning", action: helpFor(outcome) };
    }
    return withUI(previous, changes);
  }

  /* An unexpected failure carries the log's incident reference; Get help opens Help & Diagnostics at it. */
  function helpFor(outcome) {
    var incident = outcome.detail && outcome.detail.incident;
    if (typeof incident !== "string") return null;
    return { label: "Get help", run: function () { send("panel.support", { incident: incident }); } };
  }

  /* A viewport-state command changes what the host shows and never the Model, so a refusal is a warning
     about the view, never about an edit the user should check. Results are kept by request id, because
     several views send them independently; the oldest are dropped once the page is clearly done with
     them, which is a bound on the map rather than a promise about any one entry. */
  function reduceViewResult(previous, payload) {
    var outcome = payload.outcome || {};
    var changes = { viewResults: recentResults(previous.ui.viewResults, payload) };
    if (payload.session !== previous.session) return previous;
    if (outcome.status !== "completed") {
      changes.notice = { message: outcome.message || "The viewport did not change.",
        tone: outcome.status === "failed" ? "error" : "warning", action: helpFor(outcome) };
    }
    return withUI(previous, changes);
  }

  /* Session and machine setup answers the view that asked, which shows its own refusal. */
  function reduceSetupResult(previous, payload) {
    if (payload.session !== previous.session) return previous;
    return withUI(previous, { setupResults: recentResults(previous.ui.setupResults, payload) });
  }

  /* Reads answer their owner without republishing a snapshot or changing the Model. */
  function reduceQueryResult(previous, payload) {
    if (payload.session !== previous.session) return previous;
    return withUI(previous, { queryResults: recentResults(previous.ui.queryResults, payload) });
  }

  function reduceFileExportResult(previous, payload) {
    if (payload.session !== previous.session) return previous;
    return withUI(previous, { fileExportResults: recentResults(previous.ui.fileExportResults, payload) });
  }

  /* The Setup view's entries (sections/setup.js): machine setup, the same whichever Model is shown. */
  function reduceSetupEntries(previous, payload) {
    return withUI(previous, { setupEntries: payload.entries || [] });
  }

  /* The Export pane reads it; Export writes nothing to the Model, so no notice is raised. */
  function reduceExportResult(previous, payload) {
    if (payload.session !== previous.session) return previous;
    return withUI(previous, { exportResult: payload });
  }

  /* A confirmation leaves the state as it was: it shows only if the host's stored preferences move the display
     profile (receive). A refusal or failure restores the previous value and says why. */
  function reducePreferenceResult(previous, payload) {
    var name = Object.keys(pendingPreferences).filter(function (key) {
      return pendingPreferences[key].requestId === payload.request_id;
    })[0];
    var item;
    if (!name) return previous;
    item = pendingPreferences[name];
    delete pendingPreferences[name];
    preferences.replace(payload.preferences, pendingPreferences);
    if (payload.status === "completed") return previous;
    preferences.set(item.key, item.previous, item.extra);
    return withUI(previous, { notice: { message: payload.message || "The display preference could not be saved.",
      tone: "error" } });
  }

  function reduceNotice(previous, payload) {
    if (payload.session !== previous.session) return previous;
    return withUI(previous, { notice: { message: payload.message, tone: payload.tone || "info" } });
  }

  function reduceFailure(previous, payload) {
    return withUI(previous, { notice: { message: payload.message || "The panel request failed.", tone: "error" } });
  }

  var MAX_VIEW_RESULTS = 8;
  function recentResults(previous, payload) {
    var kept = copy(previous), ids = Object.keys(kept);
    kept[payload.request_id] = payload;
    ids.slice(0, Math.max(0, ids.length + 1 - MAX_VIEW_RESULTS)).forEach(function (id) { delete kept[id]; });
    return kept;
  }

  /* A message that leaves the state and the display profile as they were has nothing to show, so it renders
     nothing: a confirmed preference, a result for another Model. */
  function receive(envelope) {
    var handler = envelope && HANDLERS[envelope.type], payload = (envelope && envelope.payload) || {};
    var before = state, moved;
    if (!handler) return;
    moved = holdingProfileRepaint(function () { state = handler(state, payload); });
    offerHelp(before, payload);
    if (state === before && !moved) return;
    render();
  }

  /* An unexpected failure from any request carries its incident reference. Views show their own refusals,
     so where the answer raised no notice of its own, one with Get help is added for the failure. */
  function offerHelp(before, payload) {
    var outcome = payload.outcome, action;
    if (!outcome || outcome.status !== "failed" || payload.session !== state.session) return;
    if (state.ui.notice !== before.ui.notice || !(action = helpFor(outcome))) return;
    state = withUI(state, { notice: { message: outcome.message || "PH-Composer could not complete that request.",
      tone: "error", action: action } });
  }

  /* A pane's regions. `main` is the work surface and every section that names no region. `inspector` is
     a column beside it that shows one section at a time. `tools` is a group of small controls the work
     surface places in its own control row (`region(pane, "tools")`): view controls such as Colour by.
     `actions` is the same for the page header's authoring toolbar (`region(pane, "actions")`): tools that
     change the Model, such as Classify faces. A pane that offers either must place it, and until it does
     it leads the main region. A pane with only `main` sections is laid out exactly as before. The regions
     are marked `data-phc-region`, a name no section's content uses. */
  var REGIONS = ["main", "inspector", "tools", "actions"];
  /* Which inspector section shows when several want to: a tool in use, then what is selected, then the
     record in hand, then ambient reference. `order` breaks a tie inside a tier. */
  var TIERS = ["tool", "selection", "record", "ambient"];

  function region(paneName, name) {
    var pane = document.querySelector("[data-pane='" + paneName + "']");
    var node, main;
    if (!pane) throw new Error("no pane \"" + paneName + "\"");
    if (REGIONS.indexOf(name) < 0) throw new Error("no pane region \"" + name + "\"");
    node = pane.querySelector("[data-phc-region='" + name + "']");
    if (node || name === "main" && !pane.querySelector("[data-phc-region]")) return node || pane;
    // The first region a pane asks for wraps what is already in it as `main`.
    main = pane.querySelector("[data-phc-region='main']");
    if (!main) {
      main = ui.element("div", "phc-pane-main");
      main.setAttribute("data-phc-region", "main");
      while (pane.firstChild) main.appendChild(pane.firstChild);
      pane.appendChild(main);
    }
    if (name === "main") return main;
    node = name === "inspector" ? ui.element("aside", "phc-pane-inspector") :
      ui.element("div", name === "actions" ? "phc-pane-actions" : "phc-pane-tools");
    node.setAttribute("data-phc-region", name);
    if (name === "inspector") {
      node.hidden = true;
      node.setAttribute("aria-label", "Inspector");
      pane.classList.add("has-inspector");
      pane.appendChild(node);
    } else main.insertBefore(node, main.firstChild);
    return node;
  }

  function mount(entry) {
    var root = document.querySelector("[data-section='" + entry.name + "']");
    if (root) return root;
    if (!document.querySelector("[data-pane='" + entry.pane + "']")) {
      throw new Error("panel section \"" + entry.name + "\" names no pane \"" + entry.pane + "\"");
    }
    root = ui.element("section");
    root.setAttribute("data-section", entry.name);
    if (entry.region === "inspector") root.tabIndex = -1;
    region(entry.pane, entry.region).appendChild(root);
    return root;
  }

  /* An inspector shows one section. Each section's `when(state)` answers false, true or "hold": the
     first to hold wins, because it has a draft the user must not lose sight of; otherwise the first to
     answer true, by tier and then order. `when` runs after every section has rendered, so it may read
     what its own render just worked out. If the section that had the focus is hidden, the focus moves
     to the one now shown. */
  function wants(entry) {
    try { return entry.when ? entry.when(state) : true; } catch (error) {
      if (window.console) window.console.error("panel section \"" + entry.name + "\" failed its when", error);
      return false;
    }
  }

  function within(root, node) {
    for (; node; node = node.parentNode) if (node === root) return true;
    return false;
  }

  /* Whether a section is holding the pane's inspector. A control that would open another section there
     asks first, and says why it cannot, rather than opening something the user will not see. */
  function inspectorHeld(paneName) {
    return sections.some(function (entry) {
      return entry.region === "inspector" && entry.pane === paneName && wants(entry) === "hold";
    });
  }

  function showInspectors() {
    var byPane = Object.create(null);
    sections.forEach(function (entry) {
      var root = entry.region === "inspector" && document.querySelector("[data-section='" + entry.name + "']");
      if (root) (byPane[entry.pane] = byPane[entry.pane] || []).push({ entry: entry, root: root, want: wants(entry) });
    });
    Object.keys(byPane).forEach(function (paneName) {
      var candidates = byPane[paneName].slice().sort(function (left, right) {
        return TIERS.indexOf(left.entry.tier) - TIERS.indexOf(right.entry.tier) ||
          left.entry.order - right.entry.order || left.entry.registered - right.entry.registered;
      });
      var chosen = candidates.filter(function (item) { return item.want === "hold"; })[0] ||
        candidates.filter(function (item) { return item.want; })[0] || null;
      var active = document.activeElement, lostFocus = false;
      candidates.forEach(function (item) {
        var hide = item !== chosen;
        if (hide && !item.root.hidden && within(item.root, active)) lostFocus = true;
        item.root.hidden = hide;
      });
      region(paneName, "inspector").hidden = !chosen;
      if (lostFocus && chosen) chosen.root.focus();
    });
  }

  /* One section's failure stays in that section: the shell, the notices and every other section still
     paint, so a refusal warning is never hidden by an unrelated error. The host log records it. */
  function renderSection(entry) {
    try {
      entry.render(mount(entry), state, send);
    } catch (error) {
      if (window.console) window.console.error("panel section \"" + entry.name + "\" failed to render", error);
      report("panel_render_failed", entry.name, error);
    }
  }

  /* A page failure the host log records: the event, the section it happened in, the error's class and the
     panel's own frames, never the message, which can carry Model content. A page caught in a failure loop
     reports its first MAX_REPORTS and then stays quiet. Reporting never throws. */
  var MAX_REPORTS = 20, reports = 0;
  var JS_FRAME = /^\s+at (?:(\S+) \()?\S*?\/html\/([\w\/.-]+\.js):(\d+):\d+\)?$/;
  /* `fixedClass`, when given, is the class to name in place of the error's, with no frames: an event that is
     not an error, such as a Content-Security-Policy violation. */
  function report(event, sectionName, error, fixedClass) {
    if (reports >= MAX_REPORTS) return;
    reports += 1;
    try {
      send("panel.diagnostic", { event: event, section: sectionName || null,
        error_class: fixedClass || errorClass(error), frames: fixedClass ? [] : stackFrames(error) });
    } catch (ignored) { /* the report itself failed; the page carries on */ }
  }
  /* A rejection can be any value and an error's name can be set by anyone, so only the language's own error
     types are named; any other Error is "Error" and anything else "NotAnError". */
  var ERROR_TYPES = ["Error", "TypeError", "RangeError", "ReferenceError", "SyntaxError", "URIError", "EvalError"];
  function errorClass(error) {
    if (Object.prototype.toString.call(error) !== "[object Error]") return "NotAnError";
    return ERROR_TYPES.indexOf(error.name) >= 0 ? error.name : "Error";
  }
  /* Chromium starts a stack with the error's own "Name: message", which may span lines or look like a frame;
     only the lines after it are frames. A stack that does not start that way gives none. */
  function stackFrames(error) {
    var stack = String(error && error.stack || ""), head = String(error);
    if (!error || !error.stack || stack.indexOf(head) !== 0) return [];
    return stack.slice(head.length).split("\n").map(function (line) {
      var match = JS_FRAME.exec(line);
      return match && { file: "html/" + match[2], line: Number(match[3]), method: match[1] || "?" };
    }).filter(Boolean).slice(0, 20);
  }
  /* Cmd+Z and Cmd+Shift+Z (Ctrl+Z, Ctrl+Shift+Z and Ctrl+Y on Windows) step SketchUp's own Undo and Redo for the
     shown Model, as they do in the model window. A text field being edited keeps the keys for its own text; a
     grid cell at rest is read-only, so it passes them on. Nothing is sent while no Model is shown, or while a
     dialog is open: a held form's draft stays on the revision it read. */
  function textEditing(node) {
    if (!node) return false;
    if (node.isContentEditable) return true;
    if (/^textarea$/i.test(node.tagName || "")) return !node.readOnly;
    return /^input$/i.test(node.tagName || "") && !node.readOnly &&
      !/^(checkbox|radio|button|submit|reset|range|color|file)$/i.test(node.type || "");
  }
  function historyKey(event) {
    var key = String(event.key || "").toLowerCase();
    if (!(event.metaKey || event.ctrlKey) || event.altKey || event.defaultPrevented) return;
    var redo = (key === "z" && event.shiftKey) || (key === "y" && event.ctrlKey && !event.metaKey && !event.shiftKey);
    if (!(key === "z" || redo) || state.session === null || textEditing(event.target) || openModal()) return;
    if (event.preventDefault) event.preventDefault();
    if (redo) send("panel.redo", { session: state.session });
    else send("panel.undo", { session: state.session });
  }
  if (document.addEventListener) document.addEventListener("keydown", historyKey);
  // Closing the active document tells the host nothing; the panel's window gaining focus lets it catch up.
  if (window.addEventListener) window.addEventListener("focus", function () { send("panel.focus", {}); });
  if (window.addEventListener) {
    window.addEventListener("error", function (event) { report("panel_uncaught_error", null, event && event.error); });
    window.addEventListener("unhandledrejection", function (event) {
      report("panel_unhandled_rejection", null, event && event.reason);
    });
    /* Something the page's Content-Security-Policy blocked. The violated directive and URL stay in the page:
       the log takes no free text. */
    window.addEventListener("securitypolicyviolation", function () {
      report("panel_csp_violation", null, null, "SecurityPolicyViolation");
    });
  }

  function render() {
    ui.attachTooltip(document.body);
    api.state = state;
    renderNotice();
    renderUnitToggle();
    applyTab();
    renderNoModel();
    if (state.session !== null) { sections.forEach(renderSection); showInspectors(); }
    else if (state.ui.noModel) sections.filter(function (entry) { return entry.withoutModel; }).forEach(renderSection);
    renderRecovery();
    document.body._checkTooltip();
  }

  /* With no Model active the panes would keep the closed Model's last screen; they hide behind one line that
     says how to show a Model. The host sends such a snapshot when it learns the Model it showed has closed. */
  var noModelNote = null;
  function renderNoModel() {
    var none = Boolean(state.ui.noModel), panes = document.querySelector(".panel-panes");
    if (!panes) return;
    // A dialog the closed Model's screen held open (a form, a review) can only send to a session that is gone,
    // so it closes with it; a Model shown later is a new session and builds its screens afresh.
    if (none && !panes.hidden) {
      Array.prototype.forEach.call(document.querySelectorAll("dialog"), function (dialog) {
        if (dialog.closeModal) dialog.closeModal();
        else if (dialog.open && dialog.close) dialog.close();
      });
    }
    if (none && !noModelNote) {
      noModelNote = ui.element("p", "phc-no-model", "No Model is active. Click a SketchUp document window to show " +
        "it here.");
      noModelNote.setAttribute("role", "status");
      panes.parentNode.insertBefore(noModelNote, panes);
    }
    if (noModelNote) noModelNote.hidden = !none;
    panes.hidden = none;
  }

  /* One floating notice above the panes, so a late message never reflows the page. Warnings and errors stay
     until dismissed; information fades on the next interaction; a success confirmation also fades by itself. */
  function renderNotice() {
    var layer = document.querySelector("[data-notice-layer]");
    var current = state.ui.notice;
    if (!layer) return;
    if (!notice) notice = ui.floatingNotice(document.body);
    // An open modal makes the page behind it inert, so the notice, and any way out it offers, shows in it.
    var host = openModal() || layer;
    if (notice.parentNode !== host) host.appendChild(notice);
    if (current === shownNotice) return;
    shownNotice = current;
    if (!current) { notice.clear(); return; }
    notice.show(current.message, { tone: current.tone, action: current.action,
      persistent: current.tone === "warning" || current.tone === "error" });
  }

  function openModal() {
    return Array.prototype.filter.call(document.querySelectorAll("dialog"), function (node) {
      return node.open;
    }).pop() || null;
  }

  function applyTab() {
    var name = state.ui.activeTab;
    Array.prototype.forEach.call(document.querySelectorAll("[data-pane]"), function (pane) {
      pane.hidden = pane.getAttribute("data-pane") !== name;
    });
    Array.prototype.forEach.call(document.querySelectorAll("[data-tab]"), function (tab) {
      var current = tab.getAttribute("data-tab") === name;
      tab.setAttribute("aria-pressed", String(current));
      // A tab row narrower than its tabs scrolls; the current tab stays in view.
      if (current && tab.scrollIntoView) tab.scrollIntoView({ block: "nearest", inline: "nearest" });
    });
  }

  function showTab(name) {
    if (!document.querySelector("[data-pane='" + name + "']")) return;
    if (name !== state.ui.activeTab) {
      var refusing = Object.keys(navigationGuards).filter(function (key) {
        return navigationGuards[key].guard(name);
      })[0];
      if (refusing) {
        var entry = navigationGuards[refusing];
        notify(entry.guard(name), "warning");
        if (entry.refused) entry.refused();
        return;
      }
    }
    state = withUI(state, { activeTab: name });
    render();
  }

  /* Shows `name`'s tab through the same guards as a tab click, then hands `intent` to each of that tab's
     sections that registered `onNavigate(root, intent)`, so a control elsewhere can open a tab at the
     right place. Returns whether the tab is shown; a refusing guard has already said why. */
  function navigate(name, intent) {
    showTab(name);
    if (state.ui.activeTab !== name) return false;
    sections.forEach(function (entry) {
      if (entry.pane === name && entry.onNavigate) entry.onNavigate(mount(entry), intent || {});
    });
    return true;
  }

  /* `options.pane` names the tab the section belongs to (default "overview"). `options.order` places
     it within that pane, low first; sections that do not ask are placed after those that do, in the
     order they registered. A pane holds the screen's work surface first and its secondary controls
     after it, and load order is decided by the module graph, so a section that cares says so.
     `options.onNavigate(root, intent)` receives the intent of a `navigate` to its pane.
     `options.region` places it in the pane's `inspector`, `tools` or `actions` region instead of `main`. An
     inspector section names its `options.tier` and may give `options.when(state)`; see showInspectors.
     `options.withoutModel` keeps a section rendering while no Model is active (renderNoModel), as the status bar
     does; every other section waits for a Model. */
  function section(name, renderFunction, options) {
    var entry = { name: name, render: renderFunction, pane: (options && options.pane) || "overview",
      region: (options && options.region) || "main", when: options && options.when,
      tier: options && options.tier,
      order: (options && options.order) !== undefined ? options.order : DEFAULT_ORDER,
      onNavigate: options && options.onNavigate, withoutModel: Boolean(options && options.withoutModel),
      registered: sections.length };
    if (REGIONS.indexOf(entry.region) < 0) {
      throw new Error("panel section \"" + name + "\" names no region \"" + entry.region + "\"");
    }
    if (entry.region === "inspector" && TIERS.indexOf(entry.tier) < 0) {
      throw new Error("inspector section \"" + name + "\" needs a tier: " + TIERS.join(", "));
    }
    if (!document.querySelector("[data-section='" + name + "']") &&
        !document.querySelector("[data-pane='" + entry.pane + "']")) {
      throw new Error("panel section \"" + name + "\" names no pane \"" + entry.pane + "\"");
    }
    sections.push(entry);
    sections.sort(function (left, right) {
      return left.order - right.order || left.registered - right.registered;
    });
    if (state.session !== null) { sections.forEach(renderSection); showInspectors(); }
  }

  function preferenceValue(key, extra) {
    var current = preferences.current();
    if (key === "unit_system") return current.unitSystem;
    if (key === "table_view") return preferences.tableView(extra.scope);
    return preferences.dimensionFormat(extra.scope, extra.system);
  }

  /* Applies a display preference at once and asks the host to remember it; a refusal restores the previous
     value. `extra` is `{ scope, system }` for a dimension format and `{ scope }`, the host id, for a table
     view. */
  function setPreference(key, value, extra) {
    var details = extra || {};
    var name = key === "dimension_format" ? key + "." + details.scope + "." + details.system :
      key === "table_view" ? key + "." + details.scope : key;
    var requestId = "preferences:" + String(preferenceSequence += 1);
    var payload = { request_id: requestId, key: key, value: value };
    if (key === "dimension_format") {
      payload.scope = details.scope;
      payload.system = details.system;
    }
    if (key === "table_view") payload.scope = details.scope;
    pendingPreferences[name] = { requestId: requestId, key: key, value: value, extra: details,
      previous: preferenceValue(key, details) };
    // setPreference renders once, whether or not the choice moves the display profile (a table view does not).
    holdingProfileRepaint(function () { preferences.set(key, value, details); });
    render();
    send("preferences.set", payload);
    return requestId;
  }

  var renderedUnitSystem = null;
  function renderUnitToggle() {
    var system = preferences.current().unitSystem;
    if (system === renderedUnitSystem) return;
    renderedUnitSystem = system;
    Array.prototype.forEach.call(document.querySelectorAll("[data-unit-system]"), function (button) {
      button.setAttribute("aria-pressed", String(button.getAttribute("data-unit-system") === system));
    });
  }

  /* The one route to the host. An action names the shown session and, unless the caller gives one, the
     revision this page last rendered. */
  function send(type, payload) {
    var message = copy(payload);
    if (type === "action.invoke" && message.expected_revision === undefined) message.expected_revision = state.revision;
    if (window.sketchup && window.sketchup.ph_composer_message) {
      window.sketchup.ph_composer_message(JSON.stringify({ type: type, payload: message }));
    }
  }

  /* Requests the host has not answered in time (request.js), each with its way out. They are kept apart from
     the single notice slot, so no other message, and no dismissal, can take the way out away; each goes when
     its request settles. An edit is never sent again: Check status asks the host what became of it, which
     also brings the Model's state up to date. Any other request can only stop waiting; its answer, if it
     still comes, is ignored, so its result is left for the user to check. */
  var unanswered = [], recovery = null;
  function unconfirmed(channel) {
    if (channel.session !== state.session) return;
    if (!unanswered.some(function (item) { return item.channel === channel && item.id === channel.pending; })) {
      unanswered.push({ channel: channel, id: channel.pending });
    }
    render();
  }
  request.onUnconfirmed(unconfirmed);

  /* After every section has rendered, since a section's render is where its request settles. The bar sits in
     an open modal when there is one, because the page behind it cannot be reached. */
  function renderRecovery() {
    var layer = document.querySelector("[data-notice-layer]"), host;
    unanswered = unanswered.filter(function (item) {
      return item.channel.pending === item.id && !item.channel.abandoned && item.channel.session === state.session;
    });
    if (!layer) return;
    if (!recovery) {
      recovery = ui.element("div", "phc-floating-notice phc-recovery");
      recovery.setAttribute("data-tone", "warning");
      recovery.setAttribute("role", "alert");
    }
    recovery.hidden = !unanswered.length;
    recovery.replaceChildren.apply(recovery, unanswered.map(recoveryRow));
    host = openModal() || layer;
    if (recovery.parentNode !== host) host.appendChild(recovery);
  }
  ui.onModalChange(renderRecovery);
  function recoveryRow(item) {
    var channel = item.channel, action = channel.message === "action.invoke";
    var row = ui.element("div", "phc-recovery-row");
    row.appendChild(ui.element("span", "phc-floating-notice-message", action ?
      "PH-Composer has not confirmed this change yet. It may have been applied, or its answer was lost." :
      "PH-Composer has not answered this request yet, so its result is not known."));
    // Bound to the request that raised it: a later request on the same channel is never checked or dropped.
    row.appendChild(ui.button(action ? "Check status" : "Stop waiting", function () {
      if (channel.pending !== item.id) { repaint(); return; }
      if (action) channel.checkStatus(); else { channel.abandon(); repaint(); }
    }));
    return row;
  }

  /* A notice raised by the page itself, such as a refused navigation. It never reaches the host. An
     `action` ({ label, run }) puts the way out on the notice itself, such as cancelling the held draft. */
  function notify(message, tone, action) {
    state = withUI(state, { notice: { message: message, tone: tone || "info", action: action || null } });
    render();
  }
  /* Takes down the page's own notice once what it reported no longer holds, such as a refused navigation that
     has since gone through. Only while that message is still the one shown; a newer notice stays. */
  function withdraw(message) {
    if (!state.ui.notice || state.ui.notice.message !== message) return;
    state = withUI(state, { notice: null });
    render();
  }

  /* A view may restate a refused or failed outcome of its own request in its users' words; the host's message
     and code stay the contract. Each translator answers text or null for a detached
     `{ request_id, session, outcome }`; `options.owner` names it in diagnostics, and the returned function
     removes it. A translator that throws or answers something other than a string is skipped and logged under
     its owner; it never stops the result being recorded, because the reducer that calls it must return. The
     first string with visible text wins; a blank one declines. Iteration runs over a copy, so disposal during
     a call takes effect from the next outcome. */
  var translators = [];
  function outcomeText(translate, options) {
    var owner = options && options.owner;
    if (typeof translate !== "function") throw new Error("panel.outcomeText needs a function");
    if (owner !== undefined && (typeof owner !== "string" || !owner)) {
      throw new Error("panel.outcomeText owner must be a nonempty string");
    }
    var entry = { translate: translate, owner: owner || "anonymous" };
    translators.push(entry);
    return function dispose() {
      var index = translators.indexOf(entry);
      if (index >= 0) translators.splice(index, 1);
    };
  }
  function outcomeWords(payload) {
    var current = translators.slice();
    for (var index = 0; index < current.length; index += 1) {
      var text;
      try { text = current[index].translate(JSON.parse(JSON.stringify(payload))); } catch (error) {
        translatorFailed(current[index], "threw", error);
        continue;
      }
      if (text === null || text === undefined || text === "") continue;
      if (typeof text !== "string") { translatorFailed(current[index], "answered " + typeof text); continue; }
      if (!text.trim()) continue;
      return text;
    }
    return null;
  }
  /* A diagnostic must not become a second failure: a missing or throwing console is ignored. */
  function translatorFailed(entry, what, error) {
    try {
      if (window.console) window.console.error("panel.outcomeText " + entry.owner + " " + what, error || "");
    } catch (ignored) { /* the console itself failed */ }
  }

  /* Sent once the page has started, so the first snapshot has somewhere to render. */
  /* Every module has started: a table view whose host never declared itself is a registration mistake. */
  function ready() {
    var orphans = tableViews.unhosted();
    if (orphans.length && window.console) window.console.error("table views with no host: " + orphans.join(", "));
    send("panel.ready", {});
  }

  /* A presentation-only change: a section that owns local view state (a selection, a filter, an open
     row) repaints every section from the state already in hand. It never reaches the host. */
  function repaint() { render(); }

  /* The display profile (unit system, dimension formats, number format) has one repaint owner: the panel renders
     every section once when it moves. A step that renders when it ends, a received message or a preference
     chosen here, holds that render so the change shows in the step's own. Components that patch their own
     nodes (record edits, unit fields) keep their own subscriptions. */
  var profileHolds = 0, profileMoved = false;
  preferences.subscribe(function () {
    if (profileHolds) profileMoved = true;
    else render();
  });
  /* Runs work with the profile's render held; answers whether the profile moved since the outermost hold
     began. */
  function holdingProfileRepaint(work) {
    if (!profileHolds) profileMoved = false;
    profileHolds += 1;
    try { work(); } finally { profileHolds -= 1; }
    return profileMoved;
  }

  var worked = [];
  api = { receive: receive, section: section, region: region, inspectorHeld: inspectorHeld, ready: ready,
    state: state, showTab: showTab, navigate: navigate,
    send: send,
    setPreference: setPreference, repaint: repaint, notify: notify, withdraw: withdraw, outcomeText: outcomeText,
    // `guard(tab)` answers why the tab may not change, or null; `refused`, when given, runs after a
    // refusal is shown, so a section can point the user at the work that holds the tab.
    navigationGuard: function (name, guard, refused) { navigationGuards[name] = { guard: guard, refused: refused }; },
    // A feature says which tab its records are worked on: `prefix` is its id, which every section it owns
    // starts with. `tabFor(owner)` answers { tab, label } for the longest prefix that is `owner` or ends at one
    // of its dots, or null, so a foundation screen can send the user to a gap without naming any feature.
    workedOn: function (prefix, tab) { worked.push({ prefix: prefix, tab: tab }); },
    tabFor: function (owner) {
      var text = String(owner || ""), best = null;
      worked.forEach(function (entry) {
        var fits = text === entry.prefix || text.indexOf(entry.prefix + ".") === 0;
        if (fits && (!best || entry.prefix.length > best.prefix.length)) best = entry;
      });
      var button = best && document.querySelector("[data-tab='" + best.tab + "']");
      return button ? { tab: best.tab, label: String(button.textContent || "").trim() || best.tab } : null;
    }
  };
  Array.prototype.forEach.call(document.querySelectorAll("[data-tab]"), function (tab) {
    tab.addEventListener("click", function () { showTab(tab.getAttribute("data-tab")); });
  });
  Array.prototype.forEach.call(document.querySelectorAll("[data-unit-system]"), function (button) {
    button.addEventListener("click", function () {
      var system = button.getAttribute("data-unit-system");
      if (preferences.current().unitSystem !== system) setPreference("unit_system", system);
    });
  });
  return api;
});
