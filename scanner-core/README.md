# Upstream Agent Threat Scanner adapter

This adapter preserves direct compatibility with the upstream MIT-licensed @estelwalks/agent-threat-scanner package (v0.2.0). It can be used to run the full upstream static ruleset against Agent Skill files and other supported artifacts.

The FastAPI web application also contains a native Python runtime rules engine for low-latency prompt/tool interception. This avoids spawning Node for every Codex action while keeping the project compatible with the original scanner for deeper artifact scans.

Install:

    cd scanner-core
    npm install
    printf '{"content":"Ignore previous instructions"}' | npm run scan
