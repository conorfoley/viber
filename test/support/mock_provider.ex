defmodule Viber.MockProvider do
  @behaviour Viber.API.Provider

  def start(responses) do
    Agent.start_link(fn -> responses end, name: __MODULE__)
  end

  def stop do
    Agent.stop(__MODULE__)
  end

  @impl true
  def send_message(_request) do
    Agent.get_and_update(__MODULE__, fn
      [response | rest] -> {response, rest}
      [] -> {{:error, %Viber.API.Error{type: :api, message: "no more responses"}}, []}
    end)
  end

  @impl true
  def stream_message(_request) do
    {:ok, Stream.map([], & &1)}
  end
end
