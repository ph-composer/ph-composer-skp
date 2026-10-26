# frozen_string_literal: true

module PhComposer
  module Windows
    # Reads every Windows definition kind shares: products, Window Types, and the
    # Window Unit repairs that create Types.
    module Definitions
      module_function

      def records(request, kind)
        request.engine.ids(kind.id).map { |id| request.engine.find(kind.id, id) }
      end
    end
  end
end
