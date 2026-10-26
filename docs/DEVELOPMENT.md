# Development

**DATE:** 2026-09-30 | **STATUS:** Partly implemented. The commands below exist unless marked
"not yet". The extension has its foundation, the Zones screen with its Zone tree and Faces view,
the Classify tool and its palette, the shared Colour-by service, the Python runtime payload and the
HBJSON/report workflow with pinned translation wheels. The normal build refuses canonical export
until an authored construction provider is available. Phase 1 acceptance uses a separately composed
synthetic development provider; it never becomes a stored Assembly or shipping fallback. METr
remains deferred.

The development loop needs no installed dependencies beyond Ruby, Node and `uv`. Ruby source stays
compatible with Ruby 2.7 inside the SketchUp 2023 support floor. The proving host is SketchUp
2026.1 with Ruby 3.2.2. Build tools run through `uv`; they never install packages into system
Python.

## Prerequisites

- Ruby 2.7.2 and 3.2.2 through rbenv (see "Ruby versions").
- Node 22 and pnpm, for the JavaScript suite and eslint.
- `uv`, which provides Python 3.11 for the tools and their tests.

## Offline loop

```sh
make ci
```

`ci` runs, in order: `syntax` (every `.rb` under `src`, `tests` and `tools`), `lint`, `test`,
`fixtures-check`, `panel-manifest-check`, `help-check` (the shipped `ph_composer/help/index.html` is
current with `docs/HELP.md`; `make help` rewrites it), `runtime-check` (the tree, the Pyodide pin, the gates
and the installed-size budget against `src/ph_composer/vendor/manifest.json`), `runtime-pin-check`
(shipped wheels against `pyproject.toml`), `hostkit-test`, `python-check` (ty, Astral's type
checker, over the translation package, the tools and their tests), `rbz` and `rbz-check`, which also refuses an
installed extension over the manifest's 26,000,000-byte ceiling, or more than 1,500,000 bytes past its
baseline, the installed size at the last phase close. Raising either, or resetting the baseline at a
phase close, is a recorded decision.

`test` loads the real extension code against a stub SketchUp API and runs the Ruby and Python
suites in one pass. The Ruby suite runs as one process per processor, each loading a share of the
`*_test.rb` files (`tests/parallel_tests.rb`), and reports one summary; `RUBY_TEST_JOBS` sets the
count. Each shard prints its own Minitest seed. To chase an order-dependent failure, run the suite in
one process with `ruby -Itests tests/all_tests.rb`. JavaScript tests are discovered by the glob `tests/*_test.js` and run under
`node --test` against a DOM double. The stubs say in comments what they support and what they
refuse to pretend to support; see `tests/support/.index.md`. A rule that needs no host is tested
without the stub: `tests/support/face_geometry_pure.rb` loads only `core/face_geometry.rb` and runs in a
bare Ruby process, and `context/EXTENSIBILITY.md`, "Organization and dependencies", lists which
foundation files are pure and which are native adapters.

## Lint

```sh
make lint
```

Three rule sets, each a developer tool rather than something the extension needs. `make test`
stays dependency free, so rubocop and eslint each print a named skip line when absent. CI
installs both. A local skip is not gate evidence.

- `lint-ruby` runs rubocop from the `Gemfile`, with gems in `vendor/bundle` so adding a linter
  cannot change what the suite's `require` resolves. Install with `bundle install` using the
  bundler of the Ruby you test with.
- `lint-js` runs eslint from `package.json` at `ecmaVersion: 2020`, the floor host's Chromium 88
  level, with post-88 runtime APIs refused. Install with `pnpm install`; the repository keeps
  pnpm's one-day minimum release age and refuses non-registry subdependencies.
- `lint-python` runs ruff over `tools/`, `tests/python` and the translation package, lint and
  format check. Its rules include the ones that require every parameter and return to be
  annotated, which `python-check` relies on and ty does not enforce itself. ty is pinned to an
  exact version while it is in beta.
- `lint-citations` fails if shipped code or a test cites a planning document or a planning
  identifier (a phase stage, question, decision or acceptance number). Comments cite `context/`
  instead, because planning documents move when they are archived.
