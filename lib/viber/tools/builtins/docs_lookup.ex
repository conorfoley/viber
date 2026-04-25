defmodule Viber.Tools.Builtins.DocsLookup do
  @moduledoc """
  Look up Elixir module/function documentation via the Code and IEx.Introspection APIs.
  """

  @spec execute(map()) :: {:ok, String.t()} | {:error, String.t()}
  def execute(%{"module" => module_str} = input) do
    function = input["function"]
    arity = input["arity"]

    case parse_module(module_str) do
      {:ok, module} ->
        if function do
          lookup_function(module, String.to_atom(function), arity)
        else
          lookup_module(module)
        end

      {:error, _} = err ->
        err
    end
  end

  def execute(_), do: {:error, "Missing required parameter: module"}

  defp parse_module(str) do
    module =
      str
      |> String.trim()
      |> then(fn
        ":" <> rest -> String.to_atom(rest)
        name -> Module.concat([name])
      end)

    case Code.ensure_loaded(module) do
      {:module, ^module} -> {:ok, module}
      {:error, _} -> {:error, "Module #{str} not found or not loadable"}
    end
  end

  defp lookup_module(module) do
    lines = ["# #{inspect(module)}", ""]

    lines =
      case Code.fetch_docs(module) do
        {:docs_v1, _, _, _, %{"en" => doc}, _, _} ->
          lines ++ [doc, ""]

        {:docs_v1, _, _, _, :none, _, _} ->
          lines ++ ["No module documentation available.", ""]

        {:docs_v1, _, _, _, :hidden, _, _} ->
          lines ++ ["Module documentation is hidden.", ""]

        _ ->
          lines ++ ["No documentation available.", ""]
      end

    lines = lines ++ ["## Functions", ""]

    functions =
      case Code.fetch_docs(module) do
        {:docs_v1, _, _, _, _, _, docs} ->
          docs
          |> Enum.filter(fn
            {{:function, _, _}, _, _, _, _} -> true
            _ -> false
          end)
          |> Enum.map(fn {{:function, name, arity}, _, signatures, doc, _} ->
            sig = if signatures != [], do: hd(signatures), else: "#{name}/#{arity}"

            doc_summary =
              case doc do
                %{"en" => text} -> String.split(text, "\n", parts: 2) |> hd()
                _ -> ""
              end

            "  #{sig} - #{doc_summary}"
          end)

        _ ->
          []
      end

    lines =
      if functions == [] do
        lines ++ ["  No documented functions"]
      else
        lines ++ functions
      end

    specs = fetch_specs(module)
    lines = if specs != [], do: lines ++ ["", "## Typespecs", "" | specs], else: lines

    {:ok, Enum.join(lines, "\n")}
  end

  defp lookup_function(module, function, arity) do
    case Code.fetch_docs(module) do
      {:docs_v1, _, _, _, _, _, docs} ->
        matches =
          Enum.filter(docs, fn
            {{:function, ^function, a}, _, _, _, _} ->
              is_nil(arity) or a == arity

            _ ->
              false
          end)

        if matches == [] do
          {:error, "No documentation found for #{inspect(module)}.#{function}"}
        else
          text =
            Enum.map_join(matches, "\n\n---\n\n", fn {{:function, name, ar}, _, signatures, doc,
                                                      _} ->
              sig = if signatures != [], do: hd(signatures), else: "#{name}/#{ar}"

              doc_text =
                case doc do
                  %{"en" => t} -> t
                  _ -> "No documentation available."
                end

              spec_text =
                case fetch_spec(module, name, ar) do
                  nil -> ""
                  spec -> "\n\n```elixir\n#{spec}\n```"
                end

              "## #{sig}#{spec_text}\n\n#{doc_text}"
            end)

          {:ok, text}
        end

      _ ->
        {:error, "No documentation available for #{inspect(module)}"}
    end
  end

  defp fetch_specs(module) do
    case Code.Typespec.fetch_specs(module) do
      {:ok, specs} ->
        Enum.map(specs, fn {{name, arity}, spec_forms} ->
          spec_str =
            spec_forms
            |> Enum.map_join("\n", fn form ->
              Code.Typespec.spec_to_quoted(name, form)
              |> Macro.to_string()
            end)

          "  @spec #{name}/#{arity}: #{spec_str}"
        end)

      :error ->
        []
    end
  end

  defp fetch_spec(module, name, arity) do
    case Code.Typespec.fetch_specs(module) do
      {:ok, specs} ->
        case List.keyfind(specs, {name, arity}, 0) do
          {_, spec_forms} ->
            spec_forms
            |> Enum.map_join("\n", fn form ->
              Code.Typespec.spec_to_quoted(name, form)
              |> Macro.to_string()
            end)

          nil ->
            nil
        end

      :error ->
        nil
    end
  end
end
