# frozen_string_literal: true

module PhComposer
  module Records
    # The naming rule every catalog kind shares. A name is unique within its kind, compared without
    # outer space or case, and a copy takes the first free "<name> (copy)", "<name> (copy 2)", and so on.
    # `rows` are the kind's records as read, each with its `id` and `name`.
    module Names
      module_function

      def unique!(name, rows, except: nil)
        if name.strip.empty? || rows.any? { |row| row["id"] != except && row["name"].strip.casecmp(name.strip).zero? }
          raise CodedError.new("validation.failed", "Give the record a unique, nonempty name.")
        end
      end

      def copy_name(name, rows)
        stem = name.strip
        existing = rows.map { |row| row.fetch("name").strip.downcase }
        (1..).each do |index|
          candidate = index == 1 ? "#{stem} (copy)" : "#{stem} (copy #{index})"
          return candidate unless existing.include?(candidate.downcase)
        end
      end
    end
  end
end
