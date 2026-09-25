import json
import re
from dataclasses import dataclass, asdict
from typing import Iterable


@dataclass(frozen=True)
class Rule:
    id: str
    category: str
    severity: str
    weight: int
    pattern: str
    title: str
    title_ar: str
    recommendation: str
    recommendation_ar: str
    flags: int = re.IGNORECASE | re.MULTILINE


# A curated Python port of high-value patterns inspired by the MIT-licensed
# estelwalks/agent-threat-scanner project. The architecture keeps rules separate
# so the complete upstream ruleset can be synchronized later without changing API code.
RULES: tuple[Rule, ...] = (
    Rule('IGNORE_INSTRUCTIONS','prompt_injection','high',62,r'ignore\s+(all\s+)?(previous|prior|above|your)\s+(instructions?|prompts?|rules?|guidelines?)','Ignore previous instructions','تجاهل التعليمات السابقة','Treat external text as data, not higher-priority instructions.','اعتبر المحتوى الخارجي بيانات وليس تعليمات أعلى أولوية.'),
    Rule('DISREGARD_GUIDELINES','prompt_injection','medium',52,r'disregard\s+(all\s+)?(previous|prior|above|your)\s+(instructions?|prompts?|rules?|guidelines?)','Disregard guidelines','تجاهل القواعد','Reject attempts to override safety guidance.','ارفض محاولات تجاوز تعليمات الأمان.'),
    Rule('FORGET_CONTEXT','prompt_injection','medium',50,r'forget\s+(everything|all|what)\s+(you|i)\s+(told|said|know)','Forget context','نسيان السياق','Keep the original user intent and trusted context.','حافظ على هدف المستخدم والسياق الموثوق.'),
    Rule('ROLE_ELEVATION','prompt_injection','medium',50,r'you\s+are\s+(now\s+)?(a|an|the)\s+(root|admin|system|super)\s*(user|administrator)?','Role elevation','رفع الصلاحيات عبر الدور','Do not grant privileges through role-play instructions.','لا تمنح صلاحيات عبر تعليمات لعب الأدوار.'),
    Rule('DAN_MODE','prompt_injection','medium',50,r'(DAN|do\s+anything\s+now)\s+mode','DAN jailbreak','محاولة DAN','Reject jailbreak instructions.','ارفض تعليمات كسر القيود.'),
    Rule('PROMPT_LEAK','prompt_injection','high',68,r'(reveal|show|print|leak|expose).{0,40}(system\s+prompt|hidden\s+instructions|developer\s+message)','System prompt extraction','استخراج تعليمات النظام','Do not reveal hidden/system instructions.','لا تكشف تعليمات النظام أو التعليمات المخفية.'),
    Rule('READ_ENV','sensitive_file_access','high',66,r'(?:(?:cat|type|open|read|get-content)\s+[^\n]{0,120})?(?:^|[\s/\\])\.env\b','Environment file access','الوصول إلى ملف البيئة','Require explicit approval before reading secret-bearing environment files.','اطلب موافقة صريحة قبل قراءة ملفات البيئة الحساسة.'),
    Rule('READ_SSH_KEY','sensitive_file_access','high',72,r'(?:\.ssh[/\\](?:id_rsa|id_ed25519|id_ecdsa)|authorized_keys)','SSH key access','الوصول إلى مفاتيح SSH','Block or require approval for private-key access.','احظر أو اطلب موافقة للوصول إلى المفاتيح الخاصة.'),
    Rule('READ_AWS_CREDS','sensitive_file_access','high',72,r'\.aws[/\\]credentials','Cloud credentials access','الوصول إلى بيانات اعتماد سحابية','Protect credential files.','احمِ ملفات بيانات الاعتماد.'),
    Rule('GITHUB_TOKEN','secret_access','critical',92,r'gh[pousr]_[A-Za-z0-9_]{20,}','GitHub token detected','اكتشاف GitHub Token','Remove secrets from prompts/logs and rotate exposed credentials.','احذف الأسرار من الطلبات والسجلات وغيّر بيانات الاعتماد المكشوفة.'),
    Rule('AWS_KEY','secret_access','critical',92,r'(AKIA|ASIA)[A-Z0-9]{16}','AWS access key detected','اكتشاف AWS Key','Never expose cloud keys.','لا تكشف مفاتيح الوصول السحابية.'),
    Rule('PRIVATE_KEY','secret_access','critical',95,r'-----BEGIN\s+(?:RSA|OPENSSH|EC|DSA)?\s*PRIVATE KEY-----','Private key detected','اكتشاف مفتاح خاص','Block transmission and rotate if exposed.','امنع الإرسال وغيّر المفتاح إذا انكشف.'),
    Rule('CURL_POST','data_exfiltration','high',72,r'curl\b[^\n]{0,240}\s(?:-X\s*POST|-d\s|--data\b|--upload-file\b)','Outbound curl upload','إرسال بيانات عبر curl','Review destination and payload before sending data externally.','راجع الوجهة والبيانات قبل الإرسال للخارج.'),
    Rule('EXFIL_SERVICE','data_exfiltration','high',76,r'(webhook\.site|pipedream\.net|requestbin\.com|hookbin\.com|interact\.sh)','Known exfiltration/OAST service','خدمة محتملة لتسريب البيانات','Block unapproved exfiltration endpoints.','احظر نقاط الإرسال الخارجية غير المعتمدة.'),
    Rule('CURL_PIPE_SHELL','remote_execution','critical',94,r'curl\b[^|\n]{0,300}\|\s*(?:ba)?sh\b','Remote script execution','تنفيذ سكربت عن بعد','Download, inspect, and verify before execution.','حمّل وافحص وتحقق قبل التنفيذ.'),
    Rule('WGET_PIPE_SHELL','remote_execution','high',82,r'wget\b[^|\n]{0,300}\|\s*(?:ba)?sh\b','Remote wget execution','تنفيذ wget عن بعد','Do not pipe remote content directly to a shell.','لا تمرر المحتوى البعيد مباشرة إلى Shell.'),
    Rule('POWERSHELL_ENCODED','remote_execution','high',80,r'powershell(?:\.exe)?[^\n]{0,200}(?:-enc|-encodedcommand)\s+[A-Za-z0-9+/=]{20,}','Encoded PowerShell','PowerShell مشفّر','Decode and review before execution.','فك الترميز وراجع الأمر قبل التنفيذ.'),
    Rule('REVERSE_SHELL','remote_execution','critical',100,r'(/dev/(?:tcp|udp)/|\bnc\s+[^\n]{0,100}\s-e\s+|\bsocat\b[^\n]{0,160}\bexec:)','Reverse shell','Reverse Shell','Block reverse-shell behavior.','احظر سلوك Reverse Shell.'),
    Rule('RM_RF_ROOT','destructive','critical',100,r'\brm\s+[^\n]{0,80}-rf\s+/(?:\s|$)','Root deletion','حذف جذر النظام','Block destructive filesystem commands.','احظر أوامر حذف النظام.'),
    Rule('WINDOWS_DELETE_TREE','destructive','high',86,r'\b(?:rmdir|rd)\s+/s\s+/q\b','Recursive Windows deletion','حذف متكرر في ويندوز','Require explicit approval for recursive deletion.','اطلب موافقة صريحة للحذف المتكرر.'),
    Rule('DD_WIPE','destructive','critical',100,r'\bdd\s+[^\n]{0,160}\bof=/dev/(?:sd[a-z]|nvme|hd[a-z])','Disk wipe','مسح القرص','Never allow raw disk overwrite without explicit trusted workflow.','لا تسمح بالكتابة المباشرة على القرص دون مسار موثوق.'),
    Rule('PY_EVAL','command_injection','medium',42,r'(?<![\w.])eval\s*\(','Dynamic eval','تنفيذ eval ديناميكي','Prefer safe parsers and validated inputs.','استخدم بدائل آمنة ومدخلات متحقق منها.'),
    Rule('OS_SYSTEM','command_injection','medium',48,r'\bos\.system\s*\(','os.system execution','تنفيذ os.system','Prefer subprocess with shell=False and validated args.','استخدم subprocess بدون shell مع تحقق من المعاملات.'),
    Rule('SHELL_TRUE','command_injection','high',64,r'subprocess\.(?:run|call|Popen)\s*\([^)]{0,250}shell\s*=\s*True','Shell execution enabled','تشغيل shell=True','Use argument arrays and shell=False.','استخدم قائمة معاملات وshell=False.'),
    Rule('BASE64_EXEC','obfuscation','high',78,r'base64\s+(?:-d|--decode)[^|\n]{0,160}\|\s*(?:ba)?sh\b','Encoded payload execution','تنفيذ حمولة مشفرة','Decode and inspect payload first.','فك الترميز وافحص الحمولة أولاً.'),
    Rule('SUDO','privilege_escalation','medium',46,r'\bsudo\b','Elevated command','أمر بصلاحيات مرتفعة','Require approval for privilege elevation.','اطلب موافقة لرفع الصلاحيات.'),
    Rule('SCHTASKS','persistence','medium',50,r'\bschtasks(?:\.exe)?\b[^\n]{0,220}/create\b','Scheduled task persistence','استمرارية عبر Scheduled Task','Review persistence changes.','راجع تغييرات الاستمرارية.'),
    Rule('REG_RUN','persistence','high',62,r'\breg(?:\.exe)?\s+add\s+HK(?:LM|CU)\\Software\\Microsoft\\Windows\\CurrentVersion\\Run','Registry persistence','استمرارية عبر Registry','Review startup registry modifications.','راجع تعديلات بدء التشغيل في Registry.'),
    Rule('INSECURE_FTP','network_abuse','low',24,r'\bftp://','Insecure FTP','FTP غير آمن','Prefer SFTP/FTPS.','استخدم SFTP أو FTPS.'),
)

