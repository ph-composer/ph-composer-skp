# frozen_string_literal: true

module PhComposer
  module Library
    # The bounded reads of a loaded catalog (context/AGENT_INTERFACE.md, "Focused reads"). A compact page counts
    # its notes and summarizes each row's snapshot and each comparison; the notes page on their own; one row's
    # part reads exactly in fragments. Every cursor binds the catalog generation it was read from, and the
    # in-file reads, which compare with local records, the Model revision too. Rows are what catalog and in_file
    # build, so no read here has a rule of its own.
    module CatalogReads
      WARNINGS = "ph_composer.library.warnings.list"
      UNAVAILABLE = "ph_composer.library.unavailable.list"
      CATALOG_DETAIL = "ph_composer.library.catalog.detail"
      IN_FILE_DETAIL = "ph_composer.library.in_file.detail"
      NOTES = { WARNINGS => "warnings", UNAVAILABLE => "unavailable" }.freeze
      ROW_PARTS = %w[snapshot display_label library_name].freeze
      # A compact comparison lists at most this many local candidates, and only as many as fit CANDIDATE_BYTES
      # serialized, so one row stays well inside a page whatever the labels hold.
      CANDIDATES = 20
      CANDIDATE_BYTES = 8 * 1024
      DETAIL_EXAMPLE = { "provider_id" => "example", "kind" => "example_parts", "library_id" => "synthetic",
                         "record_id" => "one", "path" => %w[snapshot notes] }.freeze
      COMPACT = { "type" => "boolean",
                  "description" => "true counts the warnings and unavailable notes, summarizes each row's snapshot " \
                                   "and comparison, and cuts long labels; the detail and notes reads give them " \
                                   "whole. false, the default, answers them in full." }.freeze

      extend SchemaShapes

      module_function

      # The catalog summary with its notes counted in place of listed.
      def compact_entry(entry)
        entry.reject { |key, _value| %w[warnings unavailable].include?(key) }
             .merge("warning_total" => entry.fetch("warnings").length,
                    "unavailable_total" => entry.fetch("unavailable").length)
      end

      # A catalog or in_file row with its snapshot summarized, its labels cut and its comparison compact.
      def compact_row(row)
        compact = row.reject { |key, _value| key == "snapshot" }
                     .merge(OccurrencePath.bounded_names(row.slice("library_name", "display_label")))
                     .merge("snapshot_summary" => Fragments.summary(row.fetch("snapshot")))
        compact["resolution"] = compact_resolution(row.fetch("resolution")) if row.key?("resolution")
        compact
      end

      # The first candidates, compact, while they number at most CANDIDATES and weigh at most CANDIDATE_BYTES (the
      # first always), and how many there are; in_file.detail reads any of them whole.
      def compact_resolution(resolution)
        all = resolution.fetch("candidates")
        weight = 0
        candidates = all.first(CANDIDATES).map { |candidate| compact_candidate(candidate) }
                        .take_while.with_index do |candidate, index|
          weight += JSON.generate(candidate).bytesize
          index.zero? || weight <= CANDIDATE_BYTES
        end
        resolution.merge("candidates" => candidates, "candidate_total" => all.length)
      end

      def compact_candidate(candidate)
        candidate.slice("id", "comparison_available", "source_changed")
                 .merge(OccurrencePath.bounded_names(candidate.slice("display_label")))
                 .merge("difference_fields" => candidate.fetch("differences").map { |row| row.fetch("field") },
                        "expected_values_summary" => Fragments.summary(candidate.fetch("expected_values")))
      end

      def install(feature)
        NOTES.each do |name, key|
          feature.query(name, :description => "A bounded page of a loaded catalog's #{key} notes, in order.",
                              :refuses => Refuses::CATALOG, :params => notes_params,
                              :result => Schemas.notes_page(key), :examples => [PAGE_EXAMPLE]) do |request|
            notes_page(request, name)
          end
        end
        install_details(feature)
      end

      def install_details(feature)
        feature.query(CATALOG_DETAIL, :description => "One part of one catalog row, read exactly in fragments.",
                                      :refuses => Refuses::CATALOG_DETAIL, :params => detail_params(ROW_PARTS),
                                      :result => Schemas.detail, :examples => [DETAIL_EXAMPLE]) do |request|
          detail(request, CATALOG_DETAIL, ROW_PARTS, :resolved => false)
        end
        parts = ROW_PARTS + ["resolution"]
        feature.query(IN_FILE_DETAIL, :description => "One part of one in_file row, its comparison with local " \
                                                      "records included, read exactly in fragments.",
                                      :refuses => Refuses::IN_FILE_DETAIL, :params => detail_params(parts),
                                      :result => Schemas.detail,
                                      :examples => [DETAIL_EXAMPLE.merge("path" => ["resolution", "candidates", 0,
                                                                                    "expected_values"])]) do |request|
          detail(request, IN_FILE_DETAIL, parts, :resolved => true)
        end
      end
      private_class_method :install_details

      def notes_params
        properties = Library.selected_params.fetch("properties").merge("limit" => Pages::LIMIT,
                                                                       "cursor" => Pages::CURSOR)
        object(properties, :optional => %w[generation limit cursor])
      end

      def detail_params(parts)
        properties = Library.selected_params.fetch("properties").merge(
          "library_id" => described(TEXT, "The library holding the row, as the catalog row gives it."),
          "record_id" => described(TEXT, "The row's record id within that library."),
          "path" => Fragments.path_param(parts, '["snapshot", "notes"]'), "cursor" => Pages::CURSOR
        )
        object(properties, :optional => %w[generation cursor])
      end

      def notes_page(request, query)
        entry = entry(request)
        key = NOTES.fetch(query)
        notes = entry.fetch(key).each_with_index.to_a
        page, next_cursor = Pages.bounded(request, query, notes, :key => ->((_note, index)) { [index] },
                                                                 :revision => [entry.fetch("generation")],
                                                                 :prepare => ->(sliced) { sliced.map(&:first) })
        entry.slice("provider_id", "kind", "generation")
             .merge(key => page, "total" => notes.length, "next_cursor" => next_cursor)
      end

      # One part of the row catalog (or, `resolved`, in_file) builds, bound to what that row was read from.
      def detail(request, query, parts, resolved:)
        path = request.params.fetch("path")
        Fragments.check_start!(path, parts)
        entry = entry(request)
        row = Coordinator.row_in(entry, request.params)
        row = Library.resolved(request, [row]).first if resolved
        revision = [entry.fetch("generation"), resolved ? request.revision : nil]
        { "generation" => entry.fetch("generation") }
          .merge(Fragments.detail(request, query, row, path, :parts => parts, :revision => revision))
      end

      def entry(request)
        params = request.params
        State.for(request.session).fetch(params.fetch("provider_id"), params.fetch("kind"), request.registry,
                                         :generation => params["generation"])
      end
      private_class_method :notes_page, :detail, :entry
    end
  end
end
