"use strict";

/* The kit's words and chip fills for honeybee's face types and boundary conditions. */

var assert = require("assert");
var fs = require("fs");
var path = require("path");
var test = require("node:test");
var dom = require("./support/dom_stub");
var panelSource = require("./support/panel_source");

function words() {
  var context = { document: dom.buildDocument("") };
  context.window = context;
  return panelSource.start(context, ["face_words"]).face_words;
}

/* The hues a Colour-by mode draws in the viewport, read from the Ruby table that declares them. */
function rubyHues(constant) {
  var source = fs.readFileSync(path.join(__dirname, "..", "src", "ph_composer", "features", "zones", "faces",
    "colour_modes.rb"), "utf8");
  var body = new RegExp(constant + " = \\{([\\s\\S]*?)\\}\\.freeze").exec(source)[1], hues = {}, match;
  var entry = /"(\w+)" => \[(\d+), (\d+), (\d+)\]/g;
  while ((match = entry.exec(body))) hues[match[1]] = [Number(match[2]), Number(match[3]), Number(match[4])];
  return hues;
}

test("a Face numbers among the Faces of its own type", function () {
  var kit = words();
  var faces = ["Floor", "Wall", "Wall", "RoofCeiling", "Wall", null, null].map(function (type) {
    return { values: type ? { face_type: type } : {} };
  });
  assert.deepStrictEqual(faces.map(function (face) { return kit.faceName(face, faces); }),
    ["Floor 1", "Wall 1", "Wall 2", "Roof or ceiling 1", "Wall 3", "Face 1", "Face 2"]);
});

test("a chip's hue is the one the viewport draws for the same value", function () {
  var kit = words();
  // Compared as JSON: the kit's objects come from the panel's own context.
  assert.deepStrictEqual(JSON.parse(JSON.stringify(kit.HUES.face_type)), rubyHues("FACE_TYPE_COLOURS"));
  assert.deepStrictEqual(JSON.parse(JSON.stringify(kit.HUES.boundary_condition)), rubyHues("BOUNDARY_COLOURS"));
});

test("a chip fill is an opaque light tint of its hue, and a value without one takes the neutral pill", function () {
  var kit = words(), chip = dom.element("select");
  assert.strictEqual(kit.fill("boundary_condition", "Outdoors"), "rgb(205, 236, 255)");
  assert.strictEqual(kit.fill("boundary_condition", ""), "");
  kit.paintFill(chip, "face_type", "Floor");
  assert.strictEqual(chip.style["--category-fill"], "rgb(222, 222, 222)");
  kit.paintFill(chip, "face_type", null);
  assert.strictEqual(chip.style["--category-fill"], undefined);
});
