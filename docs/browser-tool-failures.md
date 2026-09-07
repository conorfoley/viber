# Browser Tool Failures: `browser_navigate` and `browser_get_accessibility_tree`

## Summary

During a session where Viber successfully used `browser_navigate` and `browser_get_accessibility_tree` early on, both tools began returning `"Content script error: Error: Missing host permission for the tab"` after a page navigation that caused the browser extension to lose its tab connection. All subsequent calls to any browser tool in that session failed with the same error.

## What Happened

The sequence was:

1. `browser_get_accessibility_tree` — ✅ succeeded (YouTube page)
2. `browser_click` — ✅ succeeded (filled PR description textarea)
3. `browser_click` — ✅ succeeded (submitted the PR form)
4. `browser_navigate` to `github.com/.../pulls` — ❌ `Missing host permission for the tab`
5. `browser_get_accessibility_tree` — ❌ same error
6. Every subsequent browser tool call — ❌ same error

## Root Cause (Hypothesis)

The error `"Missing host permission for the tab"` is a Chrome/Firefox extension error thrown when the content script attempts to call `chrome.tabs.sendMessage` (or equivalent) on a tab that it no longer has access to. This happens because:

- **The form submission navigated the tab away** from the GitHub PR page to a new URL. After the navigation, the tab's content script context was destroyed and a new one was loaded for the new page.
- **The extension's active tab reference became stale.** The backend `BrowserAction.Broker` still holds a reference to the old tab/port, and when it sends the next action, the extension tries to relay it to a content script that no longer exists in that tab context.
- **Host permissions** are not actually missing — the error is misleading. The real issue is a dead message channel to the content script, which manifests as a host permission error in some extension APIs.

## Affected Code

- **`lib/viber/runtime/browser_action.ex`** / **`BrowserAction.Broker`** — The broker dispatches actions to the extension and awaits results via `POST /sessions/:id/browser_action_result`. It has no mechanism to detect that the extension's tab connection has been invalidated by a navigation.
- **`lib/viber/server/router.ex`** — `browser_navigate` has `handler: nil`, meaning the backend sends it as a `browser_action` SSE event to the extension. After the extension executes the navigation, the tab transitions and the content script unloads — but there is no re-registration handshake to re-establish the connection for the new page.
- **Browser extension side** — After executing `browser_navigate`, the extension needs to wait for the new page to load, re-inject the content script, and signal the backend that the tab is ready before the next browser action is dispatched.

## What to Fix

1. **Extension: re-register after navigation.** After `browser_navigate` resolves (i.e. the tab's `onUpdated` fires with `status: "complete"`), the extension should re-inject the content script and send a `tab_ready` or `reconnect` event back to the backend before resolving the action result.

2. **Broker: wait for tab-ready before dispatching the next action.** After a `browser_navigate` action completes, the broker should pause dispatch of subsequent browser actions until it receives confirmation that the new page's content script is active. A short timeout with a clear error is better than silently failing.

3. **Better error surfacing.** The raw extension error string (`"Content script error: Error: Missing host permission for the tab"`) is opaque. The broker or executor should detect this pattern and return a more actionable message to the LLM, e.g. `"Browser tab connection lost after navigation — waiting for page to re-register."` This lets the model retry or inform the user rather than repeatedly calling failing tools.

4. **Consider a `browser_wait_for_load` tool.** An explicit tool that blocks until the current tab reports `status: "complete"` would let the LLM sequence navigation + action safely without relying on implicit timing.

## Reproduction Steps

1. Start a Viber session with the browser extension connected.
2. Use `browser_navigate` to go to a page that triggers a full navigation (e.g. submitting a form, or navigating between domains).
3. Immediately call `browser_get_accessibility_tree` or any other browser tool.
4. Observe: `Content script error: Error: Missing host permission for the tab`.

## Severity

**Medium.** The session remains functional for all non-browser tools. However, once browser tools start failing, they fail for the remainder of the session with no recovery path short of the user manually reloading the extension or opening a new session.
