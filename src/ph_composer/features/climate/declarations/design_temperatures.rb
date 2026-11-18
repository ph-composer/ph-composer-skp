# frozen_string_literal: true

module PhComposer
  module Climate
    # The design temperatures' read, also the snapshot section the Climate tab paints from, and their update,
    # which sets any of the three fields as one native Undo step so each typed value saves on its own.
    module DesignTemperaturesRegistration
      PREFIX = "#{FEATURE_ID}.design_temperatures".freeze
      FIELDS = Settings::DESIGN_DEFAULTS.keys.freeze
      PARTIAL = Shapes.object(Settings::DESIGN_VALUES.fetch("properties"), :optional => FIELDS)

      module_function

      def install(feature)
        feature.query("#{PREFIX}.get",
                      :description => "The ASHRAE 99% heating and 1% cooling dry bulbs, the source note, the " \
                                      "state and the warning. A new Model reads not_set and nothing is written.",
                      :refuses => %w[record.unreadable], :params => Shapes::NONE,
                      :result => Shapes::DESIGN_TEMPERATURES,
                      :examples => [{}]) { |request| Settings.design_temperatures(request.model) }
        feature.snapshot_section(PREFIX, :query => "#{PREFIX}.get")
        feature.action("#{PREFIX}.update",
                       :description => "Set any of the two design temperatures and the source note; null unsets " \
                                       "one. Each field given is guarded by its value in expected_values, which " \
                                       "names the same fields; fields not given keep what is stored.",
                       :refuses => %w[record.unreadable target.changed validation.failed],
                       :params => Shapes.object({
                         "values" => Shapes.described(PARTIAL, "The fields to set."),
                         "expected_values" => Shapes.described(
                           PARTIAL, "The same fields as last read; a change refuses."
                         )
                       }),
                       :result => Shapes::DESIGN_TEMPERATURES, :undo_name => "Change Design Temperature",
                       :side_effects => "Stores the design temperatures in this SKP.",
                       :examples => [{ "values" => { "heating_99_c" => -12.2 },
                                       "expected_values" => { "heating_99_c" => nil } }]) do |request, proposal|
          Settings.propose_design_temperatures(request, proposal,
                                               :values => request.params.fetch("values"),
                                               :expected_values => request.params.fetch("expected_values"))
        end
      end
    end
  end
end
