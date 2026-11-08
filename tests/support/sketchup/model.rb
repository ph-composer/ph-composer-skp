# frozen_string_literal: true

# Sketchup::Model, its transaction and observer behaviour, and the Sketchup module functions.

require_relative "catalogs"

module Sketchup
  class Model
    attr_reader :entities, :operations, :operation_starts, :nested_starts, :path, :selection, :observers, :overlays,
                :active_view, :active_tool, :layers, :pages, :guid, :definitions, :materials
    attr_accessor :title, :shadow_info

    def initialize(dictionaries = {}, entities: Entities.new)
      @dictionaries = dictionaries.each_with_object({}) do |(name, values), result|
        result[name] = AttributeDictionary.new(name, values)
      end
      @entities = entities
      @entities.root = true
      @definitions = DefinitionList.new
      @materials = Materials.new
      @selection = Selection.new(self)
      @overlays = OverlaysManager.new
      @active_view = View.new(self)
      @layers = Layers.new(self)
      @pages = ObservableCollection.new
      @active_path = nil
      @operations = []
      @operation_starts = []
      @nested_starts = []
      @undo_stack = []
      @redo_stack = []
      @current_operation = nil
      @modified = false
      @path = ""
      @title = "Untitled"
      @guid = "model-#{object_id}"
      @shadow_info = {}
      @observers = []
    end

    def attribute_dictionaries
      @dictionaries.values unless @dictionaries.empty?
    end

    def attribute_dictionary(name, create = false)
      return @dictionaries[name] unless create

      @dictionaries[name] ||= AttributeDictionary.new(name)
    end

    def get_attribute(dictionary_name, key, default = nil)
      dictionary = @dictionaries[dictionary_name]
      dictionary ? (dictionary[key].nil? ? default : dictionary[key]) : default
    end

    def set_attribute(dictionary_name, key, value)
      dictionary = (@dictionaries[dictionary_name] ||= AttributeDictionary.new(dictionary_name))
      dictionary[key] = value
      @modified = true
      value
    end

    def delete_attribute(dictionary_name, key = nil)
      if key.nil?
        removed = @dictionaries.delete(dictionary_name)
      else
        dictionary = @dictionaries[dictionary_name]
        removed = dictionary&.delete_key(key)
        @dictionaries.delete(dictionary_name) if dictionary&.empty?
      end
      @modified = true unless removed.nil?
      removed
    end

    def active_path
      @active_path
    end

    def active_path=(value)
      @active_path = value
      @observers.each do |observer|
        observer.onActivePathChanged(self) if observer.respond_to?(:onActivePathChanged)
      end
      value
    end

    # The operation start_operation opened, with the Model state commit or abort returns to.
    OpenOperation = Struct.new(:name, :disable_ui, :transparent, :snapshot, keyword_init: true)

    # A start inside an open operation is refused here and recorded in `nested_starts`; on the host it splits
    # the open operation's Undo step (context/SKETCHUP_HOST_BEHAVIOR.md).
    def start_operation(name, disable_ui = false, next_transparent = false, transparent = false)
      if @current_operation
        @nested_starts << name
        return false
      end

      @operation_starts << [name, disable_ui, next_transparent, transparent]
      @current_operation = OpenOperation.new(:name => name, :disable_ui => disable_ui, :transparent => transparent,
                                             :snapshot => transaction_snapshot)
      true
    end

    def commit_operation
      return false unless @current_operation

      operation = @current_operation
      @undo_stack << operation.snapshot unless operation.transparent && @undo_stack.any?
      @redo_stack.clear unless operation.transparent
      @operations << [operation.name, operation.disable_ui, :committed]
      @current_operation = nil
      @observers.each do |observer|
        observer.onTransactionCommit(self) if observer.respond_to?(:onTransactionCommit)
      end
      true
    end

    # SketchUp 26.1.188 fires onTransactionUndo, not onTransactionAbort, for an aborted operation,
    # synchronously inside the call (context/SKETCHUP_HOST_BEHAVIOR.md, "Observers and edit contexts").
    def abort_operation
      return false unless @current_operation

      operation = @current_operation
      restore_transaction_snapshot(operation.snapshot)
      @operations << [operation.name, operation.disable_ui, :aborted]
      @current_operation = nil
      @observers.each do |observer|
        observer.onTransactionUndo(self) if observer.respond_to?(:onTransactionUndo)
      end
      true
    end

    def undo
      snapshot = @undo_stack.pop
      return false unless snapshot

      @redo_stack << transaction_snapshot
      restore_transaction_snapshot(snapshot)
      @active_path = nil
      @selection.clear
      @observers.each do |observer|
        observer.onTransactionUndo(self) if observer.respond_to?(:onTransactionUndo)
      end
      true
    end

    def redo
      snapshot = @redo_stack.pop
      return false unless snapshot

      @undo_stack << transaction_snapshot
      restore_transaction_snapshot(snapshot)
      @active_path = nil
      @selection.clear
      @observers.each do |observer|
        observer.onTransactionRedo(self) if observer.respond_to?(:onTransactionRedo)
      end
      true
    end

    def active_entities
      path = Array(@active_path)
      return @entities if path.empty?

      container = path.last
      container.respond_to?(:entities) ? container.entities : container.definition.entities
    end

    # The host names the active tool: Select when none is chosen, and "RubyTool" for an extension's own.
    Tools = Struct.new(:model) do
      def active_tool_name
        model.active_tool ? "RubyTool" : "SelectionTool"
      end
    end

    def tools
      Tools.new(self)
    end

    def select_tool(tool)
      previous = @active_tool
      @active_tool = tool
      previous.deactivate(@active_view) if previous && !previous.equal?(tool)
      tool.activate if tool && !previous.equal?(tool)
      self
    end

    def edit_transform
      Array(@active_path).reduce(Geom::Transformation.new) do |transform, entity|
        transform * entity.transformation
      end
    end

    def drawing_element_visible?(path)
      Array(path).all? do |entity|
        (!entity.respond_to?(:hidden?) || !entity.hidden?) &&
          (!entity.respond_to?(:layer) || !entity.layer ||
            !entity.layer.respond_to?(:visible?) || entity.layer.visible?)
      end
    end

    # Fires both save callbacks with the Model's own path unchanged (host evidence 2026-11-07).
    def save_copy(path)
      fire_pre_save
      Sketchup.store_model(path, self)
      @observers.each do |observer|
        observer.onSaveModel(self) if observer.respond_to?(:onSaveModel)
      end
      true
    end

    def save(path = nil)
      raise ArgumentError, "model has no path" if (path.nil? || path.empty?) && @path.empty?

      @path = path unless path.nil? || path.empty?
      fire_pre_save
      Sketchup.store_model(@path, self)
      # A save inside an edit context leaves the Model modified (host evidence 2026-10-16).
      @modified = !Array(@active_path).empty?
      @observers.each do |observer|
        observer.onSaveModel(self) if observer.respond_to?(:onSaveModel)
      end
      true
    end

    # SketchUp 2026.1 reports an empty active path inside onPreSaveModel and restores the edit
    # context afterwards; neither change fires onActivePathChanged. It does not restore a context with
    # a locked Group on its path: the Model is left at the root (host evidence 2026-10-16). An observer
    # that sets a path inside the callback makes SketchUp save the reopened context in world
    # coordinates, so the stub refuses it (host evidence 2026-09-06).
    def fire_pre_save
      restored = @active_path
      @active_path = nil
      @observers.each do |observer|
        observer.onPreSaveModel(self) if observer.respond_to?(:onPreSaveModel)
      end
      unless @active_path.nil?
        raise "active_path changed inside onPreSaveModel; SketchUp saves the reopened context in world coordinates"
      end

      @active_path = Array(restored).any?(&:locked?) ? nil : restored
    end

    def modified?
      @modified
    end

    def add_observer(observer)
      @observers << observer
      true
    end

    def remove_observer(observer)
      @observers.delete(observer)
      true
    end

    def close(_ignore_changes = false)
      @valid = false
      Sketchup.active_model = nil if Sketchup.active_model.equal?(self)
      nil
    end

    def valid?
      @valid != false
    end

    def path=(value)
      @path = value
    end

    def replace_state_from(other)
      other.instance_variables.each do |name|
        instance_variable_set(name, other.instance_variable_get(name))
      end
      self
    end

    def transaction_snapshot
      Marshal.dump([@dictionaries, @entities, @definitions, @materials])
    end

    def restore_transaction_snapshot(snapshot)
      @dictionaries, @entities, @definitions, @materials = Marshal.load(snapshot)
    end
    private :transaction_snapshot, :restore_transaction_snapshot
  end

  class << self
    attr_accessor :active_model, :platform_value, :version_value, :locale_value,
                  :preserve_active_on_open, :reuse_active_model_on_open, :refuse_default_writes
    attr_reader :registered_extensions, :default_writes

    def register_extension(extension, load_on_start)
      (@registered_extensions ||= []) << [extension, load_on_start]
      true
    end

    # The support floor, raised from 2022 on 2026-09-12 (decision 22). Tests that need another
    # host set `Sketchup.version_value` explicitly; the default is what the extension must support.
    def version
      @version_value || "23.0.0"
    end

    def platform
      @platform_value
    end

    def get_locale
      @locale_value || "en-US"
    end

    def find_support_file(name)
      return STUB_PLUGINS_DIR if name == "Plugins"

      nil
    end

    # SketchUp 26.1 stores a string containing a double quote but reads it back as nil.
    def read_default(section, key, default = nil)
      value = (@defaults ||= {}).fetch([section, key], default)
      value.is_a?(String) && value.include?('"') ? nil : value
    end

    # The host answers false when it could not store the value; `refuse_default_writes = true` reproduces
    # that, and `:silently` answers true without storing, so only a read-back can tell.
    def write_default(section, key, value)
      return false if @refuse_default_writes == true
      return true if @refuse_default_writes == :silently

      (@defaults ||= {})[[section, key]] = value
      (@default_writes ||= []) << [section, key, value]
      true
    end

    def clear_default_writes
      @default_writes = []
    end

    def undo
      @active_model.undo
      nil
    end

    def redo
      @active_model.redo
      nil
    end

    # SketchUp's status bar, which is where a modal tool's guidance goes when no panel is open.
    attr_reader :status_texts

    def status_text=(value)
      (@status_texts ||= []) << value
      value
    end

    def add_observer(observer)
      (@observers ||= []) << observer
      true
    end

    def remove_observer(observer)
      (@observers ||= []).delete(observer)
      true
    end

    def store_model(path, model)
      (@saved_models ||= {})[path] = Marshal.dump(model)
    end

    def open_file(path, with_status: false)
      data = (@saved_models ||= {})[path]
      return false unless data

      opened_model = Marshal.load(data)
      opened_model.path = path
      if @reuse_active_model_on_open && @active_model
        @active_model.replace_state_from(opened_model)
        opened_model = @active_model
      else
        @active_model = opened_model unless @preserve_active_on_open
      end
      (@observers ||= []).each do |observer|
        observer.onOpenModel(opened_model) if observer.respond_to?(:onOpenModel)
        unless @reuse_active_model_on_open
          observer.onActivateModel(opened_model) if observer.respond_to?(:onActivateModel)
        end
      end
      with_status ? 0 : true
    end

    def reset
      @version_value = nil
      @active_model = Model.new
      @registered_extensions ||= []
      @defaults = {}
      @default_writes = []
      @refuse_default_writes = false
      @saved_models = {}
      @observers = []
      @platform_value = :platform_osx
      @locale_value = nil
      RegionalSettings.reset
      @preserve_active_on_open = false
      @reuse_active_model_on_open = false
      @status_texts = []
    end
  end
end
