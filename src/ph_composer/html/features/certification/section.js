/* The Phius certification section of the Building Segment settings dialog (context/EXTENSIBILITY.md, "Building
   Segment settings"): the building category, certification program, building use, building status and building
   type of one Segment, each a choice. It edits a draft of its namespace's payload, which Zones' Save sends with
   the dialog's other sections in one Undo step; the certification feature's validator checks it there too. A
   Segment with no settings shows the defaults, and Save sends all five once the user changes one. The values and
   defaults are Ruby's (features/certification/segment.rb); this file only labels them. */
PhComposerUI.define("features/certification/section", ["panel", "workspace"], function (panel, ui) {
  "use strict";
  var NAMESPACE = "ph_composer.certification.segment";
  // Each field in the order the section shows it, with its label and each value's label in the order offered.
  var FIELDS = [
    { key: "category", label: "Building category", values: [["residential", "Residential"],
      ["non_residential", "Non-residential"]] },
    { key: "program", label: "Certification program", values: [["phius_2021_core", "Phius 2021 CORE"],
      ["phius_2021_zero", "Phius 2021 ZERO"], ["phius_2018_core", "Phius 2018 CORE"],
      ["phius_2018_zero", "Phius 2018 ZERO"], ["phius_2018", "Phius 2018"], ["phius_2015", "Phius 2015"]] },
    { key: "use", label: "Building use", values: [["residential", "Residential"],
      ["office_administrative", "Office / administrative"], ["school", "School"], ["other", "Other"],
      ["undefined_unfinished", "Undefined / unfinished"]] },
    { key: "status", label: "Building status", values: [["in_planning", "In planning"],
      ["under_construction", "Under construction"], ["complete", "Complete"]] },
    { key: "type", label: "Building type", values: [["new_construction", "New construction"],
      ["retrofit", "Retrofit"], ["mixed", "Mixed"]] }
  ];
  var DEFAULTS = { category: "residential", program: "phius_2021_core", use: "residential", status: "in_planning",
    type: "new_construction" };

  function offered(field, value) {
    return field.values.some(function (pair) { return pair[0] === value; });
  }

  function choice(field, draft, context) {
    var select = ui.element("select");
    select.setAttribute("aria-label", field.label);
    field.values.forEach(function (pair) {
      var option = ui.element("option", "", pair[1]);
      option.value = pair[0];
      select.appendChild(option);
    });
    select.value = draft[field.key];
    select.disabled = Boolean(context.readOnly);
    select.addEventListener("change", function () { draft[field.key] = select.value; context.changed(); });
    var row = ui.element("div", "phc-segment-settings-row");
    row.appendChild(ui.element("span", "phc-segment-settings-label", field.label));
    row.appendChild(select);
    return row;
  }

  panel.segmentSettingsSection(NAMESPACE, {
    title: "Phius certification", order: 30,
    // `draft` is the stored payload, or {} for a Segment with none: a field it lacks shows its default. A stored
    // value the section does not offer is kept, so the choice shows none and its problem holds Save until the
    // user picks one, rather than being replaced unseen.
    render: function (segment, draft, context) {
      var part = ui.element("div");
      FIELDS.forEach(function (field) {
        if (!Object.prototype.hasOwnProperty.call(draft, field.key)) draft[field.key] = DEFAULTS[field.key];
        part.appendChild(choice(field, draft, context));
      });
      return part;
    },
    validate: function (draft) {
      return FIELDS.filter(function (field) { return !offered(field, draft[field.key]); }).map(function (field) {
        return "Choose a " + field.label.toLowerCase() + ".";
      });
    },
    collect: function (draft) {
      var payload = {};
      FIELDS.forEach(function (field) { payload[field.key] = draft[field.key]; });
      return payload;
    }
  });

  return { NAMESPACE: NAMESPACE, FIELDS: FIELDS, DEFAULTS: DEFAULTS };
});
