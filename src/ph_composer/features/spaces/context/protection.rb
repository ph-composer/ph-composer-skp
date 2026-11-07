# frozen_string_literal: true

module PhComposer
  module Spaces
    # A Volume is protected by its own lock: while it is locked a click in the Space selects the whole
    # Volume rather than its Faces. Protection writes only lock state, so it commits directly in a
    # transparent operation that joins the user's step and never aborts (context/TECH_STACK.md, "Join the
    # user's Undo step"); the predecessor's evidence for each rule is linked from that section.
    module Protection
      module_function

      # A Group's transform relative to its parent, read through the open edit context. While a context is
      # open the host reports the Groups on the path as identity and the children of any of them in world
      # coordinates (context/SKETCHUP_HOST_BEHAVIOR.md). A child of the innermost open Group converts
      # through `edit_transform`, which is that Group's world transform; a child of an outer Group on the
      # path cannot be read reliably, nor can a Group on the path, so both answer nil.
      def local_transform(model, entity, parent_ids)
        case placement(model, entity, parent_ids)
        when :closed then entity.transformation
        when :in_open_context then model.edit_transform.inverse * entity.transformation
        end
      end

      # Sets a Group's transform relative to its parent, through the open edit context as above. Answers
      # false, writing nothing, where the transform cannot be read.
      def set_local_transform(model, entity, parent_ids, local)
        case placement(model, entity, parent_ids)
        when :closed then entity.transformation = local
        when :in_open_context then entity.transformation = model.edit_transform * local
        else return false
        end
        true
      end

      # :closed, :in_open_context (a child of the innermost open Group) or :unreadable.
      def placement(model, entity, parent_ids)
        open_ids = Array(model.active_path).map(&:persistent_id)
        return :unreadable if open_ids.include?(entity.persistent_id)
        return :in_open_context if !open_ids.empty? && open_ids == parent_ids
        return :unreadable if open_ids.include?(parent_ids.last)

        :closed
      end

      def volume?(entity)
        entity.is_a?(Sketchup::Group) && !entity.get_attribute(VOLUME_STORE.dictionary, VOLUME_STORE.key).nil?
      end

      def valid?(entity)
        !entity.respond_to?(:valid?) || entity.valid?
      end

      # The innermost Volume on `path`, with its index, or nil.
      def open_volume(path)
        index = Array(path).rindex { |entity| volume?(entity) }
        index && [path[index], index]
      end

      # Locks `volume` in one transparent operation. A lock that cannot be written is put back and the
      # operation still commits, because aborting it would undo the step it joined. Inside an extension
      # operation (Delete Space closing the path) the lock joins that operation instead: a nested start
      # would split its Undo step. Answers whether it wrote.
      def protect(model, volume)
        return false unless volume && valid?(volume) && !volume.locked?

        started = !Sessions.for(model).mutating? && model.start_operation("Protect Volume", true, false, true)
        begin
          volume.locked = true
        rescue StandardError => error
          Diagnostics.exception("space_protect", error)
          begin
            volume.locked = false
          rescue StandardError
            nil
          end
        ensure
          model.commit_operation if started
        end
        true
      end

      # Unlocks `volume` in one transparent operation, the converse of `protect`, for a Volume an Undo has put
      # back on the edit path still locked. Answers whether it wrote.
      def release(model, volume)
        return false unless volume && valid?(volume) && volume.locked?

        started = model.start_operation("Unprotect Volume", true, false, true)
        begin
          volume.locked = false
        rescue StandardError => error
          Diagnostics.exception("space_release", error)
        ensure
          model.commit_operation if started
        end
        !volume.locked?
      end

      # The EditContext boundary: leaving a path that holds an open Volume for one that does not hold it
      # at the same place protects it first. Answers the Volume it left protected, or nil.
      def leaving(model, from, to)
        volume, index = open_volume(from)
        return nil unless volume
        return nil if to.length > index && to[0..index].each_with_index.all? { |entity, i| entity.equal?(from[i]) }

        protect(model, volume)
        volume
      end
    end
  end
end
