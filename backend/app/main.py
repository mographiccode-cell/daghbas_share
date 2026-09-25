import csv
import io
import json
import os
from datetime import datetime, timezone
from typing import Any

from fastapi import Depends, FastAPI, HTTPException, Response, WebSocket, WebSocketDisconnect
from fastapi.encoders import jsonable_encoder
from fastapi.middleware.cors import CORSMiddleware
from sqlalchemy.orm import Session

from .auth import (
    create_access_token,
    decode_access_token,
    generate_integration_token,
    hash_integration_token,
    hash_password,
    verify_password,
)
from .database import Base, SessionLocal, engine, ensure_sqlite_schema
from .deps import get_current_user, get_db, get_integration_user
from .llm_analyzer import analyze_with_ollama
from .models import ApprovalRequest, AuditLog, Project, SecurityPolicy, SecurityScan, User
from .schemas import (
    CodexPromptIn,
    CodexToolIn,
    CodexToolResultIn,
    LoginIn,
    PolicyIn,
    ProjectIn,
    ScanIn,
    SignupIn,
)
from .security_engine import (
    ALL_CATEGORIES,
    decision_for,
    findings_json,
    merge_findings,
    policy_findings,
    redact_sensitive,
    risk_score,
    static_analyze,
    threat_level,
)

Base.metadata.create_all(bind=engine)
ensure_sqlite_schema()

app = FastAPI(title='AI Agent Security Guard', version='1.1.0')
app.add_middleware(
    CORSMiddleware,
    allow_origins=[x.strip() for x in os.getenv('CORS_ORIGINS', 'http://127.0.0.1:5173,http://localhost:5173').split(',') if x.strip()],
    allow_credentials=True,
    allow_methods=['*'],
    allow_headers=['*'],
)


class ConnectionManager:
    def __init__(self):
        self.connections: dict[int, set[WebSocket]] = {}

    async def connect(self, user_id: int, websocket: WebSocket):
        await websocket.accept()
        self.connections.setdefault(user_id, set()).add(websocket)

    def disconnect(self, user_id: int, websocket: WebSocket):
        sockets = self.connections.get(user_id)
        if sockets:
            sockets.discard(websocket)
            if not sockets:
                self.connections.pop(user_id, None)

    async def send(self, user_id: int, event: dict[str, Any]):
        dead = []
        payload = jsonable_encoder(event)
        for ws in list(self.connections.get(user_id, set())):
            try:
                await ws.send_json(payload)
            except Exception:
                dead.append(ws)
        for ws in dead:
            self.disconnect(user_id, ws)


ws_manager = ConnectionManager()


def _json_list(raw: str | None) -> list[str]:
    try:
        data = json.loads(raw or '[]')
        return [str(x) for x in data] if isinstance(data, list) else []
    except Exception:
        return []


def _safe_details(details: dict[str, Any]) -> dict[str, Any]:
    raw = json.dumps(details, ensure_ascii=False, default=str)
    redacted = redact_sensitive(raw)
    try:
        return json.loads(redacted)
    except Exception:
        return {'details': redacted[:4000]}


def _safe_findings(findings: list[dict]) -> list[dict]:
    safe = []
    for finding in findings:
        item = dict(finding)
        for key in ('match', 'evidence'):
            if key in item and item[key] is not None:
                item[key] = redact_sensitive(str(item[key]))
        safe.append(item)
    return safe


def default_policy(db: Session, user: User) -> SecurityPolicy:
    policy = db.query(SecurityPolicy).filter(SecurityPolicy.user_id == user.id).first()
    if not policy:
        policy = SecurityPolicy(
            user_id=user.id,
            enabled_categories_json=json.dumps(ALL_CATEGORIES),
            blocked_domains_json='[]',
            blocked_tools_json='[]',
            approval_tools_json='[]',
        )
        db.add(policy)
        db.commit()
        db.refresh(policy)
    return policy


