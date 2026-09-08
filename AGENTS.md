# Repository Guidelines

## Project Overview

Viber is a full **Web Accessibility and Coding Assistant** built in Elixir/OTP. It provides an interactive CLI/REPL and HTTP server for LLM-powered coding workflows, with database tooling, browser integration, scheduled job execution, and hot code reloading. Entry point: `Viber.CLI.Main`.

> **Motto:** *If the web can't do it, Viber can build you a webapp that can.*

Viber navigates and interprets live web pages via its browser integration, enabling web accessibility auditing, content extraction, and browser interaction — as well as scaffolding or building full webapps when the browser alone isn't enough.

## Project Structure & Module Organization

The codebase is organized into eight top-level domains under `lib/viber/`:

- **API** (`api/`) — LLM provider abstraction via `Viber.API.Provider` behaviour, with Anthropic and OpenAI-compatible implementations. Includes streaming SSE parser, typed request/response structs, and a client with model alias resolution.
- **CLI** (`cli/`) — Entry point (`Main`), interactive REPL, terminal renderer, REPL history, and project init scaffolding.
- **Commands** (`commands/`) — Slash-command system with a parser, registry, and individual handler modules (e.g., `/help`, `/model`, `/effort`, `/thinking`, `/compact`, `/config`, `/connect`, `/databases`, `/resume`).
- **Database** (`database/`) — `ConnectionManager` for named MySQL/PostgreSQL connections, `AuditLogger` and `QueryLog` for structured query logging.
- **Gateway** (`gateway/`) — Routes inbound messages from external chat channels (Discord first) to persistent Viber sessions via the `Viber.Gateway.Adapter` behaviour and a central `Router`.
- **Runtime** (`runtime/`) — Session management, conversation state, config loading, permissions, prompt building, usage tracking, conversation compaction, sub-agents, and skills.
- **Scheduler** (`scheduler/`) — Quantum-based cron jobs: `Runner` executes jobs (SQL/scripts/health checks), `JobStore` persists them, `AlertSink` dispatches notifications (Slack webhook, file, log).
- **Server** (`server/`) — Optional HTTP/SSE server (Bandit + Plug) on port 4100 for programmatic access, with session handler and SSE streaming.
- **Tools** (`tools/`) — Tool spec definition (with optional input-dependent `permission_fn`), registry, executor, built-in tools (bash, file_ops, glob, grep, ls, web_fetch, git, scheduler, mysql_*, data_export, …), and MCP (Model Context Protocol) client/server integration.

Additional top-level modules: `HotReloader` (file-system watcher for live code reloading) and `Repo` (Ecto repo).

A Mix task (`mix viber`) starts the REPL via `Mix.Tasks.Viber`. The OTP application tree starts registries, a dynamic supervisor for sessions, a task supervisor, the MCP server manager, and (by config) the repo, scheduler, gateway, and HTTP server.

## Build, Test, and Development Commands

```sh
mix deps.get          # Install dependencies
mix compile           # Compile the project
mix test              # Run all tests
mix test path/to/test.exs          # Run a single test file
mix test path/to/test.exs:42       # Run a specific test by line
mix test --failed     # Re-run only previously failed tests
mix format            # Format code
mix format --check-formatted       # Check formatting (CI)
mix credo             # Run Credo static analysis
mix dialyzer          # Run Dialyzer for static type analysis
mix checklist         # Run all checks: format, compile, test, credo, dialyzer
mix viber             # Start the interactive REPL
mix escript.build     # Build the CLI escript binary
```

Use `mix checklist` when finishing any set of changes to catch issues before committing.

## Coding Style & Naming Conventions

- Formatter: `mix format` with default Elixir formatter settings (`.formatter.exs` covers `{mix,.formatter}.exs`, `{config,lib,test}/**/*.{ex,exs}`).
- Static analysis: Dialyzer via `dialyxir` (dev-only dependency).
- Modules use `@moduledoc` consistently. Typespecs (`@spec`, `@type`, `@callback`) are used for public APIs.
- Test support modules live in `test/support/` and are compiled only in the `:test` environment (`elixirc_paths`).

## Testing Guidelines

- Framework: ExUnit (standard `mix test`).
- Tests mirror the `lib/` directory structure under `test/viber/`.
- Mock provider: `test/support/mock_provider.ex` implements the `Viber.API.Provider` behaviour for testing.
- Integration tests: `test/viber/integration_test.exs` covers cross-module workflows.

## Elixir Gotchas

- **List index access**: Lists do not support `list[i]`. Use `Enum.at(list, i)`, pattern matching, or `List` functions instead.
- **Block expression rebinding**: The result of `if`/`case`/`cond` must be bound at the call site. Rebinding a variable inside the block has no effect outside it:
  ```elixir
  # WRONG — socket is unchanged after this
  if condition do
    socket = assign(socket, :key, value)
  end

  # CORRECT
  socket = if condition do
    assign(socket, :key, value)
  else
    socket
  end
  ```
- **Struct field access**: Never use `struct[:field]` on structs that don't implement `Access`. Always use `struct.field` directly.
- **`String.to_atom/1` on user input**: Atoms are not garbage collected — never convert arbitrary user/external input to atoms. Use `String.to_existing_atom/1` if the atom must already exist.
- **Predicate naming**: Predicate functions must end in `?` (e.g., `connected?/1`), never start with `is_`. The `is_` prefix is reserved for guard macros.
- **Never nest modules in the same file**: Multiple `defmodule` blocks in one file can cause cyclic dependency and compilation errors.

## Idiomatic Elixir Review Checklist

- Keep stream/event adapters incremental: when converting provider stream chunks, emit only the new delta fragment, not the accumulated buffer.
- Keep specs and call sites aligned: if a function contract expects a map payload, avoid passing `nil`; use `%{}` for empty params.
- Treat `mix dialyzer` warnings as merge blockers for public/runtime paths (`lib/`), especially unknown function and contract warnings.
- Add focused tests for streaming tool-call assembly and MCP notification payload shapes to prevent regressions in protocol adapters.
- Verify error handling is complete: every `{:error, reason}` return and `rescue`/`catch` block should be handled or explicitly propagated — avoid silently swallowing errors.

## Dependencies

Key runtime dependencies: `req` (HTTP), `jason` (JSON), `plug` + `bandit` (HTTP server), `owl` (terminal UI), `ecto_sql` + `postgrex` + `myxql` (database), `quantum` (cron scheduling), `file_system` (hot reload). Dev-only: `dialyxir` (Dialyzer), `credo` (static analysis).
