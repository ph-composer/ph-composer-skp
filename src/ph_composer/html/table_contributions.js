/* Named tables accept columns and actions from other composed modules. Callbacks receive the current
   snapshot and row; registration retains neither a Model nor its draft state. An action marked `detail` is
   also offered on the record's own page, where that page composes the same table. */
PhComposerUI.define("table_contributions", [], function () {
  "use strict";
  var tables = Object.create(null);
  function register(name, contribution) {
    if (!name || !contribution || !contribution.id) throw new Error("A table contribution needs a table and id.");
    var entries = tables[name] || (tables[name] = []);
    if (entries.some(function (entry) { return entry.id === contribution.id; })) {
      throw new Error("Duplicate table contribution: " + contribution.id);
    }
    entries.push(contribution);
    return function () {
      var index = entries.indexOf(contribution);
      if (index >= 0) entries.splice(index, 1);
    };
  }
  function compose(name, owner, state, send) {
    var entries = (tables[name] || []).filter(function (entry) { return !entry.available || entry.available(state); });
    var columns = owner.columns.slice(), owners = Object.create(null), ids = Object.create(null);
    columns.forEach(function (column) { ids[column[0]] = true; });
    entries.forEach(function (entry) {
      (entry.columns || []).forEach(function (column) {
        if (ids[column[0]]) throw new Error("Duplicate contributed column: " + column[0]);
        ids[column[0]] = true;
        owners[column[0]] = entry;
        columns.push(column);
      });
    });
    return Object.assign({}, owner, { columns: columns,
      value: function (row, field) {
        var entry = owners[field];
        return entry ? entry.value(row, field, state) : owner.value(row, field);
      }, cell: function (cell, row, field, value) {
        var entry = owners[field];
        return entry ? Boolean(entry.cell && entry.cell(cell, row, field, value, state)) :
          Boolean(owner.cell && owner.cell(cell, row, field, value));
      }, actions: function (row) {
        var actions = owner.actions ? owner.actions(row).slice() : [], used = Object.create(null);
        actions.forEach(function (action) { used[action.id] = true; });
        entries.forEach(function (entry) {
          (entry.actions ? entry.actions(row, state) : []).forEach(function (action) {
            if (used[action.id]) throw new Error("Duplicate contributed action: " + action.id);
            used[action.id] = true;
            actions.push(Object.assign({}, action, { tableContributor: entry.id }));
          });
        });
        return actions;
      }, action: function (row, action, control) {
        var entry = entries.filter(function (candidate) { return candidate.id === action.tableContributor; })[0];
        if (entry) entry.action(row, action, control, state, send);
        else if (owner.action) owner.action(row, action, control);
      }
    });
  }
  return { register: register, compose: compose };
});
