defmodule Viber.Runtime.BrowserAction do
  @moduledoc """
  Typed struct representing a pending browser action dispatched to a browser extension.

  The broker emits these over the SSE stream as `:browser_action` events. The
  extension executes the action and posts the result back to the backend via
  `POST /sessions/:id/browser_action_result`.

  ## Fields

    * `:id` — unique action identifier (UUID-style random string).
    * `:session_id` — session that originated the request.
    * `:tool_name` — name of the browser tool (e.g. `"browser_click"`).
    * `:input` — parsed tool input map.
    * `:inserted_at` — UTC timestamp when the request was registered.
  """

  @type t :: %__MODULE__{
          id: String.t(),
          session_id: String.t() | nil,
          tool_name: String.t(),
          input: map(),
          inserted_at: DateTime.t()
        }

  @enforce_keys [:id, :tool_name, :input]
  defstruct id: nil,
            session_id: nil,
            tool_name: nil,
            input: %{},
            inserted_at: nil

  @spec new(String.t() | nil, String.t(), map()) :: t()
  def new(session_id, tool_name, input) do
    %__MODULE__{
      id: generate_id(),
      session_id: session_id,
      tool_name: tool_name,
      input: input,
      inserted_at: DateTime.utc_now()
    }
  end

  defp generate_id do
    :crypto.strong_rand_bytes(8) |> Base.url_encode64(padding: false)
  end
end
