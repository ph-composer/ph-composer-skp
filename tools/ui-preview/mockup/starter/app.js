"use strict";
/* global Mockup */
/* exported JOURNEYS, init, STEPS */
/* Starter mockup: one state variable, one render, delegated events and the `do=` steps. When the page grows
   past a few hundred lines, split it as the Programs prototype does (model.js, views.js, app.js) so each
   edit has a short, unique anchor. A throwaway planning page, not panel code. */
var svg = Mockup.svg, esc = Mockup.esc;

var JOURNEYS = [
  { title: "Three Zones", hint: "<em>Check a Zone</em> to see the selection bar." },
  { title: "One flagged", hint: "The Attic has no Assembly: its row is flagged." }
];

var S;
function init(journey) {
  S = {
    checked: {},
    zones: [
      { id: "z1", name: "Living", area: 48 },
      { id: "z2", name: "Bedroom", area: 14 },
      { id: "z3", name: "Attic", area: 22, missing: journey === 2 ? "No Assembly on the Attic floor" : "" }
    ]
  };
}

function zoneRow(z) {
  var flagged = z.missing ?
    ' <span class="zp-flag" data-tip="' + esc(z.missing) + '">' + svg("alert", 14) + '</span>' : "";
  return '<tr class="tier-0"><td class="col-actions"><input type="checkbox" data-act="check" data-v="' + z.id + '"' +
    (S.checked[z.id] ? " checked" : "") + ' aria-label="Check ' + esc(z.name) + '"></td>' +
    '<td class="mk-name">' + esc(z.name) + flagged + '</td>' +
    '<td>' + z.area.toFixed(1) + '</td></tr>';
}

function render() {
  Mockup.strip();
  document.getElementById("app-tabs").innerHTML =
    '<button type="button" class="is-active" aria-pressed="true">Zones</button>';
  var n = Object.keys(S.checked).length;
  document.getElementById("pane").innerHTML =
    '<div class="phc-heading"><h1>Zones</h1></div>' +
    '<div class="phc-table-mount"><table class="phc-table"><thead><tr><th class="col-actions"></th>' +
    '<th class="mk-name">Name</th><th>Floor area [m²]</th></tr></thead><tbody>' +
    S.zones.map(zoneRow).join("") + '</tbody></table></div>' +
    (n ? '<div class="phc-selection-bar" role="region" aria-label="Selection">' + n + ' Zone' + (n > 1 ? "s" : "") +
      ' selected</div>' : "");
}

document.addEventListener("change", function (e) {
  var el = e.target;
  if (el.getAttribute("data-act") !== "check") return;
  if (el.checked) S.checked[el.getAttribute("data-v")] = 1; else delete S.checked[el.getAttribute("data-v")];
  Mockup.notice(el.checked ? "Checked." : "Unchecked.");
  render();
});

// `do=` steps: change S before the first render. Return a function for work that needs the rendered page.
var STEPS = {
  check: function () { S.checked.z1 = 1; }
};
