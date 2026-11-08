# frozen_string_literal: true

module PhComposer
  module Zones
    module Options
      # Single-option commands reuse the same final-collection validation and atomic rewrite as the dialog.
      module Commands
        module_function

        def draft(request, collection)
          list = Options.choice_rows(request.engine, collection)
          default = Options.settings(request.engine)&.fetch("default_segment_id")
          { :collection => collection, :options => DeepCopy.call(list), :expected_options => list,
            :default_segment_id => default, :expected_default_segment_id => default, :replacements => {} }
        end

        def list(request, collection)
          kind = KINDS.fetch(collection)
          rows = Options.records(request.engine, kind.id)
          page, cursor = Pages.slice(request, "#{PREFIX}.list", rows, :key => ->(row) { row.fetch("id") })
          inventory = Inventory.rows(request.model)
          { "options" => page.map { |row| detail(request, collection, row.fetch("id"), inventory) },
            "next_cursor" => cursor, "total" => rows.length }
        end

        def detail(request, collection, id, inventory = Inventory.rows(request.model))
          kind = KINDS.fetch(collection)
          record = request.engine.find(kind.id, id)
          request.engine.view(kind.id, record).slice("id", "schema_version", "values", "user_data", "extension_data")
                 .merge("usage" => Options.usage(inventory, collection, id))
        end

        def create(request, proposal, collection, values, user_data = nil)
          params = draft(request, collection)
          temporary = "new:option"
          params.fetch(:options) << values.merge("id" => temporary).merge(user_data ? { "user_data" => user_data } : {})
          params[:default_segment_id] ||= temporary if collection == "building_segment"
          result = Options.manage(request, proposal, **params)
          { "id" => result.fetch("created_ids").fetch(temporary) }
        end

        def update(request, proposal, collection, id, values, expected_values)
          params = draft(request, collection)
          selected = params.fetch(:options).find { |row| row.fetch("id") == id }
          Options.refuse("target.not_found", "That option is absent") unless selected
          unless expected_values.all? { |key, value| selected[key] == value }
            Options.refuse("target.changed", "That option changed since it was read")
          end
          selected.merge!(values)
          Options.manage(request, proposal, **params)
          { "id" => id }
        end

        def remove(request, proposal, collection, id, replacement, replacement_given)
          params = draft(request, collection)
          unless params.fetch(:options).any? { |row| row.fetch("id") == id }
            Options.refuse("target.not_found", "That option is absent")
          end
          params[:options] = params.fetch(:options).reject { |row| row.fetch("id") == id }
          params[:replacements][id] = replacement if replacement_given
          if collection == "building_segment" && params.fetch(:default_segment_id) == id
            params[:default_segment_id] = replacement
          end
          Options.manage(request, proposal, **params)
        end
      end

      module CommandRegistration
        module_function

        def install(feature)
          collection = Registration::COLLECTION
          identity = Shapes.object({ "collection" => collection, "id" => Shapes::ID })
          example = { "collection" => "level", "id" => "lvl_Ab12Cd34Ef56" }
          base = LEVELS.descriptor.view_schema
          properties = base.fetch("properties").merge("values" => { "type" => "object" })
          view = Shapes.with(base.merge("properties" => properties),
                             "usage" => Shapes.object({ "live" => Shapes::COUNT, "recoverable" => Shapes::COUNT }))
          feature.query("#{PREFIX}.detail", :description => "One option's values, metadata and usage.",
                                            :params => Registration.describe_params(identity), :result => view,
                                            :refuses => Registration::REFUSALS, :examples => [example]) do |request|
            Commands.detail(request, request.params.fetch("collection"), request.params.fetch("id"))
          end
          feature.query("#{PREFIX}.usage", :description => "Live and recoverable Zone usage of one option.",
                                           :params => Registration.describe_params(identity),
                                           :result => Shapes.object({ "live" => Shapes::COUNT,
                                                                      "recoverable" => Shapes::COUNT }),
                                           :refuses => Registration::REFUSALS, :examples => [example]) do |request|
            Commands.detail(request, request.params.fetch("collection"), request.params.fetch("id")).fetch("usage")
          end
          list_params = Shapes.object({ "collection" => collection, "limit" => Pages::LIMIT,
                                        "cursor" => Pages::CURSOR }, :optional => %w[limit cursor])
          feature.query("#{PREFIX}.list", :description => "One page of model-owned option definitions.",
                                          :params => Registration.describe_params(list_params),
                                          :result => Shapes.object({ "options" => Shapes.list(view),
                                                                     "next_cursor" => Pages::NEXT_CURSOR,
                                                                     "total" => Pages::TOTAL }),
                                          :refuses => Registration::REFUSALS + Refuses::PAGE,
                                          :examples => [{ "collection" => "level" }]) do |request|
            Commands.list(request, request.params.fetch("collection"))
          end
          install_writes(feature, identity, example)
        end

        def install_writes(feature, identity, example)
          values = Shapes.object({ "name" => NAME, "colour" => COLOUR })
          create = Shapes.object({ "collection" => Registration::COLLECTION, "values" => values,
                                   "user_data" => { "type" => "object" } }, :optional => ["user_data"])
          example_create = { "collection" => "level", "values" => { "name" => "Level 1", "colour" => "#1F7478" } }
          action(feature, "create", create, Shapes.object({ "id" => Shapes::ID }),
                 [example_create]) do |request, proposal|
            Commands.create(request, proposal, request.params.fetch("collection"), request.params.fetch("values"),
                            request.params["user_data"])
          end
          update = Shapes.with(identity, "values" => values, "expected_values" => values)
          action(feature, "update", update, Shapes.object({ "id" => Shapes::ID }),
                 [example.merge("values" => { "name" => "Level 1", "colour" => "#1F7478" },
                                "expected_values" => { "name" => "Level 1",
                                                       "colour" => "#1F7478" })]) do |request, proposal|
            Commands.update(request, proposal, request.params.fetch("collection"), request.params.fetch("id"),
                            request.params.fetch("values"), request.params.fetch("expected_values"))
          end
          remove = Shapes.object(identity.fetch("properties").merge("replacement_id" => { "type" => %w[string null] }),
                                 :optional => ["replacement_id"])
          action(feature, "remove", remove, Registration::RESULT, [example]) do |request, proposal|
            Commands.remove(request, proposal, request.params.fetch("collection"), request.params.fetch("id"),
                            request.params["replacement_id"], request.params.key?("replacement_id"))
          end
          merge = Shapes.with(identity, "target_id" => Shapes::ID)
          action(feature, "merge", merge, Registration::RESULT, [example.merge("target_id" => "lvl_Zz12Cd34Ef56")]) do |
                      request, proposal|
            Commands.remove(request, proposal, request.params.fetch("collection"), request.params.fetch("id"),
                            request.params.fetch("target_id"), true)
          end
        end

        def action(feature, verb, params, result, examples, &block)
          feature.action("#{PREFIX}.#{verb}", :description => "#{verb.capitalize} a managed Zone option atomically.",
                                              :params => Registration.describe_params(params), :result => result,
                                              :refuses => Registration::REFUSALS,
                                              :examples => examples, :undo_name => "Manage Zone Options",
                                              :side_effects => "Writes choices and references atomically.",
                         &block)
        end
      end
    end
  end
end
