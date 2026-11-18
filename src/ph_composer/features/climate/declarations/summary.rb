# frozen_string_literal: true

module PhComposer
  module Climate
    # The Climate tab's sidebar cards: each card's state in one snapshot section, so the panel follows a
    # change without reading every value.
    module SummaryRegistration
      NAME = "#{FEATURE_ID}.summary".freeze
      CARD = Shapes.object({ "state" => Shapes::DESIGN_STATE, "warning" => Shapes::WARNING }).freeze
      CLIMATE_CARD = Shapes.object({
        "state" => { "type" => "string", "enum" => %w[none incomplete complete] },
        "origin" => { "type" => %w[string null], "enum" => ["station", "hand", nil],
                      "description" => "Where the climate came from; null with none." },
        "verdict" => Shapes::VERDICT.merge("type" => %w[string null], "enum" => Shapes::VERDICT.fetch("enum") + [nil]),
        "edited" => { "type" => "boolean", "description" => "true when a value differs from the station file." }
      }).freeze
      RESULT = Shapes.object({ "site" => Shapes::SITE_STATE, "design_temperatures" => CARD,
                               "climate" => CLIMATE_CARD }).freeze

      module_function

      def install(feature)
        feature.query("#{NAME}.get", :description => "The state of the site, design-temperature and climate cards.",
                                     :refuses => %w[record.unreadable], :params => Shapes::NONE, :result => RESULT,
                                     :examples => [{}]) { |request| read(request) }
        feature.snapshot_section(NAME, :query => "#{NAME}.get")
      end

      def read(request)
        model = request.model
        design = Settings.design_temperatures(model)
        site = Settings.site(model)
        { "site" => site.fetch("state"),
          "design_temperatures" => { "state" => design.fetch("state"), "warning" => design.fetch("warning") },
          "climate" => Operations.card(request.engine, site) }
      end
    end
  end
end
