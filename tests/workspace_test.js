"use strict";

/* The shared presentation kit: anchored bubbles, memoised paints, floating notices and the record form
   lifecycle. Transport-free. Browser layout is a separate gate; nothing here measures a box. */

var assert = require("assert");
var test = require("node:test");
var vm = require("vm");
var dom = require("./support/dom_stub");
var panelSource = require("./support/panel_source");

/* A whole stub document, not just a createElement: the bubble attaches listeners to the document, and a
   placement case has to be able to fire them. */
var context = {
  innerWidth: 1280, innerHeight: 800,
  document: dom.buildDocument(""),
  setTimeout: setTimeout,
  clearTimeout: clearTimeout
};
context.window = context;
vm.createContext(context);
var modules = panelSource.start(context, ["workspace", "record_form"]);
var ui = modules.workspace;

test("a detached drawing trigger stays in its scrollport and keeps Bubble activation and dismissal", function () {
  var scroll = dom.element("div"), trigger = dom.element("button"), child = dom.element("span");
  context.document.body.appendChild(scroll); scroll.appendChild(trigger); trigger.appendChild(child);
  var bubble = new ui.Bubble(trigger, "Drawing width", { detachedTrigger: true });
  context.document.body.appendChild(bubble.root);
  assert.strictEqual(trigger.parentNode, scroll);
  assert.strictEqual(bubble.root.contains(trigger), false);
  trigger.listeners.click({});
  assert.strictEqual(bubble.panel.hidden, false);
  context.document.dispatchEvent({ type: "mousedown", target: child });
  assert.strictEqual(bubble.panel.hidden, false, "pressing the trigger cannot close before its click toggles");
  trigger.listeners.click({}); assert.strictEqual(bubble.panel.hidden, true);
  trigger.listeners.keydown({ key: "ArrowDown", preventDefault: function () {} });
  assert.strictEqual(bubble.panel.hidden, false);
  trigger.listeners.keydown({ key: "Escape", preventDefault: function () {} });
  assert.strictEqual(bubble.panel.hidden, true);
  assert.strictEqual(context.document.activeElement, trigger);
  bubble.open(false);
  context.document.dispatchEvent({ type: "mousedown", target: context.document.body });
  assert.strictEqual(bubble.panel.hidden, true, "outside pointer input still dismisses the editor");
});

test("a bubble with no room below it opens above its trigger", function () {
  var trigger = dom.element("button");
  context.document.body.appendChild(trigger);
  var bubble = new ui.Bubble(trigger, "Options", {});
  context.document.body.appendChild(bubble.panel);
  bubble.panel.rect = { left: 0, top: 0, right: 300, bottom: 250, width: 300, height: 250 };
  bubble.content.rect = { left: 0, top: 60, right: 300, bottom: 250, width: 300, height: 190 };
  // Near the bottom of an 800px window: 250 of panel plus the gap does not fit under it, and
  // there is more room above.
  trigger.rect = { left: 100, top: 700, right: 160, bottom: 730, width: 60, height: 30 };

  bubble.open(false);

  assert.strictEqual(bubble.panel.classList.contains("is-above"), true);
  assert.strictEqual(bubble.panel.style.top, "440px", "the panel sits its own height above the trigger");
  bubble.close(false);
});

test("a bubble with room below it opens below, where it belongs", function () {
  var trigger = dom.element("button");
  context.document.body.appendChild(trigger);
  var bubble = new ui.Bubble(trigger, "Options", {});
  context.document.body.appendChild(bubble.panel);
  bubble.panel.rect = { left: 0, top: 0, right: 300, bottom: 250, width: 300, height: 250 };
  bubble.content.rect = { left: 0, top: 60, right: 300, bottom: 250, width: 300, height: 190 };
  trigger.rect = { left: 100, top: 100, right: 160, bottom: 130, width: 60, height: 30 };

  bubble.open(false);

  assert.strictEqual(bubble.panel.classList.contains("is-above"), false);
  assert.strictEqual(bubble.panel.style.top, "140px");
  bubble.close(false);
});

