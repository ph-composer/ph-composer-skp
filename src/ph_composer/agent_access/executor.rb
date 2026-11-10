# frozen_string_literal: true

require "json"

module PhComposer
  module AgentAccess
    # Runs one agent tool call on the main thread, where every PhComposer::API call belongs. The tool
    # table is the allowlist: each tool names its capability, the fixed schema its arguments must meet,
    # whether it acts on a Model session, and the one API call it makes. Nothing a request names is
    # called otherwise.
    #
    # A token acts on a session through one caller handle, issued by `API.connect` with the token's
    # capabilities the first time the token names that session and kept while both live, so its
    # sequences and retained outcomes carry across calls. Dispatch enforces the grants as for any caller.
    class Executor
      # `run` receives the caller's OperationContext (nil for a tool that names no session), the validated
      # arguments, the token's public row and that binding's Sequencer, and returns the API's answer.
      Tool = Struct.new(:name, :description, :capability, :input_schema, :session, :annotations, :run,
                        keyword_init: true)
      # Serialized `structuredContent` larger than this is refused, never truncated: both target clients
      # fail a larger result (context/AGENT_INTERFACE.md, "User-controlled local access").
      MAX_RESULT_BYTES = Pages::REPLY_BYTES
      # The most of a caller's own text (a name, a schema path) an error message repeats back.
      MAX_ECHO = 160
      SESSION_UNKNOWN = "That Model session is closed or was never opened. Call discover for the open ones."

      Binding = Struct.new(:context, :sequencer)

      # `bindings` outlives this Executor (AgentAccess.bindings), so a listener restarted on another port
      # keeps each token's caller handle, sequences and keys.
      def initialize(tools:, bindings: AgentAccess.bindings)
        @tools = tools
        @bindings = bindings
      end

      # The tool result for one call by `token` (its public row from the snapshot it authenticated with).
      def call(token, name, arguments)
        live = Tokens.snapshot.values.find { |row| row.fetch("id") == token.fetch("id") }
        unless live
          prune
          return revoked
        end

        tool = @tools[name]
        return error("There is no tool named #{name.to_s[0, MAX_ECHO].inspect}.") unless tool && granted?(live, tool)

        findings = JsonSchema.validate(arguments, tool.input_schema)
        return error("The arguments are not valid: #{findings.first.to_s[0, MAX_ECHO]}.") unless findings.empty?

        prune
        binding = Binding.new(nil, nil)
        if tool.session
          session = Sessions.find(arguments["session"])
          unless session && Tokens.serves?(live, session)
            bound = session && live["model_name"] ? " This token reaches only #{live['model_name']}." : ""
            return result(Outcome.refused("session.unknown", SESSION_UNKNOWN + bound, :revision => nil))
          end

          binding = binding_for(live, session)
        end
        answer = tool.run.call(binding.context, arguments, live, binding.sequencer)
        note_committed(live, arguments, answer) if name == "invoke"
        result(answer, :acted => acts?(tool, arguments))
      rescue CodedError => error
        result(Outcome.refused(error.code, error.message, :revision => nil, :detail => error.detail))
      end

      # The answer to a call whose token was revoked before it ran.
      def revoked
        error("This token was revoked; nothing ran.", "access.revoked")
      end

      # The answer a worker gives without the main thread: no SketchUp call, only an Outcome.
      def busy(message)
        result(Outcome.refused("session.busy", message, :status => "busy", :revision => nil))
      end

      # The answer for a call that raised unexpectedly; the cause is in the diagnostics log only.
      def failed
        result(Outcome.failed(:effect => "unknown", :revision => nil))
      end

      # Counts a committed invoke for the token's revoke acknowledgment; a replay counts once.
      def note_committed(token, arguments, answer)
        return unless answer.is_a?(Hash) && answer["effect"] == "committed"

        AgentAccess.committed(token.fetch("id"), arguments["session"], answer["sequence"])
      end

      # A tool names the capability it needs, or several of which any one will do.
      def granted?(token, tool)
        Executor.reaches?(token, tool)
      end

      def self.reaches?(token, tool)
        !(Array(tool.capability) & token.fetch("capabilities")).empty?
      end

      private

      # One caller handle and one Sequencer per token and session, so sequences and keys carry across calls.
      def binding_for(token, session)
        @bindings[[token.fetch("id"), session.id]] ||= begin
          context = API.connect(:session_id => session.id, :capabilities => token.fetch("capabilities"))
          AgentAccess.bound(token.fetch("id"), session, context.caller)
          Binding.new(context, Sequencer.new)
        end
      end

      # Forgets the handles of closed sessions and revoked tokens.
      def prune
        open = Sessions.all.map(&:id)
        live = Tokens.snapshot.values.map { |row| row.fetch("id") }
        @bindings.delete_if { |(token, session), _context| !open.include?(session) || !live.include?(token) }
        AgentAccess.prune_handles
      end

      # The MCP tool result: the answer as `structuredContent` and one line of text, not a second copy of
      # the JSON, which a client that shows both would count twice. Every result passes through here or
      # `error`, so none leaves larger than the budget.
      # `acted` marks a tool that may have changed something (every tool but the reads): its outcome is
      # never turned into a refusal by its size.
      def result(value, acted: false)
        text = JSON.generate(value)
        if text.bytesize > MAX_RESULT_BYTES && acted && outcome?(value)
          value = trimmed(value)
          text = JSON.generate(value)
          value = minimal(value) if text.bytesize > MAX_RESULT_BYTES
          text = JSON.generate(value)
        end
        if text.bytesize > MAX_RESULT_BYTES
          return error("The result is #{text.bytesize} bytes, over the #{MAX_RESULT_BYTES}-byte limit. Ask for " \
                       "less: a smaller page, fewer fields or one owner's operations.",
                       "request.response_too_large")
        end

        { "content" => [{ "type" => "text", "text" => summary(value) }], "structuredContent" => value,
          "isError" => false }
      end

      def outcome?(value)
        value.is_a?(Hash) && value.key?("status") && value.key?("effect")
      end

      # Whether a call may have changed something, so an oversized answer is trimmed rather than refused: every
      # tool but the reads, and not export_status with part, which reads what an ended task kept.
      def acts?(tool, arguments)
        tool.capability != "read" && !(tool.name == "export_status" && arguments.key?("part"))
      end

      # What a tool that acts did is never reported as refused because its answer was large: the outcome
      # keeps its status, code, effect, revision and sequence, and drops the value and the lists, which the
      # caller reads back.
      def trimmed(outcome)
        outcome.merge("message" => "#{outcome['message']} The full result was over the reply limit; read back " \
                                   "what it changed.",
                      "value" => task_receipt(outcome["value"]), "affected" => [], "findings" => [],
                      "detail" => { "omitted" => %w[value affected findings] })
      end

      # An export task's identity, stage, source and outcome with its artifacts and diagnostics counts, so a
      # caller keeps which run it was, where its files are and what they hash to when the task's diagnostics are
      # too large to send (export_status with part reads them); nil for anything else.
      def task_receipt(value)
        return nil unless value.is_a?(Hash) && value.key?("task_id")

        outcome = value["outcome"]
        inner = outcome && outcome["value"].is_a?(Hash) ? outcome["value"].slice("artifacts") : nil
        kept = outcome && outcome.slice("status", "code", "effect", "revision")
                                 .merge("message" => outcome["message"].to_s[0, MAX_ECHO * 2], "value" => inner)
        value.slice("task_id", "stage", "count", "cancellable", "source", "diagnostics").merge("outcome" => kept)
      end

      # Only what says what happened, for an outcome still over the budget once trimmed.
      # An export task keeps its id, source and outcome code, which export_status with part reads from.
      def minimal(outcome)
        task = outcome["value"].is_a?(Hash) && outcome["value"]["task_id"] ? outcome["value"] : nil
        kept = task && task.slice("task_id", "stage", "source").merge(
          "outcome" => task["outcome"]&.slice("status", "code", "effect", "revision")
        )
        Outcome.build(outcome["status"], outcome["code"], "The result was over the reply limit; read back what " \
                                                          "it changed.", outcome["effect"], outcome["revision"],
                      :value => kept)
               .merge(outcome.slice("sequence"))
      end

      def summary(value)
        return "Result in structuredContent." unless value.is_a?(Hash) && value["status"]

        [value["status"], value["code"], value["message"]].compact.join(": ")
      end

      # A tool error still carries the whole Outcome envelope `discover` publishes.
      def error(message, code = nil)
        outcome = Outcome.refused(code || "request.malformed", message[0, 2 * MAX_ECHO], :revision => nil)
        { "content" => [{ "type" => "text", "text" => outcome["message"] }], "structuredContent" => outcome,
          "isError" => true }
      end
    end
  end
end
