/* Anchored and modal surfaces: the bubble, the action menu, record-form dialogs, floating notices, and the
   shared tooltip layer. Only one top-level bubble is open across the workspace. */
PhComposerUI.define("overlay", ["dom", "icons"], function (dom, icons) {
  "use strict";
  var element = dom.element, button = dom.button, glyph = icons.glyph, iconButton = icons.iconButton;

  /* Shared non-modal, anchored editor. Only one bubble is open across the workspace. */
  var activeBubble = null, bubbleSequence = 0;
  function Bubble(trigger, title, options) {
    var self = this;
    this.options = options || {}; this.children = [];
    if (this.options.parent) this.options.parent.children.push(this);
    this.trigger = trigger; this.root = element("div", "phc-bubble-anchor");
    this.panel = element("section", "phc-bubble"); this.panel.hidden = true;
    this.panel._bubble = this;
    this.panel.setAttribute("role", "dialog"); this.panel.setAttribute("aria-label", title);
    this.panel.setAttribute("id", "phc-bubble-" + (++bubbleSequence));
    trigger.setAttribute("aria-controls", this.panel.getAttribute("id"));
    trigger.setAttribute("aria-expanded", "false");
    var header = element("div", "phc-bubble-heading"); header.appendChild(element("strong", "", title));
    var close = button("", function () { self.close(true); }); close.setAttribute("aria-label", "Close " + title);
    close.innerHTML = icons.svgIcon("clear", 16);
    header.appendChild(close); this.panel.appendChild(header); this.heading = header; this.closeButton = close;
    this.content = element("div", "phc-bubble-content"); this.panel.appendChild(this.content);
    // Drawing labels stay in their SVG/scrollport; their editor mounts outside that region.
    if (!this.options.detachedTrigger) this.root.appendChild(trigger);
    this.root.appendChild(this.panel);
    if (!this.options.ownTrigger) {
      trigger.addEventListener("click", function () { self.toggle(); });
      trigger.addEventListener("keydown", function (event) {
        if (event.key === "ArrowRight" || event.key === "ArrowDown") { event.preventDefault(); self.open(); }
      });
    }
    if (this.options.hover) {
      trigger.addEventListener("mouseenter", function (event) {
        self.cancelHover();
        // A drag in progress (the body carries `is-dragging`) never opens a hover bubble.
        if (event.buttons || document.body.classList.contains("is-dragging")) return;
        self.hoverTimer = window.setTimeout(function () {
          self.hoverTimer = null;
          if (self.root.isConnected && trigger.matches(":hover") &&
            !document.body.classList.contains("is-dragging")) self.open(false);
        }, 450);
      });
      function closeAfterLeave() {
        if (window.setTimeout) window.setTimeout(function () {
          if (!self.root.matches(":hover") && !trigger.matches(":hover") &&
            !self.panel.contains(document.activeElement)) self.close(false);
        }, 220);
      }
      trigger.addEventListener("mouseleave", function () {
        self.cancelHover();
        if (self.options.detachedTrigger) closeAfterLeave();
      });
      this.root.addEventListener("mouseleave", closeAfterLeave);
    }
    function closeOnEscape(event) {
      if (event.key === "Escape" && !self.panel.hidden && !event.defaultPrevented) {
        event.preventDefault(); self.close(true);
      }
    }
    this.root.addEventListener("keydown", closeOnEscape);
    if (this.options.detachedTrigger) trigger.addEventListener("keydown", closeOnEscape);
  }
  Bubble.prototype.cancelHover = function () {
    if (this.hoverTimer != null) window.clearTimeout(this.hoverTimer);
    this.hoverTimer = null;
  };
  Bubble.prototype.toggle = function () { if (this.panel.hidden) this.open(); else this.close(true); };
  Bubble.prototype.open = function (focusInput) {
    this.cancelHover();
    if (document.body.classList.contains("is-dragging")) return;
    if (this.options.parent) {
      this.options.parent.open(false);
      var self = this; this.options.parent.children.forEach(function (child) {
        if (child !== self) child.close(false);
      });
    }
    if (!this.options.parent && activeBubble && activeBubble !== this && activeBubble.close(false) === false) return;
    if (!this.options.parent) activeBubble = this;
    this.panel.hidden = false;
    var cell = this.root.closest("th, td");
    if (cell) cell.classList.add("has-open-bubble");
    this.trigger.setAttribute("aria-expanded", "true");
    this.position();
    // An owner's onOpen can tell a deliberate open (click, keyboard) from a hover or a repaint's reopen.
    this.openedWithFocus = focusInput !== false;
    if (this.options.onOpen) this.options.onOpen(this);
    var panel = this.panel;
    var content = this.content;
    var candidates = ["input", "select", "button"].reduce(function (all, tag) {
      return all.concat(Array.prototype.slice.call(content.querySelectorAll(tag)));
    }, []);
    var focus = candidates.filter(function (node) {
      for (var current = node; current && current !== panel; current = current.parentNode) {
        if (current.hidden) return false;
      }
      return !node.disabled;
    })[0];
    if (focus && focusInput !== false) focus.focus({ preventScroll: true });
  };
  /* Placement, in CSS pixels. A bubble sits BUBBLE.GAP from its trigger and at least BUBBLE.MARGIN inside the
     viewport; the fallbacks stand in for a measurement the host has not produced yet (a hidden panel). */
  var BUBBLE = {
    MARGIN: 12, GAP: 10, SIDE_GAP: 8, SIDE_ROOM: 20, CONTENT_CLEARANCE: 22, CONTENT_CHROME: 16,
    FALLBACK_CHROME: 60, FALLBACK_VIEWPORT: { width: 1024, height: 768 }, FALLBACK_BOX: { width: 300, height: 250 },
    FALLBACK_TRIGGER: 30, POINTER_EDGE: 12, POINTER_INSET: 20, SUBMENU_POINTER_TOP: 18, SUBMENU_POINTER_BOTTOM: 24
  };
  Bubble.prototype.position = function () {
    // Measure natural height; a clamp left by an earlier placement would understate what the content needs.
    this.content.style.maxHeight = "";
    var anchor = this.trigger.getBoundingClientRect(), box = this.panel.getBoundingClientRect();
    var view = { width: window.innerWidth || BUBBLE.FALLBACK_VIEWPORT.width,
      height: window.innerHeight || BUBBLE.FALLBACK_VIEWPORT.height };
    var size = { width: box.width || BUBBLE.FALLBACK_BOX.width, height: box.height || BUBBLE.FALLBACK_BOX.height };
    var sideFits = anchor.right + size.width + BUBBLE.SIDE_ROOM <= view.width ||
      anchor.left >= size.width + BUBBLE.SIDE_ROOM;
    if (this.options.parent || (this.options.side && sideFits)) this.positionSubmenu(anchor, size, view);
    else this.positionAnchored(anchor, box, size, view);
  };
  /* Beside the trigger, flipping to its left when the right side has no room; the pointer tracks the
     trigger's middle. */
  Bubble.prototype.positionSubmenu = function (anchor, size, view) {
    var flip = anchor.right + size.width + BUBBLE.GAP > view.width;
    var left = Math.max(BUBBLE.MARGIN,
      flip ? anchor.left - size.width - BUBBLE.SIDE_GAP : anchor.right + BUBBLE.SIDE_GAP);
    var top = Math.max(BUBBLE.MARGIN, Math.min(anchor.top, view.height - size.height - BUBBLE.MARGIN));
    this.panel.classList.remove("pointer-hidden");
    this.panel.classList.remove("is-above");
    this.panel.style.left = left + "px";
    this.panel.style.top = top + "px";
    this.panel.classList.add("is-submenu"); this.panel.classList[flip ? "add" : "remove"]("opens-left");
    var middle = anchor.top + (anchor.height || BUBBLE.FALLBACK_TRIGGER) / 2 - top;
    this.panel.style.setProperty("--bubble-pointer-y", Math.max(BUBBLE.SUBMENU_POINTER_TOP,
      Math.min(size.height - BUBBLE.SUBMENU_POINTER_BOTTOM, middle)) + "px");
  };
  /* Below the trigger, or above it when the box does not fit below and above offers more room; the content then
     scrolls within the room it has. The pointer hides when clamping moved the box off the trigger. */
  Bubble.prototype.positionAnchored = function (anchor, box, size, view) {
    var above = anchor.bottom + size.height + BUBBLE.MARGIN > view.height &&
      anchor.top > Math.min(size.height + BUBBLE.MARGIN, view.height - anchor.bottom);
    this.panel.classList.remove("is-submenu");
    this.panel.classList.remove("opens-left");
    var contentBox = this.content.getBoundingClientRect();
    var panelChrome = typeof contentBox.top === "number" && typeof box.top === "number" && contentBox.top > box.top ?
      contentBox.top - box.top + BUBBLE.CONTENT_CHROME : BUBBLE.FALLBACK_CHROME;
    var available = (above ? anchor.top : view.height - anchor.bottom) - BUBBLE.CONTENT_CLEARANCE;
    this.content.style.maxHeight = Math.max(0, available - panelChrome) + "px";
    box = this.panel.getBoundingClientRect();
    var width = box.width || size.width, height = box.height || size.height;
    var left = Math.max(BUBBLE.MARGIN, Math.min(anchor.left, view.width - width - BUBBLE.MARGIN));
    this.panel.style.left = left + "px";
    var top = above ? anchor.top - height - BUBBLE.GAP : anchor.bottom + BUBBLE.GAP;
    var finalTop = Math.max(BUBBLE.MARGIN, Math.min(top, view.height - height - BUBBLE.MARGIN));
    this.panel.style.top = finalTop + "px";
    this.panel.classList[above ? "add" : "remove"]("is-above");
    var pointer = anchor.left + (anchor.width || BUBBLE.FALLBACK_TRIGGER) / 2 - left;
    this.panel.classList[finalTop !== top || pointer < BUBBLE.POINTER_EDGE ||
      pointer > width - BUBBLE.POINTER_EDGE ? "add" : "remove"]("pointer-hidden");
    this.panel.style.setProperty("--bubble-pointer",
      Math.max(BUBBLE.POINTER_INSET, Math.min(width - BUBBLE.POINTER_INSET, pointer)) + "px");
  };
  /* Below an anchor, or above it when there is no room below, clamped to the viewport: for popovers that are not
     bubbles (the colour form). */
  function placeNear(anchor, size, gap, margin) {
    var left = Math.max(margin, Math.min(anchor.left, window.innerWidth - size.width - margin));
    var top = anchor.bottom + gap;
    if (top + size.height > window.innerHeight - margin) top = anchor.top - size.height - gap;
    return { left: left, top: Math.max(margin, Math.min(top, window.innerHeight - size.height - margin)) };
  }
  Bubble.prototype.close = function (focus) {
    var reason = this.options.guard && this.options.guard();
    if (reason) {
      if (this.options.refused) this.options.refused(reason);
      return false;
    }
    var wasOpen = !this.panel.hidden;
    this.cancelHover();
    this.children.forEach(function (child) { child.close(false); });
    this.panel.hidden = true; this.trigger.setAttribute("aria-expanded", "false");
    var cell = this.root.closest("th, td");
    if (cell && !Array.from(cell.querySelectorAll(".phc-bubble")).some(function (bubble) {
      return !bubble.hidden;
    })) cell.classList.remove("has-open-bubble");
    if (activeBubble === this) activeBubble = null;
    if (focus) this.trigger.focus({ preventScroll: true });
    if (wasOpen && this.options.onClose) this.options.onClose(this);
    return true;
  };
  Bubble.prototype.deepest = function () {
    var child = this.children.filter(function (item) { return !item.panel.hidden; })[0];
    return child ? child.deepest() : this;
  };
  Bubble.activeTitle = function (owner) {
    return activeBubble && (!owner || owner.contains(activeBubble.root)) &&
      activeBubble.deepest().panel.getAttribute("aria-label");
  };
  Bubble.closeActive = function (owner) {
    if (activeBubble && (!owner || owner.contains(activeBubble.root))) activeBubble.close(false);
  };
  /* A table cell's validation message is drawn over the table, so a scroller cannot clip it and a last row can
     show it: under the cell, or above it when there is no room below. `cell` is the td carrying `has-cell-error`. */
  var CELL_ERROR = { GAP: 2, MARGIN: 8 };
  function placeCellError(cell) {
    var message = cell.querySelector(".cell-error");
    if (!message || message.hidden) return;
    var spot = placeNear(cell.getBoundingClientRect(), message.getBoundingClientRect(), CELL_ERROR.GAP,
      CELL_ERROR.MARGIN);
    message.style.left = spot.left + "px"; message.style.top = spot.top + "px";
  }
  function placeCellErrors() {
    Array.prototype.forEach.call(document.querySelectorAll(".has-cell-error"), placeCellError);
  }
  function placeCellErrorFrom(event) {
    var cell = event.target && event.target.closest && event.target.closest(".has-cell-error");
    if (cell) placeCellError(cell);
  }
  if (document.addEventListener) {
    document.addEventListener("mousedown", function (event) {
      if (activeBubble && !activeBubble.root.contains(event.target) &&
        !activeBubble.trigger.contains(event.target)) activeBubble.close(false);
    });
    document.addEventListener("scroll", function (event) {
      if (activeBubble && !activeBubble.panel.contains(event.target)) activeBubble.close(false);
      placeCellErrors();
    }, true);
    document.addEventListener("mouseover", placeCellErrorFrom);
    document.addEventListener("focusin", placeCellErrorFrom);
  }
  if (window.addEventListener) window.addEventListener("resize", function () {
    if (activeBubble) activeBubble.position();
    placeCellErrors();
  });
  /* One notice at a time; a newer message replaces an older one. Tones: `success` is a disposable
     confirmation that fades by itself after SUCCESS_MS (longer for a long message, up to SUCCESS_MAX_MS),
     held while the pointer or focus is on it, and also on the next interaction elsewhere; `info`
     (instructions, tool directions) fades on the next interaction unless persistent; `warning` and `error`
     stay until dismissed. */
  var SUCCESS_MS = 3000, SUCCESS_MAX_MS = 8000;
  function successDelay(text) {
    return Math.min(SUCCESS_MAX_MS, SUCCESS_MS + Math.max(0, String(text).length - 40) * 50);
  }
  function floatingNotice(owner) {
    var root = element("div", "phc-notice phc-floating-notice"),
      message = element("span", "phc-floating-notice-message");
    var revision = 0, persistent = false, timer = null, held = false;
    function stopTimer() { if (timer !== null && window.clearTimeout) window.clearTimeout(timer); timer = null; }
    function startTimer() {
      stopTimer();
      if (root.getAttribute("data-tone") !== "success" || root.hidden || held || !window.setTimeout) return;
      var current = revision;
      timer = window.setTimeout(function () { timer = null; if (current === revision) root.fade(); },
        successDelay(message.textContent));
    }
    function hold() { held = true; stopTimer(); }
    function release() { held = false; startTimer(); }
    root.addEventListener("mouseenter", hold); root.addEventListener("mouseleave", release);
    root.addEventListener("focusin", hold); root.addEventListener("focusout", release);
    message.setAttribute("role", "status");
    message.setAttribute("aria-live", "polite");
    message.setAttribute("aria-atomic", "true");
    var dismiss = iconButton("Dismiss message", "clear", function () { root.clear(); });
    dismiss.classList.add("phc-floating-notice-dismiss");
    var act = button("", function () {
      var chosen = act._action; root.clear();
      if (chosen) chosen.run();
    });
    act.className = "phc-floating-notice-action";
    act.hidden = true;
    root.appendChild(message);
    root.appendChild(act);
    root.appendChild(dismiss);
    root.hidden = true;
    root.message = message; root.dismissButton = dismiss; root.actionButton = act;
    root.show = function (text, options) {
      revision += 1; persistent = Boolean(options && options.persistent); root.classList.remove("is-dismissing");
      // A hold belongs to the notice under the pointer or focus now; a hidden notice never sent its leave.
      held = root.contains(document.activeElement) || Boolean(root.matches && root.matches(":hover"));
      message.textContent = text || "";
      act._action = (options && options.action) || null;
      act.textContent = act._action ? act._action.label : "";
      act.hidden = !act._action;
      root.hidden = !message.textContent;
      root.setAttribute("data-persistent", String(persistent));
      // Information and instructions are neutral; yellow is kept for warnings and red for errors.
      root.setAttribute("data-tone", (options && options.tone) || "info");
      startTimer();
    };
    root.clear = function () {
      revision += 1;
      stopTimer();
      persistent = false; held = false;
      root.classList.remove("is-dismissing");
      message.textContent = "";
      act._action = null; act.hidden = true;
      root.hidden = true;
    };
    root.fade = function () {
      if (root.hidden || persistent || root.classList.contains("is-dismissing")) return;
      var current = ++revision; root.classList.add("is-dismissing");
      if (!window.setTimeout) { root.clear(); return; }
      window.setTimeout(function () { if (current === revision) root.clear(); }, 180);
    };
    function pointerdown(event) { if (!root.contains(event.target)) root.fade(); }
    function keydown(event) {
      if (event.key === "Escape" && !root.hidden) { escape(event); return; }
      if (!root.contains(event.target) && !/^(Shift|Control|Alt|Meta)$/.test(event.key || "")) root.fade();
    }
    /* A notice that fades leaves the key to whatever it describes. One that stays until dismissed (a warning, an
       error) waits for an open bubble or dialog to take Escape first, then closes; it uses the key, so a tool
       beneath it keeps going, unless the key was pressed in a field, which keeps its own Escape. */
    function escape(event) {
      if (!persistent) { root.fade(); return; }
      if (activeBubble || Array.prototype.some.call(document.querySelectorAll("dialog"), function (node) {
        return node.open; })) return;
      root.clear();
      if (!/^(input|select|textarea)$/i.test(event.target && event.target.tagName || "")) event.preventDefault();
    }
    if (owner) {
      owner.addEventListener("pointerdown", pointerdown, true);
      owner.addEventListener("keydown", keydown, true);
    }
    root.dispose = function () {
      revision += 1;
      stopTimer();
      if (owner) {
        owner.removeEventListener("pointerdown", pointerdown, true);
        owner.removeEventListener("keydown", keydown, true);
      }
    };
    return root;
  }
  /* An icon-button menu: the ellipsis unless `options.icon` names another icon. */
  function ActionMenu(label, options) {
    var self = this;
    this.label = label || "More actions"; this.unavailable = null;
    var trigger = iconButton(this.label, (options && options.icon) || "more"),
      bubble = new Bubble(trigger, this.label, Object.assign({}, options, { ownTrigger: true }));
    trigger.addEventListener("click", function () { if (!self.unavailable) bubble.toggle(); });
    trigger.addEventListener("keydown", function (event) {
      if (self.unavailable || (event.key !== "ArrowRight" && event.key !== "ArrowDown")) return;
      event.preventDefault(); bubble.open();
    });
    bubble.root.classList.add("phc-action-menu-anchor"); bubble.panel.classList.add("phc-action-menu");
    this.root = bubble.root; this.trigger = trigger; this.bubble = bubble; this.content = bubble.content;
  }
  /* Why the menu cannot open now, or null when it can. An unavailable menu keeps its trigger on screen with the
     reason as its tooltip and in its accessible name, and opens nothing: a natively disabled button would show
     no tooltip. An open menu that becomes unavailable closes. */
  ActionMenu.prototype.setUnavailable = function (reason) {
    this.unavailable = reason || null;
    if (this.unavailable) {
      this.trigger.setAttribute("aria-disabled", "true");
      this.trigger.setAttribute("aria-label", this.label + ". " + this.unavailable);
      dom.tooltip(this.trigger, this.unavailable);
      if (!this.bubble.panel.hidden) this.bubble.close(false);
    } else {
      this.trigger.removeAttribute("aria-disabled");
      icons.paintIconButton(this.trigger, this.label);
    }
  };
  ActionMenu.prototype.add = function (label, handler, options) {
    // Focus goes back to the trigger before the handler runs, so a dialog it opens returns there, not to
    // this item, which the closed menu has hidden.
    var self = this, item = button(label, function () { self.bubble.close(true); handler(); });
    item.className = "phc-action-menu-item" + (options && options.destructive ? " phc-danger-action" : "");
    if (options && options.icon) item.replaceChildren(glyph(options.icon), element("span", "", label));
    this.content.appendChild(item); return item;
  }
  // Shared confirmation order: secondary cancel, then primary action at the right.
  function actionRow(cancel, primary, destructive) {
    var row = element("div", "phc-dialog-actions");
    cancel.className += " phc-action-cancel";
    primary.className += " primary " + (destructive ? "phc-action-delete" : "phc-action-apply");
    row.appendChild(cancel); row.appendChild(primary); return row;
  }
  /* Record forms open above a stationary page. The hidden flag mirrors the open state, so owners keep one flag;
     Escape runs the owner's cancel, which may refuse while a request is pending. */
  var dialogSequence = 0;
  /* Callers told whenever a form dialog opens or closes, such as the panel, which keeps a way out of an
     unanswered request inside whatever modal is open. */
  var modalWatchers = [];
  function onModalChange(watcher) { modalWatchers.push(watcher); }
  function modalChanged() { modalWatchers.slice().forEach(function (watcher) { watcher(); }); }
  /* Every dialog carries the same top-right close control, and it does what Escape and the dialog's own
     Cancel (or Done) do: onCancel, which may refuse while a request is pending; an owner that disables its
     Cancel disables `closeButton` too. It is put back on every open, because an owner may replace the
     dialog's children between uses; an owner does not replace them while the dialog is open. */
  function formDialog(className, onCancel) {
    var node = element("dialog", "phc-dialog phc-form-dialog" + (className ? " " + className : ""));
    var close = iconButton("Close", "clear", function () { onCancel(); });
    close.classList.add("phc-dialog-close");
    node.hidden = true;
    node.closeButton = close;
    node.addEventListener("cancel", function (event) { event.preventDefault(); onCancel(); });
    var opener = null;
    node.openModal = function () {
      if (close.parentNode !== node) node.insertBefore(close, node.firstChild || null);
      // Focus goes back where it came from when the dialog closes; the host's Chromium does not do it.
      if (node.hidden) opener = document.activeElement;
      var heading = node.querySelector("h2");
      if (heading) {
        if (!heading.id) heading.id = "phc-form-dialog-" + (++dialogSequence);
        node.setAttribute("aria-labelledby", heading.id);
      }
      node.hidden = false; if (!node.open && node.showModal) node.showModal();
      modalChanged();
    };
    node.closeModal = function () {
      var wasOpen = !node.hidden;
      node.hidden = true; if (node.open && node.close) node.close();
      if (wasOpen && opener && opener.isConnected && opener.focus && !node.contains(document.activeElement)) {
        opener.focus({ preventScroll: true });
      }
      opener = null;
      if (wasOpen) modalChanged();
    };
    return node;
  }
  /* Why an action is not available, beside that action: an alert icon that opens the reason in a bubble
     anchored to it. A general hint belongs in a help button instead; a blocking reason stays where the
     blocked action is, so the user never hunts for it. */
  function reasonButton(action, reason) {
    var trigger = iconButton("Why " + action + " is unavailable", "alert");
    var bubble = new Bubble(trigger, "Why " + action + " is unavailable");
    trigger.classList.add("phc-blocked-reason");
    bubble.root.classList.add("phc-blocked-reason-anchor");
    bubble.content.appendChild(element("p", "phc-blocked-reason-text", reason));
    return bubble.root;
  }
  function helpButton(label, explanation) {
    var help = button(""); help.className = "phc-help";
    help.innerHTML = icons.svgIcon("help", 16);
    dom.tooltip(help, explanation);
    help.setAttribute("aria-label", label + ": " + explanation);
    return help;
  }
  var tooltipSequence = 0;
  /* A panel shares one hover/focus tooltip across its tables, toolbars, drawings and dialogs. A standalone
     table may attach its own layer; attaching beneath an existing layer reuses that owner's listeners. */
  function attachTooltip(root) {
    var ancestor = root;
    while (ancestor) {
      if (ancestor._checkTooltip) { root._checkTooltip = ancestor._checkTooltip; return; }
      ancestor = ancestor.parentNode;
    }
    var tip = element("div", "row-tooltip"); tip.hidden = true; tip.setAttribute("role", "tooltip");
    tip.id = "phc-tooltip-" + (++tooltipSequence);
    var timer;
    var owner;
    root.appendChild(tip);
    function unlink() {
      if (!owner) return;
      var other = (owner.getAttribute("aria-describedby") || "").split(/\s+/).filter(function (id) {
        return id && id !== tip.id;
      });
      if (other.length) owner.setAttribute("aria-describedby", other.join(" "));
      else owner.removeAttribute("aria-describedby");
    }
    function hide() { tip.hidden = true; unlink(); owner = null; }
    function later() { clearTimeout(timer); timer = setTimeout(hide, 100); }
    function show(event) {
      if (tip.contains(event.target)) { clearTimeout(timer); return; }
      var node = event.target;
      while (node && node !== root && !node.getAttribute("data-tooltip")) node = node.parentNode;
      if (!node || node === root) { hide(); return; }
      clearTimeout(timer);
      unlink();
      owner = node;
      // A native modal's top layer covers body overlays, so its tooltip must live inside that dialog.
      var layer = node.closest("dialog[open]") || root;
      if (tip.parentNode !== layer) layer.appendChild(tip);
      tip.textContent = node.getAttribute("data-tooltip"); tip.hidden = false;
      var described = node.getAttribute("aria-describedby");
      node.setAttribute("aria-describedby", (described ? described + " " : "") + tip.id);
      var bounds = node.getBoundingClientRect();
      tip.style.left = Math.max(8, Math.min(bounds.left, window.innerWidth - tip.offsetWidth - 8)) + "px";
      tip.style.top = (bounds.bottom + tip.offsetHeight + 8 < window.innerHeight ?
        bounds.bottom + 4 : bounds.top - tip.offsetHeight - 4) + "px";
    }
    root.addEventListener("mouseover", show); root.addEventListener("focusin", show);
    root.addEventListener("mouseout", later); root.addEventListener("focusout", later);
    tip.addEventListener("mouseover", function () { clearTimeout(timer); });
    tip.addEventListener("mouseout", later);
    root.addEventListener("keydown", function (event) { if (event.key === "Escape") hide(); }, true);
    root.addEventListener("scroll", hide, true);
    root.addEventListener("click", function () { if (owner) hide(); }, true);
    root._checkTooltip = function () {
      if (owner && (!root.contains(owner) || owner.getAttribute("data-tooltip") !== tip.textContent)) hide();
      var node = owner;
      while (node && node !== root) {
        if (node.hidden || (node.tagName === "DIALOG" && !node.open)) { hide(); break; }
        node = node.parentNode;
      }
    };
  }

  return { Bubble: Bubble, ActionMenu: ActionMenu, floatingNotice: floatingNotice, actionRow: actionRow,
    formDialog: formDialog, onModalChange: onModalChange,
    helpButton: helpButton, reasonButton: reasonButton, attachTooltip: attachTooltip,
    placeNear: placeNear, placeCellError: placeCellError, BUBBLE: BUBBLE, SUCCESS_MS: SUCCESS_MS };
});