def audit(db: Session, user_id: int, event_type: str, details: dict[str, Any]):
    safe = _safe_details(details)
    db.add(AuditLog(user_id=user_id, event_type=event_type, details_json=json.dumps(safe, ensure_ascii=False, default=str)))
    db.commit()


def ensure_project_owned(db: Session, user_id: int, project_id: int | None) -> Project | None:
    if project_id is None:
        return None
    project = db.query(Project).filter(Project.id == project_id, Project.user_id == user_id).first()
    if not project:
        raise HTTPException(404, 'Project not found')
    return project


def project_dict(project: Project):
    return {
        'id': project.id,
        'name': project.name,
        'description': project.description,
        'created_at': project.created_at,
    }


async def run_scan(db: Session, user: User, payload: ScanIn) -> tuple[SecurityScan, ApprovalRequest | None]:
    ensure_project_owned(db, user.id, payload.project_id)
    policy = default_policy(db, user)
    categories = _json_list(policy.enabled_categories_json)
    blocked_domains = _json_list(policy.blocked_domains_json)
    blocked_tools = _json_list(policy.blocked_tools_json)
    approval_tools = [x.lower() for x in _json_list(policy.approval_tools_json)]

    static = static_analyze(payload.source_text, categories)
    static.extend(policy_findings(payload.source_text, payload.tool_name, blocked_domains, blocked_tools))
    llm = await analyze_with_ollama(payload.source_text, enabled=policy.llm_enabled)
    findings, llm_used = merge_findings(static, llm)
    score = risk_score(findings, llm)
    decision = decision_for(score, policy.approval_threshold, policy.block_threshold)

    normalized_tool = (payload.tool_name or '').strip().lower()
    if decision != 'block' and normalized_tool and any(
        normalized_tool == allowed or normalized_tool.startswith(allowed) for allowed in approval_tools if allowed
    ):
        decision = 'approval'

    if policy.require_approval_for_sensitive_files and any(f.get('category') == 'sensitive_file_access' for f in findings):
        if decision == 'allow':
            decision = 'approval'

    safe_findings = _safe_findings(findings)
    scan = SecurityScan(
        user_id=user.id,
        project_id=payload.project_id,
        source_type=payload.source_type,
        source_text=redact_sensitive(payload.source_text),
        tool_name=payload.tool_name,
        session_id=payload.session_id,
        decision=decision,
        risk_score=score,
        threat_level=threat_level(score),
        findings_json=findings_json(safe_findings),
        llm_used=llm_used,
    )
    db.add(scan)
    db.commit()
    db.refresh(scan)

    approval = None
    if decision == 'approval':
        approval = ApprovalRequest(user_id=user.id, scan_id=scan.id, status='pending')
        db.add(approval)
        db.commit()
        db.refresh(approval)

    audit(db, user.id, 'scan.completed', {
        'scan_id': scan.id,
        'project_id': scan.project_id,
        'decision': decision,
        'risk_score': score,
        'source_type': payload.source_type,
        'tool_name': payload.tool_name,
    })
    await ws_manager.send(user.id, {
        'type': 'scan.completed',
        'scan': scan_dict(scan, approval),
    })
    if approval:
        await ws_manager.send(user.id, {
            'type': 'approval.created',
            'approval_id': approval.id,
            'scan_id': scan.id,
        })
    return scan, approval


def scan_dict(scan: SecurityScan, approval: ApprovalRequest | None = None):
    return {
        'id': scan.id,
        'project_id': scan.project_id,
        'source_type': scan.source_type,
        'source_preview': (scan.source_text or '')[:400],
        'tool_name': scan.tool_name,
        'session_id': scan.session_id,
        'decision': scan.decision,
        'risk_score': scan.risk_score,
        'threat_level': scan.threat_level,
        'findings': json.loads(scan.findings_json or '[]'),
        'llm_used': scan.llm_used,
        'approval_id': approval.id if approval else None,
        'created_at': scan.created_at,
    }


