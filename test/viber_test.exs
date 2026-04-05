defmodule ViberTest do
  use ExUnit.Case

  test "application module is loaded" do
    assert {:module, Viber.Application} = Code.ensure_loaded(Viber.Application)
  end
end
