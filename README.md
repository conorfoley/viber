# Viber

An AI-powered coding assistant built in Elixir. Viber provides an interactive CLI/REPL and an HTTP/SSE server for LLM-driven coding workflows — file editing, shell commands, database queries, scheduled jobs, and more — all managed through a conversational interface with a fine-grained permission system.

## Features

- **Multi-provider LLM support** — Anthropic Claude and OpenAI-compatible APIs (OpenAI, xAI Grok, Ollama) with streaming responses and model alias resolution
- **Interactive REPL** — Terminal-based chat with rich Markdown rendering, persistent history, slash commands, and session save/resume
- **Sub-agents** — Spawn isolated parallel agents from within a conversation; each inherits the parent's model, config, and permissions but starts with a fresh session. Sub-agent tool activity streams inline to the terminal with visual indentation
- **34 built-in tools** — File operations, shell execution, grep/glob search, git, test runner, code formatter, static analysis (Dialyzer/Credo), clipboard, `jq`, Ecto schema inspector, web search, Hex package lookup, inline docs, image viewer, and more
- **Database tooling** — Named MySQL/PostgreSQL connections; run queries, inspect schemas, explain plans, export data (CSV/JSON/SQL), and transform results in-memory
- **Scheduled jobs** — Quantum-based cron scheduler for SQL queries, shell scripts, and health checks with alerting (Slack webhook, file, log)
- **Permission system** — Five-tier model (`:read_only` → `:workspace_write` → `:danger_full_access`, plus `:prompt` and `:allow`) with per-tool dynamic permission functions and an "always allow" option
- **Gateway / Discord integration** — Receive messages from Discord (and future chat platforms) via a webhook adapter; sessions are persistent per user/channel
- **MCP integration** — Model Context Protocol client and server for extending tool capabilities
- **HTTP/SSE server** — Programmatic access on port 4100 for IDE integrations and automation
- **Hot reloading** — File-system watcher that reloads only changed BEAM files during development

## Requirements

- Elixir 1.19+ / Erlang OTP 28+
- PostgreSQL (for session persistence; optional but recommended)

## Installation

```sh
git clone <repo-url> && cd viber
mix deps.get
mix compile
```

### Run as a Mix task

```sh
mix viber
```

### Build the CLI binary

```sh
mix escript.build
./viber
```

## Configuration

Config files are loaded and merged in order: user → project → local.

| File | Purpose |
|---|---|
| `~/.config/viber/settings.json` | User-level defaults |
| `.viber/settings.json` | Project-level config (commit this) |
| `.viber/settings.local.json` | Local overrides (gitignore this) |

Run `/init` in the REPL to scaffold a `.viber/settings.json` in your project root, or create one manually:

```json
{
  "model": "sonnet",
  "permissions": "prompt"
}
```

Environment variables take precedence over config files:

| Variable | Description |
|---|---|
| `ANTHROPIC_API_KEY` | Anthropic Claude API key |
| `OPENAI_API_KEY` | OpenAI API key |
| `XAI_API_KEY` | xAI (Grok) API key |
| `OLLAMA_HOST` | Ollama server URL |
| `VIBER_MODEL` | Default model override |
| `VIBER_START_SERVER` | Set to `true` to start the HTTP server |

## Usage

### REPL

Start with `mix viber`. Type naturally to chat with the LLM. Use `@path/to/file` in any message to inline file contents into the prompt.

### Slash Commands

| Command | Description |
|---|---|
| `/help` | Show available slash commands |
| `/model [name]` | Switch LLM model |
| `/compact` | Summarise and compact conversation history |
| `/config` | View or update configuration |
| `/clear` | Clear conversation history |
| `/status` | Show session status and token usage |
| `/attach [pattern]` | Attach files to context via glob or path |
| `/toolset [name]` | Enable or disable a tool group |
| `/connect` | Connect to a database |
| `/databases` | List active database connections |
| `/apikey [key]` | Set API key for the current session |
| `/resume [id]` | List recent sessions, resume a conversation, or purge old sessions |
| `/retry` | Undo the last turn and re-send the same input |
| `/undo` | Remove the last conversation turn |
| `/reload` | Recompile and hot-reload Viber source modules |
| `/init` | Scaffold a `.viber/settings.json` config |
| `/bug` | Generate a bug report template |
| `/doctor` | Check environment, connectivity, and configuration |

