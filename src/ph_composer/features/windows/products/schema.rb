# frozen_string_literal: true

module PhComposer
  module Windows
    FEATURE_ID = "ph_composer.windows"
    FRAME_KIND = "#{FEATURE_ID}.frame"
    GLAZING_KIND = "#{FEATURE_ID}.glazing"
    PSI_INSTALL_KIND = "#{FEATURE_ID}.psi_install_type"
    TYPE_KIND = "#{FEATURE_ID}.window_type"
    Fields = Records::AuthoringFields

    # Products are model-owned definitions. Signed junction values and zero U-values are authored
    # exactly; missing values remain absent or null until the user supplies them.
    module Products
      module_function

      def text(key)
        Fields.field(key, { "type" => "string" })
      end

      # A missing value stays null until the user supplies it; `minimum` is inclusive, so a zero
      # U-value is authored exactly, and a signed value has none.
      def number(key, unit, minimum: nil, maximum: nil)
        schema = { "type" => %w[number null], "x-unit" => unit }
        schema["minimum"] = minimum unless minimum.nil?
        schema["maximum"] = maximum unless maximum.nil?
        Fields.field(key, schema)
      end

      def color
        Fields.field("color", { "type" => "string" })
      end

      # One product kind: the shared authoring fields, then `own_fields`.
      def kind(id:, label:, prefix:, own_fields:)
        authored = Fields.with_source_snapshot(Fields.common + own_fields)
        snapshot_schema = Fields.source_snapshot_schema(authored)
        Records::RecordKind.new(
          :id => id, :label => label, :schema_version => 1, :id_prefix => prefix, :fields => authored,
          :validate => lambda do |values|
            Fields.problems(values) + Fields.source_problems(values["source"], snapshot_schema)
          end
        )
      end

      # Each product kind's fields after the shared ones, by its collection name.
      OWN_FIELDS = {
        "frames" => [text("manufacturer"), text("brand"), text("product_code"), text("position"), text("operation"),
                     number("width_m", "m", :minimum => 0), number("uf_w_m2k", "W/m2K", :minimum => 0),
                     number("psi_g_w_mk", "W/mK"), color],
        "glazings" => [text("manufacturer"), text("product_code"), text("description"),
                       number("ug_w_m2k", "W/m2K", :minimum => 0),
                       number("g_value", "fraction", :minimum => 0, :maximum => 1), color],
        "psi_install_types" => [number("psi_w_mk", "W/mK")]
      }.freeze

      KINDS = {
        "frames" => kind(:id => FRAME_KIND, :label => "Frame", :prefix => "frm",
                         :own_fields => OWN_FIELDS.fetch("frames")),
        "glazings" => kind(:id => GLAZING_KIND, :label => "Glazing", :prefix => "glz",
                           :own_fields => OWN_FIELDS.fetch("glazings")),
        "psi_install_types" => kind(:id => PSI_INSTALL_KIND, :label => "Psi-Install Type", :prefix => "psi",
                                    :own_fields => OWN_FIELDS.fetch("psi_install_types"))
      }.freeze

      # The collection's numeric fields: thermal inputs a replacement must also carry.
      def number_keys(collection)
        OWN_FIELDS.fetch(collection).reject { |field| field.schema.fetch("type") == "string" }.map(&:key)
      end

      # Authored text starts empty and color white; numbers stay absent.
      def defaults(collection, values)
        result = OWN_FIELDS.fetch(collection).each_with_object({}) do |field, row|
          next unless field.schema.fetch("type") == "string"

          row[field.key] = field.key == "color" ? "#ffffff" : ""
        end
        result.merge(Fields.defaults(values))
      end
    end
  end
end
