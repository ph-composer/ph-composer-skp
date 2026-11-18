/* The outline map kit part with invented points: the shape a feature copies to put places on the shipped map
   (src/ph_composer/html/outline_map.js documents the options). Nothing here is climate: markers with a tone, one
   ring, a pin the user places, a selection and a hover tip that the caller writes.

   It never ships. tools/ui-preview/index.html loads it after the kit starts; it does nothing unless the page
   address carries `?example=outline_map`, and then it covers the page with the map. `&markers=N` draws N
   invented markers (default 12), which the browser evidence uses to time the map with a thousand of them.
   It is plain script, not a module: it reaches the kit through PhComposerUI.get. */
(function () {
  "use strict";
  var search = window.location.search;
  if (!/[?&]example=outline_map\b/.test(search)) return;
  var count = Number((/[?&]markers=(\d+)/.exec(search) || [])[1] || 12);
  var outlineMap = PhComposerUI.get("outline_map");

  // Invented places on a fixed grid across the United States and southern Canada, so a run is repeatable.
  var points = [];
  for (var i = 0; i < count; i += 1) {
    points.push({ id: "place-" + i, latitude_deg: 26 + (i * 7.31) % 24, longitude_deg: -123 + (i * 13.7) % 54,
      tone: i % 5 === 0 ? "warning" : "ok", label: count <= 20 ? "Place " + (i + 1) : "" });
  }
  var log = document.createElement("p");
  log.className = "example-outline-map-log";
  log.setAttribute("role", "status");

  var started = window.performance.now();
  var map = outlineMap({
    label: "Example outline map", hint: "Click a marker to select it, or anywhere else to place the pin.",
    points: points,
    rings: [{ latitude_deg: 40.7, longitude_deg: -74.0, radius_km: 80, label: "80 km" }],
    pin: null,
    selected: null,
    onSelect: function (id) {
      map.update({ selected: id });
      log.textContent = "Selected " + id;
    },
    onPlace: function (point) {
      map.update({ pin: { latitude_deg: point.latitude_deg, longitude_deg: point.longitude_deg, label: "Pin" } });
      log.textContent = "Placed at " + point.latitude_deg.toFixed(4) + ", " + point.longitude_deg.toFixed(4);
    },
    // The tip is the caller's content: text here, or a node.
    onHover: function (id) { return id ? "Invented place " + id.replace("place-", "#") : null; }
  });

  var page = document.createElement("div");
  page.className = "example-outline-map phc-workspace";
  // Over the preview's own panel, which stays loaded beneath.
  page.style.cssText = "position:fixed;inset:0;z-index:1000;padding:8px;background:var(--paper);";
  page.appendChild(map.root);
  page.appendChild(log);
  document.body.appendChild(page);
  map.root.style.height = "calc(100vh - 48px)";
  map.frame({ south: 24, west: -126, north: 52, east: -66 });
  window.exampleOutlineMap = map;
  // The first map on the page builds the border paths: the time to its first frame is the cold first paint.
  window.requestAnimationFrame(function () {
    window.exampleOutlineMapFirstPaintMs = window.performance.now() - started;
  });
})();
