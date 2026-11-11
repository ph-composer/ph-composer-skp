# Review evidence and reproduction

DATE: 2026-11-09. BASELINE: `f65ccee62b0a3994a46001d55f7aefd1a69f0faf`, API 1.31.
All Ruby checks used the repository's pinned Ruby 3.2.2 and existing offline SketchUp stub.
No install, native host change, real token/configuration write or live provider account was used.

## Retained evidence

| Evidence | Result | Meaning |
| --- | --- | --- |
| [discovery_probe.rb](discovery_probe.rb), [JSON inventory](discovery.json), [log](discovery-probe.log) | 1 test, 3 assertions, pass | Actual registry and external discovery/schema sizes; all current descriptions fit; metadata catalogs omitted externally |
| [feature_probe.rb](feature_probe.rb), [log](feature-probe.log) | 9 tests, 69 assertions, pass | Reproduces baseline unsafe ownership/identity/locks and incomplete receipts/recovery/bounds |
| [envelope_probe.rb](envelope_probe.rb), [log](envelope-probe.log) | 10 tests, 84 assertions, pass | Reproduces budget failures through actual MCP executor and preflight/extraction mismatch |
| [foundation-tests.log](foundation-tests.log) | 233 tests, 6,779 assertions, pass | Existing API/session/connection/token/retry/export suite |
| [feature-tests.log](feature-tests.log) | 249 tests, 7,396 assertions, pass | Existing Zones/Spaces/Thermal Bridge and shared API suites |
| [envelope-tests.log](envelope-tests.log) | 446 tests, 5,389 assertions, pass | Existing 41-file envelope/library/export/metadata suite |
| [agent-access-browser.log](agent-access-browser.log) | Passed | Existing Agent Access Chrome checks with synthetic UI state; all errors checked by shared collector |

All suite runs had zero failures, errors and skips. Suite selections overlap; do not add these counts
and call the sum unique tests. Review probes assert the observed baseline behavior, including defects;
their green result is evidence of reproduction, not a clean bill of health. Retained byte measurements
can vary slightly with generated IDs/timestamps. The fixtures use only synthetic data.

Browser screenshots/evidence were generated in a temporary review-specific folder and inspected for
New token and the narrow issued-token dialog. They were not copied into the repository; rerun the
check to regenerate them. Chrome results are not native HtmlDialog or client-connection acceptance.

## Reproduce

The retained probes assert behavior at `f65ccee62b0a3994a46001d55f7aefd1a69f0faf` and can fail
against later source that fixes a finding. To reproduce the historical receipts, use a disposable
checkout of that baseline and copy this evidence directory into the same repository-relative path.
Do not switch a shared checkout or overwrite this review's retained inventory/logs. From that
baseline checkout's root, with its `.ruby-version` active:

```sh
rbenv exec ruby -Itests planning/archive/agent-workflows-review-2026-11/evidence/discovery_probe.rb
rbenv exec ruby -Itests planning/archive/agent-workflows-review-2026-11/evidence/feature_probe.rb
rbenv exec ruby -Itests planning/archive/agent-workflows-review-2026-11/evidence/envelope_probe.rb
make ui-checks UI_CHECKS=tools/ui-preview/agent_access_checks.cjs
```

The inventory probe rewrites only its adjacent `discovery.json`. Tests use scratch credential/home
paths and a stub listener; they do not touch the user's client setup. The regular server suite also
uses isolated test sockets. Do not run these probes against a live model. After implementation,
update ordinary regression tests rather than silently rewriting historical review observations.

Focused existing suite selections (load each selected path with `require_relative` in one Ruby
process, as `ruby -Itests -e 'ARGV.each { |path| require_relative path }' <paths>`):

- Foundation: `tests/api_test.rb`, `api_client_test.rb`, `api_reference_test.rb`,
  `agent_access_tokens_test.rb`, `agent_access_server_test.rb`, `agent_access_write_tools_test.rb`,
  `agent_access_connections_test.rb`, `agent_access_client_config_test.rb`, `agent_guide_test.rb`,
  `caller_and_outcome_test.rb`, `context_navigation_test.rb`, `model_context_test.rb`,
  `sessions_test.rb`, `export_tasks_test.rb`, `approved_locations_test.rb` (all under `tests/`).
- Geometry: `tests/{api_client,api_reference,agent_guide,zone_face,zone_options,zone_solve_scope,
  zones_containment,spaces_operations,spaces_candidate_faces,spaces_paged_reads,spaces_context,
  thermal_bridge_assignment,thermal_bridge_schedule,thermal_bridge_export}_test.rb`.
- Envelope: 41 paths listed in [suite-files.txt](suite-files.txt), selected once before the run.

## Limits and source drift

No new real-host or fresh-client acceptance ran, so drawing-gesture cooperation is an unverified
risk. Existing archived Phase 3a1, envelope and thermal host receipts are historical evidence only.
No current SketchUp 2023, Windows, performance or release assurance is implied. No full `make ci`
was needed for these review/planning-only edits; focused existing suites support the investigation.

The primary checkout advanced from its initial SUI-02 branch to SUI-03 during the audit. Immutable
`f93d8b6b` was inspected for its direct claim guard, which partially addresses R01. No worktree rebase
or alternate-head test was performed. Every future fix must rerun the relevant reproduction on
current merged source; especially recheck R01/R04 before changing active Spaces code.

Publication update, 2026-11-10: the documentation branch advanced to `6d06ff49` and the Spaces
packet links were updated to its archive. No baseline probe or feature suite was rerun as part of
publication. A focused consistency review and the repository's staged documentation checks cover
the publication diff; [planning-validation.log](planning-validation.log) records the link/scope check.