@app.get('/api/health')
def health():
    return {'status': 'ok', 'service': 'ai-agent-security-guard', 'version': '1.1.0'}


@app.post('/api/auth/signup')
def signup(payload: SignupIn, db: Session = Depends(get_db)):
    email = payload.email.lower().strip()
    if db.query(User).filter(User.email == email).first():
        raise HTTPException(409, 'Email already registered')
    user = User(
        name=payload.name.strip(),
        email=email,
        password_hash=hash_password(payload.password),
        language=payload.language if payload.language in {'en', 'ar'} else 'en',
    )
    db.add(user)
    db.commit()
    db.refresh(user)
    default_policy(db, user)
    audit(db, user.id, 'auth.signup', {'email': user.email})
    return {
        'access_token': create_access_token(user.id),
        'token_type': 'bearer',
        'user': {'id': user.id, 'name': user.name, 'email': user.email, 'language': user.language},
    }


@app.post('/api/auth/login')
def login(payload: LoginIn, db: Session = Depends(get_db)):
    user = db.query(User).filter(User.email == payload.email.lower().strip()).first()
    if not user or not verify_password(payload.password, user.password_hash):
        raise HTTPException(401, 'Invalid email or password')
    audit(db, user.id, 'auth.login', {'email': user.email})
    return {
        'access_token': create_access_token(user.id),
        'token_type': 'bearer',
        'user': {'id': user.id, 'name': user.name, 'email': user.email, 'language': user.language},
    }


@app.get('/api/auth/me')
def me(user: User = Depends(get_current_user)):
    return {'id': user.id, 'name': user.name, 'email': user.email, 'language': user.language}


@app.post('/api/projects')
def create_project(payload: ProjectIn, db: Session = Depends(get_db), user: User = Depends(get_current_user)):
    project = Project(user_id=user.id, name=payload.name.strip(), description=payload.description.strip())
    db.add(project)
    db.commit()
    db.refresh(project)
    audit(db, user.id, 'project.created', {'project_id': project.id, 'name': project.name})
    return project_dict(project)


@app.get('/api/projects')
def list_projects(db: Session = Depends(get_db), user: User = Depends(get_current_user)):
    rows = db.query(Project).filter(Project.user_id == user.id).order_by(Project.id.desc()).all()
    return [project_dict(x) for x in rows]


@app.get('/api/projects/{project_id}')
def get_project(project_id: int, db: Session = Depends(get_db), user: User = Depends(get_current_user)):
    return project_dict(ensure_project_owned(db, user.id, project_id))


@app.delete('/api/projects/{project_id}')
def delete_project(project_id: int, db: Session = Depends(get_db), user: User = Depends(get_current_user)):
    project = ensure_project_owned(db, user.id, project_id)
    db.query(SecurityScan).filter(SecurityScan.user_id == user.id, SecurityScan.project_id == project.id).update({'project_id': None})
    db.delete(project)
    db.commit()
    audit(db, user.id, 'project.deleted', {'project_id': project_id})
    return {'ok': True}


@app.post('/api/scans')
async def create_scan(payload: ScanIn, db: Session = Depends(get_db), user: User = Depends(get_current_user)):
    scan, approval = await run_scan(db, user, payload)
    return scan_dict(scan, approval)


@app.get('/api/scans')
def list_scans(
    limit: int = 100,
    decision: str | None = None,
    source_type: str | None = None,
    project_id: int | None = None,
    db: Session = Depends(get_db),
    user: User = Depends(get_current_user),
):
    query = db.query(SecurityScan).filter(SecurityScan.user_id == user.id)
    if decision:
        query = query.filter(SecurityScan.decision == decision)
    if source_type:
        query = query.filter(SecurityScan.source_type == source_type)
    if project_id is not None:
        ensure_project_owned(db, user.id, project_id)
        query = query.filter(SecurityScan.project_id == project_id)
    rows = query.order_by(SecurityScan.id.desc()).limit(min(max(limit, 1), 500)).all()
    return [scan_dict(x) for x in rows]


