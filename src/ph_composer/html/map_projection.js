/* The outline map's projection: pure functions, no DOM, so they are tested without a browser.

   Equirectangular, with longitude scaled by the cosine of the view's centre latitude, so that near the
   centre a degree of longitude and a degree of latitude cover the same ground and a ring of equal distance
   reads as a circle. A view is { latitude_deg, longitude_deg } at its centre, `scale` in pixels per degree of
   latitude, and the `width` and `height` it is drawn at in pixels. y grows downward, as on screen.

   The zoom range is held by the latitude span the view shows top to bottom: from 170 degrees, the whole
   world, to half a degree, about 55 km, close enough to read a county line near a site. The centre stays
   within 80 degrees of the equator, where the cosine still leaves longitude readable.

   A ring is the set of points at one great-circle distance from a centre on the same sphere the Phius limit
   check measures with (mean radius 6371.0088 km), so its outline is the limit drawn exactly, whatever the
   projection does to it. */
PhComposerUI.define("map_projection", [], function () {
  "use strict";
  var EARTH_RADIUS_KM = 6371.0088;
  var WIDEST_SPAN_DEG = 170, CLOSEST_SPAN_DEG = 0.5, CENTRE_LIMIT_DEG = 80;
  var RADIANS = Math.PI / 180;

  function clamp(value, low, high) { return Math.min(high, Math.max(low, value)); }
  function cosine(view) { return Math.cos(view.latitude_deg * RADIANS); }

  /* The view as given, with its scale held to the zoom range for its height and its centre to the limits. */
  function bounded(view) {
    var height = Math.max(1, view.height);
    return { latitude_deg: clamp(view.latitude_deg, -CENTRE_LIMIT_DEG, CENTRE_LIMIT_DEG),
      longitude_deg: clamp(view.longitude_deg, -180, 180),
      scale: clamp(view.scale, height / WIDEST_SPAN_DEG, height / CLOSEST_SPAN_DEG),
      width: view.width, height: view.height };
  }

  /* A point's place in the view, in pixels. */
  function project(view, latitude, longitude) {
    return { x: view.width / 2 + (longitude - view.longitude_deg) * cosine(view) * view.scale,
      y: view.height / 2 - (latitude - view.latitude_deg) * view.scale };
  }

  /* The point under a pixel: the inverse of `project`. */
  function invert(view, x, y) {
    return { latitude_deg: view.latitude_deg - (y - view.height / 2) / view.scale,
      longitude_deg: view.longitude_deg + (x - view.width / 2) / (cosine(view) * view.scale) };
  }

  /* The view at `scale` that puts `point` under the pixel (x, y). The centre latitude is solved first,
     because the cosine that scales longitude is taken there. Pan and zoom both use it, so the point a
     drag grabbed, or the one under the wheel, stays under the pointer. */
  function anchor(view, point, x, y, scale) {
    var next = bounded({ latitude_deg: point.latitude_deg + (y - view.height / 2) / scale,
      longitude_deg: 0, scale: scale, width: view.width, height: view.height });
    next.longitude_deg = clamp(point.longitude_deg - (x - view.width / 2) / (cosine(next) * next.scale), -180, 180);
    return next;
  }

  /* The view zoomed by `factor` about the pixel (x, y), within the zoom range. */
  function zoomAt(view, factor, x, y) {
    var target = bounded({ latitude_deg: view.latitude_deg, longitude_deg: view.longitude_deg,
      scale: view.scale * factor, width: view.width, height: view.height });
    return anchor(view, invert(view, x, y), x, y, target.scale);
  }

  /* The view that fits `bounds` ({ south, west, north, east } in degrees) into width by height pixels with
     `margin` pixels clear on every side. */
  function frame(bounds, width, height, margin) {
    var pad = margin === undefined ? 16 : margin;
    var centre = { latitude_deg: (bounds.south + bounds.north) / 2, longitude_deg: (bounds.west + bounds.east) / 2 };
    var k = Math.cos(clamp(centre.latitude_deg, -CENTRE_LIMIT_DEG, CENTRE_LIMIT_DEG) * RADIANS);
    var across = Math.max(1, width - 2 * pad) / Math.max(1e-9, (bounds.east - bounds.west) * k);
    var down = Math.max(1, height - 2 * pad) / Math.max(1e-9, bounds.north - bounds.south);
    return bounded({ latitude_deg: centre.latitude_deg, longitude_deg: centre.longitude_deg,
      scale: Math.min(across, down), width: width, height: height });
  }

  /* The bounds a ring of `radiusKm` around a point covers, for framing it. */
  function ringBounds(latitude, longitude, radiusKm) {
    var dLat = radiusKm / EARTH_RADIUS_KM / RADIANS;
    var dLon = dLat / Math.max(0.05, Math.cos(latitude * RADIANS));
    return { south: latitude - dLat, north: latitude + dLat, west: longitude - dLon, east: longitude + dLon };
  }

  /* `steps` points at `radiusKm` along the great circle from the centre, from north clockwise. */
  function ring(latitude, longitude, radiusKm, steps) {
    var count = steps || 72, angular = radiusKm / EARTH_RADIUS_KM, points = [];
    var phi = latitude * RADIANS, lambda = longitude * RADIANS;
    for (var i = 0; i < count; i += 1) {
      var bearing = 2 * Math.PI * i / count;
      var phi2 = Math.asin(Math.sin(phi) * Math.cos(angular) + Math.cos(phi) * Math.sin(angular) * Math.cos(bearing));
      var lambda2 = lambda + Math.atan2(Math.sin(bearing) * Math.sin(angular) * Math.cos(phi),
        Math.cos(angular) - Math.sin(phi) * Math.sin(phi2));
      points.push({ latitude_deg: phi2 / RADIANS, longitude_deg: lambda2 / RADIANS });
    }
    return points;
  }

  /* The SVG matrix that draws (longitude, -latitude) in degrees at this view: x and y are affine in the two,
     so the borders are built once and a pan or zoom changes only this transform. */
  function matrix(view) {
    var across = cosine(view) * view.scale;
    return [across, 0, 0, view.scale, view.width / 2 - view.longitude_deg * across,
      view.height / 2 + view.latitude_deg * view.scale];
  }

  return { EARTH_RADIUS_KM: EARTH_RADIUS_KM, WIDEST_SPAN_DEG: WIDEST_SPAN_DEG, CLOSEST_SPAN_DEG: CLOSEST_SPAN_DEG,
    bounded: bounded, project: project, invert: invert, anchor: anchor, zoomAt: zoomAt, frame: frame,
    ring: ring, ringBounds: ringBounds, matrix: matrix };
});
