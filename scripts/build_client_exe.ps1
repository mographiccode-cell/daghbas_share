param(
  [string]$PythonExe = "python"
)

$ErrorActionPreference = "Stop"

& $PythonExe -m pip install pyinstaller
& $PythonExe -m PyInstaller --noconfirm --onefile --windowed --name DaghbasShareClient desktop_client/main.py

Write-Host "تم إنشاء الملف التنفيذي داخل dist/DaghbasShareClient.exe"
