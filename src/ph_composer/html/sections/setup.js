/* The Setup view, behind the gear at the right end of the tab row: setup for this computer that belongs to no
   page, such as agent access. Each entry is a native menu item a feature declared `in_setup`
   (shell/setup_entries.rb). The view lists them under their menu's name, each with the line of current state
   its feature gives, and runs one as the Extensions menu does. It names no feature. The entries are asked for
   each time the view opens and when the panel's window regains focus, after a window an entry opened. */
PhComposerUI.define("sections/setup", ["panel", "icons", "page_header", "workspace"],
  function (panel, icons, header, ui) {
    "use strict";
    var element = ui.element, shown = false, session = null, send = null;
    var gear = document.querySelector("[data-tab='setup']");
    if (gear) gear.innerHTML = icons.svgIcon("settings", 18);

    function ask() { if (send) send("panel.setup_entries", {}); }

    function entryRow(entry) {
      var row = element("div", "phc-setup-entry");
      row.appendChild(element("p", "", entry.summary || ""));
      row.appendChild(ui.button(entry.label, function () { send("panel.setup_open", { name: entry.name }); }));
      return row;
    }

    function paint(root, entries) {
      var page = header.pageHeader({ title: "Setup" }), groups = [], byMenu = {};
      (entries || []).forEach(function (entry) {
        var group = byMenu[entry.menu];
        if (!group) {
          group = byMenu[entry.menu] = element("section", "phc-setup-group");
          group.appendChild(element("h2", "", entry.menu)); groups.push(group);
        }
        group.appendChild(entryRow(entry));
      });
      if (!entries) groups.push(element("p", "muted", "Reading setup…"));
      root.replaceChildren.apply(root, [page.root].concat(groups));
    }

    function render(root, state, post) {
      send = post;
      // Opened now, or shown again for another Model (or after none): either way, ask afresh.
      var opened = state.ui.activeTab === "setup" && (!shown || state.session !== session);
      shown = state.ui.activeTab === "setup"; session = state.session;
      var entries = state.ui.setupEntries || null;
      ui.memoPaint(root, "setup", [entries], function () { paint(root, entries); });
      // Last, and after `shown`: an answer can arrive while this call is still running.
      if (opened) ask();
    }

    if (window.addEventListener) window.addEventListener("focus", function () { if (shown) ask(); });
    panel.section("setup", render, { pane: "setup" });
  });
