# AI Agent Security Guard

A bilingual English/Arabic web security platform that extends the ideas of **Agent Threat Scanner** into a multi-user runtime protection workflow for AI agents and Codex.

## Core capabilities

- Account creation and secure sign-in.
- Strict per-user isolation for projects, scans, policies, approvals, audit logs, and integration tokens.
- Project management so scans/reports can be separated per user project.
- Static security rules for prompt injection, secret access, sensitive files, data exfiltration, remote execution, command injection, destructive actions, obfuscation, privilege escalation, persistence, and network abuse.
- Optional local semantic analysis through **Ollama**.
- Per-user policy controls: thresholds, enabled categories, blocked domains, blocked tools, and tools that require approval.
- Risk scoring with `allow / block / approval` decisions.
- Human approval inbox for sensitive actions.
- Codex lifecycle protection at `UserPromptSubmit`, `PreToolUse`, and `PostToolUse`.
- Audit logging, filters, live WebSocket alerts, dashboard metrics, and user/project-scoped CSV report export.
- React + Vite dashboard with English/Arabic switching and RTL support.
- SQLite now, with SQLAlchemy models kept portable for later PostgreSQL migration.
- Optional compatibility adapter for the original `@estelwalks/agent-threat-scanner` v0.2.0.

## Architecture

```text
Codex / VS Code
      |
      +--> UserPromptSubmit ----+
      +--> PreToolUse ----------+--> FastAPI Security API
      +--> PostToolUse ---------+          |
                                         +--> Rules Engine
                                         +--> Optional Ollama LLM
                                         +--> Risk / Policy Engine
                                         +--> Approval Workflow
                                         +--> SQLite
                                                  |
                                             React Dashboard
                                             + Live Alerts
```

## Security design

- Passwords are hashed with Argon2.
- Browser sessions use signed JWT access tokens.
- Codex uses a separate random integration token; only its SHA-256 digest is stored in SQLite.
- Every protected user-owned query is scoped by `user_id`.
- Raw scan content is redacted before persistence; common secret formats are not stored verbatim.
- `.env`, SQLite DB files, private keys, node modules, local reports, and test DBs are excluded by `.gitignore`.
- Ollama is optional and local-first; if unavailable, deterministic rules continue to work.
- Codex hook mode defaults to fail-closed if the security API is unavailable.
- SQLite migrations are additive so older local databases can continue to be used as features are added.

## Quick start on Windows

See **`WINDOWS_RUN_AR.md`** for the detailed Arabic Windows walkthrough.

### Backend

```powershell
cd backend
py -3 -m venv .venv
.\.venv\Scripts\Activate.ps1
pip install -r requirements.txt
$env:JWT_SECRET = (py -3 -c "import secrets; print(secrets.token_urlsafe(48))")
py -3 -m uvicorn app.main:app --host 127.0.0.1 --port 8000 --reload
```

API docs: `http://127.0.0.1:8000/docs`

### Frontend

```powershell
cd frontend
npm install
npm run dev
```

Open: `http://127.0.0.1:5173`

### Optional local LLM

```powershell
ollama pull qwen2.5:3b
$env:OLLAMA_ENABLED="true"
$env:OLLAMA_MODEL="qwen2.5:3b"
```

Restart the backend after changing these variables.

### Codex integration

1. Open **Codex Integration** in the dashboard.
2. Generate an integration token.
3. Set `AGENT_GUARD_URL` and `AGENT_GUARD_TOKEN` in the shell that launches VS Code/Codex.
4. Run:

```powershell
cd codex
.\install_hooks.bat
```

The installer backs up existing Codex hook configuration and preserves unrelated hooks. See `codex/README.md`.

## Tests

```bash
cd backend
PYTHONPATH=. pytest -q
```

Current verified result: **24 passed**. The suite contains a dedicated test for each of the 15 functional requirements. Live subprocess tests also verify the actual Codex hook bridge. See `TEST_REPORT.md`.

## Upstream scanner

The `scanner-core/` directory integrates `@estelwalks/agent-threat-scanner` v0.2.0 for deeper artifact scanning. See `THIRD_PARTY_NOTICES.md` for attribution and the upstream MIT license.

## Current security boundary

`PreToolUse` can prevent a supported local tool action before it executes. `PostToolUse` runs after execution and therefore cannot reverse side effects; it can block unsafe tool output from continuing into the agent workflow. Codex lifecycle hooks are a strong guardrail for supported paths, not a universal sandbox for every possible hosted or specialized tool path.
