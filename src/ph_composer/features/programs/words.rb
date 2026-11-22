# frozen_string_literal: true

module PhComposer
  module Programs
    # How the Programs findings name a record the user named.
    module Words
      module_function

      # The possessive of a user's name: "House's", and "Apartments'" for a name that ends in s.
      def possessive(name)
        text = name.to_s
        text.end_with?("s", "S") ? "#{text}'" : "#{text}'s"
      end
    end
  end
end
