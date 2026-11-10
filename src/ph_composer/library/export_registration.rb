# frozen_string_literal: true

require_relative "export_workflow"

module PhComposer
  module Library
    module ExportRegistration
      module_function

      def params
        text = { "type" => "string", "minLength" => 1 }
        selected = Library.object({ "record_kind" => text, "id" => text })
        Library.object({
          "scope" => Library.described({ "type" => "string", "enum" => %w[all selected] },
                                       "all, the default, takes every supported local definition; selected takes " \
                                       "only records."),
          "identity" => Library.described({ "type" => "string", "enum" => %w[new update] },
                                          "new, the default, gives the file a new library id; update keeps the id " \
                                          "of the library file being replaced."),
          "kinds" => Library.described({ "type" => "array", "items" => text, "minItems" => 1 },
                                       "Limit the export to these library kinds, such as materials."),
          "records" => Library.described({ "type" => "array", "items" => selected, "minItems" => 1 },
                                         "With scope selected: the records to export, each by record kind and id."),
          "library_name" => Library.described(text, "The library name written into the file. Defaults to Model " \
                                                    "library, or to the replaced file's name for update."),
          "expected_revision" => Library.described({ "type" => "integer", "minimum" => 0 },
                                                   "The Model revision export_preview reported; refused if the " \
                                                   "Model changed since."),
          "projection_digest" => Library.described(text, "The projection_digest export_preview reported; refused " \
                                                         "if what would be written differs. Required to replace a " \
                                                         "file at an approved location."),
          "compact" => Library.described({ "type" => "boolean" }, COMPACT)
        }, :optional => %w[scope identity kinds records library_name expected_revision projection_digest compact])
      end

      COMPACT = "true counts the omissions in omission_total in place of listing them; " \
                "ph_composer.library.export_preview.omissions pages them. false, the default, lists them."
      OMISSIONS = "ph_composer.library.export_preview.omissions"

      # `value` with its omissions counted in place of listed, and a library name longer than
      # OccurrencePath::NAME_CHARACTERS cut and named in `truncated`.
      def compact(value)
        names = value.key?("library_name") ? OccurrencePath.bounded_names(value.slice("library_name")) : {}
        value.reject { |key, _value| key == "omissions" }.merge(names)
             .merge("omission_total" => value.fetch("omissions").length)
      end

      def summary_fields
        text = { "type" => "string", "minLength" => 1 }
        label = Library.described(text, "The registered record kind's label, for display; kind and record_kind " \
                                        "stay the identifiers.")
        counted = Library.object({ "kind" => text, "record_kind_label" => label,
                                   "count" => { "type" => "integer", "minimum" => 0 } })
        omitted = Library.object({ "record_kind" => text, "record_kind_label" => label, "id" => text,
                                   "fields" => { "type" => "array", "items" => text }, "reason" => text },
                                 :optional => ["id"])
        { "kinds" => { "type" => "array", "items" => counted },
          "omissions" => { "type" => "array", "items" => omitted } }
      end

      def counted_fields
        { "omission_total" => { "type" => "integer", "minimum" => 0 },
          "projection_digest" => Library::TEXT, "revision" => { "type" => "integer", "minimum" => 0 } }
      end

      def install(feature)
        state = Library.described(Library::TEXT, "The SHA-256 the destination holds after the write; export_preview " \
                                                 "with the location reports it as destination.state.")
        fields = summary_fields.merge(counted_fields)
                               .merge("library_id" => Library::TEXT, "library_name" => Library::TEXT,
                                      "identity" => { "type" => "string", "enum" => %w[new update] },
                                      "written" => { "type" => "boolean" }, "destination_state" => state)
        cut = Library.described({ "type" => "array", "items" => Library::TEXT },
                                "Compact only: fields cut to 256 characters, such as library_name.")
        shape = Library.object(fields.merge("truncated" => cut),
                               :optional => %w[omissions omission_total projection_digest revision truncated])
        feature.file_export("#{FEATURE_ID}.export_file",
                            :description => "Write local definitions to a library file the user chooses in the " \
                                            "native save dialog; export_preview shows what it will hold.",
                            :refuses => Refuses::EXPORT_FILE,
                            :params => params, :result => shape, :approval => ExportWorkflow::APPROVAL,
                            :precondition => ExportWorkflow.method(:precondition),
                            :examples => [{}, { "scope" => "selected", "records" => [
                                                                         { "record_kind" => "example_parts",
                                                                           "id" => "part_AAAAAAAAAAAA" }
                                                                       ],
                                                "identity" => "new" }]) do |request|
          ExportWorkflow.run(request)
        end
        install_preview(feature)
      end

      def install_preview(feature)
        destination = Library.described(
          Library.object({ "exists" => { "type" => "boolean" }, "state" => { "type" => %w[string null] } }),
          "With location: whether the approved destination holds a file, and its state. Pass state as the " \
          "location's expected_destination to replace it."
        )
        scope = { "type" => "string", "enum" => %w[all selected] }
        preview_shape = Library.object(summary_fields.merge(counted_fields)
                                                     .merge("scope" => scope, "destination" => destination),
                                       :optional => %w[omissions omission_total destination])
        location = Library.described({ "type" => "string", "minLength" => 1 },
                                     "The id of an approved save destination, to report what it holds now.")
        preview_params = Library.object(params.fetch("properties").slice("scope", "kinds", "records", "compact")
                                              .merge("location" => location),
                                        :optional => %w[scope kinds records compact location])
        feature.query("#{FEATURE_ID}.export_preview",
                      :description => "Review local library export counts and omissions.",
                      :refuses => Refuses::EXPORT_PREVIEW,
                      :params => preview_params, :result => preview_shape, :examples => [{}]) do |request|
          preview(request)
        end
        install_omissions(feature, params.fetch("properties"))
      end

      def preview(request)
        projection = ExportProjection.build(request)
        summary = ExportProjection.summary(projection, request.registry)
        value = summary.merge("projection_digest" => projection.fetch("projection_digest"),
                              "revision" => request.session.revision, "scope" => request.params.fetch("scope", "all"))
        value = compact(value) if request.params["compact"]
        return value unless request.params.key?("location")

        value.merge("destination" => ApprovedLocations.observe(request.params["location"]) do |path|
          FileWriter.state(path)
        end)
      end

      # The omissions of the projection export_preview reviewed, a page at a time. Each page builds the
      # projection again and binds its cursor to the Model revision and that projection's digest, so a page of a
      # changed projection refuses rather than mixing two.
      def install_omissions(feature, properties)
        omitted = summary_fields.fetch("omissions").fetch("items")
        reviewed = Library.described(Library::TEXT, "The projection_digest export_preview reported; refused as " \
                                                    "revision.stale if the projection is no longer that one.")
        omission_params = Library.object(properties.slice("scope", "kinds", "records")
                                                   .merge("projection_digest" => reviewed, "limit" => Pages::LIMIT,
                                                          "cursor" => Pages::CURSOR),
                                         :optional => %w[scope kinds records projection_digest limit cursor])
        result = Library.object({ "omissions" => { "type" => "array", "items" => omitted }, "total" => Pages::TOTAL,
                                  "next_cursor" => Pages::NEXT_CURSOR }.merge(counted_fields.slice("projection_digest",
                                                                                                   "revision")))
        feature.query(OMISSIONS, :description => "A bounded page of what a library export leaves out, for the same " \
                                                 "scope as export_preview.",
                                 :refuses => Refuses::EXPORT_OMISSIONS, :params => omission_params,
                                 :result => result, :examples => [{}, { "scope" => "all", "limit" => 50 }]) do |request|
          omissions_page(request)
        end
      end

      def omissions_page(request)
        projection = ExportProjection.build(request)
        digest = projection.fetch("projection_digest")
        reviewed = request.params["projection_digest"]
        if reviewed && reviewed != digest
          raise Error.new("revision.stale", "What export_preview reviewed is not what would be written. Preview again.")
        end

        rows = ExportProjection.summary(projection, request.registry).fetch("omissions").each_with_index.to_a
        page, next_cursor = Pages.bounded(request, OMISSIONS, rows, :key => ->((_row, index)) { [index] },
                                                                    :revision => [request.revision, digest],
                                                                    :prepare => ->(sliced) { sliced.map(&:first) })
        { "omissions" => page, "total" => rows.length, "next_cursor" => next_cursor, "projection_digest" => digest,
          "revision" => request.session.revision }
      end
      private_class_method :preview, :install_omissions, :omissions_page
    end
  end
end
