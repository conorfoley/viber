defmodule Viber.Runtime.Permissions do
  @moduledoc """
  Permission model with a mode ladder and tool-level policy checking.
  """

  @type permission_mode :: :read_only | :workspace_write | :danger_full_access | :prompt | :allow
  @type outcome :: :allow | :prompt | {:deny, String.t()}

  defmodule Policy do
    @moduledoc """
    A permission policy mapping tools to required permission modes.
    """

    @type t :: %__MODULE__{
            active_mode: Viber.Runtime.Permissions.permission_mode(),
            tool_requirements: %{String.t() => Viber.Runtime.Permissions.permission_mode()}
          }

    @enforce_keys [:active_mode]
    defstruct active_mode: :prompt, tool_requirements: %{}
  end

  @spec new_policy(permission_mode()) :: Policy.t()
  def new_policy(active_mode) do
    %Policy{active_mode: active_mode}
  end

  @spec register_tool(Policy.t(), String.t(), permission_mode()) :: Policy.t()
  def register_tool(%Policy{} = policy, tool_name, required_mode) do
    %{policy | tool_requirements: Map.put(policy.tool_requirements, tool_name, required_mode)}
  end

  @spec check(Policy.t(), String.t(), String.t()) :: outcome()
  def check(%Policy{} = policy, tool_name, _tool_input) do
    current = policy.active_mode
    required = Map.get(policy.tool_requirements, tool_name, :danger_full_access)

    cond do
      current == :allow ->
        :allow

      current == :prompt && mode_rank(required) <= mode_rank(:read_only) ->
        :allow

      current == :prompt ->
        :prompt

      mode_rank(current) >= mode_rank(required) ->
        :allow

      true ->
        {:deny,
         "tool '#{tool_name}' requires #{mode_to_string(required)} permission; current mode is #{mode_to_string(current)}"}
    end
  end

  @spec prompt_user(String.t(), String.t()) :: boolean()
  def prompt_user(tool_name, tool_input) do
    truncated = String.slice(tool_input, 0, 300)

    content =
      [
        Owl.Data.tag(tool_name, [:bright, :yellow]),
        "\n\n",
        Owl.Data.tag(truncated, :faint)
      ]

    box =
      content
      |> Owl.Box.new(
        padding_x: 1,
        padding_y: 0,
        border_style: :solid_rounded,
        border_tag: :yellow,
        title: Owl.Data.tag(" Permission Required ", :yellow)
      )
      |> Owl.Data.to_chardata()

    IO.write(box)
    IO.puts("")

    answer =
      IO.gets([
        IO.ANSI.yellow(),
        "  Allow? ",
        IO.ANSI.bright(),
        "[Y/n]",
        IO.ANSI.reset(),
        " "
      ])
      |> to_string()
      |> String.trim()
      |> String.downcase()

    answer in ["y", "yes", ""]
  end

  @spec mode_from_string(String.t()) :: permission_mode()
  def mode_from_string("read-only"), do: :read_only
  def mode_from_string("workspace-write"), do: :workspace_write
  def mode_from_string("danger-full-access"), do: :danger_full_access
  def mode_from_string("prompt"), do: :prompt
  def mode_from_string("allow"), do: :allow
  def mode_from_string(_), do: :prompt

  @spec mode_to_string(permission_mode()) :: String.t()
  def mode_to_string(:read_only), do: "read-only"
  def mode_to_string(:workspace_write), do: "workspace-write"
  def mode_to_string(:danger_full_access), do: "danger-full-access"
  def mode_to_string(:prompt), do: "prompt"
  def mode_to_string(:allow), do: "allow"

  @spec mode_rank(permission_mode()) :: integer()
  def mode_rank(:read_only), do: 0
  def mode_rank(:workspace_write), do: 1
  def mode_rank(:danger_full_access), do: 2
  def mode_rank(:prompt), do: -1
  def mode_rank(:allow), do: 3
end
