defmodule Viber.API.Error do
  @moduledoc """
  Structured error type for API operations.
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
          status: integer() | nil,
          attempts: integer() | nil
        }

  @enforce_keys [:type, :message]
  defstruct [:type, :message, :status, :attempts, retryable: false]

  @spec missing_credentials(String.t(), [String.t()]) :: t()
  def missing_credentials(provider, env_vars) do
    %__MODULE__{
      type: :missing_credentials,
      message: "missing #{provider} credentials; export #{Enum.join(env_vars, " or ")}"
    }
  end

  @spec api_error(integer(), String.t(), boolean()) :: t()
  def api_error(status, message, retryable) do
    %__MODULE__{type: :api, message: message, status: status, retryable: retryable}
  end

  @spec retries_exhausted(integer(), String.t()) :: t()
  def retries_exhausted(attempts, last_message) do
    %__MODULE__{
      type: :retries_exhausted,
      message: "api failed after #{attempts} attempts: #{last_message}",
      attempts: attempts
    }
  end

  @spec retryable?(t()) :: boolean()
  def retryable?(%__MODULE__{retryable: retryable}), do: retryable
end
