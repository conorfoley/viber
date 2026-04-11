defmodule Viber.Scheduler do
  @moduledoc """
  Quantum-based cron scheduler for Viber scheduled jobs.
  """

  use Quantum, otp_app: :viber
end