### Model Aliases

Short aliases resolve to full model names:

| Alias | Model |
|---|---|
| `sonnet` | claude-sonnet-4-6 |
| `opus` | claude-opus-4-6 |
| `haiku` | claude-haiku-4-5-20251213 |
| `gpt4o` | gpt-4o |
| `gpt41` | gpt-4.1 |
| `o3` | o3 |
| `o3-mini` | o3-mini |
| `o4-mini` | o4-mini |
| `grok` | grok-3 |
| `grok-mini` | grok-3-mini |
| `llama3`, `llama3.1`, `llama3.2` | Ollama Llama 3 variants |
| `mistral`, `codestral` | Ollama Mistral models |
| `qwen2.5`, `phi4`, `gemma3`, `deepseek-r1` | Other Ollama local models |

### Sub-agents

The `spawn_agent` tool lets the LLM delegate independent work to isolated child agents. Multiple `spawn_agent` calls in the same turn run in parallel. Sub-agent tool calls stream inline to the terminal, visually indented with `↳`.

### Discord Gateway

1. Set credentials in `config/runtime.exs`:

   ```elixir
   config :viber, :discord,
     bot_token:      System.get_env("DISCORD_BOT_TOKEN"),
     public_key:     System.get_env("DISCORD_PUBLIC_KEY"),
     application_id: System.get_env("DISCORD_APPLICATION_ID")
   ```

2. Enable the HTTP server (`VIBER_START_SERVER=true`).
3. Point Discord's Interactions Endpoint URL at `https://<your-host>/gateway/discord`.

The `/viber` slash command is registered automatically on startup. Proactive messages can be sent programmatically via `Viber.Gateway.send_to_channel/3` and `Viber.Gateway.broadcast/1`.

### HTTP/SSE Server

Start with `VIBER_START_SERVER=true mix viber`. The server listens on port 4100 and exposes a streaming SSE API for IDE integrations and automation.

## Development

```sh
mix deps.get                         # Install dependencies
mix compile                          # Compile
mix test                             # Run all tests
mix test path/to/test.exs            # Run a single test file
mix test path/to/test.exs:42         # Run a test by line
mix format                           # Format code
mix format --check-formatted         # Check formatting (CI)
mix dialyzer                         # Static type analysis
mix credo                            # Code quality checks
mix test.live                        # Run live integration tests (requires API keys)
```

## Architecture

Viber is organised into eight domains under `lib/viber/`:

- **API** — Provider behaviour, Anthropic and OpenAI-compatible implementations, streaming SSE parser, model alias resolution
- **CLI** — Escript entry point, interactive REPL with history, terminal Markdown renderer, `init` scaffolding
- **Commands** — Slash-command parser, registry, and individual handler modules
- **Database** — Named connection pool management (MySQL/PostgreSQL), audit logger, query log
- **Gateway** — Multi-adapter message bus; Discord webhook adapter with Ed25519 signature verification
- **Runtime** — Session GenServer, conversation turn loop, sub-agent runner, system prompt builder, permission broker, config, usage tracking, compaction, session persistence
- **Scheduler** — Quantum-based cron job engine with alert sink integration
- **Server** — Bandit/Plug HTTP server, SSE streaming, session handler
- **Tools** — `Spec` struct with static and dynamic permissions, registry, executor, 34 built-in tools, MCP client/server

See [VIBER.md](VIBER.md) for detailed architecture, conventions, and key file references.

## License

[AGPL-3.0](LICENSE)
