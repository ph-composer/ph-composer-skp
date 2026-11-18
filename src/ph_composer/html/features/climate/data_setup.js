/* Climate Data on This Computer: the climate data folders set up on this computer, read afresh by
   `folders.list` each time the dialog opens, with no Rescan and no notice of new stations (J1, R4). Each row
   shows the dataset name, the folder's display location, the format found, the stations and states, and the
   files not read grouped by kind, so a folder that also holds other formats does not read as a failure.

   Add Folder opens the native chooser first, since the path never reaches the panel, and then the new row's name
   for editing, prefilled from the folder. A folder that cannot be found says so and offers Locate and Remove;
   PH-Composer never removes one itself (J6). Every command applies at once and touches no Model, so the dialog
   ends with Done. Its messages stay inside it, above the native modal's top layer. */
PhComposerUI.define("features/climate/data_setup", ["workspace", "request", "features/climate/shared"],
function (ui, requests, shared) {
  "use strict";
  var el = ui.element, FOLDERS = shared.PREFIX + "folders.";
  var MAX_NAME = 120; // features/climate/folders/store.rb, MAX_NAME_LENGTH
  var FORMAT_WORDS = { phius_station_file: "Phius monthly station files" };
  // Files not read, by kind: an extension the user would recognise is named, the rest are "other".
  var KINDS = { ".xls": "Excel", ".xlsx": "Excel", ".xlsm": "Excel", ".csv": "CSV", ".pdf": "PDF", ".epw": "EPW",
    ".txt": "text", ".zip": "zip" };
  var NONE = "—";
  var WAITING = { add: "Choose the folder in the window that opened…", locate: "Choose the folder in the window " +
    "that opened…", rename: "Saving the name…", remove: "Removing…" };
  var KEPT = [
    ["Kept on this computer", "Each folder's location and the name you give it, in a PH-Composer settings file in " +
      "your user folder, outside SketchUp's own folders. Every SketchUp version on this computer reads it. Not " +
      "shared with a Model or with anyone who opens it."],
    ["Read when needed", "Station files, each time the station picker opens. A file you add or change shows up " +
      "the next time, with nothing to import."],
    ["Kept in a Model", "Only the station you attach: its values, the dataset name and the station name. Never a " +
      "folder location."]];

  function count(value) { return Number(value).toLocaleString("en-US"); }
  function plural(value, word) { return count(value) + " " + word + (value === 1 ? "" : "s"); }

  /* "1,150 Excel files · 4 other": the kinds named in the order the host gives (most first), then the rest. */
  function notRead(folder) {
    var total = folder.files_not_read_total, named = {}, order = [], rest = total;
    if (!folder.found || !total) return null;
    (folder.files_not_read || []).forEach(function (kind) {
      var word = KINDS[kind.extension];
      if (!word) return;
      if (!(word in named)) { named[word] = 0; order.push(word); }
      named[word] += kind.count; rest -= kind.count;
    });
    var parts = order.map(function (word) { return plural(named[word], word + " file"); });
    if (rest > 0) parts.push(count(rest) + " other");
    return parts.join(" · ");
  }

  function DataSetup(session, send, closed) {
    var self = this;
    this.closed = closed; this.folders = null; this.failure = null; this.renaming = null; this.verb = null;
    this.reads = requests.channel(session, send, "climate_folders", "query.invoke");
    this.commands = requests.channel(session, send, "climate_folder_setup", "setup.invoke");
    this.root = ui.formDialog("climate-data-setup", function () { self.close(); });
    this.root.appendChild(el("h2", "", "Climate data on this computer"));
    this.root.appendChild(el("p", "climate-dialog-note", "Folders of climate files you are licensed to use. " +
      "PH-Composer reads them here and never copies or shares them."));
    this.status = el("p", "climate-data-status"); this.status.setAttribute("role", "status");
    this.root.appendChild(this.status);
    this.list = el("div", "climate-data-list"); this.root.appendChild(this.list);
    this.notes = el("div", "climate-data-notes"); this.root.appendChild(this.notes);
    this.root.appendChild(el("p", "climate-dialog-note", "Station files are found in subfolders. A station's " +
      "state is the name of the folder it sits in."));
    var kept = el("dl", "climate-data-kept");
    KEPT.forEach(function (item) { kept.appendChild(el("dt", "", item[0])); kept.appendChild(el("dd", "", item[1])); });
    this.root.appendChild(kept);
    this.addButton = intent(ui.button("Add Folder…", null), function () { self.run("add", {}); });
    // Every change here applies at once, so the dialog ends with Done, never a Cancel that would undo nothing.
    this.done = intent(ui.button("Done", null), function () { self.close(); });
    var footer = el("div", "phc-dialog-actions climate-data-actions");
    footer.appendChild(this.addButton); footer.appendChild(this.done);
    this.root.appendChild(footer);
    this.keepClickWhileNaming();
    document.body.appendChild(this.root);
  }

  /* A button whose click runs `run`, also kept on it as its intent, so a press that first saves a name being
     typed still does what it was pressed for. */
  function intent(button, run) {
    button._intent = run;
    button.addEventListener("click", function (event) { run(event); });
    return button;
  }

  /* Pressing another button while a name is being typed saves the name first, as leaving the field does, and
     then does what the button was pressed for: once the name is saved, or at once when nothing needed saving.
     Left to the browser, leaving the field would save the name, disable or repaint the button under the pointer,
     and lose the click. */
  DataSetup.prototype.keepClickWhileNaming = function () {
    var self = this;
    this.root.addEventListener("mousedown", function (event) {
      var button = event.target && event.target.closest ? event.target.closest("button") : null;
      var editor = self.editor;
      if (!button || !button._intent || !editor || !editor.isConnected || editor.contains(button)) return;
      event.preventDefault();
      self.swallow = button;
      var run = button._intent;
      if (self.commitRename()) self.afterRename = run;
      else if (!self.editor) run();
    }, true);
    // The click that follows that press has been answered already.
    this.root.addEventListener("click", function (event) {
      var swallowed = self.swallow;
      self.swallow = null;
      if (swallowed && (event.target === swallowed || swallowed.contains(event.target))) {
        event.preventDefault(); event.stopPropagation();
      }
    }, true);
  };

  DataSetup.prototype.isOpen = function () { return !this.root.hidden; };

  /* Opens on a fresh read; `add` starts Add Folder at once, for the Climate tab's empty state. */
  DataSetup.prototype.open = function (options) {
    if (this.isOpen() || this.disposed) return;
    this.folders = null; this.failure = null; this.renaming = null; this.closeWhenSettled = false;
    this.say("");
    this.reads.reset(); this.reads.run(FOLDERS + "list", {});
    this.paint(); this.root.openModal();
    if (options && options.add) this.run("add", {}); else this.addButton.focus();
  };

  DataSetup.prototype.consume = function (state) {
    var listed = this.reads.consume(state), done = this.commands.consume(state);
    if (listed) this.settleList(listed);
    if (done) this.settle(done);
    if (listed || done) this.paint();
  };

  DataSetup.prototype.settleList = function (outcome) {
    if (outcome.status === "completed") { this.folders = outcome.value.folders; this.failure = null; }
    else { this.folders = []; this.failure = outcome.message; }
  };

  /* A command's answer. A cancelled chooser changes nothing; a refusal (an overlapping folder, an unknown id)
     says why and leaves the list as it was. */
  DataSetup.prototype.settle = function (outcome) {
    var verb = this.verb, value = outcome.value;
    this.verb = null;
    if (outcome.status === "cancelled") this.say("");
    else if (outcome.status !== "completed") this.say(outcome.message, "warning");
    else {
      this.say("");
      if (verb === "remove") this.folders = value.folders;
      else if (verb === "add") { this.replace(value, true); this.renaming = value.id; }
      else this.replace(value);
    }
    if (verb === "rename") this.renaming = null;
    var after = this.afterRename;
    this.afterRename = null;
    if (this.closeWhenSettled) {
      this.closeWhenSettled = false;
      if (outcome.status === "completed" || outcome.status === "cancelled") return this.close();
    } else if (after && outcome.status === "completed") after();
  };

  /* A row the host answered takes the place of the one with its id; `append` adds it when there is none (a list
     read that answered after an add may already hold it). */
  DataSetup.prototype.replace = function (row, append) {
    var folders = this.folders || [], listed = folders.some(function (folder) { return folder.id === row.id; });
    this.folders = listed || !append ? folders.map(function (folder) { return folder.id === row.id ? row : folder; }) :
      folders.concat([row]);
  };

  /* One command at a time. */
  DataSetup.prototype.run = function (verb, params) {
    if (this.disposed || this.commands.busy()) return false;
    this.verb = verb;
    this.commands.run(FOLDERS + verb, params);
    this.say(WAITING[verb]);
    this.paint();
    return true;
  };

  DataSetup.prototype.say = function (text, tone) {
    this.status.textContent = text || "";
    this.status.className = "climate-data-status" + (tone ? " is-" + tone : "");
  };

  DataSetup.prototype.busy = function () { return this.commands.busy() || this.reads.busy(); };

  DataSetup.prototype.paint = function () {
    var self = this, busy = this.busy(), folders = this.folders;
    this.addButton.disabled = busy || Boolean(this.failure);
    this.done.disabled = false;
    this.addButton.classList.toggle("primary", !folders || !folders.length);
    this.done.classList.toggle("primary", Boolean(folders && folders.length));
    if (this.editor && this.editor.isConnected) return; // a name being typed is not painted over
    this.notes.replaceChildren();
    if (!folders) { this.list.replaceChildren(el("p", "muted", "Reading the climate data folders…")); return; }
    if (this.failure) { this.list.replaceChildren(el("p", "climate-data-failure", this.failure)); return; }
    if (!folders.length) {
      this.list.replaceChildren(el("p", "muted", "No climate data folder is set up on this computer."));
      return;
    }
    var table = el("table", "phc-table climate-data-table"), head = el("tr"), body = el("tbody");
    ["Name", "Folder", "Format found", "Stations", "States", "Not read", ""].forEach(function (title) {
      var th = el("th", "", title); if (!title) th.setAttribute("aria-label", "Actions"); head.appendChild(th);
    });
    var thead = el("thead"); thead.appendChild(head); table.appendChild(thead); table.appendChild(body);
    folders.forEach(function (folder) { body.appendChild(self.row(folder, busy)); });
    this.list.replaceChildren(table);
    folders.forEach(function (folder) { self.note(folder); });
    if (this.renaming) this.startRename(this.renaming);
  };

  DataSetup.prototype.row = function (folder, busy) {
    var self = this, row = el("tr");
    row.setAttribute("data-folder-id", folder.id); row.setAttribute("data-found", String(folder.found));
    var name = el("td", "climate-data-name"), line = el("div", "climate-data-line");
    line.appendChild(el("span", "climate-data-name-text", folder.name));
    var rename = intent(ui.iconButton("Rename " + folder.name, "pencil", null), function () {
      self.startRename(folder.id);
    });
    rename.classList.add("climate-data-rename"); rename.disabled = busy;
    line.appendChild(rename); name.appendChild(line);
    row.appendChild(name);
    var location = cell("Folder", folder.display_location, "climate-data-location");
    ui.tooltip(location, folder.display_location); // a long location is cut short in its column
    row.appendChild(location);
    var format = cell("Format found", "");
    if (!folder.found) format.appendChild(el("span", "climate-data-chip is-warning", "Folder not found"));
    else if (folder.format) format.appendChild(el("span", "climate-data-chip is-ok", FORMAT_WORDS[folder.format] ||
      folder.format));
    else format.appendChild(el("span", "muted", "No station files"));
    row.appendChild(format);
    row.appendChild(cell("Stations", folder.found ? count(folder.station_count) : NONE, "is-number"));
    row.appendChild(cell("States", folder.found ? count(folder.state_count) : NONE, "is-number"));
    var others = notRead(folder);
    row.appendChild(cell("Not read", others || NONE, "climate-data-not-read"));
    var cellActions = el("td"), actions = el("div", "climate-data-line climate-data-row-actions");
    cellActions.appendChild(actions);
    if (!folder.found) actions.appendChild(this.action("Locate…", "Locate " + folder.name, busy, function () {
      self.run("locate", { id: folder.id }); }));
    actions.appendChild(this.action("Remove", "Remove " + folder.name, busy, function (event) {
      self.confirmRemove(folder, event && event.currentTarget); }));
    row.appendChild(cellActions);
    return row;
  };

  function cell(label, text, className) {
    var td = el("td", className || "", text);
    td.setAttribute("data-label", label);
    return td;
  }

  DataSetup.prototype.action = function (label, accessible, busy, run) {
    var button = intent(ui.button(label, null), run);
    button.setAttribute("aria-label", accessible); button.disabled = busy;
    return button;
  };

  /* What a row's state means, below the table, so it never makes a row taller than its neighbours. */
  DataSetup.prototype.note = function (folder) {
    var text = !folder.found ? folder.name + ": the folder is not where it was. It may have moved, been renamed, " +
      "or be on a drive that is not connected. Locate points this setting at its new place. Its stations are " +
      "left out of the station picker until then. Models are not affected." :
      folder.complete === false ? folder.name + ": the folder is too large or too deep to read in full, so the " +
      "counts are of the part read." : null;
    if (text) this.notes.appendChild(el("p", "climate-dialog-note", text));
  };

  /* The name edits in place: Enter, the check or leaving the field applies; Escape or the cross puts it back. */
  DataSetup.prototype.startRename = function (id) {
    var self = this, row = this.list.querySelector("[data-folder-id='" + id + "']"), done = false;
    var folder = (this.folders || []).filter(function (item) { return item.id === id; })[0];
    if (!row || !folder || this.commands.busy()) return;
    this.renaming = id;
    var nameCell = row.querySelector(".climate-data-name"), editor = el("div", "climate-data-name-editor");
    var input = el("input", "climate-data-name-input");
    input.value = folder.name; input.setAttribute("aria-label", "Dataset name");
    input.setAttribute("maxlength", String(MAX_NAME));
    var apply = ui.iconButton("Apply name", "check", function () { finish(true); });
    var cancel = ui.iconButton("Cancel rename", "clear", function () { finish(false); });
    // Pressing a button keeps the focus in the field, so leaving it cannot apply before the cross cancels.
    [apply, cancel].forEach(function (button) {
      button.addEventListener("mousedown", function (event) { event.preventDefault(); });
    });
    editor.appendChild(input); editor.appendChild(apply); editor.appendChild(cancel);
    nameCell.replaceChildren(editor);
    this.editor = editor;
    function finish(commit) {
      if (done) return;
      var name = input.value.trim();
      if (commit && !name) {
        input.setAttribute("aria-invalid", "true"); self.say("A dataset name cannot be empty.", "warning");
        input.focus(); return;
      }
      done = true; self.editor = null; self.renaming = null;
      if (commit && name !== folder.name) { self.renaming = id; return self.run("rename", { id: id, name: name }); }
      self.say(""); self.paint();
      return false;
    }
    this.cancelRename = function () { finish(false); };
    // Whether saving the name sent a rename; a blank name keeps the field open and sends nothing.
    this.commitRename = function () { return Boolean(finish(true)); };
    input.addEventListener("keydown", function (event) {
      if (event.key === "Enter") { event.preventDefault(); finish(true); }
      if (event.key === "Escape") {
        event.preventDefault(); if (event.stopPropagation) event.stopPropagation(); finish(false);
      }
    });
    input.addEventListener("blur", function () { finish(true); });
    input.focus(); if (input.select) input.select();
  };

  /* Remove names the dataset and says what stays: the folder, its files and every Model's climate. */
  DataSetup.prototype.confirmRemove = function (folder, trigger) {
    var self = this, dialog = ui.formDialog("phc-confirm-dialog", close);
    this.confirm = dialog;
    function close() {
      if (self.confirm === dialog) self.confirm = null;
      dialog.closeModal(); if (dialog.parentNode) dialog.parentNode.removeChild(dialog);
      if (trigger && trigger.isConnected && trigger.focus) trigger.focus({ preventScroll: true });
    }
    dialog.appendChild(el("h2", "", "Remove " + folder.name + "?"));
    dialog.appendChild(el("p", "", "PH-Composer stops reading this folder on this computer. The folder and its " +
      "files are not touched, and Models keep the climates attached from it."));
    var cancel = ui.button("Cancel", close);
    var confirm = ui.button("Remove", function () { close(); self.run("remove", { id: folder.id }); });
    dialog.appendChild(ui.actionRow(cancel, confirm, true));
    document.body.appendChild(dialog); dialog.openModal(); cancel.focus({ preventScroll: true });
  };

  /* Done, the close control and Escape: a name being typed is settled first (Escape puts it back), and a
     command still running closes the dialog when it is answered, unless it is refused. */
  DataSetup.prototype.close = function () {
    if (this.editor && this.editor.isConnected) { this.cancelRename(); return; }
    if (this.commands.busy()) {
      this.closeWhenSettled = true; this.afterRename = null;
      this.say(this.status.textContent + " The dialog closes when this is done.");
      return;
    }
    this.reads.reset();
    this.root.closeModal();
    this.closed();
  };

  DataSetup.prototype.dispose = function () {
    this.disposed = true; this.reads.reset(); this.commands.reset(); this.root.closeModal();
    var confirm = this.confirm;
    if (confirm) { confirm.closeModal(); if (confirm.parentNode) confirm.parentNode.removeChild(confirm); }
    if (this.root.parentNode) this.root.parentNode.removeChild(this.root);
  };

  return { DataSetup: DataSetup, notRead: notRead };
});
