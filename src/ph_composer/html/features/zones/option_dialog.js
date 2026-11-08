/* One collection draft, one public proposal, one Save. Adoption uses this same modal ownership:
   opening/cancelling never writes, source mappings remain explicit, and refusals retain the draft. */
PhComposerUI.define("features/zones/option_dialog", ["workspace", "request", "features/zones/zone_options"],
function (ui, requests, options) {
  "use strict";
  var serial = 0, PALETTE = options.PALETTE;
  function copy(value) { return JSON.parse(JSON.stringify(value)); }
  function choiceView(choice) { return { id: choice.id, name: choice.values.name, colour: choice.values.colour }; }
  function usage(choice) {
    var used = choice.usage || {}, live = used.live || 0, recoverable = used.recoverable || 0;
    return live + (live === 1 ? " live Zone" : " live Zones") + " · " + recoverable + " recoverable";
  }
  function validChoices(choices) {
    var seen = Object.create(null);
    for (var i = 0; i < choices.length; i++) {
      var choice = choices[i], key = options.key(choice.name);
      if (!key) return "Enter a name for every option.";
      if (seen[key]) return "Equivalent names: " + seen[key] + " and " + choice.name + ". Rename or merge them.";
      if (!/^#[0-9a-f]{6}$/i.test(choice.colour)) return "Enter " + choice.name + " colour as #RRGGBB.";
      seen[key] = choice.name;
    }
    return "";
  }
  function OptionDialog(session, send, guard, notice, onSaved) {
    var self = this;
    this.guard = guard; this.notice = notice; this.onSaved = onSaved;
    this.channel = requests.channel(session, function (type, payload) {
      send(type, Object.assign({}, payload, { expected_revision: self.revision }));
    }, "zone_options");
  }
  OptionDialog.prototype.active = function () { return Boolean(this.dialog); };
  OptionDialog.prototype.consume = function (state, data) {
    this.current = data; this.currentRevision = state.revision;
    var outcome = this.channel.consume(state);
    if (!this.dialog) return;
    if (outcome && outcome.status === "completed") {
      if (this.onSaved) this.onSaved(this.collection, outcome.value || {});
      this.close();
      this.notice(this.adopting ? "Managed options adopted." : options.title(this.collection) + " saved.", "success");
      return;
    }
    if (outcome) this.error.textContent = outcome.message || "The options were not saved.";
    if (state.revision !== this.revision && !this.channel.busy()) {
      this.stale = true; this.error.textContent = "The Model changed. Cancel and reopen to review its current options.";
    }
    this.pending();
  };
  OptionDialog.prototype.open = function (collection) {
    var reason = this.guard && this.guard();
    if (reason) return this.notice(reason, "warning");
    if (this.active()) return;
    this.collection = collection; this.revision = this.currentRevision; this.stale = false;
    this.adopting = Boolean(this.current.adoption && this.current.adoption.required);
    this.expected = options.list(this.current, collection).map(choiceView);
    this.draft = copy(this.expected); this.replacements = {};
    this.defaultId = this.current.default_segment_id || null;
    this.expectedDefault = this.defaultId;
    this.sources = copy((this.current.adoption || {}).sources || []);
    this.mappings = this.sources.map(function (source) {
      return { source: source.key, target: "new", name: source.name, colour: source.colour || PALETTE[0] };
    });
    this.build();
  };
  OptionDialog.prototype.build = function () {
    var self = this;
    this.dialog = ui.formDialog("phc-zone-options-dialog", function () { self.cancel(); });
    this.dialog.appendChild(ui.element("h2", "",
      this.adopting ? "Adopt managed Zone options" : "Manage " + options.title(this.collection)));
    this.list = ui.element("div", "phc-zone-option-list");
    this.error = ui.element("div", "phc-form-status"); this.error.setAttribute("role", "alert");
    if (this.adopting) this.dialog.appendChild(ui.element("p", "phc-zone-option-help",
      "Review every stored category and its live and recoverable uses. " +
      "Equivalent names require an explicit merge or a distinct name. Adoption is one Undo step."));
    this.dialog.appendChild(this.list);
    if (!this.adopting) {
      this.add = ui.button("Add", function () {
        var base = self.collection === "level" ? "Level" : self.draft.length ? "Building Segment" :
          (self.current.adoption || {}).suggested_segment || "Building Segment";
        var name = base, suffix = 1;
        while (self.draft.some(function (choice) { return options.key(choice.name) === options.key(name);
          })) name = base + " " + (++suffix);
        var choice = { id: "new:" + (++serial), name: name, colour: PALETTE[0] };
        self.draft.push(choice);
        if (self.collection === "building_segment" && !self.defaultId) self.defaultId = choice.id;
        self.fill();
        var names = self.list.querySelectorAll("[data-option-name]"); names[names.length - 1].focus();
      });
      this.dialog.appendChild(this.add);
      if (this.collection === "building_segment") {
        var row = ui.element("label", "phc-zone-option-default", "Default Building Segment");
        this.defaultSelect = ui.element("select"); this.defaultSelect.setAttribute("aria-label",
          "Default Building Segment");
        this.defaultSelect.addEventListener("change", function () {
          self.defaultId = self.defaultSelect.value || null; self.validate(); });
        row.appendChild(this.defaultSelect); this.dialog.appendChild(row);
      }
    }
    this.dialog.appendChild(this.error);
    this.cancelButton = ui.button("Cancel", function () { self.cancel(); });
    this.save = ui.button(this.adopting ? "Adopt" : "Save", function () { self.submit(); });
    this.save.className = "primary";
    this.dialog.appendChild(ui.actionRow(this.cancelButton, this.save));
    // Enter follows the same submission path; native select and colour controls keep their own keys.
    this.dialog.addEventListener("keydown", function (event) {
      if (event.key === "Enter" && event.target && event.target.tagName.toLowerCase() === "input" &&
          event.target.type !== "color") {
        event.preventDefault(); self.submit();
      }
    });
    document.body.appendChild(this.dialog); this.fill(); this.dialog.openModal();
  };
  OptionDialog.prototype.colourEditor = function (choice, label) {
    var self = this, root = ui.element("div", "phc-zone-option-colour"), picker = ui.element("input"),
      hex = ui.element("input");
    picker.type = "color"; picker.setAttribute("type", "color"); picker.value = choice.colour;
    picker.setAttribute("aria-label", label + " colour");
    hex.type = "text"; hex.setAttribute("type", "text"); hex.value = choice.colour; hex.maxLength = 7;
    hex.setAttribute("aria-label", label + " hex colour");
    function set(value) {
      if (self.channel.busy() || self.stale) return;
      choice.colour = value; hex.value = value;
      if (/^#[0-9a-f]{6}$/i.test(value)) picker.value = value;
      self.validate();
    }
    picker.addEventListener("input", function () { set(picker.value); });
    hex.addEventListener("input", function () { set(hex.value); });
    root.appendChild(picker); root.appendChild(hex);
    var palette = ui.element("div", "phc-zone-option-palette"); palette.setAttribute("role", "group");
    palette.setAttribute("aria-label", label + " colour palette");
    PALETTE.forEach(function (colour) {
      var swatch = ui.button("", function () { set(colour); });
      swatch.style.backgroundColor = colour; swatch.setAttribute("aria-label", label + " colour " + colour);
      ui.tooltip(swatch, colour); palette.appendChild(swatch);
    });
    root.appendChild(palette); return root;
  };
  OptionDialog.prototype.fill = function () {
    var self = this; this.list.replaceChildren();
    if (this.adopting) this.fillAdoption();
    else {
      this.draft.forEach(function (choice) {
        var row = ui.element("div", "phc-zone-option-row"), name = ui.element("input");
        name.type = "text"; name.setAttribute("type", "text"); name.value = choice.name;
        name.setAttribute("aria-label", choice.name + " name"); name.setAttribute("data-option-name", choice.id);
        name.addEventListener("input", function () { choice.name = name.value; self.fillDefault(); self.validate(); });
        row.appendChild(name); row.appendChild(self.colourEditor(choice, choice.name));
        var stored = options.find(self.current, self.collection, choice.id);
        row.appendChild(ui.element("span", "phc-zone-option-usage", stored ? usage(stored) : "Unused"));
        row.appendChild(ui.button("Merge / Delete", function () { self.removal(choice, row); }));
        self.list.appendChild(row);
      });
      if (!this.draft.length) this.list.appendChild(ui.element("p", "phc-empty",
        "No " + options.title(this.collection) + " defined."));
      this.fillDefault();
    }
    this.validate();
  };
  OptionDialog.prototype.fillDefault = function () {
    if (!this.defaultSelect) return;
    var self = this; this.defaultSelect.replaceChildren();
    this.draft.forEach(function (choice) { self.defaultSelect.appendChild(ui.option(choice.id, choice.name)); });
    this.defaultSelect.value = this.defaultId || "";
  };
  OptionDialog.prototype.removal = function (choice, row) {
    var self = this, stored = options.find(this.current, this.collection, choice.id),
      used = stored && stored.usage || {};
    var required = Boolean(used.live || used.recoverable || this.defaultId === choice.id), area = ui.element("div",
      "phc-zone-option-removal");
    var replacement = ui.element("select"); replacement.setAttribute("aria-label", "Replacement for " + choice.name);
    replacement.appendChild(ui.option("pending", "Choose a replacement"));
    if (this.collection === "level" || !required) replacement.appendChild(ui.option("",
      this.collection === "level" ? "Not set" : "Delete unused option"));
    this.draft.forEach(function (target) { if (target.id !== choice.id) replacement.appendChild(ui.option(target.id,
      target.name)); });
    replacement.value = "pending";
    var remove = ui.button("Remove", function () {
      if (replacement.value === "pending") return;
      var target = replacement.value || null;
      Object.keys(self.replacements).forEach(function (id) {
        if (self.replacements[id] === choice.id) self.replacements[id] = target;
      });
      if (choice.id.indexOf("new:") !== 0) self.replacements[choice.id] = target;
      if (self.defaultId === choice.id) self.defaultId = target;
      self.draft = self.draft.filter(function (entry) { return entry !== choice; }); self.fill();
    });
    remove.disabled = true;
    replacement.addEventListener("change", function () { remove.disabled = replacement.value === "pending"; });
    // A Level can be cleared; a Building Segment only merges into another, so each says what it offers.
    var next = this.collection === "level" ? "Choose a survivor to merge, or clear the Level assignment." :
      "Choose a survivor to merge.";
    area.appendChild(ui.element("span", "phc-zone-option-help", choice.name + ": " +
      (stored ? usage(stored) + ". " : "") + next));
    area.appendChild(replacement); area.appendChild(remove); area.appendChild(ui.button("Keep", function () {
      self.fill(); }));
    // The decision stays in this dialog. Only one replacement surface is shown at a time.
    var previous = this.list.querySelector(".phc-zone-option-removal"); if (previous) previous.remove();
    row.appendChild(area);
  };
  OptionDialog.prototype.fillAdoption = function () {
    var self = this;
    this.sources.forEach(function (source, index) {
      var mapping = self.mappings[index], row = ui.element("div", "phc-zone-option-row phc-zone-adoption-row");
      row.appendChild(ui.element("div", "phc-zone-option-source",
        (source.collection === "level" ? "Level: " : "Building Segment: ") + source.name));
      row.appendChild(ui.element("span", "phc-zone-option-usage", usage({ usage: source })));
      var target = ui.element("select"); target.setAttribute("aria-label", "Adopt " + source.name + " as");
      target.appendChild(ui.option("new", "Create a local option"));
      options.list(self.current, source.collection).forEach(function (choice) {
        target.appendChild(ui.option(choice.id, "Use " + choice.values.name)); });
      self.sources.forEach(function (other) {
        if (source.collection === other.collection && source.key !== other.key) {
          target.appendChild(ui.option("source:" + other.key, "Merge with " + other.name));
        }
      });
      target.value = mapping.target;
      var name = ui.element("input"); name.type = "text"; name.setAttribute("type", "text"); name.value = mapping.name;
      name.setAttribute("aria-label", "Local name for " + source.name); name.disabled = mapping.target !== "new";
        name._optionReadOnly = name.disabled;
      name.addEventListener("input", function () { mapping.name = name.value; self.validate(); });
      target.addEventListener("change", function () { mapping.target = target.value; self.fill(); });
      row.appendChild(target); row.appendChild(name);
      var colours = self.colourEditor(mapping, "Adopt " + source.name);
      if (mapping.target !== "new") colours.querySelectorAll("input, button").forEach(function (control) {
        control.disabled = true; control._optionReadOnly = true; });
      row.appendChild(colours); self.list.appendChild(row);
    });
  };
  OptionDialog.prototype.adoptionParams = function () {
    var self = this, resolved = [], roots = {};
    function resolve(index, seen) {
      var mapping = self.mappings[index], source = self.sources[index];
      if (seen.indexOf(index) >= 0) throw new Error("Merge choices form a cycle. Choose one surviving option.");
      if (mapping.target.indexOf("source:") === 0) {
        var key = mapping.target.slice(7), targetIndex = self.sources.map(function (entry) { return entry.key;
          }).indexOf(key);
        if (targetIndex < 0 || self.sources[targetIndex].collection !== source.collection) {
          throw new Error("Choose a valid survivor.");
        }
        return resolve(targetIndex, seen.concat(index));
      }
      if (mapping.target === "new") {
        roots[index] = { collection: source.collection, id: String(index), name: mapping.name, colour: mapping.colour };
        return { target_id: null, name: mapping.name, colour: mapping.colour };
      }
      var choice = options.find(self.current, source.collection, mapping.target);
      if (!choice) throw new Error("Choose an existing local option or create one.");
      return { target_id: choice.id, name: choice.values.name, colour: choice.values.colour };
    }
    this.mappings.forEach(function (mapping, index) { resolved.push(Object.assign({ source: mapping.source },
      resolve(index, []),
      mapping.target.indexOf("source:") === 0 ? { target_source: mapping.target.slice(7), target_id: null } : {})); });
    ["building_segment", "level"].forEach(function (collection) {
      var choices = options.list(self.current,
        collection).map(choiceView).concat(Object.keys(roots).map(function (id) { return roots[id]; })
        .filter(function (choice) { return choice.collection === collection; }));
      var error = validChoices(choices); if (error) throw new Error(error);
    });
    return { mappings: resolved };
  };
  OptionDialog.prototype.problem = function () {
    if (this.stale) return "The Model changed. Cancel and reopen to review its current options.";
    if (this.adopting) {
      try { this.adoptionParams(); return ""; } catch (error) { return error.message; }
    }
    var error = validChoices(this.draft); if (error) return error;
    if (this.collection === "building_segment" && !this.draft.some(function (choice) {
      return choice.id === this.defaultId; }, this)) {
      return "Choose a default Building Segment.";
    }
    return "";
  };
  OptionDialog.prototype.validate = function () {
    if (!this.dialog) return;
    this.error.textContent = this.problem();
      this.save.disabled = Boolean(this.error.textContent) || this.channel.busy();
  };
  OptionDialog.prototype.pending = function () {
    var busy = this.channel.busy();
    this.dialog.setAttribute("aria-busy", String(busy));
    this.dialog.querySelectorAll("input, select, button").forEach(function (control) {
      control.disabled = busy || Boolean(control._optionReadOnly);
    });
    this.save.disabled = busy || Boolean(this.problem());
    if (this.stale) {
      this.dialog.querySelectorAll("input, select, button").forEach(function (control) { control.disabled = true; });
      this.cancelButton.disabled = false; this.dialog.closeButton.disabled = false;
    }
  };
  OptionDialog.prototype.submit = function () {
    if (this.channel.busy() || this.problem()) { this.validate(); return; }
    var params = this.adopting ? this.adoptionParams() : { collection: this.collection,
      options: copy(this.draft), expected_options: copy(this.expected), default_segment_id: this.defaultId,
      expected_default_segment_id: this.expectedDefault, replacements: copy(this.replacements) };
    this.error.textContent = "";
    this.channel.run("ph_composer.zones.options." + (this.adopting ? "adopt" : "manage"), params); this.pending();
  };
  OptionDialog.prototype.cancel = function () {
    if (this.channel.busy()) { this.error.textContent = "Wait for the options change to finish."; return; }
    this.close();
  };
  OptionDialog.prototype.close = function () {
    if (!this.dialog) return;
    this.dialog.closeModal(); this.dialog.remove(); this.dialog = null;
  };
  OptionDialog.prototype.dispose = function () { this.channel.reset(); this.close(); };
  return OptionDialog;
});
