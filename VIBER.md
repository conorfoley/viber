# Project Instructions

## Overview
Viber is an Elixir port of the Claw AI coding assistant. It provides an interactive CLI/REPL and an HTTP/SSE server for LLM-powered coding workflows. Built as an OTP application with an escript entry point.

## Stack
- Language: Elixir 1.19 / OTP
- HTTP client: Req
- HTTP server: Bandit + Plug (port 4100)
- JSON: Jason
- Terminal UI: Owl
- Static analysis: Dialyzer (dialyxir), Credo

## Architecture
Six domains under `lib/viber/`:
- **API** — Provider behaviour (`Viber.API.Provider`), Anthropic + OpenAI implementations, streaming SSE parser, model alias resolution via `Client`.
- **CLI** — `Main` escript entry point, interactive REPL, terminal renderer, `init` scaffolding.
- **Commands** — Slash-command system: parser, registry, handlers (`/help`, `/model`, `/compact`, `/config`).
- **Runtime** — `Session` (GenServer per conversation), `Conversation` (turn loop + tool execution), `Prompt` (system prompt builder), `Permissions` (mode ladder), `Usage` tracking, `Compaction`.
- **Server** — HTTP/SSE server for programmatic access, session handler, SSE streaming.
- **Tools** — `Spec` (tool definition + dynamic permissions via `permission_fn`), `Registry`, `Executor`, built-in tools, MCP client/server.

## Permission Model
Five modes: `:read_only` < `:workspace_write` < `:danger_full_access`, plus `:prompt` (default, auto-allows read-only tools, prompts for the rest) and `:allow` (everything auto-allowed).

Tools declare a static `permission` level. Tools may also provide a `permission_fn` that inspects the input to return a dynamic permission — e.g., the `git` tool returns `:read_only` for `status`/`log`/`diff` but `:workspace_write` for `commit`/`checkout`.

## Built-in Tools
`bash`, `read_file`, `write_file`, `edit_file`, `multi_edit`, `glob_search`, `grep_search`, `ls`, `web_fetch`, `test_runner`, `diagnostics`, `formatter`, `mix_task`, `git`, `clipboard`, `jq`, `user_input`, `ecto_schema_inspector`

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
- `lib/viber/tools/registry.ex` — All built-in tool specs with schemas, permissions, and handlers.
- `lib/viber/tools/spec.ex` — Tool spec struct including optional `permission_fn` for input-dependent permissions.
- `lib/viber/tools/executor.ex` — Dispatches tool calls to handlers.
- `lib/viber/api/client.ex` — LLM client with model alias resolution and streaming.
- `lib/viber/application.ex` — OTP supervision tree.
- `mix.exs` — Project config, deps, escript setup.
