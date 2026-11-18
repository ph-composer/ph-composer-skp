"use strict";
/* The outline map kit part with invented points: it draws the shipped borders, markers, rings and the pin; a click
   selects a marker or places a point; a drag pans and places nothing; the wheel and the buttons zoom; Reset
   returns to the frame; a cancelled or lost press ends the gesture; hover asks the caller for the tip. The
   projection's arithmetic is tests/map_projection_test.js's. */
var assert = require("assert");
var test = require("node:test");
var dom = require("./support/dom_stub");
var panelSource = require("./support/panel_source");

var RECT = { left: 100, top: 50, right: 660, bottom: 470, width: 560, height: 420, x: 100, y: 50 };
var POINTS = [
  { id: "alpha", latitude_deg: 42.75, longitude_deg: -73.8, tone: "ok", label: "Alpha" },
  { id: "beta", latitude_deg: 43.5, longitude_deg: -72.5, tone: "warning", label: "Beta" }
];

function setup(options) {
  var context = { document: dom.buildDocument("<html><body></body></html>"), setTimeout: setTimeout,
    clearTimeout: clearTimeout };
  context.window = context;
  dom.attachEvents(context);
  var modules = panelSource.start(context, ["outline_map", "map_projection", "map_borders"]);
  var calls = { select: [], place: [], hover: [] };
  var map = modules.outline_map(Object.assign({
    label: "Outline map", hint: "Click to place.", points: POINTS,
    rings: [{ latitude_deg: 42.75, longitude_deg: -73.8, radius_km: 80.4672, label: "50 mi" }],
    pin: { latitude_deg: 43, longitude_deg: -73, label: "Site" },
    selected: "alpha",
    onSelect: function (id) { calls.select.push(id); },
    onPlace: function (point) { calls.place.push(point); },
    onHover: function (id) { calls.hover.push(id); return id ? "About " + id : null; }
  }, options || {}));
  map.svg.rect = RECT;
  context.document.body.appendChild(map.root);
  map.frame({ south: 41, west: -76, north: 45, east: -71 });
  return { map: map, calls: calls, projection: modules.map_projection, borders: modules.map_borders,
    document: context.document };
}
function event(type, x, y, extra) {
  return Object.assign({ type: type, clientX: x, clientY: y, button: 0, isPrimary: true, pointerId: 1, buttons: 1,
    preventDefault: function () { this.defaultPrevented = true; } }, extra || {});
}
function fire(node, name, payload) { node.listeners[name](payload); }
function pixelOf(t, latitude, longitude) {
  var at = t.projection.project(t.map.view, latitude, longitude);
  return { x: at.x + RECT.left, y: at.y + RECT.top };
}
function marker(t, id) { return t.map.root.querySelector("[data-point='" + id + "']"); }
function press(t, target, from, to) {
  fire(t.map.svg, "pointerdown", event("pointerdown", from.x, from.y, { target: target }));
  if (to) fire(t.map.svg, "pointermove", event("pointermove", to.x, to.y, { target: target }));
  var end = to || from;
  fire(t.map.svg, "pointerup", event("pointerup", end.x, end.y, { target: target }));
}

