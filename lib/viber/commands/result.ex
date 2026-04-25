defmodule Viber.Commands.Result do
  @moduledoc """
  Canonical return value of a slash command, produced by `Viber.Commands.Dispatcher.invoke/4`.

  Frontends consume the result by:

    * rendering `:text` (a human-readable payload, may be `nil`),
    * forwarding `:events` to the same channel that streams conversation
      events (so `:message_added`, `:usage_updated`, model-change events,
      etc. propagate to remote clients),
    * applying `:state_patch` to local UI state — keys describe abstract
      transitions any frontend should honour.

  Recognised `:state_patch` keys:

    * `:session` — replace the active session pid (e.g. after `/resume`).
    * `:model` — switch the active model (e.g. after `/model <name>`).
    * `:enabled_toolsets` — replace the active toolset list (`/toolset ...`).
    * `:retry_input` — re-send this user input as the next message
      (`/retry`).
    * `:cleared` — session history was cleared.
  """

  alias Viber.Runtime.Event

  @enforce_keys []
  defstruct text: nil, events: [], state_patch: %{}

  @type t :: %__MODULE__{
          text: iodata() | nil,
          events: [Event.t()],
          state_patch: map()
        }

  @doc "Construct a text-only result."
  @spec text(iodata()) :: t()
  def text(text), do: %__MODULE__{text: text}
end
