from pathlib import Path
import sys

path = Path(sys.argv[1] if len(sys.argv) > 1 else 'generated/android/app/build.gradle.kts')
text = path.read_text(encoding='utf-8')

if 'isCoreLibraryDesugaringEnabled = true' not in text:
    marker = '    compileOptions {\n'
    if marker not in text:
        raise SystemExit('compileOptions marker not found')
    text = text.replace(
        marker,
        marker + '        isCoreLibraryDesugaringEnabled = true\n',
        1,
    )

if 'coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:' not in text:
    dependency = '''\n\ndependencies {\n    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.5")\n}\n'''
    text = text.rstrip() + dependency

path.write_text(text, encoding='utf-8')
print(f'PATCHED_ANDROID_DESUGARING {path}')
