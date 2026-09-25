#!/usr/bin/env python3
"""Codex lifecycle hook bridge for AI Agent Security Guard.

Reads Codex hook JSON from stdin and sends only the minimum required event data
into the locally configured security API. Secrets are read from environment
variables and are never printed.
"""
import json
import os
import sys
import time
import urllib.error
import urllib.request

BASE_URL = os.getenv('AGENT_GUARD_URL', 'http://127.0.0.1:8000').rstrip('/')
TOKEN = os.getenv('AGENT_GUARD_TOKEN', '')
TIMEOUT = int(os.getenv('AGENT_GUARD_APPROVAL_TIMEOUT', '120'))
FAIL_CLOSED = os.getenv('AGENT_GUARD_FAIL_CLOSED', 'true').lower() in {'1','true','yes','on'}


def request_json(path, method='GET', payload=None):
    data = None if payload is None else json.dumps(payload).encode('utf-8')
    req = urllib.request.Request(
        BASE_URL + path,
        data=data,
        method=method,
        headers={
            'Content-Type': 'application/json',
            'X-Agent-Guard-Token': TOKEN,
        },
    )
    with urllib.request.urlopen(req, timeout=10) as res:
        return json.loads(res.read().decode('utf-8'))


def block_prompt(reason):
    print(json.dumps({'decision': 'block', 'reason': reason}, ensure_ascii=False))


def block_tool(reason):
    print(json.dumps({
        'hookSpecificOutput': {
            'hookEventName': 'PreToolUse',
            'permissionDecision': 'deny',
            'permissionDecisionReason': reason,
        }
    }, ensure_ascii=False))


def allow_tool(context=None):
    out = {
        'hookSpecificOutput': {
            'hookEventName': 'PreToolUse',
            'permissionDecision': 'allow',
        }
    }
    if context:
        out['hookSpecificOutput']['additionalContext'] = context
    print(json.dumps(out, ensure_ascii=False))


def wait_for_approval(approval_id):
    deadline = time.time() + TIMEOUT
    while time.time() < deadline:
        state = request_json(f'/api/integrations/codex/approvals/{approval_id}/status')
        status = state.get('status')
        if status in {'approved','rejected'}:
            return status
        time.sleep(2)
    return 'timeout'


def main():
    try:
        event = json.load(sys.stdin)
    except Exception:
        event = {}

    hook_name = event.get('hook_event_name')
    if not TOKEN:
        reason = 'AI Agent Security Guard token is not configured.'
        if FAIL_CLOSED:
            block_prompt(reason) if hook_name == 'UserPromptSubmit' else block_tool(reason)
        return

    try:
        if hook_name == 'UserPromptSubmit':
            result = request_json('/api/integrations/codex/prompt', 'POST', {
                'session_id': event.get('session_id'),
                'turn_id': event.get('turn_id'),
                'prompt': event.get('prompt', ''),
                'model': event.get('model'),
                'cwd': event.get('cwd'),
            })
            decision = result.get('decision')
            if decision == 'block':
                block_prompt(result.get('reason', 'Prompt blocked by security policy.'))
            elif decision == 'approval':
                status = wait_for_approval(result.get('approval_id'))
                if status != 'approved':
                    block_prompt('Prompt was not approved in the security dashboard.')
            else:
                return

        elif hook_name == 'PreToolUse':
            result = request_json('/api/integrations/codex/pre-tool', 'POST', {
                'session_id': event.get('session_id'),
                'turn_id': event.get('turn_id'),
                'tool_name': event.get('tool_name', ''),
                'tool_input': event.get('tool_input'),
                'model': event.get('model'),
                'cwd': event.get('cwd'),
            })
            decision = result.get('decision')
            reason = result.get('reason', 'Blocked by security policy.')
            if decision == 'block':
                block_tool(reason)
            elif decision == 'approval':
                status = wait_for_approval(result.get('approval_id'))
                if status == 'approved':
                    allow_tool('Approved by AI Agent Security Guard dashboard.')
                else:
                    block_tool('Action rejected or approval timed out in AI Agent Security Guard.')
            else:
                allow_tool()
        else:
            return
    except (urllib.error.URLError, urllib.error.HTTPError, TimeoutError, OSError) as exc:
        if FAIL_CLOSED:
            reason = 'Security service unavailable; action blocked by fail-closed policy.'
            block_prompt(reason) if hook_name == 'UserPromptSubmit' else block_tool(reason)
        else:
            return


if __name__ == '__main__':
    main()
