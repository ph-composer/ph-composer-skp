# Development

## Set up the checkout

Install Ruby 3.2.2 and 2.7.2 through rbenv, Node 22 with pnpm, and uv for Python 3.11.
Install the Ruby and JavaScript development dependencies:

```sh
bundle install
pnpm install --frozen-lockfile
```

Use Bundler for the Ruby version under test. The Makefile finds rbenv's Ruby in a non-interactive
shell, where running `ruby` directly can pick up the system interpreter.

## Run the checks

```sh
make ci
make ci RUBY=$(rbenv prefix 2.7.2)/bin/ruby
```

GitHub Actions runs the full offline gate on Ruby 3.2.2 and 2.7.2. The gate checks Ruby syntax,
lint, Ruby/JavaScript/Python tests, generated fixtures, panel and help pages, runtime pins,
host tools, Python types and the RBZ contents. Ruby tests use a SketchUp stub. JavaScript tests
use a DOM double. See [test support](../tests/support/.index.md) for what each stub models.

Use `make lint` and `make test` for focused work. Ruby tests run in shards and print their seeds.
Set `RUBY_TEST_JOBS=1` or use `ruby -Itests tests/all_tests.rb` to investigate order-dependent
failures. Run `make coverage` when the owning phase requires it. The Makefile defines the thresholds.

The lint tools are RuboCop, ESLint and Ruff. Install the project's dependencies if lint reports a
skip. `make lint-citations` checks that shipped code and tests cite durable engineering contracts.
`make lint-paths` checks tracked files for personal home paths, with exceptions for synthetic
test paths. Write `~` or `<repo>` in public instructions.

## Git hooks

`make hooks` installs the repository hooks. `make ci` also installs them when the checkout
has no configured hooks path. Pre-commit runs checks for the staged paths. Changes to a
shared linter configuration run its full check. The commit message hook requires the
[DCO sign-off](DCO.md).

For a code change, run the final gate before committing:

```sh
make ci && git commit -s
```

## Fixtures and coverage

- Edit [Help](HELP.md) and run `make help` to regenerate the offline HTML.
- Edit the [agent operating guide](AGENT_GUIDE.md) and run `make fixtures` to copy it into
  the extension. Section headings define discovery topic IDs.
- Change registered API declarations at their source. Run `make fixtures` to regenerate the
  [API reference](API_REFERENCE.md). Its schemas and examples come from the declarations.
- Review every regenerated fixture. `make fixtures-check` compares the generated contents
  with the files in your checkout.

After adding, renaming or re-declaring a panel module, run `make panel-manifest`. After editing
shipped `html/` or `python/` files, run `make runtime-manifest` before `make ci`. The
[technical architecture](../context/TECH_STACK.md#pyodide-and-export-boundary) explains the
pinned runtime. `make runtime-browser-check` runs its browser probe. The browser check and
`make phase-one-proof` exercise the pinned HBJSON translation outside SketchUp.

## Build, install and reload

```sh
make rbz       # dist/ph_composer.rbz
make install  # replaces this extension in SketchUp's Plugins folder
```

You can also install the RBZ through Extension Manager. Restart SketchUp after replacing the
loader. Close and reopen the panel after installing changes to its assets.

`make rbz-check` verifies the package contents and size limits. The package's
`ph_composer/build.json` records a 12-character digest of the shipped files and the source commit.
A `-dirty` suffix identifies a build made with local source changes. Help & Diagnostics and
support reports show the build. Source checkouts report a development build.

## The panel

```sh
make ui-deps
make ui-preview
make ui-checks
make ui-checks UI_CHECKS=tools/ui-preview/spaces_checks.cjs
make ui-gallery
```

The preview runs the real panel in a browser with a stand-in host and synthetic data. Browser
checks record console, page, request and HTTP errors. The gallery captures screen states.
See the [preview guide](../tools/ui-preview/.index.md) for fixtures, screenshots and traces.

## Test in SketchUp

Use the [native acceptance procedure](../.agents/skills/ph-composer-native-acceptance/SKILL.md)
with the [case ledger](../planning/native-acceptance/README.md). Start from the specified build
and fixture in a fresh SketchUp process. Use the [host kit](../tools/hostkit/.index.md) for
fixture setup, bounded waits and read-back. Use [native controls](../context/NATIVE_CONTROL_CAPABILITIES.md)
for assertions that depend on SketchUp gestures, pixels or windows. Record the observed results
and verify restoration of the normal build after fault cases.

The development bridge evaluates Ruby in SketchUp. Install and remove it with
`make bridge-install` and `make bridge-uninstall`. Keep host fixtures and raw evidence in
gitignored `_private/`. The bridge's `launch` and `quit` commands close open documents.
Use a scratch process and save work you intend to keep first. See the
[host kit](../tools/hostkit/.index.md) for the command reference and the
[acceptance run procedure](../tools/hostkit/ACCEPTANCE_RUN.md) for evidence receipts.

The [foundation example](../tools/examples/foundation/README.md) shows a complete feature built
against the public contracts. The [authoring walkthroughs](../tools/examples/authoring/README.md)
exercise commands with the panel closed.

## Answer a support report

1. Match the incident reference to its log record. Use `session`, `request` or `run_id` to
   follow related records.
2. Match the log's `build` to its source commit. For a development or dirty build, ask for the
   checkout details if the report cannot identify the source.
3. Check the reported `effect`. Explain whether the model changed and what the user should
   inspect when the effect is unknown.
4. Reproduce the issue with synthetic data. Record the build that carries the fix and the
   offline or host checks that verified it.

## Prepare a release

1. Uninstall the development bridge. Start SketchUp and verify that the bridge state file stays absent.
2. Run `make ci` and `make rbz-check` on the release commit. Confirm the archive's `build.json`
   identifies that commit and build.
3. Update the current release in [Help](HELP.md) and run `make help`. Update the supported
   version in the [security policy](SECURITY.md) and verify the private reporting route.
4. Check that each action in the [CI workflow](../.github/workflows/ci.yml) is pinned by commit.
5. Record the release and platform acceptance against the [project status](../planning/STATUS.md).
