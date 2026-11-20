/* A development-only Building Segment settings section: the panel half of the note example_segment_note.rb
   registers (context/EXTENSIBILITY.md, "Building Segment settings"). It renders one field from its namespace's
   stored payload, reports a blank note as a problem, which keeps Save disabled, and gives Save the payload to
   send. Zones' dialog frame lists it after General by its order and names no section.

   It never ships. Load it into a running host with example_segment_note_load.rb; tools/ui-preview/index.html
   loads it after the kit starts. It is plain script, not a module: it reaches the kit through PhComposerUI.get. */
(function () {
  "use strict";

  var ui = PhComposerUI.get("workspace");

  PhComposerUI.get("panel").segmentSettingsSection("example.segment.note", {
    title: "Note", order: 90,
    // `draft` is a copy of the stored payload ({} when there is none); the section edits it and says so.
    render: function (segment, draft, context) {
      var input = ui.element("input");
      input.type = "text"; input.setAttribute("type", "text");
      input.setAttribute("aria-label", "Note text");
      input.value = draft.text || "";
      input.addEventListener("input", function () { draft.text = input.value; context.changed(); });
      var row = ui.element("div", "phc-segment-settings-row");
      row.appendChild(ui.element("span", "phc-segment-settings-label", "Text"));
      row.appendChild(input);
      return row;
    },
    validate: function (draft) { return String(draft.text || "").trim() ? [] : ["Enter a note."]; },
    collect: function (draft) { return { text: String(draft.text).trim() }; }
  });
}());
