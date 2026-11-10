# frozen_string_literal: true

module PhComposer
  module AgentAccess
    # The tools an agent sees: the public API's verbs, each with a small fixed schema
    # (context/AGENT_INTERFACE.md, "User-controlled local access"). Operation schemas are not copied
    # here; an agent reads them with `describe`, so an outside feature's operations work with no change
    # to this table. This table is the allowlist the Executor runs and `tools/list` shows.
    module Tools
      OPERATION_KINDS = Discovery::OPERATION_KINDS.keys.freeze
      INDEX_KEYS = %w[api extension capabilities sessions features schemas].freeze

      module_function

      def string(description)
        { "type" => "string", "minLength" => 1, "description" => description }
      end

      def object(properties, required)
        { "type" => "object", "additionalProperties" => false, "required" => required, "properties" => properties }
      end

      SESSION = string("The Model session id, from discover's sessions.")
      NAME = string("The operation's name, from discover.")
      PARAMS = { "type" => "object", "description" => "The operation's params, as describe's params schema says." }
      READ_ONLY = { "readOnlyHint" => true, "openWorldHint" => false }.freeze
      WRITES = { "readOnlyHint" => false, "openWorldHint" => false }.freeze
      KEY = { "type" => "string", "minLength" => 1, "maxLength" => Sequencer::MAX_KEY,
              "description" => "Your own name for this change, up to #{Sequencer::MAX_KEY} characters. Send the same " \
                               "key again after a lost reply: the same request answers its first outcome and is " \
                               "never applied twice." }.freeze
      REVISION = { "type" => "integer", "description" => "The revision of the read this change is based on." }.freeze

      # Without a section or an owner, a compact index: every operation's name by kind and owner, the
      # sections to page and the guide. With a section, one bounded page of it (AgentAccess::Discovery).
      # With only an owner, that owner's full entries, unpaged as before. The whole discovery document is
      # larger than one tool result may be.
      def discover(arguments, token)
        document = API.discover
        sessions = served(document.fetch("sessions"), token)
        document = document.merge("sessions" => sessions)
        connection = token.slice("id", "label", "capabilities", "model_name")
        connection["reason"] = unserved(token) if sessions.empty? && token["model_name"]
        page = if arguments["section"]
                 Discovery.section(document, arguments)
               elsif (owner = arguments["owner"])
                 Discovery.check_unsectioned(arguments)
                 owned(document, owner)
               else
                 Discovery.check_unsectioned(arguments)
                 Discovery.index(document, INDEX_KEYS)
               end
        page.merge("connection" => connection)
      end

      # The sessions a token may act on: a Model-only token sees only its own Model's.
      def served(sessions, token)
        sessions.select { |row| (session = Sessions.find(row["id"])) && Tokens.serves?(token, session) }
      end

      # Why a Model-only token reaches no open session, by file names only: its own, and the open ones.
      def unserved(token)
        bound = token["model_name"]
        names = Sessions.all.map { |session| File.basename(session.model.path.to_s) }.map do |name|
          next "an unsaved Model" if name.empty?

          name == bound ? "#{name} (in another folder)" : name
        end
        open = names.empty? ? "no Model is open" : "open now: #{names.join(', ')}"
        "This token is bound to #{token['model_name']}, which is not open; #{open}. Open #{token['model_name']} " \
          "in SketchUp, or ask the user for a token for this Model."
      end

      def owned(document, owner)
        unless document.fetch("features").any? { |feature| feature["id"] == owner }
          raise CodedError.new("params.invalid", "There is no feature #{owner[0, 80].inspect}; discover lists them.")
        end

        { "owner" => owner }.merge(OPERATION_KINDS.to_h do |kind|
          [kind, document.fetch(kind).select { |entry| entry["owner"] == owner }]
        end)
      end

      def describe(arguments)
        API.describe(:name => arguments.fetch("name")) ||
          Outcome.refused("request.unknown_operation", "There is no operation named " \
                                                       "#{arguments.fetch('name')[0, 120].inspect}.", :revision => nil)
      end

      def tool(name, description, input_schema, session:, capability: "read", annotations: nil, &run)
        hints = annotations || (capability == "read" ? READ_ONLY : WRITES)
        Executor::Tool.new(:name => name, :description => description, :capability => capability,
                           :input_schema => input_schema, :session => session, :annotations => hints,
                           :run => run).freeze
      end

      # The whole preview when it fits one reply, else its compact form; with `part`, one fragment of that part.
      def preview(context, arguments)
        name = arguments["name"]
        params = arguments.fetch("params", {})
        if arguments.key?("cursor") && !arguments.key?("part")
          return Outcome.refused("params.invalid", "A cursor reads the next fragment of a part; name the part.",
                                 :revision => nil)
        end
        if arguments.key?("part")
          return API.preview_part(:context => context, :name => name, :params => params, :part => arguments["part"],
                                  :cursor => arguments["cursor"])
        end

        API.preview(:context => context, :name => name, :params => params, :within => Executor::MAX_RESULT_BYTES)
      end

      # One mutation with the sequence the binding assigns, which every invoke result carries.
      def invoke(context, arguments, sequencer)
        sequence = sequencer.assign(arguments["idempotency_key"])
        request = { "sequence" => sequence, "expected_revision" => arguments.fetch("expected_revision"),
                    "proposal_digest" => arguments["proposal_digest"] }.compact
        API.invoke(:context => context, :name => arguments["name"], :params => arguments.fetch("params", {}),
                   :request => request).merge("sequence" => sequence)
      end

      # The retained outcome of an invoke, by its sequence or by the key it was sent with.
      def outcome(context, arguments, sequencer)
        sequence = arguments["sequence"] || sequencer.lookup(arguments["idempotency_key"])
        unless sequence
          return Outcome.refused("request.outcome_unavailable", "This connection sent no change with that key; " \
                                                                "inspect the Model before issuing new work.",
                                 :revision => nil)
        end

        API.outcome(:context => context, :request => { "sequence" => sequence }).merge("sequence" => sequence)
      end

      # A task method's bounded-read options from the arguments, as the API's keyword arguments.
      def task_options(name, arguments)
        keys = Export::TaskContract::TASKS.fetch(name).dig("params", "properties").keys - %w[location task_id]
        arguments.slice(*keys).transform_keys(&:to_sym)
      end

      # A task method's params with the session it runs on.
      def task_schema(name)
        params = Export::TaskContract::TASKS.fetch(name).fetch("params")
        object({ "session" => SESSION }.merge(params.fetch("properties")), ["session"] + params.fetch("required", []))
      end

      # A run block for a verb that takes a name and params; a proc, so the executor's extra arguments drop.
      def operation(&call)
        proc do |context, arguments|
          call.call(:context => context, :name => arguments["name"], :params => arguments.fetch("params", {}))
        end
      end

      TABLE = [
        tool("discover", "Start here. Lists the open Model sessions with their ids and file names, the features, " \
                         "every operation's name, the sections to page and the operating guide. Pass section for " \
                         "one bounded page: operations (with owner for one feature's), features, record_kinds, " \
                         "reference_targets, extensions, library_kinds, refusals, contracts or guide (with topic " \
                         "for one topic's text).",
             object({ "owner" => string("A feature id from this tool's features list."),
                      "section" => { "type" => "string", "enum" => Discovery::SECTIONS,
                                     "description" => "One section of what is installed, a bounded page at a time." },
                      "topic" => string("With section guide: one topic's id, from the guide section's topics."),
                      "limit" => { "type" => "integer", "minimum" => 1, "maximum" => Pages::MAXIMUM_LIMIT,
                                   "description" => "With a list section: rows per page, " \
                                                    "#{Pages::DEFAULT_LIMIT} when absent." },
                      "cursor" => string("With a list section: next_cursor from its previous page.") }, []),
             :session => false) { |_context, arguments, token| discover(arguments, token) },
        tool("describe", "The full declaration of one operation: what it does, its params and result schemas, " \
                         "examples and refusals. Read it before calling the operation.",
             object({ "name" => NAME }, ["name"]), :session => false) { |_context, arguments| describe(arguments) },
        tool("query", "Runs a read-only query on one Model session. Nothing in the Model changes.",
             object({ "session" => SESSION, "name" => NAME, "params" => PARAMS }, %w[session name]),
             :session => true) do |context, arguments|
          API.query(:context => context, :name => arguments["name"], :params => arguments.fetch("params", {}))
        end,
        tool("preview", "Shows what an action would change on one Model session without changing anything, with " \
                        "the proposal digest an invoke can carry. A preview larger than one reply leaves out value, " \
                        "affected and findings and gives each one's size and digest in detail.parts: read each " \
                        "with part, following next_cursor, and join the fragments' text; after any change the next " \
                        "fragment is refused as query.cursor_expired.",
             object({ "session" => SESSION, "name" => NAME, "params" => PARAMS,
                      "part" => { "type" => "string", "enum" => PreviewParts::PARTS,
                                  "description" => "One part of the preview, as canonical JSON text in fragments." },
                      "cursor" => string("With part: next_cursor from its previous fragment.") }, %w[session name]),
             :session => true) { |context, arguments| preview(context, arguments) },
        tool("context", "Where one Model session stands: its file name and path, revision, whether it is busy, " \
                        "the edit path from the root and the selection, in pages. Read it before acting on the " \
                        "selection or the open Group.",
             object({ "session" => SESSION, "limit" => { "type" => "integer" },
                      "cursor" => string("next_cursor from the previous page.") }, ["session"]),
             :session => true) do |context, arguments|
          API.query(:context => context, :name => ContextCommands::READ,
                    :params => arguments.slice("limit", "cursor"))
        end,
        tool("export_preflight", "Checks whether one Model session can export now and what would block it, " \
                                 "optionally against an approved destination's id. compact counts by owner and " \
                                 "code; part pages findings or repairs with filters, and row reads one whole.",
             task_schema("export_preflight"), :session => true) do |context, arguments|
          API.export_preflight(:context => context, :location => arguments["location"],
                               **task_options("export_preflight", arguments))
        end,
        tool("invoke", "Applies one action to one Model session as one Undo step, refused with nothing written if " \
                       "the Model changed since expected_revision. Preview first for a compound edit. The result " \
                       "carries the sequence this connection assigned.",
             object({ "session" => SESSION, "name" => NAME, "params" => PARAMS, "expected_revision" => REVISION,
                      "idempotency_key" => KEY,
                      "proposal_digest" => string("The proposal_digest a preview returned, to refuse a change " \
                                                  "that is no longer the same.") },
                    %w[session name expected_revision]),
             :session => true, :capability => "model_write",
             :annotations => WRITES.merge("idempotentHint" => true)) do |context, arguments, _token, sequencer|
          invoke(context, arguments, sequencer)
        end,
        tool("outcome", "The outcome of an earlier invoke, by its sequence or idempotency_key, without running it " \
                        "again: after a lost reply, read it here before deciding anything.",
             object({ "session" => SESSION, "sequence" => { "type" => "integer", "minimum" => 1 },
                      "idempotency_key" => KEY }, ["session"]),
             :session => true, :capability => "model_write",
             :annotations => READ_ONLY) do |context, arguments, _token, sequencer|
          outcome(context, arguments, sequencer)
        end,
        # A capture is a view command under its own grant, so either grant reaches this tool and dispatch
        # applies the one the command declares.
        tool("view", "Runs a view command: the camera, the selection, the open Group, or ph_composer.view.capture " \
                     "for an image of the view. Never changes authored data; describe says what else it can " \
                     "trigger, as its side_effects, and which grant it needs.",
             object({ "session" => SESSION, "name" => NAME, "params" => PARAMS }, %w[session name]),
             :session => true, :capability => %w[view capture], &operation { |**call| API.view(**call) }),
        tool("setup", "Runs a setup command: this computer's libraries and settings, for every Model.",
             object({ "session" => SESSION, "name" => NAME, "params" => PARAMS }, %w[session name]),
             :session => true, :capability => "setup", &operation { |**call| API.setup(**call) }),
        tool("export_file", "Runs a file export to a location the user approved, named by its id.",
             object({ "session" => SESSION, "name" => NAME, "params" => PARAMS }, %w[session name]),
             :session => true, :capability => "export", &operation { |**call| API.export_file(**call) }),
        tool("start_export", "Starts the HBJSON export of one Model to a destination the user approved; poll it " \
                             "with export_status.",
             task_schema("start_export"), :session => true, :capability => "export") do |context, arguments|
          API.start_export(:context => context, :location => arguments.fetch("location"))
        end,
        tool("export_status", "One export task's progress and, once it ends, its outcome; compact while polling. " \
                              "Once it ended, part reads what it kept: findings a page at a time, the report or " \
                              "the result in fragments, unchanged by later edits.",
             task_schema("export_status"), :session => true, :capability => "export",
                                           :annotations => READ_ONLY) do |context, arguments|
          API.export_status(:context => context, :task_id => arguments.fetch("task_id"),
                            **task_options("export_status", arguments))
        end,
        tool("cancel_export", "Cancels an export task before it starts writing.",
             task_schema("cancel_export"), :session => true, :capability => "export") do |context, arguments|
          API.cancel_export(:context => context, :task_id => arguments.fetch("task_id"))
        end,
        tool("latest_export", "The most recent export task this token started on the Model, to find one after a " \
                              "lost reply.",
             task_schema("latest_export"), :session => true, :capability => "export",
                                           :annotations => READ_ONLY) do |context, arguments|
          API.latest_export(:context => context, **task_options("latest_export", arguments))
        end
      ].to_h { |entry| [entry.name, entry] }.freeze
    end
  end
end
