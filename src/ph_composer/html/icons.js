/* The icon registry. Every icon name the panel renders is a key here; an unknown name throws at render
   rather than painting an empty button, and tests/icons_test.js scans the literal names in html/. */
/* eslint max-len: ["error", { "code": 120, "ignoreStrings": true }] -- SVG path data is one string per icon. */
PhComposerUI.define("icons", ["dom"], function (dom) {
  "use strict";
  var element = dom.element, button = dom.button;
  var ICONS = {
    add: '<path d="M12 4v16M4 12h16"/>',
    group_add: '<path d="M3 6h7l2 2h9v11H3Z"/><path d="M12 11v6m-3-3h6"/>',
    ungroup: '<rect width="8" height="6" x="5" y="4" rx="1"/><rect width="8" height="6" x="11" y="14" rx="1"/>',
    sort: '<path d="M8 6h12M8 12h8M8 18h4M4 5v14m-2-2 2 2 2-2"/>',
    sort_ascending: '<path d="m3 8 4-4 4 4M7 4v16M11 12h4M11 16h7M11 20h10"/>',
    sort_descending: '<path d="m3 16 4 4 4-4M7 20V4M11 4h10M11 8h7M11 12h4"/>',
    material_add: '<path d="M5 3h9l5 5v13H5ZM14 3v6h5M8 15h8m-4-4v8"/>',
    stop: '<rect x="6" y="6" width="12" height="12" rx="1"/>',
    refresh: '<path d="M20 4v6h-6M4 20v-6h6M5.6 8a7 7 0 0 1 11.6-2L20 10M4 14l2.8 4A7 7 0 0 0 18.4 16"/>',
    select_faces: '<path d="M8 3H3v5m0 4v5h5m4-14h5v5" stroke-dasharray="2 2"/><path d="m11 10 10 5-5 1-1 5Z"/>',
    enter: '<path d="M10 3h10v18H10M3 12h12m-4-4 4 4-4 4"/>',
    close: '<path d="M10 3h10v18H10M15 12H3m4-4-4 4 4 4"/>',
    locate: '<circle cx="12" cy="12" r="6"/><path d="M12 2v3m0 14v3M2 12h3m14 0h3"/><circle cx="12" cy="12" r="1" fill="currentColor" stroke="none"/>',
    delete: '<path d="M4 6h16M9 6V3h6v3M6 6l1 15h10l1-15M10 10v7m4-7v7"/>',
    replace: '<path d="M14 4a2 2 0 0 1 2-2m0 8a2 2 0 0 1-2-2m6-6a2 2 0 0 1 2 2m0 4a2 2 0 0 1-2 2M3 7l3 3 3-3M6 10V5a3 3 0 0 1 3-3h1"/>' +
      '<rect x="2" y="14" width="8" height="8" rx="2"/>',
    repair: '<path d="m15 3-3 3 1 4 4 1 3-3a6 6 0 0 1-7 8l-6 6-4-4 6-6a6 6 0 0 1 6-9Z"/>',
    duplicate: '<path d="M8 8h12v12H8zM4 4h12v4M4 4v12h4"/>',
    variant: '<path d="M12 3v18M3 12h18M5 5l14 14M19 5 5 19"/>',
    sidebar: '<rect x="3" y="4" width="18" height="16" rx="2"/><path d="M9 4v16"/>',
    database: '<ellipse cx="12" cy="5" rx="8" ry="3"/><path d="M4 5v14c0 4 16 4 16 0V5M4 12c0 4 16 4 16 0"/>',
    document: '<path d="M5 3h9l5 5v13H5ZM14 3v6h5M8 13h8M8 17h8"/>',
    search: '<circle cx="10" cy="10" r="6"/><path d="m15 15 6 6"/>',
    chevron: '<path d="m6 9 6 6 6-6"/>',
    arrow_up: '<path d="m5 12 7-7 7 7"/><path d="M12 19V5"/>',
    arrow_down: '<path d="M12 5v14"/><path d="m19 12-7 7-7-7"/>',
    material_in_file: '<path d="M5 3h9l5 5v13H5ZM14 3v6h5"/><rect x="9" y="12" width="6" height="6" rx="1" fill="currentColor" stroke="none"/>',
    check_circle: '<circle cx="12" cy="12" r="9"/><path d="m7 12 3 3 7-7"/>',
    /* Drawing toolbar glyphs from Lucide (https://lucide.dev), matching BLDGTYP's web application.
       ISC License. Copyright (c) 2026 Lucide Icons and Contributors. Permission to use, copy, modify,
       and/or distribute this software for any purpose with or without fee is hereby granted, provided
       that the above copyright notice and this permission notice appear in all copies. THE SOFTWARE IS
       PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES WITH REGARD TO THIS SOFTWARE INCLUDING ALL
       IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR ANY
       SPECIAL, DIRECT, INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES WHATSOEVER RESULTING FROM LOSS OF
       USE, DATA OR PROFITS, WHETHER IN AN ACTION OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS ACTION, ARISING
       OUT OF OR IN CONNECTION WITH THE USE OR PERFORMANCE OF THIS SOFTWARE. */
    settings: '<path d="M12.22 2h-.44a2 2 0 0 0-2 2v.18a2 2 0 0 1-1 1.73l-.43.25a2 2 0 0 1-2 0l-.15-.08a2 2 0 0 0-2.73.73l-.22.38a2 2 0 0 0 .73 2.73l.15.1a2 2 0 0 1 1 1.72v.51a2 2 0 0 1-1 1.74l-.15.09a2 2 0 0 0-.73 2.73l.22.38a2 2 0 0 0 2.73.73l.15-.08a2 2 0 0 1 2 0l.43.25a2 2 0 0 1 1 1.73V20a2 2 0 0 0 2 2h.44a2 2 0 0 0 2-2v-.18a2 2 0 0 1 1-1.73l.43-.25a2 2 0 0 1 2 0l.15.08a2 2 0 0 0 2.73-.73l.22-.39a2 2 0 0 0-.73-2.73l-.15-.08a2 2 0 0 1-1-1.74v-.5a2 2 0 0 1 1-1.74l.15-.09a2 2 0 0 0 .73-2.73l-.22-.38a2 2 0 0 0-2.73-.73l-.15.08a2 2 0 0 1-2 0l-.43-.25a2 2 0 0 1-1-1.73V4a2 2 0 0 0-2-2z"/><circle cx="12" cy="12" r="3"/>',
    info: '<circle cx="12" cy="12" r="10"/><path d="M12 16v-4"/><path d="M12 8h.01"/>',
    // Lucide copy-minus and copy-plus: the one Collapse all / Expand all toggle of the shared view controls.
    copy_minus: '<line x1="12" x2="18" y1="15" y2="15"/><rect width="14" height="14" x="8" y="8" rx="2" ry="2"/><path d="M4 16c-1.1 0-2-.9-2-2V4c0-1.1.9-2 2-2h10c1.1 0 2 .9 2 2"/>',
    copy_plus: '<line x1="15" x2="15" y1="12" y2="18"/><line x1="12" x2="18" y1="15" y2="15"/><rect width="14" height="14" x="8" y="8" rx="2" ry="2"/><path d="M4 16c-1.1 0-2-.9-2-2V4c0-1.1.9-2 2-2h10c1.1 0 2 .9 2 2"/>',
    // Lucide columns-3 and tag: the Columns and Labels menus of the Zones control row.
    columns: '<rect width="18" height="18" x="3" y="3" rx="2"/><path d="M9 3v18"/><path d="M15 3v18"/>',
    tag: '<path d="M12.586 2.586A2 2 0 0 0 11.172 2H4a2 2 0 0 0-2 2v7.172a2 2 0 0 0 .586 1.414l8.704 8.704a2.426 2.426 0 0 0 3.42 0l6.58-6.58a2.426 2.426 0 0 0 0-3.42z"/><circle cx="7.5" cy="7.5" r=".5" fill="currentColor"/>',
    help: '<circle cx="12" cy="12" r="10"/><path d="M9.09 9a3 3 0 0 1 5.83 1c0 2-3 3-3 3"/><path d="M12 17h.01"/>',
    link: '<path d="M10 13a5 5 0 0 0 7.54.54l3-3a5 5 0 0 0-7.07-7.07l-1.72 1.71"/><path d="M14 11a5 5 0 0 0-7.54-.54l-3 3a5 5 0 0 0 7.07 7.07l1.71-1.71"/>',
    zoom_out: '<circle cx="11" cy="11" r="8"/><path d="m21 21-4.35-4.35"/><path d="M8 11h6"/>',
    zoom_in: '<circle cx="11" cy="11" r="8"/><path d="m21 21-4.35-4.35"/><path d="M11 8v6"/><path d="M8 11h6"/>',
    fit: '<path d="M15 3h6v6"/><path d="m21 3-7 7"/><path d="m3 21 7-7"/><path d="M9 21H3v-6"/>',
    pan: '<path d="M18 11V6a2 2 0 0 0-4 0"/><path d="M14 10V4a2 2 0 0 0-4 0v2"/><path d="M10 10.5V6a2 2 0 0 0-4 0v8"/><path d="M18 8a2 2 0 1 1 4 0v6a8 8 0 0 1-8 8h-2c-2.8 0-4.5-.86-5.99-2.34l-3.6-3.6a2 2 0 0 1 2.83-2.82L7 15"/>',
    clear: '<path d="M18 6 6 18"/><path d="m6 6 12 12"/>',
    merge: '<path d="M14 3a1 1 0 0 1 1 1v5a1 1 0 0 1-1 1"/><path d="M19 3a1 1 0 0 1 1 1v5a1 1 0 0 1-1 1"/><path d="m7 15 3 3"/><path d="m7 21 3-3H5a2 2 0 0 1-2-2v-2"/><rect x="14" y="14" width="7" height="7" rx="1"/><rect x="3" y="3" width="7" height="7" rx="1"/>',
    split: '<circle cx="6" cy="6" r="3"/><path d="M8.12 8.12 12 12"/><path d="M20 4 8.12 15.88"/><circle cx="6" cy="18" r="3"/><path d="M14.8 14.8 20 20"/>',
    glazed: '<rect x="3" y="3" width="18" height="18" rx="2"/><path d="m8 14 6-6"/>',
    empty: '<path d="M5 3a2 2 0 0 0-2 2"/><path d="M19 3a2 2 0 0 1 2 2"/><path d="M21 19a2 2 0 0 1-2 2"/><path d="M5 21a2 2 0 0 1-2-2"/><path d="M9 3h1"/><path d="M9 21h1"/><path d="M14 3h1"/><path d="M14 21h1"/><path d="M3 9v1"/><path d="M21 9v1"/><path d="M3 14v1"/><path d="M21 14v1"/>',
    mirror: '<path d="M8 3 4 7l4 4"/><path d="M4 7h16"/><path d="m16 21 4-4-4-4"/><path d="M20 17H4"/>',
    eyedropper: '<path d="m12 9-8.414 8.414A2 2 0 0 0 3 18.828v1.344a2 2 0 0 1-.586 1.414A2 2 0 0 1 3.828 21h1.344a2 2 0 0 0 1.414-.586L15 12"/><path d="m18 9 .4.4a1 1 0 1 1-3 3l-3.8-3.8a1 1 0 1 1 3-3l.4.4 3.4-3.4a1 1 0 1 1 3 3z"/><path d="m2 22 .414-.414"/>',
    paint_bucket: '<path d="M11 7 6 2"/><path d="M18.992 12H2.041"/><path d="M21.145 18.38A3.34 3.34 0 0 1 20 16.5a3.3 3.3 0 0 1-1.145 1.88c-.575.46-.855 1.02-.855 1.595A2 2 0 0 0 20 22a2 2 0 0 0 2-2.025c0-.58-.285-1.13-.855-1.595"/><path d="m8.5 4.5 2.148-2.148a1.205 1.205 0 0 1 1.704 0l7.296 7.296a1.205 1.205 0 0 1 0 1.704l-7.592 7.592a3.615 3.615 0 0 1-5.112 0l-3.888-3.888a3.615 3.615 0 0 1 0-5.112L5.67 7.33"/>',
    filter: '<path d="M3 6h18"/><path d="M7 12h10"/><path d="M10 18h4"/>',
    palette: '<path d="M12 22a1 1 0 0 1 0-20 10 9 0 0 1 10 9 5 5 0 0 1-5 5h-2.25a1.75 1.75 0 0 0-1.4 2.8l.3.4a1.75 1.75 0 0 1-1.4 2.8z"/><circle cx="13.5" cy="6.5" r=".5" fill="currentColor"/><circle cx="17.5" cy="10.5" r=".5" fill="currentColor"/><circle cx="6.5" cy="12.5" r=".5" fill="currentColor"/><circle cx="8.5" cy="7.5" r=".5" fill="currentColor"/>',
    eye: '<path d="M2.062 12.348a1 1 0 0 1 0-.696 10.75 10.75 0 0 1 19.876 0 1 1 0 0 1 0 .696 10.75 10.75 0 0 1-19.876 0"/><circle cx="12" cy="12" r="3"/>',
    undo: '<path d="M3 12a9 9 0 1 0 9-9 9.75 9.75 0 0 0-6.74 2.74L3 8"/><path d="M3 3v5h5"/>',
    installs: '<path d="M4 5h16v14H4Z"/><path d="M8 5v14M16 5v14M4 9h4m8 6h4"/>',
    anchor: '<circle cx="12" cy="12" r="7"/><circle cx="12" cy="12" r="2"/><path d="M12 2v3m0 14v3M2 12h3m14 0h3"/>',
    more: '<circle cx="5" cy="12" r="1.5" fill="currentColor" stroke="none"/><circle cx="12" cy="12" r="1.5" fill="currentColor" stroke="none"/><circle cx="19" cy="12" r="1.5" fill="currentColor" stroke="none"/>',
    ruler: '<path d="M4 17 17 4l3 3L7 20Z"/><path d="m14 7 3 3M11 10l2 2M8 13l3 3"/>',
    assign: '<rect x="3" y="5" width="8" height="8" rx="1"/><path d="M7 13v6h13V8h-6m1 6h5m-2.5-2.5L20 14l-2.5 2.5"/>'
    ,fill_down: '<path d="M5 4h14v5H5Z"/><path d="M12 11v9m-4-4 4 4 4-4"/>'
    ,fill_right: '<path d="M4 5h5v14H4Z"/><path d="M11 12h9m-4-4 4 4-4 4"/>'
    ,alert: '<path d="M12 4 3 20h18Z"/><path d="M12 10v4m0 3v.01"/>'
    ,grip: '<circle cx="9" cy="9" r="1.5" fill="currentColor" stroke="none"/><circle cx="15" cy="9" r="1.5" fill="currentColor" stroke="none"/><circle cx="9" cy="15" r="1.5" fill="currentColor" stroke="none"/><circle cx="15" cy="15" r="1.5" fill="currentColor" stroke="none"/>'
    ,grip_vertical: '<circle cx="9" cy="5" r="1.5" fill="currentColor" stroke="none"/><circle cx="15" cy="5" r="1.5" fill="currentColor" stroke="none"/><circle cx="9" cy="12" r="1.5" fill="currentColor" stroke="none"/><circle cx="15" cy="12" r="1.5" fill="currentColor" stroke="none"/><circle cx="9" cy="19" r="1.5" fill="currentColor" stroke="none"/><circle cx="15" cy="19" r="1.5" fill="currentColor" stroke="none"/>'
    ,info: '<circle cx="12" cy="12" r="10"/><path d="M12 16v-4"/><path d="M12 8h.01"/>'
    ,check: '<path d="M20 6 9 17l-5-5"/>'
    ,star: '<path d="M11.525 2.295a.53.53 0 0 1 .95 0l2.31 4.679a2.123 2.123 0 0 0 1.595 1.16l5.166.756a.53.53 0 0 1 .294.904l-3.736 3.638a2.123 2.123 0 0 0-.611 1.878l.882 5.14a.53.53 0 0 1-.771.56l-4.618-2.428a2.122 2.122 0 0 0-1.973 0L6.396 21.01a.53.53 0 0 1-.77-.56l.881-5.139a2.122 2.122 0 0 0-.611-1.879L2.16 9.795a.53.53 0 0 1 .294-.906l5.165-.755a2.122 2.122 0 0 0 1.597-1.16z"/>'
    ,pencil: '<path d="M21.174 6.812a1 1 0 0 0-3.986-3.987L3.842 16.174a2 2 0 0 0-.5.83l-1.321 4.352a.5.5 0 0 0 .623.622l4.353-1.32a2 2 0 0 0 .83-.497z"/><path d="m15 5 4 4"/>'
  };
  /* The disclosure chevron in table hierarchy cells: its own 12-unit grid and a finer stroke. */
  var ROW_CHEVRON = '<svg width="12" height="12" viewBox="0 0 12 12" fill="none" stroke="currentColor" stroke-width="1.2" stroke-linecap="round" ' +
    'stroke-linejoin="round" aria-hidden="true" focusable="false"><path d="m4.5 3 3 3-3 3"/></svg>';

  function has(name) { return Object.prototype.hasOwnProperty.call(ICONS, name); }
  function svgIcon(name, size) {
    if (!has(name)) throw new Error("Unknown icon \"" + name + "\"");
    return '<svg width="' + size + '" height="' + size +
      '" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.75" ' +
      'stroke-linecap="round" stroke-linejoin="round" aria-hidden="true" focusable="false">' + ICONS[name] + '</svg>';
  }
  function glyph(kind) {
    var node = element("span", "phc-glyph"); node.setAttribute("data-glyph", kind);
    node.innerHTML = svgIcon(kind, 16);
    return node;
  }
  function iconButton(label, icon, handler) {
    var node = button("", handler); node.className = "phc-icon-button assembly-tool-icon";
    return paintIconButton(node, label, icon);
  }
  function paintIconButton(node, label, icon) {
    dom.tooltip(node, label);
    node.setAttribute("aria-label", label);
    if (icon && node.getAttribute("data-icon") !== icon) {
      node.setAttribute("data-icon", icon);
      node.innerHTML = svgIcon(icon, 18);
    }
    return node;
  }

  return { names: Object.keys(ICONS), has: has, svgIcon: svgIcon, glyph: glyph, iconButton: iconButton,
    paintIconButton: paintIconButton,
    ROW_CHEVRON: ROW_CHEVRON };
});
