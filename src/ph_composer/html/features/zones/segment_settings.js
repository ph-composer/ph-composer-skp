/* The Building Segment settings dialog (context/EXTENSIBILITY.md, "Building Segment settings"): one Segment's
   General values, then a section for each namespace another feature registered with
   `panel.segmentSettingsSection`, in their order. Each section edits a draft of its own payload; Save is one
   request, `ph_composer.zones.save_segment_settings`, and one Undo step across every section. A section is
   validated and sent once the user has changed it, so one left alone keeps its stored payload. Save stays
   disabled while a changed section reports a problem, and Cancel, the close icon and Escape write nothing. The
   dialog names no section and no other feature. */
PhComposerUI.define("features/zones/segment_settings", ["panel", "workspace", "request",
  "features/zones/zone_options"],
function (panel, ui, requests, zoneOptions) {
  "use strict";
  var PALETTE = zoneOptions.PALETTE;
  var STALE = "The Model changed. Cancel and reopen the settings to see its current values.";

  function copy(value) { return value === undefined ? undefined : JSON.parse(JSON.stringify(value)); }

  function SegmentSettings(session, send, notice) {
    var self = this;
    this.notice = notice;
    this.channel = requests.channel(session, function (type, payload) {
      send(type, Object.assign({}, payload, { expected_revision: self.revision }));
    }, "segment_settings");
  }

  SegmentSettings.prototype.active = function () { return Boolean(this.dialog); };

  /* Each snapshot: the options read, the outcome of a Save, and whether the Model moved under an open dialog. */
  SegmentSettings.prototype.consume = function (state, options) {
    this.options = options; this.currentRevision = state.revision; this.snapshot = state;
    var outcome = this.channel.consume(state);
    if (!this.dialog) return;
    if (outcome && outcome.status === "completed") {
      var name = this.general.name.trim();
      this.close();
      this.notice(name + " settings saved.", "success");
      return;
    }
    if (outcome) this.message = outcome.message || "The settings were not saved.";
    if (state.revision !== this.revision && !this.channel.busy()) this.stale = true;
    this.validate();
  };

  /* Opens the dialog on one Segment of the options read; `zones` is how many Zones it holds. */
  SegmentSettings.prototype.open = function (segment, zones) {
    if (this.dialog) return;
    var self = this, options = this.options || {};
    this.segment = segment; this.revision = this.currentRevision; this.stale = false;
    this.isDefault = options.default_segment_id === segment.id;
    this.expectedDefault = options.default_segment_id || null;
    this.general = { name: segment.values.name, colour: segment.values.colour, joins: this.isDefault };
    this.message = "";
    // A section is validated and saved once the user has changed it; one left alone is kept as stored.
    this.sections = panel.segmentSettingsSections().map(function (spec) {
      var stored = (segment.extension_data || {})[spec.namespace];
      return { spec: spec, draft: copy(stored && stored.payload) || {}, changed: false };
    });
    this.dialog = ui.formDialog("phc-segment-settings-dialog", function () { self.cancel(); });
    this.dialog.appendChild(ui.element("h2", "", "Building Segment settings"));
    // The body scrolls; one fieldset in it holds every section, so a pending Save or a stale read freezes them
    // all at once without touching what a section disables itself.
    var scroller = ui.element("div", "phc-segment-settings-body");
    var body = this.body = ui.element("fieldset", "phc-segment-settings-fields");
    scroller.appendChild(body);
    body.appendChild(this.generalSection(zones));
    this.sections.forEach(function (entry) {
      var part = ui.element("div", "phc-segment-settings-section");
      part.setAttribute("data-namespace", entry.spec.namespace);
      part.appendChild(ui.element("h3", "", entry.spec.title));
      var context = { readOnly: Boolean(entry.spec.readOnly), state: self.snapshot,
        changed: function () { entry.changed = true; self.edited(); } };
      var node = entry.spec.render(segment, entry.draft, context);
      if (node) part.appendChild(node);
      body.appendChild(part);
    });
    this.status = ui.element("div", "phc-form-status");
    this.status.setAttribute("role", "alert");
    this.cancelButton = ui.button("Cancel", function () { self.cancel(); });
    this.save = ui.button("Save", function () { self.submit(); });
    this.dialog.appendChild(scroller);
    this.dialog.appendChild(this.status);
    this.dialog.appendChild(ui.actionRow(this.cancelButton, this.save));
    // Enter in a text field follows the same path as Save.
    this.dialog.addEventListener("keydown", function (event) {
      var target = event.target;
      if (event.key === "Enter" && target && target.tagName && target.tagName.toLowerCase() === "input" &&
          target.type !== "checkbox") {
        event.preventDefault(); self.submit();
      }
    });
    document.body.appendChild(this.dialog);
    this.validate();
    this.dialog.openModal();
    this.nameInput.focus();
  };

  /* Name, colour, whether new Zones join it (checked and fixed on the default) and its Zone count. */
  SegmentSettings.prototype.generalSection = function (zones) {
    var self = this, part = ui.element("div", "phc-segment-settings-section");
    part.appendChild(ui.element("h3", "", "General"));
    var name = this.nameInput = ui.element("input");
    name.type = "text"; name.setAttribute("type", "text"); name.value = this.general.name;
    name.setAttribute("aria-label", "Name");
    name.addEventListener("input", function () { self.general.name = name.value; self.edited(); });
    part.appendChild(field("Name", name));

    var colour = ui.element("div", "phc-segment-colour"), hex = ui.element("input");
    hex.type = "text"; hex.setAttribute("type", "text"); hex.maxLength = 7; hex.value = this.general.colour;
    hex.setAttribute("aria-label", "Colour");
    var swatches = ui.element("div", "phc-segment-swatches");
    swatches.setAttribute("role", "group"); swatches.setAttribute("aria-label", "Colour palette");
    function paintSwatches() {
      Array.prototype.forEach.call(swatches.children, function (swatch) {
        swatch.setAttribute("aria-pressed", String(swatch._colour.toUpperCase() === self.general.colour.toUpperCase()));
      });
    }
    PALETTE.forEach(function (value) {
      var swatch = ui.button("", function () {
        self.general.colour = value; hex.value = value; paintSwatches(); self.edited();
      });
      swatch._colour = value;
      swatch.style.backgroundColor = value;
      swatch.setAttribute("aria-label", "Colour " + value);
      ui.tooltip(swatch, value);
      swatches.appendChild(swatch);
    });
    hex.addEventListener("input", function () { self.general.colour = hex.value; paintSwatches(); self.edited(); });
    colour.appendChild(hex); colour.appendChild(swatches);
    paintSwatches();
    part.appendChild(field("Colour", colour));

    var joins = this.joinsInput = ui.element("input");
    joins.type = "checkbox"; joins.setAttribute("type", "checkbox"); joins.checked = this.general.joins;
    joins.disabled = this.isDefault;
    joins.setAttribute("aria-label", "New Zones join this Segment");
    joins.addEventListener("change", function () { self.general.joins = joins.checked; self.edited(); });
    var joinsCell = ui.element("label", "phc-segment-joins");
    joinsCell.appendChild(joins);
    joinsCell.appendChild(ui.element("span", "", this.isDefault ? "To change it, make another Segment the default." :
      "Makes this the default Segment."));
    part.appendChild(field("New Zones join this Segment", joinsCell));
    part.appendChild(field("Zones", ui.element("span", "phc-segment-zone-count", String(zones))));
    return part;
  };

  function field(label, control) {
    var row = ui.element("div", "phc-segment-settings-row");
    row.appendChild(ui.element("span", "phc-segment-settings-label", label));
    row.appendChild(control);
    return row;
  }

  /* What keeps Save disabled: the General values, then each section's own problems, named by its title. */
  SegmentSettings.prototype.problems = function () {
    if (this.stale) return [STALE];
    var found = [], name = this.general.name.trim(), self = this, key = zoneOptions.key(name);
    if (!name) found.push("Enter a name.");
    var taken = zoneOptions.list(this.options || {}, "building_segment").filter(function (choice) {
      return choice.id !== self.segment.id && zoneOptions.key(choice.values.name) === key;
    })[0];
    if (name && taken) found.push("Another Building Segment is named " + taken.values.name + ".");
    if (!/^#[0-9a-f]{6}$/i.test(this.general.colour)) found.push("Enter the colour as #RRGGBB.");
    this.sections.forEach(function (entry) {
      if (entry.spec.readOnly || !entry.changed || !entry.spec.validate) return;
      (entry.spec.validate(entry.draft) || []).forEach(function (problem) {
        found.push(entry.spec.title + ": " + problem);
      });
    });
    return found;
  };

  /* An edit clears what the last refused Save said, then validates again. */
  SegmentSettings.prototype.edited = function () {
    this.message = "";
    this.validate();
  };

  SegmentSettings.prototype.validate = function () {
    if (!this.dialog) return;
    var busy = this.channel.busy(), problems = this.problems();
    this.status.textContent = problems.length ? problems.join(" ") : this.message;
    this.dialog.setAttribute("aria-busy", String(busy));
    this.save.disabled = busy || problems.length > 0;
    this.body.disabled = busy || this.stale;
  };

  SegmentSettings.prototype.submit = function () {
    if (this.channel.busy() || this.problems().length) { this.validate(); return; }
    var segment = this.segment, payloads = {};
    this.sections.forEach(function (entry) {
      if (!entry.spec.readOnly && entry.changed) payloads[entry.spec.namespace] = entry.spec.collect(entry.draft);
    });
    this.message = "";
    this.channel.run("ph_composer.zones.save_segment_settings", {
      id: segment.id, values: { name: this.general.name.trim(), colour: this.general.colour.toUpperCase() },
      expected_values: { name: segment.values.name, colour: segment.values.colour },
      default: this.isDefault || this.general.joins, expected_default_segment_id: this.expectedDefault,
      extension_payloads: payloads, expected_extension_data: copy(segment.extension_data || {})
    });
    this.validate();
  };

  /* Cancel, the close icon and Escape: nothing is sent. A Save already sent finishes first. */
  SegmentSettings.prototype.cancel = function () {
    if (this.channel.busy()) { this.message = "Wait for the settings to finish saving."; this.validate(); return; }
    this.close();
  };

  SegmentSettings.prototype.close = function () {
    if (!this.dialog) return;
    this.dialog.closeModal(); this.dialog.remove(); this.dialog = null;
  };

  SegmentSettings.prototype.dispose = function () { this.channel.reset(); this.close(); };

  return SegmentSettings;
});
