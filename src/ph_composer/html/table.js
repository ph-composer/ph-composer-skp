/* The shared record table: keyed rows patched in place, group headings, row icon actions, column resize and
   tooltips. It knows no record vocabulary: callers pass rows, columns, cell values and actions. */
PhComposerUI.define("table", ["dom", "icons", "overlay", "view_controls"],
  function (dom, icons, overlay, viewControls) {
  "use strict";
  var element = dom.element, button = dom.button, groupToggle = viewControls.groupToggle,
    paintGroupToggle = viewControls.paintGroupToggle;
  /* The columns table.css keeps sticky at the left edge, with the widths its custom properties default to. */
  var STICKY_WIDTHS = { hierarchy: 110, name: 220 };
  var DEFAULT_WIDTH = 140;
  var ARROW_KEYS = ["ArrowDown", "ArrowUp", "ArrowRight", "ArrowLeft"];

  function controls(entry, items, cache) {
    if (!entry.controls) entry.controls = {};
    var keep = {};
    items.forEach(function (item) {
      var control = entry.controls[item.id];
      keep[item.id] = true;
      if (!control) {
        control = { node: button("", function () {
          if (!control.node.disabled && cache.options.action) {
            cache.options.action(entry.row, control.item, control.node);
          }
        }) };
        control.node.className = "row-icon " + (item.id === "delete" ? "row-delete" : "");
        control.node.setAttribute("data-row-action", item.id);
        entry.controls[item.id] = control; entry.cells.actions.appendChild(control.node);
      }
      if (!control.item || control.item.icon !== item.icon) {
        control.node.innerHTML = icons.svgIcon(item.icon, 16);
      }
      control.item = item;
      // An action that starts a group (a contributor's, acting on something other than the record) is set apart.
      control.node.classList.toggle("row-icon-starts", Boolean(item.starts));
      control.node.setAttribute("aria-label", item.label);
      control.node.setAttribute("data-tooltip", item.label);
      control.node.disabled = Boolean(cache.options.disabled || item.disabled);
    });
    Object.keys(entry.controls).forEach(function (id) {
      if (!keep[id]) { entry.cells.actions.removeChild(entry.controls[id].node); delete entry.controls[id]; }
    });
  }
  function defaultColumnWidth(cache, field) {
    // The Actions column defaults to what its rows hold (table() measures it), not a generic column's width.
    var own = Object.prototype.hasOwnProperty.call(cache.defaultWidths, field);
    if (field === "actions" && cache.actionsWidth && !own) return cache.actionsWidth;
    return own ? cache.defaultWidths[field] : DEFAULT_WIDTH;
  }
  function minimumColumnWidth(cache, field) {
    var configured = cache.options.columnMinWidths && Number(cache.options.columnMinWidths[field]);
    var computed = window.getComputedStyle ?
      parseFloat(window.getComputedStyle(cache.headers[field]).minWidth) : 0;
    return Math.max(64, isFinite(configured) ? configured : 0, isFinite(computed) ? computed : 0);
  }
  function paintColumnWidth(cache, field) {
    var width = Number(cache.columnWidths[field]);
    var minimum = minimumColumnWidth(cache, field);
    width = Math.max(minimum, isFinite(width) && width > 0 ? Math.round(width) : defaultColumnWidth(cache, field));
    var value = width + "px";
    cache.columnElements[field].style.width = value;
    cache.headers[field].style.width = value;
    cache.headers[field].style.minWidth = "";
    if (Object.prototype.hasOwnProperty.call(cache.stickyWidths, field)) {
      cache.node.style.setProperty("--col-" + field + "-width", value);
    }
    cache.resizeHandles[field].setAttribute("aria-valuemin", String(minimum));
    cache.resizeHandles[field].setAttribute("aria-valuenow", String(width));
  }
  /* Fixed-layout tables otherwise squeeze unclaimed columns to almost nothing once the identity
     columns fill a narrow panel. Reserve every visible column's width and let the mount scroll. */
  function paintTableWidth(cache) {
    var width = cache.columns.reduce(function (total, column) {
      var field = column[0];
      if (cache.headers[field].hidden) return total;
      return total + (field === "actions" ? cache.actionsWidth : parseFloat(cache.columnElements[field].style.width));
    }, 0);
    cache.node.style.minWidth = width + "px";
  }
  function setColumnWidth(cache, field, width, source) {
    cache.columnWidths[field] = Math.max(minimumColumnWidth(cache, field), Math.min(480, Math.round(width)));
    paintColumnWidth(cache, field);
    paintTableWidth(cache);
    if (cache.options.columnResize) cache.options.columnResize(field, cache.columnWidths[field], source);
    return cache.columnWidths[field];
  }
  function resetColumnWidth(cache, field) {
    delete cache.columnWidths[field]; paintColumnWidth(cache, field);
    paintTableWidth(cache);
    if (cache.options.columnResize) cache.options.columnResize(field, null);
    if (cache.options.columnResizeEnd) cache.options.columnResizeEnd(field, null);
  }
  function attachColumnResize(cache, column) {
    var field = column[0], label = column[1];
    if (field === "actions") return;
    var handle = element("span", "phc-column-resizer");
    handle.tabIndex = 0; handle.setAttribute("role", "separator"); handle.setAttribute("aria-orientation", "vertical");
    handle.setAttribute("aria-label", "Resize " + label + " column");
    handle.setAttribute("aria-valuemin", "64"); handle.setAttribute("aria-valuemax", "480");
    handle.setAttribute("aria-keyshortcuts", "ArrowLeft ArrowRight Enter");
    dom.tooltip(handle, "Drag to resize. Use Left or Right Arrow; Enter resets.");
    function currentWidth() {
      var box = cache.headers[field].getBoundingClientRect();
      return Number(cache.columnWidths[field]) || Number(box.width) || defaultColumnWidth(cache, field);
    }
    handle.addEventListener("mousedown", function (event) {
      if (event.button !== undefined && event.button !== 0) return;
      event.preventDefault(); event.stopPropagation();
      var start = currentWidth(), startX = event.clientX;
      var moved = false;
      function move(moveEvent) {
        moved = true; setColumnWidth(cache, field, start + moveEvent.clientX - startX, "pointer");
      }
      function finish() {
        document.removeEventListener("mousemove", move); document.removeEventListener("mouseup", finish);
        if (window.removeEventListener) window.removeEventListener("blur", finish);
        if (document.body && document.body.classList) document.body.classList.remove("phc-column-resizing");
        if (moved && cache.options.columnResizeEnd) cache.options.columnResizeEnd(field, cache.columnWidths[field]);
      }
      if (document.body && document.body.classList) document.body.classList.add("phc-column-resizing");
      document.addEventListener("mousemove", move); document.addEventListener("mouseup", finish);
      if (window.addEventListener) window.addEventListener("blur", finish);
    });
    handle.addEventListener("dblclick", function (event) {
      event.preventDefault(); event.stopPropagation(); resetColumnWidth(cache, field);
    });
    handle.addEventListener("keydown", function (event) {
      if (event.key === "Enter" || event.key === " ") {
        event.preventDefault(); event.stopPropagation(); resetColumnWidth(cache, field); return;
      }
      if (event.key !== "ArrowLeft" && event.key !== "ArrowRight") return;
      event.preventDefault(); event.stopPropagation();
      setColumnWidth(cache, field, currentWidth() + (event.key === "ArrowLeft" ? -12 : 12), "keyboard");
    });
    cache.resizeHandles[field] = handle;
  }
  function buildCache(root, tableColumns, options) {
    var node = element("table", "phc-table"), columnGroup = element("colgroup"),
      head = element("thead"), header = element("tr");
    var headers = Object.create(null), columnElements = Object.create(null);
    tableColumns.forEach(function (column) {
      var columnElement = element("col", "col-" + column[0]);
      var th = element("th", "col-" + column[0]);
      th._heading = element("span", "phc-header-label-row");
      th._label = element("span", "phc-th-label", column[1]);
      th._labelText = column[1];
      dom.tooltip(th._label, column[1]);
      th._heading.appendChild(th._label);
      th.appendChild(th._heading);
      columnElements[column[0]] = columnElement; columnGroup.appendChild(columnElement);
      th.scope = "col"; headers[column[0]] = th; header.appendChild(th);
    });
    head.appendChild(header); node.appendChild(columnGroup); node.appendChild(head);
    var stickyWidths = options.stickyWidths || STICKY_WIDTHS;
    var cache = { node: node, headers: headers, columnElements: columnElements,
      resizeHandles: Object.create(null), body: element("tbody"),
      rows: Object.create(null), columns: tableColumns, columnWidths: options.columnWidths || {},
      stickyWidths: stickyWidths,
      defaultWidths: Object.assign({}, stickyWidths, options.defaultWidths || {}),
      groups: Object.create(null), empty: element("p", "phc-empty") };
    tableColumns.forEach(function (column) { attachColumnResize(cache, column); });
    cache.resetColumnWidths = function () {
      Object.keys(cache.columnWidths).forEach(function (field) { delete cache.columnWidths[field]; });
      cache.columns.forEach(function (column) {
        if (cache.resizeHandles[column[0]]) paintColumnWidth(cache, column[0]);
      });
      paintTableWidth(cache);
      if (cache.options.columnResize) cache.options.columnResize(null, null);
      if (cache.options.columnResizeEnd) cache.options.columnResizeEnd(null, null);
    };
    node.appendChild(cache.body); root.replaceChildren(node, cache.empty); root._table = cache;
    overlay.attachTooltip(root);
    return cache;
  }
  function paintHeaders(cache, options) {
    cache.node.classList.toggle("has-header-action-row", Boolean(options.headerActions));
    var anyActions = false;
    cache.columns.forEach(function (column) {
      var field = column[0], th = cache.headers[field];
      if (th._labelText !== column[1]) {
        th._label.textContent = column[1];
        dom.tooltip(th._label, column[1]);
        th._labelText = column[1];
      }
      if (options.header) options.header(th, field);
      var actions = options.headerActions ? options.headerActions(field) || [] : [];
      if (actions.length) anyActions = true;
      paintHeaderActions(th, actions, Boolean(options.headerActions));
      var hidden = Boolean(options.hiddenColumns && options.hiddenColumns[field]);
      th.hidden = hidden; cache.columnElements[field].hidden = hidden;
      cache.columnElements[field].style.display = hidden ? "none" : "";
      var handle = cache.resizeHandles[field];
      if (handle) {
        handle.setAttribute("aria-label", "Resize " + column[1] + " column");
        if (handle.parentNode !== th) th.appendChild(handle);
        paintColumnWidth(cache, field);
      }
    });
    // A table whose columns hold no actions right now keeps the compact one-band header.
    cache.node.classList.toggle("is-actionless", !anyActions);
  }
  /* A row's checkbox, first in its Actions cell, and the header's in the Actions header. `options.check` is
     { state(row) -> true | false | "mixed" | null (no box), toggle(row, event), header() -> true | false |
     "mixed", toggleAll(event), label(row), headerLabel(value) optional, any() }. Checking is the caller's view
     state, so a box stays usable while the table's edits are busy; the caller owns what is checked and the
     table only paints it. A row whose box is checked takes `is-checked`; while any row is, every row shows its box. */
  function checkbox(label, onClick) {
    var box = element("input", "row-check");
    box.type = "checkbox"; box.setAttribute("type", "checkbox");
    box.setAttribute("aria-label", label);
    box.addEventListener("click", function (event) { onClick(event); });
    return box;
  }
  function paintCheck(box, value, label) {
    box.checked = value === true;
    box.indeterminate = value === "mixed";
    box.setAttribute("aria-checked", value === "mixed" ? "mixed" : String(value === true));
    box.setAttribute("aria-label", label);
  }
  function paintRowCheck(cache, entry, row) {
    var check = cache.options.check, value = check ? check.state(row) : null;
    if (value === null || value === undefined) {
      if (entry.check) { entry.check.parentNode.removeChild(entry.check); entry.check = null; }
      return false;
    }
    if (!entry.check) {
      entry.check = checkbox("", function (event) { cache.options.check.toggle(entry.row, event); });
      entry.cells.actions.insertBefore(entry.check, entry.cells.actions.firstChild);
    }
    paintCheck(entry.check, value, check.label(row));
    return value === true;
  }
  function paintHeaderCheck(cache) {
    var check = cache.options.check, th = cache.headers.actions;
    if (!th) return;
    if (!check) {
      if (cache.headerCheck) { th._heading.removeChild(cache.headerCheck); cache.headerCheck = null; }
      return;
    }
    if (!cache.headerCheck) {
      cache.headerCheck = checkbox("", function (event) { cache.options.check.toggleAll(event); });
      th._heading.insertBefore(cache.headerCheck, th._label);
    }
    var value = check.header();
    paintCheck(cache.headerCheck, value, check.headerLabel ? check.headerLabel(value) :
      value === true ? "Uncheck every row shown" : "Check every row shown");
    cache.node.classList.toggle("has-checked", Boolean(check.any()));
  }
  /* A column's header actions: `options.headerActions(field)` answers `[{ node, persistent }]`, nodes the caller
     built and repaints (a menu, a toggle). The table keeps them in a shallow band beneath the label, shows them only
     while the pointer is over the header or focus is inside it, and keeps a `persistent` one (a pressed
     toggle, an active filter) visible at rest (table.css). It names no action. */
  function paintHeaderActions(th, actions, reserveRow) {
    if (!actions.length && !th._actions && !reserveRow) return;
    if (!th._actions) {
      th._actions = element("span", "phc-header-actions");
      th.insertBefore(th._actions, th._heading.nextSibling);
    }
    actions.forEach(function (action, index) {
      action.node.classList.add("phc-header-action");
      action.node.classList.toggle("is-persistent", Boolean(action.persistent));
      if (th._actions.children[index] !== action.node) {
        th._actions.insertBefore(action.node, th._actions.children[index] || null);
      }
    });
    while (th._actions.children.length > actions.length) th._actions.removeChild(th._actions.lastChild);
    th.classList.toggle("has-header-actions", actions.length > 0);
  }
  /* Places the heading for row's group once, before its first row; returns the next body position. */
  function paintGroups(cache, group, retainedGroups, position) {
    if (!group || retainedGroups[group.key]) return position;
    retainedGroups[group.key] = true;
    var heading = cache.groups[group.key];
    if (!heading) {
      heading = groupToggle(function () { cache.options.toggleGroup(group.key); });
      heading.node = element("tr", "phc-group-row");
      var groupCell = element("td"); groupCell.colSpan = cache.columns.length;
      groupCell.appendChild(heading.button); heading.node.appendChild(groupCell); cache.groups[group.key] = heading;
    }
    paintGroupToggle(heading, group);
    if (cache.body.children[position] !== heading.node) {
      cache.body.insertBefore(heading.node, cache.body.children[position] || null);
    }
    return position + 1;
  }
  function rowLabel(row) { return row.record.name || row.record.display_name; }
  /* "Zone Attic", but "Zone 1" rather than "Zone Zone 1" when the name already says what the row is. */
  function rowTitle(row) {
    var label = rowLabel(row) || "";
    return label.indexOf(row.tier + " ") === 0 || label === row.tier ? label : (row.tier + " " + label).trim();
  }
  function navigateRows(root, cache, expanded, entry, event) {
    if (ARROW_KEYS.indexOf(event.key) === -1) return;
    var targets = Array.prototype.slice.call(cache.body.querySelectorAll(".row-target"));
    var index = targets.indexOf(entry.target);
    // A row with nothing under it has nothing to open, so Left goes straight to its parent.
    var opens = entry.row.depth < tiers(cache) && !(cache.options.expandable && !cache.options.expandable(entry.row));
    var next;
    if (event.key === "ArrowDown") next = targets[index + 1];
    else if (event.key === "ArrowUp") next = targets[index - 1];
    else if (event.key === "ArrowRight") {
      if (opens && !entry.open && mayToggle(cache, entry)) {
        expanded[entry.row.key] = true; table(root, cache.records, cache.options);
      } else if (opens && targets[index + 1]) next = targets[index + 1];
    } else if (opens && entry.open && mayToggle(cache, entry)) {
      expanded[entry.row.key] = false; table(root, cache.records, cache.options);
    } else if (entry.row.parent) next = cache.rows[entry.row.parent].target;
    event.preventDefault();
    if (next) next.focus();
  }
  /* Whether a row may open or shut: `options.mayToggle(row, opening)`, when given, answers (and says why not). */
  function mayToggle(cache, entry) {
    return !cache.options.mayToggle || cache.options.mayToggle(entry.row, !entry.open) !== false;
  }
  /* How many tree levels open: rows at a shallower depth carry a chevron. `options.tiers`, 2 by default
     (a Zone and the summary rows beneath it); a tree four deep (Zone, Space, Volume, Floor Segment) passes 3. */
  function tiers(cache) {
    return cache.options && cache.options.tiers ? cache.options.tiers : 2;
  }
  function buildRow(root, cache, expanded, row) {
    var entry = { node: element("tr", "tier-" + row.depth), cells: {} };
    entry.node.setAttribute("data-row-key", row.key);
    cache.rows[row.key] = entry;
    cache.columns.forEach(function (column) {
      var td = element("td", "col-" + column[0]);
      entry.cells[column[0]] = td; entry.node.appendChild(td);
    });
    var hierarchy = entry.cells.hierarchy;
    // Built when the row first sits at a depth that opens. A row can change depth and keep its key (a
    // Face that gains a record moves up under its Zone), so paintRow asks for it again.
    entry.needChevron = function () {
      if (entry.chevron || !hierarchy) return;
      entry.chevron = button("", function () {
        if (!mayToggle(cache, entry)) return;
        expanded[entry.row.key] = !entry.open;
        table(root, cache.records, cache.options);
        entry.chevron.focus();
      });
      entry.chevron.className = "row-chevron";
      entry.chevron.innerHTML = icons.ROW_CHEVRON;
      hierarchy.insertBefore(entry.chevron, hierarchy.firstChild);
    };
    if (row.depth < tiers(cache)) entry.needChevron();
    if (hierarchy) {
      entry.target = button(row.tier, function () { if (cache.options.inspect) cache.options.inspect(entry.row); });
      entry.target.className = "row-target";
      entry.target.addEventListener("keydown", function (event) { navigateRows(root, cache, expanded, entry, event); });
      hierarchy.appendChild(entry.target);
    }
    return entry;
  }
  function paintCells(cache, entry, row, options) {
    cache.columns.forEach(function (column) {
      var field = column[0];
      var td = entry.cells[field];
      td.hidden = Boolean(options.hiddenColumns && options.hiddenColumns[field]);
      if (field === "hierarchy" || field === "actions") return;
      var text = options.value(row, field);
      if (options.cell && options.cell(td, row, field, text)) return;
      text = text === undefined || text === null ? "-" : String(text);
      if (td.textContent !== text) td.textContent = text;
      dom.tooltip(td, text);
      if (text === "-") td.setAttribute("aria-label", "Unavailable");
      else td.removeAttribute("aria-label");
      if (options.decorate) options.decorate(td, row, field, text);
    });
  }
  /* Paints one row's state, actions, marker and cells; returns the number of row actions. */
  function paintRow(cache, entry, row, isOpen, rowHidden, group) {
    var options = cache.options;
    entry.node.hidden = Boolean(rowHidden || (group && group.collapsed));
    entry.row = row; entry.open = isOpen;
    if (entry.target) {
      entry.target.setAttribute("aria-label",
        row.tier + " " + (rowLabel(row) || "") + ". Select; arrow keys navigate rows.");
    }
    var actions = options.actions ? options.actions(row) : [];
    controls(entry, actions, cache);
    if (options.actionsCell) options.actionsCell(entry.cells.actions, row);
    var selected = options.selected && options.selected(row);
    var checked = paintRowCheck(cache, entry, row);
    entry.node.className = "tier-" + row.depth + (selected ? " host-selected" : "") +
      (checked ? " is-checked" : "");
    if (row.depth < tiers(cache)) entry.needChevron();
    if (entry.target) entry.target.disabled = Boolean(options.disabled);
    if (entry.chevron) {
      entry.chevron.hidden = row.depth >= tiers(cache);
      // A row with nothing under it keeps the chevron's place, so its label lines up, but offers nothing to open.
      var leaf = Boolean(options.expandable && !options.expandable(row));
      entry.chevron.classList.toggle("is-leaf", leaf);
      entry.chevron.disabled = leaf;
      entry.chevron.setAttribute("aria-label", (isOpen ? "Collapse " : "Expand ") + rowTitle(row));
      entry.chevron.setAttribute("aria-expanded", String(isOpen));
    }
    if (entry.cells.hierarchy && options.marker) {
      var marker = options.marker(row);
      if (marker) {
        if (!entry.marker) {
          entry.marker = element("span", "phc-row-marker"); entry.cells.hierarchy.appendChild(entry.marker);
        }
        // An `icon` marker shows a glyph where a word would not fit; its words stay in tooltip and label.
        if (marker.icon) entry.marker.replaceChildren(icons.glyph(marker.icon));
        else entry.marker.textContent = marker.text;
        entry.marker.classList.toggle("is-icon", Boolean(marker.icon));
        entry.marker.setAttribute("data-tooltip", marker.tooltip); entry.marker.hidden = false;
        entry.marker.setAttribute("role", "img");
        entry.marker.setAttribute("aria-label", marker.tooltip);
      } else if (entry.marker) entry.marker.hidden = true;
    }
    paintCells(cache, entry, row, options);
    return actions.length;
  }
  /* A re-render keeps focus on the control that had it, unless that control is now hidden. */
  function restoreFocus(root, focused, hadFocus) {
    if (!hadFocus || document.activeElement === focused || !root.contains(focused)) return;
    for (var ancestor = focused; ancestor; ancestor = ancestor.parentNode) { if (ancestor.hidden) return; }
    focused.focus({ preventScroll: true });
  }
  /* options: rows, columns, value(row, field) and empty are required; `tree: true` styles top-level rows as
     group headings; see the callers for the other optional hooks. */
  /* Numbers read from the right; words and chips from the left. A column's own cells decide which it holds, so
     a screen states no alignment and its heading always agrees with its values. */
  var NUMBER = /^[\u2212+-]?\d[\d\s.,]*(\s*[^\d\s]{1,12})?$/;
  var LEADING = { actions: true, hierarchy: true, name: true };
  var QUANTITY_LABEL = new RegExp("(\\s(mm|m|m²|m³|in|ft|ft²|ft³|kg|W/K)$|W/\\(|/\\(|factor|count|quantity|runs|" +
    "thickness|length|area|value|\u03c8|\u03bb|emissivity|density|conductivity|heat)", "i");
  function columnKind(cells) {
    var kind = null;
    for (var index = 0; index < cells.length && index < 12; index += 1) {
      var cell = cells[index];
      if (cell.classList.contains("is-numeric")) return "number";
      if (cell.querySelector("select, .phc-enum-pill, input:not([type=checkbox])")) return "text";
      var text = (cell.textContent || "").trim();
      if (!text || text === "\u2014" || text === "-" || text === "?") continue;
      if (!NUMBER.test(text)) return "text";
      kind = "number";
    }
    return kind || "text";
  }
  function alignColumns(cache) {
    cache.columns.forEach(function (column) {
      var field = column[0], th = cache.headers[field];
      if (!th || LEADING[field]) return;
      var cells = cache.body.querySelectorAll("tr:not(.phc-group-row) > td.col-" + field);
      // With no rows yet, a heading that names a quantity or a unit still reads from the right, so a column
      // keeps its alignment from the empty Model to the full one.
      if (!cells.length) { th.classList.toggle("is-end", QUANTITY_LABEL.test(column[1] || "")); return; }
      var text = columnKind(cells) === "text";
      th.classList.toggle("is-end", !text);
      Array.prototype.forEach.call(cells, function (cell) {
        cell.classList.toggle("is-start", text);
        // A cell showing a chip lets the chip carry its state (a flag), not the whole cell.
        cell.classList.toggle("has-chip", Boolean(cell.querySelector("select.phc-enum-cell, .phc-enum-pill")));
      });
    });
  }
  function table(root, records, options) {
    var focused = document.activeElement, hadFocus = focused && root.contains(focused);
    var rows = options.rows, expanded = options.expanded || Object.create(null);
    var visible = Object.create(null), retained = Object.create(null), retainedGroups = Object.create(null);
    var cache = root._table || buildCache(root, options.columns, options);
    var position = 0, actionCount = 0;
    cache.options = options; cache.records = records; cache.columns = options.columns;
    // A tree's top-level rows head their groups (table.css).
    cache.node.classList.toggle("is-tree", Boolean(options.tree));
    // Row icons that show only on hover or focus, for a screen whose rows carry them as quiet affordances.
    cache.node.classList.toggle("reveals-row-actions", Boolean(options.revealRowActions));
    if (options.columnWidths) cache.columnWidths = options.columnWidths;
    paintHeaders(cache, options);
    paintHeaderCheck(cache);
    cache.empty.hidden = (options.visibleCount === undefined ? rows.length : options.visibleCount) > 0;
    // An empty table draws no scroll shade: there is nothing beyond its edge to read.
    root.classList.toggle("is-empty-table", !cache.empty.hidden);
    cache.empty.textContent = options.empty || "No records.";
    rows.forEach(function (row) {
      var group = options.group ? options.group(row) : null;
      position = paintGroups(cache, group, retainedGroups, position);
      var isOpen = Object.prototype.hasOwnProperty.call(expanded, row.key) ? expanded[row.key] : row.depth === 0;
      var rowHidden = Boolean(options.rowHidden && options.rowHidden(row));
      retained[row.key] = true;
      if (row.parent && !visible[row.parent]) return;
      visible[row.key] = !rowHidden && isOpen;
      var entry = cache.rows[row.key] || buildRow(root, cache, expanded, row);
      actionCount = Math.max(actionCount, paintRow(cache, entry, row, isOpen, rowHidden, group));
      if (cache.body.children[position] !== entry.node) {
        cache.body.insertBefore(entry.node, cache.body.children[position] || null);
      }
      position += 1;
    });
    // The Actions column is as wide as what its rows hold. A column holding only the row checkbox shrinks to it
    // and drops its heading word; one with icons keeps room for the word "Actions".
    var checkOnly = actionCount === 0 && !options.actionsCell && Boolean(options.check);
    cache.actionsWidth = Math.max(16 + actionCount * 32 + (options.actionsCell ? 40 : 0) + (options.check ? 28 : 0),
      checkOnly ? 44 : 80);
    cache.node.classList.toggle("has-check-only-actions", checkOnly);
    if (cache.resizeHandles.actions) paintColumnWidth(cache, "actions");
    var actionsVisible = cache.headers.actions && !cache.headers.actions.hidden;
    root.style.setProperty("--row-actions-width", (actionsVisible ? cache.actionsWidth : 0) + "px");
    paintTableWidth(cache);
    while (cache.body.children.length > position) cache.body.removeChild(cache.body.lastChild);
    alignColumns(cache);
    // The edge shade marks only a table that truly runs past its frame.
    root.classList.toggle("is-overflowing", root.scrollWidth - root.clientWidth > 8);
    Object.keys(cache.rows).forEach(function (key) {
      if (!retained[key]) { delete cache.rows[key]; delete expanded[key]; }
    });
    Object.keys(cache.groups).forEach(function (key) { if (!retainedGroups[key]) delete cache.groups[key]; });
    restoreFocus(root, focused, hadFocus);
    root._checkTooltip();
    // After every paint, the caller's own included, a row opened or shut from its chevron among them.
    if (options.painted) options.painted();
  }


  return { table: table, STICKY_WIDTHS: STICKY_WIDTHS };
});
