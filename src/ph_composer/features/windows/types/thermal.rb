# frozen_string_literal: true

module PhComposer
  module Windows
    # Unrounded heat coefficients from the predecessor's independently characterized fixture.
    # Missing terms withhold the corresponding value; an incomplete element never contributes zero.
    module Thermal
      SIDES = Types::SIDES

      module_function

      # Top and bottom (even indexes in SIDES) run along the element's width; right and left along its height.
      def horizontal_edge?(index)
        index.even?
      end

      def number(value, positive: false, signed: false)
        return nil unless value.is_a?(Numeric) && value.finite? &&
                          (signed || (positive ? value > 0 : value >= 0))

        value.to_f
      end

      # Each finding is coded where its condition is detected; a reworded message never changes its code.
      def finding(code, message, side: nil)
        row = { "code" => code, "message" => message }
        side ? row.merge("side" => side) : row
      end

      # `default_id` is the Model's default Psi-Install Type; `default_psi_w_mk` is what an edge inherits when
      # there is none. A default Type no longer in the Model resolves to nothing, never to that value.
      def calculate(record, products, default_id, default_psi_w_mk: nil)
        unless (record.fetch("rows_m") + record.fetch("columns_m")).all? { |n| number(n, :positive => true) }
          return { "elements" => [],
                   "findings" => [finding("window_type.dimensions_incomplete", "Enter all grid dimensions.")],
                   "uw_w_m2k" => nil,
                   "u_effective_w_m2k" => nil, "complete" => false }
        end
        layout = Grid.new(record)
        input = products.merge("default_install_id" => default_id, "default_psi_w_mk" => default_psi_w_mk)
        details = record.fetch("elements").reject { |cell| cell.fetch("kind") == "empty" }.map do |cell|
          width = layout.side_length(cell, 0)
          height = layout.side_length(cell, 1)
          classifications = layout.classify(cell)
          detail = element(input, cell, width, height, classifications.map { |edge| edge == :shared })
          complete_element(detail, cell, products, classifications)
        end
        area = details.sum { |detail| detail.fetch("area_m2") }
        construction = total(details, "h_construction_w_k")
        installation = total(details, "h_install_w_k")
        findings = details.empty? ? [finding("window_type.no_glazed_elements", "No glazed elements.")] : []
        { "elements" => details, "findings" => findings, "area_m2" => area,
          "empty_area_m2" => record.fetch("rows_m").sum * record.fetch("columns_m").sum - area,
          "h_construction_w_k" => construction, "h_install_w_k" => installation,
          "uw_w_m2k" => construction && construction / area,
          "u_effective_w_m2k" => construction && installation && (construction + installation) / area,
          "complete" => !details.empty? && details.all? { |detail| detail.fetch("complete") } }
      end

      def operation_complete?(cell)
        operation = cell["operation"]
        operation && (operation.fetch("type") == "fixed" || !operation.fetch("directions").empty?)
      end

      def complete_element(detail, cell, products, classifications)
        if classifications.include?(:partial)
          classifications.each_with_index do |classification, i|
            next unless classification == :partial

            detail.fetch("edges")[i]["install"] = { "source" => "unsupported_partial", "id" => nil, "psi_w_mk" => nil }
          end
          detail["h_install_w_k"] = nil
          detail.fetch("findings") << finding("window_type.partial_shared_edge",
                                              "Partially shared edges need a proved installation mapping.")
        end
        glazing = products.fetch("glazings")[cell["glazing_id"]]
        detail["g_value"] = glazing && glazing["g_value"]
        detail.fetch("findings") << finding("window_type.g_value_missing", "Missing g-value.") if detail["g_value"].nil?
        unless operation_complete?(cell)
          detail.fetch("findings") << finding("window_type.operation_incomplete", "Choose operation and handedness.")
        end
        frame_mismatches(detail, cell, products.fetch("frames"))
        construction, installation = detail.values_at("h_construction_w_k", "h_install_w_k")
        detail["complete"] = !construction.nil? && !installation.nil? && !detail["g_value"].nil? &&
                             !!operation_complete?(cell)
        detail["uw_w_m2k"] = construction && construction / detail.fetch("area_m2")
        detail["u_effective_w_m2k"] = construction && installation &&
                                      (construction + installation) / detail.fetch("area_m2")
        detail
      end

      def frame_mismatches(detail, cell, frames)
        return unless cell["operation"]

        cell.fetch("frames").each do |side, id|
          frame = frames[id]
          next unless frame

          operation = frame["operation"].to_s.downcase
          next unless %w[fixed swing slide].include?(operation) && operation != cell["operation"]["type"]

          detail.fetch("findings") << finding("window_type.frame_operation_mismatch",
                                              "#{side}: frame operation #{operation} differs from element operation.",
                                              :side => side)
        end
      end

      def total(details, field)
        return nil if details.empty? || details.any? { |detail| detail[field].nil? }

        details.sum { |detail| detail.fetch(field) }
      end

      def install(input, cell, side, shared)
        return { "source" => "shared", "id" => nil, "psi_w_mk" => 0.0 } if shared

        resolution = EdgeResolution.resolve(cell, side, :perimeter, input["default_install_id"])
        id = resolution.effective_id
        psi = id ? input.fetch("psi_install_types")[id]&.fetch("psi_w_mk", nil) : input["default_psi_w_mk"]
        { "source" => resolution.source.to_s, "id" => id, "psi_w_mk" => number(psi, :signed => true) }
      end

      def element(input, cell, width, height, shared)
        findings = []
        edges = SIDES.each_with_index.map do |side, i|
          resolved = install(input, cell, side, shared[i])
          if resolved["psi_w_mk"].nil?
            findings << finding("window_type.install_unresolved", "The #{side} edge has no Psi-Install Type.",
                                :side => side)
          end
          { "side" => side, "length_m" => horizontal_edge?(i) ? width : height, "install" => resolved }
        end
        result = { "id" => cell.fetch("id"), "area_m2" => width * height, "edges" => edges, "findings" => findings,
                   "h_construction_w_k" => nil, "h_install_w_k" => nil }
        if edges.all? { |edge| !edge.fetch("install")["psi_w_mk"].nil? }
          result["h_install_w_k"] = edges.sum do |edge|
            edge.fetch("length_m") * edge.fetch("install").fetch("psi_w_mk")
          end
        end
        frames = SIDES.map { |side| input.fetch("frames")[cell.fetch("frames").fetch(side)] }
        widths = frames.map { |frame| frame && number(frame["width_m"]) }
        if widths.any?(&:nil?)
          findings << finding("window_type.frame_width_unresolved", "A Frame width is missing.")
          return result
        end
        top, right, bottom, left = widths
        glazing_width, glazing_height = width - left - right, height - top - bottom
        if glazing_width <= 0 || glazing_height <= 0
          findings << finding("window_type.glazing_area_nonpositive", "Frame widths leave no glazing area.")
          return result
        end
        result["glazing_area_m2"] = glazing_width * glazing_height
        result["frame_area_m2"] = result.fetch("area_m2") - glazing_width * glazing_height
        coefficients(result, input, cell, frames, widths, glazing_width, glazing_height)
      end

      def coefficients(result, input, cell, frames, widths, glazing_width, glazing_height)
        uf = frames.map { |frame| frame && number(frame["uf_w_m2k"]) }
        psi = frames.map { |frame| frame && number(frame["psi_g_w_mk"], :signed => true) }
        glazing = input.fetch("glazings")[cell["glazing_id"]]
        ug = glazing && number(glazing["ug_w_m2k"])
        top, right, bottom, left = widths
        result.fetch("edges").each_with_index do |edge, i|
          # Each corner square is split between its two frames, so a frame loses half of each neighbour's width.
          adjacent = horizontal_edge?(i) ? left + right : top + bottom
          edge["frame_area_m2"] = widths[i] * (edge.fetch("length_m") - adjacent / 2.0)
          edge["glass_edge_m"] = horizontal_edge?(i) ? glazing_width : glazing_height
          edge["h_frame_w_k"] = uf[i] && uf[i] * edge.fetch("frame_area_m2")
          edge["h_spacer_w_k"] = psi[i] && psi[i] * edge.fetch("glass_edge_m")
        end
        result["h_glazing_w_k"] = ug && ug * glazing_width * glazing_height
        if ug.nil? || uf.any?(&:nil?) || psi.any?(&:nil?)
          result.fetch("findings") << finding("window_type.construction_unresolved",
                                              "A Glazing Ug, Frame Uf or Frame psi-g value is missing.")
        else
          edges = result.fetch("edges").sum { |edge| edge.fetch("h_frame_w_k") + edge.fetch("h_spacer_w_k") }
          result["h_construction_w_k"] = result.fetch("h_glazing_w_k") + edges
        end
        result
      end
    end
  end
end
