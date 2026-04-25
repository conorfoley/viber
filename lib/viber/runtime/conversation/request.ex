defmodule Viber.Runtime.Conversation.Request do
  @moduledoc """
  Typed request payload for `Viber.Runtime.Conversation.run/1`.

  Replaces the historical keyword-list interface so frontends surface
  missing required fields (`:session`, `:model`, `:user_input`) at the
  boundary rather than deep in the conversation loop.

  Construct via `new/1`, which accepts a keyword list or map and
  performs coercion (e.g. browser context normalisation). Required
  fields are enforced via `@enforce_keys`.
  """

  alias Viber.Runtime.BrowserContext

  @type event_handler :: (Viber.Runtime.Event.t() -> :ok)

  @type t :: %__MODULE__{
          session: GenServer.server(),
          model: String.t(),
          user_input: String.t(),
          config: term(),
          event_handler: event_handler(),
          permission_mode: atom(),
          project_root: String.t(),
          provider_module: module() | nil,
          browser_context: BrowserContext.t() | nil,
          interrupt: :atomics.atomics_ref() | nil,
          enabled_toolsets: [atom()] | nil,
          max_iterations: pos_integer() | nil
        }

  @enforce_keys [:session, :model, :user_input]
  defstruct [
    :session,
    :model,
    :user_input,
    :config,
    :provider_module,
    :interrupt,
    :enabled_toolsets,
    :browser_context,
    :max_iterations,
    event_handler: &__MODULE__.__noop_handler__/1,
    permission_mode: :prompt,
    project_root: "."
  ]

  @doc false
  def __noop_handler__(_event), do: :ok

  @doc """
  Build a `%Request{}` from a keyword list or map.

  Raises `ArgumentError` if any of `:session`, `:model`, or
  `:user_input` are missing.
  """
  @spec new(keyword() | map() | t()) :: t()
  def new(%__MODULE__{} = req),
    do: %{req | browser_context: BrowserContext.new(req.browser_context)}

  def new(opts) when is_list(opts), do: new(Map.new(opts))

  def new(opts) when is_map(opts) do
    opts = atomize_keys(opts)

    session = fetch!(opts, :session)
    model = fetch!(opts, :model)
    user_input = fetch!(opts, :user_input)

    %__MODULE__{
      session: session,
      model: model,
      user_input: user_input,
      config: Map.get(opts, :config),
      event_handler: Map.get(opts, :event_handler, &__MODULE__.__noop_handler__/1),
      permission_mode: Map.get(opts, :permission_mode, :prompt),
      project_root: Map.get(opts, :project_root, default_project_root()),
      provider_module: Map.get(opts, :provider_module),
      browser_context: BrowserContext.new(Map.get(opts, :browser_context)),
      interrupt: Map.get(opts, :interrupt),
      enabled_toolsets: Map.get(opts, :enabled_toolsets),
      max_iterations: Map.get(opts, :max_iterations)
    }
  end

  defp atomize_keys(map) do
    Map.new(map, fn
      {k, v} when is_atom(k) -> {k, v}
      {k, v} when is_binary(k) -> {String.to_existing_atom(k), v}
    end)
  end

  defp fetch!(map, key) do
    case Map.fetch(map, key) do
      {:ok, value} ->
        value

      :error ->
        raise ArgumentError, "Conversation.Request: missing required field #{inspect(key)}"
    end
  end

  defp default_project_root do
    case File.cwd() do
      {:ok, cwd} -> cwd
      _ -> "."
    end
  end
end
