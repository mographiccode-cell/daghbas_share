# AI Agent Security Guard

A bilingual (English/Arabic) web security platform that extends the ideas of **Agent Threat Scanner** into a multi-user runtime protection workflow for AI agents and Codex.

## Core capabilities

- Account creation and secure sign-in.
- Strict per-user data isolation for scans, policies, approvals, logs, and integration tokens.
- Static security rules for prompt injection, secret access, sensitive files, data exfiltration, remote execution, command injection, destructive actions, obfuscation, privilege escalation, persistence, and network abuse.
- Optional local LLM semantic review through **Ollama**.
- Risk scoring and `allow / block / approval` decisions.
- Human approval inbox for sensitive actions.
- Audit logging, dashboard metrics, and user-scoped CSV security report export.
- Codex lifecycle hook bridge for `UserPromptSubmit`, `PreToolUse`, and `PostToolUse` so both requested actions and returned untrusted content can be evaluated.
- React + Vite web dashboard with complete English/Arabic switching and RTL support.
- SQLite now, with SQLAlchemy models kept portable for later PostgreSQL migration.
- Optional compatibility adapter for the original `@estelwalks/agent-threat-scanner` v0.2.0.

## Architecture

```text
Codex / VS Code
      |
      v
Codex lifecycle hooks
      |
      v
FastAPI Security API ------------------- React/Vite Dashboard
      |                                        |
      |                                        +-- Approve / Reject
      v
Rules Engine + optional Ollama LLM
      |
      +-- Allow
      +-- Block
      +-- Require Approval
      |
      v
SQLite: users / scans / policies / approvals / audit logs
```

## Security design

- Passwords are hashed with Argon2.
- Browser sessions use signed JWT access tokens.
- Codex uses a separate random integration token; only its SHA-256 digest is stored in SQLite.
- Every user-owned query includes `user_id` filtering.
- `.env`, SQLite DB files, private keys, node modules, local reports, and test DBs are excluded by `.gitignore`.
- LLM analysis is optional and defaults to a local Ollama endpoint, so prompts do not need to leave the machine.
- Codex hook mode defaults to fail-closed if the security API is unavailable.

## Quick start on Windows

### 1. Backend

```powershell
cd backend
python -m venv .venv
.\.venv\Scripts\Activate.ps1
pip install -r requirements.txt
$env:JWT_SECRET="replace-with-a-long-random-secret-value"
python -m uvicorn app.main:app --host 127.0.0.1 --port 8000 --reload
```

API docs: `http://127.0.0.1:8000/docs`

### 2. Frontend

```powershell
cd frontend
npm install
npm run dev
```

Open: `http://127.0.0.1:5173`

### 3. Optional local LLM

Install Ollama and pull a local model, then enable:

```powershell
$env:OLLAMA_ENABLED="true"
$env:OLLAMA_MODEL="qwen2.5:3b"
```

If Ollama is unavailable, the application automatically keeps the deterministic rules result instead of failing the scan.

### 4. Codex integration

Open **Codex Integration** in the dashboard, generate a token, then follow `codex/README.md`.

## Tests

```bash
cd backend
PYTHONPATH=. pytest -q
```

The test suite includes 15 requirement-mapped tests (`FR01`–`FR15`) plus regression tests covering authentication, prompt/tool/output scanning, approvals, tenant isolation, policies, audit logs, secret redaction, filtering, and report export. See `TEST_REPORT.md` for verified results.

## Upstream scanner

The `scanner-core/` directory integrates `@estelwalks/agent-threat-scanner` v0.2.0 for deeper artifact scanning. See `THIRD_PARTY_NOTICES.md` for attribution and the upstream MIT license.

## Current scope

This academic release protects supported Codex lifecycle hook paths and the web/API workflow. OpenAI documents that some hosted or specialized tool paths may not pass through the default local function-tool hook path, so hooks should be treated as a strong guardrail rather than a universal sandbox boundary.
