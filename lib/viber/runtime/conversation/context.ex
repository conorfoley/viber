defmodule Viber.Runtime.Conversation.Context do
  @moduledoc false

  @type t :: %__MODULE__{
          session: GenServer.server(),
          model: String.t(),
          config: term(),
          event_handler: (Viber.Runtime.Conversation.event() -> :ok),
          permission_mode: atom(),
          project_root: String.t(),
          provider_module: module() | nil,
          task_supervisor: atom(),
          browser_context: map(),
          allowed_tools: MapSet.t(String.t()),
          interrupt: :atomics.atomics_ref() | nil,
          enabled_toolsets: [atom()] | nil
        }

  @enforce_keys [:session, :model, :event_handler]
  defstruct [
    :session,
    :model,
    :config,
    :provider_module,
    :event_handler,
    :interrupt,
    :enabled_toolsets,
    permission_mode: :prompt,
    project_root: ".",
    task_supervisor: Viber.TaskSupervisor,
    browser_context: %{},
    allowed_tools: MapSet.new()
  ]
end
