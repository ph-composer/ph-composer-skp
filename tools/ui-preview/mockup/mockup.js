/* PH-Composer mockup kit (tools/ui-preview/.index.md, "Mockup kit"). A clickable planning mockup loads this
   script in its <head>:

     <script src="<relative path>/tools/ui-preview/mockup/mockup.js"
             data-panel-css="features/zones/zones.css library/library.css"></script>
     <link rel="stylesheet" href="my-mockup.css">

   It writes the panel's own stylesheets (base, overlay, shell, table, then each data-panel-css path under
   src/ph_composer/html/) and the kit's mockup.css ahead of the page's stylesheet, so a mockup looks like the
   panel and its own rules win ties. Then the page calls Mockup.start(config) once its state and views are
   defined. The kit owns the journey strip, `?journey=N&do=a,b` replay, data-tip tooltips, the success
   notice, the Lucide icon registry and the scene list the gallery captures. Mockups are throwaway planning
   pages, never panel code; Chromium 88 floor does not apply, but keep to plain scripts so a page opens from
   the ui-preview server without a build. */
(function () {
  "use strict";
  var me = document.currentScript;
  var kit = new URL(".", me.src);
  var html = new URL("../../../src/ph_composer/html/", kit);
  var sheets = ["base.css", "overlay.css", "shell.css", "table.css"]
    .concat((me.getAttribute("data-panel-css") || "").split(/\s+/).filter(Boolean))
    .map(function (p) { return new URL(p, html).href; })
    .concat([new URL("mockup.css", kit).href]);
  // document.write keeps the links in order and ahead of the page's own stylesheet, with no unstyled flash.
  sheets.forEach(function (href) { document.write('<link rel="stylesheet" href="' + href + '">'); });
  document.write('<link rel="icon" href="data:,">');  // no favicon request, so no stray 404

  // ---------------------------------------------------------------- icons (Lucide, ISC licence)
  /* eslint-disable max-len */
  var ICONS = {
    add: '<path d="M12 4v16M4 12h16"/>',
    sidebar: '<rect x="3" y="4" width="18" height="16" rx="2"/><path d="M9 4v16"/>',
    duplicate: '<path d="M8 8h12v12H8zM4 4h12v4M4 4v12h4"/>',
    del: '<path d="M4 6h16M9 6V3h6v3M6 6l1 15h10l1-15M10 10v7m4-7v7"/>',
    pencil: '<path d="M21.174 6.812a1 1 0 0 0-3.986-3.987L3.842 16.174a2 2 0 0 0-.5.83l-1.321 4.352a.5.5 0 0 0 .623.622l4.353-1.32a2 2 0 0 0 .83-.497z"/>',
    more: '<circle cx="5" cy="12" r="1.5" fill="currentColor" stroke="none"/><circle cx="12" cy="12" r="1.5" fill="currentColor" stroke="none"/><circle cx="19" cy="12" r="1.5" fill="currentColor" stroke="none"/>',
    settings: '<circle cx="12" cy="12" r="3"/><path d="M12 2v3m0 14v3M2 12h3m14 0h3M4.9 4.9l2.1 2.1m10 10 2.1 2.1M4.9 19.1 7 17m10-10 2.1-2.1"/>',
    alert: '<path d="M12 4 3 20h18Z"/><path d="M12 10v4m0 3v.01"/>',
    info: '<circle cx="12" cy="12" r="10"/><path d="M12 16v-4"/><path d="M12 8h.01"/>',
    clear: '<path d="M18 6 6 18"/><path d="m6 6 12 12"/>',
    locate: '<circle cx="12" cy="12" r="6"/><path d="M12 2v3m0 14v3M2 12h3m14 0h3"/><circle cx="12" cy="12" r="1" fill="currentColor" stroke="none"/>',
    check: '<circle cx="12" cy="12" r="9"/><path d="m7 12 3 3 7-7"/>',
    users: '<path d="M16 21v-2a4 4 0 0 0-4-4H6a4 4 0 0 0-4 4v2"/><circle cx="9" cy="7" r="4"/><path d="M22 21v-2a4 4 0 0 0-3-3.87"/><path d="M16 3.13a4 4 0 0 1 0 7.75"/>',
    light: '<path d="M15 14c.2-1 .7-1.7 1.5-2.5 1-.9 1.5-2.2 1.5-3.5A6 6 0 0 0 6 8c0 1 .2 2.2 1.5 3.5.7.7 1.3 1.5 1.5 2.5"/><path d="M9 18h6"/><path d="M10 22h4"/>',
    plug: '<path d="M12 22v-5"/><path d="M9 8V2"/><path d="M15 8V2"/><path d="M18 8v5a4 4 0 0 1-4 4h-4a4 4 0 0 1-4-4V8Z"/>',
    flame: '<path d="M8.5 14.5A2.5 2.5 0 0 0 11 12c0-1.38-.5-2-1-3-1.072-2.143-.224-4.054 2-6 .5 2.5 2 4.9 4 6.5 2 1.6 3 3.5 3 5.5a7 7 0 1 1-14 0c0-1.153.433-2.294 1-3a2.5 2.5 0 0 0 2.5 2.5z"/>',
    droplet: '<path d="M12 22a7 7 0 0 0 7-7c0-2-1-3.9-3-5.5s-3.5-4-4-6.5c-.5 2.5-2 4.9-4 6.5C6 11.1 5 13 5 15a7 7 0 0 0 7 7z"/>',
    wind: '<path d="M17.7 7.7a2.5 2.5 0 1 1 1.8 4.3H2"/><path d="M9.6 4.6A2 2 0 1 1 11 8H2"/><path d="M12.6 19.4A2 2 0 1 0 14 16H2"/>',
    waves: '<path d="M2 6c.6.5 1.2 1 2.5 1C7 7 7 5 9.5 5c2.6 0 2.4 2 5 2 2.5 0 2.5-2 5-2 1.3 0 1.9.5 2.5 1"/><path d="M2 12c.6.5 1.2 1 2.5 1 2.5 0 2.5-2 5-2 2.6 0 2.4 2 5 2 2.5 0 2.5-2 5-2 1.3 0 1.9.5 2.5 1"/><path d="M2 18c.6.5 1.2 1 2.5 1 2.5 0 2.5-2 5-2 2.6 0 2.4 2 5 2 2.5 0 2.5-2 5-2 1.3 0 1.9.5 2.5 1"/>',
    thermo: '<path d="M14 4v10.54a4 4 0 1 1-4 0V4a2 2 0 0 1 4 0Z"/>',
    calendar: '<path d="M8 2v4"/><path d="M16 2v4"/><rect width="18" height="18" x="3" y="4" rx="2"/><path d="M3 10h18"/>',
    sigma: '<path d="M18 7V5a1 1 0 0 0-1-1H6.5a.5.5 0 0 0-.4.8l4.5 6a2 2 0 0 1 0 2.4l-4.5 6a.5.5 0 0 0 .4.8H17a1 1 0 0 0 1-1v-2"/>',
    home: '<path d="M15 21v-8a1 1 0 0 0-1-1h-4a1 1 0 0 0-1 1v8"/><path d="M3 10a2 2 0 0 1 .709-1.528l7-5.999a2 2 0 0 1 2.582 0l7 5.999A2 2 0 0 1 21 10v9a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2z"/>',
    reset: '<path d="M3 12a9 9 0 1 0 9-9 9.75 9.75 0 0 0-6.74 2.74L3 8"/><path d="M3 3v5h5"/>',
    chev: '<path d="m9 18 6-6-6-6"/>',
    lock: '<rect width="18" height="11" x="3" y="11" rx="2" ry="2"/><path d="M7 11V7a5 5 0 0 1 10 0v4"/>'
  };
  /* eslint-enable max-len */

  function esc(t) { return String(t).replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/"/g, "&quot;"); }
  function svg(name, size) {
    if (!ICONS[name]) console.error("Mockup: no icon named " + name);
    size = size || 16;
    return '<svg width="' + size + '" height="' + size + '" viewBox="0 0 24 24" fill="none" stroke="currentColor"' +
      ' stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">' +
      (ICONS[name] || "") + '</svg>';
  }

  var cfg = null;
  var journey = 1;
  var replaying = false;

  // ---------------------------------------------------------------- journey strip
  function strip() {
    var el = document.getElementById("mk-strip");
    if (!el) {
      el = document.createElement("div"); el.id = "mk-strip"; el.className = "mk-strip";
      document.body.insertBefore(el, document.body.firstChild);
    }
    var h = '<b>' + esc(cfg.title) + '</b>';
    if (cfg.journeys.length > 1) {
      h += '<span>Journey:</span>';
      cfg.journeys.forEach(function (j, i) {
        h += '<button type="button" data-mk="journey" data-v="' + (i + 1) + '"' +
          ' aria-pressed="' + (journey === i + 1) + '">' +
          (i + 1) + ' · ' + esc(j.title) + '</button>';
      });
    }
    var hint = cfg.hint ? cfg.hint(journey) : cfg.journeys[journey - 1].hint;
    h += '<button type="button" data-mk="reset">Reset</button><span class="mk-hint">' + (hint || "") + '</span>';
    el.innerHTML = h;
  }

  function startJourney(n) {
    journey = n;
    cfg.init(n);
    cfg.render();
  }

  // ---------------------------------------------------------------- notice and tooltip
  var noticeTimer = null;
  function notice(text) {
    if (replaying) return;
    var old = document.querySelector(".mk-notice"); if (old) old.remove();
    clearTimeout(noticeTimer);
    if (!text) return;
    var n = document.createElement("div");
    n.className = "mk-notice"; n.setAttribute("role", "status");
    n.innerHTML = svg("check", 16) + '<span>' + text + '</span>';
    document.body.appendChild(n);
    noticeTimer = setTimeout(function () { n.remove(); }, 3500);
  }

  function tooltips() {
    var tip = document.createElement("div");
    tip.className = "mk-tip"; tip.setAttribute("role", "tooltip"); tip.hidden = true;
    document.body.appendChild(tip);
    document.addEventListener("mouseover", function (e) {
      var el = e.target.closest("[data-tip]"); if (!el) { tip.hidden = true; return; }
      tip.textContent = el.getAttribute("data-tip"); tip.hidden = false;
      var r = el.getBoundingClientRect();
      tip.style.left = Math.min(window.innerWidth - 310, Math.max(4, r.left)) + "px";
      tip.style.top = (r.bottom + 6 + 60 > window.innerHeight ? r.top - tip.offsetHeight - 6 : r.bottom + 6) + "px";
    });
  }

  // ---------------------------------------------------------------- replay
  // `?journey=N&do=a,b` starts journey N and runs the named steps in order before the first render. A step
  // that needs the rendered page (open a dialog, anchor a bubble) returns a function, run after that render.
  // An unknown step is a console error, so the gallery capture fails rather than shooting the wrong state.
  function replay() {
    var n = parseInt((location.search.match(/[?&]journey=(\d+)/) || [])[1], 10);
    journey = n >= 1 && n <= cfg.journeys.length ? n : 1;
    cfg.init(journey);
    var after = [];
    replaying = true;
    ((location.search.match(/[?&]do=([\w,-]+)/) || [])[1] || "").split(",").filter(Boolean).forEach(function (name) {
      var step = cfg.steps && cfg.steps[name];
      if (!step) { console.error("Mockup: no step named " + name); return; }
      var later = step();
      if (typeof later === "function") after.push(later);
    });
    cfg.render();
    after.forEach(function (fn) { fn(); });
    replaying = false;
    // Two frames let the last render lay out; the gallery waits for this flag instead of a fixed delay.
    requestAnimationFrame(function () {
      requestAnimationFrame(function () { document.documentElement.setAttribute("data-mockup-ready", ""); });
    });
  }

  /* config:
       title     strip label
       journeys  [{ title, hint }]: one per starting state; hint says what to try (HTML allowed)
       init(n)   build the state for journey n (1-based); the page keeps its own state variable
       render()  draw the page; call Mockup.strip() from it so the hint follows the state
       hint(n)   optional: the strip hint when it depends on the state
       steps     { name: fn } for `do=` replay
       scenes    [{ group, try, shots: [{ png, journey, do, size, hover, select, clip, note }] }]: what the
                 gallery captures and the README scene table lists (tools/ui-preview/.index.md) */
  function start(config) {
    cfg = config;
    window.MOCKUP = { title: cfg.title, journeys: cfg.journeys, scenes: cfg.scenes || [] };
    document.addEventListener("click", function (e) {
      var el = e.target.closest("[data-mk]"); if (!el) return;
      if (el.getAttribute("data-mk") === "journey") startJourney(+el.getAttribute("data-v"));
      else startJourney(journey);
    });
    tooltips();
    replay();
  }

  window.Mockup = {
    start: start,
    strip: function () { if (cfg) strip(); },
    notice: notice,
    svg: svg,
    esc: esc,
    icons: ICONS,
    journey: function () { return journey; }
  };
})();
