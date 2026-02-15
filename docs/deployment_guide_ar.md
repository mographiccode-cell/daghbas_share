# دليل النشر والتشغيل الكامل (بالعربية)

هذا الدليل يشرح تشغيل النظام كسيرفر داخل الشركة، تشغيل الواجهة على الشبكة، بناء الملف التنفيذي للعميل، وتثبيت PostgreSQL خطوة بخطوة.

## 1) المتطلبات الأساسية

- نظام تشغيل السيرفر: Ubuntu 22.04+ أو Windows Server.
- Python 3.10+
- PostgreSQL 14+
- فتح المنفذ `8000` داخل الشبكة الداخلية.

## 2) تشغيل السيرفر على الشبكة

### 2.1 تجهيز البيئة
```bash
python -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
cp .env.example .env
```

### 2.2 تعديل `.env`
- عدّل القيم التالية بقيم قوية:
  - `SECRET_KEY`
  - `INSTALLATION_MASTER_KEY`
  - `LICENSE_SECRET`
- اضبط `DATABASE_URL` على PostgreSQL الحقيقي.

### 2.3 تشغيل الخدمة
```bash
./scripts/run_server.sh
```
السيرفر سيعمل على:
- `http://SERVER_IP:8000`

الواجهة الشبكية (لكل أجهزة الشبكة عبر المتصفح):
- `http://SERVER_IP:8000/ui`


## 2.4 التثبيت الأسهل (نسخ ولصق)
```bash
python -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
cp .env.example .env
./scripts/run_server.sh
```

## 3) تثبيت PostgreSQL

### Ubuntu
```bash
./scripts/install_postgres_ubuntu.sh
```

### اختبار الاتصال
```bash
psql postgresql://daghbas:daghbas@127.0.0.1:5432/daghbas_share -c "SELECT 1;"
```

## 4) تشغيل الخدمة تلقائيًا (Systemd)

1. انسخ ملف الخدمة:
```bash
sudo cp deployment/daghbas-share.service /etc/systemd/system/
```
2. عدّل المسارات واسم المستخدم داخل الملف عند الحاجة.
3. فعّل الخدمة:
```bash
sudo systemctl daemon-reload
sudo systemctl enable daghbas-share
sudo systemctl start daghbas-share
sudo systemctl status daghbas-share
```

## 5) بناء الملف التنفيذي للعميل

## 5.1 Windows (موصى به لملف exe)
```powershell
./scripts/build_client_exe.ps1
```
الناتج:
- `dist/DaghbasShareClient.exe`

## 5.2 Linux
```bash
./scripts/build_client_exe.sh
```
الناتج:
- `dist/DaghbasShareClient`

> ملاحظة: بناء exe الحقيقي يجب أن يتم على Windows غالبًا.

## 6) تفعيل جهاز العميل (من الشركة فقط)

- عند أول تشغيل، سيطلب البرنامج تفعيل الجهاز.
- أدخل:
  - اسم العميل
  - مفتاح الشركة `INSTALLATION_MASTER_KEY`
- التطبيق يتصل بـ:
  - `POST /installations/activate`
  - ثم يتحقق عبر `POST /installations/validate`

## 7) سيناريو التشغيل النهائي في الشركة

1. شغّل السيرفر على جهاز مركزي.
2. ثبّت PostgreSQL واربط `DATABASE_URL`.
3. افتح المنفذ 8000 داخل الشبكة.
4. وزّع `DaghbasShareClient.exe` فقط (بدون سورس).
5. فعّل كل جهاز بمفتاح الشركة.
6. أي جهاز على الشبكة يمكنه استخدام واجهة الويب من:
   - `http://SERVER_IP:8000/ui`

## 8) أخطاء شائعة وحلولها

### خطأ: `Could not import module app.main`
- السبب: تشغيل الأمر من مجلد خاطئ أو عدم تفعيل البيئة الافتراضية.
- الحل: شغّل من جذر المشروع وفعل `.venv`.

### خطأ: `connection refused` عند PostgreSQL
- السبب: الخدمة غير شغالة أو إعدادات خاطئة.
- الحل:
  - `sudo systemctl status postgresql`
  - راجع `DATABASE_URL`.

### خطأ: `Invalid master key`
- السبب: مفتاح تفعيل خاطئ.
- الحل: استخدم قيمة `INSTALLATION_MASTER_KEY` الصحيحة من `.env` على السيرفر.

### خطأ: `License token mismatch` أو `Token is not bound to this device`
- السبب: محاولة نسخ ترخيص جهاز إلى جهاز آخر.
- الحل: فعّل الجهاز الجديد رسميًا من الشركة.

### خطأ: واجهة `/ui` لا تعمل على جهاز آخر
- السبب: Firewall أو السيرفر يعمل على localhost فقط.
- الحل:
  - استخدم `--host 0.0.0.0`
  - افتح المنفذ 8000 في الجدار الناري.

## 9) توصيات إنتاجية إضافية

- استخدم HTTPS عبر Nginx reverse proxy.
- فعّل نسخ احتياطي يومي لقاعدة البيانات.
- اعتمد Git tags لكل إصدار (`vX.Y.Z`).
- وقّع الملف التنفيذي رقميًا (Code Signing).


## 10) تشخيص أخطاء الواجهات بدقة

- واجهة الويب تعرض تفاصيل HTTP مباشرة داخل الصفحة (status + detail).
- عميل سطح المكتب يسجل الأخطاء في ملف: `~/daghbas_share_client.log`.
- عند مشاركة خطأ للدعم، أرسل:
  1) نص الخطأ من الواجهة
  2) آخر 50 سطر من ملف السجل
  3) لقطة من إعداد `.env` بدون الأسرار


## 11) سياسة حفظ الملفات داخل نفس المجلد

- النظام يطبق حفظًا مباشرًا داخل نفس الملف (In-Place Save).
- لا يتم نقل الملف إلى مسار آخر عند التعديل.
- إذا رفع المستخدم ملفًا بنفس الاسم داخل نفس المجلد، يتم تحديث نفس السجل ونفس المسار ورفع الإصدار.
- endpoint الصريح للحفظ: `PUT /files/{file_id}/save`.
