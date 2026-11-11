/* Preloaded into every JavaScript test process (`node --require tools/js_test_stdout.js --test ...`): makes
   stdout blocking when it is a pipe, so a process that exits at once loses none of what it wrote.

   Why: `node --test` runs each file in a child that reports its results to the runner over a stdout pipe.
   Node writes to a pipe asynchronously on POSIX (Linux included), and `--test-force-exit` ends the child as
   soon as its tests finish, dropping whatever the pipe had not taken yet. The runner then counts only the
   results that arrived and exits 0: on macOS, 5 of 30 full runs lost 10 to 18 tests, the last of the largest
   file. `_handle.setBlocking` is libuv's switch behind Node's own synchronous stdout; it is internal, so a
   stdout without it is left as it is. Development only; nothing here ships. */
"use strict";

var handle = process.stdout._handle;
if (handle && typeof handle.setBlocking === "function") handle.setBlocking(true);
