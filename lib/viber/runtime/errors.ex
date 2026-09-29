defmodule Viber.Runtime.Errors do
  @moduledoc """
  Conventions for error reasons at Viber's public boundaries.

  An error reason is a term, never pre-rendered text:

    * a `raise` keeps its exception struct,
    * a `throw` or `exit` is `{:throw, value}` / `{:exit, value}`,
    * each tag has one shape.

  Reasons are turned into text only at the edges (renderer, SSE, gateway,
  tool output shown to the model) via `message/1`.
  """

  alias Viber.API.Error, as: APIError

  @type caught :: Exception.t() | {:throw, term()} | {:exit, term()}

  @spec from_caught(:error | :throw | :exit, term(), Exception.stacktrace()) :: caught()
  def from_caught(kind, value, stacktrace \\ [])

  def from_caught(:error, value, stacktrace), do: Exception.normalize(:error, value, stacktrace)
  def from_caught(:throw, value, _stacktrace), do: {:throw, value}
  def from_caught(:exit, value, _stacktrace), do: {:exit, value}

  @spec retryable?(term()) :: boolean()
  def retryable?(%APIError{} = err), do: APIError.retryable?(err)
  def retryable?({:stream_error, reason}), do: retryable?(reason)
  def retryable?(_), do: false

  @spec context_window_exceeded?(term()) :: boolean()
  def context_window_exceeded?(%APIError{} = err), do: APIError.context_window_exceeded?(err)
  def context_window_exceeded?({:stream_error, reason}), do: context_window_exceeded?(reason)
  def context_window_exceeded?(_), do: false

  @spec message(term()) :: String.t()
  def message(reason) when is_binary(reason), do: reason
  def message(%APIError{message: msg}), do: msg
  def message(%{__exception__: true} = exception), do: Exception.message(exception)
  def message({:stream_error, reason}), do: "stream error: " <> message(reason)
  def message({:throw, value}), do: "thrown: " <> inspect(value)
  def message({:exit, value}), do: "exited: " <> Exception.format_exit(value)
  def message(:max_iterations), do: "maximum iterations exceeded"
  def message(:timeout), do: "timed out"
  def message(:busy), do: "busy: too many concurrent runs"
  def message(reason), do: inspect(reason)

  @spec to_wire(term()) :: map()
  def to_wire(%APIError{} = err) do
    %{
      kind: "api_error",
      type: Atom.to_string(err.type),
      status: err.status,
      retryable: err.retryable,
      context_window_exceeded: err.context_window_exceeded
    }
  end

  def to_wire({:stream_error, reason}), do: Map.put(to_wire(reason), :stream, true)

  def to_wire(%{__exception__: true} = exception),
    do: %{kind: "exception", type: inspect(exception.__struct__)}

  def to_wire({kind, _value}) when kind in [:throw, :exit], do: %{kind: Atom.to_string(kind)}
  def to_wire(reason) when is_atom(reason), do: %{kind: Atom.to_string(reason)}
  def to_wire(_reason), do: %{kind: "other"}
end