test("a memoised paint runs only when its inputs change, per owner and key", function () {
  var owner = {}, paints = 0;
  function paint() { paints += 1; }

  assert.strictEqual(ui.memoPaint(owner, "audit", [["rec_a"], "SI"], paint), true);
  assert.strictEqual(ui.memoPaint(owner, "audit", [["rec_a"], "SI"], paint), false, "unchanged inputs skip the paint");
  assert.strictEqual(ui.memoPaint(owner, "drawing", [["rec_a"], "SI"], paint), true, "another key memoises separately");
  assert.strictEqual(ui.memoPaint(owner, "audit", [["rec_a"], "IP"], paint), true);
  assert.strictEqual(ui.memoPaint(owner, "audit", [["rec_a"], "IP"]), false, "the paint callback is optional");
  assert.strictEqual(paints, 3);
});

test("a side bubble opens to the trigger's right, and flips left when the right has no room", function () {
  var trigger = dom.element("button");
  context.document.body.appendChild(trigger);
  var bubble = new ui.Bubble(trigger, "Submenu", { side: true });
  context.document.body.appendChild(bubble.panel);
  bubble.panel.rect = { left: 0, top: 0, right: 300, bottom: 250, width: 300, height: 250 };
  trigger.rect = { left: 100, top: 100, right: 160, bottom: 130, width: 60, height: 30 };

  bubble.open(false);
  assert.strictEqual(bubble.panel.classList.contains("is-submenu"), true);
  assert.strictEqual(bubble.panel.classList.contains("opens-left"), false);
  assert.strictEqual(bubble.panel.style.left, "168px", "right of the trigger by the side gap");
  assert.strictEqual(bubble.panel.style.top, "100px");
  bubble.close(false);

  // A trigger near the right edge of the 1280px window: the right side cannot hold 300px, the left side can.
  trigger.rect = { left: 1000, top: 100, right: 1060, bottom: 130, width: 60, height: 30 };
  bubble.open(false);
  assert.strictEqual(bubble.panel.classList.contains("opens-left"), true);
  assert.strictEqual(bubble.panel.style.left, "692px", "left of the trigger by the side gap");
  bubble.close(false);
});

test("a warning notice stays until dismissed; an information notice fades on the next interaction", function () {
  var owner = dom.element("div");
  dom.attachEvents(owner);
  context.document.body.appendChild(owner);
  var notice = ui.floatingNotice(owner);
  owner.appendChild(notice);

  notice.show("Nothing was written.", { tone: "warning", persistent: true });
  owner.dispatchEvent({ type: "pointerdown", target: owner });
  assert.strictEqual(notice.hidden, false, "a warning survives unrelated clicks");
  assert.strictEqual(notice.getAttribute("data-tone"), "warning");
  assert.strictEqual(notice.message.getAttribute("role"), "status");
  assert.strictEqual(notice.dismissButton.getAttribute("aria-label"), "Dismiss message");
  notice.dismissButton.listeners.click({});
  assert.strictEqual(notice.hidden, true, "Dismiss clears it");

  notice.show("Saved.");
  assert.strictEqual(notice.getAttribute("data-tone"), "info", "information is the default tone");
  notice.fade();
  assert.strictEqual(notice.classList.contains("is-dismissing"), true);
  notice.dispose();
});

