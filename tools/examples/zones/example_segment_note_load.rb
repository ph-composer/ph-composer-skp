# frozen_string_literal: true

# The development composition entry for the Building Segment note: its namespace and its settings section. Load
# it into a running host (after PH-Composer has loaded) or a test.
require_relative "example_segment_note"

PhComposer::Registry.install([ExampleSegmentNote]) unless PhComposer::Registry.installed?(ExampleSegmentNote::ID)
PhComposer::Panel.add_development_script(File.join(__dir__, "example_segment_note.js"))
