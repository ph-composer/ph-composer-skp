# frozen_string_literal: true

# UI: menus, commands, toolbars, HtmlDialog and the module functions the shell calls.

module UI
  class Menu
    attr_reader :name, :entries, :validation_procs

    def initialize(name)
      @name = name
      @entries = []
      @validation_procs = {}
    end

    def add_submenu(name)
      menu = Menu.new(name)
      @entries << menu
      menu
    end

    def add_item(item, &block)
      entry = block ? [item, block] : item
      @entries << entry
      @entries.length - 1
    end

    def add_separator
      @entries << :separator
    end

    def set_validation_proc(item, &block)
      @validation_procs[item] = block
    end
  end

  class Command
    attr_accessor :menu_text, :tooltip, :status_bar_text, :small_icon, :large_icon
    attr_reader :label

    def initialize(label, &block)
      @label = label
      @block = block
    end

    def call
      @block.call
    end

    def proc
      @block
    end
  end

  class Toolbar
    attr_reader :name, :items, :restored, :shown

    def initialize(name)
      @name = name
      @items = []
      (@@instances ||= []) << self
    end

    def add_item(command)
      @items << command
    end

    def restore
      @restored = true
    end

    def show
      @shown = true
    end

    def get_last_state
      TB_NEVER_SHOWN
    end

    def self.instances
      @@instances ||= []
    end

    def self.reset
      @@instances = []
    end
  end

  class HtmlDialog
    STYLE_DIALOG = 0
    STYLE_WINDOW = 1
    STYLE_UTILITY = 2

    attr_reader :options, :callbacks, :scripts, :file, :url, :html, :bring_to_front_count

    def initialize(options = {})
      @options = options
      @callbacks = {}
      @scripts = []
      @visible = false
      @bring_to_front_count = 0
    end

    def set_file(path)
      @file = path
    end

    def set_url(url)
      @url = url
    end

    def set_html(html)
      @html = html
    end

    def add_action_callback(name, &block)
      @callbacks[name] = block
    end

    def set_on_closed(&block)
      @on_closed = block
    end

    def show
      @visible = true
    end

    def visible?
      @visible
    end

    def bring_to_front
      @bring_to_front_count += 1
    end

    def close
      @visible = false
      @on_closed.call if @on_closed
    end

    def execute_script(script)
      @scripts << script
    end

    def fire(name, payload = nil)
      @callbacks.fetch(name).call(nil, payload)
    end
  end

  # A pending UI.start_timer callback; a repeating one runs again after each call.
  Timer = Struct.new(:id, :repeat, :block, keyword_init: true)

  # Recorded when shown; real SketchUp draws a box beside the Model window, stacked with any still up.
  class Notification
    attr_reader :extension, :message

    def initialize(extension, message = nil, _icon_name = nil, _icon_tooltip = nil)
      @extension = extension
      @message = message
    end

    def show
      UI.notifications << self
      true
    end
  end

  class << self
    attr_reader :opened_urls, :messages, :last_savepanel, :last_openpanel, :context_menu_handlers
    attr_reader :notifications
    attr_writer :open_url_result, :messagebox_result
    attr_writer :inputbox_result
    attr_reader :inputboxes
    attr_reader :created_cursors, :last_cursor

    def create_cursor(path, hot_x, hot_y)
      @created_cursors << [path, hot_x, hot_y]
      @created_cursors.length
    end

    def set_cursor(id)
      @last_cursor = id
      true
    end

    def menu(name)
      (@menus ||= {})[name] ||= Menu.new(name)
    end

    def inputbox(prompts, defaults, lists_or_title, title = nil)
      args = title ? [prompts, defaults, lists_or_title, title] : [prompts, defaults, lists_or_title]
      (@inputboxes ||= []) << args
      @inputbox_result
    end

    def openURL(url)
      (@opened_urls ||= []) << url
      @open_url_result
    end

    def start_timer(interval, repeat = false, &block)
      @next_timer_id ||= 0
      @next_timer_id += 1
      (@timer_intervals ||= {})[@next_timer_id] = interval
      (@timers ||= []) << Timer.new(:id => @next_timer_id, :repeat => repeat, :block => block)
      @next_timer_id
    end

    def add_context_menu_handler(&block)
      (@context_menu_handlers ||= []) << block
      true
    end

    def build_context_menu
      menu = Menu.new("Context")
      (@context_menu_handlers ||= []).each { |handler| handler.call(menu) }
      menu
    end

    def stop_timer(timer_id)
      (@timer_intervals ||= {}).delete(timer_id)
      (@timers ||= []).reject! { |timer| timer.id == timer_id }
      true
    end

    def timer_intervals
      @timer_intervals ||= {}
    end

    def timer_count
      (@timers ||= []).length
    end

    def run_timers(limit = 10_000)
      count = 0
      while (timer = (@timers ||= []).shift)
        timer.block.call
        @timers << timer if timer.repeat
        count += 1
        raise "timer limit exceeded" if count > limit
      end
      count
    end

    def run_timer(timer_id)
      timer = (@timers ||= []).find { |item| item.id == timer_id }
      return false unless timer

      @timers.delete(timer)
      timer.block.call
      true
    end

    def run_next_timer
      timer = (@timers ||= []).shift
      return false unless timer

      timer.block.call
      @timers << timer if timer.repeat
      true
    end

    def messagebox(message, _flags = nil)
      (@messages ||= []) << message
      @messagebox_result || IDYES
    end

    def select_directory(_options = {})
      @selected_directory
    end

    def savepanel(title, directory = nil, filename = nil)
      @last_savepanel = [title, directory, filename]
      @selected_save_path
    end

    def openpanel(title, directory = nil, filename = nil)
      @last_openpanel = [title, directory, filename]
      @selected_open_path
    end

    attr_writer :selected_directory
    attr_writer :selected_save_path
    attr_writer :selected_open_path

    def reset
      @inputbox_result = nil
      @inputboxes = []
      @created_cursors = []
      @last_cursor = nil
      @menus = {}
      @opened_urls = []
      @open_url_result = true
      @messages = []
      @notifications = []
      @messagebox_result = nil
      @timers = []
      @timer_intervals = {}
      @selected_directory = nil
      @selected_save_path = nil
      @selected_open_path = nil
      @last_savepanel = nil
      @last_openpanel = nil
      @next_timer_id = 0
      @context_menu_handlers = []
      Toolbar.reset
    end
  end
end

Sketchup.reset
UI.reset
