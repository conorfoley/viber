defmodule Viber.Runtime.SubAgentAdmissionTest do
  use ExUnit.Case, async: false

  alias Viber.Runtime.{Admission, SubAgent}
  alias Viber.Runtime.Conversation.Context

  test "a sub-agent is refused with :busy when the pool is full" do
    %{sub_agent: %{limit: limit, in_use: in_use}} = Admission.stats()

    holders =
      for _ <- 1..(limit - in_use) do
        pid = spawn(fn -> Process.sleep(:infinity) end)
        :ok = Admission.acquire(:sub_agent, holder: pid)
        pid
      end

    on_exit(fn -> Enum.each(holders, &Process.exit(&1, :kill)) end)

    ctx = %Context{
      session: self(),
      model: "test",
      event_handler: fn _ -> :ok end,
      provider_module: Viber.ScriptedProvider,
      project_root: System.tmp_dir!()
    }

    assert {:error, :busy} = SubAgent.run(%{"task" => "anything"}, ctx)
    assert Viber.ScriptedProvider.requests() == []
  end
end
