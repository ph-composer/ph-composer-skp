"use strict";
/* The outline map's projection, with no browser: a point projects and inverts to itself, pan and zoom keep the
   point under the pointer, a frame fits its bounds, the zoom range holds, and a ring is drawn from the same
   points tests/map_ring_test.rb measures with the Phius limit check's own distance function. */
var assert = require("assert");
var fs = require("fs");
var path = require("path");
var test = require("node:test");
var panelSource = require("./support/panel_source");

function projection() {
  var context = {};
  context.window = context;
  return panelSource.start(context, ["map_projection"]).map_projection;
}
var map = projection();
var VIEW = map.bounded({ latitude_deg: 42.75, longitude_deg: -73.8, scale: 120, width: 560, height: 420 });
function near(actual, expected, tolerance, message) {
  assert.ok(Math.abs(actual - expected) <= (tolerance || 1e-9), message + ": " + actual + " is not " + expected);
}

test("a point projects and inverts to itself", function () {
  [[42.75, -73.8], [43.56, -72.87], [-33.9, 151.2], [64.8, -147.7]].forEach(function (point) {
    var pixel = map.project(VIEW, point[0], point[1]);
    var back = map.invert(VIEW, pixel.x, pixel.y);
    near(back.latitude_deg, point[0], 1e-9, "latitude");
    near(back.longitude_deg, point[1], 1e-9, "longitude");
  });
  var centre = map.project(VIEW, 42.75, -73.8);
  assert.deepStrictEqual([centre.x, centre.y], [280, 210]);
});

test("longitude is scaled by the cosine of the centre latitude, so a degree reads alike both ways there", function () {
  var east = map.project(VIEW, 42.75, -72.8), north = map.project(VIEW, 43.75, -73.8);
  near(east.x - 280, 120 * Math.cos(42.75 * Math.PI / 180), 1e-9, "a degree east");
  near(210 - north.y, 120, 1e-9, "a degree north");
});

test("zooming about a pixel keeps the point under it, within the zoom range", function () {
  var under = map.invert(VIEW, 100, 300);
  var zoomed = map.zoomAt(VIEW, 2, 100, 300);
  var pixel = map.project(zoomed, under.latitude_deg, under.longitude_deg);
  near(pixel.x, 100, 1e-6, "x");
  near(pixel.y, 300, 1e-6, "y");
  near(zoomed.scale, 240, 1e-9, "scale");
  assert.strictEqual(map.zoomAt(VIEW, 1e6, 100, 300).scale, 420 / map.CLOSEST_SPAN_DEG);
  assert.strictEqual(map.zoomAt(VIEW, 1e-6, 100, 300).scale, 420 / map.WIDEST_SPAN_DEG);
});

test("a pan anchors the grabbed point under the pointer as the centre latitude changes", function () {
  var grabbed = map.invert(VIEW, 400, 100);
  var panned = map.anchor(VIEW, grabbed, 150, 380, VIEW.scale);
  var pixel = map.project(panned, grabbed.latitude_deg, grabbed.longitude_deg);
  near(pixel.x, 150, 1e-6, "x");
  near(pixel.y, 380, 1e-6, "y");
  assert.notStrictEqual(panned.latitude_deg, VIEW.latitude_deg);
});

test("a frame fits its bounds inside the margin and centres them", function () {
  var bounds = { south: 40, west: -80, north: 46, east: -66 };
  var view = map.frame(bounds, 560, 420, 16);
  var corners = [map.project(view, 40, -80), map.project(view, 46, -66)];
  corners.forEach(function (pixel) {
    assert.ok(pixel.x >= 16 - 1e-6 && pixel.x <= 544 + 1e-6, "x inside: " + pixel.x);
    assert.ok(pixel.y >= 16 - 1e-6 && pixel.y <= 404 + 1e-6, "y inside: " + pixel.y);
  });
  near(view.latitude_deg, 43, 1e-9, "centre latitude");
  near(view.longitude_deg, -73, 1e-9, "centre longitude");
});

test("the SVG matrix draws (longitude, -latitude) where project puts it", function () {
  var m = map.matrix(VIEW), lat = 44.1, lon = -71.3, pixel = map.project(VIEW, lat, lon);
  near(m[0] * lon + m[2] * -lat + m[4], pixel.x, 1e-9, "x");
  near(m[1] * lon + m[3] * -lat + m[5], pixel.y, 1e-9, "y");
});

test("a ring is the shared vectors' points, which the Ruby limit check measures at three latitudes", function () {
  var vectors = JSON.parse(fs.readFileSync(path.join(__dirname, "support", "map_ring_vectors.json"), "utf8"));
  assert.strictEqual(vectors.centres.length, 3);
  vectors.centres.forEach(function (centre) {
    var points = map.ring(centre.latitude_deg, centre.longitude_deg, vectors.radius_km, vectors.steps);
    assert.strictEqual(points.length, centre.ring.length);
    points.forEach(function (point, index) {
      near(point.latitude_deg, centre.ring[index][0], 1e-8, "latitude " + index);
      near(point.longitude_deg, centre.ring[index][1], 1e-8, "longitude " + index);
    });
  });
});

test("a ring near the centre of the view reads as a circle", function () {
  var view = map.frame(map.ringBounds(42.75, -73.8, 80.4672), 560, 420, 16);
  var centre = map.project(view, 42.75, -73.8);
  var radii = map.ring(42.75, -73.8, 80.4672, 36).map(function (point) {
    var pixel = map.project(view, point.latitude_deg, point.longitude_deg);
    return Math.hypot(pixel.x - centre.x, pixel.y - centre.y);
  });
  var longest = Math.max.apply(null, radii), shortest = Math.min.apply(null, radii);
  assert.ok((longest - shortest) / longest < 0.02, "radii vary by " + (longest - shortest) + " px");
});
