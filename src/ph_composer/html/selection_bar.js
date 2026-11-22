/* A bar that floats over the bottom of a work surface while something there is selected: a count line, the
   controls its owner places in `controls`, and a clear icon. It sits in the work surface's overlay layer, so
   showing or hiding it never reflows the table; while it shows it pads the scroll area it covers by its own
   height, so the last rows stay reachable. On a panel too short to float it without covering the table's
   header, it docks beneath the work surface instead (`reserve`). It names no record and no field: the owner
   supplies the words, the controls and what clearing means. */
PhComposerUI.define("selection_bar", ["dom", "icons"], function (dom, icons) {
  "use strict";
  var FALLBACK_HEIGHT = 52, CLEARANCE = 16;

  function SelectionBar(label, onClear) {
    this.root = dom.element("div", "phc-selection-bar");
    this.root.setAttribute("role", "region");
    this.root.setAttribute("aria-label", label);
    this.count = dom.element("span", "phc-selection-bar-count");
    this.count.setAttribute("role", "status");
    this.controls = dom.element("div", "phc-selection-bar-controls");
    this.clear = icons.iconButton("Clear selection", "clear", function () { onClear(); });
    this.clear.classList.add("phc-selection-bar-clear");
    this.root.appendChild(this.count);
    this.root.appendChild(this.controls);
    this.root.appendChild(this.clear);
    this.root.hidden = true;
  }

  /* `text` is the count line, or empty for a bar that is all controls; `clearable` offers the clear icon. */
  SelectionBar.prototype.show = function (text, clearable) {
    if (this.count.textContent !== text) this.count.textContent = text;
    this.count.hidden = !text;
    this.clear.hidden = !clearable;
    this.root.hidden = false;
  };

  SelectionBar.prototype.hide = function () { this.root.hidden = true; };

  /* Pads `scroll` by the bar's height while it shows, and gives the padding back when it goes. `keep` is the
     height at the top of `scroll` the bar must leave in view, such as a table's header: where floating would
     cover it (the shortest panels), the bar docks in flow after its positioned element's content instead, so
     the owner places the bar after the work surface. `fit`, if given, sizes the work surface around the bar:
     it runs with the bar floating, and again if it docks. */
  SelectionBar.prototype.reserve = function (scroll, keep, fit) {
    // Measuring sets the padding afresh, which would pull a scroll near the end back; the scroll is put back after.
    var root = this.root, scrolled = scroll.scrollTop;
    root.classList.remove("is-docked");
    scroll.style.paddingBottom = root.hidden ? "" : (root.offsetHeight || FALLBACK_HEIGHT) + CLEARANCE + "px";
    if (fit) fit();
    // The bar floats a little above the scroller's bottom edge, by however much its container's layout puts
    // beneath the table; the padding covers that too, so the last row can still scroll clear of the bar.
    if (!root.hidden) {
      var over = scroll.getBoundingClientRect().bottom - root.getBoundingClientRect().top + CLEARANCE;
      if (over > parseFloat(scroll.style.paddingBottom)) scroll.style.paddingBottom = Math.ceil(over) + "px";
    }
    if (!root.hidden && keep !== undefined &&
        root.getBoundingClientRect().top < scroll.getBoundingClientRect().top + keep) {
      root.classList.add("is-docked");
      scroll.style.paddingBottom = "";
      if (fit) fit();
    }
    if (scroll.scrollTop !== scrolled) scroll.scrollTop = scrolled;
  };

  return { SelectionBar: SelectionBar };
});
