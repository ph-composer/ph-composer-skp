# frozen_string_literal: true

module PhComposer
  # How a native client, the panel or a menu, asks the user for the location a setup command or file
  # export declares (Declarations::Approval) and then calls it. The dialogs live here, outside every
  # handler, so a scripted caller of the same operation is refused at once instead of blocking
  # SketchUp on a dialog nobody is watching (context/AGENT_INTERFACE.md, "Host lifecycle"). A
  # declaration without an approval runs as the public API would run it.
  module NativeApproval
    # The location the user chose and, for a save destination that already exists, whether they agreed
    # to replace it. It never enters params, a result or a log. From an approved location
    # (shell/approved_locations.rb) it also carries the location's id and label and `state`, the
    # destination state the caller reviewed; from a native dialog those are nil, and the consent was
    # given against the destination as it is now.
    Granted = Struct.new(:path, :replace, :state, :label, :location_id, keyword_init: true) do
      def inspect
        "#<#{self.class.name}>"
      end
      alias_method :to_s, :inspect

      # Printing or serializing an approval never shows its path; read `path` explicitly.
      def to_h
        { "replace" => replace }
      end
      alias_method :to_a, :to_h
    end

    NOUNS = { "save_file" => "destination file", "open_file" => "file", "open_folder" => "folder" }.freeze

    module_function

    def setup(context, name, params)
      dispatch = Dispatch.new
      refusal = -> { dispatch.setup_refusal(context, name, params) }
      call(context, Registry.current.setup_commands[name], refusal) do |approval|
        dispatch.setup(context, name, params, :approval => approval)
      end
    end

    def file_export(context, name, params)
      dispatch = Dispatch.new
      refusal = -> { dispatch.file_export_refusal(context, name, params) }
      call(context, Registry.current.file_exports[name], refusal) do |approval|
        dispatch.file_export(context, name, params, :approval => approval)
      end
    end

    def noun(approval)
      NOUNS.fetch(approval.kind)
    end

    # Dispatch's answer to a declared location: the native client's Granted, which wins, or the one an
    # approved location in params stands for, with `params` less that location, which the handler never
    # sees. With neither, it refuses with access.user_required: a location only the user can choose
    # arrives from them or not at all.
    def admit(declaration, approval, params)
      needed = declaration.respond_to?(:approval) && declaration.approval
      return [approval, params] unless needed

      location = params["location"]
      params = params.reject { |key, _value| key == "location" }
      return [approval, params] if approval
      return [ApprovedLocations.grant(location, needed.kind), params] if location

      raise CodedError.new("access.user_required", user_required(declaration.name, needed))
    end

    # The refusal a caller without a native dialog gets, naming where the user approves the location so
    # the caller can tell them.
    def user_required(name, approval)
      where = LocationCommands::WHERE.fetch(approval.kind)
      if approval.standing
        where = "#{LocationCommands::EXPORT_TAB}#{where}" if approval.kind == "save_file"
        return "#{name} needs the user, so no dialog was opened. Ask them to approve one in SketchUp (#{where}), " \
               "then find its id in ph_composer.locations.list."
      end

      named = File.extname(approval.default_name.to_s)
      named = named.empty? ? "" : ", named with #{named}"
      "#{name} needs the user to choose a #{noun(approval)} in SketchUp, from the PH-Composer panel or menu, or a " \
        "location they approved, passed as location. No dialog was opened. They approve one in SketchUp " \
        "(#{where}#{named})."
    end

    # The dispatch outcome, or a cancellation when the user dismissed a dialog. An unknown name or a
    # closed session opens no dialog and is dispatch's to refuse. The grant, params and busy state are
    # checked through `refusal` before the dialog opens, and again by dispatch after it, since the
    # session can change while the dialog is open.
    def call(context, declaration, refusal)
      approval = declaration&.approval
      session = context.is_a?(OperationContext) && Sessions.find(context.session_id)
      return yield(nil) unless approval && session

      refused = refusal.call
      return refused if refused

      granted = ask(approval, session.model)
      return cancelled(session) unless granted

      yield granted
    end

    # A Granted from the native dialog for `approval`, or nil when the user cancelled it.
    def ask(approval, model)
      case approval.kind
      when "save_file" then save_destination(approval, model)
      when "open_file" then present(UI.openpanel(approval.title, nil, approval.filter || "*.*"))
      when "open_folder" then present(UI.select_directory(:title => approval.title))
      end
    end

    def save_destination(approval, model)
      directory = model.path.to_s.empty? ? nil : File.dirname(model.path)
      path = UI.savepanel(approval.title, directory, approval.default_name)
      return nil if path.nil?

      path = with_extension(path, approval.default_name) if approval.standing

      return nil unless approval.standing || confirm_replace(path, "Replace the existing file?")

      Granted.new(:path => path, :replace => File.exist?(path))
    end

    # Whether the user agrees to replace what exists at `path`, chosen in the Save dialog; true when it
    # does not exist. The macOS Save sheet has already asked about the file it names, so on macOS this
    # asks nothing. Elsewhere `question` asks once, until the Windows Save dialog is checked.
    def confirm_replace(path, question)
      return true unless File.exist?(path)
      return true if Sketchup.platform == :platform_osx

      UI.messagebox(question, MB_YESNO) == IDYES
    end

    # A name that does not end in the extension the dialog offered takes it, so an approved export
    # destination is never kept under a name its export would refuse; one ending in that extension or
    # `.json` (a library export's destination), in any case, keeps it. A dot inside a name ("v1.2") is
    # not an extension. Only for a standing approval, which writes nothing: after a Save dialog that
    # writes now, the sheet's own replace question covered the name as typed, not the one with an
    # extension added.
    def with_extension(path, default_name)
      extension = File.extname(default_name.to_s)
      return path if extension.empty?

      kept = [extension, ".json"].any? { |ending| path.downcase.end_with?(ending.downcase) }
      kept ? path : "#{path.chomp('.')}#{extension}"
    end

    def present(path)
      path && Granted.new(:path => path, :replace => false)
    end

    def cancelled(session)
      Outcome.build("cancelled", "request.cancelled", "Cancelled. Nothing changed.", "none", session.revision)
    end
    private_class_method :call, :ask, :save_destination, :with_extension, :present, :cancelled
  end
end
