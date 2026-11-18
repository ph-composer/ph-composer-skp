# frozen_string_literal: true

module PhComposer
  module Climate
    # The climate record's kind, its read and the four writes, each one native Undo step guarded by the
    # editable fields last read. Entering a climate and editing one are separate actions so that each carries
    # its own Undo name.
    module ClimateRegistration
      PREFIX = "#{FEATURE_ID}.climate".freeze
      PROPERTIES = Schema::KIND.values_schema.fetch("properties")
      EDITABLE = Shapes.object(PROPERTIES.slice(*Schema::EDITABLE)).freeze
      VALUES = Shapes.described(EDITABLE, "Every editable field: the name and the station elevation are needed, " \
                                          "any other value may be null.").freeze
      EXPECTED = Shapes.described(EDITABLE, "The editable fields as climate.get last returned them under " \
                                            "climate.values; a change refuses.").freeze
      MISSING_ROW = Shapes.object({
        "row" => Schema::CELL.fetch("properties").fetch("row"),
        "columns" => Shapes.list({ "type" => "string", "enum" => Schema::MONTHS + Schema::CASES },
                                 :description => "The months or cases missing; empty for a single value.")
      }).freeze
      CLIMATE = Shapes.object({ "id" => Shapes::ID, "values" => Schema::KIND.values_schema },
                              :description => "The record's values. Its user_data, which has no size bound, is " \
                                              "read with ph_composer.records.detail.").freeze
      # What a write answers; climate.get adds the record under climate.
      WRITTEN = Shapes.object({
        "state" => { "type" => "string", "enum" => %w[none incomplete complete],
                     "description" => "none with no climate; incomplete while missing lists a gap." },
        "missing" => Shapes.list(MISSING_ROW, :description => "What a complete climate still needs, by row, in " \
                                                              "grid order."),
        "edited_cells" => Shapes.list(Schema::CELL, :description => "Each value that differs from the " \
                                                                    "station file; none for a climate " \
                                                                    "entered by hand. Wind speed is never " \
                                                                    "one."),
        "limit_check" => Shapes::LIMIT_CHECK_OR_NULL
      }).freeze
      RESULT = Shapes.with(WRITTEN, "climate" => CLIMATE.merge("type" => %w[object null])).freeze
      REFUSES = %w[record.unreadable target.changed validation.failed].freeze
      EXAMPLE = {
        "name" => "Typed climate", "station_latitude_deg" => nil, "station_longitude_deg" => nil,
        "station_elevation_m" => 10.0, "daily_temp_swing_k" => nil, "wind_speed_m_s" => nil,
        "monthly" => Schema.empty_monthly, "peak_loads" => Schema.empty_peak_loads
      }.freeze

      module_function

      def install(feature)
        feature.record_kind(Schema::KIND)
        feature.query("#{PREFIX}.get",
                      :description => "The Model's climate with its state, what is missing, the edited cells and " \
                                      "the Phius limit check against the site. State none when there is none.",
                      :refuses => %w[record.unreadable], :params => Shapes::NONE, :result => RESULT,
                      :examples => [{}]) { |request| Operations.read(request) }
        install_entry(feature)
        install_restore_and_clear(feature)
      end

      def install_entry(feature)
        feature.action("#{PREFIX}.enter_values",
                       :description => "Enter a climate by hand: a name and the station elevation are needed, " \
                                       "every other value may stay null and the climate reads incomplete. " \
                                       "Station coordinates are optional and go together. Refuses when the " \
                                       "Model already holds a climate.",
                       :refuses => REFUSES, :params => Shapes.object({ "values" => VALUES }), :result => WRITTEN,
                       :undo_name => "Enter Climate Values", :side_effects => "Stores the climate in this SKP.",
                       :examples => [{ "values" => EXAMPLE }]) do |request, proposal|
          Operations.enter_values(request, proposal, :values => request.params.fetch("values"))
        end
        feature.action("#{PREFIX}.save_values",
                       :description => "Edit the values of the Model's climate. A station's name and coordinates " \
                                       "stay as its file gave them; a value that differs from the file is an " \
                                       "edit, and the provenance's source type and edited values change with it.",
                       :refuses => REFUSES + [Operations::NOT_FOUND],
                       :params => Shapes.object({ "values" => VALUES, "expected_values" => EXPECTED }),
                       :result => WRITTEN, :undo_name => "Edit Climate Values",
                       :side_effects => "Stores the climate in this SKP.",
                       :examples => [{ "values" => EXAMPLE.merge("daily_temp_swing_k" => 11.5),
                                       "expected_values" => EXAMPLE }]) do |request, proposal|
          Operations.save_values(request, proposal, :values => request.params.fetch("values"),
                                                    :expected_values => request.params.fetch("expected_values"))
        end
      end

      def install_restore_and_clear(feature)
        guarded = Shapes.object({ "expected_values" => EXPECTED })
        feature.action("#{PREFIX}.restore_original",
                       :description => "Copy the values the station file read back over every edit. Refuses " \
                                       "climate.no_original for a climate entered by hand.",
                       :refuses => REFUSES + [Operations::NOT_FOUND, Operations::NO_ORIGINAL], :params => guarded,
                       :result => WRITTEN, :undo_name => "Restore Climate Values",
                       :side_effects => "Stores the climate in this SKP.",
                       :examples => [{ "expected_values" => EXAMPLE }]) do |request, proposal|
          Operations.restore_original(request, proposal, :expected_values => request.params.fetch("expected_values"))
        end
        feature.action("#{PREFIX}.clear",
                       :description => "Delete the Model's climate. The site and the design temperatures stay.",
                       :refuses => REFUSES + [Operations::NOT_FOUND], :params => guarded,
                       :result => SchemaShapes.with_removed_user_data(WRITTEN), :undo_name => "Clear Climate",
                       :side_effects => "Removes the climate from this SKP.",
                       :examples => [{ "expected_values" => EXAMPLE }]) do |request, proposal|
          Operations.clear(request, proposal, :expected_values => request.params.fetch("expected_values"))
        end
      end
    end
  end
end
