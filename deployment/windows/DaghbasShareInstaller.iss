#define MyAppName "Daghbas Share"
#define MyAppVersion "0.1.0"
#define MyAppPublisher "Daghbas"
#define MyAppExeName "DaghbasShareClient.exe"

[Setup]
AppId={{8D5DB21B-127D-4A6C-B707-5B94D487A67F}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
DefaultDirName={autopf}\DaghbasShare
DefaultGroupName=Daghbas Share
OutputDir=..\..\release
OutputBaseFilename=DaghbasShareInstaller
Compression=lzma
SolidCompression=yes
WizardStyle=modern

[Files]
Source: "..\..\dist\DaghbasShareClient.exe"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\..\dist\DaghbasShareServer.exe"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\..\.env.example"; DestDir: "{app}"; DestName: ".env"; Flags: ignoreversion onlyifdoesntexist
Source: "..\..\README.md"; DestDir: "{app}"; Flags: ignoreversion

[Icons]
Name: "{group}\Daghbas Share Client"; Filename: "{app}\DaghbasShareClient.exe"
Name: "{group}\Daghbas Share Server"; Filename: "{app}\DaghbasShareServer.exe"
Name: "{group}\Uninstall Daghbas Share"; Filename: "{uninstallexe}"

[Run]
Filename: "{app}\DaghbasShareClient.exe"; Description: "Launch Client"; Flags: nowait postinstall skipifsilent
