import csv
import io
import json
import os
from datetime import datetime, timezone
from typing import Any
from fastapi import Depends, FastAPI, HTTPException, Response
from fastapi.middleware.cors import CORSMiddleware
from sqlalchemy.orm import Session
from .auth import create_access_token, generate_integration_token, hash_integration_token, hash_password, verify_password
from .database import Base, engine
from .deps import get_current_user, get_db, get_integration_user
from .llm_analyzer import analyze_with_ollama
from .models import ApprovalRequest, AuditLog, SecurityPolicy, SecurityScan, User
from .schemas import CodexPromptIn, CodexToolIn, LoginIn, PolicyIn, ScanIn, SignupIn
from .security_engine import ALL_CATEGORIES, decision_for, findings_json, merge_findings, risk_score, static_analyze, threat_level

Base.metadata.create_all(bind=engine)

app = FastAPI(title='AI Agent Security Guard', version='1.0.0')
app.add_middleware(
    CORSMiddleware,
    allow_origins=[x.strip() for x in os.getenv('CORS_ORIGINS', 'http://127.0.0.1:5173,http://localhost:5173').split(',') if x.strip()],
    allow_credentials=True,
    allow_methods=['*'],
    allow_headers=['*'],
)


def default_policy(db: Session, user: User) -> SecurityPolicy:
    policy = db.query(SecurityPolicy).filter(SecurityPolicy.user_id == user.id).first()
    if not policy:
        policy = SecurityPolicy(user_id=user.id, enabled_categories_json=json.dumps(ALL_CATEGORIES))
        db.add(policy)
        db.commit()
        db.refresh(policy)
    return policy


def audit(db: Session, user_id: int, event_type: str, details: dict[str, Any]):
    db.add(AuditLog(user_id=user_id, event_type=event_type, details_json=json.dumps(details, ensure_ascii=False, default=str)))
    db.commit()


