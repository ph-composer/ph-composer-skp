/* A choice applied at once in a table cell, drawn as the tables' enum pill. `choices` are { value, label }, `value`
   the Model's, `choose(chosen, select)` applies one; the cell shows the Model's value until the change lands. The
   select is kept across repaints, so focus a dialog returns to it finds it. */
PhComposerUI.define("choice_cell", ["dom"], function (dom) {
  "use strict";
  return function choiceCell(td, options) {
    var select = td.choiceSelect;
    if (!select) {
      select = td.choiceSelect = dom.element("select", "phc-enum-cell");
      select.addEventListener("change", function () {
        var current = select.choiceOptions, chosen = select.value;
        select.value = current.value;
        if (chosen !== current.value) current.choose(chosen, select);
      });
    }
    select.choiceOptions = options;
    var listed = JSON.stringify(options.choices);
    if (select.choiceListed !== listed) {
      select.choiceListed = listed;
      select.replaceChildren();
      options.choices.forEach(function (choice) { select.appendChild(dom.option(choice.value, choice.label)); });
    }
    select.value = options.value;
    select.disabled = Boolean(options.disabled);
    select.setAttribute("aria-label", options.label);
    if (select.parentNode !== td) td.replaceChildren(select);
    td.classList.add("phc-editable-cell");
    return select;
  };
});
