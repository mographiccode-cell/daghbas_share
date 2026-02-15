# مخطط النظام الداخلي لإدارة المهام والملفات

## 1) ملخص تنفيذي
هذا المستند يترجم الرؤية إلى خطة عملية لبناء **تطبيق مكتبي داخلي (Intranet Desktop App)** لشركة صغيرة/متوسطة باستخدام:

- **Python**
- **PyQt6** (تطبيق العميل)
- **FastAPI** (الخادم)
- **PostgreSQL** (قاعدة البيانات)

الهدف هو إنهاء الاعتماد على البريد الإلكتروني كوسيلة أساسية لإدارة الملفات والمهام، والانتقال إلى منصة مركزية آمنة وقابلة للتوسع.

---

## 2) المشكلة الحالية والهدف

### الوضع الحالي
- تبادل المهام والملفات عبر البريد الإلكتروني.
- النسخ النهائية محفوظة غالبًا على جهاز المسؤول.
- غياب إدارة مركزية للمجلدات.

### الأثر التشغيلي
- تضارب نسخ الملفات.
- فقدان أثر التعديلات.
- بطء في دورة العمل.
- صعوبة المساءلة (من عدّل ماذا ومتى).

### الهدف من النظام
- إنشاء بيئة مركزية لإدارة الملفات والمهام.
- صلاحيات وصول واضحة حسب الأدوار.
- مزامنة داخل الشبكة الداخلية.
- تتبع كامل للأحداث (Audit Trail).

---

## 3) الرؤية المعمارية

## 3.1 نمط النظام
**Client–Server داخل شبكة الشركة**:

1. **Server Layer**
   - FastAPI REST API
   - PostgreSQL
   - File Storage Service
   - Authentication Service
   - Logging & Audit Service

2. **Desktop Client**
   - PyQt6 GUI
   - API Client
   - File Sync Manager
   - Local cache (اختياري)

## 3.2 تدفق العمل العام
1. المستخدم يسجل الدخول من تطبيق سطح المكتب.
2. التطبيق يحصل على Access/Refresh Tokens.
3. المستخدم يتصفح المجلدات حسب الصلاحية.
4. رفع/تنزيل/قفل ملفات عبر API.
5. جميع العمليات تُسجل في Audit Log.

---

## 4) المعمارية الأمنية

## 4.1 المصادقة وإدارة الجلسات
- Access Token: صلاحية قصيرة (مثال 15 دقيقة).
- Refresh Token: صلاحية أطول (مثال 7 أيام).
- تجديد Access تلقائيًا دون إزعاج المستخدم.
- ربط الجلسة بـ Device ID وIP داخلي (مع مرونة لحالات DHCP).

## 4.2 كلمات المرور
- تخزين `password_hash` فقط باستخدام **bcrypt**.
- منع تسجيل كلمات المرور في السجلات.

## 4.3 أمان النقل
- **HTTPS فقط** داخل الشبكة.
- TLS بشهادة داخلية (CA داخلية أو Self-hosted PKI).
- رفض أي طلب HTTP غير مشفر.

## 4.4 حماية تخزين الملفات
- عدم حفظ الملف باسمه الحقيقي في نظام الملفات.
- توليد اسم تخزين داخلي UUID وربطه ميتاداتيًا بقاعدة البيانات.

## 4.5 منع التضارب (File Locking)
- إنشاء Lock عند بدء التحرير.
- منع التعديل المتزامن من مستخدم آخر.
- تحرير القفل عند الإغلاق أو انتهاء المهلة (TTL).

## 4.6 Audit Log
- تسجيل كل حدث مهم:
  - فتح ملف
  - رفع/تعديل/حذف
  - تغيير صلاحيات
  - إنشاء/تعديل مهام
- يمنع التعديل أو الحذف المباشر لسجل التدقيق من الواجهة.

## 4.7 RBAC
أدوار مقترحة:
- Admin
- Manager
- Employee
- Read-Only

صلاحيات تفصيلية:
- Create Folder
- Upload
- Download
- Edit
- Delete
- Assign Task

---

## 5) تصميم قاعدة البيانات (PostgreSQL)

الجداول الأساسية:

- **users**: `id, username, password_hash, role_id, device_id, is_active, created_at`
- **roles**: `id, name`
- **folders**: `id, name, parent_id, created_by, created_at`
- **files**: `id, folder_id, stored_name, original_name, version, size, created_by, updated_at, is_locked`
- **permissions**: `id, user_id, folder_id, can_read, can_write, can_delete`
- **tasks**: `id, title, description, assigned_to, status, due_date`
- **logs**: `id, user_id, action, target_type, target_id, timestamp`

