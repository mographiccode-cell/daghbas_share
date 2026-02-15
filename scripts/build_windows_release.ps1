param(
  [string]$Version = "0.1.0",
  [string]$PythonExe = "python"
)

$ErrorActionPreference = "Stop"

$Root = Split-Path -Parent $PSScriptRoot
Set-Location $Root

& $PythonExe -m pip install -r requirements.txt
& $PythonExe -m PyInstaller --noconfirm --onefile --windowed --name DaghbasShareClient desktop_client/main.py
& $PythonExe -m PyInstaller --noconfirm --onefile --name DaghbasShareServer server_entry.py

$OutDir = Join-Path $Root "release/windows/$Version"
New-Item -ItemType Directory -Path $OutDir -Force | Out-Null
New-Item -ItemType Directory -Path (Join-Path $OutDir "config") -Force | Out-Null
New-Item -ItemType Directory -Path (Join-Path $OutDir "docs") -Force | Out-Null

Copy-Item "dist/DaghbasShareClient.exe" (Join-Path $OutDir "DaghbasShareClient.exe") -Force
Copy-Item "dist/DaghbasShareServer.exe" (Join-Path $OutDir "DaghbasShareServer.exe") -Force
Copy-Item ".env.example" (Join-Path $OutDir "config/.env.example") -Force
Copy-Item "README.md" (Join-Path $OutDir "README.md") -Force
Copy-Item "docs/deployment_guide_ar.md" (Join-Path $OutDir "docs/deployment_guide_ar.md") -Force

$zipPath = Join-Path $Root "release/DaghbasShare-windows-$Version.zip"
if (Test-Path $zipPath) { Remove-Item $zipPath -Force }
Compress-Archive -Path (Join-Path $OutDir "*") -DestinationPath $zipPath

Write-Host "Windows release created: $zipPath"
Write-Host "Optional: Compile Inno Setup script at deployment/windows/DaghbasShareInstaller.iss"
