from pathlib import Path
import sys

path = Path(sys.argv[1] if len(sys.argv) > 1 else 'generated/windows/runner/main.cpp')
text = path.read_text(encoding='utf-8')

if '#include <filesystem>' not in text:
    marker = '#include <windows.h>'
    if marker not in text:
        raise SystemExit('windows.h include not found')
    text = text.replace(marker, marker + '\n#include <filesystem>\n#include <system_error>', 1)

cleanup = r'''
  // LocalShare: synchronously remove temporary received files before a normal
  // Windows process exit. Crash leftovers are also removed on the next launch
  // by the Dart service startup cleanup.
  wchar_t temp_path[MAX_PATH + 1] = {0};
  const DWORD temp_len = ::GetTempPathW(MAX_PATH, temp_path);
  if (temp_len > 0 && temp_len < MAX_PATH) {
    std::error_code cleanup_error;
    std::filesystem::remove_all(
        std::filesystem::path(temp_path) / L"LocalShare", cleanup_error);
  }
'''

needle = '  ::CoUninitialize();'
if needle not in text:
    raise SystemExit('CoUninitialize marker not found')
if 'LocalShare: synchronously remove temporary received files' not in text:
    text = text.replace(needle, cleanup + '\n' + needle, 1)

path.write_text(text, encoding='utf-8')
print(f'PATCHED_WINDOWS_TEMP_CLEANUP {path}')
