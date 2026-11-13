# PH-Composer repository guidance

PH-Composer authors Phius passive building models in SketchUp. The SKP owns the building data.
Library imports create editable local records. Users choose and configure their own providers.
HBJSON is the canonical export.

## Find the owning document

| Work | Read |
| --- | --- |
| User workflow and planned product scope | [Documentation](docs/.index.md) |
| Ruby, JavaScript and Python implementation | [Engineering context](context/.index.md) and [coding standards](context/CODING_STANDARDS.md) |
| Registration, operations, revisions, records and references | [Core contracts](context/CONTRACTS.md) |
| New features, providers, exporters and UI contributions | [Contributor architecture](context/EXTENSIBILITY.md) |
| SketchUp transactions, observers and compatibility | [Technical architecture](context/TECH_STACK.md) and [measured host behavior](context/SKETCHUP_HOST_BEHAVIOR.md) |
| Local agent access and user grants | [Agent interface](context/AGENT_INTERFACE.md) and [client setup](docs/AGENT_ACCESS.md) |
| Build, test and release | [Development guide](docs/DEVELOPMENT.md) |
| Security reports and implementation | [Security policy](docs/SECURITY.md), [listener rules](context/AGENT_INTERFACE.md#security-posture) and [panel rules](context/TECH_STACK.md#panel) |
| Host and preview tools | [Host kit](tools/hostkit/.index.md) and [UI preview](tools/ui-preview/.index.md) |
| Active work and acceptance | [Planning status](planning/STATUS.md), then the owning packet and [native case ledger](planning/native-acceptance/README.md) |

Shipping code lives in `src/ph_composer/`. Development tools live in `tools/`. Use
`PhComposer` in Ruby and `ph_composer` for machine identifiers. Use [project terms](context/UBIQUITOUS_LANGUAGE.md)
in code, schemas and UI text.

## Apply the repository contracts

- Put model state and domain calculations in Ruby. JavaScript formats results and routes UI
  actions. Python translation produces HBJSON. Downstream exporters consume HBJSON.
- Build features through the same contribution contracts as third-party extensions. Register
  each contribution explicitly at the composition root or through its documented registration entry point.
- Preserve native transactions and Undo/Redo, observer ordering, active edit paths and
  per-Model state. Cite the [measured host behavior](context/SKETCHUP_HOST_BEHAVIOR.md) for host assumptions.
- Target Ruby 2.7 and Chromium 88, the SketchUp 2023 compatibility floor. Use the owning
  acceptance record for tested hosts and the [security policy](docs/SECURITY.md) for supported builds.
- Keep public fixtures synthetic. Put client files, licensed PHI and Phius material, real
  METr exports and personal setup notes under gitignored `_private/`. Maintain a
  `MANIFEST.md` for private test corpora. Tests that use them skip explicitly when absent.

## Architecture and code review

Load the [architecture review skill](.agents/skills/ph-composer-architecture-review/SKILL.md)
before substantive code changes or contribution design. For Ruby work, give the same reviewer
the [Ruby quality criteria](.agents/skills/ph-composer-ruby-quality/SKILL.md). For HtmlDialog work,
load the [UI polish skill](.agents/skills/ph-composer-ui-polish/SKILL.md) and its reference first.
Review documentation against its owning sources and check its cross-references.

## Verification

Run focused tests during implementation and `make ci` on the final code diff. Refresh the
runtime manifest after changing shipped panel or Python files. Review any golden change against
the intended contract. Commit with DCO sign-off and hooks enabled. See
[Git hooks](docs/DEVELOPMENT.md#git-hooks) and the [DCO](docs/DCO.md).

Run required real-host checks with the specified build, fixture and process state. Follow the
[native acceptance skill](.agents/skills/ph-composer-native-acceptance/SKILL.md). Use
`host_bridge.py wait-for` for deferred work and `host_bridge.py diagnostics` for recent events.
After a fault case, verify that `fault restore` returns `restored: true`, then confirm a fresh
normal run. Browser checks use `tools/ui-preview/support/browser_evidence.cjs` and declare
intentional errors with `expect`.

## Record decisions and status

Keep user guides in `docs/`, engineering contracts in `context/` and decisions, plans and
acceptance evidence in `planning/`. Treat every tracked file as public. Follow the
[planning conventions](planning/.instructions.md) and the [stage brief](.agents/stage-brief.md)
when running a PR stage. Feature interviews establish scope. Implementation requires separate
authorization. Record implementation, merge, host acceptance and release as separate facts.
Check the [project status](planning/STATUS.md) and the applicable acceptance gates before making
public distribution, platform support or certification claims.
