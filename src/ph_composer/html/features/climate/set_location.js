/* Set Location: the five site fields typed in one dialog and written by one `site.update`, one Undo step,
   guarded by the five values read when it opened. Set waits for latitude, longitude and elevation, which the
   station check needs; climate zone and hours from UTC may stay unset. Read from SketchUp Geolocation fills
   latitude and longitude from what SketchUp reports and writes nothing until Set. A refusal keeps the draft;
   a stale site puts the Model's values back in the fields. The empty region at the top is where the
   outline map goes. */
PhComposerUI.define("features/climate/set_location", ["workspace", "record_form", "request", "unit_field",
  "features/climate/shared"],
function (ui, RecordForm, requests, unitField, shared) {
  "use strict";
  var UPDATE = shared.PREFIX + "site.update", GEOLOCATION = shared.PREFIX + "site.geolocation";
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
    // The outline map goes here; until it does the region takes no room.
    this.mapRegion = ui.element("div", "climate-map-region");
    this.mapRegion.hidden = true;
    this.form.appendChild(this.mapRegion);
    var place = ui.element("div", "climate-site-fields");
    this.latitude = this.textField(place, "Latitude", "°");
    this.longitude = this.textField(place, "Longitude", "°");
    this.elevation = new unitField.UnitField({ field: shared.ELEVATION, onCommit: function () { self.paint(); } });
    place.appendChild(this.labelled("Elevation", this.elevation.root));
    this.elevation.input.addEventListener("input", function () { self.paint(); });
    // The field takes Enter to read its draft; the form's own Enter then sets the location, as in the others.
    this.elevation.input.addEventListener("keydown", function (event) { if (event.key === "Enter") self.submit(); });
    this.form.appendChild(place);
    this.form.appendChild(ui.element("p", "climate-dialog-note", REQUIRED));
    var forExport = ui.element("fieldset", "climate-site-fields climate-export-fields");
    forExport.appendChild(ui.element("legend", "", "For export"));
    this.zone = ui.element("select", "phc-choice-pill");
    this.zone.setAttribute("aria-label", "Climate zone");
    this.zone.appendChild(ui.option("", "Not set"));
    shared.ZONES.forEach(function (zone) { self.zone.appendChild(ui.option(String(zone[0]), zone[1])); });
    forExport.appendChild(this.labelled("Climate zone", this.zone));
    this.hours = this.textField(forExport, "Hours from UTC", "h");
    this.form.appendChild(forExport);
    var geo = ui.element("div", "climate-geolocation");
    geo.appendChild(ui.element("p", "climate-dialog-note", GEO_NOTE));
    this.readButton = ui.button("Read from SketchUp Geolocation", function () { self.readGeolocation(); });
    geo.appendChild(this.readButton);
    this.geoStatus = ui.element("p", "climate-geolocation-status");
    this.geoStatus.setAttribute("role", "status");
    geo.appendChild(this.geoStatus);
    this.form.appendChild(geo);
    this.finish();
    this.load(site);
    document.body.appendChild(this.root);
    this.show();
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
  function text(value) { return value === null || value === undefined ? "" : String(value); }
  function number(input) {
    var value = input.value.trim().replace(/−/g, "-");
    return value === "" || !isFinite(Number(value)) ? null : Number(value);
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
  SetLocation.prototype.paint = function () {
    var busy = this.busy();
    this.submitButton.disabled = busy || !this.ready();
    [this.latitude, this.longitude, this.zone, this.hours, this.readButton].forEach(function (control) {
      control.disabled = busy;
    });
    this.elevation.setDisabled(busy);
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
    var geo = this.geolocation.consume(state), outcome;
    if (geo) this.filled(geo);
    outcome = this.settle(state);
    if (!outcome) return;
    if (outcome.status === "completed") { this.hide(); return; }
    // Another write changed the site after the dialog opened: show what the Model holds now.
    if (outcome.code === "target.changed") {
      var message = this.error.textContent;
      this.load(this.currentSite());
      this.error.textContent = message;
    }
    this.paint();
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
  };

  SetLocation.prototype.dispose = function () {
    this.withdraw();
    this.geolocation.reset();
    this.elevation.dispose();
    if (this.root.parentNode) this.root.parentNode.removeChild(this.root);
  };

  return { open: function (session, send, site, currentSite, closed) {
    return new SetLocation(session, send, site, currentSite, closed);
  } };
});
