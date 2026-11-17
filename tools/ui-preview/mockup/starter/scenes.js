"use strict";
/* exported SCENES */
/* Starter mockup scenes. `make ui-gallery MOCKUP=<dir>/mockup.html` shoots each PNG beside the page and
   rewrites README.md's scene table. Fields: png, journey, do (steps in app.js), size ("420x732"; default
   1280x800), hover and select (Playwright selectors acted on after the replay), note. */
var SCENES = [
  { group: "1. Three Zones", try: "Check a Zone",
    shots: [{ png: "start", journey: 1 }, { png: "checked", journey: 1, do: "check" }] },
  { group: "2. One flagged", try: "Hover the flag on the Attic",
    shots: [{ png: "flagged", journey: 2, hover: ".zp-flag" }] }
];
