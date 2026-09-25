export const translations = {
  en: {
    appName: 'AI Agent Security Guard', tagline: 'Runtime security for AI agents and Codex',
    login: 'Sign in', signup: 'Create account', name: 'Full name', email: 'Email', password: 'Password',
    noAccount: 'Create a new account', haveAccount: 'Already have an account?', signOut: 'Sign out',
    dashboard: 'Dashboard', scanner: 'Security Scanner', approvals: 'Approvals', policies: 'Policies', audit: 'Audit Logs', integration: 'Codex Integration',
    totalScans: 'Total scans', blocked: 'Blocked', allowed: 'Allowed', waiting: 'Waiting approval', critical: 'Critical',
    recentActivity: 'Recent security activity', source: 'Source', decision: 'Decision', risk: 'Risk', threat: 'Threat level', date: 'Date',
    scanTitle: 'Analyze prompt or tool action', scanHelp: 'Paste untrusted text, a prompt, or a tool command. Rules run first; optional Ollama semantic analysis runs when enabled.',
    sourceType: 'Source type', prompt: 'Prompt', tool: 'Tool action', content: 'External content', toolName: 'Tool name', text: 'Content to analyze', analyze: 'Analyze',
    findings: 'Findings', noFindings: 'No configured rule matched.', recommendation: 'Recommendation',
    pending: 'Pending', approved: 'Approved', rejected: 'Rejected', approve: 'Approve', reject: 'Reject', noApprovals: 'No approval requests.',
    approvalThreshold: 'Approval threshold', blockThreshold: 'Block threshold', llmEnabled: 'Enable local LLM analysis', sensitiveApproval: 'Require approval for sensitive files', categories: 'Enabled categories', save: 'Save policy',
    integrationTitle: 'Connect Codex to this security dashboard', integrationText: 'Generate a local integration token, store it in an environment variable, then install the included Codex hooks.', generateToken: 'Generate / rotate token', tokenWarning: 'This token is shown only now. Store it securely and never commit it to GitHub.', copy: 'Copy', hookConfig: 'Hook setup',
    logs: 'Events', event: 'Event', details: 'Details', language: 'العربية', loading: 'Loading...', refresh: 'Refresh', error: 'Something went wrong',
    allow: 'Allow', block: 'Block', approval: 'Approval', none: 'None', low: 'Low', medium: 'Medium', high: 'High',
    exportReport: 'Export CSV report', accountSecurity: 'Each account is isolated by user_id at every API query.', codexStatus: 'Codex token configured', ollamaStatus: 'Local LLM enabled', yes: 'Yes', no: 'No'
  },
  ar: {
    appName: 'حارس أمان وكلاء الذكاء الاصطناعي', tagline: 'حماية وقت التشغيل للوكلاء وCodex',
    login: 'تسجيل الدخول', signup: 'إنشاء حساب', name: 'الاسم الكامل', email: 'البريد الإلكتروني', password: 'كلمة المرور',
    noAccount: 'إنشاء حساب جديد', haveAccount: 'لديك حساب بالفعل؟', signOut: 'تسجيل الخروج',
    dashboard: 'لوحة التحكم', scanner: 'الفحص الأمني', approvals: 'الموافقات', policies: 'السياسات', audit: 'سجل التدقيق', integration: 'ربط Codex',
    totalScans: 'إجمالي الفحوصات', blocked: 'محظور', allowed: 'مسموح', waiting: 'بانتظار الموافقة', critical: 'حرج',
    recentActivity: 'آخر الأنشطة الأمنية', source: 'المصدر', decision: 'القرار', risk: 'الخطورة', threat: 'مستوى التهديد', date: 'التاريخ',
    scanTitle: 'تحليل Prompt أو عملية أداة', scanHelp: 'ألصق نصًا غير موثوق أو Prompt أو أمر أداة. تعمل القواعد أولًا ثم تحليل Ollama الدلالي عند تفعيله.',
    sourceType: 'نوع المصدر', prompt: 'Prompt', tool: 'عملية أداة', content: 'محتوى خارجي', toolName: 'اسم الأداة', text: 'المحتوى المراد تحليله', analyze: 'فحص',
    findings: 'النتائج', noFindings: 'لم تتطابق أي قاعدة مفعّلة.', recommendation: 'التوصية',
    pending: 'معلق', approved: 'مقبول', rejected: 'مرفوض', approve: 'موافقة', reject: 'رفض', noApprovals: 'لا توجد طلبات موافقة.',
    approvalThreshold: 'حد طلب الموافقة', blockThreshold: 'حد الحظر', llmEnabled: 'تفعيل تحليل LLM المحلي', sensitiveApproval: 'طلب موافقة للملفات الحساسة', categories: 'فئات الحماية المفعّلة', save: 'حفظ السياسة',
    integrationTitle: 'ربط Codex بلوحة الحماية', integrationText: 'أنشئ رمز ربط محليًا، خزّنه في متغير بيئة، ثم ثبّت Codex Hooks المرفقة.', generateToken: 'إنشاء / تدوير الرمز', tokenWarning: 'يظهر هذا الرمز الآن فقط. احفظه بأمان ولا ترفعه إلى GitHub.', copy: 'نسخ', hookConfig: 'إعداد Hooks',
    logs: 'الأحداث', event: 'الحدث', details: 'التفاصيل', language: 'English', loading: 'جارٍ التحميل...', refresh: 'تحديث', error: 'حدث خطأ',
    allow: 'سماح', block: 'حظر', approval: 'موافقة', none: 'لا يوجد', low: 'منخفض', medium: 'متوسط', high: 'مرتفع',
    exportReport: 'تصدير تقرير CSV', accountSecurity: 'يتم عزل بيانات كل حساب باستخدام user_id في كل استعلام API.', codexStatus: 'رمز Codex مهيأ', ollamaStatus: 'LLM المحلي مفعّل', yes: 'نعم', no: 'لا'
  }
}
