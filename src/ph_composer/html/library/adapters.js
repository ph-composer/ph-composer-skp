/* A placement supplies its record kind, presentation and target validation. The sidebar knows no feature, and no
   kind's vocabulary: a library row's label is `display_label`, the host's projection through the kind adapter. A
   placement whose local records have their own label word supplies `name` for them, and `localLabel` names the
   source choice for this file's records ("Materials in this file"). */
PhComposerUI.define("library/adapters", ["workspace"], function (ui) {
  "use strict";
  function adapter(options) {
    return Object.assign({ title: "Library", localLabel: "In this file", read: function () { return []; },
      categories: function () { return []; }, properties: [],
      name: function (row) { return row.display_label || row.id; },
      searchText: function (row) { return [this.name(row), row.values.category, row.values.notes].join(" "); },
      category: function (row) { return row.values.category || ""; },
      decorate: function () {}, target: function () { return { hint: "Choose a target first." }; },
      emptyText: "No records in this file.", compare: function (a, b) { return ui.compareText(a, b); }
    }, options);
  }
  return { adapter: adapter };
});
