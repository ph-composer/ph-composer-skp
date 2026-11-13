# PH-Composer help

Open this guide from Help & Diagnostics. The offline copy ships with your build.

## SketchUp compatibility

PH-Composer is tested on SketchUp 2026 for macOS. The code targets SketchUp 2023 and later
on macOS. Use Help & Diagnostics to check the version and platform of the running host.

## Installing and updating

In SketchUp, open Extensions > Extension Manager, choose Install Extension and select the
`.rbz` file. Use the same steps to replace an installed build. Restart SketchUp after installing.

Current release: none. Check https://github.com/ph-composer/ph-composer-skp/releases for published
builds. Help & Diagnostics shows your installed version and build.

## Checking the result of an edit

After 20 seconds without a reply, the panel offers Check status. It asks for the original
request's result and refreshes the panel.

- "PH-Composer did not receive that change": nothing was written. Repeat the edit if needed.
- "PH-Composer can no longer tell whether that change was applied": inspect the model first.

For a non-edit request, Stop waiting clears the wait. Check the result before repeating the request.

## When Export stops

If the runtime takes about 30 seconds to start or stops responding for five minutes, Export ends
before writing files. Try Export again. If it keeps stopping, save a support report.

## Messages you may see

- `request.not_received`: PH-Composer did not receive the change. Nothing was written.
- `request.outcome_unavailable`: the result is unknown. Check the model.
- `operation.rollback_unverified`: the change failed and rollback could not be confirmed.
  Check the model before continuing.
- `runtime.boot_timeout` or `runtime.unresponsive`: the runtime failed to start or stopped
  responding. Nothing was written.
- `runtime.conformance_failed`: HBJSON failed the final check. Nothing was written.

If a message offers Get help and shows a reference such as PHC-3FA9C1, include the reference
in your report.

## Fixing settings

In Help & Diagnostics, open More actions and choose Reset display preferences to restore the
default units, dimension formats, table views and Colour-by mode. To recover a panel that has
stopped drawing, choose Reopen panel. Apply any edits you want to keep before reopening.

Use the Libraries screen to reset unreadable library setup.

## Getting help

Open any SketchUp document, then choose Extensions > PH-Composer > Help and Diagnostics.
You can also open it from the bottom of the panel.

1. Choose Copy diagnostics or Save support report. Review the preview before sharing.
2. Choose Report a problem to open a public GitHub issue. Share the report and steps to
   reproduce the problem with a synthetic model.

Clear diagnostic history removes the local log. Keep any reports you need before clearing it.
If Help & Diagnostics cannot open, its fallback message shows the version, build and log folder.

## If SketchUp crashes

Follow the SketchUp crash reporter's instructions at
https://help.sketchup.com/en/sketchup/reporting-errors-bugsplat. Keep the crash details.
After restarting, open Help & Diagnostics and save a report. Include both in your issue.

## If PH-Composer does not load

Reinstall the `.rbz` and restart SketchUp. If loading still fails, report the version you
installed and check `PH-Composer/logs` inside SketchUp's support folder.
