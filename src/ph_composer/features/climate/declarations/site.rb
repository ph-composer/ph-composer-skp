# frozen_string_literal: true

module PhComposer
  module Climate
    # The site's read, Set Location, which writes its five fields together as one native Undo step and answers
    # the limit check the Model's climate gets after the change, and the preview of that check at a proposed
    # site, which Set Location shows before it is set.
    module SiteRegistration
      PREFIX = "#{FEATURE_ID}.site".freeze
      EXAMPLE = { "latitude_deg" => 40.6782, "longitude_deg" => -73.9442, "elevation_m" => 10.0,
                  "climate_zone" => 14, "hours_from_utc" => -5 }.freeze

      module_function

      def install(feature)
        feature.query("#{PREFIX}.get",
                      :description => "The Model's site: latitude, longitude, elevation, climate zone and hours " \
                                      "from UTC, with the site state. A new Model reads not_set and nothing is " \
                                      "written.",
                      :refuses => %w[record.unreadable], :params => Shapes::NONE, :result => Shapes::SITE,
                      :examples => [{}]) { |request| Settings.site(request.model) }
        feature.action("#{PREFIX}.update",
                       :description => "Set the five site fields together, guarded by the five last read. " \
                                       "Latitude, longitude and elevation are all given or all null; climate zone " \
                                       "and hours from UTC may be null with the site set.",
                       :refuses => %w[record.unreadable target.changed validation.failed],
                       :params => Shapes.object({
                         "values" => Shapes.described(Settings::SITE_VALUES, "The five new site fields."),
                         "expected_values" => Shapes.described(Settings::SITE_VALUES,
                                                               "The five site fields last read; a change refuses.")
                       }),
                       :result => Shapes::SITE_UPDATE, :undo_name => "Set Site Location",
                       :side_effects => "Stores the site in this SKP.",
                       :examples => [{ "values" => EXAMPLE,
                                       "expected_values" => Settings::SITE_DEFAULTS }]) do |request, proposal|
          site = Settings.propose_site(request, proposal, :values => request.params.fetch("values"),
                                                          :expected_values => request.params.fetch("expected_values"))
          site.merge("limit_check" => Operations.limit_check(request.engine, site))
        end
        feature.query("#{PREFIX}.preview_limit_check",
                      :description => "The Phius limit check the Model's climate would get at a proposed latitude, " \
                                      "longitude and elevation; null with no climate. Nothing is written.",
                      :refuses => %w[record.unreadable], :params => Shapes::PROPOSED_SITE,
                      :result => Shapes.object({ "limit_check" => Shapes::LIMIT_CHECK_OR_NULL }),
                      :examples => [EXAMPLE.slice(*Settings::LOCATION_FIELDS)]) do |request|
          { "limit_check" => Operations.limit_check(request.engine, request.params) }
        end
      end
    end
  end
end
