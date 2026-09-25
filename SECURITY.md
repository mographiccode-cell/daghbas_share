# Security Notes

## Secrets

Never commit real values for `JWT_SECRET`, `AGENT_GUARD_TOKEN`, LLM/API keys, OAuth credentials, private keys, or production database URLs. Use local environment variables or an appropriate secret manager.

The Codex integration token is generated randomly by the backend. The application stores only its SHA-256 digest in SQLite; the plaintext token is returned only when it is generated/rotated.

## Local-first LLM

Ollama integration is disabled by default. When enabled, the configured local Ollama server receives the content being analyzed. If you point `OLLAMA_URL` at a remote service, review its privacy/security properties first.

## Codex hooks

The included hooks default to fail-closed if the security API is unavailable. OpenAI documents that lifecycle hooks cover supported local function-tool paths but may not cover every hosted or specialized tool path. Treat the hook layer as a strong guardrail, not a universal sandbox.

## Reporting vulnerabilities

For an academic deployment, report vulnerabilities privately to the project owner rather than posting credentials, tokens, or exploit details in public issues.
