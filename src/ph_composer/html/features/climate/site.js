/* The Site location pane: with no site, what the site is and the way to set it; with one, its five fields, each
   unset one said so. Set Location itself opens from the page header, or from the empty state's own button. */
PhComposerUI.define("features/climate/site", ["workspace", "unit_preferences", "features/climate/shared"],
function (ui, preferences, shared) {
  "use strict";
  var NOT_SET = "Not set";

  function Pane(openSetLocation) {
    this.root = ui.element("section", "climate-pane climate-site");
    this.open = openSetLocation;
  }

  Pane.prototype.render = function (site) {
    // Painted again only when the site or the unit system moves, so the empty state's button keeps its focus.
    var key = site ? JSON.stringify(site) + preferences.current().unitSystem : "";
    if (key === this.painted) return;
    this.painted = key;
    if (!site) { this.root.replaceChildren(); return; }
    if (site.state !== "set") this.empty(); else this.facts(site);
  };

  Pane.prototype.empty = function () {
    var box = ui.element("div", "climate-empty"), list = ui.element("ul");
    box.appendChild(ui.element("h2", "", "The site location is not set"));
    box.appendChild(ui.element("p", "", "The site is where the building is. It is separate from the climate " +
      "station, which may be some distance away."));
    ["Type the latitude, longitude and elevation in Set Location.",
      "Read from SketchUp Geolocation fills latitude and longitude. Nothing is written back to SketchUp.",
      "The station check measures distance and elevation from the site."].forEach(function (line) {
      list.appendChild(ui.element("li", "", line));
    });
    box.appendChild(list);
    var set = ui.button("Set Location…", this.open);
    set.className = "primary";
    box.appendChild(set);
    this.root.replaceChildren(box);
  };

  Pane.prototype.facts = function (site) {
    var list = ui.element("dl", "climate-facts");
    function row(term, value) {
      list.appendChild(ui.element("dt", "", term));
      list.appendChild(ui.element("dd", value === null ? "is-unset" : "", value === null ? NOT_SET : value));
    }
    row("Latitude", site.latitude_deg.toFixed(3) + "°");
    row("Longitude", site.longitude_deg.toFixed(3) + "°");
    row("Elevation", shared.formatted(site.elevation_m, shared.ELEVATION));
    row("Climate zone", site.climate_zone_label);
    row("Hours from UTC", shared.hours(site.hours_from_utc));
    this.root.replaceChildren(ui.element("h2", "", "Site location"), list);
  };

  return Pane;
});