test("Escape closes a warning, one layer at a time: a bubble or a dialog that is open takes it first", function () {
  var owner = dom.element("div"), prevented = 0;
  dom.attachEvents(owner);
  context.document.body.appendChild(owner);
  var notice = ui.floatingNotice(owner);
  owner.appendChild(notice);
  function escape() {
    owner.dispatchEvent({ type: "keydown", key: "Escape", target: owner,
      preventDefault: function () { prevented += 1; } });
  }
  notice.show("Nothing was written.", { tone: "warning", persistent: true });
  var trigger = dom.element("button"); owner.appendChild(trigger);
  var bubble = new ui.Bubble(trigger, "Open"); owner.appendChild(bubble.root);
  bubble.open(false);
  escape();
  assert.strictEqual(notice.hidden, false, "the open bubble takes Escape; the warning stays");
  assert.strictEqual(prevented, 0, "and the key still reaches the bubble");
  bubble.close(false);
  escape();
  assert.strictEqual(notice.hidden, true, "with nothing else open, Escape closes the warning");
  assert.strictEqual(prevented, 1, "the warning used the key, so a tool beneath it keeps going");

  notice.show("Nothing was written.", { tone: "warning", persistent: true });
  var field = dom.element("input"); owner.appendChild(field);
  owner.dispatchEvent({ type: "keydown", key: "Escape", target: field,
    preventDefault: function () { prevented += 1; } });
  assert.strictEqual(notice.hidden, true, "pressed in a field, it closes the warning");
  assert.strictEqual(prevented, 1, "and a field keeps its own Escape");

  notice.show("Saved.");
  bubble.open(false);
  escape();
  bubble.close(false);
  assert.strictEqual(notice.classList.contains("is-dismissing"), true, "information fades on Escape, bubble or not");
  assert.strictEqual(prevented, 1, "and leaves the key to the tool it describes");
  notice.dispose();
});

test("a bubble opened from a table cell lifts that cell above the rows after it", function () {
  var td = dom.element("td"), trigger = dom.element("button");
  context.document.body.appendChild(td);
  var bubble = new ui.Bubble(trigger, "Used by Assemblies");
  td.appendChild(bubble.root);
  bubble.open(false);
  assert.strictEqual(td.classList.contains("has-open-bubble"), true);
  bubble.close(false);
  assert.strictEqual(td.classList.contains("has-open-bubble"), false);
});

test("a success notice fades by itself, unless the pointer holds it, and a newer message replaces it", function () {
  var owner = dom.element("div"), timers = [], saved = [context.setTimeout, context.clearTimeout];
  dom.attachEvents(owner);
  context.setTimeout = function (callback, delay) {
    timers.push({ callback: callback, delay: delay });
    return timers.length;
  };
  context.clearTimeout = function (id) { if (timers[id - 1]) timers[id - 1].cleared = true; };
  var notice = ui.floatingNotice(owner);
  function due() { return timers.filter(function (timer) { return !timer.cleared && timer.delay >= 3000; }); }
  try {
    notice.show("Zone made.", { tone: "success" });
    assert.strictEqual(due().length, 1, "a success confirmation starts its own clock");
    notice.listeners.mouseenter({});
    assert.strictEqual(due().length, 0, "hovering holds it");
    notice.listeners.mouseleave({});
    assert.strictEqual(due().length, 1);
    notice.show("Make Zone needs a selection.", { tone: "warning", persistent: true });
    assert.strictEqual(due().length, 0, "a newer message stops the old clock; a warning has none");
    notice.show("Zone made.", { tone: "success" });
    due().slice(-1)[0].callback();
    assert.strictEqual(notice.classList.contains("is-dismissing"), true);
    // Dismissed while held: a hidden notice never sends its leave, so the hold must not outlive it.
    notice.show("Zone made.", { tone: "success" });
    notice.listeners.mouseenter({});
    notice.dismissButton.listeners.click({});
    var mark = timers.length;
    notice.show("Zone made again.", { tone: "success" });
    assert.strictEqual(timers.slice(mark).filter(function (timer) { return timer.delay >= 3000; }).length, 1,
      "the next confirmation still fades");
    notice.show(new Array(30).join("A longer confirmation. "), { tone: "success" });
    assert.ok(timers.slice(-1)[0].delay > 3000, "a long message stays longer");
  } finally {
    context.setTimeout = saved[0]; context.clearTimeout = saved[1];
    notice.dispose();
  }
});

test("a dialog's top-right close is its Cancel, comes back after its owner replaces the content, and closing " +
  "returns focus", function () {
  var cancelled = 0, dialog = ui.formDialog("", function () { cancelled += 1; dialog.closeModal(); });
  var opener = dom.element("button");
  context.document.body.appendChild(opener); context.document.body.appendChild(dialog);
  opener.focus();
  dialog.openModal();
  var close = dialog.querySelector(".phc-dialog-close");
  assert.strictEqual(close.getAttribute("aria-label"), "Close");
  close.listeners.click({});
  assert.strictEqual(cancelled, 1);
  assert.ok(context.document.activeElement === opener, "focus returns to what opened the dialog");
  dialog.replaceChildren(dom.element("h2"));
  dialog.openModal();
  assert.ok(dialog.children[0] === close, "the close control is back, first");
});

