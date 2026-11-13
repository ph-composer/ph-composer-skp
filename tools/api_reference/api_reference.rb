# frozen_string_literal: true

require "json"

# Development only: never shipped. Writes docs/API_REFERENCE.md from the registered declarations, so
# the reference cannot drift from what discovery and validation use. tests/api_reference_test.rb owns
# the file: `make fixtures` rewrites it and every other run compares it.
module PhComposerTools
  module ApiReference
    # Each group's capability is the one dispatch enforces for its kind.
    GROUPS = [["Queries", :queries, "query"], ["Actions", :actions, "action"],
              ["View commands", :view_commands, "view_command"], ["Setup commands", :setup_commands, "setup_command"],
              ["File exports", :file_exports, "file_export"]].map do |title, key, kind|
      [title, key, PhComposer::Declarations::CAPABILITIES.fetch(kind)]
    end.freeze

    module_function

    def markdown(registry)
      [intro, kinds(registry), library_kinds(registry), common_refusals,
       *GROUPS.map { |title, key, capability| operations(registry, title, key, capability) },
       participants(registry), tasks, codes(registry), changes].join("\n")
    end

    def intro
      <<~MARKDOWN
        # PH-Composer API reference

        Run `make fixtures` to regenerate this reference from the registered declarations. Start
        with the [Ruby quickstart](API_QUICKSTART.md) or [agent setup](AGENT_ACCESS.md).

        - Data: [record kinds](#record-kinds), [library kinds](#library-kinds)
        - Operations: [queries](#queries), [actions](#actions), [view commands](#view-commands),
          [setup commands](#setup-commands), [file exports](#file-exports), [export tasks](#export-tasks)
        - Contracts: [proposal participants](#proposal-participants), [common refusals](#common-refusals),
          [feature codes](#feature-codes), [API changes](#api-changes)

        Use `PhComposer::API.describe(name:)` to read a declaration in the running extension.
        Params and results use JSON Schema. A number's `x-unit` gives its canonical SI unit.
        Operation calls return an outcome with these fields.

        | Field | Meaning |
        | --- | --- |
        | `status` | `completed`, `refused`, `failed`, `busy`, `pending` or `cancelled` |
        | `code` | `ok`, or why the request did not complete, such as `revision.stale` or `target.changed` |
        | `effect` | What happened to the Model: `none`, `committed`, `rolled_back` or `unknown` |
        | `revision` | The Model revision associated with the outcome. Use the revision of the read your edit relies on |
        | `value` | The operation's result, described below as its result schema; absent unless completed |
        | `affected` | Each record an action changed: `kind`, `id`, `change` and, for entities, `reference` |
        | `findings` | Advisory rows the operation reports without refusing |
        | `detail` | Structured data a caller needs to act on a refusal |
        | `proposal_digest` | Digest of the preview. Send it with invoke to apply the reviewed change |

        Check `effect` before retrying a refusal or failure. A no-op completes with `effect` `none`
        and adds no Undo step.
      MARKDOWN
    end

    def kinds(registry)
      rows = registry.record_kinds.values.map { |kind| ["catalog", kind.descriptor] } +
             registry.reference_targets.values.map { |target| ["entity", target.descriptor] }
      sections = rows.sort_by { |_storage, descriptor| descriptor.kind }.map do |storage, descriptor|
        kind_section(registry, storage, descriptor)
      end
      "## Record kinds\n\nA catalog kind is stored in the Model's own records and read through " \
        "`ph_composer.records.list`. An entity kind is stored on SketchUp geometry and read through its " \
        "owner's queries; its writes are its owner's actions.\n\n#{sections.join("\n")}"
    end

    def kind_section(registry, storage, descriptor)
      description = descriptor.to_h
      lines = ["### `#{descriptor.kind}`", "",
               "#{descriptor.label}, a #{storage} kind owned by `#{registry.owner_of(descriptor.kind)}`, " \
               "schema version #{descriptor.schema_version.inspect}.", ""]
      unless description.fetch("references").empty?
        lines << "References: " + description.fetch("references").map do |reference|
          "`#{reference.fetch('key')}` names #{reference.fetch('cardinality')} `#{reference.fetch('target_kind')}`"
        end.join("; ") + "."
        lines << ""
      end
      lines.concat(json_block("Values", description.fetch("values")))
      occurrence = description.fetch("occurrence_reference")
      lines.concat(json_block("Occurrence reference", occurrence)) if occurrence
      lines.join("\n")
    end

    def operations(registry, title, key, capability)
      declarations = registry.public_send(key).values.sort_by(&:name)
      "## #{title}\n\nCalled with a context granted `#{capability}`.\n\n" +
        declarations.map { |declaration| operation_section(declaration, registry) }.join("\n")
    end

    # Each library kind as `describe` answers it: what `ph_composer.library.copy` copies, and the target its
    # `assignment` param takes, or that it takes none.
    def library_kinds(registry)
      sections = registry.library_kinds.values.sort_by(&:name).map do |declaration|
        described = PhComposer::Library::KindDescriptor.call(declaration)
        lines = ["### `#{described.fetch('name')}`", "",
                 "Wire kind `#{described.fetch('wire_kind')}`, version #{described.fetch('wire_version')}, copied " \
                 "as `#{described.fetch('record_kind')}`. Owner: `#{described.fetch('owner')}`.", ""]
        assignment = described.fetch("assignment")
        unless assignment.fetch("supported")
          lines << "No assignment: `ph_composer.library.copy` refuses one with `library.assignment_unavailable`."
          next lines.join("\n") + "\n"
        end

        lines.concat(json_block("Assignment target", assignment.fetch("target")))
        assignment.fetch("examples").each { |example| lines.concat(json_block("Example assignment", example)) }
        lines.join("\n")
      end
      "## Library kinds\n\nWhat `ph_composer.library.copy` can copy, by the wire kind its `kind` param names. " \
        "Its `assignment` param takes the kind's assignment target, and the copy and the assignment are one " \
        "Undo step.\n\n#{sections.join("\n")}"
    end

    # Participants answer no client, so they have a section of their own rather than a capability.
    def participants(registry)
      sections = registry.proposal_participants.values.sort_by(&:name).map do |declaration|
        operation_section(declaration, registry)
      end
      "## Proposal participants\n\nCalled by no client. An action of a feature that requires the owner names " \
        "the participant in its `participants` and calls it inside its own proposal; its refusals are " \
        "included in that action's.\n\n#{sections.join("\n")}"
    end

    # The codes every operation of a kind can answer, printed once instead of under each operation.
    def common_refusals
      rows = PhComposer::Refusals::COMMON.map do |set, codes|
        "| `#{set}` | #{codes.map { |code| "`#{code}`" }.join(', ')} |"
      end
      "## Common refusals\n\nEvery operation answers the codes of its kind's set besides its own, and an " \
        "operation that needs the user to choose a location also answers the `approval` set. Each operation " \
        "below lists only its own codes. `PhComposer::API.discover` returns these sets as `common_refusals`, " \
        "and `describe` returns an operation's own codes as `refuses` and the sets it answers as " \
        "`common_refusal_sets`. Every refusal has `code`, `owner` and `description`; the foundation's " \
        "description is null. Discovery's `refusal_documentation` points to " \
        "[Outcomes and codes](#{PhComposer::API.discover.fetch('refusal_documentation')}).\n\n" \
        "| Set | Codes |\n| --- | --- |\n#{rows.join("\n")}\n\n" \
        "What each common code means, as the agent connection's discover section `refusals` gives it:\n\n" \
        "| Code | Meaning |\n| --- | --- |\n#{meanings}\n"
    end

    def meanings
      PhComposer::Refusals::MEANINGS.sort.map { |code, meaning| "| `#{code}` | #{meaning} |" }.join("\n")
    end

    # The shell's export task methods: API methods with keyword arguments, not registered operations.
    def tasks
      sections = PhComposer::Export::TaskContract::TASKS.keys.map do |name|
        task = PhComposer::Export::TaskContract.describe(name)
        lines = ["### `PhComposer::API.#{name}`", "",
                 "#{task.fetch('description')} Needs `#{task.fetch('capability')}`.", ""]
        lines.concat(json_block("Keyword arguments besides context", task.fetch("params")))
        lines.concat(json_block("Result value", task.fetch("result")))
        task.fetch("examples").each { |example| lines.concat(json_block("Example arguments", example)) }
        lines.join("\n")
      end
      "## Export tasks\n\nHBJSON runtime exports use retained task methods. " \
        "Each params key is the method's keyword argument.\n\n#{sections.join("\n")}"
    end

    # Each feature's own codes. Foundation and shared-noun codes are in context/CONTRACTS.md.
    # Every shape change under this major (PhComposer::API::CHANGES), so a client built against an
    # earlier minor can see what it would now read.
    def changes
      rows = PhComposer::API::CHANGES.map { |row| "| 1.#{row['minor']} | #{row['date']} | #{row['change']} |" }
      "## API changes\n\n| Version | Date | Change |\n| --- | --- | --- |\n#{rows.join("\n")}\n"
    end

    def codes(registry)
      sections = registry.codes.values.group_by(&:owner).sort.map do |owner, codes|
        rows = codes.sort_by(&:code).map { |code| "| `#{code.code}` | #{code.description} |" }
        ["### `#{owner}`", "", "| Code | Meaning |", "| --- | --- |", *rows, ""].join("\n")
      end
      "## Feature codes\n\nThe codes each feature raises under its own noun, as an outcome's `code` or a " \
        "finding's. The foundation's and the shared nouns' codes are listed in context/CONTRACTS.md, " \
        "\"Outcomes and codes\".\n\n#{sections.join("\n")}"
    end

    def operation_section(declaration, registry)
      lines = ["### `#{declaration.name}`", "", "#{declaration.description} Owner: `#{declaration.owner}`.", ""]
      terms_lines(declaration).each { |line| lines.push(line, "") }
      if declaration.respond_to?(:approval) && declaration.approval
        noun = PhComposer::NativeApproval.noun(declaration.approval)
        lines << if declaration.approval.standing
                   "Needs the user: the panel or menu asks for a #{noun} and keeps it as an approved location; " \
                     "any other caller is refused with `access.user_required`."
                 else
                   "Needs the user: the panel or menu asks for a #{noun} first. Any other caller passes " \
                     "`location`, the id of a location the user approved, or is refused with " \
                     "`access.user_required`."
                 end
        lines << ""
      end
      calls = declaration.respond_to?(:participants) ? Array(declaration.participants) : []
      unless calls.empty?
        lines << "Calls: #{calls.map { |name| "`#{name}`" }.join(', ')}."
        lines << ""
      end
      lines << refuses_line(declaration, registry)
      lines << ""
      lines.concat(json_block("Params", declaration.params))
      lines.concat(json_block("Result", declaration.result))
      Array(declaration.examples).each { |example| lines.concat(json_block("Example params", example)) }
      lines.join("\n")
    end

    # The Undo step and side effects, preconditions and an unbounded read's alternative, as declared.
    def terms_lines(declaration)
      lines = []
      if declaration.is_a?(PhComposer::Declarations::Action)
        lines << "Undo step: #{declaration.undo_name}. #{declaration.side_effects}"
      elsif declaration.respond_to?(:side_effects) && declaration.side_effects
        lines << "Side effects: #{declaration.side_effects}"
      end
      own = declaration.respond_to?(:capability) ? declaration.capability : nil
      lines << "Needs the `#{own}` grant rather than `view`." if own && own != "view"
      preconditions = declaration.respond_to?(:preconditions) ? Array(declaration.preconditions) : []
      lines << "Before calling: #{preconditions.join(' ')}" unless preconditions.empty?
      if declaration.respond_to?(:response) && declaration.response
        lines << "Unbounded: answers the whole Model in one result. A client with a reply budget reads " \
                 "`#{declaration.response['prefer']}` instead."
      end
      lines
    end

    def refuses_line(declaration, registry)
      sets = PhComposer::Refusals.common_sets(declaration).map { |set| "`#{set}`" }.join(" and ")
      noun = sets.include?(" and ") ? "sets" : "set"
      codes = PhComposer::Refusals.declared(declaration, registry).sort
      return "Refuses: only the #{sets} common #{noun}." if codes.empty?

      "Refuses: #{codes.map { |code| "`#{code}`" }.join(', ')}, and the #{sets} common #{noun}."
    end

    # Empty containers are collapsed because json gem versions lay them out differently; the page
    # must not go stale on a gem update (tests/support/fixture_files.rb says the same for goldens).
    def json_block(label, value)
      text = JSON.pretty_generate(value).gsub(/\[\n\s*\]/, "[]").gsub(/\{\n\s*\}/, "{}")
      ["#{label}:", "", "```json", text, "```", ""]
    end
  end
end
