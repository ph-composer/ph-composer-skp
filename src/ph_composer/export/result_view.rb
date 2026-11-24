# frozen_string_literal: true

module PhComposer
  module Export
    # What one contributor's report reads of the translator's result document: its own section's
    # fields by name, and another section's fields only when the contributor declared it in `requires:`
    # (Declarations::ExportContributor). Registration checks that each declared section belongs to a
    # feature the contributor's feature requires, so a report never reads up a layer.
    class ResultView
      def initialize(result, contributor)
        @result = result
        @contributor = contributor
      end

      # One of this contributor's own fields, as Hash#fetch: `default` when its translation did not add
      # it, KeyError without one.
      def fetch(field, *default)
        own.fetch(field, *default)
      end

      # The fields another section's translation added, `{}` when it added none. Reading a section the
      # contributor did not declare is a defect in the contributor, not in the Model.
      def section(name)
        unless Array(@contributor.requires).include?(name)
          raise InternalError, "#{@contributor.name} reads #{name} without declaring it in requires."
        end

        @result.fetch(name, {})
      end

      # The findings the run reported against this contributor's section, its notes among them, as the result
      # lists them.
      def findings
        @result.fetch("findings", []).select { |finding| finding["section"] == @contributor.name }
      end

      private

      def own
        @result.fetch(@contributor.name, {})
      end
    end
  end
end
