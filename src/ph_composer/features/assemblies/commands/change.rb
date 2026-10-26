# frozen_string_literal: true

module PhComposer
  module Assemblies
    module Commands
      # Detached command output. The record engine validates references and expected values when
      # the handler proposes this change; the pure command never reads or writes a Model.
      Change = Struct.new(:record, :findings, keyword_init: true)

      module_function

      def mutate(record, materials = {})
        candidate = DeepCopy.call(record)
        yield candidate
        problems = Assembly::Schema::KIND.problems(candidate)
        unless problems.empty?
          raise CodedError.new("validation.failed", problems.first, "findings" => problems)
        end

        Change.new(:record => candidate, :findings => Validation.assembly(candidate, materials))
      end

      def patch(record, values)
        candidate = DeepCopy.call(record)
        values.each { |key, value| value.nil? ? candidate.delete(key) : candidate[key] = DeepCopy.call(value) }
        candidate
      end

      def layer!(record, layer_id)
        layer = record.fetch("layers").find { |entry| entry.fetch("id") == layer_id }
        raise CodedError.new("target.not_found", "Layer #{layer_id} was not found.") unless layer

        layer
      end

      def segment!(layer, segment_id)
        segment = layer.fetch("segments").find { |entry| entry.fetch("id") == segment_id }
        raise CodedError.new("target.not_found", "Layer-Segment #{segment_id} was not found.") unless segment

        segment
      end

      def index!(value, size)
        return value if value.is_a?(Integer) && value.between?(0, size)

        raise CodedError.new("params.invalid", "The insertion index must be a whole number from 0 to #{size}.")
      end
    end
  end
end
