defmodule Viber.Runtime.Conversation.Context do
  @moduledoc false

  @type t :: %__MODULE__{
          session: GenServer.server(),
          model: String.t(),
          config: term(),
          event_handler: (Viber.Runtime.Conversation.event() -> :ok),
          permission_mode: atom(),
          project_root: String.t(),
          provider_module: module() | nil
        }

  @enforce_keys [:session, :model, :event_handler]
  defstruct [
    :session,
    :model,
    :config,
    :provider_module,
    :event_handler,
    permission_mode: :prompt,
    project_root: "."
  ]
end
