defmodule Viber.Env do
  @moduledoc """
  Shared helpers for reading environment variables.
  """

  @spec key_set?(String.t()) :: boolean()
  def key_set?(var) do
    case System.get_env(var) do
      nil -> false
      "" -> false
      _ -> true
    end
  end
end