- `lint-paths` fails if a file outside `tests/` and `tools/hostkit/tests/` names a home folder,
  such as `/Users/<name>/` or `C:\Users\<name>\`. Write `~` or `<repo>` instead; `/Users/example`
  is the synthetic account examples use. The tests keep their synthetic home paths, because those
  are what the redaction they test removes.

The line ceiling is 120 characters in every language. What the linters cannot express is in
[`context/CODING_STANDARDS.md`](../context/CODING_STANDARDS.md).

## Git hooks

The repository keeps its git hooks in `.githooks/`. They install themselves the first time you run
`make lint`, `make test`, `make ci` or `pnpm install`, which set `core.hooksPath` to `.githooks`;
`make hooks` installs them on demand. An existing `core.hooksPath` pointing somewhere else is left
alone, with a line saying so.

- `pre-commit` runs, on the staged files only, the checks they can affect: ruff lint and format
  for Python, ty over its whole configured set when any Python file is staged, `ruby -c` and
  rubocop for Ruby, eslint for JavaScript, the panel and runtime manifest checks when panel or
  translation assets change, the planning-citation check for shipped code and tests, and the
  home-path check for every file outside `tests/` and `tools/hostkit/tests/`. Each is the Makefile target CI runs, given the
  staged file list. A deleted or renamed file runs the checks that read the whole set, and a change
  to a linter's configuration (`pyproject.toml`, `.rubocop.yml`, `package.json`, the `Makefile`)
  runs that linter over the whole tree. A commit that touches only documentation runs only the
  home-path check. A failure prints the tool's output and the command that fixes it, and nothing is
  committed. The hook never edits or re-stages a file.
- `commit-msg` refuses a message without a `Signed-off-by:` line ([DCO.md](DCO.md)). The message
  git writes to conclude a merge is left alone.

Rubocop matters here beyond style: it parses at the Ruby 2.7 floor, so it catches syntax that the
3.2 interpreter accepts and SketchUp 2023 would not load. A missing rubocop or eslint prints the
same named skip `make lint` prints, and CI still runs both. The hooks start on the system
`python3` and need `uv` only when a check runs; they add the usual install locations of `uv`,
Homebrew, rbenv and pnpm to `PATH` themselves, so a graphical git client finds them too.

The hooks are a fast first check, not the gate: `make ci` still runs the full suite before a
change is proposed. Chain the two, as in `make ci && git commit -s`, so a failed gate stops the
commit. Do not bypass a hook with `--no-verify`; fix what it reports instead. A file with unstaged
changes is checked as it is on disk, and the hook says which files that applied to. Three checks
read more than the staged files, so another contributor's unfinished file in a shared checkout can
fail them: the type check reads its whole configured set, the manifest checks read what they hash,
and a configuration change lints the whole tree.

## Ruby versions

The suite runs on Ruby 2.7 to 3.2 and refuses anything outside that span, because both ends are
real. A loop on one version alone cannot see Ruby 3 keyword separation in either direction.

```sh
brew install rbenv ruby-build
rbenv install 2.7.2
rbenv install 3.2.2
make ci                                        # 3.2.2, from .ruby-version
make ci RUBY=$(rbenv prefix 2.7.2)/bin/ruby    # the floor
```

A non-interactive shell (an agent's tool shell, a git client) can resolve `ruby` and `bundle` to
macOS's system Ruby 2.6, which the suite refuses. The `make` targets find the rbenv Ruby
themselves. Run a single test file or RuboCop yourself like this:

```sh
$(rbenv which ruby) -Itests tests/definition_lists_test.rb
PATH="$(dirname "$(rbenv which ruby)"):$PATH" bundle exec rubocop src/ph_composer/shell
```

GitHub Actions runs `make ci` on both, one matrix job per version, on every pull request and
every push to `main`. A newer push to the same pull request cancels the run in progress.

## Fixtures and coverage

Generated goldens are regenerated with `make fixtures`, which prints every file it changed; every
other run compares them. Each golden has exactly one owning test, listed in `FIXTURE_OWNERS` in
the Makefile, and `FIXTURE_PATHS` names what `make fixtures-check` compares. There are two:
`tests/fixtures/phase_one/two_zones_extraction.json`, the Phase 1 two-Zone extraction, owned by
`tests/phase_one_export_test.rb`; and [`API_REFERENCE.md`](API_REFERENCE.md), the generated API
reference, owned by `tests/api_reference_test.rb`. Hand-authored inputs live apart from goldens and
nothing regenerates them.

`make fixtures-check` compares the goldens' content before and after regenerating them, not against
the last commit. A golden you regenerated and have not committed yet passes, so `make ci && git
commit -s` works in one chain. Stage the regenerated golden with the rest, or the CI run on the
pushed commit fails.

`make coverage` measures Ruby line coverage of the extension folder against a 93% minimum,
JavaScript line coverage of `html/` (the runtime page included) against 94%, and Python coverage of
the translation package against 92%. It sits outside `make ci`; run it before a phase gate.
Thresholds ratchet upward only.

`tests/fixtures/phase_one/two_zones.hbjson` is the exact canonical HBJSON the Phase 1 translation
produces for the two-Zone extraction, written by
`uv run tools/examples/phase_one/translate_two_zones.py --write-hbjson <path>`; the artifact-guard
tests check it passes unchanged. It is a hand-reviewed contract example, regenerated only when the
translation deliberately changes. `make phase-one-proof` runs the same script without writing: it
checks the pinned wheel versions, identifiers, reciprocal Surface targets, areas and volume of the
two-Zone translation and reloads the result in honeybee.

`tests/fixtures/foundation/{extraction,result}.json` are hand-reviewed contract examples, not
generated goldens: the Ruby suite checks that the example feature collects to the extraction, and
the Python suite that its sections translate that to the result.

## The Python runtime

The runtime payload is the Pyodide core pinned in `tools/runtime/vendor.py`, plus the shipped
`html/` and `python/` files, each listed with its size and SHA-256 in the manifest. After editing
anything under `html/` or `python/`:

```sh
make panel-manifest      # when a panel module was added, renamed or re-declared
make runtime-manifest    # re-hashes html/ and python/; never adopts a changed Pyodide file
make ci
```

`uv run tools/runtime/vendor.py` without flags downloads the pinned Pyodide release, checks its
hash and rewrites the manifest. `make runtime-browser-check` boots the shipped runtime page in the
Chromium 88 snapshot (downloaded once with `uv run tools/runtime/browser_check.py
--download-chromium`) and checks isolation, single-flight boot, that no stack module loads, and the
manifest's cold-boot and round-trip ceilings. It launches a browser, so it is not part of `make
ci`, and a browser pass is not host evidence. On the host, `tools/hostkit/runtime_probe.rb` runs the
same probe and reports teardown (see `tools/hostkit/.index.md`).

## Build, install and reload

```sh
make rbz       # dist/ph_composer.rbz, install through Extension Manager
make install   # replace only this extension's loader and folder in the Plugins directory
```

The archive holds the loader and the `ph_composer/` folder and nothing else. `make rbz` and
`make rbz-check` refuse development material (host kit, examples, fixtures, tests, the private
corpus), file types the extension does not ship, blocking browser dialogs in panel code, and any
line naming the retired designPH integration or the predecessor's namespace. A documentary
citation that must name the predecessor is admitted one exact line at a time through
`tools/rbz/shipping_allowlist.json`, with a reason.

Restart SketchUp after replacing the loader. For every phase gate, quit all SketchUp processes
and relaunch after `make install`. Installation is preparation, not host validation.

Every archive carries `ph_composer/build.json`: `build`, twelve hex characters of a digest over every
shipped file, and `commit`, the source commit it was built from, marked `-dirty` when `src/` had
uncommitted changes. Help & Diagnostics, each log line and every support report name that build. A
source checkout has no `build.json` and reports itself as a development build.

The identity is informational. Nothing verifies the installed files against it when SketchUp loads
the extension: a file changed or added under the extension folder runs as the extension, with the
user's own permissions, as any extension in the Plugins folder does.

## Answering a support report

A report arrives as a GitHub issue or an email with the text from Help & Diagnostics. Its header
names the version, build and commit, runtime manifest, SketchUp version and platform, whether the
log was being written, and the incident the user selected. Its body is the newest log lines as JSON.

1. Find the failure. Search the log lines for the incident reference. Its record names the event,
   operation or stage, code, error class and extension-relative frames, which point at the file and
   line. `session`, `request` and `run_id` join the records for one panel request or export.
2. Find the source that failure ran. Every log line carries its own `build`. When it matches the
   header's `Build`, check out the header's `commit`. When it differs, the user has installed
   another build since; find that build's commit from its release's `build.json`, or ask the user
   which version they ran then. Until the source is known, read the frames as approximate.
   `development` means a source checkout; ask which commit. A `-dirty` commit cannot be reproduced
   exactly; say so in the issue.
3. Read the effect before anything else. `effect` `none` or `rolled_back` means the Model was not
   changed; `unknown` means the user must inspect it. Answer that first.
4. Reproduce it with synthetic data in an offline test, or under the development bridge
   (`tools/hostkit/`). Never ask for or commit a user's Model, and never put a report's project
   details in a test, a fixture or the repository.
5. Fix it with the test that reproduces it, link the issue in the pull request, and record in the
   issue which build carries the fix and how it was verified: offline, or on which host.

Before publishing a release, check each of these on the release commit:

1. `make bridge-uninstall` on the machine that builds the release candidate, then a fresh SketchUp
   launch to confirm no `ph_composer_host_bridge.json` reappears.
2. `make ci` and `make rbz-check` pass, and `build.json` records a commit without `-dirty`.
3. "Current release" in `docs/HELP.md` names the release, then `make help`, in the same change, so
   the shipped help names it.
4. The supported versions line in `SECURITY.md` names the release.
5. Every action in `.github/workflows/ci.yml` is pinned to a commit. CI does not check this;
   Dependabot proposes the bumps that keep the pins current.

A report says nothing about certification or energy-model validity. Answer those questions
separately from installation and runtime faults.

## Native acceptance continuity

The [native acceptance skill](../.agents/skills/ph-composer-native-acceptance/SKILL.md) coordinates
fixture/build identity, control selection, observed assertions and normal-build restoration.
The [case/result ledger](../planning/native-acceptance/README.md) screens affected checks and
retains historical evidence without fabricating missing run provenance. Source snapshots do not
run SketchUp or prove current-host acceptance. [Control capabilities](../context/NATIVE_CONTROL_CAPABILITIES.md)
identify which claims require native pixels or a human gesture.

## Driving SketchUp from a terminal

This section concerns development tooling. Scripts and in-process clients use the public interface
in [API_QUICKSTART.md](API_QUICKSTART.md); users' agents connect through the agent listener in
[AGENT_ACCESS.md](AGENT_ACCESS.md), which ships in the RBZ, needs a token the user issues and runs only
the public operations. The development bridge is neither: it evaluates arbitrary Ruby, is installed
by hand and never ships. `tools/hostkit/agent_access_probe.py` runs both supported agents headless
against a configured listener and keeps a transcript with the token masked.

Host work defaults to the development bridge, not to a person at the Ruby Console.
`make bridge-install` places the bridge in the SketchUp Plugins folder, never in the RBZ, and
`make bridge-uninstall` removes it. `launch` always opens a document, because the bridge did not
start while SketchUp waited at its Welcome screen
([host evidence](../planning/archive/phase-00-foundation/evidence/phase-02-bootstrap.md)):

```sh
uv run tools/hostkit/host_bridge.py launch _private/host/run.skp --fresh-from _private/host/blank.skp
uv run tools/hostkit/host_bridge.py state
uv run tools/hostkit/host_bridge.py quit
```

`launch` quits any running SketchUp, opens the Model as the only document and loads the helpers.
For a scratch fixture, one under a `_private/` folder or the temporary folder, it first removes
SketchUp's autosave copy of that file, so the open does not stop on "The recovered version of this file
is newer". When the bridge does not come up it names SketchUp's open windows, since a prompt may be
waiting on another display. `quit` saves every open document to a scratch path and closes it, including
documents opened after the first, so terminating meets no save prompt. A host the bridge cannot reach, or
one still on a prompt after 30 seconds, is killed, and `quit` says so.
From there `eval`, `state`, `save`, `shot`, `key`, `console` and `quit` cover the fresh-process
loop, and `wait-for` waits for a named host condition (a session settling, a revision changing, an
export finishing) through separate polls under one deadline, printing a versioned JSON result with
`--json`, and `diagnostics` reads the extension's recent log records filtered by session, incident, run
and severity, paged by a cursor that says when history is missing. `fault` arms, observes and restores a
named development fault on a synthetic fixture, so a failure case can be reproduced and its restoration
read back. `tools/hostkit/.index.md` lists what each does. Every `eval` runs in one shared binding, so
a local variable assigned in one call survives into the next and keeps its object alive. Set such
locals to nil before checking that a closed Model's session was collected. The measured host facts
the bridge depends on are in [`context/SKETCHUP_HOST_BEHAVIOR.md`](../context/SKETCHUP_HOST_BEHAVIOR.md).

Phase-specific native probes live under [`tools/spikes/`](../tools/spikes) and never ship. The
P1-A Zone geometry probe and its stepwise bridge commands are documented in
[`tools/spikes/geometry/README.md`](../tools/spikes/geometry/README.md); its accepted results are
in [`planning/archive/phase-01-faces-and-zones/evidence/p1-a-geometry.md`](../planning/archive/phase-01-faces-and-zones/evidence/p1-a-geometry.md).
The panel-closed walkthroughs are in
[`tools/examples/authoring/`](../tools/examples/authoring/README.md): P1-B's Zone and Face
authoring, P1-C's adjacency, P1-D's Zone repairs, P1-D's adjacency cut, P1-D's Colour-by overlay,
P1-D's Classify tool, P1-D's Zones / Faces screen, P1-D's split identity repair, the gesture cost
measurement, and a panel-closed client that repeats the API quickstart against a real Model. The
Classify tool's walkthrough ran on 2026-09-20 with an operator at the mouse,
because SketchUp delivers pointer events to the active tool and the Ruby API synthesizes none; it
covered the parts of Colour-by's that a drawing tool exercises. Colour-by's own questions were
closed later by the [Colour-by continuation](../planning/archive/phase-01-faces-and-zones/evidence/p1-d-colour-by-continuation.md).
Accepted current-host results are in
[`p1-b-authoring.md`](../planning/archive/phase-01-faces-and-zones/evidence/p1-b-authoring.md),
[`p1-c-adjacency-hbjson.md`](../planning/archive/phase-01-faces-and-zones/evidence/p1-c-adjacency-hbjson.md),
[`p1-d-repairs-and-cut.md`](../planning/archive/phase-01-faces-and-zones/evidence/p1-d-repairs-and-cut.md) and
[`p1-d-classify-tool.md`](../planning/archive/phase-01-faces-and-zones/evidence/p1-d-classify-tool.md).

The Zones / Faces screen's eight handoff questions were completed with native computer use on
2026-09-26. The [evidence](../planning/archive/phase-01-faces-and-zones/evidence/p1-d-overview.md) records the fixes,
fresh-process checks and remaining acceptance boundaries. Its walkthrough builds the Model and
reads back what the panel's commands did; native controls drive the HtmlDialog interactions.

A gate that needs pointer input cannot be scripted and cannot be skipped. The Classify tool's gate
found three defects that no offline test could have caught, one of them in a slice already recorded
as implemented and reviewed, because its own host gate had not been run.

Native Undo and Redo are menu actions: a walkthrough sends `Sketchup.send_action("editUndo:")`
and reads the result in a later call. There is no `Sketchup::Model#undo` on the host, although the
offline stub has one; that and the other measured facts these walkthroughs depend on are in
[`context/SKETCHUP_HOST_BEHAVIOR.md`](../context/SKETCHUP_HOST_BEHAVIOR.md).