### ملاحظات تقنية مهمة
- تفعيل مفاتيح أجنبية (FK) وفهارس على:
  - `files.folder_id`
  - `permissions.user_id`, `permissions.folder_id`
  - `logs.user_id`, `logs.timestamp`
- إضافة قيد Unique مناسب على بعض الحقول (مثل username).

---

## 6) تصميم FastAPI

## 6.1 هيكل المشروع
```text
app/
 ├── main.py
 ├── routers/
 ├── models/
 ├── schemas/
 ├── services/
 ├── auth/
 ├── security/
 └── storage/
```

## 6.2 APIs الأساسية

### Auth
- `POST /login`
- `POST /refresh`
- `POST /logout`

### Users
- `GET /users`
- `POST /users`
- `PATCH /users/{id}`

### Folders
- `GET /folders`
- `POST /folders`
- `DELETE /folders/{id}`

### Files
- `POST /upload`
- `GET /download/{id}`
- `POST /lock/{id}`
- `POST /unlock/{id}`

### Tasks
- `POST /tasks`
- `PATCH /tasks/{id}`
- `GET /tasks/my`

---

## 7) تصميم تطبيق PyQt6

الشاشات الأساسية:
1. تسجيل الدخول
2. لوحة تحكم
3. شجرة المجلدات (Tree View)
4. عرض الملفات
5. إدارة المهام
6. لوحة المسؤول

مبادئ هندسية:
- MVC Pattern
- Service Layer للتكامل مع API
- Threading للرفع/التحميل
- Progress bars + Notifications

---

## 8) الهوية البصرية وتجربة المستخدم (عربي أولًا)

- لغة الواجهة: **العربية بالكامل** (RTL).
- الخط المعتمد: **IBM Plex Sans Arabic**.
- دعم اتجاه النص Right-to-Left في كل النوافذ والجداول.
- ألوان هادئة وتباين واضح.
- رسائل تأكيد قبل الحذف، وتنبيهات نجاح/فشل مفهومة.

### إرشادات تنفيذ سريعة في PyQt6
- تفعيل الاتجاه:
  - `app.setLayoutDirection(Qt.RightToLeft)`
- تحميل الخط عند بدء التطبيق:
  - `QFontDatabase.addApplicationFont("assets/fonts/IBMPlexSansArabic-Regular.ttf")`

---

## 9) إستراتيجية التخزين والمزامنة

مجلد تخزين مركزي:
```text
/data/storage/
```

التقسيم المقترح:
- حسب السنة
- حسب القسم
- حسب المجلد (Folder ID)

اعتبارات مهمة:
- حد أعلى لحجم الملف.
- فحص الامتدادات المسموحة.
- التحقق من سلامة الملف قبل التسجيل النهائي.

---

## 10) الأداء والاعتمادية

- Indexing مدروس في PostgreSQL.
- Pagination في القوائم الكبيرة.
- Lazy loading للمجلدات الفرعية.
- ضغط الملفات الكبيرة أثناء النقل عند الحاجة.

---

## 11) النسخ الاحتياطي والتعافي

- نسخة يومية لقاعدة البيانات.
- نسخة أسبوعية لمجلد الملفات.
- نسخة خارجية (NAS/External HDD).
- اختبار دوري لعملية الاستعادة (Restore Drill).

---

## 12) خارطة التنفيذ المرحلية

### المرحلة 1 (أسبوع 1–2)
- إعداد قاعدة البيانات
- نظام Auth
- إدارة المستخدمين الأساسية

### المرحلة 2 (أسبوع 3–4)
- إدارة المجلدات والملفات
- Upload/Download
- Locking

### المرحلة 3 (أسبوع 5)
- إدارة المهام
- نظام الصلاحيات

### المرحلة 4 (أسبوع 6)
- Audit Logs
- Security Hardening
- اختبارات شاملة

---

## 13) المخاطر وخطط التخفيف

| الخطر | خطة التخفيف |
|---|---|
| فقدان بيانات | Backup دوري + اختبار الاستعادة |
| اختراق داخلي | HTTPS + RBAC + مراجعة صلاحيات |
| تضارب التعديلات | File Lock + Versioning |
| حمل زائد | حدود رفع + مراقبة + تحسين قواعد البيانات |

---

## 14) قرار فني نهائي

الحل المقترح:
- آمن ومناسب لبيئة داخلية.
- قابل للتوسع تدريجيًا.
- يدعم حوكمة الملفات والمهام.
- قابل للتحول لاحقًا إلى واجهة Web إذا تطلبت الأعمال ذلك.

