# frozen_string_literal: true

module PhComposer
  module Climate
    # The codes Climate reports under its own noun, published in docs/API_REFERENCE.md. Its operations refuse
    # only with foundation codes so far; this one is a warning a read carries.
    module Codes
      ALL = {
        Settings::CROSSED => "The heating design temperature is at or above the cooling one; both still save."
      }.freeze

      module_function

      def install(feature)
        ALL.each { |code, description| feature.code(code, :description => description) }
      end
    end
  end
end
