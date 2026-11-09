# frozen_string_literal: true

module PhComposer
  module Spaces
    # Pure: which Zone occurrence a Space is hosted in. Membership is the `zone_id` on the Space's record
    # (context/CONTRACTS.md, "Space membership"); `zones` are rows with `zone_id` and `zone_path`, as the
    # Zones read names them. A repeated Zone id resolves to its first occurrence in path order, since a
    # repeated Zone carries its own finding.
    module Membership
      module_function

      def zone_row(record, zones)
        id = record["zone_id"]
        return nil unless id

        zones.select { |zone| zone.fetch("zone_id") == id }.min_by { |zone| zone.fetch("zone_path") }
      end
    end
  end
end
