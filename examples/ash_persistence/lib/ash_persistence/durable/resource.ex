defmodule AshPersistence.Durable.Resource do
  @moduledoc false

  defmacro run_fields do
    quote do
      attributes do
        uuid_primary_key :id
        attribute :run_id, :string, allow_nil?: false, public?: true
        attribute :reactor_hash, :integer, allow_nil?: false, public?: true
        attribute :reactor_module, :string, allow_nil?: false, public?: true
        attribute :status, :string, allow_nil?: false, public?: true
        attribute :inputs, :map, default: %{}, public?: true
        attribute :persisted_context, :map, default: %{}, public?: true
        attribute :result, :map, public?: true
        attribute :error, :string, public?: true
        attribute :halt_reason, :map, public?: true
        attribute :attempt, :integer, default: 1, allow_nil?: false, public?: true
        create_timestamp :inserted_at
        update_timestamp :updated_at
      end

      identities do
        identity :unique_run_id, [:run_id], pre_check?: true
      end

      actions do
        defaults [:read, :destroy]

        create :create do
          accept [
            :run_id,
            :reactor_hash,
            :reactor_module,
            :status,
            :inputs,
            :persisted_context,
            :result,
            :error,
            :halt_reason,
            :attempt
          ]
        end

        update :update do
          require_atomic? false

          accept [
            :status,
            :inputs,
            :persisted_context,
            :result,
            :error,
            :halt_reason,
            :attempt
          ]
        end
      end
    end
  end

  defmacro step_fields do
    quote do
      attributes do
        uuid_primary_key :id
        attribute :run_id, :string, allow_nil?: false, public?: true
        attribute :step_name, :string, allow_nil?: false, public?: true
        attribute :step_impl, :string, public?: true
        attribute :step_hash, :integer, public?: true
        attribute :status, :string, allow_nil?: false, public?: true
        attribute :attempt, :integer, default: 1, allow_nil?: false, public?: true
        attribute :mode, :string, default: "replayable", allow_nil?: false, public?: true
        attribute :inputs, :map, default: %{}, public?: true
        attribute :output, :map, public?: true
        attribute :error, :string, public?: true
        attribute :halt_payload, :map, public?: true
        attribute :compensation_payload, :map, public?: true
        attribute :undo_payload, :map, public?: true
        create_timestamp :inserted_at
        update_timestamp :updated_at
      end

      identities do
        identity :unique_run_step, [:run_id, :step_name], pre_check?: true
      end

      actions do
        defaults [:read, :destroy]

        create :create do
          accept [
            :run_id,
            :step_name,
            :step_impl,
            :step_hash,
            :status,
            :attempt,
            :mode,
            :inputs,
            :output,
            :error,
            :halt_payload,
            :compensation_payload,
            :undo_payload
          ]
        end

        update :update do
          require_atomic? false

          accept [
            :step_impl,
            :step_hash,
            :status,
            :attempt,
            :mode,
            :inputs,
            :output,
            :error,
            :halt_payload,
            :compensation_payload,
            :undo_payload
          ]
        end
      end
    end
  end

  defmacro event_fields do
    quote do
      attributes do
        uuid_primary_key :id
        attribute :run_id, :string, allow_nil?: false, public?: true
        attribute :step_name, :string, allow_nil?: false, public?: true
        attribute :event_type, :string, allow_nil?: false, public?: true
        attribute :payload, :map, default: %{}, public?: true
        create_timestamp :inserted_at
      end

      actions do
        defaults [:read, :destroy]

        create :create do
          accept [:run_id, :step_name, :event_type, :payload]
        end
      end
    end
  end
end
