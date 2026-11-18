/* The outline map: world country borders and the states and provinces of the United States and Canada, shipped
   with the extension (map_borders.js), with markers, rings and one pin on top. No tile and nothing else is
   fetched. It knows points, rings and borders, and nothing about what they stand for.

   var map = outlineMap({ label, hint, points, rings, pin, selected, onSelect, onPlace, onHover });
   parent.appendChild(map.root); map.frame({ south, west, north, east });

   - points: [{ id, latitude_deg, longitude_deg, tone, label }], each drawn as a marker; `tone` is "ok", "warning"
     or omitted for neutral. `selected` is one point's id, outlined in the selection teal.
   - rings: [{ latitude_deg, longitude_deg, radius_km, label }], each the line at that great-circle distance.
   - pin: { latitude_deg, longitude_deg, label } or null: the one place being set.
   - onSelect(id) runs on a click on a marker; onPlace({ latitude_deg, longitude_deg }) on a click anywhere else
     (and on a marker when there is no onSelect). A press that moves more than DRAG_PX is a pan and places
     nothing. onHover(id) runs as the pointer enters a marker and answers the tip's content (text or a node,
     or null for none); onHover(null) runs as it leaves.
   - update({ points, rings, pin, selected }) repaints with whichever are given.
   - frame(bounds) sets the view and makes it what Reset returns to; reset() goes back to it. userMoved() says
     whether the user has panned or zoomed since; show(latitude, longitude) pans to a point outside the view.
   - dispose() ends any gesture and stops following the drawing's size.

   Drag pans and the wheel zooms about the pointer; the zoom and Reset buttons are reachable by keyboard.
   Placing and selecting have no keyboard route on the map: the caller offers one (typed fields, a list).
   The projection and the zoom range are map_projection.js's. */
