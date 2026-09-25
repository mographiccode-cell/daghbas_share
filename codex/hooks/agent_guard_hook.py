#!/usr/bin/env python3
"""Codex lifecycle hook bridge for AI Agent Security Guard.

Supported events:
- UserPromptSubmit: inspect the outgoing prompt.
- PreToolUse: inspect tool name/input before execution.
- PostToolUse: inspect tool output before Codex consumes it.

Secrets are read only from environment variables and are never printed.
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
FAIL_CLOSED = os.getenv('AGENT_GUARD_FAIL_CLOSED', 'true').lower() in {'1', 'true', 'yes', 'on'}


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


def emit(obj):
    print(json.dumps(obj, ensure_ascii=False))


def block_prompt(reason):
    emit({'decision': 'block', 'reason': reason})


def block_pre_tool(reason):
    emit({
        'hookSpecificOutput': {
            'hookEventName': 'PreToolUse',
            'permissionDecision': 'deny',
            'permissionDecisionReason': reason,
        }
    })


def allow_pre_tool(context=None):
    out = {
        'hookSpecificOutput': {
            'hookEventName': 'PreToolUse',
            'permissionDecision': 'allow',
        }
    }
    if context:
        out['hookSpecificOutput']['additionalContext'] = context
    emit(out)


def block_post_tool(reason):
    # PostToolUse cannot undo the tool's side effects, but a blocking result
    # prevents the unsafe output from reaching the continuing Codex workflow.
    emit({
        'decision': 'block',
        'reason': reason,
        'hookSpecificOutput': {
            'hookEventName': 'PostToolUse',
        },
    })


def wait_for_approval(approval_id):
    deadline = time.time() + TIMEOUT
    while time.time() < deadline:
        state = request_json(f'/api/integrations/codex/approvals/{approval_id}/status')
        status = state.get('status')
        if status in {'approved', 'rejected'}:
            return status
        time.sleep(1)
    return 'timeout'


def _unavailable(hook_name):
    reason = 'Security service unavailable; blocked by fail-closed policy.'
    if hook_name == 'UserPromptSubmit':
        block_prompt(reason)
    elif hook_name == 'PostToolUse':
        block_post_tool(reason)
    else:
        block_pre_tool(reason)


def main():
    try:
        event = json.load(sys.stdin)
    except Exception:
        event = {}

    hook_name = event.get('hook_event_name')
    if not TOKEN:
        if FAIL_CLOSED:
            reason = 'AI Agent Security Guard token is not configured.'
            if hook_name == 'UserPromptSubmit':
                block_prompt(reason)
            elif hook_name == 'PostToolUse':
                block_post_tool(reason)
            else:
                block_pre_tool(reason)
        return

    try:
        common = {
            'session_id': event.get('session_id'),
            'turn_id': event.get('turn_id'),
            'model': event.get('model'),
            'cwd': event.get('cwd'),
        }

        if hook_name == 'UserPromptSubmit':
            result = request_json('/api/integrations/codex/prompt', 'POST', {
                **common,
                'prompt': event.get('prompt', ''),
            })
            if result.get('decision') == 'block':
                block_prompt(result.get('reason', 'Prompt blocked by security policy.'))
            elif result.get('decision') == 'approval':
                status = wait_for_approval(result.get('approval_id'))
                if status != 'approved':
                    block_prompt('Prompt was not approved in the security dashboard.')
            return

        if hook_name == 'PreToolUse':
            result = request_json('/api/integrations/codex/pre-tool', 'POST', {
                **common,
                'tool_name': event.get('tool_name', ''),
                'tool_input': event.get('tool_input'),
            })
            decision = result.get('decision')
            reason = result.get('reason', 'Blocked by security policy.')
            if decision == 'block':
                block_pre_tool(reason)
            elif decision == 'approval':
                status = wait_for_approval(result.get('approval_id'))
                if status == 'approved':
                    allow_pre_tool('Approved by AI Agent Security Guard dashboard.')
                else:
                    block_pre_tool('Action rejected or approval timed out in AI Agent Security Guard.')
            else:
                allow_pre_tool()
            return

        if hook_name == 'PostToolUse':
            result = request_json('/api/integrations/codex/post-tool', 'POST', {
                **common,
                'tool_name': event.get('tool_name', ''),
                'tool_input': event.get('tool_input'),
                'tool_response': event.get('tool_response'),
            })
            decision = result.get('decision')
            reason = result.get('reason', 'Tool output blocked by security policy.')
            if decision == 'block':
                block_post_tool(reason)
            elif decision == 'approval':
                status = wait_for_approval(result.get('approval_id'))
                if status != 'approved':
                    block_post_tool('Tool output rejected or approval timed out in AI Agent Security Guard.')
            return
    except (urllib.error.URLError, urllib.error.HTTPError, TimeoutError, OSError):
        if FAIL_CLOSED:
            _unavailable(hook_name)


if __name__ == '__main__':
    main()