async def run_scan(db: Session, user: User, payload: ScanIn) -> tuple[SecurityScan, ApprovalRequest | None]:
    policy = default_policy(db, user)
    categories = json.loads(policy.enabled_categories_json or '[]')
    static = static_analyze(payload.source_text, categories)
    llm = await analyze_with_ollama(payload.source_text, enabled=policy.llm_enabled)
    findings, llm_used = merge_findings(static, llm)
    score = risk_score(findings, llm)
    decision = decision_for(score, policy.approval_threshold, policy.block_threshold)

    if policy.require_approval_for_sensitive_files and any(f.get('category') == 'sensitive_file_access' for f in findings):
        if decision == 'allow':
            decision = 'approval'

    scan = SecurityScan(
        user_id=user.id,
        source_type=payload.source_type,
        source_text=payload.source_text,
        tool_name=payload.tool_name,
        session_id=payload.session_id,
        decision=decision,
        risk_score=score,
        threat_level=threat_level(score),
        findings_json=findings_json(findings),
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

    audit(db, user.id, 'scan.completed', {'scan_id': scan.id, 'decision': decision, 'risk_score': score, 'source_type': payload.source_type})
    return scan, approval


def scan_dict(scan: SecurityScan, approval: ApprovalRequest | None = None):
    return {
        'id': scan.id,
        'source_type': scan.source_type,
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
    return {'status': 'ok', 'service': 'ai-agent-security-guard'}


@app.post('/api/auth/signup')
def signup(payload: SignupIn, db: Session = Depends(get_db)):
    email = payload.email.lower().strip()
    if db.query(User).filter(User.email == email).first():
        raise HTTPException(409, 'Email already registered')
    user = User(name=payload.name.strip(), email=email, password_hash=hash_password(payload.password), language=payload.language if payload.language in {'en','ar'} else 'en')
    db.add(user)
    db.commit()
    db.refresh(user)
    default_policy(db, user)
    audit(db, user.id, 'auth.signup', {'email': user.email})
    return {'access_token': create_access_token(user.id), 'token_type': 'bearer', 'user': {'id': user.id, 'name': user.name, 'email': user.email, 'language': user.language}}


@app.post('/api/auth/login')
def login(payload: LoginIn, db: Session = Depends(get_db)):
    user = db.query(User).filter(User.email == payload.email.lower().strip()).first()
    if not user or not verify_password(payload.password, user.password_hash):
        raise HTTPException(401, 'Invalid email or password')
    audit(db, user.id, 'auth.login', {'email': user.email})
    return {'access_token': create_access_token(user.id), 'token_type': 'bearer', 'user': {'id': user.id, 'name': user.name, 'email': user.email, 'language': user.language}}


@app.get('/api/auth/me')
def me(user: User = Depends(get_current_user)):
    return {'id': user.id, 'name': user.name, 'email': user.email, 'language': user.language}


@app.post('/api/scans')
async def create_scan(payload: ScanIn, db: Session = Depends(get_db), user: User = Depends(get_current_user)):
    scan, approval = await run_scan(db, user, payload)
    return scan_dict(scan, approval)


@app.get('/api/scans')
def list_scans(limit: int = 100, db: Session = Depends(get_db), user: User = Depends(get_current_user)):
    rows = db.query(SecurityScan).filter(SecurityScan.user_id == user.id).order_by(SecurityScan.id.desc()).limit(min(limit, 500)).all()
    return [scan_dict(x) for x in rows]


@app.get('/api/scans/{scan_id}')
def get_scan(scan_id: int, db: Session = Depends(get_db), user: User = Depends(get_current_user)):
    scan = db.query(SecurityScan).filter(SecurityScan.id == scan_id, SecurityScan.user_id == user.id).first()
    if not scan:
        raise HTTPException(404, 'Scan not found')
    approval = db.query(ApprovalRequest).filter(ApprovalRequest.scan_id == scan.id, ApprovalRequest.user_id == user.id).first()
    return scan_dict(scan, approval)


@app.get('/api/dashboard')
def dashboard(db: Session = Depends(get_db), user: User = Depends(get_current_user)):
    scans = db.query(SecurityScan).filter(SecurityScan.user_id == user.id).all()
    pending = db.query(ApprovalRequest).filter(ApprovalRequest.user_id == user.id, ApprovalRequest.status == 'pending').count()
    return {
        'total_scans': len(scans),
        'blocked': sum(1 for x in scans if x.decision == 'block'),
        'allowed': sum(1 for x in scans if x.decision == 'allow'),
        'approval_required': sum(1 for x in scans if x.decision == 'approval'),
        'pending_approvals': pending,
        'critical': sum(1 for x in scans if x.threat_level == 'critical'),
        'recent': [scan_dict(x) for x in sorted(scans, key=lambda s: s.id, reverse=True)[:8]],
    }


@app.get('/api/policies')
def get_policy(db: Session = Depends(get_db), user: User = Depends(get_current_user)):
    p = default_policy(db, user)
    return {
        'approval_threshold': p.approval_threshold,
        'block_threshold': p.block_threshold,
        'llm_enabled': p.llm_enabled,
        'require_approval_for_sensitive_files': p.require_approval_for_sensitive_files,
        'enabled_categories': json.loads(p.enabled_categories_json or '[]'),
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
    db.commit()
    audit(db, user.id, 'policy.updated', {'approval_threshold': p.approval_threshold, 'block_threshold': p.block_threshold, 'llm_enabled': p.llm_enabled})
    return {'ok': True}


@app.get('/api/approvals')
def approvals(db: Session = Depends(get_db), user: User = Depends(get_current_user)):
    rows = db.query(ApprovalRequest).filter(ApprovalRequest.user_id == user.id).order_by(ApprovalRequest.id.desc()).all()
    out = []
    for a in rows:
        s = db.query(SecurityScan).filter(SecurityScan.id == a.scan_id, SecurityScan.user_id == user.id).first()
        out.append({'id': a.id, 'status': a.status, 'scan': scan_dict(s) if s else None, 'created_at': a.created_at, 'decided_at': a.decided_at})
    return out


def decide_approval(approval_id: int, new_status: str, db: Session, user: User):
    a = db.query(ApprovalRequest).filter(ApprovalRequest.id == approval_id, ApprovalRequest.user_id == user.id).first()
    if not a:
        raise HTTPException(404, 'Approval not found')
    if a.status != 'pending':
        raise HTTPException(409, f'Approval already {a.status}')
    a.status = new_status
    a.decided_at = datetime.now(timezone.utc)
    db.commit()
    audit(db, user.id, f'approval.{new_status}', {'approval_id': a.id, 'scan_id': a.scan_id})
    return {'id': a.id, 'status': a.status}


@app.post('/api/approvals/{approval_id}/approve')
def approve(approval_id: int, db: Session = Depends(get_db), user: User = Depends(get_current_user)):
    return decide_approval(approval_id, 'approved', db, user)


@app.post('/api/approvals/{approval_id}/reject')
def reject(approval_id: int, db: Session = Depends(get_db), user: User = Depends(get_current_user)):
    return decide_approval(approval_id, 'rejected', db, user)


@app.get('/api/audit')
def audit_logs(limit: int = 200, db: Session = Depends(get_db), user: User = Depends(get_current_user)):
    rows = db.query(AuditLog).filter(AuditLog.user_id == user.id).order_by(AuditLog.id.desc()).limit(min(limit, 1000)).all()
    return [{'id': x.id, 'event_type': x.event_type, 'details': json.loads(x.details_json), 'created_at': x.created_at} for x in rows]


@app.get('/api/reports/security.csv')
def security_report_csv(db: Session = Depends(get_db), user: User = Depends(get_current_user)):
    rows = db.query(SecurityScan).filter(SecurityScan.user_id == user.id).order_by(SecurityScan.id.desc()).all()
    buffer = io.StringIO()
    writer = csv.writer(buffer)
    writer.writerow(['scan_id','created_at','source_type','tool_name','decision','risk_score','threat_level','llm_used','finding_ids'])
    for x in rows:
        findings = json.loads(x.findings_json or '[]')
        writer.writerow([x.id, x.created_at.isoformat() if x.created_at else '', x.source_type, x.tool_name or '', x.decision, x.risk_score, x.threat_level, x.llm_used, '|'.join(str(f.get('id','')) for f in findings)])
    audit(db, user.id, 'report.exported', {'format': 'csv', 'rows': len(rows)})
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
    return {'codex_token_configured': bool(user.integration_token_hash), 'ollama_enabled': os.getenv('OLLAMA_ENABLED', 'false').lower() in {'1','true','yes','on'}}


@app.post('/api/integrations/codex/prompt')
async def codex_prompt(payload: CodexPromptIn, db: Session = Depends(get_db), user: User = Depends(get_integration_user)):
    scan, approval = await run_scan(db, user, ScanIn(source_type='codex_prompt', source_text=payload.prompt, session_id=payload.session_id))
    return {'decision': scan.decision, 'reason': _reason(scan), 'risk_score': scan.risk_score, 'approval_id': approval.id if approval else None, 'scan_id': scan.id}


@app.post('/api/integrations/codex/pre-tool')
async def codex_pre_tool(payload: CodexToolIn, db: Session = Depends(get_db), user: User = Depends(get_integration_user)):
    rendered = json.dumps({'tool_name': payload.tool_name, 'tool_input': payload.tool_input}, ensure_ascii=False, default=str)
    scan, approval = await run_scan(db, user, ScanIn(source_type='codex_tool', source_text=rendered, tool_name=payload.tool_name, session_id=payload.session_id))
    return {'decision': scan.decision, 'reason': _reason(scan), 'risk_score': scan.risk_score, 'approval_id': approval.id if approval else None, 'scan_id': scan.id}


@app.get('/api/integrations/codex/approvals/{approval_id}/status')
def codex_approval_status(approval_id: int, db: Session = Depends(get_db), user: User = Depends(get_integration_user)):
    a = db.query(ApprovalRequest).filter(ApprovalRequest.id == approval_id, ApprovalRequest.user_id == user.id).first()
    if not a:
        raise HTTPException(404, 'Approval not found')
    return {'id': a.id, 'status': a.status}


def _reason(scan: SecurityScan) -> str:
    findings = json.loads(scan.findings_json or '[]')
    if not findings:
        return 'No configured security rule matched.'
    top = sorted(findings, key=lambda f: int(f.get('weight', 0)), reverse=True)[:3]
    return '; '.join(f"{f.get('id')}: {f.get('title')}" for f in top)
