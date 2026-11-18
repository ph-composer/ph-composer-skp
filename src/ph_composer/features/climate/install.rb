# frozen_string_literal: true

# One feature owns a Model's climate. Today that is the site location and the design temperatures, as
# Model settings, and the climate itself, one record with the Phius limit check against the site; the climate
# data folders, the station reader, the Climate tab and the Site export section join it later. It requires
# Zones, which that export section builds on; no Zones file names it. Climate is not a Library kind and
# registers no library provider.
#
#   site/           the climate-zone codes and their labels
#   settings.rb     the site and the design temperatures: two settings dictionaries and their derived states
#   climate/        the climate record: its schema, the pure rules (completeness, edits, the limit check), the
#                   builder that rewrites its provenance, and its operations
#   codes.rb        the codes under the climate noun
#   declarations/   what Climate registers: the site, the design temperatures, the climate and the summary
module PhComposer
  module Climate
    FEATURE_ID = "ph_composer.climate"
  end
end

require_relative "site/climate_zones"
require_relative "settings"
require_relative "climate/schema"
require_relative "climate/completeness"
require_relative "climate/edits"
require_relative "climate/limit_check"
require_relative "climate/record"
require_relative "climate/operations"
require_relative "declarations/shapes"
require_relative "declarations/site"
require_relative "declarations/design_temperatures"
require_relative "declarations/climate"
require_relative "declarations/summary"
require_relative "codes"

module PhComposer
  module Climate
    module_function

    def install(registry)
      feature = registry.feature(FEATURE_ID, :contract_version => 1, :requires => ["ph_composer.zones"])
      SiteRegistration.install(feature)
      DesignTemperaturesRegistration.install(feature)
      ClimateRegistration.install(feature)
      SummaryRegistration.install(feature)
      Codes.install(feature)
    end
  end
end
