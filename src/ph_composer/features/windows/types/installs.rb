# frozen_string_literal: true

module PhComposer
  module Windows
    # Detached draft edits. The panel owns its session; one registered save submits its final
    # product and edge values together. Internal shared assignments are never invented or painted.
    module Installs
      module_function

      def each_edge(record)
        layout = Grid.new(record)
        record.fetch("elements").each do |element|
          next if element.fetch("kind") == "empty"

          layout.classify(element).each_with_index do |classification, i|
            yield element, Types::SIDES[i], classification
          end
        end
      end

      def validate(record)
        each_edge(record) do |element, side, classification|
          if classification == :partial
            raise CodedError.new("validation.failed", "Partly shared edges need a proved installation mapping.")
          end
          if classification == :shared && element.fetch("installs")[side]
            raise CodedError.new("validation.failed", "Shared edges cannot store an installation assignment.")
          end
        end
        record
      end

      def paint(record, element_id, side, install_id)
        unless Types::SIDES.include?(side)
          raise CodedError.new("params.invalid", "Choose a canonical edge.")
        end

        copy = DeepCopy.call(record)
        element = copy.fetch("elements").find { |cell| cell.fetch("id") == element_id }
        raise CodedError.new("target.not_found", "The element no longer exists.") unless element

        if element["kind"] == "empty"
          raise CodedError.new("validation.failed", "Empty elements have no installation edges.")
        end

        classification = Grid.new(copy).classify(element).fetch(Types::SIDES.index(side))
        unless classification == :perimeter
          raise CodedError.new("validation.failed", "Only perimeter edges can be painted.")
        end

        element.fetch("installs")[side] = install_id
        copy
      end

      def apply_all(record, install_id)
        copy = DeepCopy.call(record)
        each_edge(copy) do |element, side, classification|
          element.fetch("installs")[side] = install_id if classification == :perimeter
        end
        validate(copy)
      end

      # `record` with every assignment off a perimeter edge cleared, for values set on all four sides at once.
      def perimeter_only(record)
        copy = DeepCopy.call(record)
        each_edge(copy) do |element, side, classification|
          element.fetch("installs")[side] = nil unless classification == :perimeter
        end
        validate(copy)
      end

      # The grid bands and each element's kind, spans and edge classifications, in span order: what two
      # Types must share for `copy`. Its digest is the panel's `copy_key`, so its shape stays as it is.
      def topology(record)
        layout = Grid.new(record)
        [record.fetch("rows_m"), record.fetch("columns_m"), record.fetch("elements").map do |element|
          [element.fetch("kind"), element.fetch("row_span"), element.fetch("column_span"),
           layout.classify(element).map(&:to_s)]
        end.sort_by { |entry| [entry[1], entry[2]] }]
      end

      # What a client needs to stage installation edits without classifying edges itself: each
      # non-empty element's four edges with their classification and whether `paint` accepts them, the
      # digest of what `copy` compares (equal keys mean `copy` accepts the pair; the value is opaque),
      # and each element's slot in the join `copy` performs. Derived on every read, never stored.
      def topology_facts(record)
        layout = Grid.new(record)
        edges = record.fetch("elements").each_with_object({}) do |element, rows|
          next if element.fetch("kind") == "empty"

          rows[element.fetch("id")] = Types::SIDES.zip(layout.classify(element)).to_h do |side, classification|
            [side, { "classification" => classification.to_s, "paintable" => classification == :perimeter }]
          end
        end
        slots = record.fetch("elements").to_h { |element| [element.fetch("id"), CanonicalJson.generate(slot(element))] }
        { "edges" => edges, "copy_key" => CanonicalJson.digest(comparable(topology(record))), "copy_slots" => slots }
      end

      # The topology as `copy` compares it, with each dimension as a Float: Ruby equality takes 1 and
      # 1.0 as one value, and the digest must too.
      def comparable(topology)
        rows, columns, elements = topology
        [rows.map { |value| value&.to_f }, columns.map { |value| value&.to_f }, elements]
      end

      def slot(element)
        [element.fetch("kind"), element.fetch("row_span"), element.fetch("column_span")]
      end

      def copy(source, target)
        unless topology(source) == topology(target)
          raise CodedError.new("validation.failed", "Copy targets need an identical grid and edge topology.")
        end

        validate(source)
        result = DeepCopy.call(target)
        assignments = source.fetch("elements").to_h { |element| [slot(element), element.fetch("installs")] }
        result.fetch("elements").each do |element|
          element["installs"] = DeepCopy.call(assignments.fetch(slot(element)))
        end
        result
      end
    end
  end
end
