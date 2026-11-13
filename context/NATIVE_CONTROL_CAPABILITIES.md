# Native control capabilities

Choose a control route for the assertion you need to observe. The routes below were exercised
on SketchUp 26.1.188 for macOS. Recheck them when the host or controller changes.
[Measured host behavior](SKETCHUP_HOST_BEHAVIOR.md) covers the SketchUp API.
Use the [native acceptance procedure](../.agents/skills/ph-composer-native-acceptance/SKILL.md)
to run and record a case.

| Claim/action | Preferred control and evidence | Limit or fallback |
| --- | --- | --- |
| Model/session, edit path, records and actual references | Development bridge readback; product mutations through public operations | Read after action in a separate call. An eval sleep prevents host timers from running; wait with `host_bridge.py wait-for`, which polls a named read in separate calls under one deadline. `host_bridge.py diagnostics` reads the log for the same session or run. |
| Native Undo/Redo, menus, keyboard and dialog behavior | Available native controller; compare records before/after through bridge | Bridge-triggered menu actions are asynchronous; callbacks called directly are offline simulation. |
| Overlay/HUD, occlusion, hatch, hover and visual layout | Real window capture and native interaction | Bridge `shot` uses `View#write_image`, which omits overlay/tool/HUD drawing. |
| Floating Overlays inspector | Fresh native snapshot, target the actual inspector and verify overlay enabled state | Refresh targeting once if the inspector is unavailable. Ask for one checkbox action if it still fails, then read the resulting state. |
| Hold mouse while switching Model or edit context | Separate button-down/up controls if supported by the current controller | If the controller completes a drag in one call, ask the operator to hold and release while the bridge traces the transition. |
| Pending export plus Model/panel/runtime loss | Read task stage before triggering loss; later session/file readback | Use an explicit tools-only runtime delay when ordinary completion is too fast. Remove it in a fresh normal process afterward. |
| Destination selection | Native Save dialog navigation followed by actual path readback | Navigate with the dialog's folder controls. Typing a full path produced a filename with colons in Documents. |
| Missing/blank window | Refresh current surface and check active Space/document | Read bridge state to confirm whether the panel is open. |
| Window-bounded capture and menu labels | Current native computer-use controller: bind SketchUp, capture its window, read fresh accessibility state and invoke the observed menu item | Use a window-bounded `getScreenshot` call for pixel evidence. The combined accessibility and screenshot call did not consistently return pixels. |
| Escape inside the panel | The background controller's `app_key escape` on the panel window, with the bridge reading the Model before and after | On 2026-10-04 (ZT-07) background Escape reached the web view and drove its Escape layers. On 2026-10-03 a synthesized Escape did not, while Backspace, Enter and letters did; if it fails again, ask for one physical keypress. |
| Panel clicks and Edit > Undo | Background control (`app_click`, `app_type`, `app_menu`) on the panel and model windows, with the bridge reading the Model before and after | On 2026-10-26 (thermal bridges T09) background clicks and typing reached the panel throughout a long session, and Edit read "Undo <operation>" and undid and redid once a click on the model window's title bar made it key. For Save and Close under background control, use `host_bridge.py save` and the window close button |
| Panel form fields | Click the field, then type; for a `<select>`, focus it (click a neighbouring field, then Tab or Shift+Tab) and press the option's first letter | Opening a select's popup and choosing in it did not stick, and a background `mode: replace` did not select a field's text: place the caret, End, Backspace, then type (T09, 2026-10-26). Read the value back before relying on it |
| Viewport clicks for a tool | Background `app_click` on the model window at the target's screen point: `view.screen_coords` read through the bridge, scaled to the window's screenshot frame (measure the scale and toolbar offset on the active display) | The edge tool took single clicks this way (T09). A press may carry the Command key; check the selection afterwards |
| A context-menu item | SketchUp's Edit > "<n> <entities>" selection submenu through `app_menu`: it carries extension context-menu items, the same handlers a right-click shows | A full-screen right-click can be refused when another app's window overlays the viewport (T09); the menu bar route needs no full-screen control. A right-click itself is then not observed |
| Controls shown only on hover (header and row icons) | Inject a dev-only style through `dialog.execute_script` that sets them visible, target them by coordinate, then remove the style before any at-rest check | Background control cannot hover. Never leave the style in place while judging what shows at rest (2026-10-04, ZT-07). |
| Reading panel DOM state into Ruby | A development callback registered before the panel's `show`, or window pixels | On SketchUp 26.1.188 (2026-10-15, E18) `add_action_callback` on an already shown HtmlDialog never reached `window.sketchup`, even after `set_file` reloaded the page. Read pixels instead, or wrap the dialog's construction in a development helper. |
| Pointer drags inside the panel | Full-screen native control: `left_mouse_down`, stepped moves, a capture while held, `left_mouse_up` | Hover-revealed handles appear for the real pointer, so no visibility style is needed when the pointer passes over the row first (E18). Bridge-driven focus changes (`Sketchup.focus`) work while the button is held, to test blur. |
| An agent write while a native viewport gesture is partway through (Move click-move, held drag, Line; Rotate and Scale click-move) | Full-screen native control in one approved, uninterrupted hold, run from the conductor session, with every held row batched into one recipe; the bridge and the client recorder read tool state, refusals and the Undo stack | Run the held gesture in the foreground. Use [AW10 evidence](../planning/native-acceptance/evidence/aw10-integrated-acceptance-2026-11-10.md) for the observed writes and Undo results. |
| Fresh process / install | Existing hostkit launch and build/install workflow | Inspect all open documents first. `launch` quits the host and may kill it after timeout; a scratch save does not authorize discarding unrelated work. |

For a handoff, name the starting state, target, expected cue and when to release or stop.
Activate the document before the gesture. Verify the edit path and tool state through the
bridge. Check that the recorder works before starting. Use the
[run procedure](../tools/hostkit/ACCEPTANCE_RUN.md) to capture evidence.

## Capability changes and restoration

Verify new controller capabilities on a synthetic case before updating this reference.
For repeatable fault cases, use `host_bridge.py fault arm`. Verify `restored: true` from
`fault restore`, then restart the normal build and confirm its expected behavior.

Evidence includes [Phase 2 groundwork observations](../planning/archive/phase-02-envelope/evidence/p2-01-groundwork.md),
[thermal bridges T09](../planning/archive/phase-03b-thermal-bridges/evidence/p3b-09-acceptance.md),
[Colour-by toggle continuation](../planning/archive/phase-01-faces-and-zones/evidence/p1-d-colour-by-continuation.md),
[held gesture/context continuation](../planning/archive/phase-01-faces-and-zones/evidence/p1-d-keyboard-context.md),
[export lifecycle and restoration](../planning/archive/phase-01-faces-and-zones/evidence/p1-e-export-workflow.md),
[R06 rerun](../planning/native-acceptance/evidence/r06-rerun-2026-09-30.md),
[Library product tabs](../planning/native-acceptance/evidence/library-product-tab-headers-2026-10-03.md),
[Assembly Layer drag](../planning/native-acceptance/evidence/assembly-layer-drag-2026-10-15.md).
