/* Set Location: the five site fields typed in one dialog and written by one `site.update`, one Undo step,
   guarded by the five values read when it opened. Set waits for latitude, longitude and elevation, which the
   station check needs; climate zone and hours from UTC may stay unset. Read from SketchUp Geolocation fills
   latitude and longitude from what SketchUp reports and writes nothing until Set. A refusal keeps the draft;
   a stale site puts the Model's values back in the fields.

   The outline map beside the fields places the site: a click fills latitude and longitude, and typed values
   move the pin. With a climate whose station has coordinates, the map shows the station and the ring at
   Phius's distance limit around it, and a site that would put the station outside the Phius limits is warned
   about before Set, from the host's own limit check at the proposed site. Set still saves it. */
PhComposerUI.define("features/climate/set_location", ["workspace", "record_form", "request", "unit_field",
  "unit_numbers", "unit_preferences", "outline_map", "map_projection", "features/climate/shared"],
function (ui, RecordForm, requests, unitField, numbers, preferences, outlineMap, projection, shared) {
  "use strict";
  var UPDATE = shared.PREFIX + "site.update", GEOLOCATION = shared.PREFIX + "site.geolocation";
  var PREVIEW = shared.PREFIX + "site.preview_limit_check", CLIMATE = shared.PREFIX + "climate.get";
  // With no site and no station the map opens on the United States and southern Canada.
  var NORTH_AMERICA = { south: 24, west: -126, north: 52, east: -66 };
  var NEARBY_KM = 120; // how much ground around the site and the station the map opens on
  var PLACED_DIGITS = 4; // a click fills coordinates to 0.0001 degree, about 11 m
  var REQUIRED = "Latitude, longitude and elevation are needed. The station check compares distance and " +
    "elevation to the site.";
  var GEO_NOTE = "Read from SketchUp Geolocation fills latitude and longitude. It does not fill elevation or " +
    "hours from UTC. Nothing is written back to SketchUp.";
  var NO_GEOLOCATION = "This SketchUp model has no geolocation.";
  var FILLED = "Latitude and longitude are filled from SketchUp. Set Location saves them.";

  /* `currentSite()` answers the Model's site as last painted, for a stale refusal; `closed()` runs when it
     closes, whichever way. */
  function SetLocation(session, send, site, currentSite, closed) {
    var self = this;
    RecordForm.call(this, session, send, { title: "Set site location", action: UPDATE, label: "climate_site",
      submitLabel: "Set Location", pendingText: "Setting the location…", failureText: "The location was not set.",
      className: "climate-set-location", changed: function () { self.dispose(); closed(); } });
    this.currentSite = currentSite;
    this.geolocation = requests.channel(session, send, "climate_geolocation", "query.invoke");
    this.stationRead = requests.channel(session, send, "climate_station", "query.invoke");
    this.preview = requests.channel(session, send, "climate_preview", "query.invoke");
    this.station = null; this.previewed = null; this.check = null; this.checked = null; this.checkFailure = null;
    this.map = outlineMap({ label: "Outline map. Click to place the site",
      hint: "Click to place the site. Drag to pan.",
      onPlace: function (point) { self.place(point); } });
    var body = ui.element("div", "climate-set-location-body");
    body.appendChild(this.map.root);
    var column = ui.element("div", "climate-set-location-fields");
    body.appendChild(column);
    this.form.appendChild(body);
    var place = ui.element("div", "climate-site-fields");
    this.latitude = this.textField(place, "Latitude", "°");
    this.longitude = this.textField(place, "Longitude", "°");
    // Typed coordinates off the map's view bring the view to them; a click on the map is already in view.
    [this.latitude, this.longitude].forEach(function (input) {
      input.addEventListener("input", function () { self.showSite(); });
    });
    this.elevation = new unitField.UnitField({ field: shared.ELEVATION, onCommit: function () { self.paint(); } });
    var elevation = this.labelled("Elevation", this.elevation.root);
    elevation.classList.add("climate-field-wide");
    place.appendChild(elevation);
    this.elevation.input.addEventListener("input", function () { self.paint(); });
    // The field takes Enter to read its draft; the form's own Enter then sets the location, as in the others.
    this.elevation.input.addEventListener("keydown", function (event) { if (event.key === "Enter") self.submit(); });
    column.appendChild(place);
    column.appendChild(ui.element("p", "climate-dialog-note", REQUIRED));
    this.warning = ui.element("p", "climate-limit-warning");
    this.warning.setAttribute("role", "status");
    this.warning.hidden = true;
    column.appendChild(this.warning);
    var forExport = ui.element("fieldset", "climate-site-fields climate-export-fields");
    forExport.appendChild(ui.element("legend", "", "For export"));
    this.zone = ui.element("select", "phc-choice-pill");
    this.zone.setAttribute("aria-label", "Climate zone");
    this.zone.appendChild(ui.option("", "Not set"));
    shared.ZONES.forEach(function (zone) { self.zone.appendChild(ui.option(String(zone[0]), zone[1])); });
    forExport.appendChild(this.labelled("Climate zone", this.zone));
    this.hours = this.textField(forExport, "Hours from UTC", "h");
    column.appendChild(forExport);
    var geo = ui.element("div", "climate-geolocation");
    geo.appendChild(ui.element("p", "climate-dialog-note", GEO_NOTE));
    this.readButton = ui.button("Read from SketchUp Geolocation", function () { self.readGeolocation(); });
    geo.appendChild(this.readButton);
    this.geoStatus = ui.element("p", "climate-geolocation-status");
    this.geoStatus.setAttribute("role", "status");
    geo.appendChild(this.geoStatus);
    column.appendChild(geo);
    this.finish();
    this.load(site);
    document.body.appendChild(this.root);
    this.show();
    this.frameMap();
    this.stationRead.run(CLIMATE, {});
    this.latitude.focus();
  }
  RecordForm.extend(SetLocation);

  SetLocation.prototype.labelled = function (title, control) {
    var label = ui.element("label", "climate-field");
    label.appendChild(ui.element("span", "climate-field-label", title));
    label.appendChild(control);
    return label;
  };
  SetLocation.prototype.textField = function (parent, title, unit) {
    var self = this, input = ui.element("input"), wrap = ui.element("span", "phc-unit-field");
    input.type = "text"; input.setAttribute("inputmode", "decimal"); input.setAttribute("autocomplete", "off");
    input.setAttribute("aria-label", title);
    input.addEventListener("input", function () { self.paint(); });
    wrap.appendChild(input); wrap.appendChild(ui.element("span", "phc-unit-label", unit));
    parent.appendChild(this.labelled(title, wrap));
    return input;
  };

  /* The fields show `site`, which becomes the precondition the write is guarded by. */
  SetLocation.prototype.load = function (site) {
    var self = this;
    this.expected = {};
    shared.SITE_FIELDS.forEach(function (key) { self.expected[key] = site[key] === undefined ? null : site[key]; });
    this.latitude.value = text(site.latitude_deg);
    this.longitude.value = text(site.longitude_deg);
    this.elevation.setValue(site.elevation_m); this.elevation.cancel();
    this.zone.value = site.climate_zone === null || site.climate_zone === undefined ? "" : String(site.climate_zone);
    this.hours.value = text(site.hours_from_utc);
    this.paint();
  };
  /* Coordinates and the offset are read and shown in the panel's number format, as the unit fields are. */
  function numberFormat() { return numbers.normalizeNumberFormat(preferences.current().numberFormat); }
  function text(value) {
    return value === null || value === undefined ? "" : String(value).replace(".", numberFormat().decimal);
  }
  function number(input) {
    var value = input.value.trim().replace(/−/g, "-");
    if (value === "") return null;
    var parsed = numbers.parseRegionalNumber(value, numberFormat());
    return parsed.ok ? parsed.value : null;
  }
  SetLocation.prototype.elevationValue = function () {
    if (!this.elevation.editing) return this.elevation.baseline;
    var parsed = this.elevation.parse();
    return parsed.ok ? parsed.value : null;
  };
  /* The five values typed, or a sentence saying which one cannot be read. */
  SetLocation.prototype.values = function () {
    var hours = this.hours.value.trim().replace(/−/g, "-");
    if (hours !== "" && !/^[+-]?\d+$/.test(hours)) return "Enter hours from UTC as a whole number, such as -5.";
    return { latitude_deg: number(this.latitude), longitude_deg: number(this.longitude),
      elevation_m: this.elevationValue(), climate_zone: this.zone.value === "" ? null : Number(this.zone.value),
      hours_from_utc: hours === "" ? null : Number(hours) };
  };
  SetLocation.prototype.ready = function () {
    return number(this.latitude) !== null && number(this.longitude) !== null && this.elevationValue() !== null;
  };
  /* The site the fields hold now, latitude and longitude only, or null while either is missing or off the
     globe. */
  SetLocation.prototype.typedPoint = function () {
    var latitude = number(this.latitude), longitude = number(this.longitude);
    if (latitude === null || longitude === null || Math.abs(latitude) > 90 || Math.abs(longitude) > 180) return null;
    return { latitude_deg: latitude, longitude_deg: longitude };
  };
  /* A click on the map: the fields take the point, rounded, in the panel's number format. */
  SetLocation.prototype.place = function (point) {
    if (this.busy()) return;
    this.latitude.value = text(Number(point.latitude_deg.toFixed(PLACED_DIGITS)));
    this.longitude.value = text(Number(point.longitude_deg.toFixed(PLACED_DIGITS)));
    this.paint();
  };
  SetLocation.prototype.showSite = function () {
    var site = this.typedPoint();
    if (site) this.map.show(site.latitude_deg, site.longitude_deg);
  };
  /* The map opens on the site and the station, whichever there are, or on North America. A station read after
     the user has moved the map leaves the view where they put it. */
  SetLocation.prototype.frameMap = function () {
    if (this.map.userMoved()) return;
    var around = [this.typedPoint(), this.station].filter(Boolean).map(function (point) {
      return projection.ringBounds(point.latitude_deg, point.longitude_deg, NEARBY_KM);
    });
    this.map.frame(around.length ? around.reduce(function (all, bounds) {
      return { south: Math.min(all.south, bounds.south), west: Math.min(all.west, bounds.west),
        north: Math.max(all.north, bounds.north), east: Math.max(all.east, bounds.east) };
    }) : NORTH_AMERICA);
  };
  SetLocation.prototype.paintMap = function () {
    var site = this.typedPoint(), station = this.station, check = this.currentCheck();
    this.map.update({
      pin: site ? { latitude_deg: site.latitude_deg, longitude_deg: site.longitude_deg, label: "Site" } : null,
      points: station ? [{ id: "station", latitude_deg: station.latitude_deg, longitude_deg: station.longitude_deg,
        label: station.name, tone: check && check.verdict === "fail" ? "warning" : "ok" }] : [],
      rings: station ? [{ latitude_deg: station.latitude_deg, longitude_deg: station.longitude_deg,
        radius_km: shared.DISTANCE_LIMIT_KM, label: "50 mi from the station" }] : []
    });
  };

  /* The proposed site's three values as the limit check takes them, or null until all three read. */
  SetLocation.prototype.proposed = function () {
    var site = this.typedPoint(), elevation = this.elevationValue();
    if (!site || elevation === null) return null;
    return { latitude_deg: site.latitude_deg, longitude_deg: site.longitude_deg, elevation_m: elevation };
  };
  function key(values) { return values ? [values.latitude_deg, values.longitude_deg, values.elevation_m].join() : ""; }
  /* Asks the host for the limit check at the typed site, one request at a time: a change made while one is
     out is asked about when it answers, and an answer for values no longer typed is not shown. */
  SetLocation.prototype.askPreview = function () {
    var values = this.proposed();
    if (!this.station || !values || key(values) === this.previewed || this.preview.busy()) return;
    this.previewed = key(values);
    this.preview.run(PREVIEW, values);
  };
  /* The limit check answered for the values typed now, or null while none has been. */
  SetLocation.prototype.currentCheck = function () {
    return this.checked !== null && this.checked === key(this.proposed()) ? this.check : null;
  };
  SetLocation.prototype.paintWarning = function () {
    var check = this.currentCheck(), current = this.checked !== null && this.checked === key(this.proposed());
    var failing = Boolean(this.station && check && check.verdict === "fail");
    var unknown = Boolean(this.station && current && this.checkFailure);
    this.warning.hidden = !failing && !unknown;
    this.warning.textContent = failing ? limitWarning(check, this.station.name) :
      unknown ? "The Phius limit check could not be run for this site: " + this.checkFailure : "";
  };
  /* "At this site Northfield Regional, the attached station, is outside the Phius limits: 131 km away, over
     50 mi. The station stays attached and will read Outside Phius limits." */
  // The limits are said as Phius states them, in miles and feet, whatever the display units.
  function limitWarning(check, name) {
    var reasons = [];
    if (check.distance_ok === false) {
      reasons.push(shared.formatted(check.distance_km, shared.DISTANCE) + " away, over 50 mi");
    }
    if (check.elevation_ok === false) {
      reasons.push(shared.formatted(check.elevation_difference_m, shared.ELEVATION) + " apart in elevation, " +
        "over 400 ft");
    }
    return "At this site " + name + ", the attached station, is outside the Phius limits: " + reasons.join("; ") +
      ". The station stays attached and will read Outside Phius limits.";
  }

  SetLocation.prototype.paint = function () {
    var busy = this.busy();
    this.submitButton.disabled = busy || !this.ready();
    [this.latitude, this.longitude, this.zone, this.hours, this.readButton].forEach(function (control) {
      control.disabled = busy;
    });
    this.elevation.setDisabled(busy);
    this.paintMap();
    this.askPreview();
    this.paintWarning();
  };

  SetLocation.prototype.submit = function () {
    if (this.busy() || !this.ready()) return;
    var values = this.values();
    if (typeof values === "string") { this.error.textContent = values; return; }
    if (this.run({ values: values, expected_values: this.expected })) this.paint();
  };

  SetLocation.prototype.readGeolocation = function () {
    if (this.busy() || this.geolocation.busy()) return;
    this.geoStatus.textContent = "Reading…";
    this.geolocation.run(GEOLOCATION, {});
  };

  SetLocation.prototype.consume = function (state) {
    var geo = this.geolocation.consume(state), read = this.stationRead.consume(state);
    var check = this.preview.consume(state), outcome;
    if (geo) this.filled(geo);
    if (read) this.stationFound(read);
    if (check) {
      // One request is out at a time, so this answers the values last asked about.
      this.check = check.status === "completed" ? check.value.limit_check : null;
      this.checkFailure = check.status === "completed" ? null : check.message || "PH-Composer did not answer.";
      this.checked = this.previewed;
      this.paint();
    }
    outcome = this.settle(state);
    if (!outcome) return;
    if (outcome.status === "completed") { this.hide(); return; }
    // Another write changed the site after the dialog opened: show what the Model holds now. A write that
    // reached the host before the panel saw that change refuses as a stale revision instead.
    if (outcome.code === "target.changed" || (outcome.code === "revision.stale" && this.siteMoved())) {
      var message = this.error.textContent;
      this.load(this.currentSite());
      this.error.textContent = message;
    }
    this.paint();
  };
  SetLocation.prototype.siteMoved = function () {
    var site = this.currentSite() || {}, expected = this.expected;
    return shared.SITE_FIELDS.some(function (key) {
      return (site[key] === undefined ? null : site[key]) !== expected[key];
    });
  };
  SetLocation.prototype.filled = function (outcome) {
    var value = outcome.value || {};
    if (outcome.status !== "completed") {
      this.geoStatus.textContent = outcome.message || "SketchUp was not read.";
      return;
    }
    if (!value.geolocated) { this.geoStatus.textContent = NO_GEOLOCATION; return; }
    this.latitude.value = text(value.latitude_deg);
    this.longitude.value = text(value.longitude_deg);
    this.geoStatus.textContent = FILLED;
    this.paint();
    this.showSite();
  };

  /* The climate's station, when it has coordinates; a climate typed without them has no place on the map. */
  SetLocation.prototype.stationFound = function (outcome) {
    var values = outcome.status === "completed" && outcome.value.climate && outcome.value.climate.values;
    if (!values || values.station_latitude_deg === null || values.station_longitude_deg === null) return;
    this.station = { name: values.name, latitude_deg: values.station_latitude_deg,
      longitude_deg: values.station_longitude_deg };
    this.frameMap();
    this.paint();
  };

  SetLocation.prototype.dispose = function () {
    this.withdraw();
    this.geolocation.reset();
    this.stationRead.reset();
    this.preview.reset();
    this.map.dispose();
    this.elevation.dispose();
    if (this.root.parentNode) this.root.parentNode.removeChild(this.root);
  };

  return { open: function (session, send, site, currentSite, closed) {
    return new SetLocation(session, send, site, currentSite, closed);
  } };
});
