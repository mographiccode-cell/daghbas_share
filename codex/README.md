# Codex Integration

This folder contains a local Codex lifecycle hook bridge.

## What it intercepts

- `UserPromptSubmit`: sends the outgoing user prompt to the Security Guard API before Codex continues.
- `PreToolUse`: sends supported local tool calls (Bash, `apply_patch`, MCP tools, and other local function tools) to the Security Guard API before execution.
- `PostToolUse`: inspects returned tool output, including content read from files or MCP tools, before Codex consumes that output. This protects against indirect prompt injection inside untrusted content.

For `approval` decisions, the hook waits for a decision from the web dashboard. Approval timeout defaults to 120 seconds.

## Install

1. Start the backend at `http://127.0.0.1:8000`.
2. In the web dashboard, open **Codex Integration** and generate an integration token.
3. Set these environment variables in the shell that launches Codex:

```bash
AGENT_GUARD_URL=http://127.0.0.1:8000
AGENT_GUARD_TOKEN=ag_your_token_here
AGENT_GUARD_APPROVAL_TIMEOUT=120
AGENT_GUARD_FAIL_CLOSED=true
```

PowerShell:

```powershell
$env:AGENT_GUARD_URL="http://127.0.0.1:8000"
$env:AGENT_GUARD_TOKEN="ag_your_token_here"
$env:AGENT_GUARD_APPROVAL_TIMEOUT="120"
$env:AGENT_GUARD_FAIL_CLOSED="true"
```

4. Create `<your-project>/.codex/hooks/`, then copy `agent_guard_hook.py` there.
5. Copy this `hooks.json` to `<your-project>/.codex/hooks.json`.
6. Start Codex from the project root and review/trust the project hooks when Codex asks. You can inspect hook sources with `/hooks` in Codex CLI.

> Codex lifecycle hooks are a guardrail for supported local function-tool paths. Hosted tools such as Codex built-in WebSearch are not currently covered by PreToolUse/PostToolUse; for web content that must be enforced, route retrieval through a local/MCP tool or scan the content through the Security Guard API.
