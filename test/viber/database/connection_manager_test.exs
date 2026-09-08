defmodule Viber.Database.ConnectionManagerTest do
  use ExUnit.Case, async: true

  alias Viber.Database.ConnectionManager

  describe "parse_connection_url/1" do
    test "parses a full postgres URL" do
      assert {:ok, config} =
               ConnectionManager.parse_connection_url(
                 "postgres://alice:secret@db.example.com:5433/analytics"
               )

      assert config.type == :postgres
      assert config.hostname == "db.example.com"
      assert config.port == 5433
      assert config.username == "alice"
      assert config.password == "secret"
      assert config.database == "analytics"
      assert config.read_only == false
    end

    test "treats postgresql scheme as postgres" do
      assert {:ok, %{type: :postgres}} =
               ConnectionManager.parse_connection_url("postgresql://localhost/db")
    end

    test "parses a mysql URL and defaults the port" do
      assert {:ok, config} =
               ConnectionManager.parse_connection_url("mysql://root@127.0.0.1/shop")

      assert config.type == :mysql
      assert config.port == 3306
      assert config.username == "root"
      assert config.password == ""
    end

    test "defaults the postgres port when omitted" do
      assert {:ok, %{port: 5432}} =
               ConnectionManager.parse_connection_url("postgres://user@localhost/db")
    end

    test "url-decodes userinfo" do
      assert {:ok, config} =
               ConnectionManager.parse_connection_url("postgres://a%40b:p%3Aw@localhost/db")

      assert config.username == "a@b"
      assert config.password == "p:w"
    end

    test "rejects unsupported schemes" do
      assert {:error, msg} = ConnectionManager.parse_connection_url("redis://localhost/0")
      assert msg =~ "Invalid connection URL"
    end

    test "rejects malformed URLs" do
      assert {:error, _msg} = ConnectionManager.parse_connection_url("not-a-database-url")
    end
  end
end
