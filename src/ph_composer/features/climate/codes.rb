# frozen_string_literal: true

module PhComposer
  module Climate
    # The codes Climate reports under its own noun, published in docs/API_REFERENCE.md: two refusals of the
    # climate's writes, and a warning the design-temperature read carries.
    module Codes
      ALL = {
        Settings::CROSSED => "The heating design temperature is at or above the cooling one; both still save.",
        Operations::NOT_FOUND => "The Model holds no climate to edit, restore or clear. Nothing was written.",
        Operations::NO_ORIGINAL => "A climate entered by hand has no station values to restore. Nothing was " \
                                   "written."
      }.freeze

      module_function

      def install(feature)
        ALL.each { |code, description| feature.code(code, :description => description) }
      end
    end
  end
end
