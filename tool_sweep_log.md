# Viber Tool Sweep Log

- **Date:** 2026-09-27
- **Working directory:** `/home/deck/Projects/viber`
- **Environment:** Elixir 1.20.4 / OTP 27, headless SteamOS session
- **Scope:** Read-only sweep across all built-in tools; stateful tools (write/edit/multi_edit) exercised against `/tmp` only.
- **Post-hoc note (user-confirmed):** several failures below were caused by the user not responding to permission prompts in time (timeouts), not by tool defects. Affected entries are reclassified in §Reclassifications.

## Summary

| Category | Count |
|---|---|
| ✅ Working | 33 |
| ❌ Broken (initial) | 2 |
| ⚠️ Degraded / unverifiable | 3 |
| ♻️ Reclassified as permission-timeout artifacts (user-confirmed) | 2 |
| ❌ Confirmed defects after reclassification | 1 (diagnostics false-negative) |

## ✅ Working

`bash` · `ls` · `git` (status/log) · `grep_search` · `glob_search` · `read_file` · `write_file` · `edit_file` · `multi_edit` · `jq` · `docs_lookup` · `hex_package_info` (info/versions) · `formatter` (check, content + path modes) · `web_search` · `web_fetch` · `spawn_agent` (worker + reviewer roles) · `mix_task` · `scheduler` (list) · `ecto_schema_inspector` (graceful "not found") · `skill` (graceful unknown-skill error) · `image_view` (graceful bad-format error) · `mysql_schema` / `data_transform` (graceful "no active connection")

Notes:

- `spawn_agent` worker ping and reviewer verdict both succeeded (`VERDICT: passed`).
- `formatter`, `skill`, `image_view`, `hex_package_info` (unknown package), `docs_lookup` (unknown module), `grep_search`/`glob_search` (no matches) all return clean, non-crashing error messages for invalid input.
- `jq` correctly errored on a bad filter (array indexed with a string) and passed on the corrected filter — expected behavior.

## ❌ Broken (pre-reclassification)

See §Reclassifications — both entries below were reclassified after user confirmation that the failures were permission-prompt timeouts.

### 1. `clipboard` (read)

- **Error:** `Failed to read clipboard: Error: target STRING not available`
- **Cause:** No clipboard backend available in the headless/SteamOS session.
- **Severity:** Real defect. The tool surfaces a raw backend error instead of a clean, user-friendly failure (e.g. "no clipboard available in this environment").

### 2. `diagnostics` (credo)

- **Symptom:** Called with `path: lib/viber/ex.ex` (nonexistent). Structured result reported:

  ```
  Tool: credo
  Findings: 0
  No issues found.
  ```

  ...while the attached raw output shows an actual crash:

  ```
  ** (File.Error) could not read file "/home/deck/Projects/viber/lib/viber/ex.ex": no such file or directory
      (credo 1.7.19) lib/credo/sources.ex:229: Credo.Sources.to_source_file/1
  ```

- **Severity:** Real defect — a crash is being swallowed and reported as a **false-negative pass** ("No issues found"). A missing file (or any Credo invocation crash) should be surfaced as an error, not zero findings.

## ⚠️ Degraded / Unverifiable

| Tool(s) | Status |
|---|---|
| `browser_*` (all 6) | `browser_navigate` to https://example.com timed out: "is the extension connected?" — browser extension not connected; all browser tools likely affected. |
| `mysql_query`, `mysql_explain`, `data_export` | No active database connection; no credentials in env or `.viber.json`. Degrade gracefully ("No active database connection") but functional behavior could not be verified. |

## ♻️ Reclassifications (user-confirmed: permission prompts timed out)

The user confirmed they did not respond to approval prompts in time during the sweep. The following failures are **permission-timeout artifacts, not tool defects**:

| Tool | Original failure | Likely true cause |
|---|---|---|
| `clipboard` (read) | `target STRING not available` | Prompt timed out before the clipboard backend was granted/started |
| `browser_*` (all 6) | `browser_navigate` timeout, "is the extension connected?" | Extension connection likely gated behind a timed-out approval |

`diagnostics` (credo false-negative) is **not** affected by this explanation — it occurred on a fully permitted, in-workspace call and still misreported a crash as "Findings: 0". That remains the only confirmed defect from the sweep.

## Recommended Fixes

1. **Diagnostics:** parse tool exit status / crash markers in the output; any non-zero exit or `** (EXIT` / `File.Error` frame should be reported as an error, never as `findings: 0`.
2. **Prompt UX:** permission-prompt timeouts should surface a distinct "approval timed out" result (rather than a backend/extension error) so timeouts are not mistaken for tool defects. Consider extending the approval window or auto-reminding the user.
3. **Cleanup:** `/tmp/viber_smoke.txt` and `/tmp/viber_write.txt` (sweep test artifacts) removed on 2026-09-27.
