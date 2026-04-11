# Viber

An AI-powered coding assistant built in Elixir. Viber provides an interactive CLI/REPL and an HTTP/SSE server for LLM-driven coding workflows — file editing, shell commands, database queries, scheduled jobs, and more — all managed through a conversational interface with a fine-grained permission system.

## Features

- **Multi-provider LLM support** — Anthropic Claude and OpenAI-compatible APIs (OpenAI, Ollama, etc.) with streaming responses and model alias resolution
- **Interactive REPL** — Terminal-based chat with rich rendering, slash commands, and session persistence/resumption
- **25+ built-in tools** — File operations, shell execution, grep/glob search, git, test runner, code formatter, diagnostics (Dialyzer/Credo), and more
- **Database tooling** — Connect to MySQL and PostgreSQL databases; run queries, inspect schemas, explain plans, export data, and transform results
- **Scheduled jobs** — Cron-based job scheduler for SQL queries, shell scripts, and health checks with alerting (Slack, file, log)
- **Permission system** — Five-tier permission model (read-only → full access) with per-tool dynamic permission functions
- **MCP integration** — Model Context Protocol client and server for extending tool capabilities
- **HTTP/SSE server** — Programmatic access on port 4100 for IDE integrations and automation
- **Hot reloading** — File-system watcher for live code reloading during development

## Requirements

- Elixir 1.19+
- Erlang/OTP (compatible with Elixir 1.19)

## Installation

```sh
git clone <repo-url> && cd viber
mix deps.get
mix compile
```

### Build the CLI binary

```sh
mix escript.build
./viber
```

### Run as a Mix task

```sh
mix viber
```

## Usage

### REPL

Start the interactive REPL with `mix viber` or the built escript. Type naturally to chat with the LLM, which can read/write files, run commands, query databases, and more.

### Slash Commands

| Command | Description |
|---------|-------------|
| `/help` | Show available commands |
| `/model` | Switch LLM model |
| `/compact` | Compact conversation history |
| `/config` | View/update configuration |
| `/clear` | Clear conversation |
| `/status` | Show session status |
| `/attach` | Attach files to context |
| `/bug` | Report a bug |
| `/connect` | Connect to a database |
| `/databases` | List database connections |
| `/init` | Initialize project config |
| `/reload` | Reload configuration |
| `/resume` | Resume a previous session |

### HTTP/SSE Server

Start with `VIBER_START_SERVER=true mix viber` or configure in your project's `.viber.json`. The server listens on port 4100 by default.

## Configuration

Create a `.viber.json` in your project root or set environment variables. Run `/init` in the REPL to generate a starter config.

## Development

```sh
mix deps.get          # Install dependencies
mix compile           # Compile
mix test              # Run all tests
mix test path/to/test.exs          # Run a single test file
mix test path/to/test.exs:42       # Run a test by line
mix format            # Format code
mix format --check-formatted       # Check formatting
mix dialyzer          # Static type analysis
mix credo             # Code quality checks
```

## Architecture

Viber is organized into eight domains:

- **API** — LLM provider abstraction with streaming SSE parser
- **CLI** — Entry point, REPL, and terminal rendering
- **Commands** — Slash-command parser, registry, and handlers
- **Database** — Connection management, audit logging, query log
- **Runtime** — Session management, conversation loop, permissions, config, usage tracking
- **Scheduler** — Cron job execution with alerting
- **Server** — HTTP/SSE server (Bandit + Plug)
- **Tools** — Tool specs, registry, executor, built-ins, and MCP integration

See [VIBER.md](VIBER.md) for detailed architecture and conventions.

## License

TODO: Add license