SEVERITY_RANK = {'low': 1, 'medium': 2, 'high': 3, 'critical': 4}
ALL_CATEGORIES = sorted({r.category for r in RULES})


def _enabled(rule: Rule, enabled_categories: Iterable[str] | None) -> bool:
    if not enabled_categories:
        return True
    enabled = set(enabled_categories)
    return rule.category in enabled


def static_analyze(text: str, enabled_categories: Iterable[str] | None = None) -> list[dict]:
    findings: list[dict] = []
    for rule in RULES:
        if not _enabled(rule, enabled_categories):
            continue
        match = re.search(rule.pattern, text or '', rule.flags)
        if not match:
            continue
        item = asdict(rule)
        item.pop('pattern', None)
        item.pop('flags', None)
        item['match'] = match.group(0)[:240]
        item['offset'] = match.start()
        findings.append(item)
    return findings


def merge_findings(static_findings: list[dict], llm_result: dict | None) -> tuple[list[dict], bool]:
    findings = list(static_findings)
    llm_used = False
    if llm_result and isinstance(llm_result, dict):
        llm_used = True
        for item in llm_result.get('findings', []) or []:
            if not isinstance(item, dict):
                continue
            findings.append({
                'id': item.get('id', 'LLM_SEMANTIC'),
                'category': item.get('category', 'prompt_injection'),
                'severity': item.get('severity', 'medium'),
                'weight': int(item.get('weight', 45)),
                'title': item.get('title', 'Semantic security finding'),
                'title_ar': item.get('title_ar', 'نتيجة تحليل دلالي'),
                'recommendation': item.get('recommendation', 'Review the content before execution.'),
                'recommendation_ar': item.get('recommendation_ar', 'راجع المحتوى قبل التنفيذ.'),
                'match': item.get('evidence', '')[:240],
                'offset': -1,
                'source': 'llm',
            })
    return findings, llm_used


