/* The Equipment Set editor's body: its users and device count, then the device grid (device, with its type when
   renamed; quantity; energy demand, or the Phius rule a rule device follows; in conditioned space; reference
   quantity). Edit and Delete sit in each row's Actions cell, revealed on hover or focus; a row click also edits.
   **Add device**, the Set's primary action, sits in the page header (`headerAction`).

   Add and Edit open the device dialog (features/programs/device_dialog.js), laid out from
   `equipment_sets.device_types`, read once. Delete confirms in the shared dialog, naming the Set and the Dwellings
   that use it, then sends `delete_device` through the page; each is one Undo step. The host
   (features/programs/tab.js) gives `session`, `send`, `run(name, params, done)`, `busy()`, `askFirst(heading, text,
   label, apply)`, `notify(text)`, `refuse(text)` and `repaint()`. */
PhComposerUI.define("features/programs/equipment_set_editor", ["workspace", "table", "request",
  "features/programs/device_dialog"],
function (ui, tables, requests, DeviceDialog) {
  "use strict";
  var el = ui.element;
  var PREFIX = "ph_composer.programs.equipment_sets.";
  var COLUMNS = [["actions", "Actions"], ["device", "Device"], ["quantity", "Quantity"], ["energy", "Energy demand"],
    ["inside", "In conditioned space"], ["reference", "Reference quantity"]];
  // Sized for the residential default's names and Phius rule lines at the panel's usual width.
  var WIDTHS = { device: 370, quantity: 76, energy: 214, inside: 116, reference: 150 };

  function SetEditor(host) {
    var self = this;
    this.host = host;
    this.root = el("div", "pgm-editor");
    this.metrics = el("div", "pgm-metrics");
    this.mount = el("div", "phc-table-mount pgm-devices");
    this.root.appendChild(this.metrics); this.root.appendChild(this.mount);
    this.reads = requests.channel(host.session, host.send, "programs-device-types", "query.invoke");
    this.headerAction = ui.button("", function () { self.add(); });
    this.headerAction.className = "primary pgm-add-device";
    this.headerAction.innerHTML = ui.svgIcon("add", 14);
    this.headerAction.appendChild(el("span", "", "Add device"));
    // A click on a row edits its device; its own controls do what they say.
    this.mount.addEventListener("click", function (event) {
      if (event.target.closest("button, input, select, a")) return;
      var tr = event.target.closest("[data-row-key]");
      if (tr && self.enabled) self.edit(tr.getAttribute("data-row-key"));
    });
  }

  SetEditor.prototype.render = function (row, context) {
    this.row = row; this.context = context;
    this.settleTypes(context.state);
    // No device opens while a write is out, the page's or the dialog's, or before the device types arrive.
    this.enabled = context.enabled && !this.host.busy() && Boolean(this.types);
    if (this.dialog) this.dialog.refresh(context.state);
    var devices = row.values.devices || [];
    var metrics = [["Used by", context.zones === 1 ? "1 Zone" : context.zones + " Zones"],
      ["Devices", String(devices.length)]];
    var root = this.metrics;
    ui.memoPaint(this, "metrics", metrics, function () {
      root.replaceChildren.apply(root, metrics.map(function (item) {
        var node = el("div", "pgm-metric");
        node.appendChild(el("small", "", item[0])); node.appendChild(el("strong", "", item[1]));
        return node;
      }));
    });
    this.paintGrid(devices);
    // A failed read keeps Add on screen, its reason as its tooltip; pressing it asks again.
    this.headerAction.disabled = !this.enabled && !this.typesError;
    ui.tooltip(this.headerAction, this.typesError || "Add a device to " + row.values.name);
    // An Add pressed before the device types arrived opens once they have.
    if (this.pendingAdd && this.enabled) { this.pendingAdd = false; this.openDialog(null); }
  };

  /* The device types, read once per panel session; Add waits for them. */
  SetEditor.prototype.settleTypes = function (state) {
    var outcome = this.reads.consume(state);
    if (outcome) {
      if (outcome.status === "completed") { this.types = outcome.value.types; this.typesError = null; }
      else this.typesError = outcome.message || "The device types could not be read.";
    }
    if (!this.types && !this.typesError && !this.reads.busy()) this.reads.run(PREFIX + "device_types", {});
  };

  SetEditor.prototype.type = function (name) {
    return (this.types || []).filter(function (entry) { return entry.type === name; })[0] || null;
  };

  SetEditor.prototype.paintGrid = function (devices) {
    var self = this;
    tables.table(this.mount, devices, {
      rows: devices.map(function (device) {
        return { key: device.id, record: device, tier: "Device", depth: 0, parent: null };
      }),
      columns: COLUMNS, defaultWidths: WIDTHS, revealRowActions: true, disabled: !this.enabled,
      empty: "No devices yet. Choose Add device.",
      value: function (row, field) { return self.value(row.record, field); },
      cell: function (td, row, field) { return self.cell(td, row.record, field); },
      actions: function (row) {
        var name = row.record.display_name;
        return [{ id: "edit", icon: "pencil", label: "Edit " + name }, { id: "delete", icon: "delete",
          label: "Delete " + name }];
      },
      action: function (row, item) {
        if (item.id === "edit") self.edit(row.key);
        else self.confirmDelete(row.record);
      }
    });
  };

  SetEditor.prototype.value = function (device, field) {
    if (field === "quantity") return String(device.quantity);
    if (field === "inside") return device.in_conditioned_space ? "Yes" : "No";
    if (field === "reference") return DeviceDialog.REFERENCE[device.reference_quantity] || "—";
    return null;
  };

  /* The Device cell names the type beside a renamed device; the energy cell marks a Phius-rule device. */
  SetEditor.prototype.cell = function (td, device, field) {
    var type = this.type(device.type);
    if (field === "device") {
      var label = type ? type.label : ui.titleCase(device.type);
      var nodes = [el("span", "", device.display_name)];
      if (device.display_name !== label) nodes.push(el("span", "muted", " · " + label));
      td.replaceChildren.apply(td, nodes);
      ui.tooltip(td, device.display_name + (device.display_name !== label ? " (" + label + ")" : ""));
      return true;
    }
    if (field !== "energy") return false;
    if (!type) { td.textContent = "—"; return true; }
    var shown = DeviceDialog.demand(type, device);
    if (shown.rule) {
      var rule = el("span", "pgm-sigma", "Σ " + shown.rule);
      td.replaceChildren(rule);
      ui.tooltip(td, shown.rule + ": worked out by WUFI-Passive and METr from the reference quantity.");
    } else { td.textContent = shown.text; ui.tooltip(td, shown.text); }
    return true;
  };

  /* ---------------------------------------------------------------- the device dialog */

  SetEditor.prototype.add = function () {
    if (this.typesError) {
      // Asked again on the next paint.
      this.typesError = null; this.pendingAdd = true; this.host.repaint(); return;
    }
    if (!this.types) { this.pendingAdd = true; return; }
    this.openDialog(null);
  };

  SetEditor.prototype.edit = function (id) {
    var device = (this.row.values.devices || []).filter(function (entry) { return entry.id === id; })[0];
    if (!device || !this.enabled || this.dialog) return;
    if (!this.type(device.type)) {
      this.host.refuse(device.display_name + " has a type this build does not know.");
      return;
    }
    this.openDialog(device);
  };

  SetEditor.prototype.openDialog = function (device) {
    var self = this, host = this.host, set = this.row;
    if (!this.enabled || this.dialog) return;
    this.dialog = new DeviceDialog({ session: host.session, send: host.send, set: set, types: this.types,
      device: device, changed: function (outcome, dialog) {
        if (dialog.root.parentNode) dialog.root.parentNode.removeChild(dialog.root);
        if (self.dialog === dialog) self.dialog = null;
        if (outcome && outcome.status === "completed") {
          host.notify(device ? "Saved " + dialog.draft.display_name + "." : "Added " + dialog.draft.display_name +
            " to " + set.values.name + ".");
        }
        host.repaint();
      } });
    this.root.appendChild(this.dialog.root);
    this.dialog.open();
  };

  /* Delete names the device, the Set and the Dwellings that use it. */
  SetEditor.prototype.confirmDelete = function (device) {
    var self = this, set = this.row, dwellings = this.context.dwellings || [];
    var users = dwellings.length ? (dwellings.length === 1 ? "Dwelling " : "Dwellings ") + dwellings.join(", ") +
      (dwellings.length === 1 ? " uses" : " use") + " this Set." : "No Dwelling uses this Set.";
    this.host.askFirst("Delete device?", "This removes " + device.display_name + " from " + set.values.name + ". " +
      users, "Delete device", function () {
      self.host.run(PREFIX + "delete_device", { id: set.id, device_id: device.id,
        expected_values: { display_name: device.display_name, quantity: device.quantity } }, function () {
        return device.display_name + " deleted from " + set.values.name + ".";
      });
    });
  };

  SetEditor.prototype.busy = function () { return Boolean(this.dialog && this.dialog.busy()); };

  SetEditor.prototype.guard = function () {
    return this.busy() ? "Wait for the last change to finish." : null;
  };

  SetEditor.prototype.dispose = function () {
    if (this.dialog) { this.dialog.withdraw(); if (this.dialog.root.parentNode) this.dialog.root.remove(); }
    this.dialog = null;
  };

  return SetEditor;
});
