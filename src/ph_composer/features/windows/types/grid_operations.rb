# frozen_string_literal: true

module PhComposer
  module Windows
    # Pure grid gestures from the predecessor, one public function per gesture. Each takes the
    # stored record and the gesture's own params and returns detached authored values; the record
    # schema checks final coverage and references at the proposal boundary.
    module GridOperations
      module_function

      def refuse(message)
        raise CodedError.new("validation.failed", message)
      end

      # Copies of the record and params, so a gesture never changes its caller's values.
      def detached(record, values)
        [DeepCopy.call(record), DeepCopy.call(values)]
      end

      def cells(record, ids)
        refuse("Select unique elements first.") unless ids.is_a?(Array) && !ids.empty? && ids.uniq == ids
        ids.map do |id|
          record.fetch("elements").find { |cell| cell.fetch("id") == id } ||
            raise(CodedError.new("target.not_found", "The selected element no longer exists."))
        end
      end

      def axis(values)
        refuse("Choose rows or columns.") unless %w[rows_m columns_m].include?(values["axis"])
        values.fetch("axis")
      end

      def dimension(record, values)
        record, values = detached(record, values)
        key = axis(values)
        index = values.fetch("index")
        unless index.is_a?(Integer) && index.between?(0, record.fetch(key).length - 1)
          refuse("Choose an existing band.")
        end
        record[key][index] = values.fetch("value")
        record
      end

      def set_element_name(record, values)
        set_element_field(record, values, "name")
      end

      def set_element_glazing(record, values)
        set_element_field(record, values, "glazing_id")
      end

      def set_element_operation(record, values)
        set_element_field(record, values, "operation")
      end

      # An Empty element is wall area: it takes a name and nothing else.
      def set_element_field(record, values, field)
        record, values = detached(record, values)
        cell = cells(record, [values.fetch("element_id")]).first
        refuse("Empty is wall area, without products.") if cell["kind"] == "empty" && field != "name"
        cell[field] = values.fetch(field)
        record
      end

      def set_element_frame(record, values)
        record, values = detached(record, values)
        cell = cells(record, [values.fetch("element_id")]).first
        refuse("Empty is wall area, without products.") if cell["kind"] == "empty"
        cell.fetch("frames")[values.fetch("side")] = values.fetch("frame_id")
        record
      end

      def flip(record)
        record = DeepCopy.call(record)
        last_column = record.fetch("columns_m").length - 1
        record.fetch("columns_m").reverse!
        record.fetch("elements").each do |cell|
          first, last = cell.fetch("column_span")
          cell["column_span"] = [last_column - last, last_column - first]
          %w[frames installs].each do |field|
            cell[field]["left"], cell[field]["right"] = cell[field]["right"], cell[field]["left"]
          end
          next unless cell["operation"]

          cell["operation"]["directions"].map! { |side| { "left" => "right", "right" => "left" }.fetch(side, side) }
        end
        record
      end

      def kind(record, values)
        record, values = detached(record, values)
        refuse("Choose Glazed or Empty.") unless %w[glazed empty].include?(values["kind"])
        cells(record, values.fetch("ids")).each do |cell|
          next if cell.fetch("kind") == values.fetch("kind")

          cell["kind"] = values.fetch("kind")
          cell["frames"] = Types::SIDES.to_h { |side| [side, nil] }
          cell["installs"] = Types::SIDES.to_h { |side| [side, nil] }
          cell["glazing_id"] = cell["operation"] = nil
        end
        record
      end

      def merge(record, values, identity)
        record, values = detached(record, values)
        selected = cells(record, values.fetch("ids"))
        unless selected.length >= 2 && selected.map { |cell| cell.fetch("kind") }.uniq.length == 1
          refuse("Select at least two elements of the same kind.")
        end
        rows = [selected.map { |cell| cell["row_span"].first }.min, selected.map { |cell| cell["row_span"].last }.max]
        columns = [selected.map { |cell| cell["column_span"].first }.min,
                   selected.map { |cell| cell["column_span"].last }.max]
        area = selected.sum do |cell|
          (cell["row_span"].last - cell["row_span"].first + 1) *
            (cell["column_span"].last - cell["column_span"].first + 1)
        end
        unless area == (rows.last - rows.first + 1) * (columns.last - columns.first + 1)
          refuse("Selection must cover one rectangle without gaps.")
        end
        merged = DeepCopy.call(selected.min_by { |cell| [cell["row_span"].first, cell["column_span"].first] })
        merge_installs(selected, merged, rows, columns)
        merged.merge!("id" => identity.call("wel"), "row_span" => rows, "column_span" => columns)
        record["elements"] = record.fetch("elements").reject { |cell| values["ids"].include?(cell["id"]) } + [merged]
        record
      end

      def merge_installs(selected, merged, rows, columns)
        Types::SIDES.each_with_index do |side, i|
          boundary, internal = selected.partition do |cell|
            Grid.edge(cell.fetch("row_span"), cell.fetch("column_span"), i) == Grid.edge(rows, columns, i)
          end
          assignments = boundary.map { |cell| cell.fetch("installs")[side] }.uniq
          if assignments.length != 1
            refuse("#{side.capitalize} installation assignments differ. Resolve them in Installs before merging.")
          end
          # A stored internal slot may matter after splitting; do not discard it during merge.
          if internal.any? { |cell| cell.fetch("installs")[side] }
            refuse("Stored internal installations need review before merging.")
          end
          merged["installs"][side] = assignments.first
        end
      end

      def split(record, values, identity)
        record, values = detached(record, values)
        source = cells(record, [values.fetch("element_id")]).first
        rows = source.fetch("row_span")
        columns = source.fetch("column_span")
        if rows.first == rows.last && columns.first == columns.last
          refuse("Split needs a merged element spanning more than one cell.")
        end
        replacements = (rows.first..rows.last).flat_map do |row|
          (columns.first..columns.last).map do |column|
            child = DeepCopy.call(source)
            child.merge!("id" => identity.call("wel"), "row_span" => [row, row], "column_span" => [column, column])
            Types::SIDES.each_with_index do |side, i|
              unless Grid.edge([row, row], [column, column], i) == Grid.edge(rows, columns, i)
                child["installs"][side] = nil
              end
            end
            child
          end
        end
        record["elements"] = record.fetch("elements").reject { |cell| cell["id"] == source["id"] } + replacements
        record
      end

      def band_keys(values)
        key = axis(values)
        [key, key == "rows_m" ? "row_span" : "column_span", key == "rows_m" ? "columns_m" : "rows_m"]
      end

      def insert(record, values, identity)
        record, values = detached(record, values)
        key, span_key, other_key = band_keys(values)
        index = values.fetch("index")
        refuse("Choose a grid boundary.") unless index.is_a?(Integer) && index.between?(0, record.fetch(key).length)
        if record.fetch("elements").any? { |cell| cell[span_key].first < index && cell[span_key].last >= index }
          refuse("Split elements crossing this boundary before inserting.")
        end
        layout = Grid.new(record)
        before = record.fetch("elements").to_h { |cell| [cell.fetch("id"), layout.classify(cell)] }
        record[key].insert(index, values.fetch("value"))
        record.fetch("elements").each { |cell| cell[span_key].map! { |n| n >= index ? n + 1 : n } }
        record.fetch(other_key).length.times do |n|
          row, column = key == "rows_m" ? [index, n] : [n, index]
          record["elements"] << Types.blank(row, column, :identity => identity)
        end
        layout = Grid.new(record)
        record.fetch("elements").each do |cell|
          next unless (edges = before[cell.fetch("id")])

          layout.classify(cell).each_with_index do |classification, i|
            cell["installs"][Types::SIDES[i]] = nil if edges[i] == :perimeter && classification != :perimeter
          end
        end
        record
      end

      def remove(record, values)
        record, values = detached(record, values)
        key, span_key, = band_keys(values)
        index = values.fetch("index")
        unless index.is_a?(Integer) && index.between?(0, record.fetch(key).length - 1)
          refuse("Choose an existing band.")
        end
        refuse("The last band cannot be removed.") if record.fetch(key).length == 1
        if record.fetch("elements").any? { |cell| cell.fetch("installs").values.any? }
          refuse("This layout carries installation assignments. Review remapping in Installs before removing bands.")
        end
        record[key].delete_at(index)
        record["elements"].reject! { |cell| cell[span_key] == [index, index] }
        record["elements"].each do |cell|
          first, last = cell.fetch(span_key)
          cell[span_key] = [first > index ? first - 1 : first, last >= index ? last - 1 : last]
        end
        record
      end

      def paste(record, values)
        record, values = detached(record, values)
        source = cells(record, [values.fetch("source_id")]).first
        refuse("Empty cannot supply products.") if source.fetch("kind") == "empty"
        targets = cells(record, values.fetch("ids"))
        if targets.any? { |cell| cell.fetch("kind") == "empty" || cell.fetch("id") == source.fetch("id") }
          refuse("Choose glazed targets other than the source.")
        end
        layout = Grid.new(record)
        targets.each do |target|
          %w[glazing_id frames operation].each { |key| target[key] = DeepCopy.call(source[key]) }
          paste_installs(source, target, layout)
        end
        record
      end

      # A Psi-Install belongs to an outer edge, so it copies side by side only where that side is outer on
      # both elements. Every other edge keeps what it has: paste never moves an install onto a shared edge.
      def paste_installs(source, target, layout)
        source_edges = layout.classify(source)
        target_edges = layout.classify(target)
        Types::SIDES.each_with_index do |side, i|
          next unless source_edges[i] == :perimeter && target_edges[i] == :perimeter

          target.fetch("installs")[side] = source.fetch("installs")[side]
        end
      end
    end
  end
end
