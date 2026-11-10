# frozen_string_literal: true

require_relative "pages"

module PhComposer
  # What one container holds, with no selection: the native children directly inside the Model root or a
  # Group or component named by its root-to-container path, a bounded page at a time, each with what a
  # feature's read or write needs to know before it builds on it (context/AGENT_INTERFACE.md, "Model
  # context"). It lists every child whatever its state and says, per row, whether it is hidden, locked,
  # in shared storage, a closed solid, and which registered stores have records on it; only `kinds`
  # filters, so a total never depends on view state. It walks only the path and the one collection, never
  # the Model, and moves nothing. It names no feature: ownership comes from Records::EntityStore.
  module ContextChildren
    KINDS = %w[group component face edge other].freeze

    extend SchemaShapes

    module_function

    def install(feature)
      feature.query(ContextCommands::CHILDREN,
                    :description => "One bounded page of the native entities directly inside the Model root or " \
                                    "one Group or component, by persistent id, each with its kind, name, " \
                                    "whether it is hidden, locked, shared or a closed solid, and the PH-Composer " \
                                    "records on it. Nothing is filtered out except by kinds. Reads only; " \
                                    "nothing is selected.",
                    :params => object({ "path" => path_param, "kinds" => kinds_param,
                                        "limit" => Pages::LIMIT, "cursor" => Pages::CURSOR },
                                      :optional => %w[path kinds limit cursor]),
                    :result => result,
                    :refuses => %w[target.not_found target.wrong_kind query.cursor_expired query.limit_invalid],
                    :examples => [{}, { "path" => [1201], "kinds" => %w[group component] }]) { |request| read(request) }
    end

    def read(request)
      params = request.params
      container = OccurrencePath.resolve(request.model, params.fetch("path", []))
      kinds = params.fetch("kinds", KINDS)
      children = container.entities.to_a.select { |entity| kinds.include?(kind(entity)) }
                          .sort_by(&:persistent_id)
      page, next_cursor = Pages.bounded(request, ContextCommands::CHILDREN, children,
                                        :key => ->(entity) { [entity.persistent_id] },
                                        :prepare => ->(rows) { rows.map { |entity| row(container.path, entity) } })
      { "container" => { "path" => container.path, "locked" => container.locked, "hidden" => container.hidden,
                         "shared" => container.shared },
        "children" => page, "next_cursor" => next_cursor, "total" => children.length }
    end

    def kind(entity)
      if entity.is_a?(Sketchup::Group) then "group"
      elsif entity.is_a?(Sketchup::ComponentInstance) then "component"
      elsif entity.is_a?(Sketchup::Face) then "face"
      elsif entity.is_a?(Sketchup::Edge) then "edge"
      else "other"
      end
    end

    # One child as the read names it. A Group's or component's own lock, storage, solidity, definition name
    # and child count; null for what holds nothing.
    def row(parent_path, entity)
      contents = OccurrencePath.contents(entity)
      container = !contents.nil?
      name = entity.respond_to?(:name) ? entity.name.to_s : ""
      { "path" => parent_path + [entity.persistent_id], "persistent_id" => entity.persistent_id,
        "kind" => kind(entity), "type" => entity.typename, "name" => name,
        "definition_name" => container ? definition_name(entity) : nil,
        "hidden" => OccurrencePath.hidden?(entity),
        "locked" => container ? entity.locked? : nil,
        "shared" => container ? OccurrencePath.shared?(entity) : nil,
        "solid" => container ? entity.volume.to_f.positive? : nil,
        "child_count" => container ? contents.length : nil,
        "records" => Records::EntityStore.records_on(entity) }
    end

    def definition_name(entity)
      definition = entity.definition
      definition.respond_to?(:name) ? definition.name.to_s : ""
    end

    def path_param
      { "type" => "array", "items" => { "type" => "integer" },
        "description" => "Persistent ids of the Groups and components from the root to the container, outermost " \
                         "first; [] or absent for the Model root." }
    end

    def kinds_param
      { "type" => "array", "items" => { "type" => "string", "enum" => KINDS }, "minItems" => 1,
        "description" => "Only children of these kinds; every kind when absent." }
    end

    def result
      flag = ->(text) { { "type" => %w[boolean null], "description" => text } }
      record = object({ "dictionary" => { "type" => "string" }, "key" => { "type" => "string" },
                        "claims" => { "type" => "boolean",
                                      "description" => "Whether the record makes the entity its feature's own " \
                                                       "object, which another feature does not build on." } })
      child = object({
        "path" => { "type" => "array", "items" => { "type" => "integer" },
                    "description" => "The child's root-to-entity path, as writes and path reads take it." },
        "persistent_id" => { "type" => "integer" },
        "kind" => { "type" => "string", "enum" => KINDS },
        "type" => { "type" => "string", "description" => "SketchUp's type name, such as Group or Face." },
        "name" => { "type" => "string", "description" => "The instance name; empty if none." },
        "definition_name" => { "type" => %w[string null], "description" => "A Group's or component's definition " \
                                                                           "name; null for anything else." },
        "hidden" => { "type" => "boolean", "description" => "Hidden itself, or on a hidden tag or tag folder." },
        "locked" => flag.call("A Group's or component's own lock; null for anything else."),
        "shared" => flag.call("Component storage, or a Group whose definition another Group shares; null for " \
                              "anything else."),
        "solid" => flag.call("Whether SketchUp reads a Group or component as a closed solid; null for anything else."),
        "child_count" => { "type" => %w[integer null], "minimum" => 0,
                           "description" => "Entities directly inside a Group or component; null for anything else." },
        "records" => list(record, :description => "The registered PH-Composer records on the entity, valid or " \
                                                  "not, by dictionary; empty for none.")
      })
      container = object({
        "path" => { "type" => "array", "items" => { "type" => "integer" } },
        "locked" => { "type" => "boolean", "description" => "A step on the path is locked." },
        "hidden" => { "type" => "boolean", "description" => "A step on the path is hidden." },
        "shared" => { "type" => "boolean", "description" => "A step on the path is shared storage." }
      })
      object({ "container" => container,
               "children" => list(child, :description => "This page, by persistent id."),
               "next_cursor" => Pages::NEXT_CURSOR, "total" => Pages::TOTAL })
    end
    private_class_method :row, :kind, :definition_name, :path_param, :kinds_param, :result
  end
end
