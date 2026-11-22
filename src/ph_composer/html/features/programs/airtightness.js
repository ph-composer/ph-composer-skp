/* The Airtightness section of the Building Segment settings dialog (context/EXTENSIBILITY.md, "Building Segment
   settings"): one Segment's blower-door test result, n50 in 1/h or q50 in m³/h·m², and its wind exposure. It edits
   a draft of its namespace's payload, which Zones' Save sends with the dialog's other sections in one Undo step;
   the programs feature's validator checks it there too. A blank result means no test result: the Zones then keep
   their Program's infiltration. The values, defaults and the conversion at export are Ruby's
   (features/programs/airtightness.rb, conversion.rb); this file only labels them and reads the typed number. */
PhComposerUI.define("features/programs/airtightness", ["panel", "workspace"], function (panel, ui) {
  "use strict";
  var NAMESPACE = "ph_composer.programs.airtightness";
  var BASES = [["n50", "n50", "1/h"], ["q50", "q50", "m³/h·m²"]];
  var WIND_EXPOSURES = [
    ["several_sides_no_screening", "Several sides exposed, no screening"],
    ["several_sides_moderate_screening", "Several sides exposed, moderate screening"],
    ["several_sides_high_screening", "Several sides exposed, high screening"],
    ["one_side_no_screening", "One side exposed, no screening"],
    ["one_side_moderate_screening", "One side exposed, moderate screening"],
    ["one_side_high_screening", "One side exposed, high screening"],
    ["user_defined", "User defined"]
  ];
  var DEFAULTS = { basis: "n50", value: null, wind_exposure: "several_sides_no_screening" };
  var NOTE = "Converted at export into each Zone's Infiltration, replacing the Program's value.";

  function offered(pairs, value) {
    return pairs.some(function (pair) { return pair[0] === value; });
  }

  function unit(basis) {
    var found = BASES.filter(function (pair) { return pair[0] === basis; })[0];
    return found ? found[2] : "";
  }

  var DECIMAL = /^\+?(\d+\.?\d*|\.\d+)(e[-+]?\d+)?$/i;

  /* The typed result: null when blank, the number when it is a decimal greater than 0, else undefined. */
  function parsed(value) {
    if (value === null || value === undefined) return null;
    var text = String(value).trim();
    if (text === "") return null;
    var number = DECIMAL.test(text) ? Number(text) : NaN;
    return isFinite(number) && number > 0 ? number : undefined;
  }

  function select(label, pairs, value, disabled, changed) {
    var control = ui.element("select");
    control.setAttribute("aria-label", label);
    pairs.forEach(function (pair) {
      var option = ui.element("option", "", pair[1]);
      option.value = pair[0];
      control.appendChild(option);
    });
    control.value = value;
    control.disabled = disabled;
    control.addEventListener("change", function () { changed(control.value); });
    return control;
  }

  function row(label, content) {
    var part = ui.element("div", "phc-segment-settings-row");
    part.appendChild(ui.element("span", "phc-segment-settings-label", label));
    part.appendChild(content);
    return part;
  }

  panel.segmentSettingsSection(NAMESPACE, {
    title: "Airtightness", order: 40,
    // `draft` is the stored payload, or {} for a Segment with none: a field it lacks shows its default. A stored
    // choice the section does not offer is kept, so the select shows none and its problem holds Save until the
    // user picks one, rather than being replaced unseen.
    render: function (segment, draft, context) {
      var part = ui.element("div");
      // A stored payload that is not an object cannot be edited here; it is kept as stored, and the dialog's
      // other sections still save.
      if (!draft || typeof draft !== "object" || Array.isArray(draft)) {
        part.appendChild(row("Settings", ui.element("span", "", "These settings cannot be read, so they are kept " +
          "as stored and the export refuses them.")));
        return part;
      }
      Object.keys(DEFAULTS).forEach(function (key) {
        if (!Object.prototype.hasOwnProperty.call(draft, key)) draft[key] = DEFAULTS[key];
      });
      var disabled = Boolean(context.readOnly);
      // The basis, the value and its unit read as one line, like the dialog's other rows.
      var result = ui.element("span", "phc-airtightness-result");
      var unitLabel = ui.element("span", "phc-airtightness-unit", unit(draft.basis));
      var basis = select("Test result basis", BASES, draft.basis, disabled, function (value) {
        draft.basis = value; unitLabel.textContent = unit(value); context.changed();
      });
      var value = ui.element("input");
      value.type = "text"; value.setAttribute("type", "text"); value.setAttribute("inputmode", "decimal");
      value.setAttribute("aria-label", "Test result");
      value.size = 6;
      value.value = draft.value === null || draft.value === undefined ? "" : String(draft.value);
      value.disabled = disabled;
      value.addEventListener("input", function () { draft.value = value.value; context.changed(); });
      result.appendChild(basis); result.appendChild(value); result.appendChild(unitLabel);
      part.appendChild(row("Test result", result));
      part.appendChild(row("Wind exposure", select("Wind exposure", WIND_EXPOSURES, draft.wind_exposure, disabled,
        function (choice) { draft.wind_exposure = choice; context.changed(); })));
      part.appendChild(ui.element("p", "phc-zone-option-help", NOTE));
      return part;
    },
    validate: function (draft) {
      var problems = [];
      if (!offered(BASES, draft.basis)) problems.push("Choose n50 or q50.");
      if (parsed(draft.value) === undefined) problems.push("Enter a test result greater than 0, or leave it blank.");
      if (!offered(WIND_EXPOSURES, draft.wind_exposure)) problems.push("Choose a wind exposure.");
      return problems;
    },
    collect: function (draft) {
      return { basis: draft.basis, value: parsed(draft.value), wind_exposure: draft.wind_exposure };
    }
  });

  return { NAMESPACE: NAMESPACE, BASES: BASES, WIND_EXPOSURES: WIND_EXPOSURES, DEFAULTS: DEFAULTS, parsed: parsed };
});