## The panel

Each panel file is one `PhComposerUI.define(name, dependencies, factory)` call. After adding,
renaming or re-declaring a module, regenerate the pages' script lists:

```sh
make panel-manifest
```

`make ci` fails while `html/index.html` or the preview page is stale. After installing changed panel
assets, close and reopen the panel; an open panel keeps running the old page.

The preview is the real panel in a browser, with a stand-in host and synthetic Models. It does not
replace the SketchUp walkthrough a host gate requires.

```sh
make ui-preview                                  # http://127.0.0.1:8765/tools/ui-preview/
make ui-deps                                     # once: Playwright into ~/.cache/ph-composer-ui
make ui-checks                                   # every check
make ui-checks UI_CHECKS=tools/ui-preview/spaces_checks.cjs
```

`ui-checks` finds Playwright in `UI_DEPS` (`~/.cache/ph-composer-ui`, outside the repository) or in
`NODE_PATH` when that is set, and prints a skip line without it. A check of a panel screen measures the
panel's own scroller at real panel sizes through `tools/ui-preview/support/pane_fit.cjs`, not the page.
Every check runs through `tools/ui-preview/support/browser_evidence.cjs`, which fails the run on any
console error, uncaught page error, failed request or HTTP error the check did not declare. A failed
check writes `<check>.evidence.json` and `<check>.evidence.txt` beside its screenshots, naming each event
with its step and time. To keep a Playwright trace of a failed check, then open it:

