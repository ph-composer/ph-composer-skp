# frozen_string_literal: true

module PhComposer
  module Climate
    # The codes Climate reports under its own noun, published in docs/API_REFERENCE.md: refusals of the
    # climate's writes and of the climate data folder commands, and a warning the design-temperature read carries.
    module Codes
      ALL = {
        Settings::CROSSED => "The heating design temperature is at or above the cooling one; both still save.",
        Operations::NOT_FOUND => "The Model holds no climate to edit, restore or clear. Nothing was written.",
        Operations::NO_ORIGINAL => "A climate entered by hand has no station values to restore. Nothing was " \
                                   "written.",
        Folders::Store::UNREADABLE => "This computer's climate data settings cannot be read, or a later version of " \
                                      "PH-Composer wrote them. They are left as stored; reads report it and changes " \
                                      "refuse.",
        Folders::Store::UNAVAILABLE => "This computer's settings file cannot be used: it is kept on macOS only for " \
                                       "now, or it could not be saved. Nothing was written.",
        Folders::Operations::NOT_FOUND => "No climate data folder has that id, or the chosen folder is not there. " \
                                          "Nothing was written.",
        Folders::Operations::OVERLAPS => "The chosen folder is, holds or sits inside a listed climate data folder, " \
                                         "so its stations would be listed twice. Nothing was written."
      }.freeze

      module_function

      def install(feature)
        ALL.each { |code, description| feature.code(code, :description => description) }
      end
    end
  end
end