test("a record form sends once, keeps Cancel disabled while pending and shows a refusal until closed", function () {
  var sent = [], changes = [];
  var form = new modules.record_form(
    "session-a", function (type, payload) { sent.push({ type: type, payload: payload }); },
    { title: "New part", action: "example.create", label: "create", submitLabel: "Create",
      pendingText: "Creating...", failureText: "The part was not created.",
      changed: function (arg) { changes.push(arg); } }
  );
  form.finish();
  form.show();
  assert.strictEqual(form.root.hidden, false);

  assert.notStrictEqual(form.run({ label: "Frame" }), false);
  assert.strictEqual(form.run({ label: "Frame" }), false, "single flight");
  assert.strictEqual(sent.length, 1);
  assert.strictEqual(form.cancel.disabled, true);
  form.hide();
  assert.strictEqual(form.root.hidden, false, "Cancel is refused while the request is pending");

  var outcome = { status: "refused", code: "params.invalid", message: "Label is required. Nothing was written." };
  var result = { request_id: sent[0].payload.request_id, session: "session-a", outcome: outcome };
  assert.strictEqual(form.settle({ ui: { actionResult: result } }), outcome);
  assert.strictEqual(form.error.textContent, outcome.message);
  assert.strictEqual(form.cancel.disabled, false);
  form.hide("cancelled");
  assert.strictEqual(form.root.hidden, true);
  assert.deepStrictEqual(changes, ["cancelled"]);
});

test("the text primitives read absent values as blank and compare numbers the way a person reads them", function () {
  assert.strictEqual(ui.titleCase("window_type"), "Window type");
  assert.strictEqual(ui.titleCase(null), "");
  assert.strictEqual(ui.number(1.234), "1.23");
  assert.strictEqual(ui.number(0.5, true), "0.5");
  assert.strictEqual(ui.number(NaN), "-");
  assert.deepStrictEqual([ui.blank(""), ui.blank(null), ui.blank(0)], [true, true, false]);
  assert.deepStrictEqual(["Part 10", "part 2"].sort(ui.compareText), ["part 2", "Part 10"]);
  var row = ui.propertyRow("Length", null, "mm");
  assert.deepStrictEqual(row.children.map(function (node) { return node.textContent; }), ["Length", "— mm"]);
  assert.strictEqual(ui.option("cm", "Centimetres").value, "cm");
  assert.strictEqual(ui.svg("path", { d: "M0 0" }).getAttribute("d"), "M0 0");
});

test("a change pulse animates only where the host can and the user has not asked for less motion", function () {
  var plain = dom.element("div");
  assert.strictEqual(ui.pulse(plain), null, "no Web Animations, no pulse");
  var animated = dom.element("div"), cancelled = 0;
  animated.animate = function () { return { cancel: function () { cancelled += 1; } }; };
  assert.strictEqual(ui.pulse(animated).length, 2);
  ui.pulse(animated);
  assert.strictEqual(cancelled, 2, "a second pulse replaces the first");
  context.matchMedia = function () { return { matches: true }; };
  assert.strictEqual(ui.pulse(animated), null, "reduced motion is honoured");
  delete context.matchMedia;
});

test("an action menu runs its item once, closes, and marks destructive items", function () {
  var ran = [];
  var menu = new ui.ActionMenu("Part actions");
  context.document.body.appendChild(menu.root);
  var remove = menu.add("Delete", function () { ran.push("delete"); }, { destructive: true, icon: "delete" });
  menu.trigger.listeners.click({});
  assert.strictEqual(menu.bubble.panel.hidden, false);
  remove.listeners.click({});
  assert.deepStrictEqual(ran, ["delete"]);
  assert.strictEqual(menu.bubble.panel.hidden, true);
  assert.strictEqual(remove.classList.contains("phc-danger-action"), true);
  assert.strictEqual(menu.trigger.getAttribute("aria-label"), "Part actions");
});

