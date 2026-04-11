# Project Instructions

## Overview
Viber is an Elixir port of the Claw AI coding assistant. It provides an interactive CLI/REPL and an HTTP/SSE server for LLM-powered coding workflows. Built as an OTP application with an escript entry point. Includes database tooling (MySQL/PostgreSQL), scheduled job execution, and hot code reloading.

## Stack
- Language: Elixir 1.19 / OTP
- HTTP client: Req
- HTTP server: Bandit + Plug (port 4100)
- JSON: Jason
- Terminal UI: Owl
- Database: Ecto + Postgrex (PostgreSQL) + MyXQL (MySQL)
- Scheduling: Quantum
- File watching: FileSystem
- Static analysis: Dialyzer (dialyxir), Credo

## Architecture
Eight domains under `lib/viber/`:
- **API** — Provider behaviour (`Viber.API.Provider`), Anthropic + OpenAI-compatible implementations (with streaming state machine), SSE parser, model alias resolution via `Client`.
- **CLI** — `Main` escript entry point, interactive REPL, terminal renderer, `init` scaffolding.
- **Commands** — Slash-command system: parser, registry, handlers (`/help`, `/model`, `/compact`, `/config`, `/clear`, `/status`, `/attach`, `/bug`, `/connect`, `/databases`, `/init`, `/reload`, `/resume`).
- **Database** — `ConnectionManager` for named MySQL/PostgreSQL connections, `AuditLogger` for query logging, `QueryLog` for structured log entries.
- **Runtime** — `Session` (GenServer per conversation), `Conversation` (turn loop + tool execution with `Context` and `StreamAccumulator`), `Prompt` (system prompt builder), `Permissions` (mode ladder), `Usage` tracking, `Compaction`, `Bootstrap` (startup orchestration), `FileRefs` (attached file tracking), `SessionStore` (persistence), `Config` (layered configuration).
- **Scheduler** — Quantum-based cron job system: `Runner` executes jobs (SQL queries, shell scripts, health checks), `JobStore` persists jobs, `AlertSink` dispatches notifications (Slack webhook, file, log).
- **Server** — HTTP/SSE server for programmatic access, session handler, SSE streaming.
- **Tools** — `Spec` (tool definition + dynamic permissions via `permission_fn`), `Registry`, `Executor`, built-in tools, MCP client/server integration.

Additional top-level modules: `HotReloader` (file-system watcher for live code reloading), `Repo` (Ecto repo).

## Permission Model
Five modes: `:read_only` < `:workspace_write` < `:danger_full_access`, plus `:prompt` (default, auto-allows read-only tools, prompts for the rest) and `:allow` (everything auto-allowed).

Tools declare a static `permission` level. Tools may also provide a `permission_fn` that inspects the input to return a dynamic permission — e.g., the `git` tool returns `:read_only` for `status`/`log`/`diff` but `:workspace_write` for `commit`/`checkout`. Similarly, `mysql_query` escalates to `:danger_full_access` for write queries but stays `:read_only` for SELECTs. The `scheduler` tool uses the same pattern for list/history (read) vs create/delete (write).

## Built-in Tools
`bash`, `read_file`, `write_file`, `edit_file`, `multi_edit`, `glob_search`, `grep_search`, `ls`, `web_fetch`, `test_runner`, `diagnostics`, `formatter`, `mix_task`, `git`, `clipboard`, `jq`, `user_input`, `ecto_schema_inspector`, `mysql_query`, `mysql_schema`, `mysql_explain`, `data_export`, `data_transform`, `scheduler`

## Slash Commands
`/help`, `/model`, `/compact`, `/config`, `/clear`, `/status`, `/attach`, `/bug`, `/connect`, `/databases`, `/init`, `/reload`, `/resume`

## Conventions
- Always run `mix format` after changes.
- Use `@moduledoc`, `@spec`, `@type`, and `@callback` on public APIs.
- Never add comments to code unless explicitly asked.
- Tests mirror `lib/` structure under `test/viber/`. Mock provider in `test/support/mock_provider.ex`.
- `test_runner` is always allowed (`:read_only` permission) so the agent can run tests freely.
- New tools go in `lib/viber/tools/builtins/` with a matching entry in `Registry`.

## Key Files
- `lib/viber/runtime/conversation.ex` — Core conversation turn loop, tool execution with dynamic permission resolution.
- `lib/viber/runtime/prompt.ex` — System prompt builder; reads this file (`VIBER.md`) as project context.
- `lib/viber/runtime/permissions.ex` — Permission mode ladder and policy checking.
- `lib/viber/runtime/config.ex` — Layered configuration (defaults, project `.viber.json`, env vars).
- `lib/viber/runtime/session_store.ex` — Session persistence and resumption.
- `lib/viber/tools/registry.ex` — All built-in tool specs with schemas, permissions, and handlers.
- `lib/viber/tools/spec.ex` — Tool spec struct including optional `permission_fn` for input-dependent permissions.
- `lib/viber/tools/executor.ex` — Dispatches tool calls to handlers.
- `lib/viber/database/connection_manager.ex` — Named database connection pool management.
- `lib/viber/scheduler/runner.ex` — Cron job execution engine with alert integration.
- `lib/viber/api/client.ex` — LLM client with model alias resolution and streaming.
- `lib/viber/api/providers/anthropic.ex` — Anthropic Claude provider implementation.
- `lib/viber/api/providers/openai_compat.ex` — OpenAI-compatible provider (OpenAI, Ollama, etc.).
- `lib/viber/hot_reloader.ex` — File-system watcher for live code reloading during development.
- `lib/viber/application.ex` — OTP supervision tree.
- `mix.exs` — Project config, deps, escript setup.