@app.get('/api/scans/{scan_id}')
def get_scan(scan_id: int, db: Session = Depends(get_db), user: User = Depends(get_current_user)):
    scan = db.query(SecurityScan).filter(SecurityScan.id == scan_id, SecurityScan.user_id == user.id).first()
    if not scan:
        raise HTTPException(404, 'Scan not found')
    approval = db.query(ApprovalRequest).filter(ApprovalRequest.scan_id == scan.id, ApprovalRequest.user_id == user.id).first()
    return scan_dict(scan, approval)


@app.get('/api/dashboard')
def dashboard(project_id: int | None = None, db: Session = Depends(get_db), user: User = Depends(get_current_user)):
    query = db.query(SecurityScan).filter(SecurityScan.user_id == user.id)
    if project_id is not None:
        ensure_project_owned(db, user.id, project_id)
        query = query.filter(SecurityScan.project_id == project_id)
    scans = query.all()
    pending = db.query(ApprovalRequest).filter(ApprovalRequest.user_id == user.id, ApprovalRequest.status == 'pending').count()
    return {
        'total_scans': len(scans),
        'blocked': sum(1 for x in scans if x.decision == 'block'),
        'allowed': sum(1 for x in scans if x.decision == 'allow'),
        'approval_required': sum(1 for x in scans if x.decision == 'approval'),
        'pending_approvals': pending,
        'critical': sum(1 for x in scans if x.threat_level == 'critical'),
        'recent': [scan_dict(x) for x in sorted(scans, key=lambda s: s.id, reverse=True)[:12]],
    }


@app.get('/api/policies')
def get_policy(db: Session = Depends(get_db), user: User = Depends(get_current_user)):
    p = default_policy(db, user)
    return {
        'approval_threshold': p.approval_threshold,
        'block_threshold': p.block_threshold,
        'llm_enabled': p.llm_enabled,
        'require_approval_for_sensitive_files': p.require_approval_for_sensitive_files,
        'enabled_categories': _json_list(p.enabled_categories_json),
        'blocked_domains': _json_list(p.blocked_domains_json),
        'blocked_tools': _json_list(p.blocked_tools_json),
        'approval_tools': _json_list(p.approval_tools_json),
        'available_categories': ALL_CATEGORIES,
    }


@app.put('/api/policies')
def update_policy(payload: PolicyIn, db: Session = Depends(get_db), user: User = Depends(get_current_user)):
    if payload.approval_threshold >= payload.block_threshold:
        raise HTTPException(422, 'approval_threshold must be lower than block_threshold')
    p = default_policy(db, user)
    p.approval_threshold = payload.approval_threshold
    p.block_threshold = payload.block_threshold
    p.llm_enabled = payload.llm_enabled
    p.require_approval_for_sensitive_files = payload.require_approval_for_sensitive_files
    p.enabled_categories_json = json.dumps(payload.enabled_categories or ALL_CATEGORIES)
    p.blocked_domains_json = json.dumps(sorted(set(x.strip().lower() for x in payload.blocked_domains if x.strip())))
    p.blocked_tools_json = json.dumps(sorted(set(x.strip() for x in payload.blocked_tools if x.strip())))
    p.approval_tools_json = json.dumps(sorted(set(x.strip() for x in payload.approval_tools if x.strip())))
    db.commit()
    audit(db, user.id, 'policy.updated', {
        'approval_threshold': p.approval_threshold,
        'block_threshold': p.block_threshold,
        'llm_enabled': p.llm_enabled,
        'blocked_domains_count': len(_json_list(p.blocked_domains_json)),
        'blocked_tools_count': len(_json_list(p.blocked_tools_json)),
        'approval_tools_count': len(_json_list(p.approval_tools_json)),
    })
    return {'ok': True}


