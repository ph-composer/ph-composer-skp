# frozen_string_literal: true

require "digest"

module PhComposer
  module ThermalBridges
    module Assignment
      # The explicit discard of one Edge's assignment record that ordinary clear cannot reach: text that is
      # not a JSON object (`unreadable`), or a readable record on an Edge no Zone holds (`stranded`), which
      # clear cannot name because an Edge reference starts from its Zone. Assign and clear stay strict; this
      # names the Edge by its root-to-Edge path and the stored text by its SHA-256 (`fingerprint`), removes
      # this feature's one record and nothing else, as one native operation, and refuses a different text,
      # a locked or shared path, or a record a Zone holds and clear serves.
      module Repair
        CANDIDATES = "#{FEATURE_ID}.edges.repair_candidates".freeze
        ACTION = "#{FEATURE_ID}.edges.repair".freeze
        # The stored text a preview shows is cut to this many characters; the fingerprint covers all of it.
        EXCERPT = 256
        # A readable record's values a reply shows are cut so any record fits: text to a name's length, a
        # value that is not text or a number to its size and digest, and key lists to this many.
        MAX_KEYS = 50
        # A parsed JSON number has no size bound; one longer than this is given by size and digest.
        MAX_NUMBER_BYTES = 64
        # What ordinary clear serves, which this refuses so it never becomes a lax clear.
        NOT_NEEDED = "A Zone holds this Edge and its assignment can be read; clear it with " \
                     "ph_composer.thermal_bridges.edges.clear."
        # How a diagnostic names this route.
        ROUTE = "list them with ph_composer.thermal_bridges.edges.repair_candidates and remove each with " \
                "ph_composer.thermal_bridges.edges.repair"

        # One record as stored: its text (or a non-text value's canonical JSON), digest and parsed form.
        Stored = Struct.new(:text, :fingerprint, :record, keyword_init: true) do
          def readable?
            record.is_a?(Hash)
          end
        end

        module_function

        # One bounded page of every Edge whose assignment clear cannot reach, by path.
        def candidates(request)
          Pages.limit(request.params)
          Pages.position(request, CANDIDATES)
          tagged = []
          Target.each_tagged(request.model) { |edge, path| tagged << [edge, path] }
          rows = containment(request, tagged.map(&:last)).zip(tagged).filter_map do |held, (edge, path)|
            row(request.model, edge, path, held)
          end
          page, next_cursor = Pages.bounded(request, CANDIDATES, rows.sort_by { |row| row.fetch("path") },
                                            :key => ->(row) { row.fetch("path") })
          { "edges" => page, "next_cursor" => next_cursor, "total" => rows.length }
        end

        # The preview and apply of one repair. `path` names the Edge from the root; `fingerprint` is the
        # SHA-256 of the text a candidate read gave.
        def repair(request, proposal, path:, fingerprint:)
          edge = writable_edge(request.model, path)
          stored = stored(edge)
          raise CodedError.new("target.not_found", "That Edge has no thermal-bridge assignment.") unless stored
          unless stored.fingerprint == fingerprint
            raise CodedError.new("target.changed", "The Edge's stored assignment changed since it was read.")
          end

          reason = containment(request, [path]).first.fetch("reason")
          raise CodedError.new("thermal_bridge.repair_not_needed", NOT_NEEDED) if stored.readable? && reason.nil?

          check_references!(request, proposal, path, stored)
          proposal.add_step(RepairStep.new(:path => path, :fingerprint => fingerprint,
                                           :id => stored.readable? ? Assignment.identity(stored.record) : nil),
                            :scopes => [PhComposer::Operations::EntityScope.new(path[0...-1])])
          disclosure(path, stored, reason)
        end

        # The Edge `path` names, reached through no locked or shared storage, for a write.
        def writable_edge(model, path)
          raise CodedError.new("params.invalid", "Name the Edge by a root-to-Edge path.") if path.empty?

          container = OccurrencePath.resolve(model, path[0...-1])
          raise CodedError.new("target.locked",
                               "A Group or component on the Edge's path is locked.") if container.locked
          if container.shared
            raise CodedError.new("target.shared_definition", "The Edge is in shared storage; make its Group or " \
                                                             "component unique first.")
          end

          matches = container.entities.to_a.select { |entity| entity.persistent_id == path.last }
          raise CodedError.new("target.not_found",
                               "No single entity #{path.last} is at that step.") unless matches.length == 1
          raise CodedError.new("target.wrong_kind",
                               "The path does not end at an Edge.") unless matches.first.is_a?(Sketchup::Edge)

          matches.first
        end

        # The record on `edge` as stored, or nil when it has none.
        def stored(edge)
          value = edge.get_attribute(STORE.dictionary, STORE.key)
          return nil if value.nil?

          text = value.is_a?(String) ? value : CanonicalJson.generate(value)
          Stored.new(:text => text, :fingerprint => Digest::SHA256.hexdigest(text.b), :record => parse(value))
        end

        def parse(value)
          value.is_a?(String) ? JSON.parse(value) : nil
        rescue JSON::ParserError
          nil
        end

        # Zones' containment of each root-to-Edge path, in the pages its bound admits.
        def containment(request, paths)
          paths.each_slice(Pages::MAXIMUM_LIMIT).flat_map do |slice|
            request.query(Operations::CONTAINMENT, "paths" => slice).fetch("paths")
          end
        end

        # A candidate row, or nil for a record clear serves.
        def row(model, edge, path, held)
          stored = stored(edge)
          reason = held.fetch("reason")
          return nil if stored.nil? || (stored.readable? && reason.nil?)

          { "path" => path, "condition" => stored.readable? ? "stranded" : "unreadable", "containment" => reason,
            "fingerprint" => stored.fingerprint, "bytes" => stored.text.bytesize,
            "record" => stored.readable? ? shown(stored.record, %w[id thermal_bridge_type_id quantity]) : nil,
            "write_refusal" => write_refusal(model, path) }
        end

        def write_refusal(model, path)
          writable_edge(model, path)
          nil
        rescue CodedError => error
          { "code" => error.code, "message" => error.message }
        end

        # A valid record whose id no other Edge keeps may be named by another record; removing it then refuses
        # reference.in_use, as clear's does. The engine's check reads every assignment to prove that; text on
        # another Edge that is not a JSON object names nothing, so the check passes over it (Target.entries).
        def check_references!(request, proposal, path, stored)
          return unless stored.readable? && RECORD_KIND.problems(stored.record).empty?

          id = stored.record.fetch("id")
          return if Target.readable_ids(request.model).count(id) > 1

          removal = { "reference" => { "zone_id" => nil, "zone_path" => [], "entity_path" => path, "entity_id" => id },
                      "before" => stored.record, "after" => nil, "change" => "removed" }
          request.engine.check_identity_removal!(EDGE_KIND, id, :change_set => proposal.record_changes,
                                                                :reference_plan => Operations.plan([removal]))
        end

        # What the repair discards, for the reviewer: the stored text's size, digest and opening characters and,
        # when it can be read, the values and metadata it held.
        def disclosure(path, stored, reason)
          record = stored.record if stored.readable?
          {
            "path" => path, "condition" => record ? "stranded" : "unreadable", "containment" => reason,
            "stored" => { "bytes" => stored.text.bytesize, "sha256" => stored.fingerprint, "readable" => !record.nil?,
                          "valid" => record ? RECORD_KIND.problems(record).empty? : false,
                          "excerpt" => stored.text.scrub[0, EXCERPT] },
            "discarded" => record && shown(record, %w[id thermal_bridge_type_id quantity]).merge(
              keys(record["user_data"], "user_data_keys")
            ).merge(keys(record["extension_data"], "extension_namespaces"))
          }
        end

        # `fields` of a readable record as a reply can carry them, each cut named in `truncated`.
        def shown(record, fields)
          cut = []
          values = fields.to_h do |field|
            value = record[field]
            if value.is_a?(String) && value.length > OccurrencePath::NAME_CHARACTERS
              cut << field
              value = value[0, OccurrencePath::NAME_CHARACTERS]
            elsif !(value.nil? || value.is_a?(String) || value.is_a?(Numeric)) ||
                  (value.is_a?(Numeric) && JSON.generate(value).bytesize > MAX_NUMBER_BYTES)
              cut << field
              value = Fragments.summary(value)
            end
            [field, value]
          end
          cut.empty? ? values : values.merge("truncated" => cut)
        end

        # The first MAX_KEYS keys of a metadata map, each cut, and how many it holds.
        def keys(map, name)
          names = map.is_a?(Hash) ? map.keys.sort : []
          { name => names.first(MAX_KEYS).map { |key| key[0, OccurrencePath::NAME_CHARACTERS] },
            "#{name.chomp('s')}_total" => names.length }
        end
        private_class_method :parse, :row, :write_refusal, :check_references!, :disclosure, :shown, :keys
      end

      # The one write a repair makes: re-resolve the Edge, refuse any stored text but the reviewed one, and
      # delete this feature's record key, leaving geometry and every other dictionary as they were.
      class RepairStep
        attr_reader :affected

        def initialize(path:, fingerprint:, id:)
          @path = path.dup.freeze
          @fingerprint = fingerprint
          @affected = [{ "kind" => "edge", "id" => id, "change" => "removed", "path" => @path }].freeze
        end

        def descriptor
          { "name" => "thermal_bridge_edge_repair", "path" => @path, "fingerprint" => @fingerprint }
        end

        def temporary_ids
          []
        end

        def apply(model, _slots)
          edge = Repair.writable_edge(model, @path)
          unless Repair.stored(edge)&.fingerprint == @fingerprint
            raise CodedError.new("target.changed", "The Edge's stored assignment changed after the repair was planned.")
          end

          STORE.delete(edge)
        end
      end
    end
  end
end
