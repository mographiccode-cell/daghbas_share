# daghbas_share

منتج داخلي لإدارة الملفات والمهام داخل الشركة (FastAPI + PyQt6) مع دعم عربي (RTL) ونظام تفعيل يربط التثبيت بالجهاز.

## المزايا الحالية

- واجهة ويب عربية/إنجليزية سهلة من أي جهاز على الشبكة: `/ui`.
- دعم الثيمات: Light / Dark.
- لوحة Admin داخل الواجهة للتحكم الكامل بالملفات (قفل/فك/نقل/حذف).
- عميل سطح مكتب PyQt6 مع رسائل أخطاء دقيقة وتسجيل أخطاء محلي.
- نظام تفعيل أجهزة Device-Bound.
- حفظ التعديلات على الملفات يتم **في نفس الملف ونفس المجلد** (In-Place Save) بدون نقل/نسخ عند التعديل.

## تشغيل سريع (3 خطوات)

1. إعداد البيئة:
```bash
python -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
cp .env.example .env
```

2. تشغيل السيرفر على الشبكة:
```bash
./scripts/run_server.sh
```

3. افتح من أي جهاز داخل الشبكة:
- API: `http://SERVER_IP:8000`
- واجهة الويب: `http://SERVER_IP:8000/ui`

## تشغيل عميل سطح المكتب

```bash
python -m desktop_client.main
```

> سجل أخطاء العميل يُكتب تلقائيًا في: `~/daghbas_share_client.log`

## بناء ملف تنفيذي للعميل

- Windows:
```powershell
./scripts/build_client_exe.ps1
```
- Linux:
```bash
./scripts/build_client_exe.sh
```

## تفعيل الأجهزة (شركة فقط)

- endpoint التفعيل: `POST /installations/activate`
- endpoint التحقق: `POST /installations/validate`
- التفعيل يتطلب Header: `X-Master-Key` بقيمة `INSTALLATION_MASTER_KEY` من السيرفر.

## توثيق شامل

- [مخطط النظام الداخلي لإدارة المهام والملفات](docs/arabic_system_blueprint.md)
- [سياسة الحوكمة والتوزيع والإصدار](docs/product_governance_ar.md)
- [دليل النشر والتشغيل الكامل](docs/deployment_guide_ar.md)

## سياسة حفظ الملفات (بدون نقل/نسخ)

- عند تعديل ملف موجود في نفس المجلد بنفس الاسم، السيرفر يحفظ التعديل داخل نفس الملف مباشرة.
- endpoint للحفظ المباشر: `PUT /files/{file_id}/save`
- رفع ملف بنفس الاسم في نفس المجلد عبر `/upload` سيُعتبر تحديثًا في نفس المكان (In-Place).


## صلاحية الأدمن المطلقة على الملفات

- الأدمن يستطيع: حفظ، نقل، حذف، قفل، فك قفل أي ملف حتى لو كان الملف مقفولًا من مستخدم آخر.
- endpoints مرتبطة بذلك: `POST /files/{file_id}/move`, `DELETE /files/{file_id}`, `POST /lock/{id}`, `POST /unlock/{id}`, `PUT /files/{file_id}/save`.


## بناء ملف تنفيذي نهائي كامل (Windows + Linux)

### Windows Release (Client + Server)
```powershell
./scripts/build_windows_release.ps1 -Version 1.0.0
```
الناتج:
- `release/DaghbasShare-windows-1.0.0.zip`
- `dist/DaghbasShareClient.exe`
- `dist/DaghbasShareServer.exe`

ولإنشاء Installer احترافي:
- افتح `deployment/windows/DaghbasShareInstaller.iss` عبر Inno Setup ثم Compile.

### Linux Release (Client + Server)
```bash
./scripts/build_linux_release.sh 1.0.0
```
الناتج:
- `release/DaghbasShare-linux-1.0.0.tar.gz`

التثبيت على لينكس بعد فك الضغط:
```bash
cd 1.0.0
./install.sh
```
