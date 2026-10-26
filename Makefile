.PHONY: ci syntax lint lint-ruby lint-js lint-python lint-citations lint-paths test fixtures fixtures-check coverage hostkit-test python-check \
        panel-manifest panel-manifest-check ui-preview ui-deps ui-checks rbz rbz-check install clean bridge-install \
        bridge-uninstall runtime-check runtime-pin-check runtime-manifest runtime-browser-check phase-one-proof \
        hooks hooks-auto help help-check

# `.ruby-version` pins 3.2.2, the Ruby the current proving host embeds. rbenv resolves it when it
# is installed; without rbenv this falls back to whatever `ruby` is on PATH, and the suite's own
# version guard says so if that is outside the supported span.
# `:=`, not `?=`: a recursive assignment re-runs `rbenv which` on every recipe line naming $(RUBY).
ifeq ($(origin RUBY),undefined)
RUBY := $(shell rbenv which ruby 2>/dev/null || command -v ruby)
endif
export RUBY
# Each lint target takes its file list from a variable so the pre-commit hook can run the same target on
# the staged files alone (tools/githooks/staged_checks.py). The defaults are the whole tree. A command-line
# assignment overrides them; an environment variable of the same name does not, so CI cannot be narrowed by one.
RB_FILES = $(shell find src tests tools -name '*.rb' -type f | sort)
RUBOCOP_ARGS =
ESLINT_ARGS = .
RUFF_ARGS = tools tests/python src/ph_composer/python
CITATION_FLAGS = --untracked
CITATION_PATHS = src tests
PATH_LINT_FLAGS = --untracked
PATH_LINT_PATHS = .
JS_TESTS := $(wildcard tests/*_test.js)
# Rubocop is reached through the bundler that belongs to $(RUBY), never whatever `bundle` is first
# on PATH: on macOS that is the system Ruby's, which cannot read this lock.
BUNDLE := $(dir $(RUBY))bundle
SKETCHUP_VERSION ?= 2026

# Every target docs/DEVELOPMENT.md claims for the offline loop that exists today.
ci: hooks-auto syntax lint test fixtures-check panel-manifest-check help-check runtime-check runtime-pin-check \
    hostkit-test python-check rbz rbz-check

syntax:
	@for file in $(RB_FILES); do $(RUBY) -c "$$file" >/dev/null || exit 1; done
	@echo "Ruby syntax: $(words $(RB_FILES)) files OK"

# JavaScript tests run under tools/js_test_guard.js, which kills the test process tree once its resident
# memory passes JS_TEST_MAX_RSS_MB, and each test has a time limit. A failing assertion that printed a stub
# DOM node once grew three processes past 100 GB each and stalled the machine; a Node heap flag does not
# stop that, because the memory is not the JS heap. `--test-force-exit` ends each file once its tests
# finish: a panel test leaves a request pending, and its 20 s recovery timer (request.js) otherwise holds
# the process open, about 20 s idle per file.
JS_TEST_MAX_RSS_MB ?= 4096
NODE_TEST_TIMEOUT_MS ?= 60000
export JS_TEST_MAX_RSS_MB

# One run reports every language's failures instead of stopping at the first. The JavaScript files
# are found by glob, so a new `tests/*_test.js` needs no Makefile line. The Ruby suite runs as one process
# per processor (tests/parallel_tests.rb; RUBY_TEST_JOBS overrides the count); `$(RUBY) -Itests
# tests/all_tests.rb` is the same suite in one process.
test: hooks-auto
	@$(RUBY) -Itests tests/parallel_tests.rb; ruby_status=$$?; \
	 if [ -n "$(JS_TESTS)" ]; then \
	   node tools/js_test_guard.js node --test --test-force-exit --test-timeout=$(NODE_TEST_TIMEOUT_MS) $(JS_TESTS); js_status=$$?; \
	 else echo "JavaScript suite: no tests found"; js_status=1; fi; \
	 uv run pytest; py_status=$$?; \
	 exit $$((ruby_status | js_status | py_status))

# Three rule sets, one target. Rubocop and eslint are developer tools the extension does not
# need, so each prints a named skip when absent and `make test` keeps working on a checkout with
# neither. CI installs both, so nothing skips there; a local skip is not gate evidence.
lint: hooks-auto lint-ruby lint-js lint-python lint-citations lint-paths

lint-ruby:
	@if [ -x "$(BUNDLE)" ] && $(BUNDLE) check >/dev/null 2>&1; then \
	  $(BUNDLE) exec rubocop $(RUBOCOP_ARGS); \
	else \
	  echo "lint-ruby: skipped, rubocop is not installed (run 'bundle install')"; \
	fi

lint-js:
	@if command -v pnpm >/dev/null 2>&1 && [ -d node_modules ]; then \
	  pnpm exec eslint $(ESLINT_ARGS); \
	else \
	  echo "lint-js: skipped, eslint is not installed (run 'pnpm install')"; \
	fi

# Shipped code and tests never cite planning documents (context/CODING_STANDARDS.md, "Comments").
# Planning ids: phase stages (P1-D, P3b-01), interview questions (Q18), decisions (D7, R-D4, D3b-02),
# acceptance cases (A02, R06, S01, T01) and contract, requirement or finding numbers (C4, I10, U1, B2,
# F8, F26). A review finding kept as a code comment is written `REVIEW F05` and is not a planning id.
PLANNING_IDS := \b(P\d-[A-F]\d?|P\d+[a-z]\d*-\d+|Q\d{1,2}|D\d{1,2}|D\d+[a-z]\d*-\d+|D-\d+|M\d[a-z]|R-D\d+|R0\d|A\d\d|S\d\d|T\d\d|B\d|C\d|I\d{1,2}|U\d|(?<!REVIEW )F\d\d?)\b
# Planning moves when it is archived; a citation into it breaks. The vendored payload is exempt.
lint-citations:
	@if git grep $(CITATION_FLAGS) -nP 'planning/|\bPRD\b|CONTRACTS\.md C\d|$(PLANNING_IDS)' -- $(CITATION_PATHS) \
	    ':!src/ph_composer/vendor' \
	    ':!tests/fixtures'; then \
	  echo "lint-citations: cite context/ instead of planning (context/CODING_STANDARDS.md)"; exit 1; \
	else \
	  echo "lint-citations: ok"; \
	fi

# A home path names a person and a machine; neither belongs in a public tree. /Users/example is the
# synthetic account evidence uses. tests/ and the host kit's tests are not linted: their synthetic home
# paths are what the redaction they test removes. git grep answers 1 for no match; anything else but a
# match (0) is an error, which fails the lint rather than passing it.
lint-paths:
	@git grep $(PATH_LINT_FLAGS) -InP '(?i)(?:/Users/|[a-z]:\\+Users\\+)(?!example(?![\w-]))[a-z0-9_]' -- \
	    $(PATH_LINT_PATHS) ':!tests' ':!tools/hostkit/tests' ':!src/ph_composer/vendor'; status=$$?; \
	if [ $$status -eq 1 ]; then echo "lint-paths: ok"; \
	elif [ $$status -eq 0 ]; then echo "lint-paths: replace the home path with ~ or <repo>"; exit 1; \
	else echo "lint-paths: git grep failed ($$status)"; exit 1; fi

# No skip: `test` and `python-check` already require `uv`.
lint-python:
	@uv run ruff check $(RUFF_ARGS)
	@uv run ruff format --check $(RUFF_ARGS)

# The owning tests, one per golden: exactly one test may write each file (docs/DEVELOPMENT.md
# "Fixtures and coverage"). A new golden adds its owner here and its path below.
FIXTURE_OWNERS := phase_one_export thermal_bridge_export api_reference
FIXTURE_PATHS := tests/fixtures tests/python/fixtures docs/API_REFERENCE.md

fixtures:
	@if [ -z "$(strip $(FIXTURE_OWNERS))" ]; then echo "fixtures: no generated goldens yet"; else \
	  PHC_WRITE_FIXTURES=1 $(RUBY) -Itests $(addprefix -r,$(addsuffix _test,$(FIXTURE_OWNERS))) -e ""; fi

# Regenerate, then fail if that changed any golden on disk. The comparison is by content, not against
# the last commit, so a golden regenerated and not yet committed passes and `make ci && git commit -s`
# works in one chain; CI's clean checkout compares against the commit itself.
# Paths are resolved when each snapshot runs, so a golden the regeneration creates or deletes counts.
FIXTURE_SUMS = for p in $(FIXTURE_PATHS); do [ ! -e "$$p" ] || find "$$p" -type f; done | xargs cksum | LC_ALL=C sort
fixtures-check:
	@before=$$($(FIXTURE_SUMS)); \
	 $(MAKE) --no-print-directory fixtures >/dev/null || exit 1; \
	 after=$$($(FIXTURE_SUMS)); \
	 if [ "$$before" != "$$after" ]; then \
	   echo "fixtures are stale; 'make fixtures' created, rewrote or removed these, so commit the result:"; \
	   printf '%s\n%s\n' "$$before" "$$after" | LC_ALL=C sort | uniq -u | awk '{ print $$3 }' | LC_ALL=C sort -u; \
	   exit 1; \
	 fi
	@echo "Fixtures up to date"

# Separate from ci: run it before a phase gate. Thresholds ratchet upward only. Python coverage
# measures the shipped translation package.
RUBY_COVERAGE_MIN ?= 93
JS_COVERAGE_MIN ?= 94
PYTHON_COVERAGE_MIN ?= 92

coverage:
	@$(RUBY) tools/coverage_ruby.rb $(RUBY_COVERAGE_MIN)
	@NODE_TEST_TIMEOUT_MS=$(NODE_TEST_TIMEOUT_MS) node tools/coverage_js.js $(JS_COVERAGE_MIN)
	@uv run pytest -q --cov=src/ph_composer/python --cov-report=term --cov-fail-under=$(PYTHON_COVERAGE_MIN) tests/python

# Development-only P1-C proof of the two-Zone translation, run with the synthetic construction
# provider and inline pins matching the eight shipped wheels.
phase-one-proof:
	@uv run tools/examples/phase_one/translate_two_zones.py

# The panel pages' <script> lists, generated from the PhComposerUI.define declarations
# (tools/panel_manifest.js). Rewrite after adding, renaming or re-declaring a panel module.
panel-manifest:
	@node tools/panel_manifest.js --write

panel-manifest-check:
	@node tools/panel_manifest.js

# The offline help page the extension ships is generated from docs/HELP.md (tools/help/help_page.py).
help:
	@uv run tools/help/help_page.py

help-check:
	@uv run tools/help/help_page.py --check

# The panel preview (tools/ui-preview/.index.md): the real panel, a stand-in host and the synthetic editor.
# Serves the repository root so the page can load the panel files; ctrl-c stops it.
UI_PREVIEW_PORT ?= 8765

ui-preview:
	@echo "preview on http://127.0.0.1:$(UI_PREVIEW_PORT)/tools/ui-preview/; ctrl-c stops it"
	@uv run --no-project python -m http.server $(UI_PREVIEW_PORT) --bind 127.0.0.1

# Playwright is never a project dependency. It lives outside the repository in UI_DEPS, where `make
# ui-deps` installs the pinned version, and drives the installed Chrome. NODE_PATH, when set, wins.
UI_DEPS ?= $(HOME)/.cache/ph-composer-ui
PLAYWRIGHT_VERSION ?= 1.63.0
ui-deps:
	@mkdir -p "$(UI_DEPS)" && cd "$(UI_DEPS)" && { [ -f package.json ] || echo '{"private": true}' > package.json; } \
	  && pnpm add --save-exact playwright@$(PLAYWRIGHT_VERSION)

# The browser checks in tools/ui-preview/ against the preview, on a loopback server this target starts and
# stops. UI_CHECKS narrows the run, as in `make ui-checks UI_CHECKS=tools/ui-preview/spaces_checks.cjs`.
# Without Playwright the target skips by name. Not part of `ci`: it launches a browser. A browser pass is
# not host acceptance.
UI_CHECKS ?= $(sort $(wildcard tools/ui-preview/*.cjs))
ui-checks:
	@export NODE_PATH="$${NODE_PATH:-$(UI_DEPS)/node_modules}"; \
	if [ -z "$(strip $(UI_CHECKS))" ]; then echo "ui-checks: UI_CHECKS names no check"; exit 1; fi; \
	if ! node -e "require.resolve('playwright')" >/dev/null 2>&1; then \
	  echo "ui-checks: skipped, Playwright is not resolvable from NODE_PATH=$$NODE_PATH; run 'make ui-deps' (tools/ui-preview/.index.md)"; exit 0; \
	fi; \
	if curl -s -o /dev/null "http://127.0.0.1:$(UI_PREVIEW_PORT)/"; then \
	  echo "ui-checks: port $(UI_PREVIEW_PORT) is already serving; stop that server or set UI_PREVIEW_PORT"; exit 1; \
	fi; \
	uv run --no-project python -m http.server $(UI_PREVIEW_PORT) --bind 127.0.0.1 >/dev/null 2>&1 & server=$$!; \
	trap 'kill $$server 2>/dev/null; wait $$server 2>/dev/null' EXIT; \
	for attempt in $$(seq 50); do curl -s -o /dev/null "http://127.0.0.1:$(UI_PREVIEW_PORT)/" && break; sleep 0.2; done; \
	status=0; \
	for script in $(UI_CHECKS); do \
	  UI_PREVIEW_PORT=$(UI_PREVIEW_PORT) node "$$script" || status=1; \
	done; \
	exit $$status

# The development host bridge and helpers: Ruby tests against the stub, then the Python client. Some Python
# tests run Ruby they generate; when the floor's Ruby (2.7) is installed they run again under it, so syntax
# newer than the floor fails here and not first on CI's 2.7 job.
RUBY_FLOOR ?= $(shell rbenv prefix 2.7.2 2>/dev/null)
hostkit-test:
	@$(RUBY) -Itests -Itools/hostkit/tests tools/hostkit/tests/all.rb
	@uv run pytest -q tools/hostkit/tests
	@if [ -n "$(RUBY_FLOOR)" ] && [ -x "$(RUBY_FLOOR)/bin/ruby" ] && [ "$(RUBY_FLOOR)/bin/ruby" != "$(RUBY)" ]; then \
	  RUBY="$(RUBY_FLOOR)/bin/ruby" uv run pytest -q tools/hostkit/tests -k "ReadSyntax or ReadBinding"; \
	else echo "hostkit-test: Ruby 2.7 not installed here; generated Ruby checked on $(RUBY) only"; fi

# ty over the set `[tool.ty.src]` in pyproject.toml includes; ruff's ANN rules require the annotations it reads.
python-check:
	@uv run ty check

# The runtime manifest (src/ph_composer/vendor/manifest.json) pins every asset the loopback server may
# serve. Regenerate it after editing anything under html/ or python/: panel-manifest first, since
# the runtime manifest hashes the pages it writes, then this, then rbz.
runtime-manifest:
	@uv run tools/runtime/vendor.py --refresh-manifest

# Offline: the tree, the Pyodide pin, the gates and the installed-size budget agree with the manifest.
runtime-check:
	@uv run tools/runtime/vendor.py --check

runtime-pin-check:
	@uv run tools/runtime/vendor.py --pins-check

# The shipped runtime page, booted in Chromium 88 (tools/runtime/browser_check.py). Not part of `ci`: it
# launches a browser, and a browser pass is not host evidence.
runtime-browser-check:
	@uv run tools/runtime/browser_check.py

rbz:
	@uv run tools/rbz/build.py

rbz-check:
	@uv run tools/rbz/build.py --check

install:
	@uv run tools/rbz/build.py --install --sketchup-version "$(SKETCHUP_VERSION)"

clean:
	@uv run tools/rbz/build.py --clean

PLUGINS_DIR := $(HOME)/Library/Application Support/SketchUp $(SKETCHUP_VERSION)/SketchUp/Plugins

# Development host bridge (tools/hostkit/host_bridge.rb): never part of the RBZ.
bridge-install:
	@cp tools/hostkit/host_bridge.rb "$(PLUGINS_DIR)/ph_composer_host_bridge.rb"
	@echo "host bridge installed into $(PLUGINS_DIR)"

bridge-uninstall:
	@rm -f "$(PLUGINS_DIR)/ph_composer_host_bridge.rb" "$(PLUGINS_DIR)/../ph_composer_host_bridge.json"
	@echo "host bridge removed"

# The repository's git hooks (.githooks/, docs/DEVELOPMENT.md "Git hooks"): lint, type and manifest checks
# on the staged files before each commit, and a DCO sign-off check on each message.
hooks:
	@git config core.hooksPath .githooks && echo "git hooks: installed from .githooks"

# Installs the hooks once from the targets every contributor runs, so no one has to remember `make hooks`.
# It never replaces a hooks path someone set on purpose, does nothing outside a git checkout, and never fails
# the target that called it: a locked or read-only git config only prints a line.
hooks-auto:
	@if git rev-parse --git-dir >/dev/null 2>&1; then \
	  current=$$(git config --get core.hooksPath || true); \
	  if [ -z "$$current" ]; then \
	    { git config core.hooksPath .githooks && echo "git hooks: installed from .githooks"; } || \
	      echo "git hooks: could not set core.hooksPath; run 'make hooks' later"; \
	  elif [ "$$current" != ".githooks" ]; then \
	    echo "git hooks: core.hooksPath is $$current, not .githooks; run 'make hooks' to use this repository's"; \
	  fi; \
	fi
