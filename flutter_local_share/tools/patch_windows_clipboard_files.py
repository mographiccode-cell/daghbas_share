from pathlib import Path
import sys

path = Path(sys.argv[1] if len(sys.argv) > 1 else 'generated/windows/runner/flutter_window.cpp')
text = path.read_text(encoding='utf-8')

if '#include <flutter/method_channel.h>' not in text:
    marker = '#include "flutter_window.h"\n'
    if marker not in text:
        raise SystemExit('flutter_window include marker not found')
    includes = '''#include "flutter_window.h"\n\n#include <flutter/method_channel.h>\n#include <flutter/standard_method_codec.h>\n#include <shellapi.h>\n\n#include <memory>\n#include <string>\n#include <vector>\n'''
    text = text.replace(marker, includes, 1)

helper_marker = 'namespace {\n'
helper_code = r'''namespace {

std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>>
    g_local_share_native_channel;

std::string WideToUtf8(const std::wstring& value) {
  if (value.empty()) return std::string();
  const int size = ::WideCharToMultiByte(CP_UTF8, 0, value.c_str(),
                                          static_cast<int>(value.size()),
                                          nullptr, 0, nullptr, nullptr);
  if (size <= 0) return std::string();
  std::string result(size, '\0');
  ::WideCharToMultiByte(CP_UTF8, 0, value.c_str(),
                        static_cast<int>(value.size()), result.data(), size,
                        nullptr, nullptr);
  return result;
}

flutter::EncodableList ClipboardFiles() {
  flutter::EncodableList files;
  if (!::IsClipboardFormatAvailable(CF_HDROP)) return files;
  if (!::OpenClipboard(nullptr)) return files;

  const HANDLE data = ::GetClipboardData(CF_HDROP);
  if (data != nullptr) {
    const HDROP drop = reinterpret_cast<HDROP>(data);
    const UINT count = ::DragQueryFileW(drop, 0xFFFFFFFF, nullptr, 0);
    for (UINT index = 0; index < count; ++index) {
      const UINT length = ::DragQueryFileW(drop, index, nullptr, 0);
      if (length == 0 || length > 32767) continue;
      std::wstring buffer(length + 1, L'\0');
      const UINT written =
          ::DragQueryFileW(drop, index, buffer.data(), length + 1);
      if (written == 0) continue;
      buffer.resize(written);
      const std::string utf8 = WideToUtf8(buffer);
      if (!utf8.empty()) files.emplace_back(utf8);
    }
  }
  ::CloseClipboard();
  return files;
}
'''

if 'flutter::EncodableList ClipboardFiles()' not in text:
    if helper_marker not in text:
        raise SystemExit('namespace marker not found')
    text = text.replace(helper_marker, helper_code, 1)

register_marker = '  RegisterPlugins(flutter_controller_->engine());\n'
register_code = r'''  RegisterPlugins(flutter_controller_->engine());

  g_local_share_native_channel =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          flutter_controller_->engine()->messenger(), "local_share/native",
          &flutter::StandardMethodCodec::GetInstance());
  g_local_share_native_channel->SetMethodCallHandler(
      [](const flutter::MethodCall<flutter::EncodableValue>& call,
         std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
        if (call.method_name() == "getClipboardFiles") {
          result->Success(flutter::EncodableValue(ClipboardFiles()));
          return;
        }
        result->NotImplemented();
      });
'''
if 'call.method_name() == "getClipboardFiles"' not in text:
    if register_marker not in text:
        raise SystemExit('RegisterPlugins marker not found')
    text = text.replace(register_marker, register_code, 1)

path.write_text(text, encoding='utf-8')
print(f'PATCHED_WINDOWS_CLIPBOARD_FILES {path}')
