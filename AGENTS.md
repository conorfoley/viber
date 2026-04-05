# Repository Guidelines

## Project Structure & Module Organization

Viber is an Elixir port of the Claw AI coding assistant — an interactive CLI/REPL and HTTP server for LLM-powered coding workflows. It is built as an OTP application with an escript entry point (`Viber.CLI.Main`).

The codebase is organized into six top-level domains under `lib/viber/`:

- **API** (`api/`) — LLM provider abstraction via `Viber.API.Provider` behaviour, with Anthropic and OpenAI-compatible implementations. Includes streaming SSE parser, typed request/response structs, and a client with model alias resolution.
- **CLI** (`cli/`) — Entry point (`Main`), interactive REPL, terminal renderer, and project init scaffolding.
- **Commands** (`commands/`) — Slash-command system with a parser, registry, and individual handler modules (e.g., `/help`, `/model`, `/compact`, `/config`).
- **Runtime** (`runtime/`) — Session management, conversation state, config loading, permissions, prompt building, usage tracking, and conversation compaction.
- **Server** (`server/`) — Optional HTTP/SSE server (Bandit + Plug) on port 4100 for programmatic access, with session handler and SSE streaming.
- **Tools** (`tools/`) — Tool spec definition, registry, executor, built-in tools (bash, file_ops, glob, grep, ls, web_fetch), and MCP (Model Context Protocol) client/server integration.

A Mix task (`mix viber`) starts the REPL via `Mix.Tasks.Viber`. The OTP application tree starts registries, a dynamic supervisor for sessions, a task supervisor, and the MCP server manager.

## Build, Test, and Development Commands

```sh
mix deps.get          # Install dependencies
mix compile           # Compile the project
mix test              # Run all tests
mix test path/to/test.exs          # Run a single test file
mix test path/to/test.exs:42       # Run a specific test by line
mix format            # Format code
mix format --check-formatted       # Check formatting (CI)
mix dialyzer          # Run Dialyzer for static type analysis
mix viber             # Start the interactive REPL
mix escript.build     # Build the CLI escript binary
```

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

## Idiomatic Elixir Review Checklist

- Keep stream/event adapters incremental: when converting provider stream chunks, emit only the new delta fragment, not the accumulated buffer.
- Keep specs and call sites aligned: if a function contract expects a map payload, avoid passing `nil`; use `%{}` for empty params.
- Treat `mix dialyzer` warnings as merge blockers for public/runtime paths (`lib/`), especially unknown function and contract warnings.
- Add focused tests for streaming tool-call assembly and MCP notification payload shapes to prevent regressions in protocol adapters.

## Dependencies

Key runtime dependencies: `req` (HTTP), `jason` (JSON), `plug` + `bandit` (HTTP server), `owl` (terminal UI).
