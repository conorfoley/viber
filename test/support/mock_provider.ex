defmodule Viber.MockProvider do
  @moduledoc """
  A test double for `Viber.API.Provider`.

  Each response in the list passed to `start/1` must be a pre-wrapped tuple,
  i.e. `{:ok, %Viber.API.MessageResponse{}}` or `{:error, %Viber.API.Error{}}`.

  Because the module is referenced by name as a provider, only one instance can
  be alive at a time. Tests that use this mock must therefore run with
  `async: false`.
  """

  @behaviour Viber.API.Provider

  @spec start([{:ok, Viber.API.MessageResponse.t()} | {:error, Viber.API.Error.t()}]) ::
          {:ok, pid()} | {:error, term()}
  def start(responses) when is_list(responses) do
    Agent.start_link(fn -> responses end, name: __MODULE__)
  end

  @spec stop() :: :ok
  def stop do
    Agent.stop(__MODULE__)
  end

  @impl true
  def send_message(_request) do
    Agent.get_and_update(__MODULE__, fn
      [response | rest] -> {response, rest}
      [] -> {{:error, %Viber.API.Error{type: :api, message: "no more mock responses"}}, []}
    end)
  end

  @impl true
  def stream_message(_request) do
    raise "#{__MODULE__}.stream_message/1 is not implemented — define an inline provider module in your test"
  end
end