test("an action menu takes its own icon, and an unavailable one says why and opens nothing", function () {
  var menu = new ui.ActionMenu("Labels", { icon: "tag" });
  context.document.body.appendChild(menu.root);
  assert.strictEqual(menu.trigger.getAttribute("data-icon"), "tag");
  menu.trigger.listeners.click({});
  menu.setUnavailable("Turn on Show Spaces first.");
  assert.strictEqual(menu.bubble.panel.hidden, true, "an open menu that becomes unavailable closes");
  assert.deepStrictEqual([menu.trigger.getAttribute("aria-disabled"), menu.trigger.getAttribute("aria-label"),
    menu.trigger.getAttribute("data-tooltip"), menu.trigger.disabled],
  ["true", "Labels. Turn on Show Spaces first.", "Turn on Show Spaces first.", false]);
  menu.trigger.listeners.click({});
  menu.trigger.listeners.keydown({ key: "ArrowDown", preventDefault: function () {} });
  assert.strictEqual(menu.bubble.panel.hidden, true);
  menu.setUnavailable(null);
  assert.deepStrictEqual([menu.trigger.getAttribute("aria-disabled"), menu.trigger.getAttribute("aria-label"),
    menu.trigger.getAttribute("data-tooltip")], [null, "Labels", "Labels"]);
  menu.trigger.listeners.click({});
  assert.strictEqual(menu.bubble.panel.hidden, false);
});

test("a dialog opened from an action menu item returns focus to the menu's trigger", function () {
  var dialog = ui.formDialog("", function () { dialog.closeModal(); });
  var menu = new ui.ActionMenu("More actions");
  context.document.body.appendChild(menu.root); context.document.body.appendChild(dialog);
  var item = menu.add("Reset display preferences…", function () { dialog.openModal(); });
  menu.trigger.listeners.click({});
  item.focus();
  item.listeners.click({});
  assert.strictEqual(menu.bubble.panel.hidden, true);
  dialog.closeModal();
  assert.ok(context.document.activeElement === menu.trigger, "the hidden item is never the dialog's opener");
});

test("Escape closes a bubble and returns focus; a press outside closes it without moving focus", function () {
  var trigger = dom.element("button");
  context.document.body.appendChild(trigger);
  var bubble = new ui.Bubble(trigger, "Dimension format", {});
  context.document.body.appendChild(bubble.root);
  var choice = dom.element("button");
  bubble.content.appendChild(choice);
  trigger.listeners.keydown({ key: "ArrowDown", preventDefault: function () {} });
  assert.strictEqual(context.document.activeElement, choice, "opening moves focus to the first control");
  assert.strictEqual(ui.Bubble.activeTitle(), "Dimension format");

  bubble.root.listeners.keydown({ key: "Escape", preventDefault: function () {} });
  assert.strictEqual(bubble.panel.hidden, true);
  assert.strictEqual(context.document.activeElement, trigger);

  bubble.open(false);
  context.document.dispatchEvent({ type: "mousedown", target: context.document.body });
  assert.strictEqual(bubble.panel.hidden, true);
  assert.strictEqual(context.document.activeElement, trigger);
});

test("a submenu opens its parent, closes its siblings, and closes with the parent", function () {
  var parentTrigger = dom.element("button"), first = dom.element("button"), second = dom.element("button");
  [parentTrigger, first, second].forEach(function (node) { context.document.body.appendChild(node); });
  var parent = new ui.Bubble(parentTrigger, "More", {});
  var one = new ui.Bubble(first, "One", { parent: parent });
  var two = new ui.Bubble(second, "Two", { parent: parent });
  one.open(false);
  assert.strictEqual(parent.panel.hidden, false);
  two.open(false);
  assert.strictEqual(one.panel.hidden, true);
  assert.strictEqual(parent.deepest(), two);
  parent.close(false);
  assert.strictEqual(two.panel.hidden, true);
  ui.Bubble.closeActive();
});

