# AI Agent Security Guard — Verification Report

Date: 2026-09-25
Version: 1.1.0

## Functional requirements verification

The project now has an explicit automated test for each of the 15 agreed functional requirements:

| # | Requirement | Result |
|---|---|---|
| 1 | Account creation | PASS |
| 2 | Secure sign-in | PASS |
| 3 | Per-user data isolation | PASS |
| 4 | Codex connection/integration token | PASS |
| 5 | Prompt inspection before Codex continues | PASS |
| 6 | Untrusted external/tool-response content inspection | PASS |
| 7 | Tool monitoring before execution | PASS |
| 8 | Hybrid Rules + LLM analysis path | PASS |
| 9 | Threat-category classification | PASS |
| 10 | Risk score and threat level | PASS |
| 11 | Automatic Allow / Block / Approval decision | PASS |
| 12 | Human Approve / Reject workflow | PASS |
| 13 | Per-user security-policy management | PASS |
| 14 | User-scoped audit trail | PASS |
| 15 | Dashboard + filters + live alerts + CSV report | PASS |

## Automated backend suite

Command:

```bash
cd backend
PYTHONPATH=. pytest -q
```

Result: **24 passed**.

The suite includes the 15 requirements above plus regression/hardening tests for project isolation, scan/project association, raw-secret redaction, and previous API behavior.

## Live Codex-hook integration

A real Uvicorn server was started and `codex/hooks/agent_guard_hook.py` was executed as a separate subprocess using Codex-style JSON events.

Verified live paths:

- dangerous `UserPromptSubmit` -> block;
- safe `PreToolUse` -> allow;
- dangerous `PreToolUse` -> deny before execution;
- malicious `PostToolUse.tool_response` -> block from continuing into the Codex workflow;
- sensitive action -> hook waits, dashboard/API approves, hook returns allow;
- sensitive action -> dashboard/API rejects, hook returns deny.

Result: **6/6 live hook scenarios passed**.

## Codex installer verification

`codex/install_hooks.py` was tested against a temporary user home containing an existing unrelated Codex hook.

Verified:

- existing hook preserved;
- backup of `hooks.json` created;
- UserPromptSubmit / PreToolUse / PostToolUse inserted;
- installer run a second time without duplicate Agent Guard entries;
- hook script copied into the user `.codex/hooks` directory.

Result: **PASS**.

## WebSocket/live-alert verification

The automated FR15 test establishes an authenticated WebSocket connection, triggers a security scan, and receives a `scan.completed` event containing the scan decision.

Result: **PASS**.

## Rules + LLM verification

Two layers were verified:

1. Automated functional test combines a static rule finding and a semantic LLM finding in one scan.
2. The actual Ollama HTTP adapter was tested against a local mock `/api/generate` service using the same request/response shape. The returned security JSON was parsed successfully.

Result: **PASS for integration path**.

A real Ollama model was not installed in the isolated build environment, so semantic model quality/accuracy was not benchmarked here. On the user's machine, install Ollama and enable it through the documented environment variables for real-model evaluation.

## Frontend verification

- `App.jsx` and `main.jsx` parsed successfully with the installed TypeScript JSX parser.
- JavaScript modules passed syntax checks.
- English and Arabic UI strings are provided for the implemented pages/features, including Projects, policy lists, filters, integration, and approvals.

A complete `npm install && npm run build` could not be completed inside the isolated environment because external npm package installation timed out. This is an environment limitation rather than a discovered source syntax error. A normal internet-connected Windows machine should run `npm install` and then `npm run dev`/`npm run build` as the final frontend build verification.

## Security/hardening verification

- SQLite runtime DB files are excluded by `.gitignore`.
- `.env` is excluded; only `.env.example` is included.
- integration tokens are stored as SHA-256 digests in SQLite;
- raw scan content is redacted before persistence;
- findings/audit detail fields are redacted before persistence;
- a source-tree scan found **0 real-looking private keys, GitHub tokens, OpenAI keys, or AWS access keys** after test cleanup;
- if `JWT_SECRET` is missing, the backend generates a random process-local secret instead of using a known hard-coded production fallback;
- SQLite foreign-key enforcement is enabled for new connections;
- additive SQLite migration logic keeps older local databases usable when new policy/scan columns are introduced;
- an old-schema SQLite database was created in a migration test; the new policy columns, `project_id`, and `projects` table were added successfully.

## Current boundary

`PreToolUse` is the preventive control for side effects. `PostToolUse` runs after a tool has executed, so it cannot undo a tool side effect; it can prevent unsafe tool output from reaching the next Codex step. Hosted/specialized paths not routed through supported Codex lifecycle hooks should not be treated as covered by this local guard.
