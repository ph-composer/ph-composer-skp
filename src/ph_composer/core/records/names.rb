# frozen_string_literal: true

module PhComposer
  module Records
    # The naming rule every catalog kind shares. A name is unique within its kind, compared without
    # outer space or case, and a copy takes the first free "<name> (copy)", "<name> (copy 2)", and so on.
    # `rows` are the kind's records as read, each with its `id` and `name`. A new record or entity named by
    # number takes the first free "<stem> N" (`numbered`), as "Building Segment 2" and "Piping group 1" do.
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

      # The first "<stem> N" from `from` up that none of `names` already takes, compared by `compare` (this
      # module's `key` unless a kind folds names its own way).
      def numbered(stem, names, from: 1, compare: method(:key))
        taken = names.map { |name| compare.call(name.to_s) }
        number = from
        number += 1 while taken.include?(compare.call("#{stem} #{number}"))
        "#{stem} #{number}"
      end

      # A user's name after its kind word, quoted, so a Zone named "Zone A" reads Zone “Zone A” and never
      # Zone Zone A; with no name, the kind word and `id`.
      def titled(kind, name, id = nil)
        name.nil? || name.to_s.empty? ? "#{kind} #{id}".rstrip : "#{kind} #{quoted(name)}"
      end

      def quoted(name)
        "\u201C#{name}\u201D"
      end

      # Every rule here compares with the same Unicode case fold, so an accented name is one name in any case.
      def key(name)
        name.strip.downcase(:fold)
      end
    end
  end
end
