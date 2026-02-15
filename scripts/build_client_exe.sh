#!/usr/bin/env bash
set -euo pipefail

python -m pip install pyinstaller
python -m PyInstaller --noconfirm --onefile --windowed --name DaghbasShareClient desktop_client/main.py

echo "تم إنشاء الملف التنفيذي داخل dist/DaghbasShareClient"
