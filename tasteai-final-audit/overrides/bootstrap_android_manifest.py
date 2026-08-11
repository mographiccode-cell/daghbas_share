from pathlib import Path
import re

root = Path(__file__).resolve().parent
main_manifest = root / 'android/app/src/main/AndroidManifest.xml'
debug_manifest = root / 'android/app/src/debug/AndroidManifest.xml'

if not main_manifest.exists():
    raise SystemExit('Run flutter create/bootstrap first; AndroidManifest.xml is missing.')

s = main_manifest.read_text(encoding='utf-8')
permissions = [
    'android.permission.INTERNET',
    'android.permission.ACCESS_FINE_LOCATION',
    'android.permission.ACCESS_COARSE_LOCATION',
]
insert = ''
for permission in permissions:
    if permission not in s:
        insert += f'    <uses-permission android:name="{permission}" />\n'
if insert:
    m = re.search(r'<manifest\b[^>]*>', s, flags=re.IGNORECASE | re.DOTALL)
    if not m:
        raise SystemExit('Invalid AndroidManifest.xml: <manifest> tag not found.')
    s = s[:m.end()] + '\n' + insert + s[m.end():]

# Google Maps for Flutter: inject a manifest placeholder. The real value is
# loaded from android/local.properties as MAPS_API_KEY by the Gradle patch below.
if 'com.google.android.geo.API_KEY' not in s:
    app_match = re.search(r'<application\b[^>]*>', s, flags=re.IGNORECASE | re.DOTALL)
    if not app_match:
        raise SystemExit('Invalid AndroidManifest.xml: <application> tag not found.')
    meta = '\n        <meta-data android:name="com.google.android.geo.API_KEY" android:value="${MAPS_API_KEY}" />'
    s = s[:app_match.end()] + meta + s[app_match.end():]

# Give the generated Android shell the product name used by the Flutter UI.
s = re.sub(r'android:label="[^"]*"', 'android:label="TasteAI"', s, count=1)

# Do not enable cleartext traffic in the production manifest. The emulator uses a
# debug-only override so release builds are expected to point at an HTTPS API.
s = re.sub(r'\s+android:usesCleartextTraffic="true"', '', s)
main_manifest.write_text(s, encoding='utf-8')


# flutter_secure_storage 11 targets Android API 24+. Keep the generated Flutter
# Gradle structure, but pin only the app minSdk after generation.
gradle = root / 'android/app/build.gradle.kts'
if gradle.exists():
    g = gradle.read_text(encoding='utf-8')
    if 'val tasteAiLocalProperties = Properties()' not in g:
        prefix = '''import java.util.Properties

val tasteAiLocalProperties = Properties()
val tasteAiLocalPropertiesFile = rootProject.file("local.properties")
if (tasteAiLocalPropertiesFile.exists()) {
    tasteAiLocalPropertiesFile.inputStream().use { input -> tasteAiLocalProperties.load(input) }
}

'''
        g = prefix + g
    if 'minSdk = flutter.minSdkVersion' in g:
        g = g.replace('minSdk = flutter.minSdkVersion', 'minSdk = 24')
    elif re.search(r'\bminSdk\s*=\s*\d+', g):
        g = re.sub(r'\bminSdk\s*=\s*\d+', 'minSdk = 24', g, count=1)
    if 'manifestPlaceholders["MAPS_API_KEY"]' not in g:
        default_marker = re.search(r'defaultConfig\s*\{', g)
        if not default_marker:
            raise SystemExit('Could not find defaultConfig in build.gradle.kts')
        insertion = '\n        manifestPlaceholders["MAPS_API_KEY"] = tasteAiLocalProperties.getProperty("MAPS_API_KEY", "")'
        g = g[:default_marker.end()] + insertion + g[default_marker.end():]
    gradle.write_text(g, encoding='utf-8')

debug_manifest.parent.mkdir(parents=True, exist_ok=True)
debug_manifest.write_text('''<manifest xmlns:android="http://schemas.android.com/apk/res/android">
    <application android:usesCleartextTraffic="true" />
</manifest>
''', encoding='utf-8')
print('Patched Android permissions, minSdk 24, and debug-only HTTP access.')
