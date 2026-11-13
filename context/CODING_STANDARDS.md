# Coding standards

Use [project terminology](UBIQUITOUS_LANGUAGE.md) in code and UI text. Consult the
[technical architecture](TECH_STACK.md) for SketchUp observers, transactions and runtime rules.
Run `make lint` to check the rules in `.rubocop.yml`, `eslint.config.mjs` and `pyproject.toml`.

## Layering

Contributor-facing boundaries are governed by [EXTENSIBILITY.md](EXTENSIBILITY.md). Built-in
features use those same public contracts. Separate pure Ruby domain behavior from SketchUp
adapters so calculations and validation can be exercised without the host.

- Ruby owns Model state, transactions and domain calculations.
- JavaScript renders domain values and routes public operations. The UI kit works through
  the request channel.
- Python translation reads the detached export contract and produces HBJSON.
- Downstream exporters read HBJSON and the export options.

## Ruby

- **Target Ruby 2.7.** SketchUp 2023 embeds Ruby 2.7.2. Use
  `Struct.new(keyword_init: true)` for named fields. The offline suite runs on 2.7.2 and 3.2.2.
  Keep experimental Ruby 2.7 features such as pattern matching out of shipping code.
- **`fetch` for a required key, `dig` for an optional path.** `[]` on a shape the code requires
  turns a missing key into a `nil` that surfaces three frames away. One reader for a path every
  caller walks, `fetch` at each step, because a row missing any of them is unreadable and the
  readability check has already refused it. Where a shape carries rules, a small typed value reads
  it once inside the feature; the hash stays the contract at the persistence and panel edges.
- **Sequenced statements do not share a line.** `Style/Semicolon` enforces it. The one shape it
  allows is a whole method on one line for pure delegation: `def space?(entity); Scan.space?(entity); end`.
  A body that does anything gets its own lines.
- **Errors carry their taxonomy**, defined in `core/errors.rb`: `UserError` for a message the
  panel may show verbatim, `CodedError` when the panel has to key behaviour on a stable code and
  read structured `detail`, and `InternalError` for what belongs in the log. Never raise a bare
  `Error` at a user-facing edge.
- **A refusal that wrote nothing says so**, with the sentence ending `Nothing was written.` The
  user's next question is always whether the Model changed.
- **Value objects at module boundaries.** A module that hands another module a bare Hash hands it
  a shape nothing declares. `Records::RecordKind` and its `Records::Descriptor` are the pattern.

### Ruby readability and contributor review

Assess whether a contributor can trace an operation from its entrypoint through validation,
planning and application, including a refusal, without reconstructing undocumented data shapes.
Use `.agents/skills/ph-composer-ruby-quality/SKILL.md` within the existing coherent-diff review
for substantive Ruby changes. The architecture rubric still owns contribution boundaries.

- **Give domain plans named fields.** A multi-field array whose positions mean kind, occurrence,
  before and after is an undeclared record. Use a small named value, such as
  `Struct.new(..., keyword_init: true)`, when it passes between methods or modules. Ordinary
  key/value pairs, coordinates, matrices and documented external formats can remain arrays.
  JSON hashes remain appropriate at persistence and transport boundaries; do not change a wire
  shape merely to improve an internal representation. A Struct does not destructure, so replacing
  a tuple means finding every reader first: multiple assignment, block parameters, `first` and
  index reads, the initial default the owner sets, and tests that read the internal state.
- **Name the representation.** Distinguish `zone_reference`, `zone_path`, `space_record` and
  `face_ids`. A method returning IDs says so when its name otherwise suggests entities. Name
  units on local quantities when the unit is not already unambiguous. Reserve `sort` for ordering;
  use names such as `partition` or `eligible` for eligibility decisions.
- **Keep consequential steps visible.** Separate resolution, validation, plan construction and
  proposal assembly when combining them hides execution order or failure behavior. Introduce
  intermediate values when a chain switches domain concepts. Normal Ruby guards, blocks,
  destructuring and short collection chains need no expansion when their meaning is apparent.
  A guard reads as one statement: a modifier `unless` or `if` stays on the line it guards, and a
  condition too long for that line becomes an `unless ... end` block rather than a trailing
  modifier on the next line.
- **Make coupled mutable state explicit.** When helpers pass several drawing or planning buffers
  together, consider one feature-owned builder with named responsibilities. Keyword arguments help
  distinguish independent inputs; renaming many positional arguments as keywords alone does not
  resolve responsibility or mutation ownership. Keep the completed result separate from temporary
  state when the distinction matters to failure recovery.
- **Declare the helper boundary.** Keep entrypoints and their supporting operations discoverable.
  Before making a helper private, find its callers, including module functions used by another
  module. Extract a cohesive responsibility only when it reduces what those callers must know.
  Do not split every action into a class or add a generic framework to satisfy a length metric.
- **Explain the rule that syntax cannot.** Comments state why a loop repeats, which coordinate
  space a transform uses, or which proposed value wins. Use direct sentences. Keep extended
  contracts in the owning context document, with a short source comment where needed. Name
  domain predicates for compound decisions; keep familiar mathematical formulas recognizable.

