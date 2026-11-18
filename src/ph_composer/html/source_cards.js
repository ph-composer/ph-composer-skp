/* A sidebar of cards beside one pane, each card a subject the pane can show, with its state: a title, a few
   short lines and a state chip. Cards sit in groups, each with an optional small caption. A card marked
   `planned` is shown, read only, and never selected. At narrow widths (source_cards.css) the cards give way to
   one select above the pane, so the pane keeps the width.

   new SourceCards({ label, groups: [{ caption, cards: [{ id, title, planned }] }], state, stateKey, changed })
   `state[stateKey]` remembers the selected card (the owner keeps `state` per Model session); `changed(id)` runs
   after the user picks another card. `paint(id, { lines: [text], chip: { text, tone } })` repaints one card; a
   tone is "ok", "warning" or omitted for neutral. `select(id)` selects a card as a pick would, without
   `changed`. */
PhComposerUI.define("source_cards", ["workspace"], function (ui) {
  "use strict";

  function SourceCards(options) {
    var self = this;
    this.state = options.state || {}; this.stateKey = options.stateKey || "card";
    this.changed = options.changed || function () {};
    this.cards = Object.create(null); this.order = [];
    this.root = ui.element("div", "phc-source-cards");
    this.list = ui.element("nav", "phc-source-card-list");
    this.list.setAttribute("aria-label", options.label);
    this.picker = ui.element("select", "phc-source-card-select");
    this.picker.setAttribute("aria-label", options.label);
    this.picker.addEventListener("change", function () { self.pick(self.picker.value); });
    options.groups.forEach(function (group) {
      if (group.caption) self.list.appendChild(ui.element("div", "phc-source-card-caption", group.caption));
      var choices = group.caption ? ui.element("optgroup") : self.picker;
      if (group.caption) { choices.setAttribute("label", group.caption); self.picker.appendChild(choices); }
      group.cards.forEach(function (card) { self.add(card, choices); });
    });
    this.root.appendChild(this.list); this.root.appendChild(this.picker);
    var first = this.order.filter(function (id) { return !self.cards[id].planned; })[0];
    this.select(this.cards[this.state[this.stateKey]] && !this.cards[this.state[this.stateKey]].planned ?
      this.state[this.stateKey] : first);
  }

  SourceCards.prototype.add = function (card, choices) {
    var self = this, button = ui.element("button", "phc-source-card");
    button.type = "button";
    button.setAttribute("data-card", card.id);
    var title = ui.element("span", "phc-source-card-title", card.title);
    var lines = ui.element("span", "phc-source-card-lines"), chip = ui.element("span", "phc-source-card-chip");
    button.appendChild(title); button.appendChild(lines); button.appendChild(chip);
    var option = ui.option(card.id, card.title);
    if (card.planned) {
      // Shown so the user knows it is coming; not a choice, so it never takes focus or a click.
      button.disabled = true; button.setAttribute("aria-disabled", "true"); option.disabled = true;
    } else {
      button.addEventListener("click", function () { self.pick(card.id); });
    }
    choices.appendChild(option);
    this.list.appendChild(button);
    this.cards[card.id] = { button: button, lines: lines, chip: chip, option: option, title: card.title,
      planned: Boolean(card.planned) };
    this.order.push(card.id);
  };

  SourceCards.prototype.pick = function (id) {
    if (!this.cards[id] || this.cards[id].planned) { this.picker.value = this.selected; return; }
    if (id === this.selected) return;
    this.select(id);
    this.changed(id);
  };

  SourceCards.prototype.select = function (id) {
    if (!this.cards[id] || this.cards[id].planned) return;
    var self = this;
    this.selected = this.state[this.stateKey] = id;
    this.order.forEach(function (key) {
      var current = key === id;
      self.cards[key].button.setAttribute("aria-current", current ? "true" : "false");
      self.cards[key].button.classList.toggle("is-selected", current);
    });
    this.picker.value = id;
  };

  SourceCards.prototype.paint = function (id, view) {
    var card = this.cards[id], lines = (view && view.lines) || [], chip = view && view.chip;
    if (!card) return;
    card.lines.replaceChildren.apply(card.lines, lines.map(function (line) {
      return ui.element("span", "phc-source-card-line", line);
    }));
    card.chip.hidden = !chip;
    card.chip.textContent = chip ? chip.text : "";
    if (chip && chip.tone) card.chip.setAttribute("data-tone", chip.tone); else card.chip.removeAttribute("data-tone");
    // The select names the state too, since at narrow widths it is the only place the card shows.
    card.option.textContent = card.title + (chip ? " · " + chip.text : "");
  };

  return SourceCards;
});