@app.get('/api/approvals')
def approvals(status: str | None = None, db: Session = Depends(get_db), user: User = Depends(get_current_user)):
    query = db.query(ApprovalRequest).filter(ApprovalRequest.user_id == user.id)
    if status:
        query = query.filter(ApprovalRequest.status == status)
    rows = query.order_by(ApprovalRequest.id.desc()).all()
    out = []
    for approval in rows:
        scan = db.query(SecurityScan).filter(SecurityScan.id == approval.scan_id, SecurityScan.user_id == user.id).first()
        out.append({
            'id': approval.id,
            'status': approval.status,
            'scan': scan_dict(scan) if scan else None,
            'created_at': approval.created_at,
            'decided_at': approval.decided_at,
        })
    return out


def decide_approval(approval_id: int, new_status: str, db: Session, user: User):
    approval = db.query(ApprovalRequest).filter(ApprovalRequest.id == approval_id, ApprovalRequest.user_id == user.id).first()
    if not approval:
        raise HTTPException(404, 'Approval not found')
    if approval.status != 'pending':
        raise HTTPException(409, f'Approval already {approval.status}')
    approval.status = new_status
    approval.decided_at = datetime.now(timezone.utc)
    db.commit()
    audit(db, user.id, f'approval.{new_status}', {'approval_id': approval.id, 'scan_id': approval.scan_id})
    return approval


@app.post('/api/approvals/{approval_id}/approve')
async def approve(approval_id: int, db: Session = Depends(get_db), user: User = Depends(get_current_user)):
    approval = decide_approval(approval_id, 'approved', db, user)
    await ws_manager.send(user.id, {'type': 'approval.decided', 'approval_id': approval.id, 'status': approval.status})
    return {'id': approval.id, 'status': approval.status}


@app.post('/api/approvals/{approval_id}/reject')
async def reject(approval_id: int, db: Session = Depends(get_db), user: User = Depends(get_current_user)):
    approval = decide_approval(approval_id, 'rejected', db, user)
    await ws_manager.send(user.id, {'type': 'approval.decided', 'approval_id': approval.id, 'status': approval.status})
    return {'id': approval.id, 'status': approval.status}


@app.get('/api/audit')
def audit_logs(event_type: str | None = None, limit: int = 200, db: Session = Depends(get_db), user: User = Depends(get_current_user)):
    query = db.query(AuditLog).filter(AuditLog.user_id == user.id)
    if event_type:
        query = query.filter(AuditLog.event_type == event_type)
    rows = query.order_by(AuditLog.id.desc()).limit(min(max(limit, 1), 1000)).all()
    return [{'id': x.id, 'event_type': x.event_type, 'details': json.loads(x.details_json), 'created_at': x.created_at} for x in rows]


@app.get('/api/reports/security.csv')
def security_report_csv(project_id: int | None = None, db: Session = Depends(get_db), user: User = Depends(get_current_user)):
    query = db.query(SecurityScan).filter(SecurityScan.user_id == user.id)
    if project_id is not None:
        ensure_project_owned(db, user.id, project_id)
        query = query.filter(SecurityScan.project_id == project_id)
    rows = query.order_by(SecurityScan.id.desc()).all()
    buffer = io.StringIO()
    writer = csv.writer(buffer)
    writer.writerow(['scan_id', 'project_id', 'created_at', 'source_type', 'tool_name', 'decision', 'risk_score', 'threat_level', 'llm_used', 'finding_ids'])
    for scan in rows:
        findings = json.loads(scan.findings_json or '[]')
        writer.writerow([
            scan.id, scan.project_id or '', scan.created_at.isoformat() if scan.created_at else '',
            scan.source_type, scan.tool_name or '', scan.decision, scan.risk_score,
            scan.threat_level, scan.llm_used, '|'.join(str(f.get('id', '')) for f in findings),
        ])
    audit(db, user.id, 'report.exported', {'format': 'csv', 'rows': len(rows), 'project_id': project_id})
    return Response(content=buffer.getvalue(), media_type='text/csv; charset=utf-8', headers={'Content-Disposition': 'attachment; filename=ai-agent-security-report.csv'})


