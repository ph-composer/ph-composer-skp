# frozen_string_literal: true

module PhComposer
  module Assemblies
    module Thermal
      RSI = { "RoofCeiling" => 0.10, "Wall" => 0.13, "Floor" => 0.17 }.freeze
      # Bound exact Cartesian evaluation, not authoring: 30 binary mixed Layers would require
      # over a billion paths on the host thread. Above this budget the record stays editable and
      # the display reports assembly.calculation_limit rather than an approximation.
      PATH_BUDGET = 16_384
      HEAT_FLOW = { "RoofCeiling" => "upward", "Floor" => "downward" }.freeze
      # Why a thermal display value is withheld, by the same code Validation reports for the condition.
      PREVIEW_MESSAGES = {
        "assembly.membrane_in_mixed_layer" => "A membrane Layer must hold only one Layer-Segment.",
        "assembly.segment_unassigned" => "One or more Layer-Segments do not have a Material assignment.",
        "material.conductivity_missing" => "One or more assigned materials need conductivity before export.",
        "assembly.geometry_invalid" => "Layer thickness, Layer-Segment width, or steel-stud spacing is invalid.",
        "assembly.material_dangling" => "One or more Layer-Segments reference a missing project Material.",
        "assembly.no_thermal_layers" => "Every Layer is a membrane with no thermal resistance, so no U-value is " \
                                        "available.",
        "material.invalid" => "One or more referenced Materials cannot be read.",
        "assembly.calculation_limit" => "The exact thermal calculation exceeds its path budget; no value is available."
      }.freeze
      UNCALCULABLE = "Thermal resistance could not be calculated from the assigned Layer-Segments."
      # One way heat crosses a Layer: through one Layer-Segment's material, over that segment's share of
      # the Layer's width.
      Path = Struct.new(:resistance_m2k_w, :fraction, keyword_init: true)

      module_function

      # The Assembly editor's and inventory's thermal block for a projected layered assembly: the effective values when
      # they can be calculated, the ISO 6946 films shown beside them, and the flags that say why a value is missing or
      # incomplete. The panel reads this block; it does not calculate.
      def preview(assembly, materials)
        films = surface_resistances(assembly)
        flags = preview_flags(assembly, materials)
        block = {
          "complete" => flags.empty?, "flags" => flags, "warnings" => flags.map { |flag| PREVIEW_MESSAGES.fetch(flag) },
          "u_effective_w_m2k" => nil, "u_construction_w_m2k" => nil, "r_construction_m2k_w" => nil,
          "rsi_m2k_w" => films.fetch("r_in"), "rse_m2k_w" => films.fetch("r_out"),
          "direction" => HEAT_FLOW.fetch(assembly["type"], "horizontal")
        }
        return block if flags.any?

        values = effective(assembly, materials)
        return block.merge(values) if values

        flags = (flags + ["assembly.geometry_invalid"]).uniq.sort
        block.merge("complete" => false, "flags" => flags,
                    "warnings" => flags.map { |flag| PREVIEW_MESSAGES.fetch(flag) } + [UNCALCULABLE])
      end

      def preview_flags(assembly, materials)
        layers = Array(assembly["layers"])
        flags = layers.each_with_object([]) do |layer, result|
          segments = Array(layer["segments"])
          result << "assembly.geometry_invalid" unless layer["thickness_mm"].to_f.positive?
          result << "assembly.membrane_in_mixed_layer" if Materials::Schema.membrane_in_mixed_layer?(layer, materials)
          segments.each { |segment| result.concat(segment_flags(segment, materials)) }
        end
        flags << "assembly.geometry_invalid" if layers.empty?
        flags << "assembly.no_thermal_layers" if !layers.empty? && layers.all? { |layer| membrane?(layer, materials) }
        flags << "assembly.calculation_limit" if flags.empty? && calculation_limited?(layers, materials)
        flags.uniq.sort
      end
      private_class_method :preview_flags

      def segment_flags(segment, materials)
        spacing = segment["steel_stud_spacing_mm"]
        flags = []
        if !segment["width_mm"].to_f.positive? || (!spacing.nil? && !spacing.to_f.positive?)
          flags << "assembly.geometry_invalid"
        end
        return flags << "assembly.segment_unassigned" if segment["material_id"].nil?

        material = materials[segment["material_id"]]
        if material.nil?
          flags << "assembly.material_dangling"
        elsif !Materials::Schema::KIND.problems(material).empty?
          flags << "material.invalid"
        elsif !Materials::Schema.membrane?(material) && !material["conductivity_w_mk"].to_f.positive?
          flags << "material.conductivity_missing"
        end
        flags
      end

      # Counts possible thermal paths with an early exit; no Cartesian paths are generated here.
      def calculation_limited?(layers, materials)
        count = 1
        layers.each do |layer|
          next if membrane?(layer, materials)

          count *= layer.fetch("segments").length
          return true if count > PATH_BUDGET
        end
        false
      end

      # Mean of parallel-path and isothermal-plane construction resistances; films added afterward.
      def effective(assembly, materials)
        layers = Array(assembly["layers"])
        return nil if layers.empty?
        return nil unless preview_flags(assembly, materials).empty?

        per_layer = layers.reject { |layer| membrane?(layer, materials) }
                          .map { |layer| layer_paths(layer, materials) }.reject(&:empty?)
        return nil if per_layer.empty?

        r_parallel = parallel(per_layer)
        r_isothermal = isothermal(per_layer)
        return nil unless r_parallel.positive? && r_isothermal.positive?

        r_construction = (r_parallel + r_isothermal) / 2.0
        films = surface_resistances(assembly)
        {
          "u_effective_w_m2k" => round6(1.0 / (r_construction + films.fetch("r_in") + films.fetch("r_out"))),
          "u_construction_w_m2k" => round6(1.0 / r_construction),
          "r_construction_m2k_w" => round6(r_construction)
        }
      end

      def surface_resistances(assembly)
        r_in = RSI.fetch(assembly["type"], 0.13)
        r_out = case assembly["exterior_condition"]
                when "Ground" then 0.0
                when "Outdoors", nil then 0.04
                else r_in
                end
        # Only an exterior that faces outdoors has a cladding to ventilate.
        r_out = r_in if assembly["ventilated_cladding"] && [nil, "Outdoors"].include?(assembly["exterior_condition"])
        { "r_in" => r_in, "r_out" => r_out }
      end

      # Projected layers carry is_membrane; raw records fall back to the material rule.
      def membrane?(layer, materials)
        layer.key?("is_membrane") ? layer.fetch("is_membrane") : Materials::Schema.membrane_layer?(layer, materials)
      end
      private_class_method :membrane?

      def layer_paths(layer, materials)
        assigned = Array(layer["segments"]).each_with_object([]) do |segment, result|
          material = materials[segment["material_id"]]
          next unless material && material["conductivity_w_mk"].to_f.positive?

          result << [segment, material]
        end
        total = assigned.sum { |segment, _material| segment.fetch("width_mm") }
        return [] unless total.positive?

        assigned.map do |segment, material|
          Path.new(:resistance_m2k_w => (layer.fetch("thickness_mm") / 1000.0) / material.fetch("conductivity_w_mk"),
                   :fraction => segment.fetch("width_mm").to_f / total)
        end
      end
      private_class_method :layer_paths

      def parallel(paths)
        uniform, mixed = paths.partition { |layer| layer.length == 1 }
        base_resistance = uniform.sum { |layer| layer.first.resistance_m2k_w }
        return base_resistance if mixed.empty?

        # Each mixed Layer has at least two paths. The checked budget therefore bounds recursive
        # depth to fourteen, however many uniform Layers were authored.
        total_u = 0.0
        visit = lambda do |index, resistance, fraction|
          if index == mixed.length
            total_u += fraction / resistance if resistance.positive?
            next
          end
          mixed[index].each do |path|
            visit.call(index + 1, resistance + path.resistance_m2k_w, fraction * path.fraction)
          end
        end
        visit.call(0, base_resistance, 1.0)
        total_u.positive? ? 1.0 / total_u : 0.0
      end
      private_class_method :parallel

      def isothermal(per_layer)
        per_layer.sum do |paths|
          next paths.first.resistance_m2k_w if paths.length == 1

          1.0 / paths.sum { |path| path.fraction / path.resistance_m2k_w }
        end
      end
      private_class_method :isothermal

      def round6(value)
        value.round(6)
      end
      private_class_method :round6
    end
  end
end
