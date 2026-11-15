"use strict";
/* Programs prototype: the scenes. Each shot is a PNG beside this page, captured by
   `make ui-gallery MOCKUP=planning/features/phase-06-program/mockups/programs.html`, which also rewrites the
   scene table in README.md. `do` names steps in app.js; `size` defaults to 1280x800; `hover` and `select`
   are Playwright selectors acted on after the replay. */
var SCENES = [
  { group: "1. Single-family home, five Zones, one dwelling",
    try: "Single dwelling is on: type the bedrooms on the Building Segment row. Click a locked cell, Open settings, uncheck Single dwelling, then click the House chip",
    shots: [
      { png: "j1-start", journey: 1 },
      { png: "j1-bedrooms", journey: 1, do: "house3" },
      { png: "j1-unlocked", journey: 1, do: "house3,unsingle,bubble" },
      { png: "j1-default-program", journey: 1, do: "pdefault" }] },
  { group: "2. Apartments, one Zone each",
    try: "Check every Zone, Dwelling: One dwelling each. Then check Single dwelling in the Building's settings to see its confirmation",
    shots: [
      { png: "j2-checked", journey: 2, do: "checkall" },
      { png: "j2-dwellings", journey: 2, do: "each,beds" },
      { png: "j2-single-confirm", journey: 2, do: "each,beds,trysingle" }] },
  { group: "3. Apartments plus corridors, lobby, stair, office, gym",
    try: "Apartments as in 2; pick Phius Multifamily Programs for the rest from the Program choice",
    shots: [
      { png: "j3-corridors-checked", journey: 3, do: "each,beds,checkcorr" },
      { png: "j3-common-areas", journey: 3, do: "each,beds,common" },
      { png: "j3-common-areas-420", journey: 3, do: "each,beds,common", size: "420x732" }] },
  { group: "Building Segments (journey 3, then 1)",
    try: "Check the Bike shed, Building Segment: No Building Segment or New Building Segment. Hover a Segment row: Settings and Delete appear in its Actions cell; settings is where it is renamed",
    shots: [
      { png: "j3-no-segment", journey: 3, do: "each,beds,common,moveshed" },
      { png: "j3-move-segment", journey: 3, do: "each,beds,common,checkshed" },
      { png: "j3-new-segment", journey: 3, do: "each,beds,common,newseg" },
      { png: "j3-segment-settings", journey: 3, do: "each,beds,common,segsettings" },
      { png: "j3-delete-segment", journey: 3, do: "each,beds,common,newseg,trydelete" },
      { png: "j1-segment-settings", journey: 1, do: "house3,segsettings" },
      { png: "j1-adu", journey: 1, do: "house3,adu" },
      { png: "j1-lock-bubble", journey: 1, do: "house3,lockinfo" },
      { png: "j1-segment-actions", journey: 1, do: "house3,adu", hover: "tr.zp-seg >> nth=1 >> td >> nth=1", note: "the ADU row hovered" }] },
  { group: "4. Non-residential school",
    try: "Unassigned Zones are flagged; assign from Phius Non-Residential, or browse the library sidebar",
    shots: [
      { png: "j4-start", journey: 4 },
      { png: "j4-assigned", journey: 4, do: "school" },
      { png: "j4-library", journey: 4, do: "school,libnr" },
      { png: "j4-long-name", journey: 4, do: "school,longname" }] },
  { group: "5. Custom lab programs",
    try: "Programs tab, + New Program in the sidebar, set loads, open a schedule",
    shots: [
      { png: "j5-program", journey: 5, do: "custom" },
      { png: "j5-program-420", journey: 5, do: "custom", size: "420x732" },
      { png: "j5-schedule", journey: 5, do: "custom,customsched" }] },
  { group: "Equipment Sets",
    try: "Programs tab, Equipment Sets: hover a device for Edit and Delete; Add device",
    shots: [
      { png: "equipment-sets", journey: 1, do: "sets", hover: ".zp-devices tbody tr >> nth=1" },
      { png: "device-edit", journey: 1, do: "sets,devedit" },
      { png: "device-add", journey: 1, do: "sets,devadd", select: ['dialog [name="type"]', "light_int"], note: "type Phius interior lighting" }] },
  { group: "Program cards and the ventilation Schedule",
    try: "Open and close the load cards; Schedules, SFH ventilation, change the hours",
    shots: [
      { png: "j4-program-cards", journey: 4, do: "school,libnr,cards" },
      { png: "j1-vent-schedule", journey: 1, do: "ventsched" }] },
  { group: "Zones → Spaces (journey 1, then 3)",
    try: "Zones, Spaces subtab. Type a Supply, Extract or Transfer rate on a Space and its Zone turns detailed; hover the Zone for From Program. Then compare Zones → Programs' Ventilation",
    shots: [
      { png: "j1-spaces", journey: 1, do: "house3,spaces" },
      { png: "j1-spaces-cascade", journey: 1, do: "house3,spaces,cascade" },
      { png: "j3-spaces", journey: 3, do: "each,beds,common,spaces,cascade" }] }
];