PhComposerUI.define("outline_map", ["workspace", "map_projection", "map_borders"], function (ui, projection, borders) {
  "use strict";
  var DRAG_PX = 4, BUTTON_ZOOM = 2, WHEEL_RATE = 0.0015, MARKER_RADIUS = 5;
  var WORLD = { south: -58, west: -170, north: 78, east: 180 };
  var paths = null;

  /* One ring's integers from the encoded polyline algorithm: five bits a character from 63, zigzag signed. */
  function decode(text) {
    var numbers = [], value = 0, shift = 0;
    for (var i = 0; i < text.length; i += 1) {
      var bits = text.charCodeAt(i) - 63;
      value |= (bits & 31) << shift;
      shift += 5;
      if (bits < 32) {
        numbers.push(value & 1 ? ~(value >> 1) : value >> 1);
        value = 0; shift = 0;
      }
    }
    return numbers;
  }

  /* The borders as two SVG path strings in (longitude, -latitude) degrees, built once per page: they never
     change, and a view change only moves the transform they are drawn under. */
  function borderPaths() {
    if (paths) return paths;
    function layer(lines) {
      var grid = borders.grid, parts = [];
      lines.join("").split(" ").map(decode).forEach(function (ring) {
        var x = ring[0], y = ring[1], line = ["M" + x / grid + " " + -y / grid];
        for (var i = 2; i < ring.length; i += 2) {
          x += ring[i]; y += ring[i + 1];
          line.push(x / grid + " " + -y / grid);
        }
        parts.push(line.join("L") + "Z");
      });
      return parts.join("");
    }
    paths = { countries: layer(borders.countries), states: layer(borders.states) };
    return paths;
  }

  function OutlineMap(options) {
    var self = this;
    this.options = options;
    this.points = options.points || []; this.rings = options.rings || []; this.pin = options.pin || null;
    this.selected = options.selected === undefined ? null : options.selected;
    this.home = WORLD; this.framed = true; this.view = null; this.gesture = null; this.hovered = null;
    this.root = ui.element("div", "phc-outline-map");
    this.svg = ui.svg("svg", { "class": "phc-outline-map-drawing", role: "img",
      "aria-label": options.label || "Outline map" });
    var drawn = borderPaths();
    this.bordersLayer = ui.svg("g", { "class": "phc-outline-map-borders" });
    this.bordersLayer.appendChild(ui.svg("path", { "class": "phc-outline-map-countries", d: drawn.countries,
      "vector-effect": "non-scaling-stroke" }));
    this.bordersLayer.appendChild(ui.svg("path", { "class": "phc-outline-map-states", d: drawn.states,
      "vector-effect": "non-scaling-stroke" }));
    this.ringLayer = ui.svg("g", { "class": "phc-outline-map-rings" });
    this.pointLayer = ui.svg("g", { "class": "phc-outline-map-points" });
    this.pinLayer = ui.svg("g", { "class": "phc-outline-map-pin" });
    [this.bordersLayer, this.ringLayer, this.pointLayer, this.pinLayer].forEach(function (node) {
      self.svg.appendChild(node);
    });
    this.root.appendChild(this.svg);
    var controls = ui.element("div", "phc-outline-map-controls");
    this.zoomIn = ui.iconButton("Zoom in", "zoom_in", function () { self.zoomBy(BUTTON_ZOOM); });
    this.zoomOut = ui.iconButton("Zoom out", "zoom_out", function () { self.zoomBy(1 / BUTTON_ZOOM); });
    this.resetButton = ui.iconButton("Reset map view", "fit", function () { self.reset(); });
    [this.zoomIn, this.zoomOut, this.resetButton].forEach(function (node) { controls.appendChild(node); });
    this.root.appendChild(controls);
    if (options.hint) this.root.appendChild(ui.element("p", "phc-outline-map-hint", options.hint));
    this.tip = ui.element("div", "phc-outline-map-tip");
    this.tip.setAttribute("role", "tooltip");
    this.tip.hidden = true;
    this.root.appendChild(this.tip);
    this.listen();
    // The drawing has no size until it is laid out; it repaints whenever its size changes.
    if (window.ResizeObserver) {
      this.resized = new window.ResizeObserver(function () { if (self.view) self.paint(); });
      this.resized.observe(this.svg);
    }
  }

  /* The drawing's size in pixels, as laid out now. */
  OutlineMap.prototype.size = function () {
    var rect = this.svg.getBoundingClientRect();
    return { width: Math.max(1, rect.width), height: Math.max(1, rect.height), left: rect.left, top: rect.top };
  };
  OutlineMap.prototype.local = function (event) {
    var size = this.size();
    return { x: event.clientX - size.left, y: event.clientY - size.top };
  };

  OutlineMap.prototype.frame = function (bounds) {
    this.home = bounds;
    this.reset();
  };
  OutlineMap.prototype.reset = function () {
    var size = this.size();
    this.framed = true;
    this.setView(projection.frame(this.home, size.width, size.height));
  };
  OutlineMap.prototype.zoomBy = function (factor) {
    var size = this.size();
    this.framed = false;
    this.setView(projection.zoomAt(this.current(size), factor, size.width / 2, size.height / 2));
  };
  /* The view at the drawing's present size: a resize refits the frame while the user has not moved the map,
     and otherwise keeps the centre and scale (within the zoom range for the new height). */
  OutlineMap.prototype.current = function (size) {
    var view = this.view;
    if (!view || (this.framed && (view.width !== size.width || view.height !== size.height))) {
      return projection.frame(this.home, size.width, size.height);
    }
    if (view.width !== size.width || view.height !== size.height) {
      return projection.bounded({ latitude_deg: view.latitude_deg, longitude_deg: view.longitude_deg,
        scale: view.scale, width: size.width, height: size.height });
    }
    return view;
  };
  OutlineMap.prototype.setView = function (view) {
    this.view = view;
    this.paint();
  };
  /* A pan or wheel step: the view the user moved to, painted once per display frame however many pointer
     events arrive in it. */
  OutlineMap.prototype.moved = function (view) {
    var self = this;
    this.framed = false;
    this.view = view;
    if (!window.requestAnimationFrame) { this.paint(); return; }
    if (this.frameRequest) return;
    this.frameRequest = window.requestAnimationFrame(function () {
      self.frameRequest = null;
      self.paint();
    });
  };
  /* Whether the user has panned or zoomed since the last frame or Reset. */
  OutlineMap.prototype.userMoved = function () { return !this.framed; };
  /* Pans, at the same scale, to put a point in the middle when it is outside the view; otherwise nothing. */
  OutlineMap.prototype.show = function (latitude, longitude) {
    var size = this.size(), view = this.current(size), pixel = projection.project(view, latitude, longitude);
    if (pixel.x >= 0 && pixel.x <= size.width && pixel.y >= 0 && pixel.y <= size.height) return;
    this.framed = false;
    this.setView(projection.anchor(view, { latitude_deg: latitude, longitude_deg: longitude }, size.width / 2,
      size.height / 2, view.scale));
  };

  OutlineMap.prototype.update = function (changes) {
    if (changes.points !== undefined) this.points = changes.points || [];
    if (changes.rings !== undefined) this.rings = changes.rings || [];
    if (changes.pin !== undefined) this.pin = changes.pin;
    if (changes.selected !== undefined) this.selected = changes.selected;
    this.paint();
  };

  /* Borders move by their transform; markers, rings and the pin are drawn in pixels, so they keep their size
     at every zoom. */
  OutlineMap.prototype.paint = function () {
    var size = this.size(), view = this.view = this.current(size), self = this;
    this.bordersLayer.setAttribute("transform", "matrix(" + projection.matrix(view).join(" ") + ")");
    this.ringLayer.replaceChildren.apply(this.ringLayer, this.rings.map(function (ring) {
      return self.ringNode(view, ring);
    }));
    this.pointLayer.replaceChildren.apply(this.pointLayer, this.points.map(function (point) {
      return self.pointNode(view, point);
    }));
    this.pinLayer.replaceChildren.apply(this.pinLayer, this.pin ? [this.pinNode(view, this.pin)] : []);
  };
  OutlineMap.prototype.ringNode = function (view, ring) {
    var outline = projection.ring(ring.latitude_deg, ring.longitude_deg, ring.radius_km).map(function (point) {
      var pixel = projection.project(view, point.latitude_deg, point.longitude_deg);
      return round(pixel.x) + " " + round(pixel.y);
    });
    var group = ui.svg("g", { "class": "phc-outline-map-ring" });
    group.appendChild(ui.svg("path", { d: "M" + outline.join("L") + "Z" }));
    if (ring.label) {
      var centre = projection.project(view, ring.latitude_deg, ring.longitude_deg);
      var north = projection.ring(ring.latitude_deg, ring.longitude_deg, ring.radius_km, 1)[0];
      var y = projection.project(view, north.latitude_deg, north.longitude_deg).y;
      group.appendChild(ui.svg("text", { x: round(centre.x), y: round(y - 6), "text-anchor": "middle" }, ring.label));
    }
    return group;
  };
  OutlineMap.prototype.pointNode = function (view, point) {
    var pixel = projection.project(view, point.latitude_deg, point.longitude_deg);
    var group = ui.svg("g", { "class": "phc-outline-map-point", "data-point": point.id,
      transform: "translate(" + round(pixel.x) + " " + round(pixel.y) + ")" });
    if (point.tone) group.setAttribute("data-tone", point.tone);
    if (point.id === this.selected) group.setAttribute("aria-current", "true");
    group.appendChild(ui.svg("circle", { r: MARKER_RADIUS }));
    if (point.label) group.appendChild(ui.svg("text", { x: MARKER_RADIUS + 4, y: 16 }, point.label));
    return group;
  };
  OutlineMap.prototype.pinNode = function (view, pin) {
    var pixel = projection.project(view, pin.latitude_deg, pin.longitude_deg);
    var group = ui.svg("g", { "class": "phc-outline-map-site",
      transform: "translate(" + round(pixel.x) + " " + round(pixel.y) + ")" });
    group.appendChild(ui.svg("path", { d: "M0 -12L9 0L0 12L-9 0Z" }));
    if (pin.label) group.appendChild(ui.svg("text", { x: 14, y: -6 }, pin.label));
    return group;
  };
  function round(value) { return Math.round(value * 10) / 10; }

  /* The point id under an event's target, or null. */
  function pointId(target) {
    var node = target && target.closest ? target.closest("[data-point]") : null;
    return node ? node.getAttribute("data-point") : null;
  }

  OutlineMap.prototype.listen = function () {
    var self = this, svg = this.svg;
    svg.addEventListener("pointerdown", function (event) {
      if (event.button !== 0 || event.isPrimary === false || self.gesture) return;
      var at = self.local(event), view = self.current(self.size());
      var gesture = self.gesture = { pointer: event.pointerId, x: at.x, y: at.y, view: view, dragging: false,
        grabbed: projection.invert(view, at.x, at.y), point: pointId(event.target), captured: true };
      // A press whose pointer is already gone cannot be captured; it then ends when the pointer leaves.
      try { svg.setPointerCapture(event.pointerId); } catch (error) { gesture.captured = false; }
      self.hideTip();
      self.hovered = null;
    });
    svg.addEventListener("pointermove", function (event) {
      var gesture = self.gesture;
      if (!gesture) { self.hover(pointId(event.target), event); return; }
      if (event.pointerId !== gesture.pointer) return;
      var at = self.local(event);
      if (!gesture.dragging && Math.hypot(at.x - gesture.x, at.y - gesture.y) <= DRAG_PX) return;
      gesture.dragging = true;
      self.root.classList.add("is-panning");
      self.moved(projection.anchor(gesture.view, gesture.grabbed, at.x, at.y, gesture.view.scale));
    });
    svg.addEventListener("pointerup", function (event) {
      var gesture = self.gesture;
      if (!gesture || event.pointerId !== gesture.pointer || event.button !== 0) return;
      self.endGesture();
      if (!gesture.dragging) self.click(gesture);
    });
    // A cancelled or lost press ends the gesture where it is: a pan keeps the view it reached, a press places
    // nothing.
    svg.addEventListener("pointercancel", function () { self.endGesture(); });
    svg.addEventListener("lostpointercapture", function () { self.endGesture(); });
    svg.addEventListener("pointerleave", function () {
      if (!self.gesture) self.hover(null);
      else if (!self.gesture.captured) self.endGesture();
    });
    // On the whole map, so the wheel over the zoom buttons zooms too rather than scrolling the dialog.
    this.root.addEventListener("wheel", function (event) {
      event.preventDefault();
      // A drag in progress keeps its own anchor; zooming under it would be undone by the next move.
      if (self.gesture) return;
      var at = self.local(event), size = self.size();
      self.moved(projection.zoomAt(self.current(size), Math.exp(-event.deltaY * WHEEL_RATE), at.x, at.y));
    }, { passive: false });
  };

  OutlineMap.prototype.endGesture = function () {
    var gesture = this.gesture;
    if (!gesture) return;
    this.gesture = null;
    this.root.classList.remove("is-panning");
    if (this.svg.releasePointerCapture && this.svg.hasPointerCapture && this.svg.hasPointerCapture(gesture.pointer)) {
      this.svg.releasePointerCapture(gesture.pointer);
    }
  };

  OutlineMap.prototype.click = function (gesture) {
    if (gesture.point !== null && this.options.onSelect) { this.options.onSelect(gesture.point); return; }
    var place = gesture.grabbed;
    // Off the globe at a wide zoom: there is nothing there to place.
    if (!this.options.onPlace || Math.abs(place.latitude_deg) > 90 || Math.abs(place.longitude_deg) > 180) return;
    this.options.onPlace({ latitude_deg: gesture.grabbed.latitude_deg, longitude_deg: gesture.grabbed.longitude_deg });
  };

  OutlineMap.prototype.hover = function (id, event) {
    if (id === this.hovered) return;
    this.hovered = id;
    var onHover = this.options.onHover;
    if (id === null) { this.hideTip(); if (onHover) onHover(null); return; }
    var content = onHover ? onHover(id) : null;
    if (content === null || content === undefined || content === "") { this.hideTip(); return; }
    this.tip.replaceChildren(typeof content === "string" ? ui.element("span", "", content) : content);
    var at = this.local(event), size = this.size();
    this.tip.hidden = false;
    // Below and right of the pointer, or above it near the bottom, always inside the map, which clips.
    var height = this.tip.offsetHeight || 0, width = this.tip.offsetWidth || 220;
    var top = at.y + 14 + height > size.height ? at.y - 10 - height : at.y + 14;
    this.tip.style.left = Math.round(Math.max(0, Math.min(at.x + 12, size.width - width))) + "px";
    this.tip.style.top = Math.round(Math.max(0, Math.min(top, size.height - height))) + "px";
  };
  OutlineMap.prototype.hideTip = function () {
    this.tip.hidden = true;
    this.tip.replaceChildren();
  };

  OutlineMap.prototype.dispose = function () {
    if (this.frameRequest) window.cancelAnimationFrame(this.frameRequest);
    this.frameRequest = null;
    this.endGesture();
    this.hideTip();
    if (this.resized) this.resized.disconnect();
    this.options = {};
  };

  function outlineMap(options) { return new OutlineMap(options || {}); }
  outlineMap.WORLD = WORLD;
  return outlineMap;
});