```sh
PH_COMPOSER_BROWSER_TRACE=on-failure make ui-checks UI_CHECKS=tools/ui-preview/spaces_checks.cjs
~/.cache/ph-composer-ui/node_modules/.bin/playwright show-trace <check>.trace-1.zip
```

`always` keeps the trace for passing checks too. `tools/ui-preview/.index.md` describes the page, its fixtures, the development sections it adds and the
checks.

## The development example

`tools/examples/foundation/` is a complete feature built only from the public contracts, with a
script that drives it through `PhComposer::API` as two clients with the panel closed, and a
synthetic editor: a panel section for its parts that exercises the unit field and the record form.
Its README lists each file. It never ships. Loading it registers the feature and hands the editor
to the panel, which runs it the next time the panel opens. To run it in a host with the bridge:

```sh
uv run tools/hostkit/host_bridge.py eval \
  'load "/absolute/path/to/ph-composer/ph-composer-skp/tools/examples/foundation/load.rb"; ExampleWalkthrough.run'
```

## Not yet available

These arrive with the parts they verify. Until then no command exists and none may be cited as a
passing check.

- **Library provider testing.** A local fixture server for connection providers arrives with the
  library provider contract.

## Phase 1 export verification

The Export pane performs feature-owned preflight, offers explicit Solve, repeats preflight after
repair, and creates an HBJSON/report pair. Cancellation is accepted before canonical commit.
Export never saves the SKP. Stale or retired Surface Faces are omitted with area, Zone and reason;
independent blockers leave the full diagnostics visible and write no canonical pair.

`uv run tools/runtime/browser_check.py --translation` exercises the exact shipped wheel set in
Chromium 88 and compares the explicit synthetic composition with native Python using those same
wheels. Only upstream-created PH default UUIDs and unordered construction-definition sets are
normalized for comparison; authored identities, references and values are compared directly.
The files themselves are not rewritten. This browser gate supplements real SketchUp acceptance.

Current-host acceptance and remaining distribution limits are recorded in the
[Phase 1 evidence](../planning/archive/phase-01-faces-and-zones/evidence/p1-e-export-workflow.md). SketchUp 2023,
Windows, public distribution and certification claims retain their separate gates.

## Acceptance run receipts

The development [acceptance run harness](../tools/hostkit/ACCEPTANCE_RUN.md) freezes observed
preconditions, screens assertion dependencies, records evidence hashes and checks installed package
bytes and local Markdown links. It complements the native ledger and does not award host acceptance.
`tools/hostkit/acceptance_case.py` runs one case's `begin` and `finish` around it, with the host identity
read from the bridge.
`make hostkit-test` covers its refusal and evidence-integrity behavior.
