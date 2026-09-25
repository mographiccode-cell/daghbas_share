# Codex Integration

This folder contains a local Codex lifecycle hook bridge.

## What it intercepts

- `UserPromptSubmit`: sends the outgoing user prompt to the Security Guard API before Codex continues.
- `PreToolUse`: sends supported local tool calls (Bash, `apply_patch`, MCP tools, and other local function tools) to the Security Guard API before execution.

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

4. Copy `agent_guard_hook.py` to your project at `.codex/hooks/agent_guard_hook.py`.
5. Merge `hooks.json` into a Codex hook configuration that your environment trusts.

> Codex lifecycle hooks are a guardrail for supported local function-tool paths. They are not a complete security boundary for every possible hosted or specialized tool path.
