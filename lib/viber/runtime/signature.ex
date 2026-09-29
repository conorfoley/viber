defmodule Viber.Runtime.Signature do
  @moduledoc """
  A typed contract for a model call: named inputs in, named and typed
  outputs back.

  Signatures are written as text:

      "diff, goal -> verdict: enum[passed,failed], justification, evidence: list[string]"

  Each field is `name` or `name: type`. Types:

    * `string` (the default), `integer` (or `int`), `number` (or `float`),
      `boolean` (or `bool`)
    * `enum[a,b,c]` — one of the listed strings
    * `list[type]` — a list of any of the above

  `json_schema/1` turns the outputs into a JSON schema for a submit tool,
  and `validate/2` checks a reply against it, returning a
  `Viber.Runtime.Signature.ParseError` when it does not fit.
  """

  alias Viber.API.ToolDefinition
  alias Viber.Runtime.Signature.{Field, ParseError}

  @type t :: %__MODULE__{
          name: String.t(),
          instructions: String.t() | nil,
          inputs: [Field.t()],
          outputs: [Field.t()]
        }

  @enforce_keys [:name, :inputs, :outputs]
  defstruct [:name, :instructions, :inputs, :outputs]

  @name_pattern ~r/^[a-z_][a-z0-9_]*$/

  @spec new(String.t(), keyword()) :: {:ok, t()} | {:error, String.t()}
  def new(spec, opts \\ []) when is_binary(spec) do
    name = Keyword.get(opts, :name, "result")
    descriptions = Keyword.get(opts, :descriptions, %{})

    with :ok <- check_name(name),
         {:ok, input_text, output_text} <- split_arrow(spec),
         {:ok, inputs} <- parse_fields(input_text, descriptions),
         {:ok, outputs} <- parse_fields(output_text, descriptions),
         :ok <- check_outputs(outputs),
         :ok <- check_unique(inputs ++ outputs) do
      {:ok,
       %__MODULE__{
         name: name,
         instructions: Keyword.get(opts, :instructions),
         inputs: inputs,
         outputs: outputs
       }}
    end
  end

  @spec new!(String.t(), keyword()) :: t()
  def new!(spec, opts \\ []) do
    case new(spec, opts) do
      {:ok, signature} -> signature
      {:error, message} -> raise ArgumentError, "invalid signature: #{message}"
    end
  end

  @spec tool_name(t()) :: String.t()
  def tool_name(%__MODULE__{name: name}), do: "submit_" <> name

  @spec tool_definition(t()) :: ToolDefinition.t()
  def tool_definition(%__MODULE__{} = signature) do
    %ToolDefinition{
      name: tool_name(signature),
      description:
        signature.instructions ||
          "Submit the final #{signature.name}. Call this exactly once with every field filled in.",
      input_schema: json_schema(signature)
    }
  end

  @spec json_schema(t()) :: map()
  def json_schema(%__MODULE__{outputs: outputs}) do
    %{
      "type" => "object",
      "properties" => Map.new(outputs, fn field -> {field.name, field_schema(field)} end),
      "required" => Enum.map(outputs, & &1.name),
      "additionalProperties" => false
    }
  end

  @spec format_inputs(t(), map()) :: String.t()
  def format_inputs(%__MODULE__{inputs: inputs}, values) when is_map(values) do
    Enum.map_join(inputs, "\n\n", fn %Field{name: name} ->
      "<#{name}>\n#{render_value(fetch_value(values, name))}\n</#{name}>"
    end)
  end

  @spec validate(t(), term()) :: {:ok, map()} | {:error, ParseError.t()}
  def validate(%__MODULE__{outputs: outputs}, reply) when is_map(reply) do
    reply = Map.new(reply, fn {k, v} -> {to_string(k), v} end)
    missing = for %Field{name: name} <- outputs, not Map.has_key?(reply, name), do: name

    if missing != [] do
      {:error,
       ParseError.new(:missing_fields, "missing fields: #{Enum.join(missing, ", ")}",
         fields: missing,
         raw: reply
       )}
    else
      check_fields(outputs, reply)
    end
  end

  def validate(%__MODULE__{}, reply) do
    {:error, ParseError.new(:malformed, "reply is not a JSON object", raw: reply)}
  end

  @spec decode(t(), String.t()) :: {:ok, map()} | {:error, ParseError.t()}
  def decode(%__MODULE__{} = signature, text) when is_binary(text) do
    case extract_json_object(text) do
      {:ok, map} -> validate(signature, map)
      :error -> {:error, ParseError.new(:malformed, "reply is not a JSON object", raw: text)}
    end
  end

  defp check_fields(outputs, reply) do
    {values, invalid} =
      Enum.reduce(outputs, {%{}, []}, fn %Field{name: name, type: type}, {acc, bad} ->
        case coerce(type, Map.fetch!(reply, name)) do
          {:ok, value} -> {Map.put(acc, name, value), bad}
          :error -> {acc, [name | bad]}
        end
      end)

    case Enum.reverse(invalid) do
      [] ->
        {:ok, values}

      fields ->
        {:error,
         ParseError.new(:invalid_fields, invalid_message(outputs, fields),
           fields: fields,
           raw: reply
         )}
    end
  end

  defp invalid_message(outputs, fields) do
    details =
      outputs
      |> Enum.filter(&(&1.name in fields))
      |> Enum.map_join("; ", fn field -> "#{field.name} must be #{type_text(field.type)}" end)

    "invalid fields: " <> details
  end

  defp coerce(:string, value) when is_binary(value), do: {:ok, value}
  defp coerce(:integer, value) when is_integer(value), do: {:ok, value}

  defp coerce(:integer, value) when is_float(value) do
    if value == Float.round(value), do: {:ok, trunc(value)}, else: :error
  end

  defp coerce(:number, value) when is_number(value), do: {:ok, value}
  defp coerce(:boolean, value) when is_boolean(value), do: {:ok, value}

  defp coerce({:enum, allowed}, value) when is_binary(value) do
    trimmed = String.trim(value)
    if trimmed in allowed, do: {:ok, trimmed}, else: :error
  end

  defp coerce({:list, type}, values) when is_list(values) do
    Enum.reduce_while(values, {:ok, []}, fn value, {:ok, acc} ->
      case coerce(type, value) do
        {:ok, v} -> {:cont, {:ok, [v | acc]}}
        :error -> {:halt, :error}
      end
    end)
    |> case do
      {:ok, acc} -> {:ok, Enum.reverse(acc)}
      :error -> :error
    end
  end

  defp coerce(_type, _value), do: :error

  defp type_text(:string), do: "a string"
  defp type_text(:integer), do: "an integer"
  defp type_text(:number), do: "a number"
  defp type_text(:boolean), do: "a boolean"
  defp type_text({:enum, allowed}), do: "one of " <> Enum.join(allowed, ", ")
  defp type_text({:list, type}), do: "a list of " <> String.trim_leading(type_text(type), "a ")

  defp field_schema(%Field{type: type, description: nil}), do: type_schema(type)

  defp field_schema(%Field{type: type, description: description}),
    do: Map.put(type_schema(type), "description", description)

  defp type_schema(:string), do: %{"type" => "string"}
  defp type_schema(:integer), do: %{"type" => "integer"}
  defp type_schema(:number), do: %{"type" => "number"}
  defp type_schema(:boolean), do: %{"type" => "boolean"}
  defp type_schema({:enum, allowed}), do: %{"type" => "string", "enum" => allowed}
  defp type_schema({:list, type}), do: %{"type" => "array", "items" => type_schema(type)}

  defp check_name(name) when is_binary(name) do
    if Regex.match?(@name_pattern, name), do: :ok, else: {:error, "bad name #{inspect(name)}"}
  end

  defp check_name(name), do: {:error, "bad name #{inspect(name)}"}

  defp split_arrow(spec) do
    case String.split(spec, "->") do
      [inputs, outputs] -> {:ok, inputs, outputs}
      _ -> {:error, "expected exactly one \"->\""}
    end
  end

  defp check_outputs([]), do: {:error, "at least one output field is required"}
  defp check_outputs(_), do: :ok

  defp check_unique(fields) do
    names = Enum.map(fields, & &1.name)

    case names -- Enum.uniq(names) do
      [] -> :ok
      dups -> {:error, "duplicate fields: #{Enum.join(Enum.uniq(dups), ", ")}"}
    end
  end

  defp parse_fields(text, descriptions) do
    text
    |> split_top_level()
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.reduce_while({:ok, []}, fn part, {:ok, acc} ->
      case parse_field(part, descriptions) do
        {:ok, field} -> {:cont, {:ok, [field | acc]}}
        {:error, _} = err -> {:halt, err}
      end
    end)
    |> case do
      {:ok, fields} -> {:ok, Enum.reverse(fields)}
      err -> err
    end
  end

  defp split_top_level(text) do
    {parts, current, _depth} =
      text
      |> String.graphemes()
      |> Enum.reduce({[], "", 0}, fn
        ",", {parts, current, 0} -> {[current | parts], "", 0}
        "[", {parts, current, depth} -> {parts, current <> "[", depth + 1}
        "]", {parts, current, depth} -> {parts, current <> "]", max(depth - 1, 0)}
        char, {parts, current, depth} -> {parts, current <> char, depth}
      end)

    Enum.reverse([current | parts])
  end

  defp parse_field(part, descriptions) do
    {name, type_text} =
      case String.split(part, ":", parts: 2) do
        [name, type] -> {String.trim(name), String.trim(type)}
        [name] -> {String.trim(name), "string"}
      end

    with :ok <- check_field_name(name),
         {:ok, type} <- parse_type(type_text) do
      {:ok, %Field{name: name, type: type, description: Map.get(descriptions, name)}}
    end
  end

  defp check_field_name(name) do
    if Regex.match?(@name_pattern, name),
      do: :ok,
      else: {:error, "bad field name #{inspect(name)}"}
  end

  defp parse_type(text) do
    case String.downcase(text) do
      t when t in ["string", "str"] -> {:ok, :string}
      t when t in ["integer", "int"] -> {:ok, :integer}
      t when t in ["number", "float"] -> {:ok, :number}
      t when t in ["boolean", "bool"] -> {:ok, :boolean}
      "enum[" <> rest -> parse_enum(text, rest)
      "list[" <> rest -> parse_list(rest)
      _ -> {:error, "unknown type #{inspect(text)}"}
    end
  end

  defp parse_enum(original, rest) do
    with true <- String.ends_with?(rest, "]"),
         values =
           original
           |> String.slice(5..-2//1)
           |> String.split(",")
           |> Enum.map(&String.trim/1)
           |> Enum.reject(&(&1 == "")),
         true <- values != [] do
      {:ok, {:enum, values}}
    else
      _ -> {:error, "bad enum #{inspect(original)}"}
    end
  end

  defp parse_list(rest) do
    if String.ends_with?(rest, "]") do
      with {:ok, inner} <- parse_type(String.slice(rest, 0..-2//1)) do
        {:ok, {:list, inner}}
      end
    else
      {:error, "bad list type"}
    end
  end

  defp fetch_value(values, name) do
    Enum.find_value(values, fn {k, v} -> if to_string(k) == name, do: v end)
  end

  defp render_value(nil), do: ""
  defp render_value(value) when is_binary(value), do: value
  defp render_value(value), do: Jason.encode!(value)

  defp extract_json_object(text) do
    trimmed = String.trim(text)

    candidates =
      [trimmed, strip_fence(trimmed), braces_slice(trimmed)]
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq()

    Enum.find_value(candidates, :error, fn candidate ->
      case Jason.decode(candidate) do
        {:ok, map} when is_map(map) -> {:ok, map}
        _ -> nil
      end
    end)
  end

  defp strip_fence(text) do
    case Regex.run(~r/```(?:json)?\s*(.*?)```/s, text) do
      [_, inner] -> String.trim(inner)
      _ -> nil
    end
  end

  defp braces_slice(text) do
    with {start, _} <- :binary.match(text, "{"),
         [_ | _] = ends <- :binary.matches(text, "}") do
      {stop, _} = List.last(ends)
      if stop > start, do: binary_part(text, start, stop - start + 1)
    else
      _ -> nil
    end
  end
end