test("a help button names its explanation, and a tooltip follows the pointer and Escape", function () {
  var help = ui.helpButton("Dimension format", "Applies to this editor only.");
  assert.strictEqual(help.getAttribute("aria-label"), "Dimension format: Applies to this editor only.");
  assert.strictEqual(help.getAttribute("title"), null);
  assert.strictEqual(help.getAttribute("data-tooltip"), "Applies to this editor only.");

  var root = dom.element("div");
  context.document.body.appendChild(root);
  ui.attachTooltip(root);
  var target = dom.element("button", { "data-tooltip": "Set column 1 width" });
  root.appendChild(target);
  var tip = root.children[0];
  root.listeners.mouseover({ target: target });
  assert.deepStrictEqual([tip.hidden, tip.textContent], [false, "Set column 1 width"]);
  root.listeners.keydown({ key: "Escape" });
  assert.strictEqual(tip.hidden, true);
});

test("tooltip text updates without a browser title, and icon repaint retains its accessible name", function () {
  var target = dom.element("button", { title: "Native hint" });
  ui.tooltip(target, "App hint");
  assert.strictEqual(target.getAttribute("title"), null);
  assert.strictEqual(target.getAttribute("data-tooltip"), "App hint");
  ui.tooltip(target, "");
  assert.strictEqual(target.getAttribute("data-tooltip"), null);
  ui.paintIconButton(target, "Colour by Level", "palette");
  assert.strictEqual(target.getAttribute("title"), null);
  assert.strictEqual(target.getAttribute("data-tooltip"), "Colour by Level");
  assert.strictEqual(target.getAttribute("aria-label"), "Colour by Level");
});

test("nested mounts share one tooltip, preserve descriptions, and withdraw a hidden owner's tip", function () {
  var root = dom.element("div"), mount = dom.element("div");
  context.document.body.appendChild(root);
  root.appendChild(mount);
  ui.attachTooltip(root);
  ui.attachTooltip(mount);
  ui.attachTooltip(root);
  assert.strictEqual(root.querySelectorAll("[role=tooltip]").length, 1);
  var target = dom.element("button", { "data-tooltip": "Set width", "aria-describedby": "field-error" });
  mount.appendChild(target);
  root.listeners.focusin({ target: target });
  var tip = root.querySelector("[role=tooltip]");
  assert.strictEqual(target.getAttribute("aria-describedby"), "field-error " + tip.id);
  root.listeners.mouseover({ target: target });
  assert.strictEqual(target.getAttribute("aria-describedby"), "field-error " + tip.id, "no repeated id");
  root.listeners.mouseover({ target: tip });
  assert.strictEqual(tip.hidden, false, "tooltip stays readable under the pointer");
  mount.hidden = true;
  mount._checkTooltip();
  assert.strictEqual(tip.hidden, true);
  assert.strictEqual(target.getAttribute("aria-describedby"), "field-error");
});

test("a popover is placed below its anchor, or above it when it would leave the window", function () {
  var size = { width: 200, height: 100 };
  function place(anchor) { return JSON.parse(JSON.stringify(ui.placeNear(anchor, size, 4, 8))); }
  assert.deepStrictEqual(place({ left: 50, top: 100, bottom: 130 }), { left: 50, top: 134 });
  assert.deepStrictEqual(place({ left: 1200, top: 740, bottom: 770 }), { left: 1072, top: 636 });
});

test("a header bubble lifts its sticky column until its last open submenu closes", function () {
  var header = dom.element("th"); context.document.body.appendChild(header);
  var parent = new ui.Bubble(dom.element("button"), "Type", {});
  header.appendChild(parent.root);
  var child = new ui.Bubble(dom.element("button"), "More", { parent: parent });
  parent.content.appendChild(child.root);
  assert.strictEqual(header.classList.contains("has-open-bubble"), false);
  parent.open(false);
  assert.strictEqual(header.classList.contains("has-open-bubble"), true);
  child.open(false); child.close(false);
  assert.strictEqual(header.classList.contains("has-open-bubble"), true,
    "closing a submenu keeps its still-open column menu above the checked bar");
  parent.close(false);
  assert.strictEqual(header.classList.contains("has-open-bubble"), false);
  assert.strictEqual(child.panel.hidden, true);
  header.remove();
});
