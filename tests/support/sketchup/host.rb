# frozen_string_literal: true

# The process-level surface: the load-path shim SketchUp's own `require "sketchup.rb"`
# resolves against, the numeric host constants, and SketchupExtension.

# frozen_string_literal: true

STUB_LOAD_DIR = Dir.mktmpdir("ph-composer-sketchup-stub")
STUB_PLUGINS_DIR = File.join(STUB_LOAD_DIR, "Plugins")
FileUtils.mkdir_p(STUB_PLUGINS_DIR)
File.write(File.join(STUB_LOAD_DIR, "sketchup.rb"), "")
File.write(File.join(STUB_LOAD_DIR, "extensions.rb"), "")
$LOAD_PATH.unshift(STUB_LOAD_DIR)
# The cleanup runs through Minitest.after_run, not at_exit: at_exit handlers run in reverse
# registration order, so this one would fire before Minitest runs a single test and delete
# `sketchup.rb` out from under a test that re-loads the extension (measured on Ruby 2.7.2).

MF_CHECKED = 1 unless defined?(MF_CHECKED)
MF_UNCHECKED = 0 unless defined?(MF_UNCHECKED)
MF_ENABLED = 0 unless defined?(MF_ENABLED)
MF_GRAYED = 1 unless defined?(MF_GRAYED)
TB_NEVER_SHOWN = -1 unless defined?(TB_NEVER_SHOWN)
MB_YESNO = 4 unless defined?(MB_YESNO)
IDYES = 6 unless defined?(IDYES)
IDNO = 7 unless defined?(IDNO)
GL_LINES = 1 unless defined?(GL_LINES)
SB_PROMPT = 0 unless defined?(SB_PROMPT)
SB_VCB_LABEL = 1 unless defined?(SB_VCB_LABEL)
MK_LBUTTON = 1 unless defined?(MK_LBUTTON)
# The modifier masks a tool callback's `flags` carries. These are the host's own values, measured on
# 26.1.188, 2026-09-20: a plain click arrived as 2 and a Shift-click as 131074.
CONSTRAIN_MODIFIER_MASK = 131_072 unless defined?(CONSTRAIN_MODIFIER_MASK)
COPY_MODIFIER_MASK = 524_288 unless defined?(COPY_MODIFIER_MASK)
ALT_MODIFIER_MASK = 1_048_576 unless defined?(ALT_MODIFIER_MASK)
GL_TRIANGLES = 4 unless defined?(GL_TRIANGLES)
SnapTo_Arbitrary = 0 unless defined?(SnapTo_Arbitrary)

$stub_loaded_files = {}

def file_loaded?(path)
  $stub_loaded_files.key?(path)
end

def file_loaded(path)
  $stub_loaded_files[path] = true
end

class SketchupExtension
  attr_accessor :version, :creator, :copyright, :description
  attr_reader :name, :path

  def initialize(name, path)
    @name = name
    @path = path
  end
end
