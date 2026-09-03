#!/usr/bin/env bash
set -euo pipefail
RES="app/android/app/src/main/res"
mkdir -p "$RES/mipmap-anydpi"
cat > "$RES/mipmap-anydpi/ic_launcher.xml" <<'XML'
<vector xmlns:android="http://schemas.android.com/apk/res/android"
    android:width="108dp"
    android:height="108dp"
    android:viewportWidth="108"
    android:viewportHeight="108">
    <path
        android:fillColor="#0B0818"
        android:pathData="M0,0H108V108H0Z" />
    <path
        android:fillColor="#00000000"
        android:strokeColor="#8B5CF6"
        android:strokeWidth="8"
        android:strokeLineCap="round"
        android:pathData="M54,22 A32,32 0,1 1,53.9,22" />
    <path
        android:fillColor="#A78BFA"
        android:pathData="M26,20 C30,10 42,8 47,18 C39,18 33,21 28,27 Z" />
    <path
        android:fillColor="#C4B5FD"
        android:pathData="M62,18 C68,8 80,10 84,20 L82,27 C75,21 69,18 62,18 Z" />
    <path
        android:fillColor="#FFFFFF"
        android:pathData="M50,36 C50,33 58,33 58,36 L58,56 L70,56 C73,56 73,64 70,64 L54,64 C52,64 50,62 50,60 Z" />
    <path
        android:fillColor="#34D6B6"
        android:pathData="M71,66 C75,62 81,62 85,66 L94,75 C98,79 98,85 94,89 C90,93 84,93 80,89 L71,80 C67,76 67,70 71,66 Z" />
    <path
        android:fillColor="#F1BE4A"
        android:pathData="M66,77 C70,73 76,73 80,77 L84,81 L76,89 C72,93 66,93 62,89 C58,85 58,79 62,75 Z" />
</vector>
XML

echo '=== WAQT APP ICON ==='
cat "$RES/mipmap-anydpi/ic_launcher.xml"
grep -q '@mipmap/ic_launcher' app/android/app/src/main/AndroidManifest.xml
