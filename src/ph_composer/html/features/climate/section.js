/* The Climate tab: one page header over source cards (Site location, then under "Climate sources" Phius climate
   data, Design temperatures and Hourly weather file) and the pane of the card selected. Every card's state comes
   from the summary snapshot section and the panes paint from the site and design-temperature sections. The
   card selected is remembered per Model session. The Phius climate data pane is a placeholder until the station
   picker lands, and the Hourly weather file card is Planned. Climate is first in the tab row; the panel still
   opens on Zones. */
PhComposerUI.define("features/climate/section", ["panel", "workspace", "snapshot", "source_cards",
  "features/climate/shared", "features/climate/site", "features/climate/set_location",
  "features/climate/design_temperatures"],
function (panel, ui, snapshot, SourceCards, shared, SitePane, setLocation, DesignPane) {
  "use strict";
  var TAB = "climate";
  var pages = Object.create(null);
  var WARNING = "warning", OK = "ok";
  // Export findings opened from the Export tab land on the card that fixes them.
  var CARD_FOR_CODE = { "climate.site_not_set": "site", "climate.zone_not_set": "site",
    "climate.utc_offset_not_set": "site", "climate.incomplete": "phius", "climate.outside_phius_limits": "phius",
    "climate.not_checked": "phius" };
  var CLIMATE_WORDS = { none: "Not set", incomplete: "Incomplete" };
  var VERDICT_WORDS = { pass: ["Pass", OK], fail: ["Outside Phius limits", WARNING], not_checked: ["Not checked"] };
  var DESIGN_WORDS = { not_set: ["Not set", WARNING], incomplete: ["Incomplete", WARNING], set: ["Set", OK] };

  function View(root, state, send) {
    var self = this, page = pages[state.session] || (pages[state.session] = {});
    this.session = state.session; this.send = send; this.root = root;
    root.replaceChildren();
    this.setButton = ui.button("Set Location…", function () { self.openSetLocation(); });
    this.header = ui.pageHeader({ title: "Climate" });
    this.cards = new SourceCards({ label: "Climate", state: page, stateKey: "card", groups: [
      { cards: [{ id: "site", title: "Site location" }] },
      { caption: "Climate sources", cards: [{ id: "phius", title: "Phius climate data" },
        { id: "design", title: "Design temperatures" },
        { id: "hourly", title: "Hourly weather file", planned: true }] }],
    changed: function () { panel.repaint(); } });
    this.site = new SitePane(function () { self.openSetLocation(); });
    this.phius = ui.element("section", "climate-pane climate-phius");
    this.phiusLine = ui.element("p", "climate-pane-intro");
    this.phius.appendChild(ui.element("h2", "", "Phius climate data"));
    this.phius.appendChild(this.phiusLine);
    this.design = new DesignPane(state.session, send);
    this.panes = { site: this.site.root, phius: this.phius, design: this.design.root };
    var content = ui.element("div", "climate-content");
    Object.keys(this.panes).forEach(function (key) { content.appendChild(self.panes[key]); });
    var layout = ui.element("div", "climate-layout");
    layout.appendChild(this.cards.root); layout.appendChild(content);
    root.appendChild(this.header.root); root.appendChild(layout);
  }

  View.prototype.openSetLocation = function () {
    var self = this;
    if (this.dialog || !this.siteValues) return;
    this.dialog = setLocation.open(this.session, this.send, this.siteValues,
      function () { return self.siteValues; }, function () { self.dialog = null; panel.repaint(); });
  };

  View.prototype.render = function (state) {
    var summary = snapshot.value(state, shared.SUMMARY), site = snapshot.value(state, shared.SITE);
    var design = snapshot.value(state, shared.DESIGN);
    this.siteValues = site;
    this.paintCards(summary, site, design);
    var selected = this.cards.selected, panes = this.panes;
    Object.keys(panes).forEach(function (key) { panes[key].hidden = key !== selected; });
    this.setButton.disabled = !site;
    this.header.setPrimary(selected === "site" ? this.setButton : null);
    this.site.render(site);
    this.design.render(state, design);
    this.phiusLine.textContent = "Attaching a Phius station or typing its values by hand comes in a later " +
      "version. " + (summary && summary.climate.state !== "none" ? "This Model holds a climate, and export " +
      "writes it when it is complete." : "This Model holds no climate.");
    if (this.dialog) this.dialog.consume(state);
  };

  View.prototype.paintCards = function (summary, site, design) {
    var cards = this.cards;
    cards.paint("site", site && site.state === "set" ? { lines: [shared.coordinates(site), shared.exportLine(site)] } :
      { chip: { text: "Not set", tone: WARNING } });
    var climate = summary && summary.climate;
    var verdict = climate && climate.state === "complete" ? VERDICT_WORDS[climate.verdict] : null;
    cards.paint("phius", !climate ? {} : verdict ? { chip: { text: verdict[0], tone: verdict[1] } } :
      { chip: { text: CLIMATE_WORDS[climate.state] || "Not set", tone: WARNING } });
    var words = design && DESIGN_WORDS[design.state];
    var lines = design && design.state === "set" ? ["99% heating " + shared.formatted(design.heating_99_c,
      shared.TEMPERATURE) + " · 1% cooling " + shared.formatted(design.cooling_1_c, shared.TEMPERATURE)] : [];
    if (design && design.warning) lines.push("Heating is at or above cooling");
    var tone = design && design.warning ? WARNING : words && words[1];
    cards.paint("design", words ? { lines: lines, chip: { text: words[0], tone: tone } } : {});
    cards.paint("hourly", { chip: { text: "Planned" } });
  };

  /* A navigation from elsewhere may name a card, or an export finding's code that one card fixes. */
  View.prototype.navigate = function (intent) {
    var card = intent.card || CARD_FOR_CODE[intent.code];
    if (card) { this.cards.select(card); panel.repaint(); }
  };

  View.prototype.dispose = function () {
    if (this.dialog) { this.dialog.dispose(); this.dialog = null; }
    this.design.dispose();
  };

  function render(root, state, send) {
    if (!root._view || root._view.session !== state.session) {
      if (root._view) root._view.dispose();
      root._view = new View(root, state, send);
    }
    root._view.render(state);
  }
  panel.workedOn("ph_composer.climate", TAB);
  panel.section(TAB, render, { pane: TAB, onNavigate: function (root, intent) {
    if (root._view) root._view.navigate(intent);
  } });
  return { render: render };
});
