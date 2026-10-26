# Standalone Ruby volume and airflow groundwork

DATE: 2026-10-07
STATUS: Merged through PR #84 on 2026-10-07

## Scope and identity

Ed confirmed extracting this slice from the units packet on 2026-10-07. It delivers Ruby
report definitions and tests only. P3a-01 reuses the groundwork; no Spaces stage or later
feature is implemented or accepted by this evidence.

Branch `codex/units`, based on `da88d06`; planning intake committed as `6d68801`.
Verified source Git blob identities:

- `src/ph_composer/core/units.rb`: `921da7db0bd5fdeec77fd1b5e210261df7fb2c17`
- `tests/units_test.rb`: `dda51cb60d35c7f0830689095f2ac4f6d9d0b0ac`

## Behavior and focused checks

Ruby reuses the existing foot constant to derive ft³/m³. Volume uses that factor and two
decimal places in SI and IP. Airflow divides it by 60, using m³/h and cfm with one decimal
place in either system. Formatting continues through the existing report formatter.

The formatting test first failed with `Unknown quantity: volume`. After implementation,
the existing shared-vector test covers all ten Ruby quantities and checks SI identity as
well as known IP values. Formatting examples include `1 m³` / `35.31 ft³` and
`100 m³/h` / `58.9 cfm`. Ruby has no reverse conversion/parser API; the unchanged panel
units suite verifies SI/IP input aliases and conversion to canonical values.

| Check | Result |
| --- | --- |
| Focused Ruby units, 2.7.2 and 3.2.2 | Each: 4 runs, 54 assertions, zero failures/errors/skips |
| JavaScript units, memory guard and 60-second per-test timeout | 19 tests passed, zero skips |
| Focused RuboCop | One test alignment offense corrected; final full lint passed |
| Ruby line coverage, 3.2.2 | 97.0% of 15,397 lines, above 93%; 1,451 runs and 14,761 assertions passed |
| `make ci`, Ruby 3.2.2 | Passed: 1,451 Ruby runs / 14,761 assertions; 475 JS tests; 191 Python tests; all lint, fixtures, manifests, runtime pins, hostkit, typing and RBZ checks passed |
| `make ci`, Ruby 2.7.2 | Passed: same test counts as 3.2.2; all lint, fixtures, manifests, runtime pins, hostkit, typing and RBZ checks passed |

No HTML or Python payload changed, so no runtime-manifest refresh was needed. The final
runtime check verifies 118 assets and eight wheels. This proves the offline build only.

## Review and limits

Local review of this trivial table-only code diff applied the contributor architecture
rubric. No actionable finding: the shared definitions own the new rows, existing report
formatting and constants are reused, and no feature-specific branch or host access is added.
RuboCop's existing method/class size checks pass; no new method or branching is introduced.
The repository provides no cyclomatic-complexity or CRAP gate for this slice.

Native acceptance was not run because this extraction changes no screen, record,
transaction, host lifecycle or export serialization. Actual Spaces report/screen integration,
saved layout and repaint measurement remain with their owners. SketchUp 2023 host proof,
Windows and public release gates remain open. The cross-phase units packet stays active.

Whitespace checks and local Markdown file-link validation passed for the final changed documents.
Delivery: pushed on `codex/units` as [PR #84](https://github.com/ph-composer/ph-composer-skp/pull/84),
merged to `main` at `2195f54` on 2026-10-07. No installation or deployment was performed. Source and test blob identities
above are unchanged by the delivery documentation update.

Final delivery verification: both remote `make ci` jobs passed on head `e4e914a`, including the
added acceptance-ledger cleanup. Its eight focused tests, Ruff lint/format, mypy and full ledger
validation passed; one bounded independent review found no actionable issues. Merge `2195f54`
is on `origin/main` and has the exact same tree as that reviewed head. The completed branch
was removed locally and remotely. The units packet remains active for feature-owned follow-ups.
