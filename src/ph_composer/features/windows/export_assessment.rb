# frozen_string_literal: true

require_relative "export_geometry"
require_relative "codes"
require_relative "placement/host"

module PhComposer
  module Windows
    # Assessment is detached and read-only. Every authored Unit is accounted for, including invalid
    # and unhosted Units. Blocking rows never become partial apertures or zero thermal placeholders.
    # `ExportAssessment.call` is the entry point; an instance is the working state of one call.
    class ExportAssessment
      # Aperture and construction rows for the translation, the preflight findings, the batch repairs the
      # preflight offers, and each Unit's world outline that could be placed, as `{unit_id, entity_path,
      # outline_m}` rows.
      Result = Struct.new(:apertures, :constructions, :findings, :repairs, :outlines, keyword_init: true)
      # The pinned Honeybee simple glazing material accepts a Uw above zero and up to this value.
      UW_LIMIT_W_M2K = 12
      # The one thermal condition that is reported without blocking export.
      ADVISORY_CONDITIONS = %w[window_type.frame_operation_mismatch].freeze

      # Assesses every Window Unit in a captured `snapshot` against the authored Types, product
      # collections and settings, placing each on its host from the Zones Faces section's `faces` rows.
      def self.call(snapshot:, types:, products:, settings:, faces:)
        new(snapshot, types, products, settings, faces).run
      end

      def initialize(snapshot, types, products, settings, faces)
        @snapshot, @types, @products, @settings = snapshot, types, products, settings
        @faces = faces.to_h { |face| [face.fetch("path"), face] }
        @apertures, @constructions, @findings, @repairs = [], [], [], []
        @units = unit_records
        @ids = @units.group_by { |_entry, record| record["id"] }
        @plans = {}
        @outlines = {}
      end
      private_class_method :new

      def run
        prepare_outlines
        @units.each { |entry, record| assess_unit(entry, record) }
        # Elements with the same thermal inputs share one construction row.
        constructions = @constructions.uniq { |row| row.fetch("id") }
        Result.new(:apertures => @apertures.sort_by { |row| row.fetch("id") },
                   :constructions => constructions.sort_by { |row| row.fetch("id") },
                   :findings => @findings, :repairs => @repairs, :outlines => outline_rows).freeze
      end

      private

      def outline_rows
        @units.filter_map do |entry, record|
          mapped = @outlines[entry.path]
          mapped && { "unit_id" => record["id"], "entity_path" => entry.path, "outline_m" => mapped.outer_polygon_m }
        end
      end

      def unit_records
        @snapshot.entries.filter_map do |entry|
          dictionary = entry.dictionaries[Units::STORE.dictionary]
          next unless dictionary && dictionary.key?(Units::STORE.key)

          [entry, ExportGeometry.record(entry.dictionaries, Units::STORE)]
        end
      end

      def prepare_outlines
        @units.each do |entry, record|
          type = @types[record["window_type_id"]]
          next unless type

          plan = @plans[type["id"]] ||= Units::DefinitionPlan.build(type)
          @outlines[entry.path] = Units::WorldGeometry.map(plan, entry.transform)
        rescue CodedError
          # The per-Unit assessment below names incomplete dimensions or invalid native transforms.
          next
        end
      end

      def assess_unit(entry, record)
        start = @findings.length
        reference = { "unit_id" => record["id"], "entity_path" => entry.path }
        validate_record(entry, record, reference)
        type = @types[record["window_type_id"]]
        unless type
          issue("window.unknown_type", "The Unit's Window Type is unavailable. Choose a known Type.", record, reference)
          return
        end
        plan = @plans[type["id"]]
        unless plan
          issue("window_type.dimensions_incomplete", "Complete the placed Window Type's finite positive dimensions.",
                record, reference)
          return
        end
        definition = entry.native && entry.native["definition"]
        unless definition
          issue("window.not_component", "A Window Unit must be a native ComponentInstance.", record, reference)
          return
        end
        validate_definition(definition, type, plan, record, reference)
        validate_transform(entry, record, reference)
        face = host(entry)
        validate_host(entry, face, record, reference)
        thermal = Thermal.calculate(type, @products, @settings["default_psi_install_id"])
        validate_product_availability(type, thermal, record, reference)
        report_thermal_conditions(type, thermal, record, reference)
        validate_uw_limit(thermal, record, reference)
        return if @findings.drop(start).any? { |finding| finding["blocks_export"] }

        emit(entry, record, type, face, thermal)
      rescue CodedError => error
        issue(error.code, error.message, record, reference)
      ensure
        add_repairs(@findings.drop(start), reference)
      end

      # The batch repairs the preflight offers for one Unit, under the same rules as its read.
      def add_repairs(findings, reference)
        return unless reference["unit_id"].is_a?(String)

        codes = findings.map { |finding| finding.fetch("code") }
        codes.uniq.each do |code|
          action = Units::State::REPAIRS[code]
          next unless %w[reset_to_type new_flipped_type].include?(action)

          repair = Units::State.repair(code, reference, codes)
          next unless repair

          @repairs << { "id" => "#{code}:#{reference['entity_path'].join('.')}",
                        "label" => action == "reset_to_type" ? "Reset to Type" : "New flipped Type", "checked" => false,
                        "action" => repair.fetch("name"), "params" => repair.fetch("params") }
        end
      end

      def validate_record(entry, record, reference)
        Units.validate!(record)
        issue("window.copy_id_pending", "Copied Units share an identity; resolve their identities before export.",
              record, reference) if @ids.fetch(record["id"]).length > 1
        if @units.any? { |other, _| other != entry && @snapshot.contains?(other, entry) }
          issue("window.nested_units", "A Window Unit is nested inside another Unit.", record, reference)
        end
      end

      def index
        @index ||= begin
          stored = ExportGeometry.record(@snapshot.model_dictionaries, Units::DefinitionIndex::STORE)
          if stored && !Units::DefinitionIndex.valid?(stored)
            raise Export::Blocked.new("record.unreadable", "The Window definition index is invalid.")
          end

          stored ? stored.fetch("definitions") : {}
        end
      end

      def validate_definition(definition, type, plan, record, reference)
        if index[type["id"]] != definition["id"]
          issue("window.definition_detached", "The Unit does not use its Type's primary definition. Reset to Type.",
                record, reference)
        end
        unless definition["cuts_opening"] && definition["is2d"] &&
               Units::DefinitionGeometry.facts_match?(definition, :type_id => type["id"], :plan => plan)
          issue("window.geometry_differs", "The Unit's generated geometry or cutting behavior differs from its Type.",
                record, reference)
        end
      end

      def validate_transform(entry, record, reference)
        state = Units::WorldGeometry.transform_state(entry.transform)
        if state.scaled
          issue("window.scaled", "The Unit has native in-plane scaling. Reset to Type.", record, reference)
        end
        if state.sheared
          issue("window.sheared", "The Unit has native in-plane shear. Reset to Type.", record, reference)
        end
        issue("window.mirrored", "The Unit is mirrored. Make a new flipped Type.", record, reference) if state.mirrored
      end

      def host(entry)
        id = entry.native && entry.native["glued_to_id"]
        id && @faces[entry.path[0...-1] + [id]]
      end

      def validate_host(entry, face, record, reference)
        unless face
          issue("window.unhosted", "The Unit has no resolvable native glued host Face. Rehost it before export.",
                record, reference)
          return
        end
        Placement::Hosts.conditions(face["record"] || {}, :zoned => !face["zone_id"].nil?).each do |code|
          issue(code, Codes::ALL.fetch(code), record, reference)
        end
        mapped = @outlines[entry.path]
        return unless mapped

        others = @outlines.reject { |path, _| path == entry.path }.values.map(&:outer_polygon_m)
        Placement::Fit.check!(face.fetch("geometry"), mapped.outer_polygon_m, :existing_polygons_m => others)
      rescue CodedError => error
        issue(error.code, error.message, record, reference)
      end

      # One finding per non-empty element naming a product the Model does not hold, counting the
      # Psi-Install the calculation resolved for each edge as well as the authored slots.
      def validate_product_availability(type, thermal, record, reference)
        type.fetch("elements").reject { |cell| cell["kind"] == "empty" }.each do |cell|
          slots = Snapshot.product_slots(cell).map { |collection, _side, id| [collection, id] }
          detail = thermal.fetch("elements").find { |row| row["id"] == cell["id"] }
          if detail
            slots += detail.fetch("edges").map { |edge| ["psi_install_types", edge.fetch("install")["id"]] }
          end
          next unless slots.any? { |collection, id| id && !@products.fetch(collection).key?(id) }

          issue("window_type.product_dangling",
                "A placed Type names an unavailable Frame, Glazing or Psi-Install Type.",
                record, reference)
        end
      end

      # The Type's and its elements' thermal conditions as export findings. Each message says where the
      # condition is, Type and element, so two elements with one condition are two findings; identical
      # findings collapse to one. Only ADVISORY_CONDITIONS leave export open.
      def report_thermal_conditions(type, thermal, record, reference)
        conditions = thermal.fetch("findings").map do |finding|
          message = finding.fetch("message")
          [finding.fetch("code"), type["name"] ? "#{type['name']}: #{message}" : message]
        end
        thermal.fetch("elements").each do |detail|
          element_name = type.fetch("elements").find { |cell| cell["id"] == detail["id"] }&.fetch("name", nil)
          where = [type["name"], element_name].compact.join(", ")
          detail.fetch("findings").each do |finding|
            message = finding.fetch("message")
            conditions << [finding.fetch("code"), where.empty? ? message : "#{where}: #{message}"]
          end
        end
        conditions.uniq.each do |code, message|
          issue(code, message, record, reference, :blocking => !ADVISORY_CONDITIONS.include?(code))
        end
      end

      # The exporter's limit, not an authoring rule: a computed Uw the pinned simple glazing material
      # cannot carry blocks export and leaves the authored values alone.
      def validate_uw_limit(thermal, record, reference)
        thermal.fetch("elements").each do |element|
          u_w = element["uw_w_m2k"]
          next if u_w.nil? || (u_w.finite? && u_w.positive? && u_w <= UW_LIMIT_W_M2K)

          issue("window_type.construction_unavailable",
                "The placed element's Uw must be greater than zero and no more than " \
                "#{UW_LIMIT_W_M2K} W/m2K for the pinned Honeybee simple glazing material. Authored values " \
                "remain unchanged.",
                record, reference)
        end
      end

      def emit(entry, record, type, face, thermal)
        mapped = @outlines.fetch(entry.path)
        thermal.fetch("elements").each do |detail|
          cell = type.fetch("elements").find { |item| item["id"] == detail["id"] }
          construction = construction(cell, detail)
          @constructions << construction
          polygon = mapped.panes.find { |pane| pane.element_id == cell["id"] }.polygon_m
          polygon = polygon.reverse if opposite?(polygon, face.fetch("geometry").normal)
          @apertures << { "id" => "wap_#{CanonicalJson.digest([record['id'], cell['id']])}",
                          "unit_id" => record["id"], "type_id" => type["id"], "element_id" => cell["id"],
                          "name" => "#{type.fetch('name')} / #{cell.fetch('name')}",
                          "host_face_id" => face.fetch("record").fetch("id"),
                          "zone_id" => face.fetch("zone_id"), "construction_id" => construction["id"],
                          "polygon_m" => polygon,
                          "variant_type" => type.fetch("name"),
                          "install_depth_m" => type.fetch("install_depth_m",
                                                          @settings.fetch("default_install_depth_m")),
                          "is_operable" => cell.fetch("operation").fetch("type") != "fixed" }
                        .merge(record.fetch("user_data", {}).empty? ? {} : { "user_data" => record["user_data"] })
        end
      end

      def construction(cell, detail)
        glazing = @products.fetch("glazings").fetch(cell.fetch("glazing_id"))
        sides = Types::SIDES.to_h do |side|
          frame = @products.fetch("frames").fetch(cell.fetch("frames").fetch(side))
          edge = detail.fetch("edges").find { |item| item["side"] == side }
          [side, { "frame" => frame.slice("id", "name", "width_m", "uf_w_m2k", "psi_g_w_mk"),
                   "install_id" => edge.fetch("install")["id"],
                   "install_name" => @products.fetch("psi_install_types")[edge.fetch("install")["id"]]&.fetch("name"),
                   "psi_install_w_mk" => edge.fetch("install").fetch("psi_w_mk") }]
        end
        row = { "name" => glazing.fetch("name"), "uw_w_m2k" => detail.fetch("uw_w_m2k"),
                "glazing" => glazing.slice("id", "name", "ug_w_m2k", "g_value"), "sides" => sides }
        # The id digests everything except display names, so renaming a product never renames a construction.
        signature = row.reject { |key, _| key == "name" }.merge(
          "glazing" => row.fetch("glazing").reject { |key, _| key == "name" },
          "sides" => sides.transform_values { |side|
                       side.reject { |k, _| k == "install_name" }.merge(
                         "frame" => side.fetch("frame").reject { |k, _| k == "name" }
                       )
                     }
        )
        row.merge("id" => "wwc_#{CanonicalJson.digest(signature)}")
      end

      # Whether the pane polygon winds against the host Face's normal.
      def opposite?(polygon, normal)
        a = polygon[1].zip(polygon[0]).map { |b, x| b - x }
        b = polygon[2].zip(polygon[0]).map { |c, x| c - x }
        cross = [a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0]]
        cross.zip(normal).sum { |left, right| left * right }.negative?
      end

      def issue(code, message, record, reference, blocking: true)
        id = record["id"].is_a?(String) ? record["id"] : nil
        finding = { "code" => code, "section" => ExportProjection::APERTURES, "object_id" => id,
                    "message" => message, "blocks_export" => blocking }
        if id
          finding["locate"] = { "name" => "#{FEATURE_ID}.units.locate", "params" => { "units" => [reference] } }
        end
        @findings << finding
      end
    end
  end
end
