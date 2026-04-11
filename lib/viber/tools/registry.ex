defmodule Viber.Tools.Registry do
  @moduledoc """
  Registry of built-in tool specifications with lookup and listing.
  """

  alias Viber.Tools.{Builtins, Spec}

  @specs %{
    "bash" => %Spec{
      name: "bash",
      description: "Execute a shell command in the current workspace.",
      input_schema: %{
        "type" => "object",
        "properties" => %{
          "command" => %{"type" => "string"},
          "timeout" => %{
            "type" => "integer",
            "minimum" => 1,
            "description" => "Timeout in seconds"
          },
          "description" => %{"type" => "string"}
        },
        "required" => ["command"],
        "additionalProperties" => false
      },
      permission: :danger_full_access,
      handler: &Builtins.Bash.execute/1
    },
    "read_file" => %Spec{
      name: "read_file",
      description: "Read a text file from the workspace.",
      input_schema: %{
        "type" => "object",
        "properties" => %{
          "path" => %{"type" => "string"},
          "offset" => %{"type" => "integer", "minimum" => 0},
          "limit" => %{"type" => "integer", "minimum" => 1}
        },
        "required" => ["path"],
        "additionalProperties" => false
      },
      permission: :read_only,
      handler: &Builtins.FileOps.read/1
    },
    "write_file" => %Spec{
      name: "write_file",
      description: "Write a text file in the workspace.",
      input_schema: %{
        "type" => "object",
        "properties" => %{
          "path" => %{"type" => "string"},
          "content" => %{"type" => "string"}
        },
        "required" => ["path", "content"],
        "additionalProperties" => false
      },
      permission: :workspace_write,
      handler: &Builtins.FileOps.write/1
    },
    "edit_file" => %Spec{
      name: "edit_file",
      description: "Replace text in a workspace file.",
      input_schema: %{
        "type" => "object",
        "properties" => %{
          "path" => %{"type" => "string"},
          "old_string" => %{"type" => "string"},
          "new_string" => %{"type" => "string"},
          "replace_all" => %{"type" => "boolean"}
        },
        "required" => ["path", "old_string", "new_string"],
        "additionalProperties" => false
      },
      permission: :workspace_write,
      handler: &Builtins.FileOps.edit/1
    },
    "glob_search" => %Spec{
      name: "glob_search",
      description: "Find files by glob pattern.",
      input_schema: %{
        "type" => "object",
        "properties" => %{
          "pattern" => %{"type" => "string"},
          "path" => %{"type" => "string"}
        },
        "required" => ["pattern"],
        "additionalProperties" => false
      },
      permission: :read_only,
      handler: &Builtins.Glob.execute/1
    },
    "grep_search" => %Spec{
      name: "grep_search",
      description: "Search file contents with a regex pattern.",
      input_schema: %{
        "type" => "object",
        "properties" => %{
          "pattern" => %{"type" => "string"},
          "path" => %{"type" => "string"},
          "glob" => %{"type" => "string"},
          "output_mode" => %{"type" => "string"},
          "-B" => %{"type" => "integer", "minimum" => 0},
          "-A" => %{"type" => "integer", "minimum" => 0},
          "-C" => %{"type" => "integer", "minimum" => 0},
          "-n" => %{"type" => "boolean"},
          "-i" => %{"type" => "boolean"},
          "type" => %{"type" => "string"},
          "head_limit" => %{"type" => "integer", "minimum" => 1},
          "offset" => %{"type" => "integer", "minimum" => 0},
          "multiline" => %{"type" => "boolean"}
        },
        "required" => ["pattern"],
        "additionalProperties" => false
      },
      permission: :read_only,
      handler: &Builtins.Grep.execute/1
    },
    "ls" => %Spec{
      name: "ls",
      description: "List files and directories at a given path.",
      input_schema: %{
        "type" => "object",
        "properties" => %{
          "path" => %{"type" => "string"},
          "depth" => %{"type" => "integer", "minimum" => 1},
          "ignore" => %{"type" => "array", "items" => %{"type" => "string"}}
        },
        "required" => ["path"],
        "additionalProperties" => false
      },
      permission: :read_only,
      handler: &Builtins.LS.execute/1
    },
    "web_fetch" => %Spec{
      name: "web_fetch",
      description: "Fetch a URL and convert it into readable text.",
      input_schema: %{
        "type" => "object",
        "properties" => %{
          "url" => %{"type" => "string", "format" => "uri"}
        },
        "required" => ["url"],
        "additionalProperties" => false
      },
      permission: :workspace_write,
      permission_fn: &Builtins.WebFetch.permission_for/1,
      handler: &Builtins.WebFetch.execute/1
    },
    "multi_edit" => %Spec{
      name: "multi_edit",
      description:
        "Apply multiple text replacements across one or more files atomically. " <>
          "All edits are validated before any writes occur; if any edit fails, no files are modified.",
      input_schema: %{
        "type" => "object",
        "properties" => %{
          "edits" => %{
            "type" => "array",
            "items" => %{
              "type" => "object",
              "properties" => %{
                "path" => %{"type" => "string"},
                "old_string" => %{"type" => "string"},
                "new_string" => %{"type" => "string"},
                "replace_all" => %{"type" => "boolean"}
              },
              "required" => ["path", "old_string", "new_string"],
              "additionalProperties" => false
            },
            "minItems" => 1
          }
        },
        "required" => ["edits"],
        "additionalProperties" => false
      },
      permission: :workspace_write,
      handler: &Builtins.MultiEdit.execute/1
    },
    "clipboard" => %Spec{
      name: "clipboard",
      description:
        "Read from or write to the system clipboard. " <>
          "Use action 'read' to get current clipboard contents, or 'write' with text to copy to clipboard.",
      input_schema: %{
        "type" => "object",
        "properties" => %{
          "action" => %{
            "type" => "string",
            "enum" => ["read", "write"]
          },
          "text" => %{"type" => "string"}
        },
        "required" => ["action"],
        "additionalProperties" => false
      },
      permission: :danger_full_access,
      handler: &Builtins.Clipboard.execute/1
    },
    "jq" => %Spec{
      name: "jq",
      description:
        "Run a jq filter against a JSON file or a raw JSON string. " <>
          "Provide either 'path' (path to a JSON file) or 'input' (a JSON string), not both.",
      input_schema: %{
        "type" => "object",
        "properties" => %{
          "filter" => %{"type" => "string"},
          "path" => %{"type" => "string"},
          "input" => %{"type" => "string"}
        },
        "required" => ["filter"],
        "additionalProperties" => false
      },
      permission: :read_only,
      handler: &Builtins.Jq.execute/1
    },
    "user_input" => %Spec{
      name: "user_input",
      description:
        "Ask the user a question and wait for their response. " <>
          "Use this to gather clarification or confirmation during a task. " <>
          "Optionally provide a list of options for the user to choose from.",
      input_schema: %{
        "type" => "object",
        "properties" => %{
          "question" => %{"type" => "string"},
          "options" => %{
            "type" => "array",
            "items" => %{"type" => "string"}
          }
        },
        "required" => ["question"],
        "additionalProperties" => false
      },
      permission: :read_only,
      handler: &Builtins.UserInput.execute/1
    },
    "mix_task" => %Spec{
      name: "mix_task",
      description:
        "Run an arbitrary Mix task with optional arguments and a configurable timeout.",
      input_schema: %{
        "type" => "object",
        "properties" => %{
          "task" => %{"type" => "string"},
          "args" => %{"type" => "array", "items" => %{"type" => "string"}},
          "timeout" => %{
            "type" => "integer",
            "minimum" => 1,
            "description" => "Timeout in seconds"
          }
        },
        "required" => ["task"],
        "additionalProperties" => false
      },
      permission: :danger_full_access,
      handler: &Builtins.MixTask.execute/1
    },
    "test_runner" => %Spec{
      name: "test_runner",
      description:
        "Run `mix test` with optional path/line targeting and return a parsed summary of results. " <>
          "Provides structured output with pass/fail status, test counts, and failure details.",
      input_schema: %{
        "type" => "object",
        "properties" => %{
          "path" => %{"type" => "string"},
          "line" => %{"type" => "integer", "minimum" => 1},
          "args" => %{"type" => "array", "items" => %{"type" => "string"}},
          "timeout" => %{
            "type" => "integer",
            "minimum" => 1,
            "description" => "Timeout in seconds"
          }
        },
        "required" => [],
        "additionalProperties" => false
      },
      permission: :read_only,
      handler: &Builtins.TestRunner.execute/1
    },
    "diagnostics" => %Spec{
      name: "diagnostics",
      description:
        "Run static analysis (Dialyzer or Credo) and return structured findings. " <>
          "Use tool 'dialyzer' for type checking and 'credo' for code style/quality issues. " <>
          "Optionally scope results to a specific file path.",
      input_schema: %{
        "type" => "object",
        "properties" => %{
          "tool" => %{"type" => "string", "enum" => ["dialyzer", "credo"]},
          "path" => %{"type" => "string"}
        },
        "required" => ["tool"],
        "additionalProperties" => false
      },
      permission: :read_only,
      handler: &Builtins.Diagnostics.execute/1
    },
    "git" => %Spec{
      name: "git",
      description:
        "Run a git command in the current workspace. " <>
          "Provide a subcommand (e.g., 'status', 'log', 'diff', 'add', 'commit', 'checkout', 'stash') " <>
          "and optional args. Read-only subcommands (status, log, diff, show, branch, blame, etc.) " <>
          "are safe; write subcommands (add, commit, checkout, reset, etc.) modify repository state.",
      input_schema: %{
        "type" => "object",
        "properties" => %{
          "subcommand" => %{
            "type" => "string",
            "description" => "The git subcommand to run (e.g., status, log, diff, add, commit)"
          },
          "args" => %{
            "type" => "array",
            "items" => %{"type" => "string"},
            "description" => "Additional arguments to pass to the git subcommand"
          },
          "timeout" => %{
            "type" => "integer",
            "minimum" => 1,
            "description" => "Timeout in seconds"
          }
        },
        "required" => ["subcommand"],
        "additionalProperties" => false
      },
      permission: :workspace_write,
      permission_fn: &Builtins.Git.permission_for/1,
      handler: &Builtins.Git.execute/1
    },
    "formatter" => %Spec{
      name: "formatter",
      description:
        "Apply `mix format` to a file path or an inline Elixir code snippet. " <>
          "Provide 'path' to format a file on disk, or 'content' to format a code string and get back the formatted result. " <>
          "Set 'check_only' to true to check formatting without writing changes.",
      input_schema: %{
        "type" => "object",
        "properties" => %{
          "path" => %{"type" => "string"},
          "content" => %{"type" => "string"},
          "check_only" => %{"type" => "boolean"}
        },
        "required" => [],
        "additionalProperties" => false
      },
      permission: :workspace_write,
      handler: &Builtins.Formatter.execute/1
    },
    "ecto_schema_inspector" => %Spec{
      name: "ecto_schema_inspector",
      description:
        "Parse an Ecto schema module and return its fields, types, associations, embeds, " <>
          "and changeset functions as structured output — without executing any SQL. " <>
          "Provide 'module' to inspect a specific module by name, 'path' to scan a file or directory, " <>
          "or omit both to scan the entire project.",
      input_schema: %{
        "type" => "object",
        "properties" => %{
          "module" => %{
            "type" => "string",
            "description" => "Fully-qualified module name, e.g. \"MyApp.Accounts.User\""
          },
          "path" => %{
            "type" => "string",
            "description" => "File or directory path to scope the search"
          }
        },
        "required" => [],
        "additionalProperties" => false
      },
      permission: :read_only,
      handler: &Builtins.EctoSchemaInspector.execute/1
    },
    "mysql_query" => %Spec{
      name: "mysql_query",
      description:
        "Execute a SQL query against the active database connection (MySQL or PostgreSQL). " <>
          "Returns results as a formatted table, JSON, or CSV. " <>
          "Auto-appends LIMIT to unbounded SELECTs. Blocks UPDATE/DELETE without WHERE. " <>
          "DROP/TRUNCATE require explicit confirmation. All queries are audit-logged.",
      input_schema: %{
        "type" => "object",
        "properties" => %{
          "query" => %{"type" => "string", "description" => "SQL query to execute"},
          "database" => %{
            "type" => "string",
            "description" => "Named connection to use (defaults to active connection)"
          },
          "format" => %{
            "type" => "string",
            "enum" => ["table", "json", "csv"],
            "description" => "Output format (default: table)"
          },
          "limit" => %{
            "type" => "integer",
            "minimum" => 1,
            "description" => "Row limit for SELECT queries (default: 100)"
          },
          "timeout" => %{
            "type" => "integer",
            "minimum" => 1,
            "description" => "Timeout in seconds"
          },
          "force" => %{
            "type" => "boolean",
            "description" => "Override WHERE-clause safety check for UPDATE/DELETE"
          },
          "confirm" => %{
            "type" => "boolean",
            "description" =>
              "Required for DROP/TRUNCATE — explicitly confirm destructive operations"
          }
        },
        "required" => ["query"],
        "additionalProperties" => false
      },
      permission: :danger_full_access,
      permission_fn: &Builtins.MysqlQuery.permission_for/1,
      handler: &Builtins.MysqlQuery.execute/1
    },
    "mysql_schema" => %Spec{
      name: "mysql_schema",
      description:
        "Introspect database schema: list databases, tables, describe columns/indexes, " <>
          "show CREATE TABLE, explore foreign key relationships, and search columns by pattern.",
      input_schema: %{
        "type" => "object",
        "properties" => %{
          "action" => %{
            "type" => "string",
            "enum" => [
              "list_databases",
              "list_tables",
              "describe_table",
              "show_create",
              "relationships",
              "search_columns"
            ]
          },
          "table" => %{
            "type" => "string",
            "description" => "Table name (for describe_table, show_create, relationships)"
          },
          "filter" => %{"type" => "string", "description" => "Filter pattern (for list_tables)"},
          "pattern" => %{
            "type" => "string",
            "description" => "Search pattern (for search_columns)"
          },
          "database" => %{"type" => "string", "description" => "Named connection to use"}
        },
        "required" => ["action"],
        "additionalProperties" => false
      },
      permission: :read_only,
      handler: &Builtins.MysqlSchema.execute/1
    },
    "mysql_explain" => %Spec{
      name: "mysql_explain",
      description:
        "Run EXPLAIN or EXPLAIN ANALYZE on a SQL query to show the execution plan. " <>
          "Useful for understanding query performance and identifying optimization opportunities.",
      input_schema: %{
        "type" => "object",
        "properties" => %{
          "query" => %{"type" => "string", "description" => "SQL query to explain"},
          "analyze" => %{
            "type" => "boolean",
            "description" => "Use EXPLAIN ANALYZE for actual execution stats (default: true)"
          },
          "database" => %{"type" => "string", "description" => "Named connection to use"}
        },
        "required" => ["query"],
        "additionalProperties" => false
      },
      permission: :read_only,
      handler: &Builtins.MysqlExplain.execute/1
    },
    "data_export" => %Spec{
      name: "data_export",
      description:
        "Export SQL query results to a file. Supports CSV, JSON, and SQL INSERT formats. " <>
          "Provide table_name when using sql format to set the target table in INSERT statements.",
      input_schema: %{
        "type" => "object",
        "properties" => %{
          "query" => %{"type" => "string", "description" => "SQL query whose results to export"},
          "path" => %{"type" => "string", "description" => "Output file path"},
          "format" => %{
            "type" => "string",
            "enum" => ["csv", "json", "sql"],
            "description" => "Export format (default: csv)"
          },
          "table_name" => %{
            "type" => "string",
            "description" => "Table name for SQL INSERT format"
          },
          "database" => %{"type" => "string", "description" => "Named connection to use"}
        },
        "required" => ["query", "path"],
        "additionalProperties" => false
      },
      permission: :workspace_write,
      handler: &Builtins.DataExport.execute/1
    },
    "data_transform" => %Spec{
      name: "data_transform",
      description:
        "Run a SQL query then apply in-memory transformations: group (with aggregation), " <>
          "sort, filter, sample, select columns, rename columns, or pivot. " <>
          "Returns transformed results as a formatted table.",
      input_schema: %{
        "type" => "object",
        "properties" => %{
          "query" => %{"type" => "string", "description" => "SQL query to fetch data"},
          "transform" => %{
            "type" => "string",
            "enum" => ["group", "sort", "filter", "sample", "select", "rename", "pivot"]
          },
          "group_by" => %{
            "type" => "string",
            "description" => "Column to group by (for group transform)"
          },
          "agg_column" => %{
            "type" => "string",
            "description" => "Column to aggregate (for group transform)"
          },
          "agg_function" => %{
            "type" => "string",
            "enum" => ["count", "sum", "avg", "min", "max"],
            "description" => "Aggregation function (default: count)"
          },
          "sort_by" => %{
            "type" => "string",
            "description" => "Column to sort by (for sort transform)"
          },
          "direction" => %{"type" => "string", "enum" => ["asc", "desc"]},
          "filter_column" => %{"type" => "string"},
          "filter_op" => %{
            "type" => "string",
            "enum" => ["=", "!=", ">", "<", ">=", "<=", "contains"]
          },
          "filter_value" => %{"type" => "string"},
          "columns" => %{
            "type" => "array",
            "items" => %{"type" => "string"},
            "description" => "Columns to select (for select transform)"
          },
          "renames" => %{
            "type" => "object",
            "description" => "Map of old_name => new_name (for rename transform)"
          },
          "pivot_column" => %{"type" => "string"},
          "value_column" => %{"type" => "string"},
          "group_column" => %{"type" => "string"},
          "count" => %{"type" => "integer", "minimum" => 1, "description" => "Sample size"},
          "database" => %{"type" => "string", "description" => "Named connection to use"}
        },
        "required" => ["query", "transform"],
        "additionalProperties" => false
      },
      permission: :read_only,
      handler: &Builtins.DataTransform.execute/1
    },
    "scheduler" => %Spec{
      name: "scheduler",
      description:
        "Manage scheduled cron jobs: create, list, update, delete, enable/disable, " <>
          "run immediately, and view execution history. " <>
          "Jobs can run SQL queries, shell scripts, or health checks on a cron schedule " <>
          "with optional alert rules that trigger notifications via Slack, file, or log.",
      input_schema: %{
        "type" => "object",
        "properties" => %{
          "action" => %{
            "type" => "string",
            "enum" => [
              "list",
              "create",
              "update",
              "delete",
              "enable",
              "disable",
              "run_now",
              "history"
            ]
          },
          "id" => %{
            "type" => "string",
            "description" => "Job ID (for update/delete/enable/disable/run_now)"
          },
          "name" => %{"type" => "string", "description" => "Job name (for create)"},
          "cron_expr" => %{
            "type" => "string",
            "description" => "Cron expression, e.g. '0 */6 * * *' (for create/update)"
          },
          "type" => %{
            "type" => "string",
            "enum" => ["query", "script", "health_check"],
            "description" => "Job type (default: query)"
          },
          "payload" => %{
            "type" => "object",
            "description" =>
              "Job payload: {\"query\": \"...\"} for query type, {\"script\": \"...\"} for script type"
          },
          "database" => %{"type" => "string", "description" => "Named database connection to use"},
          "alert_rule" => %{
            "type" => "object",
            "description" =>
              "Alert condition: {\"condition\": \"row_count_gt\", \"threshold\": 0}"
          },
          "alert_sink" => %{
            "type" => "object",
            "description" =>
              "Alert destination: {\"type\": \"slack\", \"webhook_url\": \"...\"} or {\"type\": \"file\", \"path\": \"...\"} or {\"type\": \"log\"}"
          },
          "enabled" => %{
            "type" => "boolean",
            "description" => "Whether the job is enabled (default: true)"
          },
          "limit" => %{
            "type" => "integer",
            "minimum" => 1,
            "description" => "Number of history entries to return"
          }
        },
        "required" => ["action"],
        "additionalProperties" => false
      },
      permission: :danger_full_access,
      permission_fn: &Builtins.Scheduler.permission_for/1,
      handler: &Builtins.Scheduler.execute/1
    }
  }

  @ets_table :viber_mcp_tools

  @spec init_mcp_table() :: :ok
  def init_mcp_table do
    try do
      :ets.new(@ets_table, [:named_table, :set, :public])
    rescue
      ArgumentError -> :already_exists
    end

    :ok
  end

  @spec builtin_specs() :: [Spec.t()]
  def builtin_specs, do: Map.values(@specs)

  @spec all_specs() :: [Spec.t()]
  def all_specs, do: builtin_specs() ++ mcp_specs()

  @spec get(String.t()) :: {:ok, Spec.t()} | :error
  def get(name) do
    normalized = normalize_name(name)

    case Map.fetch(@specs, normalized) do
      {:ok, _} = result ->
        result

      :error ->
        case mcp_get(normalized) do
          nil -> :error
          spec -> {:ok, spec}
        end
    end
  end

  @spec list_names() :: [String.t()]
  def list_names do
    builtin = Map.keys(@specs)
    mcp = Enum.map(mcp_specs(), & &1.name)
    Enum.sort(builtin ++ mcp)
  end

  @spec register_mcp_tools(String.t(), [Spec.t()]) :: :ok
  def register_mcp_tools(server_name, specs) do
    init_mcp_table()

    Enum.each(specs, fn spec ->
      :ets.insert(@ets_table, {{server_name, spec.name}, spec})
    end)

    :ok
  end

  @spec unregister_mcp_tools(String.t()) :: :ok
  def unregister_mcp_tools(server_name) do
    if ets_available?() do
      :ets.match_delete(@ets_table, {{server_name, :_}, :_})
    end

    :ok
  end

  @spec mcp_specs() :: [Spec.t()]
  def mcp_specs do
    if ets_available?() do
      :ets.tab2list(@ets_table) |> Enum.map(fn {_key, spec} -> spec end)
    else
      []
    end
  end

  @spec normalize_name(String.t()) :: String.t()
  def normalize_name(name) do
    name
    |> String.trim()
    |> String.replace(~r/[^a-zA-Z0-9_-]/, "_")
    |> String.downcase()
    |> String.replace("-", "_")
  end

  defp ets_available?, do: :ets.whereis(@ets_table) != :undefined

  defp mcp_get(name) do
    if ets_available?() do
      case :ets.match_object(@ets_table, {{:_, name}, :_}) do
        [{_key, spec} | _] -> spec
        [] -> nil
      end
    else
      nil
    end
  end
end
