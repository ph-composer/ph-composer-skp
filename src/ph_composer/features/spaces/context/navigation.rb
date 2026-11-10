# frozen_string_literal: true

module PhComposer
  module Spaces
    # Moving the edit context through the Space hierarchy, Unprotect and Restore position. Every path
    # change goes through EditContext, whose boundary protects a Volume being left: the same automatic
    # work the reconciler does on a path change, not a write of the command's. Opening a protected Volume
    # takes two calls, because a view command writes nothing: `volumes.unprotect`, an action with its own
    # Undo step, then `context.open`.
    module Navigation
      # Matching transforms within this many inches read as unmoved.
      TOLERANCE = 1.0e-6

      module_function

      def entities_for(model, ids)
        entities = model.entities
        ids.map do |persistent_id|
          entity = entities.to_a.find { |candidate| candidate.persistent_id == persistent_id }
          raise CodedError.new("target.not_found", "That occurrence no longer exists.") unless entity

          entities = entity.is_a?(Sketchup::ComponentInstance) ? entity.definition.entities : entity.entities
          entity
        end
      end

      # Opens a Space, or a Volume already unprotected, as the edit context; a Volume being left is
      # protected first. SketchUp opens no locked Group, so a protected Volume refuses until
      # `volumes.unprotect` has unlocked it, and a lock the user set on the target or above it refuses.
      def open(request, reference:)
        model = request.model
        if Resolve.kind_of(reference) == FLOOR_SEGMENT_KIND
          raise CodedError.new("params.invalid", "Open takes a Space or a Volume; locate a Floor Segment instead.")
        end

        occurrence = Resolve.occurrence(Occurrences.scan(model), reference, :mutable => false)
        EditContext.shown!(model) unless EditContext.current_ids(model) == occurrence.path
        raise CodedError.new("target.locked", "That occurrence or a Group above it is locked.") if occurrence.locked
        if occurrence.entity.locked?
          raise CodedError.new("space.volume_protected", "The Volume is protected. Unprotect it before opening it.")
        end

        EditContext.enter(model, entities_for(model, occurrence.path))
        { "path" => occurrence.path }
      end

      # Leaves the innermost Space or Volume on the path for its parent.
      def close(request)
        model = request.model
        path = EditContext.current(model)
        index = path.rindex { |entity| Protection.volume?(entity) || space?(entity) }
        EditContext.shown!(model) if index
        EditContext.enter(model, path[0...index]) if index
        { "path" => EditContext.current_ids(model) }
      end

      # Unlocks a protected Volume so it can be opened, as its own Undo step. A Volume the user locked
      # from above refuses. The edit context does not move: `context.open` opens it.
      def unprotect(request, proposal, volume:)
        occurrence = Resolve.occurrence(Occurrences.scan(request.model), volume, :mutable => true)
        locked = occurrence.entity.locked?
        if locked
          proposal.add_step(UnprotectStep.new(:path => occurrence.path, :before => occurrence.record),
                            :scopes => [Operations::EntityScope.new(occurrence.path[0...-1])])
        end
        { "volume_id" => occurrence.record.fetch("id"), "unprotected" => locked }
      end

      # Selects and frames one Space, Volume or Floor Segment, and never unlocks anything. SketchUp opens
      # no locked Group and selects nothing outside the open context, so the path opens up to the first
      # locked Group on the way, a protected Volume included, and that Group is selected in place of the
      # target; the target is still the one framed.
      def locate(request, reference:)
        model = request.model
        EditContext.shown!(model)
        occurrence = Resolve.occurrence(Occurrences.scan(model), reference, :mutable => false)
        entities = entities_for(model, occurrence.path[0...-1]) + [occurrence.entity]
        stop = entities[0...-1].index { |entity| entity.respond_to?(:locked?) && entity.locked? }
        EditContext.enter(model, stop ? entities[0...stop] : entities[0...-1])
        model.selection.clear
        model.selection.add(stop ? entities[stop] : occurrence.entity)
        model.active_view.zoom(occurrence.entity) if model.active_view.respond_to?(:zoom)
        { "path" => EditContext.current_ids(model) }
      end

      def space?(entity)
        entity.is_a?(Sketchup::Group) && !entity.get_attribute(SPACE_STORE.dictionary, SPACE_STORE.key).nil?
      end

      # Whether a Volume stands where its record says it was left. A Volume open on the path reports its
      # transform in world coordinates, so it is not compared.
      def moved?(model, occurrence)
        home = occurrence.record["home_transform"]
        local = home && Protection.local_transform(model, occurrence.entity, occurrence.path[0...-1])
        return false unless local

        local.to_a.zip(home).any? { |actual, stored| (actual - stored).abs > TOLERANCE }
      end
    end

    # Unlocks one protected Volume, guarded by the record last read; the write contract holds at apply as
    # at planning.
    class UnprotectStep
      attr_reader :affected

      def initialize(path:, before:)
        @path = path.dup.freeze
        @before = DeepCopy.frozen(before)
        @affected = [{ "kind" => VOLUME_KIND, "id" => before.fetch("id"), "change" => "updated",
                       "reference" => { "volume_id" => before.fetch("id"), "entity_path" => @path } }]
        @unlocked = nil
      end

      def descriptor
        { "name" => "unprotect_volume", "path" => @path, "before" => @before }
      end

      def apply(model, _slots)
        reference = { "volume_id" => @before.fetch("id"), "entity_path" => @path }
        volume = Resolve.occurrence(Occurrences.scan(model), reference, :mutable => true)
        unless volume.record == @before
          raise CodedError.new("target.changed", "The Volume changed after it was previewed. Nothing was written.")
        end
        return unless volume.entity.locked?

        volume.entity.locked = false
        @unlocked = volume.entity
      end

      def restore
        @unlocked.locked = true if @unlocked && Protection.valid?(@unlocked)
      end
    end

    # Puts a moved Volume back where its record says it was left, and protects it.
    class RestorePositionStep
      attr_reader :affected

      def initialize(path:, before:)
        @path = path.dup.freeze
        @before = DeepCopy.frozen(before)
        @affected = [{ "kind" => VOLUME_KIND, "id" => before.fetch("id"), "change" => "updated",
                       "reference" => { "volume_id" => before.fetch("id"), "entity_path" => @path } }]
      end

      def descriptor
        { "name" => "restore_volume_position", "path" => @path, "before" => @before }
      end

      def apply(model, _slots)
        volume = Occurrences.entity_at(model, @path)
        unless volume.is_a?(Sketchup::Group) && VOLUME_STORE.read(volume) == @before
          raise CodedError.new("target.changed", "The Volume changed after it was previewed. Nothing was written.")
        end

        home = Geom::Transformation.new(@before.fetch("home_transform"))
        if Protection.placement(model, volume, @path[0...-1]) == :unreadable
          raise CodedError.new("space.volume_open", "The Volume's context opened before it was restored.")
        end

        volume.locked = false
        Protection.set_local_transform(model, volume, @path[0...-1], home)
        volume.locked = true
      end
    end
  end
end