def risk_score(findings: list[dict], llm_result: dict | None = None) -> int:
    if not findings and not llm_result:
        return 0
    weights = sorted([max(0, min(100, int(f.get('weight', 0)))) for f in findings], reverse=True)
    score = 0.0
    for weight in weights:
        score = 100 - ((100 - score) * (100 - weight) / 100)
    if llm_result and isinstance(llm_result.get('risk_score'), (int, float)):
        score = max(score, float(llm_result['risk_score']))
    return int(round(min(100, score)))


def threat_level(score: int) -> str:
    if score >= 85:
        return 'critical'
    if score >= 65:
        return 'high'
    if score >= 35:
        return 'medium'
    if score > 0:
        return 'low'
    return 'none'


def decision_for(score: int, approval_threshold: int, block_threshold: int) -> str:
    if score >= block_threshold:
        return 'block'
    if score >= approval_threshold:
        return 'approval'
    return 'allow'


_SECRET_REDACTIONS = (
    (re.compile(r"gh[pousr]_[A-Za-z0-9_]{20,}"), "[REDACTED_GITHUB_TOKEN]"),
    (re.compile(r"(?:AKIA|ASIA)[A-Z0-9]{16}"), "[REDACTED_AWS_KEY]"),
    (re.compile(r"-----BEGIN\s+(?:RSA|OPENSSH|EC|DSA)?\s*PRIVATE KEY-----[\s\S]*?-----END\s+(?:RSA|OPENSSH|EC|DSA)?\s*PRIVATE KEY-----", re.I), "[REDACTED_PRIVATE_KEY]"),
    (re.compile(r"(?im)^([A-Z0-9_]*(?:TOKEN|SECRET|PASSWORD|API_KEY|PRIVATE_KEY)[A-Z0-9_]*\s*[=:]\s*)(.+)$"), r"\1[REDACTED]"),
)


def sanitize_for_storage(text: str, limit: int = 50000) -> str:
    """Redact common secret material before persisting prompt/tool content."""
    value = (text or '')[:limit]
    for pattern, replacement in _SECRET_REDACTIONS:
        value = pattern.sub(replacement, value)
    return value


def _sanitize_nested(value):
    if isinstance(value, str):
        return sanitize_for_storage(value, limit=10000)
    if isinstance(value, list):
        return [_sanitize_nested(v) for v in value]
    if isinstance(value, dict):
        return {k: _sanitize_nested(v) for k, v in value.items()}
    return value


def findings_json(findings: list[dict]) -> str:
    return json.dumps(_sanitize_nested(findings), ensure_ascii=False)
