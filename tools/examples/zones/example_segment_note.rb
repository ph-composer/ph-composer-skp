# frozen_string_literal: true

# A development-only Building Segment settings namespace: the Ruby half of the smallest settings section an
# outside feature adds to the Building Segment settings dialog (context/EXTENSIBILITY.md, "Building Segment
# settings"). It registers one structured extension, a note, with its validator. Zones' Save
# (ph_composer.zones.save_segment_settings) checks each payload with that validator and stores it on the Segment;
# this feature writes no record of its own. The panel half is example_segment_note.js beside this file.
#
# It never ships. Load both halves into a running host, or a test, with:
#
#   load "<repo>/tools/examples/zones/example_segment_note_load.rb"
module ExampleSegmentNote
  ID = "example.segment"
  NAMESPACE = "#{ID}.note"

  NOTE = PhComposer::Records::Extension.new(
    :namespace => NAMESPACE, :schema_version => 1, :export_relevance => "local_only",
    :validate => lambda do |payload|
      payload["text"].is_a?(String) && !payload["text"].strip.empty? ? [] : ["text must be a nonempty string"]
    end
  )

  module_function

  def install(registry)
    feature = registry.feature(ID, :contract_version => 1, :requires => ["ph_composer.zones"])
    feature.extension(NOTE)
  end
end
