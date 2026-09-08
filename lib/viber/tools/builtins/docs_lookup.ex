defmodule Viber.Tools.Builtins.DocsLookup do
  @moduledoc """
  Look up Elixir module/function documentation via the Code and IEx.Introspection APIs.
  """

  @spec execute(map()) :: {:ok, String.t()} | {:error, String.t()}
  def execute(%{"module" => module_str} = input) do
    function = input["function"]
    arity = input["arity"]

    case parse_module(module_str) do
      {:ok, module} -> lookup(module, function, arity)
      {:error, _} = err -> err
    end
  end

  def execute(_), do: {:error, "Missing required parameter: module"}

  defp lookup(module, nil, _arity), do: lookup_module(module)

  defp lookup(module, function, arity) do
    case safe_function_atom(function) do
      {:ok, fun_atom} -> lookup_function(module, fun_atom, arity)
      {:error, _} = err -> err
    end
  end

  defp parse_module(str) do
    try do
      module =
        str
        |> String.trim()
        |> then(fn
          ":" <> rest -> String.to_existing_atom(rest)
          name -> Module.safe_concat([name])
        end)

      case Code.ensure_loaded(module) do
        {:module, ^module} -> {:ok, module}
        {:error, _} -> {:error, "Module #{str} not found or not loadable"}
      end
    rescue
      ArgumentError -> {:error, "Module #{str} does not exist"}
    end
  end

  defp safe_function_atom(name) do
    {:ok, String.to_existing_atom(name)}
  rescue
    ArgumentError -> {:error, "Unknown function: #{name}"}
  end

  defp lookup_module(module) do
    lines = ["# #{inspect(module)}", ""]
    lines = lines ++ module_doc_lines(module)
    lines = lines ++ ["## Functions", ""]
    lines = lines ++ function_summary_lines(module)

    specs = fetch_specs(module)
    lines = if specs != [], do: lines ++ ["", "## Typespecs", "" | specs], else: lines

    {:ok, Enum.join(lines, "\n")}
  end

  defp module_doc_lines(module) do
    case Code.fetch_docs(module) do
      {:docs_v1, _, _, _, %{"en" => doc}, _, _} -> [doc, ""]
      {:docs_v1, _, _, _, :none, _, _} -> ["No module documentation available.", ""]
      {:docs_v1, _, _, _, :hidden, _, _} -> ["Module documentation is hidden.", ""]
      _ -> ["No documentation available.", ""]
    end
  end

  defp function_summary_lines(module) do
    case Code.fetch_docs(module) do
      {:docs_v1, _, _, _, _, _, docs} ->
        functions =
          docs
          |> Enum.filter(&function_doc?/1)
          |> Enum.map(&format_function_summary/1)

        if functions == [], do: ["  No documented functions"], else: functions

      _ ->
        ["  No documented functions"]
    end
  end

  defp function_doc?({{:function, _, _}, _, _, _, _}), do: true
  defp function_doc?(_), do: false

  defp format_function_summary({{:function, name, arity}, _, signatures, doc, _}) do
    sig = if signatures != [], do: hd(signatures), else: "#{name}/#{arity}"
    "  #{sig} - #{doc_summary(doc)}"
  end

  defp doc_summary(%{"en" => text}), do: text |> String.split("\n", parts: 2) |> hd()
  defp doc_summary(_), do: ""

  defp lookup_function(module, function, arity) do
    case Code.fetch_docs(module) do
      {:docs_v1, _, _, _, _, _, docs} ->
        docs
        |> Enum.filter(&matching_function?(&1, function, arity))
        |> format_function_matches(module)

      _ ->
        {:error, "No documentation available for #{inspect(module)}"}
    end
  end

  defp matching_function?({{:function, function, a}, _, _, _, _}, function, arity) do
    is_nil(arity) or a == arity
  end

  defp matching_function?(_, _function, _arity), do: false

  defp format_function_matches([], module) do
    {:error, "No documentation found for #{inspect(module)}.#{module}"}
  end

  defp format_function_matches(matches, module) do
    {:ok, Enum.map_join(matches, "\n\n---\n\n", &format_function_match(&1, module))}
  end

  defp format_function_match({{:function, name, ar}, _, signatures, doc, _}, module) do
    sig = if signatures != [], do: hd(signatures), else: "#{name}/#{ar}"
    doc_text = function_doc_text(doc)
    spec_text = function_spec_text(module, name, ar)

    "## #{sig}#{spec_text}\n\n#{doc_text}"
  end

  defp function_doc_text(%{"en" => t}), do: t
  defp function_doc_text(_), do: "No documentation available."

  defp function_spec_text(module, name, ar) do
    case fetch_spec(module, name, ar) do
      nil -> ""
      spec -> "\n\n```elixir\n#{spec}\n```"
    end
  end

  defp fetch_specs(module) do
    case Code.Typespec.fetch_specs(module) do
      {:ok, specs} -> Enum.map(specs, &format_spec_entry/1)
      :error -> []
    end
  end

  defp format_spec_entry({{name, arity}, spec_forms}) do
    "  @spec #{name}/#{arity}: #{spec_forms_to_string(name, spec_forms)}"
  end

  defp fetch_spec(module, name, arity) do
    case Code.Typespec.fetch_specs(module) do
      {:ok, specs} -> fetch_spec_forms(specs, name, arity)
      :error -> nil
    end
  end

  defp fetch_spec_forms(specs, name, arity) do
    case List.keyfind(specs, {name, arity}, 0) do
      {_, spec_forms} -> spec_forms_to_string(name, spec_forms)
      nil -> nil
    end
  end

  defp spec_forms_to_string(name, spec_forms) do
    Enum.map_join(spec_forms, "\n", fn form ->
      name |> Code.Typespec.spec_to_quoted(form) |> Macro.to_string()
    end)
  end
end
