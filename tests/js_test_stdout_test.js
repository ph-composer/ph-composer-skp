"use strict";

/* tools/js_test_stdout.js: a test process that writes past the pipe's buffer and exits at once still delivers
   every byte, which is what keeps `--test-force-exit` from dropping a file's last results. Without the preload
   this child delivers 64 KiB of the 1 MiB on macOS; on Linux a pipe write is synchronous, so it passes either way. */

var assert = require("assert");
var childProcess = require("child_process");
var path = require("path");
var test = require("node:test");

var PRELOAD = path.join(__dirname, "..", "tools", "js_test_stdout.js");
var SIZE = 1024 * 1024;

test("a process that exits right after a large write to a stdout pipe loses none of it", function () {
  var result = childProcess.spawnSync(process.execPath,
    ["--require", PRELOAD, "-e", "process.stdout.write('x'.repeat(" + SIZE + ")); process.exit(0)"],
    { encoding: "utf8", maxBuffer: 4 * SIZE });

  assert.strictEqual(result.status, 0);
  assert.strictEqual(result.stdout.length, SIZE);
});
