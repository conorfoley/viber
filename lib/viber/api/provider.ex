defmodule Viber.API.Provider do
  @moduledoc """
  Behaviour for LLM provider implementations.
  """

  @type stream_event :: Viber.API.Types.stream_event()

  @callback send_message(request :: Viber.API.MessageRequest.t()) ::
              {:ok, Viber.API.MessageResponse.t()} | {:error, Viber.API.Error.t()}

  @callback stream_message(request :: Viber.API.MessageRequest.t()) ::
              {:ok, Enumerable.t()} | {:error, Viber.API.Error.t()}
end
