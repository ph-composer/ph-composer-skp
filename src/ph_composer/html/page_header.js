/* The one page header every pane opens with: the title, then at the right the secondary actions and the
   one primary action last. A screen never styles its own heading. A record count belongs to the control
   row under it (view_controls.js), where it can say how many a filter shows.
   The page's overflow menu, when it has one, stands last, after the primary (`menu`).
   pageHeader({ title, actions: [node], primary: node, menu: node }) returns
   { root, setTitle(text), setActions(nodes), setPrimary(node) }; a null primary shows nothing. */
PhComposerUI.define("page_header", ["dom"], function (dom) {
  "use strict";

  function pageHeader(options) {
    var root = dom.element("div", "phc-heading");
    var actions = dom.element("div", "phc-heading-actions"), secondary = [], primary = null;
    var menu = options.menu || null;
    var title = dom.element("h1", "", options.title);
    root.appendChild(title);
    root.appendChild(actions);
    function place() {
      actions.replaceChildren.apply(actions, secondary.concat(primary ? [primary] : [], menu ? [menu] : []));
    }
    var header = {
      root: root,
      setTitle: function (text) { title.textContent = text; },
      setActions: function (nodes) { secondary = nodes.slice(); place(); },
      // Placing the same node again would drop its focus, so only a different node moves the DOM.
      setPrimary: function (node) {
        if (node === primary) return;
        primary = node;
        if (node && !/(^| )primary( |$)/.test(node.className)) node.className = (node.className + " primary").trim();
        place();
      }
    };
    secondary = (options.actions || []).slice();
    if (options.primary) header.setPrimary(options.primary); else place();
    return header;
  }

  return { pageHeader: pageHeader };
});
