# frozen_string_literal: true

module PhComposer
  # One Model-owned settings dictionary. Features declare the schema and domain checks; this
  # service reads without repair and stages one guarded write in the caller's native operation.
  class ModelSettings
    attr_reader :store, :defaults, :schema, :label, :step_name, :affected

    def initialize(dictionary:, defaults:, schema:, label:, step_name:, affected:, &problems)
      @store = Records::EntityStore.new(dictionary)
      @defaults = DeepCopy.frozen(defaults)
      @schema = DeepCopy.frozen(schema)
      @label = label.dup.freeze
      @step_name = step_name.dup.freeze
      @affected = DeepCopy.frozen(affected)
      @problems = problems
      validate!(@defaults)
    end

    # Stored settings that fail validation are unreadable: a read refuses rather than repairs them.
    def read(model)
      values = effective(store.read(model))
      problem = problems(values).first
      raise CodedError.new("record.unreadable", "#{label} settings cannot be used: #{problem}.") if problem

      values
    end

    # A field the stored dictionary does not hold takes its default, so a field added later needs no migration.
    # Anything but an object passes through for validation to refuse.
    def effective(stored)
      return DeepCopy.call(defaults) if stored.nil?

      stored.is_a?(Hash) ? DeepCopy.call(defaults).merge(stored) : stored
    end

    def validate!(values)
      problem = problems(values).first
      return values unless problem

      raise CodedError.new("validation.failed", "#{label} settings are invalid: #{problem}. Nothing was written.")
    end

    def propose(model, proposal, values:, expected_values:)
      before = read(model)
      unless before == expected_values
        raise CodedError.new("target.changed", "#{label} settings changed since they were read. Nothing was written.")
      end

      after = validate!(values)
      proposal.add_step(step(before, after), :scopes => [scope]) unless before == after
      after
    rescue StandardError => error
      proposal.refuse(error)
      raise
    end

    def scope
      Scope.new(self)
    end

    def step(before, after)
      Step.new(self, before, after)
    end

    private

    def problems(values)
      found = JsonSchema.validate(values, schema)
      found.empty? ? Array(@problems&.call(values)) : found
    end

    # Defaults are a read projection, never the stored pre-image: absent data must remain absent
    # when the host aborts or undoes a write, rather than becoming an authored defaults dictionary.
    class Scope
      def initialize(settings)
        @settings = settings
      end

      def path
        [@settings.store.dictionary]
      end

      def capture(model)
        CanonicalJson.digest(@settings.store.read(model))
      end

      def unchanged?(model, before)
        capture(model) == before
      rescue StandardError
        false
      end
    end

    class Step
      def initialize(settings, before, after)
        @settings = settings
        @before = DeepCopy.call(before)
        @after = DeepCopy.call(after)
      end

      def descriptor
        { "name" => @settings.step_name, "before" => @before, "after" => @after }
      end

      def affected
        DeepCopy.call(@settings.affected)
      end

      def apply(model, _slots)
        unless @settings.read(model) == @before
          raise CodedError.new("target.changed",
                               "#{@settings.label} settings changed after preview. Nothing was written.")
        end
        @settings.store.write(model, @after)
      end
    end
  end
end
