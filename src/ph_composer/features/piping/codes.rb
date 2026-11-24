# frozen_string_literal: true

module PhComposer
  module Piping
    # The codes the `piping` noun owns (context/CONTRACTS.md, "Outcomes and codes"), published in
    # docs/API_REFERENCE.md.
    module Codes
      INSULATION_CONDUCTIVITY_MISSING = "piping.insulation_conductivity_missing"

      DESCRIPTIONS = {
        INSULATION_CONDUCTIVITY_MISSING => "A Pipe Type has insulation and no insulation conductivity, so a pipe " \
                                           "using it cannot export."
      }.freeze

      module_function

      def install(feature)
        DESCRIPTIONS.each { |code, description| feature.code(code, :description => description) }
      end
    end
  end
end
