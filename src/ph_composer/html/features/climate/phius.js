/* The Phius climate data pane while the Model holds no climate: one of three states, from the climate data
   folders on this computer (`folders.list`, read each time the pane is shown and after the climate data dialog
   closes) and the Model's site (J3).
     no folder   says so, says why PH-Composer ships none, and offers Choose Climate Data Folder (board 2);
     no site     asks for the site first and offers Set Location (board 9);
     ready       names the dataset the station picker opens on, with its station count (board 10).
   Each offers Enter Values by Hand. Choose Station and Enter Values by Hand are shown disabled with their reason
   until the station picker and hand entry land. With a climate in the Model the pane keeps its one line. */
PhComposerUI.define("features/climate/phius", ["workspace", "request", "features/climate/shared"],
function (ui, requests, shared) {
  "use strict";
  var el = ui.element, LIST = shared.PREFIX + "folders.list";
  var PAINT = { loading: "loading", unreadable: "noFolder", no_folder: "noFolder", no_site: "noSite",
    ready: "ready", attached: "attached" };
  var LATER = { station: "Choosing a station comes in a later version of PH-Composer.",
    hand: "Typing climate values by hand comes in a later version of PH-Composer." };

  /* `actions.openData(add)` opens Climate Data on This Computer, starting Add Folder when `add`;
     `actions.setLocation()` opens Set Location. */
  function Pane(session, send, actions) {
    this.actions = actions; this.folders = undefined; this.failure = null; this.shown = false; this.painted = null;
    this.reads = requests.channel(session, send, "climate_phius_folders", "query.invoke");
    this.root = el("section", "climate-pane climate-phius");
  }

  /* Reads the folders again the next time the pane is shown, or now if it is. What was read before is not shown
     meanwhile: the dialog may have changed it. */
  Pane.prototype.refresh = function () {
    this.stale = true; this.outdated = true;
    if (this.shown) this.read();
  };

  Pane.prototype.read = function () {
    this.stale = false;
    if (!this.reads.busy()) this.reads.run(LIST, {}); else this.stale = true;
  };

  Pane.prototype.render = function (state, summary, site, shown) {
    var listed = this.reads.consume(state);
    if (listed) {
      this.folders = listed.status === "completed" ? listed.value : null;
      this.failure = listed.status === "completed" ? null : listed.message;
      if (this.stale) this.read(); else this.outdated = false;
    }
    var opened = shown && !this.shown;
    this.shown = shown;
    var attached = summary && summary.climate.state !== "none";
    if (!attached && shown && (opened || this.stale || this.folders === undefined)) this.read();
    var waiting = this.folders === undefined || this.outdated;
    var view = attached ? "attached" : !summary || !site || waiting ? "loading" :
      this.failure ? "unreadable" : this.stateFor(site);
    var key = view + "|" + JSON.stringify(this.folders || null) + (this.failure || "");
    if (key === this.painted) return;
    this.painted = key;
    this.root.setAttribute("data-state", view);
    this[PAINT[view]](summary);
  };

  /* A folder that cannot be found now is not one the picker can read: with none found, the pane is empty. */
  Pane.prototype.found = function () {
    return ((this.folders && this.folders.folders) || []).filter(function (folder) { return folder.found; });
  };

  Pane.prototype.stateFor = function (site) {
    if (!this.found().length) return "no_folder";
    return site.state === "set" ? "ready" : "no_site";
  };

  /* The dataset the station picker opens on: the one it used last, if it is found, else the first found that holds
     stations, else the first found. */
  Pane.prototype.dataset = function () {
    var found = this.found(), last = this.folders.last_dataset_id;
    return found.filter(function (folder) { return folder.id === last; })[0] ||
      found.filter(function (folder) { return folder.station_count > 0; })[0] || found[0];
  };

  Pane.prototype.box = function (title, intro, bullets, buttons) {
    var box = el("div", "climate-empty"), list = el("ul"), row = el("div", "climate-empty-actions");
    box.appendChild(el("h2", "", title));
    if (intro) box.appendChild(el("p", "", intro));
    (bullets || []).forEach(function (line) { list.appendChild(el("li", "", line)); });
    if (bullets && bullets.length) box.appendChild(list);
    buttons.forEach(function (button) { row.appendChild(button); });
    box.appendChild(row);
    this.root.replaceChildren(box);
  };

  Pane.prototype.primary = function (label, run) {
    var button = ui.button(label, run); button.className = "primary"; return button;
  };

  /* A control whose feature has not landed: disabled, with its reason beside it. */
  function later(label, reason) {
    var group = el("span", "climate-later"), button = ui.button(label, function () {});
    button.disabled = true;
    group.appendChild(button); group.appendChild(ui.reasonButton(label.replace(/…$/, ""), reason));
    return group;
  }

  Pane.prototype.noFolder = function () {
    var self = this, missing = (this.folders && this.folders.folders || []).length > 0;
    if (this.failure) {
      return this.box("No Phius climate data on this computer", this.failure, [], [later("Enter Values by Hand…",
        LATER.hand)]);
    }
    if (missing) {
      return this.box("The climate data folder cannot be found", "The climate data folder set up on this " +
        "computer is not where it was. It may have moved, or be on a drive that is not connected.",
        ["Locate it, or choose another, in Climate Data on This Computer."],
        [this.primary("Climate Data on This Computer…", function () { self.actions.openData(false); }),
          later("Enter Values by Hand…", LATER.hand)]);
    }
    this.box("No Phius climate data on this computer", "PH-Composer does not include climate data. Phius " +
      "licenses its climate files to you, so they stay on your computer.",
      ["Choose the folder that holds your Phius station files. Subfolders are read too.",
        "The folder's location is remembered on this computer only.",
        "When you pick a station, its values are copied into this Model. The Model then reads without the folder.",
        "With no climate files, type or paste the monthly values and peak loads yourself."],
      [this.primary("Choose Climate Data Folder…", function () { self.actions.openData(true); }),
        later("Enter Values by Hand…", LATER.hand)]);
  };

  Pane.prototype.noSite = function () {
    var self = this;
    this.box("Set the site location first", "A station is checked against the site: Phius allows one within " +
      "50 miles (80 km) and 400 feet (122 m) of elevation. The station list is sorted by distance from the site.",
      [], [this.primary("Set Location…", function () { self.actions.setLocation(); }),
        later("Enter Values by Hand…", LATER.hand)]);
  };

  Pane.prototype.ready = function () {
    var dataset = this.dataset(), stations = dataset.station_count;
    this.box("No Phius climate data in this Model", dataset.name + " · " + Number(stations).toLocaleString("en-US") +
      " station" + (stations === 1 ? "" : "s") + " on this computer.",
      ["Choose a station near the site. Its values are copied into this Model, which then reads without the folder.",
        "With a custom dataset from Phius, or no station file, type or paste the monthly values and peak loads " +
        "yourself."],
      [later("Choose Station…", LATER.station), later("Enter Values by Hand…", LATER.hand)]);
  };

  /* Until the attached pane lands. */
  Pane.prototype.attached = function () {
    this.root.replaceChildren(el("h2", "", "Phius climate data"), el("p", "climate-pane-intro", "Attaching a " +
      "Phius station or typing its values by hand comes in a later version. This Model holds a climate, and " +
      "export writes it when it is complete."));
  };

  Pane.prototype.loading = function () {
    this.root.replaceChildren(el("p", "muted", "Reading the climate data folders…"));
  };

  Pane.prototype.dispose = function () { this.reads.reset(); };

  return Pane;
});
