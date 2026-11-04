/* The drawing's contextual Layer menu. */
PhComposerUI.define("features/assemblies/layer_tools", ["features/assemblies/editor_shared", "workspace"],
  function (shared, ui) {
    "use strict";
    function menu(owner, record, layer, membrane, trigger, title, options) {
      options = options || {};
      var bubble = new ui.Bubble(trigger, title, { ownTrigger: true,
        detachedTrigger: Boolean(options.detachedTrigger), onOpen: options.onOpen, onClose: options.onClose });
      bubble.panel.setAttribute("data-layer-tools-key", (options.detachedTrigger ? "drawing:" : "toolbar:") + layer.id);
      function open() {
        if (!bubble.panel.hidden) { bubble.close(true); return; }
        if (owner.allowed()) bubble.open();
      }
      trigger.addEventListener("click", open);
      trigger.addEventListener("keydown", function (event) {
        if (event.key === "ArrowDown" || event.key === "ArrowRight") { event.preventDefault(); open(); }
      });
      [["Add outside", "outside"], ["Add inside", "inside"]].forEach(function (item) {
        var button = ui.button(item[0], function () {
          bubble.close(false);
          owner.insert({ kind: "layer", action: "layers.add", params: { anchor_layer_id: layer.id,
            side: item[1], thickness_mm: shared.newSize("layer") } });
        });
        button.setAttribute("data-builder-action", "layers.add"); bubble.content.appendChild(button);
      });
      [["Move outward", "outward"], ["Move inward", "inward"]].forEach(function (item) {
        var button = ui.button(item[0], function () {
          owner.action("layers.move", { layer_id: layer.id, direction: item[1] });
        });
        button.setAttribute("data-builder-action", "layers.move"); bubble.content.appendChild(button);
      });
      var barrier = record.values.air_barrier, choices = ui.element("div", "assembly-bubble-choices");
      choices.appendChild(ui.element("small", "muted", "Air barrier"));
      [["none", "None"], ["exterior", "Exterior face"], ["interior", "Interior face"]].forEach(function (item) {
        var choice = ui.button(item[1], function () {
          var params = { layer_id: item[0] === "none" ? null : layer.id };
          if (item[0] !== "none") params.face = item[0];
          bubble.close(false); owner.action("layers.set_air_barrier", params);
        });
        choice.className = "phc-setting-choice";
        choice.setAttribute("aria-label", item[0] === "none" ? "No air barrier" : item[1] + " air barrier");
        choice.setAttribute("aria-pressed", String(item[0] === "none" ? !barrier :
          barrier && barrier.layer_id === layer.id && barrier.face === item[0]));
        choices.appendChild(choice);
      });
      bubble.content.appendChild(choices);
      if (membrane) bubble.content.appendChild(ui.element("p", "muted",
        "Membranes carry no thermal resistance and are excluded from total thickness."));
      var remove = ui.button("Delete Layer", function () {
        bubble.close(false);
        owner.remove("layers.remove", { layer_id: layer.id }, "Delete Layer", layer.segments.some(function (segment) {
          return Boolean(segment.material_id);
        }) ? "Delete this Layer and all its Layer-Segments, including their Material assignments?" : null);
      }, record.values.layers.length === 1);
      remove.classList.add("phc-danger-action");
      remove.setAttribute("data-builder-action", "layers.remove"); bubble.content.appendChild(remove);
      return bubble;
    }
    return { menu: menu };
  });
