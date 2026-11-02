# frozen_string_literal: true

module PhComposer
  module Operations
    # One immutable-preview proposal combining record writes with feature-owned SketchUp steps. Steps
    # hold detached paths and values; they resolve live entities again when applied.
    class Proposal
      attr_reader :record_changes, :steps, :findings

      def initialize
        @record_changes = Records::ChangeSet.new
        @steps = []
        @scopes = []
        @findings = []
        @captures = nil
        @commit_checks = []
      end

      # A check that must still pass when the proposal is applied, not only when it was staged: a
      # time-bound permission such as a library use check. Dispatch runs every one immediately before
      # the native transaction opens (`run_commit_checks!`); one that raises refuses the whole proposal.
      def add_commit_check(&check)
        @commit_checks << check
      end

      def run_commit_checks!
        @commit_checks.each(&:call)
      end

      def add_step(step, scopes:)
        @steps << step
        Array(scopes).each { |scope| @scopes << scope unless @scopes.any? { |item| item.path == scope.path } }
        step
      end

      def add_finding(finding)
        @findings << DeepCopy.call(finding)
      end

      def capture(model)
        @captures = @scopes.to_h { |scope| [scope, scope.capture(model)] }
      end

      def apply(model, engine)
        slots = {}
        @steps.each { |step| step.apply(model, slots) }
        engine.apply(record_changes)
      end

      def unchanged?(model, engine)
        return false unless @captures

        engine.unchanged?(record_changes) && @captures.all? { |scope, before| scope.unchanged?(model, before) }
      end

      def digest
        value = {
          "record_changes" => record_changes.writes.map(&:descriptor),
          "steps" => steps.map(&:descriptor), "findings" => findings
        }
        CanonicalJson.digest(replace_temporary_ids(value, temporary_id_mapping))
      end

      def affected
        record_changes.affected + steps.flat_map(&:affected)
      end

      def empty?
        record_changes.empty? && steps.empty?
      end

      def refusal
        record_changes.refusal
      end

      def refuse(error)
        record_changes.refuse(error)
      end

      # Confines record writes while the block runs (Records::ChangeSet#guarded).
      def guarded(kinds, code, &block)
        record_changes.guarded(kinds, code, &block)
      end

      def put(*arguments, **keywords)
        record_changes.put(*arguments, **keywords)
      end

      def restage(*arguments, **keywords)
        record_changes.restage(*arguments, **keywords)
      end

      def delete(*arguments, **keywords)
        record_changes.delete(*arguments, **keywords)
      end

      def find(*arguments)
        record_changes.find(*arguments)
      end

      def writes
        record_changes.writes
      end

      private

      def temporary_id_mapping
        ids = record_changes.writes.select { |write| write.before.nil? }.map(&:id)
        ids.concat(steps.flat_map { |step| step.respond_to?(:temporary_ids) ? step.temporary_ids : [] })
        ids.uniq.each_with_index.to_h { |id, index| [id, "$created:#{index + 1}"] }
      end

      def replace_temporary_ids(value, mapping)
        case value
        when Hash
          value.to_h { |key, item| [key, replace_temporary_ids(item, mapping)] }
        when Array
          value.map { |item| replace_temporary_ids(item, mapping) }
        when String
          mapping.fetch(value, value)
        else
          value
        end
      end
    end
  end
end