@app.post('/api/integrations/token/regenerate')
def regenerate_token(db: Session = Depends(get_db), user: User = Depends(get_current_user)):
    token = generate_integration_token()
    user.integration_token_hash = hash_integration_token(token)
    db.commit()
    audit(db, user.id, 'integration.token_regenerated', {})
    return {'token': token, 'note': 'Store this token securely. It is shown only in this response.'}


@app.get('/api/integrations/status')
def integration_status(user: User = Depends(get_current_user)):
    return {
        'codex_token_configured': bool(user.integration_token_hash),
        'ollama_enabled': os.getenv('OLLAMA_ENABLED', 'false').lower() in {'1', 'true', 'yes', 'on'},
    }


@app.post('/api/integrations/codex/prompt')
async def codex_prompt(payload: CodexPromptIn, db: Session = Depends(get_db), user: User = Depends(get_integration_user)):
    scan, approval = await run_scan(db, user, ScanIn(source_type='codex_prompt', source_text=payload.prompt, session_id=payload.session_id))
    return _codex_result(scan, approval)


@app.post('/api/integrations/codex/pre-tool')
async def codex_pre_tool(payload: CodexToolIn, db: Session = Depends(get_db), user: User = Depends(get_integration_user)):
    rendered = json.dumps({'tool_name': payload.tool_name, 'tool_input': payload.tool_input}, ensure_ascii=False, default=str)
    scan, approval = await run_scan(db, user, ScanIn(source_type='codex_tool', source_text=rendered, tool_name=payload.tool_name, session_id=payload.session_id))
    return _codex_result(scan, approval)


@app.post('/api/integrations/codex/post-tool')
async def codex_post_tool(payload: CodexToolResultIn, db: Session = Depends(get_db), user: User = Depends(get_integration_user)):
    rendered = json.dumps({'tool_name': payload.tool_name, 'tool_input': payload.tool_input, 'tool_response': payload.tool_response}, ensure_ascii=False, default=str)
    scan, approval = await run_scan(db, user, ScanIn(source_type='codex_tool_response', source_text=rendered, tool_name=payload.tool_name, session_id=payload.session_id))
    return _codex_result(scan, approval)


@app.get('/api/integrations/codex/approvals/{approval_id}/status')
def codex_approval_status(approval_id: int, db: Session = Depends(get_db), user: User = Depends(get_integration_user)):
    approval = db.query(ApprovalRequest).filter(ApprovalRequest.id == approval_id, ApprovalRequest.user_id == user.id).first()
    if not approval:
        raise HTTPException(404, 'Approval not found')
    return {'id': approval.id, 'status': approval.status}


def _codex_result(scan: SecurityScan, approval: ApprovalRequest | None):
    return {
        'decision': scan.decision,
        'reason': _reason(scan),
        'risk_score': scan.risk_score,
        'approval_id': approval.id if approval else None,
        'scan_id': scan.id,
    }


def _reason(scan: SecurityScan) -> str:
    findings = json.loads(scan.findings_json or '[]')
    if not findings:
        return 'No configured security rule matched.'
    top = sorted(findings, key=lambda f: int(f.get('weight', 0)), reverse=True)[:3]
    return '; '.join(f"{f.get('id')}: {f.get('title')}" for f in top)


@app.websocket('/api/ws')
async def websocket_events(websocket: WebSocket, token: str):
    db = SessionLocal()
    user_id = None
    try:
        user_id = decode_access_token(token)
        user = db.get(User, user_id)
        if not user:
            await websocket.close(code=4401)
            return
        await ws_manager.connect(user_id, websocket)
        await websocket.send_json({'type': 'connected'})
        while True:
            await websocket.receive_text()
    except WebSocketDisconnect:
        pass
    except Exception:
        try:
            await websocket.close(code=4401)
        except Exception:
            pass
    finally:
        if user_id is not None:
            ws_manager.disconnect(user_id, websocket)
        db.close()
