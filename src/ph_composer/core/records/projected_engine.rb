# frozen_string_literal: true

module PhComposer
  module Records
    # The engine's read surface as the records will stand once a change set applies, for code that
    # joins another caller's proposal (a library kind owner's callback). Reads go through the change
    # set: a staged create is found, a staged delete is gone. Proposals are accepted only into that
    # change set and only for `writable_kinds`; any other write refuses the whole change set with
    # `refusal_code`. It never applies a change set; the dispatcher's engine does. It does not migrate
    # extension payloads. `projected` derives a further projection from the same root engine for the
    # same change set, which is how a participant delegates to a kind owner's callback.
    class ProjectedEngine
      def initialize(engine, change_set, writable_kinds:, refusal_code:)
        @engine = engine
        @change_set = change_set
        @writable_kinds = writable_kinds
        @refusal_code = refusal_code
      end

      # ---------------------------------------------------------------- reads

      def find(kind_id, id)
        @engine.find(kind_id, id, :change_set => @change_set)
      end

      def ids(kind_id)
        staged = @change_set ? @change_set.writes.select { |write| write.kind == kind_id } : []
        (@engine.ids(kind_id) + staged.select(&:after).map(&:id) - staged.reject(&:after).map(&:id)).uniq
      end

      def kind(kind_id)
        @engine.kind(kind_id)
      end

      def view(kind_id, record)
        @engine.view(kind_id, record)
      end

      def resolve_reference(kind_id, id, reference_plan: nil)
        @engine.resolve_reference(kind_id, id, :reference_plan => reference_plan, :change_set => @change_set)
      end

      def incoming_references(kind_id, id, removing: false, reference_plan: nil)
        @engine.incoming_references(kind_id, id, :change_set => @change_set, :removing => removing,
                                                 :reference_plan => reference_plan)
      end

      def check_identity_removal!(kind_id, id, reference_plan: nil)
        @engine.check_identity_removal!(kind_id, id, :change_set => @change_set, :reference_plan => reference_plan)
      end

      # A nil change set asks for a read-only view (a nested read, a library local read): it keeps this
      # projection's staged view and accepts no write.
      def projected(change_set, writable_kinds:, refusal_code:)
        if change_set.nil?
          raise InternalError, "A read-only projection cannot accept writes." unless writable_kinds.empty?

          return ProjectedEngine.new(@engine, @change_set, :writable_kinds => [], :refusal_code => refusal_code)
        end
        unless @change_set && change_set.equal?(@change_set)
          raise InternalError, "A projection can only be derived for the change set it reads through."
        end

        @engine.projected(change_set, :writable_kinds => writable_kinds, :refusal_code => refusal_code)
      end

      # ---------------------------------------------------------------- proposals

      def propose_create(kind_id, change_set, values:, user_data: nil)
        writable!(kind_id, change_set)
        @engine.propose_create(kind_id, change_set, :values => values, :user_data => user_data)
      end

      def propose_update(kind_id, id, change_set, values: {}, user_data: nil, extension_payloads: {},
                         expected_values: {})
        writable!(kind_id, change_set)
        @engine.propose_update(kind_id, id, change_set,
                               :values => values, :user_data => user_data,
                               :extension_payloads => extension_payloads, :expected_values => expected_values)
      end

      def propose_metadata_update(kind_id, id, change_set, update)
        writable!(kind_id, change_set)
        @engine.propose_metadata_update(kind_id, id, change_set, update)
      end

      def propose_delete(kind_id, id, change_set, expected_values: {}, reference_plan: nil)
        writable!(kind_id, change_set)
        @engine.propose_delete(kind_id, id, change_set, :expected_values => expected_values,
                                                        :reference_plan => reference_plan)
      end

      def propose_duplicate(kind_id, ids, change_set, &values)
        writable!(kind_id, change_set)
        @engine.propose_duplicate(kind_id, ids, change_set, &values)
      end

      private

      def writable!(kind_id, change_set)
        return if @change_set && change_set.equal?(@change_set) && @writable_kinds.include?(kind_id)

        error = CodedError.new(@refusal_code, "This projection cannot stage a #{kind_id} write.")
        @change_set&.refuse(error)
        raise error
      end
    end
  end
end