test("it draws the shipped borders, each marker with its tone, the ring, the pin and the three controls", function () {
  var t = setup();
  var countries = t.map.root.querySelector(".phc-outline-map-countries");
  var states = t.map.root.querySelector(".phc-outline-map-states");
  assert.ok(countries.getAttribute("d").split("M").length > 100, "the shipped countries");
  assert.ok(states.getAttribute("d").split("M").length > 60, "the shipped states and provinces");
  assert.match(countries.getAttribute("d"), /^M-?\d/);
  assert.match(states.getAttribute("d"), /Z$/);
  assert.match(t.map.root.querySelector(".phc-outline-map-borders").getAttribute("transform"), /^matrix\(/);
  assert.strictEqual(marker(t, "alpha").getAttribute("data-tone"), "ok");
  assert.strictEqual(marker(t, "beta").getAttribute("data-tone"), "warning");
  assert.strictEqual(marker(t, "alpha").getAttribute("aria-current"), "true");
  assert.strictEqual(marker(t, "beta").getAttribute("aria-current"), null);
  assert.strictEqual(t.map.root.querySelectorAll(".phc-outline-map-ring").length, 1);
  assert.match(t.map.root.querySelector(".phc-outline-map-ring").children[0].getAttribute("d"), /^M[\d.-]+ [\d.-]+L/);
  assert.strictEqual(t.map.root.querySelector(".phc-outline-map-site").children[1].textContent, "Site");
  var names = t.map.root.querySelector(".phc-outline-map-controls").children.map(function (node) {
    return node.getAttribute("aria-label");
  });
  assert.deepStrictEqual(names, ["Zoom in", "Zoom out", "Reset map view"]);
  assert.strictEqual(t.map.svg.getAttribute("aria-label"), "Outline map");
});

test("a click on a marker selects it and a click elsewhere places the point under it", function () {
  var t = setup();
  var beta = pixelOf(t, 43.5, -72.5);
  press(t, marker(t, "beta").children[0], beta);
  assert.deepStrictEqual(t.calls.select, ["beta"]);
  assert.strictEqual(t.calls.place.length, 0);
  var empty = { x: RECT.left + 40, y: RECT.top + 380 };
  var expected = t.projection.invert(t.map.view, 40, 380);
  press(t, t.map.svg, empty);
  assert.strictEqual(t.calls.place.length, 1);
  assert.ok(Math.abs(t.calls.place[0].latitude_deg - expected.latitude_deg) < 1e-9);
  assert.ok(Math.abs(t.calls.place[0].longitude_deg - expected.longitude_deg) < 1e-9);
});

test("without onSelect a click on a marker places, and update repaints what it is given", function () {
  var t = setup({ onSelect: null });
  press(t, marker(t, "alpha").children[0], pixelOf(t, 42.75, -73.8));
  assert.strictEqual(t.calls.place.length, 1);
  t.map.update({ selected: "beta", pin: null, rings: [] });
  assert.strictEqual(marker(t, "beta").getAttribute("aria-current"), "true");
  assert.strictEqual(t.map.root.querySelectorAll(".phc-outline-map-site").length, 0);
  assert.strictEqual(t.map.root.querySelectorAll(".phc-outline-map-ring").length, 0);
  assert.strictEqual(t.map.root.querySelectorAll(".phc-outline-map-point").length, 2);
});

test("a drag pans with the grabbed point under the pointer and places nothing", function () {
  var t = setup();
  var pin = pixelOf(t, 43, -73);
  press(t, t.map.svg, pin, { x: pin.x + 120, y: pin.y - 70 });
  assert.strictEqual(t.calls.place.length, 0);
  var after = pixelOf(t, 43, -73);
  assert.ok(Math.abs(after.x - (pin.x + 120)) < 1e-6 && Math.abs(after.y - (pin.y - 70)) < 1e-6);
  assert.strictEqual(t.map.root.classList.contains("is-panning"), false);
});

test("a press that moves no more than four pixels is still a click", function () {
  var t = setup();
  press(t, t.map.svg, { x: 300, y: 200 }, { x: 303, y: 202 });
  assert.strictEqual(t.calls.place.length, 1);
});

test("the wheel zooms about the pointer, keeping the pin under it, and never scrolls the page", function () {
  var t = setup();
  var pin = pixelOf(t, 43, -73), scale = t.map.view.scale;
  var wheel = event("wheel", pin.x, pin.y, { deltaY: -200 });
  fire(t.map.root, "wheel", wheel);
  assert.ok(wheel.defaultPrevented);
  assert.ok(t.map.view.scale > scale);
  var after = pixelOf(t, 43, -73);
  assert.ok(Math.abs(after.x - pin.x) < 1e-6 && Math.abs(after.y - pin.y) < 1e-6);
});

test("the zoom buttons double and halve the scale, and Reset returns to the frame", function () {
  var t = setup();
  var framed = t.map.view.scale;
  t.map.zoomIn.listeners.click({ preventDefault: function () {} });
  assert.ok(Math.abs(t.map.view.scale - framed * 2) < 1e-9);
  t.map.zoomOut.listeners.click({ preventDefault: function () {} });
  t.map.zoomOut.listeners.click({ preventDefault: function () {} });
  assert.ok(Math.abs(t.map.view.scale - framed / 2) < 1e-9);
  press(t, t.map.svg, { x: 300, y: 200 }, { x: 420, y: 260 });
  t.map.resetButton.listeners.click({ preventDefault: function () {} });
  assert.ok(Math.abs(t.map.view.scale - framed) < 1e-9);
  assert.ok(Math.abs(t.map.view.latitude_deg - 43) < 1e-9 && Math.abs(t.map.view.longitude_deg + 73.5) < 1e-9);
});

test("a cancelled press, a lost capture or another button ends without a place or a select", function () {
  var t = setup();
  fire(t.map.svg, "pointerdown", event("pointerdown", 300, 200, { target: t.map.svg }));
  fire(t.map.svg, "pointercancel", event("pointercancel", 300, 200));
  fire(t.map.svg, "pointerup", event("pointerup", 300, 200, { target: t.map.svg }));
  fire(t.map.svg, "pointerdown", event("pointerdown", 300, 200, { target: t.map.svg }));
  fire(t.map.svg, "lostpointercapture", event("lostpointercapture", 300, 200));
  fire(t.map.svg, "pointerup", event("pointerup", 300, 200, { target: t.map.svg }));
  press(t, t.map.svg, { x: 300, y: 200 });
  assert.strictEqual(t.calls.place.length, 1, "only the plain press placed");
  fire(t.map.svg, "pointerdown", event("pointerdown", 300, 200, { target: t.map.svg, button: 2 }));
  fire(t.map.svg, "pointerup", event("pointerup", 300, 200, { target: t.map.svg, button: 2 }));
  assert.strictEqual(t.calls.place.length, 1, "a right button places nothing");
  fire(t.map.svg, "pointerdown", event("pointerdown", 300, 200, { target: t.map.svg }));
  fire(t.map.svg, "pointerup", event("pointerup", 300, 200, { target: t.map.svg, button: 2 }));
  assert.strictEqual(t.calls.place.length, 1, "another button's release does not end a left press");
  t.map.dispose();
  fire(t.map.svg, "pointerup", event("pointerup", 300, 200, { target: t.map.svg }));
  assert.strictEqual(t.calls.place.length, 1, "a press open at dispose places nothing");
});

test("hover asks the caller for the tip by marker id, and leaving hides it", function () {
  var t = setup();
  var alpha = marker(t, "alpha").children[0];
  fire(t.map.svg, "pointermove", event("pointermove", 300, 200, { target: alpha, buttons: 0 }));
  assert.deepStrictEqual(t.calls.hover, ["alpha"]);
  assert.strictEqual(t.map.tip.hidden, false);
  assert.strictEqual(t.map.tip.textContent || t.map.tip.children[0].textContent, "About alpha");
  fire(t.map.svg, "pointermove", event("pointermove", 310, 210, { target: t.map.svg, buttons: 0 }));
  assert.deepStrictEqual(t.calls.hover, ["alpha", null]);
  assert.strictEqual(t.map.tip.hidden, true);
});

test("the borders decode from the generator's encoded polyline, in (longitude, -latitude) degrees", function () {
  var context = { document: dom.buildDocument("<html><body></body></html>") };
  context.window = context;
  dom.attachEvents(context);
  // Rings encoded by tools/map_data/map_borders.py, one split across two lines as a long layer is.
  var modules = panelSource.start(context, ["outline_map"], { map_borders: { grid: 100,
    countries: ["gEoKwQ~W", "bBwB"], states: ["n}@f^SS?f@"] } });
  var map = modules.outline_map({});
  assert.strictEqual(map.root.querySelector(".phc-outline-map-countries").getAttribute("d"), "M1 -2L4 2L3.5 1.4Z");
  assert.strictEqual(map.root.querySelector(".phc-outline-map-states").getAttribute("d"), "M-10 5L-9.9 4.9L-9.9 5.1Z");
});

test("a press on a marker hides its tip, and the next move over it shows the tip again", function () {
  var t = setup();
  var alpha = marker(t, "alpha").children[0];
  fire(t.map.svg, "pointermove", event("pointermove", 300, 200, { target: alpha, buttons: 0 }));
  press(t, alpha, { x: 300, y: 200 });
  assert.strictEqual(t.map.tip.hidden, true);
  fire(t.map.svg, "pointermove", event("pointermove", 301, 200, { target: alpha, buttons: 0 }));
  assert.strictEqual(t.map.tip.hidden, false);
  assert.deepStrictEqual(t.calls.hover, ["alpha", "alpha"]);
});

test("show pans to a point outside the view at the same scale, and userMoved follows pans and Reset", function () {
  var t = setup();
  assert.strictEqual(t.map.userMoved(), false);
  var before = t.map.view;
  t.map.show(43, -73);
  assert.strictEqual(t.map.view, before, "a point in view moves nothing");
  t.map.show(21.3, -157.8);
  var pixel = t.projection.project(t.map.view, 21.3, -157.8);
  assert.ok(Math.abs(pixel.x - 280) < 1e-6 && Math.abs(pixel.y - 210) < 1e-6, "centred");
  assert.strictEqual(t.map.view.scale, before.scale);
  assert.strictEqual(t.map.userMoved(), true);
  t.map.reset();
  assert.strictEqual(t.map.userMoved(), false);
});

test("a resize after the user moved the map keeps its centre and scale at the new size", function () {
  var t = setup();
  t.map.zoomIn.listeners.click({ preventDefault: function () {} });
  assert.strictEqual(t.map.userMoved(), true, "button zoom is the user's move");
  var before = t.map.view;
  t.map.svg.rect = { left: 100, top: 50, right: 380, bottom: 270, width: 280, height: 220, x: 100, y: 50 };
  t.map.update({});
  assert.deepStrictEqual([t.map.view.width, t.map.view.height], [280, 220]);
  assert.strictEqual(t.map.view.scale, before.scale);
  assert.strictEqual(t.map.view.latitude_deg, before.latitude_deg);
  var centre = t.projection.project(t.map.view, before.latitude_deg, before.longitude_deg);
  assert.deepStrictEqual([centre.x, centre.y], [140, 110]);
});

test("a click off the globe places nothing, and the wheel during a drag is ignored", function () {
  var t = setup();
  t.map.frame({ south: -10, west: -179, north: 10, east: -171 });
  for (var i = 0; i < 6; i += 1) t.map.zoomOut.listeners.click({ preventDefault: function () {} });
  press(t, t.map.svg, { x: RECT.left + 2, y: RECT.top + 2 });
  assert.strictEqual(t.calls.place.length, 0);
  t.map.reset();
  fire(t.map.svg, "pointerdown", event("pointerdown", 300, 200, { target: t.map.svg }));
  fire(t.map.svg, "pointermove", event("pointermove", 340, 220, { target: t.map.svg }));
  var scale = t.map.view.scale;
  var wheel = event("wheel", 340, 220, { deltaY: -400 });
  fire(t.map.root, "wheel", wheel);
  assert.ok(wheel.defaultPrevented, "the dialog does not scroll either");
  assert.strictEqual(t.map.view.scale, scale);
});