Review findings cite the source, the contributor task made harder and the smallest adequate
improvement. Distinguish a contract or correctness problem from optional polish. Existing debt
outside the changed responsibility goes into a follow-up; a phase review does not authorize a
repository-wide refactor. Complexity measurements prioritize inspection and never justify
mechanical fragmentation or a golden update.

## JavaScript

- **Target Chromium 88 and ES2020.** HtmlDialog loads classic scripts. `eslint.config.mjs`
  checks syntax, globals and methods introduced after Chromium 88.
- **Use one syntax style per file.** Keep existing ES5 files consistent. Use `const`, arrow functions
  and template literals where the file uses ES2020.
- **`Array.prototype.forEach.call` over `NodeList.forEach`.** The panel's own collections are not
  all real `NodeList`s, and the borrowed call works on both.
- **Sequenced statements do not share a line.** eslint cannot express this. A one-line function
  expression is fine. `a(); b();` is not.
- **Panel files are found by glob, never by a list.** A file left off a list is a file that
  nothing verifies.

## Python

- Annotate parameters and returns. Use `from __future__ import annotations` and typed
  dataclasses for values passed between translation sections. Ruff and ty check the configured files.
- Load honeybee and ladybug through the translation package's `stack.load` on first use.
- Run Python tools through `uv run` using the project's Python version and dependencies.

## Readability and public interfaces

- **Name the domain meaning.** Prefer `assigned_assembly_id` to `aid`, `item` or `value` when the
  value has that specific role. Use glossary terminology and consistent names across languages.
  Short conventional names are fine in a small, unambiguous scope; do not abbreviate to save space.
- **Make units and identity visible.** Prefer `area_m2` for a stored SI quantity. Distinguish a
  record, its ID and its occurrence path in names and types. Convert units at declared boundaries.
- **Prefer explicit control flow.** Intermediate values and straightforward branches are welcome.
  Do not compress several decisions into a clever expression or hide business behavior in dynamic
  method construction. A reader should be able to follow an operation in execution order.
- **Expose side effects.** Read operations do not repair records, write attributes or open dialogs.
  Named mutation operations own validation and transactions; UI and scripts reuse them.
- **Declare dependencies.** Use documented imports or supplied dependencies. Do not reach into
  another feature's internals or retrieve hidden business dependencies from global state.
- **Document public contracts.** State inputs, outputs, units, mutation and transaction ownership,
  failure behavior and a small working example. Identify supported APIs and compatibility changes.
- **Justify abstractions by what the reader can stop knowing.** Similar syntax is insufficient.
  A little duplication is preferable to a generic framework with unrelated options and callbacks.
- **Distinguish failure states.** Absent, invalid, unsupported and unavailable data have different
  consequences. Preserve the distinction and explain a recovery path at the user-facing boundary.
- **Optimize measured bottlenecks.** Use representative models and record the evidence. Keep a
  readable implementation and preserve correctness and usable interaction times.

## Comments

Comments explain intent, domain assumptions, units and non-obvious behavior. Avoid comments that
only restate the line below them.

**Code never cites planning.** Shipped code (`src/`) and tests cite no `planning/` path and no
planning identifier (a PRD question number, a phase or stage name, a decision or acceptance id).
Planning documents are provisional and move when archived; a citation into them breaks, and an
interview number tells a reader nothing. A comment states its reason itself, including any
measured number the design depends on, with the host and Model size it was measured on. A rule too
long for a comment belongs in `context/`, and the comment names that file and section, for example
`context/CONTRACTS.md, "Retries"`; a measured host fact belongs in `SKETCHUP_HOST_BEHAVIOR.md`.
Planning and evidence documents point at code, never the reverse. Development-only tooling under
`tools/spikes/` and `tools/examples/` produces evidence and may cite it. `make lint` enforces the
rule for `src/` and `tests/`.

## Tests

- **One focused test per stated behaviour**, sized like its neighbours, named for what it proves.
- **Assert behaviour directly.** A golden file is for a registry or a contract shape, where the
  whole shape must be stable and a reviewer wants to read the diff. Exactly one test owns each
  golden.
- **A stub that deviates from the host says so in a comment and names the host fact** in
  `context/SKETCHUP_HOST_BEHAVIOR.md`. The SketchUp API stub and the DOM stub are deliberate
  approximations, and the places they diverge are where an offline pass can hide a host failure.
- **Test with the project runtimes.** `make test` uses Ruby, Node and the Python dependencies
  managed by uv. Install the Ruby and JavaScript lint packages for the full offline gate.

## Line and size limits

The line ceiling is 120 characters, including transplanted code. Method and class sizes are review
signals, not a reason to fragment a cohesive operation. Prefer a readable operation over several
tiny helpers that force readers to jump between files. Assess responsibility, branching and the
amount of context a reader must retain alongside size and complexity measurements.

The lint configuration sets the 120 ceiling in all three languages and carries method and class
size limits as review signals. Ruby layout is RuboCop's whole `Layout` department: keys and
continued arguments align with the first one, a first element on its own line is indented one step,
a continued chain or operation aligns with its first operand, and guard clauses and module inclusion
groups are followed by a blank line. `.rubocop.yml` records each chosen style; break a long line at
an argument or operator boundary, never mid-expression. A justified local exception records why the
longer unit is easier to understand; it does not disable unrelated checks. Do not weaken an existing
gate opportunistically to pass a feature change.
