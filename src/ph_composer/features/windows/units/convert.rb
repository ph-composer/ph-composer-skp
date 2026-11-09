# frozen_string_literal: true

require_relative "anchors"
require_relative "convert_review"
require_relative "convert_sources"
require_relative "convert_step"
require_relative "identity_step"
require_relative "read_context"
require_relative "../types/operations"

module PhComposer
  module Windows
    module Units
      # Convert to Window Type's action: rereads the rectangles a review listed, refuses if they changed,
      # writes the new Types and hands one ConvertStep the rest. Each group becomes one Unit; groups of one
      # size that all want a new Type share it (W7-6).
      module Convert
        COPIED_PROPERTIES = %w[glazing_id frames installs operation].freeze

        module_function

        def run(request, proposal, groups:)
          identity = Records::Identity.allocator(request, "groups" => groups)
          Mutation.prepare(request, proposal, :identity => identity)
          sources = checked_sources(request, groups)
          built = built_groups(request, sources)
          matched = match(groups, built, ConvertReview.rows(built, ConvertReview.types(request)))
          planned, created_ids = with_types(request, proposal, matched, identity)
          step = ConvertStep.new(:model => request.model, :groups => planned, :new_type_ids => created_ids,
                                 :existing_polygons_m => ReadContext.new(request).other_polygons)
          proposal.add_step(step, :scopes => step.scopes)
          units = planned.map do |item|
            { "unit_id" => item.fetch(:record).fetch("id"), "type_id" => item.fetch(:type).fetch("id") }
          end
          { "units" => units, "created_type_ids" => created_ids }
        end

        # Each listed source as it is now, refused unless its geometry is what the review read.
        def checked_sources(request, groups)
          listed = groups.flat_map { |group| group.fetch("sources") }
          paths = listed.map { |row| row.fetch("path") }
          raise CodedError.new("params.invalid", "Name each rectangle once.") unless paths.uniq == paths
          if paths.length > Pages::MAXIMUM_LIMIT
            raise CodedError.new("params.invalid", "A conversion takes at most #{Pages::MAXIMUM_LIMIT} rectangles.")
          end

          sources, unread = ConvertSources.read(request.model, paths)
          unread.each { |row| raise_unread(row) }
          expected = listed.to_h { |row| row.values_at("path", "digest") }
          sources.each do |source|
            changed! unless source.geometry.digest == expected.fetch(source.path)
          end
          sources
        end

        def raise_unread(row)
          changed! if row.fetch("code") == "window.not_rectangle"

          raise CodedError.new(row.fetch("code"), row.fetch("message"))
        end

        def built_groups(request, sources)
          built, left_out = ConvertReview.assess(request, sources)
          left_out.each { |row| raise CodedError.new(row.fetch("code"), row.fetch("message")) }
          built
        end

        # The review's group and row for each requested group; a requested group the review would not form
        # is stale.
        def match(groups, built, rows)
          by_paths = built.each_index.to_h { |index| [built[index].fetch(:sources).map(&:path).sort, index] }
          groups.map do |group|
            key = group.fetch("sources").map { |row| row.fetch("path") }.sort
            index = by_paths[key]
            changed! unless index
            { :request => group, :built => built[index], :row => rows[index] }
          end
        end

        def with_types(request, proposal, matched, identity)
          rows = Definitions.records(request, Types::KIND)
          created = {}
          planned = matched.map do |entry|
            type = chosen_type(request, proposal, entry, rows, created, identity, matched)
            entry.fetch(:built).merge(:type => type, :record => record(identity, type))
          end
          [planned, created.values.map { |type| type.fetch("id") }]
        end

        def chosen_type(request, proposal, entry, rows, created, identity, matched)
          group = entry.fetch(:request)
          row = entry.fetch(:row)
          existing = group["type_id"]
          if existing && (group["name"] || group["copy_from_type_id"])
            raise CodedError.new("params.invalid", "A chosen Window Type takes no new name or Copy from.")
          end

          return existing_type(request, existing, row) if existing

          index = row.fetch("layout_index")
          created[index] ||= new_type(request, proposal, entry, rows, identity, matched, index)
        end

        def existing_type(request, type_id, row)
          type = request.engine.find(TYPE_KIND, type_id)
          return type if row.fetch("matching_types").any? { |match| match.fetch("id") == type_id }

          raise CodedError.new("validation.failed", "That Window Type is not the size of these rectangles.")
        end

        def new_type(request, proposal, entry, rows, identity, matched, index)
          name = new_name(entry, matched, index)
          Records::Names.unique!(name, rows)
          layout = entry.fetch(:built).fetch(:layout)
          copied = copied_properties(request, matched, index)
          values = { "name" => name, "columns_m" => layout.columns_m, "rows_m" => layout.rows_m,
                     "elements" => elements(layout, identity, copied) }
          id = Types::Operations.create(request, proposal, :values => values).fetch("id")
          rows << { "id" => id, "name" => name }
          proposal.find(TYPE_KIND, id).after
        end

        # The name the shared group gave, or the review's default for its size (W7-8).
        def new_name(entry, matched, index)
          choice(matched, index, "name", "name") { |name| name.strip } || entry.fetch(:row).fetch("default_name")
        end

        # What the shared group's Copy from Type gives every element: its first glazed element's properties
        # (W7-7). Nothing when the group names none.
        def copied_properties(request, matched, index)
          source_id = choice(matched, index, "copy_from_type_id", "Copy from Type") { |id| id }
          return {} unless source_id

          element = request.engine.find(TYPE_KIND, source_id).fetch("elements").find do |cell|
            cell.fetch("kind") == "glazed"
          end
          raise CodedError.new("validation.failed", "That Window Type has no glazed element to copy.") unless element

          DeepCopy.call(element.slice(*COPIED_PROPERTIES))
        end

        # The one value the groups sharing a new Window Type give for `key`, or nil when none does.
        def choice(matched, index, key, words)
          given = matched.select { |item| item.fetch(:row).fetch("layout_index") == index }
                         .filter_map { |item| item.fetch(:request)[key] && yield(item.fetch(:request)[key]) }.uniq
          if given.length > 1
            raise CodedError.new("params.invalid", "Groups sharing a new Window Type take one #{words}.")
          end

          given.first
        end

        def elements(layout, identity, copied)
          layout.spans.map do |row_span, column_span|
            Types.blank(row_span.first, column_span.first, :identity => identity)
                 .merge("row_span" => row_span, "column_span" => column_span).merge(DeepCopy.call(copied))
          end
        end

        def record(identity, type)
          { "id" => identity.call("wun"), "schema_version" => 1, "window_type_id" => type.fetch("id"),
            "anchor" => Anchors::DEFAULT, "user_data" => {}, "extension_data" => {} }
        end

        def changed!
          raise CodedError.new("target.changed", "A drawn rectangle changed since it was reviewed. Review it again.")
        end
        private_class_method :checked_sources, :raise_unread, :built_groups, :match, :with_types, :chosen_type,
                             :existing_type, :new_type, :new_name, :copied_properties, :choice, :elements, :record,
                             :changed!
      end
    end
  end
end
