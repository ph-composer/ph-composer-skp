# frozen_string_literal: true

require "digest"
require "fileutils"
require "securerandom"
require "time"
require "tmpdir"
require_relative "inline_image"

module PhComposer
  # An image of the current view, written by SketchUp's own View#write_image and read by the agent with
  # its own tools (context/AGENT_INTERFACE.md, "Focused reads and visual context"). Registered as a
  # foundation capability under its own grant, `capture`, because it can show anything in the viewport.
  # It renders the Model's geometry only: no overlay, tool drawing or panel (measured on 26.1.188), which
  # the result says as `overlays`. It moves nothing: no zoom, selection or path change.
  #
  # Each session keeps at most MAX_KEPT captures for KEEP_SECONDS in its own folder under the system
  # temporary directory; older ones are deleted by the next capture, and nothing outside that folder.
  # With `inline`, the result also carries the PNG itself (InlineImage), which an agent connection sends as an
  # image content block; every capture fits one, since a capture larger than that refuses.
  module CaptureCommand
    FEATURE_ID = "ph_composer.view"
    CAPTURE = "#{FEATURE_ID}.capture"
    MAX_SIDE = 4096
    MAX_BYTES = InlineImage::MAX_BYTES
    MAX_KEPT = 4
    KEEP_SECONDS = 15 * 60
    CODES = {
      "capture.failed" => "SketchUp did not write the image.",
      "capture.view_changed" => "The view changed while the image was written; capture again.",
      "capture.too_large" => "The image is larger than a capture may be; ask for fewer pixels."
    }.freeze

    module_function

    def install(registry)
      feature = registry.feature(FEATURE_ID, :contract_version => Declarations::CONTRACT_VERSION)
      CODES.each { |code, description| feature.code(code, :description => description) }
      side = { "type" => "integer", "minimum" => 64, "maximum" => MAX_SIDE,
               "description" => "Pixels; give width and height together, or neither for the viewport's size." }
      inline = { "type" => "boolean", "description" => "Also answer the PNG itself as inline_image, which an agent " \
                                                       "connection sends as an image content block." }
      feature.view_command(CAPTURE, :capability => "capture",
                                    :description => "Write a PNG of the current view at the current camera and " \
                                                    "answer its path, hash and what it shows, and with inline the " \
                                                    "image itself. Geometry only.",
                                    :params => object({ "width" => side, "height" => side, "inline" => inline },
                                                      %w[width height inline]),
                                    :result => result, :refuses => CODES.keys,
                                    :side_effects => "Writes one image file to a temporary folder; deletes this " \
                                                     "session's captures older than 15 minutes or beyond the " \
                                                     "newest four. Nothing in the Model or the view changes.",
                                    :examples => [{}, { "width" => 1600, "height" => 1000 },
                                                  { "width" => 1200, "height" => 800, "inline" => true }]) do |request|
        capture(request)
      end
    end

    def capture(request)
      session = request.session
      view = session.model.active_view
      before = [session.view_generation, session.revision]
      width, height = size(request.params, view)
      folder = folder_for(session)
      path = File.join(folder, "cap_#{SecureRandom.hex(8)}.png")
      written = begin
        view.write_image(:filename => path, :width => width, :height => height, :antialias => true,
                         :transparent => false)
      rescue StandardError
        false
      end
      fail_with(path, "capture.failed") unless written && File.file?(path)

      check!(path, before, session, [width, height])
      bytes = File.binread(path)
      value = { "path" => path, "sha256" => Digest::SHA256.hexdigest(bytes), "bytes" => bytes.bytesize,
                "width" => width, "height" => height, "captured_at" => Time.now.utc.iso8601,
                "provenance" => provenance(session), "overlays" => "not_included" }
      value[InlineImage::KEY] = InlineImage.of(bytes) if request.params["inline"]
      value
    ensure
      prune(folder) if folder
    end

    # Removes whatever this attempt left, a partial file included, and refuses with `code`.
    def fail_with(path, code, message = CODES.fetch(code), detail = nil)
      File.delete(path) if File.exist?(path)
      raise CodedError.new(code, message, detail)
    end

    # Refuses, and removes the file, when the view moved during the write or the image is too large. A too-large
    # refusal names a smaller size to ask for: the pixel count scaled by the byte overshoot, with a margin, since
    # a PNG's size follows its pixel count only roughly.
    def check!(path, before, session, sides)
      fail_with(path, "capture.view_changed") if [session.view_generation, session.revision] != before
      size = File.size(path)
      return if size <= MAX_BYTES

      scale = Math.sqrt(MAX_BYTES.to_f / size) * 0.9
      width, height = sides.map { |side| (side * scale).floor.clamp(64, MAX_SIDE) }
      fail_with(path, "capture.too_large", "The image is #{size} bytes, over the #{MAX_BYTES}-byte limit of a " \
                                           "capture; ask for about #{width} by #{height} pixels.",
                { "bytes" => size, "max_bytes" => MAX_BYTES, "width" => width, "height" => height })
    end

    # The asked size, or the viewport's own clamped to MAX_SIDE.
    def size(params, view)
      asked = params.values_at("width", "height").compact
      return asked if asked.length == 2
      raise CodedError.new("params.invalid", "Give both width and height, or neither.") if asked.length == 1

      [view.vpwidth, view.vpheight].map { |side| side.to_i.clamp(64, MAX_SIDE) }
    end

    def provenance(session)
      model = session.model
      selected = model.selection.to_a.map(&:persistent_id).sort
      { "session" => session.id, "revision" => session.revision, "view_generation" => session.view_generation,
        "camera" => ContextCommands.camera(model), "edit_path" => EditContext.current_ids(model),
        "selection_digest" => Digest::SHA256.hexdigest(selected.join(",")) }
    end

    def folder_for(session)
      folder = File.join(Dir.tmpdir, "ph_composer", "captures", session.id)
      FileUtils.mkdir_p(folder)
      folder
    end

    # Deletes this session's captures older than KEEP_SECONDS and all but the MAX_KEPT newest.
    def prune(folder)
      files = Dir.glob(File.join(folder, "cap_*.png")).sort_by { |file| File.mtime(file) }
      old, recent = files.partition { |file| Time.now - File.mtime(file) > KEEP_SECONDS }
      (old + recent[0...[recent.length - MAX_KEPT, 0].max]).each { |file| File.delete(file) }
    end

    def object(properties, optional)
      { "type" => "object", "additionalProperties" => false, "properties" => properties,
        "required" => properties.keys - optional }
    end

    def result
      text = { "type" => "string" }
      count = { "type" => "integer" }
      { "type" => "object", "additionalProperties" => false,
        "required" => %w[path sha256 bytes width height captured_at provenance overlays],
        "properties" => {
          "path" => text.merge("description" => "The PNG, for you to read with your own tools."),
          "sha256" => text, "bytes" => count, "width" => count, "height" => count, "captured_at" => text,
          "provenance" => { "type" => "object", "description" => "The session, revision, view generation, " \
                                                                 "camera, edit path and a selection digest " \
                                                                 "the image was taken at." },
          "overlays" => { "type" => "string", "enum" => ["not_included"],
                          "description" => "PH-Composer's overlays, tool drawing and panels are not in the image." },
          InlineImage::KEY => InlineImage::SCHEMA
        } }
    end
  end
end
