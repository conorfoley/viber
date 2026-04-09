defmodule Viber.HotReloader do
  @moduledoc """
  GenServer that watches the `lib/` directory for `.ex` file changes and
  automatically recompiles and hot-reloads updated BEAM modules.

  Subscribes to `FileSystem` events, debounces rapid saves (300 ms), then
  runs `mix compile --no-deps-check` and loads updated `.beam` files into the
  running VM via `:code.load_abs/1`.

  Also exposes a synchronous `reload/1` API used by the `/reload` slash command.
  """

  use GenServer

  @debounce_ms 300

  @type state :: %{
          watcher_pid: pid(),
          project_root: String.t(),
          debounce_timer: reference() | nil,
          pending_paths: MapSet.t()
        }

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Synchronously triggers a full recompile and hot-reload.

  Returns `{:ok, modules}` where `modules` is the list of reloaded module atoms,
  or `{:error, output}` if compilation fails.
  """
  @spec reload(String.t()) :: {:ok, [module()]} | {:error, String.t()}
  def reload(project_root) do
    case GenServer.whereis(__MODULE__) do
      nil -> run_reload(project_root)
      _pid -> GenServer.call(__MODULE__, :reload, 60_000)
    end
  end

  @impl true
  def init(opts) do
    project_root = Keyword.fetch!(opts, :project_root)
    watch_dir = Path.join(project_root, "lib")

    {:ok, watcher_pid} = FileSystem.start_link(dirs: [watch_dir])
    FileSystem.subscribe(watcher_pid)

    state = %{
      watcher_pid: watcher_pid,
      project_root: project_root,
      debounce_timer: nil,
      pending_paths: MapSet.new()
    }

    {:ok, state}
  end

  @impl true
  def handle_info(
        {:file_event, watcher_pid, {path, _events}},
        %{watcher_pid: watcher_pid} = state
      ) do
    if String.ends_with?(path, ".ex") do
      if state.debounce_timer do
        Process.cancel_timer(state.debounce_timer)
      end

      timer = Process.send_after(self(), :debounce_fire, @debounce_ms)
      pending = MapSet.put(state.pending_paths, path)
      {:noreply, %{state | debounce_timer: timer, pending_paths: pending}}
    else
      {:noreply, state}
    end
  end

  @impl true
  def handle_info({:file_event, _watcher_pid, :stop}, state) do
    {:noreply, state}
  end

  @impl true
  def handle_info(:debounce_fire, state) do
    case run_reload(state.project_root) do
      {:ok, modules} ->
        IO.puts("[hot-reload] Recompiled #{length(modules)} module(s)")

      {:error, output} ->
        IO.puts("[hot-reload] Compilation failed:\n#{output}")
    end

    {:noreply, %{state | debounce_timer: nil, pending_paths: MapSet.new()}}
  end

  @impl true
  def handle_info(_msg, state), do: {:noreply, state}

  @impl true
  def handle_call(:reload, _from, state) do
    result = run_reload(state.project_root)
    {:reply, result, state}
  end

  @spec run_reload(String.t()) :: {:ok, [module()]} | {:error, String.t()}
  defp run_reload(project_root) do
    case System.cmd("mix", ["compile", "--no-deps-check"],
           cd: project_root,
           stderr_to_stdout: true
         ) do
      {_output, 0} ->
        modules = load_beam_files(project_root)
        {:ok, modules}

      {output, _code} ->
        {:error, output}
    end
  end

  @spec load_beam_files(String.t()) :: [module()]
  defp load_beam_files(project_root) do
    ebin_dir = Path.join([project_root, "_build", "dev", "lib", "viber", "ebin"])

    ebin_dir
    |> Path.join("*.beam")
    |> Path.wildcard()
    |> Enum.flat_map(fn beam_path ->
      module =
        beam_path
        |> Path.basename(".beam")
        |> String.to_atom()

      abs_path = beam_path |> Path.rootname() |> String.to_charlist()

      :code.purge(module)

      case :code.load_abs(abs_path) do
        {:module, ^module} -> [module]
        _ -> []
      end
    end)
  end
end
