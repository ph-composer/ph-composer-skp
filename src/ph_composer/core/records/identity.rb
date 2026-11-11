# frozen_string_literal: true

require "securerandom"
require "digest"

module PhComposer
  module Records
    # Record ids are a kind prefix, an underscore and twelve alphanumerics: `exp_Ab12Cd34Ef56`. An id
    # is durable: it survives edits, save and reopen, and a duplicate always receives a new one.
    module Identity
      module_function

      def mint(prefix)
        "#{prefix}_#{SecureRandom.alphanumeric(12)}"
      end

      def pattern(prefix)
        /\A#{Regexp.escape(prefix)}_[A-Za-z0-9]{12}\z/
      end

      # A new id not already in `reserved`, which then reserves it. `identity` names each candidate: random
      # by default, or a `sequence` so that a preview and its invoke stage the same ids.
      def fresh(prefix, reserved, identity = method(:mint))
        loop do
          id = identity.call(prefix)
          next if reserved.include?(id)

          reserved << id
          return id
        end
      end

      # A stable proposal identity for geometry creation. Preview and invoke at the same revision
      # derive the same id without retaining state; a later revision derives another id.
      def derived(prefix, value)
        "#{prefix}_#{Digest::SHA256.hexdigest(CanonicalJson.generate(value))[0, 12]}"
      end

      # A callable that derives the next id for a prefix, for an operation that creates several
      # records. The session, revision, `inputs` and the call's position seed each one, so a preview
      # and its invoke allocate the same ids in the same order and it keeps no state across requests.
      # `inputs` are the operation's arguments, so two different edits at one revision differ.
      def allocator(request, inputs)
        sequence(request.session.id, request.revision) { inputs }
      end

      # The ids `allocator` derives, from a session id, a revision and the inputs its block answers. The block
      # runs once, at the first id, so a request that creates nothing never computes its inputs.
      def sequence(session_id, revision, &inputs)
        position = 0
        seed = nil
        lambda do |prefix|
          seed ||= { "session" => session_id, "revision" => revision, "params" => inputs.call }
          position += 1
          derived(prefix, seed.merge("position" => position))
        end
      end
    end
  end
end
