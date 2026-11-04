/* DOM and text primitives every panel file builds from. No state, no domain vocabulary. */
PhComposerUI.define("dom", [], function () {
  "use strict";
  var SVG_NS = "http://www.w3.org/2000/svg";

  function element(tag, className, text) {
    var node = document.createElement(tag);
    if (className) node.className = className;
    if (text !== undefined) node.textContent = text;
    return node;
  }
  function svg(tag, attrs, text) {
    var node = document.createElementNS(SVG_NS, tag);
    Object.keys(attrs || {}).forEach(function (key) { node.setAttribute(key, String(attrs[key])); });
    if (text !== undefined) node.textContent = text;
    return node;
  }
  function button(label, handler, disabled) {
    var node = element("button", "", label);
    node.type = "button";
    node.disabled = Boolean(disabled);
    if (handler) node.addEventListener("click", handler);
    return node;
  }
  function option(value, text) { var node = element("option", "", text); node.value = value; return node; }
  /* One tooltip source: browser title hints would cover the panel's styled tooltip after a long hover. */
  function tooltip(node, text) {
    node.removeAttribute("title");
    if (text) node.setAttribute("data-tooltip", String(text));
    else node.removeAttribute("data-tooltip");
    return node;
  }
  /* Writes a label whose leading PH symbol takes its subscript: "Uf W/(m² K)" sets U with f, "ψ-install" sets ψ
     with install. Any other text is written as is. One inline run, so a column layout never splits the symbol. */
  function symbolText(node, text) {
    var symbol = /^(U|\u03c8)-?([a-z]+)(?=\s|$)(.*)$/.exec(String(text));
    node.textContent = symbol ? "" : text;
    if (!symbol) return node;
    node.appendChild(element("span", "", symbol[1])); node.appendChild(element("sub", "", symbol[2]));
    if (symbol[3]) node.appendChild(element("span", "", symbol[3]));
    return node;
  }
  function titleCase(value) {
    if (value === null || value === undefined) return "";
    return String(value).replace(/_/g, " ").replace(/^./, function (letter) { return letter.toUpperCase(); });
  }
  function number(value, factor) {
    return typeof value === "number" && isFinite(value) ? (factor ? String(value) : value.toFixed(2)) : "-";
  }
  function blank(value) { return value === null || value === undefined || value === ""; }
  function compareText(a, b) {
    return String(a).localeCompare(String(b), undefined, { numeric: true, sensitivity: "base" });
  }
  /* A label/value line, as a details bubble or an inspector shows it. */
  function propertyRow(label, value, unit, prefix) {
    var row = element("div", "phc-property-row"); row.appendChild(element("span", "", label));
    row.appendChild(element("span", "phc-property-value",
      (prefix || "") + (blank(value) ? "—" : String(value)) + (unit ? " " + unit : "")));
    return row;
  }
  /* A short "this changed" pulse: a small rise, then a highlight halo that fades. Used where a surface
     changes under the user without them moving it, so the change is never silent. A host without the Web
     Animations API, or a user who asked for reduced motion, simply gets the new state. */
  function pulse(node) {
    if (!node || !node.animate) return null;
    if (window.matchMedia && window.matchMedia("(prefers-reduced-motion: reduce)").matches) return null;
    if (node.phcPulse) node.phcPulse.forEach(function (animation) { animation.cancel(); });
    node.phcPulse = [
      node.animate([
        { transform: "translateY(4px)", opacity: 0.55 },
        { transform: "translateY(-1px)", opacity: 1, offset: 0.6 },
        { transform: "none", opacity: 1 }
      ], { duration: 260, easing: "ease-out" }),
      node.animate([
        { boxShadow: "0 0 0 4px var(--interaction-highlight-tint)", offset: 0 },
        { boxShadow: "0 0 0 4px var(--interaction-highlight-tint)", offset: 0.3 },
        { boxShadow: "0 0 0 0 transparent", offset: 1 }
      ], { duration: 620, easing: "ease-out" })
    ];
    return node.phcPulse;
  }

  /* Runs `paint` only when `inputs` differ from the last call for this owner and key, and returns whether they
     differed, so a caller may also guard its own body. The key names one paint of the owner, so one owner can
     memoise several independently. Pass small inputs (a generation, an id list, a profile) where the caller has
     them; the signature is their JSON. */
  function memoPaint(owner, key, inputs, paint) {
    var signature = JSON.stringify(inputs);
    var memo = owner._memoPaint || (owner._memoPaint = Object.create(null));
    if (memo[key] === signature) return false;
    memo[key] = signature;
    if (paint) paint();
    return true;
  }

  return { element: element, svg: svg, button: button, option: option, titleCase: titleCase,
    number: number, blank: blank, compareText: compareText, propertyRow: propertyRow, memoPaint: memoPaint,
    pulse: pulse, tooltip: tooltip, symbolText: symbolText };
});
