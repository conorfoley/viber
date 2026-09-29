defmodule Viber.API.Error do
  @moduledoc """
  Structured error type for API operations.

  `cause` keeps the underlying term (a transport exception, or the last
  `Viber.API.Error` for `:retries_exhausted`) so callers can match on it
  instead of parsing `message`. `context_window_exceeded` is set when the
  provider rejected the request because the prompt was too large.
  """

  @type error_type ::
          :missing_credentials
          | :auth
          | :http
          | :json
          | :api
          | :retries_exhausted
          | :invalid_sse_frame
          | :backoff_overflow

  @type t :: %__MODULE__{
          type: error_type(),
          message: String.t(),
          retryable: boolean(),
          context_window_exceeded: boolean(),
          status: integer() | nil,
          attempts: integer() | nil,
          cause: term()
        }

  @enforce_keys [:type, :message]
  defstruct [
    :type,
    :message,
    :status,
    :attempts,
    :cause,
    retryable: false,
    context_window_exceeded: false
  ]

  @context_window_patterns [
    "prompt is too long",
    "context length",
    "context_length_exceeded",
    "context window",
    "maximum context",
    "too many tokens",
    "no user query found"
  ]

  @spec missing_credentials(String.t(), [String.t()]) :: t()
  def missing_credentials(provider, env_vars) do
    %__MODULE__{
      type: :missing_credentials,
      message: "missing #{provider} credentials; export #{Enum.join(env_vars, " or ")}"
    }
  end

  @spec api_error(integer(), String.t(), boolean()) :: t()
  def api_error(status, message, retryable) do
    %__MODULE__{
      type: :api,
      message: message,
      status: status,
      retryable: retryable,
      context_window_exceeded: context_window_message?(message)
    }
  end

  @spec http_error(Exception.t()) :: t()
  def http_error(exception) do
    %__MODULE__{
      type: :http,
      message: "http error: #{Exception.message(exception)}",
      retryable: true,
      cause: exception
    }
  end

  @spec retries_exhausted(integer(), t()) :: t()
  def retries_exhausted(attempts, %__MODULE__{} = last) do
    %__MODULE__{
      type: :retries_exhausted,
      message: "api failed after #{attempts} attempts: #{last.message}",
      attempts: attempts,
      status: last.status,
      context_window_exceeded: last.context_window_exceeded,
      cause: last
    }
  end

  @spec retryable?(t()) :: boolean()
  def retryable?(%__MODULE__{retryable: retryable}), do: retryable

  @spec context_window_exceeded?(t()) :: boolean()
  def context_window_exceeded?(%__MODULE__{context_window_exceeded: flag}), do: flag

  @spec context_window_message?(String.t()) :: boolean()
  def context_window_message?(message) when is_binary(message) do
    down = String.downcase(message)
    Enum.any?(@context_window_patterns, &String.contains?(down, &1))
  end

  def context_window_message?(_), do: false
end
