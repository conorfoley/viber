defmodule Viber.Tools.Builtins.EctoSchemaInspector do
  @moduledoc """
  Parses Ecto schema source files and returns fields, types, associations,
  embeds, and changeset functions as a structured result — without executing
  any SQL or requiring a database connection.

  Works by scanning source with regex rather than loading the module at
  runtime, so it is safe in any environment and has no compile-time
  dependency on Ecto being present in the host project.
  """

  @type field_info :: %{name: String.t(), type: String.t(), default: String.t() | nil}
  @type assoc_info :: %{kind: String.t(), name: String.t(), queryable: String.t()}
  @type embed_info :: %{kind: String.t(), name: String.t(), schema: String.t()}
  @type changeset_info :: %{name: String.t(), arity: non_neg_integer()}

  @type schema_result :: %{
          module: String.t(),
          source: String.t() | nil,
          primary_key: [String.t()],
          fields: [field_info()],
          associations: [assoc_info()],
          embeds: [embed_info()],
          changesets: [changeset_info()]
        }

  @spec execute(map()) :: {:ok, String.t()} | {:error, String.t()}
  def execute(%{"path" => path}) when is_binary(path) do
    path
    |> expand_path()
    |> collect_source_files()
    |> Enum.flat_map(&parse_file/1)
    |> case do
      [] -> {:error, "No Ecto schemas found at path: #{path}"}
      schemas -> {:ok, format_schemas(schemas)}
    end
  end

  def execute(%{"module" => module}) when is_binary(module) do
    cwd = File.cwd!()

    cwd
    |> collect_source_files()
    |> Enum.flat_map(&parse_file/1)
    |> Enum.filter(&(&1.module == normalize_module(module)))
    |> case do
      [] -> {:error, "No Ecto schema found for module: #{module}"}
      schemas -> {:ok, format_schemas(schemas)}
    end
  end

  def execute(input) when is_map(input) do
    cwd = File.cwd!()

    cwd
    |> collect_source_files()
    |> Enum.flat_map(&parse_file/1)
    |> case do
      [] -> {:error, "No Ecto schemas found in current project"}
      schemas -> {:ok, format_schemas(schemas)}
    end
  end

  @spec parse_file(String.t()) :: [schema_result()]
  def parse_file(path) do
    case File.read(path) do
      {:ok, source} -> parse_source(source, path)
      {:error, _} -> []
    end
  end

  @spec parse_source(String.t(), String.t()) :: [schema_result()]
  def parse_source(source, _file_path \\ "<string>") do
    if ecto_schema?(source) do
      [build_result(source)]
    else
      []
    end
  end

  defp ecto_schema?(source) do
    source =~ ~r/use\s+Ecto\.Schema/
  end

  defp build_result(source) do
    %{
      module: extract_module(source),
      source: extract_source_table(source),
      primary_key: extract_primary_key(source),
      fields: extract_fields(source),
      associations: extract_associations(source),
      embeds: extract_embeds(source),
      changesets: extract_changesets(source)
    }
  end

  defp extract_module(source) do
    case Regex.run(~r/defmodule\s+([\w.]+)/, source) do
      [_, mod] -> mod
      _ -> "Unknown"
    end
  end

  defp extract_source_table(source) do
    case Regex.run(~r/schema\s+"([^"]+)"/, source) do
      [_, table] -> table
      _ -> nil
    end
  end

  defp extract_primary_key(source) do
    cond do
      Regex.run(~r/@primary_key\s+false/, source) ->
        []

      match = Regex.run(~r/@primary_key\s+\{([^}]+)\}/, source) ->
        [_, inner] = match

        case String.split(inner, ",") do
          [name | _] -> [name |> String.trim() |> String.trim_leading(":")]
          _ -> ["id"]
        end

      true ->
        ["id"]
    end
  end

  defp extract_fields(source) do
    ~r/field[\s(]+:(\w+)\s*,\s*(\{[^}]+\}|:?[\w.]+(?:\.\w+)*)(?:\s*,\s*([^\n)]+))?/
    |> Regex.scan(source)
    |> Enum.map(fn
      [_, name, type, opts] ->
        %{name: name, type: normalize_type(type), default: extract_default(opts)}

      [_, name, type] ->
        %{name: name, type: normalize_type(type), default: nil}
    end)
  end

  defp extract_associations(source) do
    ~r/(belongs_to|has_one|has_many|many_to_many)[\s(]+:(\w+)\s*,\s*([\w.]+)/
    |> Regex.scan(source)
    |> Enum.map(fn [_, kind, name, queryable] ->
      %{kind: kind, name: name, queryable: queryable}
    end)
  end

  defp extract_embeds(source) do
    ~r/(embeds_one|embeds_many)[\s(]+:(\w+)\s*,\s*([\w.]+)/
    |> Regex.scan(source)
    |> Enum.map(fn [_, kind, name, schema] ->
      %{kind: kind, name: name, schema: schema}
    end)
  end

  defp extract_changesets(source) do
    ~r/def\s+(\w*changeset\w*)\s*\(([^)]*)\)/
    |> Regex.scan(source)
    |> Enum.map(fn [_, name, args] ->
      arity = args |> String.split(",") |> Enum.count(fn a -> String.trim(a) != "" end)
      %{name: name, arity: arity}
    end)
    |> Enum.uniq_by(& &1.name)
  end

  defp normalize_type(":" <> rest), do: rest
  defp normalize_type(type), do: type

  defp extract_default(opts) when is_binary(opts) do
    case Regex.run(~r/default:\s*(.+)/, String.trim_trailing(opts, ")")) do
      [_, val] -> val |> String.trim() |> String.trim_trailing(")")
      _ -> nil
    end
  end

  defp normalize_module("Elixir." <> rest), do: rest
  defp normalize_module(mod), do: mod

  defp expand_path(path) do
    if Path.type(path) == :absolute, do: path, else: Path.join(File.cwd!(), path)
  end

  defp collect_source_files(dir) do
    cond do
      File.regular?(dir) ->
        [dir]

      File.dir?(dir) ->
        dir
        |> Path.join("**/*.ex")
        |> Path.wildcard()

      true ->
        []
    end
  end

  defp format_schemas(schemas) do
    sections = Enum.map(schemas, &format_schema/1)

    "Found #{length(schemas)} Ecto schema(s)\n\n" <>
      Enum.join(sections, "\n\n#{String.duplicate("─", 60)}\n\n")
  end

  defp format_schema(schema) do
    lines = [
      "Module:  #{schema.module}",
      "Table:   #{schema.source || "(embedded / no table)"}",
      "PK:      #{format_primary_key(schema.primary_key)}"
    ]

    lines = lines ++ ["", "Fields (#{length(schema.fields)}):"] ++ format_fields(schema.fields)

    lines =
      if schema.associations != [] do
        lines ++
          ["", "Associations (#{length(schema.associations)}):"] ++
          format_associations(schema.associations)
      else
        lines
      end

    lines =
      if schema.embeds != [] do
        lines ++
          ["", "Embeds (#{length(schema.embeds)}):"] ++
          format_embeds(schema.embeds)
      else
        lines
      end

    lines =
      if schema.changesets != [] do
        lines ++
          ["", "Changesets (#{length(schema.changesets)}):"] ++
          format_changesets(schema.changesets)
      else
        lines
      end

    Enum.join(lines, "\n")
  end

  defp format_primary_key([]), do: "false (no primary key)"
  defp format_primary_key(keys), do: Enum.join(keys, ", ")

  defp format_fields([]), do: ["  (none)"]

  defp format_fields(fields) do
    Enum.map(fields, fn %{name: name, type: type, default: default} ->
      base = "  :#{name}  #{type}"
      if default, do: base <> "  (default: #{default})", else: base
    end)
  end

  defp format_associations(assocs) do
    Enum.map(assocs, fn %{kind: kind, name: name, queryable: q} ->
      "  #{kind} :#{name} → #{q}"
    end)
  end

  defp format_embeds(embeds) do
    Enum.map(embeds, fn %{kind: kind, name: name, schema: s} ->
      "  #{kind} :#{name} → #{s}"
    end)
  end

  defp format_changesets(changesets) do
    Enum.map(changesets, fn %{name: name, arity: arity} ->
      "  #{name}/#{arity}"
    end)
  end
end
