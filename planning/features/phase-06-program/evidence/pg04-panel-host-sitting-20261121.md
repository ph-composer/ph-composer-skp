# PG04 panel run, host sitting 2026-11-21

Installed RBZ sha256 `4f3f3d66…a4cfe` at `08a06474`, SketchUp 26.1.188, Ruby 3.2.2, macOS. Fresh process on a fresh
copy of the synthetic two-Segment reference (House, ADU; sha256 `70e5bd6e`). The bridge rows are in
[the bridge run](pg04-host-sitting-20261121.md).

Control: background computer-use `app_*` cannot click or type into the panel's HtmlDialog (refused as a canvas view,
also with SketchUp fronted). Panel input was therefore a labelled development script event running the page's own
handlers; the evidence is native window pixels plus bridge reads. Every native gesture stays owed.

| Assertion | Result | Observation |
| --- | --- | --- |
| dialog-section-shown | pass | ADU (no stored payload) showed the five defaults: Residential, Phius 2021 CORE, Residential, In planning, New construction. Five values changed and saved (scripted input): notice "ADU settings saved.", stored and understood exactly, House untouched; reopened dialog shows them |
| dialog-section-gesture | unknown | Owed to a full-screen hold: background clicks and keys do not reach the web view |
