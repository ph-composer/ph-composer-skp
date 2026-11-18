# frozen_string_literal: true

module PhComposer
  module Climate
    # The codes Climate reports under its own noun, published in docs/API_REFERENCE.md: refusals of the
    # climate's writes, the climate data folder commands and the station reads and writes, a warning the
    # design-temperature read carries, and the Site export section's findings.
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
                                         "so its stations would be listed twice. Nothing was written.",
        Stations::Operations::SITE_NOT_SET => "The site's latitude, longitude and elevation are not set. The " \
                                              "station list and attach refuse, reading and writing nothing; " \
                                              "export leaves a climate out of the HBJSON with this finding.",
        Stations::Operations::STATION_NOT_FOUND => "No station file with that key is in the climate data folder " \
                                                   "now, or it could not be opened. Nothing was written.",
        Stations::Operations::UNREADABLE => "The station file is not a Phius station file this version reads; the " \
                                            "message names the row. Nothing was written."
      }.merge(SiteRecord::CODES).freeze

      module_function

      def install(feature)
        ALL.each { |code, description| feature.code(code, :description => description) }
      end
    end
  end
end
