defmodule Viber.Runtime.BrowserContext do
  @moduledoc """
  Typed browser context attached to a conversation turn.

  Frontends embedded in a browser (extensions, IDE webviews, custom
  apps) can attach a `BrowserContext` so the LLM has visibility into the
  user's current page. All fields are optional; an empty context renders
  no system prompt section.

  ## Fields

    * `:url` — current page URL.
    * `:title` — current page title.
    * `:selection` — selected text on the page.
    * `:viewport` — viewport dimensions, e.g. `%{"width" => 1280, "height" => 800}`.
    * `:accessibility_tree` — serialized accessibility tree snippet.
    * `:dom_snippet` — small DOM excerpt around the focused / selected node.
    * `:focused_element` — descriptor for the currently focused element.

  Use `new/1` at the transport boundary to coerce a raw map (typically
  decoded from JSON with string keys) into the struct, or `nil` when no
  context was provided.
  """

  @type t :: %__MODULE__{
          url: String.t() | nil,
          title: String.t() | nil,
          selection: String.t() | nil,
          viewport: map() | nil,
          accessibility_tree: String.t() | nil,
          dom_snippet: String.t() | nil,
          focused_element: map() | nil
        }

  defstruct url: nil,
            title: nil,
            selection: nil,
            viewport: nil,
            accessibility_tree: nil,
            dom_snippet: nil,
            focused_element: nil

  @known_string_keys ~w(url title selection accessibility_tree dom_snippet)
  @known_map_keys ~w(viewport focused_element)

  @doc """
  Coerce a raw value into a `%BrowserContext{}` or `nil`.

  Accepts:
    * `nil` — returns `nil`.
    * an empty map — returns `nil` (no context to inject).
    * a `%BrowserContext{}` struct — returned unchanged.
    * a map with string or atom keys — converted to the struct, ignoring
      unknown keys.
  """
  @spec new(nil | map() | t()) :: t() | nil
  def new(nil), do: nil
  def new(%__MODULE__{} = ctx), do: if(empty?(ctx), do: nil, else: ctx)

  def new(map) when is_map(map) and map_size(map) == 0, do: nil

  def new(map) when is_map(map) do
    ctx =
      Enum.reduce(map, %__MODULE__{}, fn {k, v}, acc ->
        put_field(acc, to_string(k), v)
      end)

    if empty?(ctx), do: nil, else: ctx
  end

  @doc "Returns true when no fields are populated."
  @spec empty?(t()) :: boolean()
  def empty?(%__MODULE__{} = ctx) do
    ctx
    |> Map.from_struct()
    |> Map.values()
    |> Enum.all?(&is_nil/1)
  end

  defp put_field(acc, key, value) when key in @known_string_keys and is_binary(value) do
    Map.put(acc, String.to_existing_atom(key), value)
  end

  defp put_field(acc, key, value) when key in @known_map_keys and is_map(value) do
    Map.put(acc, String.to_existing_atom(key), value)
  end

  defp put_field(acc, _key, _value), do: acc
end
