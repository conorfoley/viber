defmodule Viber.Tools.Builtins.EctoSchemaInspectorTest do
  use ExUnit.Case, async: true

  alias Viber.Tools.Builtins.EctoSchemaInspector

  @simple_schema """
  defmodule MyApp.Accounts.User do
    use Ecto.Schema
    import Ecto.Changeset

    schema "users" do
      field :email, :string
      field :name, :string
      field :age, :integer, default: 0
      field :role, Ecto.Enum, values: [:admin, :member], default: :member

      belongs_to :organisation, MyApp.Org
      has_many :posts, MyApp.Post
      has_one :profile, MyApp.Profile
      many_to_many :tags, MyApp.Tag, join_through: "user_tags"

      timestamps()
    end

    def changeset(user, attrs) do
      user
      |> cast(attrs, [:email, :name, :age])
      |> validate_required([:email])
    end

    def registration_changeset(user, attrs) do
      user
      |> changeset(attrs)
      |> validate_length(:name, min: 2)
    end
  end
  """

  @embedded_schema """
  defmodule MyApp.Address do
    use Ecto.Schema

    @primary_key false
    embedded_schema do
      field :street, :string
      field :city, :string
      field :zip, :string
    end
  end
  """

  @schema_with_embeds """
  defmodule MyApp.Order do
    use Ecto.Schema

    schema "orders" do
      field :total, :decimal

      embeds_one :billing_address, MyApp.Address
      embeds_many :line_items, MyApp.LineItem
    end

    def changeset(order, attrs) do
      order
      |> cast(attrs, [:total])
    end
  end
  """

  @non_schema """
  defmodule MyApp.SomeContext do
    def hello, do: :world
  end
  """

  describe "parse_source/2" do
    test "extracts module name" do
      [result] = EctoSchemaInspector.parse_source(@simple_schema)
      assert result.module == "MyApp.Accounts.User"
    end

    test "extracts table name" do
      [result] = EctoSchemaInspector.parse_source(@simple_schema)
      assert result.source == "users"
    end

    test "defaults primary key to id" do
      [result] = EctoSchemaInspector.parse_source(@simple_schema)
      assert result.primary_key == ["id"]
    end

    test "detects @primary_key false" do
      [result] = EctoSchemaInspector.parse_source(@embedded_schema)
      assert result.primary_key == []
    end

    test "extracts plain fields with types" do
      [result] = EctoSchemaInspector.parse_source(@simple_schema)
      names = Enum.map(result.fields, & &1.name)
      assert "email" in names
      assert "name" in names
      assert "age" in names
    end

    test "extracts field defaults" do
      [result] = EctoSchemaInspector.parse_source(@simple_schema)
      age = Enum.find(result.fields, &(&1.name == "age"))
      assert age.default == "0"
    end

    test "fields without defaults have nil default" do
      [result] = EctoSchemaInspector.parse_source(@simple_schema)
      email = Enum.find(result.fields, &(&1.name == "email"))
      assert email.default == nil
    end

    test "extracts belongs_to association" do
      [result] = EctoSchemaInspector.parse_source(@simple_schema)
      assoc = Enum.find(result.associations, &(&1.name == "organisation"))
      assert assoc.kind == "belongs_to"
      assert assoc.queryable == "MyApp.Org"
    end

    test "extracts has_many association" do
      [result] = EctoSchemaInspector.parse_source(@simple_schema)
      assoc = Enum.find(result.associations, &(&1.name == "posts"))
      assert assoc.kind == "has_many"
    end

    test "extracts has_one association" do
      [result] = EctoSchemaInspector.parse_source(@simple_schema)
      assoc = Enum.find(result.associations, &(&1.name == "profile"))
      assert assoc.kind == "has_one"
    end

    test "extracts many_to_many association" do
      [result] = EctoSchemaInspector.parse_source(@simple_schema)
      assoc = Enum.find(result.associations, &(&1.name == "tags"))
      assert assoc.kind == "many_to_many"
    end

    test "extracts embeds_one" do
      [result] = EctoSchemaInspector.parse_source(@schema_with_embeds)
      embed = Enum.find(result.embeds, &(&1.name == "billing_address"))
      assert embed.kind == "embeds_one"
      assert embed.schema == "MyApp.Address"
    end

    test "extracts embeds_many" do
      [result] = EctoSchemaInspector.parse_source(@schema_with_embeds)
      embed = Enum.find(result.embeds, &(&1.name == "line_items"))
      assert embed.kind == "embeds_many"
      assert embed.schema == "MyApp.LineItem"
    end

    test "extracts changeset functions with arity" do
      [result] = EctoSchemaInspector.parse_source(@simple_schema)
      names = Enum.map(result.changesets, & &1.name)
      assert "changeset" in names
      assert "registration_changeset" in names

      cs = Enum.find(result.changesets, &(&1.name == "changeset"))
      assert cs.arity == 2
    end

    test "deduplicates changesets with same name" do
      [result] = EctoSchemaInspector.parse_source(@simple_schema)
      changeset_count = Enum.count(result.changesets, &(&1.name == "changeset"))
      assert changeset_count == 1
    end

    test "returns empty list for non-schema module" do
      assert [] == EctoSchemaInspector.parse_source(@non_schema)
    end

    test "returns empty list for embedded schema with no table" do
      [result] = EctoSchemaInspector.parse_source(@embedded_schema)
      assert result.source == nil
    end
  end

  describe "execute/1" do
    test "returns error for missing path" do
      assert {:error, msg} = EctoSchemaInspector.execute(%{"path" => "/nonexistent/path/xyz"})
      assert msg =~ "No Ecto schemas found"
    end

    test "returns error for unknown module" do
      assert {:error, msg} =
               EctoSchemaInspector.execute(%{"module" => "Completely.Unknown.Module.XYZ"})

      assert msg =~ "No Ecto schema found for module"
    end

    test "accepts empty input and scans current project" do
      result = EctoSchemaInspector.execute(%{})
      assert {:ok, _output} = result
    end

    test "output contains schema count header" do
      {:ok, output} = EctoSchemaInspector.execute(%{})
      assert output =~ ~r/Found \d+ Ecto schema/
    end

    test "scans a specific file path" do
      path = "lib/viber/tools/builtins/ecto_schema_inspector.ex"
      result = EctoSchemaInspector.execute(%{"path" => path})
      assert {:error, "No Ecto schemas found at path: " <> _} = result
    end
  end

  describe "output formatting" do
    test "formats schema with all sections" do
      tmp = System.tmp_dir!() |> Path.join("test_user_#{:rand.uniform(100_000)}.ex")
      File.write!(tmp, @simple_schema)
      on_exit(fn -> File.rm(tmp) end)

      {:ok, output} = EctoSchemaInspector.execute(%{"path" => tmp})

      assert output =~ "MyApp.Accounts.User"
      assert output =~ "users"
      assert output =~ ":email"
      assert output =~ "belongs_to"
      assert output =~ "has_many"
      assert output =~ "changeset"
    end

    test "shows primary key false for embedded schemas" do
      tmp = System.tmp_dir!() |> Path.join("test_embedded_#{:rand.uniform(100_000)}.ex")
      File.write!(tmp, @embedded_schema)

      on_exit(fn -> File.rm(tmp) end)

      {:ok, output} = EctoSchemaInspector.execute(%{"path" => tmp})
      assert output =~ "false"
    end

    test "shows (none) when no fields present" do
      source = """
      defmodule MyApp.Empty do
        use Ecto.Schema
        schema "empty" do
        end
      end
      """

      tmp = System.tmp_dir!() |> Path.join("test_empty_#{:rand.uniform(100_000)}.ex")
      File.write!(tmp, source)
      on_exit(fn -> File.rm(tmp) end)

      {:ok, output} = EctoSchemaInspector.execute(%{"path" => tmp})
      assert output =~ "(none)"
    end

    test "separator rendered between multiple schemas" do
      dir = System.tmp_dir!() |> Path.join("viber_test_#{:rand.uniform(100_000)}")
      File.mkdir_p!(dir)
      on_exit(fn -> File.rm_rf(dir) end)

      File.write!(Path.join(dir, "user.ex"), @simple_schema)
      File.write!(Path.join(dir, "address.ex"), @embedded_schema)

      {:ok, output} = EctoSchemaInspector.execute(%{"path" => dir})
      assert output =~ "─"
      assert output =~ "Found 2 Ecto schema"
    end
  end
end
