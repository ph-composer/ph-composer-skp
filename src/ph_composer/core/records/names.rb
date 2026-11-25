# frozen_string_literal: true

module PhComposer
  module Records
    # The naming rule every catalog kind shares. A name is unique within its kind, compared without
    # outer space or case, and a copy takes the first free "<name> (copy)", "<name> (copy 2)", and so on.
    # `rows` are the kind's records as read, each with its `id` and `name`.
    module Names
      module_function

      def unique!(name, rows, except: nil)
        wanted = key(name)
        if wanted.empty? || rows.any? { |row| row["id"] != except && key(row["name"]) == wanted }
          raise CodedError.new("validation.failed", "Give the record a unique, nonempty name.")
        end
      end

      def copy_name(name, rows)
        stem = name.strip
        existing = rows.map { |row| key(row.fetch("name")) }
        (1..).each do |index|
          candidate = index == 1 ? "#{stem} (copy)" : "#{stem} (copy #{index})"
          return candidate unless existing.include?(key(candidate))
        end
      end

      # Both rules compare with the same Unicode case fold, so an accented name is one name in any case.
      def key(name)
        name.strip.downcase(:fold)
      end
    end
  end
end
