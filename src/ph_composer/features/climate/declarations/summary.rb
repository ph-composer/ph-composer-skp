# frozen_string_literal: true

module PhComposer
  module Climate
    # The Climate tab's sidebar cards: each card's state in one snapshot section, so the panel follows a
    # change without reading every value.
    module SummaryRegistration
      NAME = "#{FEATURE_ID}.summary".freeze
      CARD = Shapes.object({ "state" => Shapes::DESIGN_STATE, "warning" => Shapes::WARNING }).freeze
      RESULT = Shapes.object({ "site" => Shapes::SITE_STATE, "design_temperatures" => CARD }).freeze

      module_function

      def install(feature)
        feature.query("#{NAME}.get", :description => "The state of the site and design-temperature cards.",
                                     :refuses => %w[record.unreadable], :params => Shapes::NONE, :result => RESULT,
                                     :examples => [{}]) { |request| read(request.model) }
        feature.snapshot_section(NAME, :query => "#{NAME}.get")
      end

      def read(model)
        design = Settings.design_temperatures(model)
        { "site" => Settings.site(model).fetch("state"),
          "design_temperatures" => { "state" => design.fetch("state"), "warning" => design.fetch("warning") } }
      end
    end
  end
end
