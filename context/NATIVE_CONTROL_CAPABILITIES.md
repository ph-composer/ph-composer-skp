# Native-control capabilities

DATE: 2026-10-01, updated 2026-10-26
STATUS: Development guidance grounded in SketchUp 26.1.188 on the current macOS system.

Choose the control by the claim being tested. Recheck current tool capabilities when they change;
these are observed limitations of this run, not permanent limits of SketchUp or every controller.
[Host behavior](SKETCHUP_HOST_BEHAVIOR.md) owns measured API facts. The
[native acceptance skill](../.agents/skills/ph-composer-native-acceptance/SKILL.md) owns execution.

| Claim/action | Preferred control and evidence | Limit or fallback |
| --- | --- | --- |
| Model/session, edit path, records and actual references | Development bridge readback; product mutations through public operations | Read after action in a separate call. An eval sleep prevents host timers from running; wait with `host_bridge.py wait-for`, which polls a named read in separate calls under one deadline. `host_bridge.py diagnostics` reads the log for the same session or run. |
| Native Undo/Redo, menus, keyboard and dialog behavior | Available native controller; compare records before/after through bridge | Bridge-triggered menu actions are asynchronous; callbacks called directly are offline simulation. |
| Overlay/HUD, occlusion, hatch, hover and visual layout | Real window capture and native interaction | Bridge `shot` uses `View#write_image`, which omits overlay/tool/HUD drawing. |
| Floating Overlays inspector | Fresh native snapshot, target the actual inspector and verify overlay enabled state | This inspector was inconsistently exposed/clickable. After one refreshed targeting attempt still fails, ask for one checkbox action, then machine readback. No repeated coordinate guessing. |
| Hold mouse while switching Model or edit context | Separate button-down/up controls if supported by the current controller | The run's drag API completed in one call. Human holds/releases while the bridge traces the transition. Do not replace the gesture with manually invoked callbacks and call it native proof. |
| Pending export plus Model/panel/runtime loss | Read task stage before triggering loss; later session/file readback | Use an explicit tools-only runtime delay when ordinary completion is too fast. Remove it in a fresh normal process afterward. |
| Destination selection | Native Save dialog navigation followed by actual path readback | An entered full path became a colon filename in Documents in this run. Use the dialog's folder navigation; do not assume the requested directory was selected. |
| Missing/blank window | Refresh current surface and check active Space/document | A missing capture is not proof of a failed panel. Bridge state may remain available. |
| Window-bounded capture and menu labels | Current native computer-use controller: bind SketchUp, capture its window, read fresh accessibility state and invoke the observed menu item | Window screenshots and native menu targeting worked on 2026-10-01 for SketchUp and PH-Composer. The 2026-09-30 capture limitation is historical. `getScreenshot` returned pixels; an AX-plus-screenshot call did not consistently include pixels. Use the explicit screenshot call when needed. Never capture the full screen. |
| Escape inside the panel | The background controller's `app_key escape` on the panel window, with the bridge reading the Model before and after | On 2026-10-04 (ZT-07) background Escape reached the web view and drove its Escape layers. On 2026-10-03 a synthesized Escape did not, while Backspace, Enter and letters did; if it fails again, ask for one physical keypress. |
| Panel clicks and Edit > Undo | Background control (`app_click`, `app_type`, `app_menu`) on the panel and model windows, with the bridge reading the Model before and after | On 2026-10-26 (thermal bridges T09) background clicks and typing reached the panel throughout a long session, and Edit read "Undo <operation>" and undid and redid once a click on the model window's title bar made it key. The 2026-10-03 run, where clicks stopped reaching the panel and Undo stayed disabled, is historical. File > Save and File > Close stay disabled under background control: save with `host_bridge.py save` and close a window with its close button |
| Panel form fields | Click the field, then type; for a `<select>`, focus it (click a neighbouring field, then Tab or Shift+Tab) and press the option's first letter | Opening a select's popup and choosing in it did not stick, and a background `mode: replace` did not select a field's text: place the caret, End, Backspace, then type (T09, 2026-10-26). Read the value back before relying on it |
| Viewport clicks for a tool | Background `app_click` on the model window at the target's screen point: `view.screen_coords` read through the bridge, scaled to the window's screenshot frame (on T09's display, x times 0.738, and y times 0.738 plus the 49-point toolbar band) | The edge tool took single clicks this way (T09). A press may carry the Command key; check the selection afterwards |
| A context-menu item | SketchUp's Edit > "<n> <entities>" selection submenu through `app_menu`: it carries extension context-menu items, the same handlers a right-click shows | A full-screen right-click can be refused when another app's window overlays the viewport (T09); the menu bar route needs no full-screen control. A right-click itself is then not observed |
| Controls shown only on hover (header and row icons) | Inject a dev-only style through `dialog.execute_script` that sets them visible, target them by coordinate, then remove the style before any at-rest check | Background control cannot hover. Never leave the style in place while judging what shows at rest (2026-10-04, ZT-07). |
| Reading panel DOM state into Ruby | A development callback registered before the panel's `show`, or window pixels | On SketchUp 26.1.188 (2026-10-15, E18) `add_action_callback` on an already shown HtmlDialog never reached `window.sketchup`, even after `set_file` reloaded the page. Read pixels instead, or wrap the dialog's construction in a development helper. |
| Pointer drags inside the panel | Full-screen native control: `left_mouse_down`, stepped moves, a capture while held, `left_mouse_up` | Hover-revealed handles appear for the real pointer, so no visibility style is needed when the pointer passes over the row first (E18). Bridge-driven focus changes (`Sketchup.focus`) work while the button is held, to test blur. |
| Fresh process / install | Existing hostkit launch and build/install workflow | Inspect all open documents first. `launch` quits the host and may kill it after timeout; a scratch save does not authorize discarding unrelated work. |

A human handoff names one action, its starting state, when to release/stop, the expected visible cue,
and the observation needed. Activate the document before a held gesture; verify tool/edit path and
target through current native state plus bridge readback. In the Phase 2 run, coordinate targeting
failed while accessibility window activation worked. A dotted Group boundary indicated entry into
an edit context; no confirmation dialog was expected. Test actual probe callbacks and evidence
writing before asking for a hold/release. See the [run procedure](../tools/hostkit/ACCEPTANCE_RUN.md).
Tools should collect console/state/results themselves. Human confirmation establishes only the
reported observation; bridge readback supplies the corresponding Model/task assertion.

## Capability changes and restoration

If a new controller can hold a button across calls or reliably address floating windows, verify it
with a harmless synthetic case and update this reference. Do not require human help by habit.
After development provider/fault overrides, restart the normal installed extension, verify no
helper override/live runtime remains, and record the normal build's expected behavior. Arm a
repeatable fault with `host_bridge.py fault arm` rather than a one-off prepend: its `restore` reads the
target back against the arm baseline and must report `restored: true` before the fresh process.

Sources: [Phase 2 groundwork observations](../planning/archive/phase-02-envelope/evidence/p2-01-groundwork.md),
[thermal bridges T09](../planning/archive/phase-03b-thermal-bridges/evidence/p3b-09-acceptance.md),
[Colour-by toggle continuation](../planning/archive/phase-01-faces-and-zones/evidence/p1-d-colour-by-continuation.md),
[held gesture/context continuation](../planning/archive/phase-01-faces-and-zones/evidence/p1-d-keyboard-context.md),
[export lifecycle and restoration](../planning/archive/phase-01-faces-and-zones/evidence/p1-e-export-workflow.md),
[R06 rerun](../planning/native-acceptance/evidence/r06-rerun-2026-09-30.md),
[Library product tabs](../planning/native-acceptance/evidence/library-product-tab-headers-2026-10-03.md),
[Assembly Layer drag](../planning/native-acceptance/evidence/assembly-layer-drag-2026-10-15.md).
