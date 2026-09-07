import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

class ClipboardPastePayload {
  const ClipboardPastePayload({
    required this.files,
    required this.temporaryFiles,
    this.text,
  });

  final List<File> files;
  final List<File> temporaryFiles;
  final String? text;

  bool get hasFiles => files.isNotEmpty;
}

Future<ClipboardPastePayload> readClipboardForChat() async {
  if (!Platform.isWindows) {
    final data = await Clipboard.getData('text/plain');
    return ClipboardPastePayload(
      files: const <File>[],
      temporaryFiles: const <File>[],
      text: data?.text,
    );
  }

  final files = await _readWindowsFileDropList();
  if (files.isNotEmpty) {
    return ClipboardPastePayload(files: files, temporaryFiles: const <File>[]);
  }

  final image = await _readWindowsClipboardImage();
  if (image != null) {
    return ClipboardPastePayload(
      files: <File>[image],
      temporaryFiles: <File>[image],
    );
  }

  final data = await Clipboard.getData('text/plain');
  return ClipboardPastePayload(
    files: const <File>[],
    temporaryFiles: const <File>[],
    text: data?.text,
  );
}

Future<List<File>> _readWindowsFileDropList() async {
  try {
    final result = await Process.run('powershell.exe', <String>[
      '-NoProfile',
      '-NonInteractive',
      '-STA',
      '-Command',
      r'''$ErrorActionPreference='SilentlyContinue'; $items=Get-Clipboard -Format FileDropList; if($null -ne $items){$items | ForEach-Object { $_.FullName }}''',
    ], runInShell: false).timeout(const Duration(seconds: 5));
    if (result.exitCode != 0) return const <File>[];
    final paths = '${result.stdout}'
        .split(RegExp(r'[\r\n]+'))
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .take(100);
    final output = <File>[];
    for (final path in paths) {
      final file = File(path);
      if (await file.exists()) output.add(file);
    }
    return output;
  } catch (_) {
    return const <File>[];
  }
}

Future<File?> _readWindowsClipboardImage() async {
  try {
    final root = await getTemporaryDirectory();
    final folder = Directory(
      '${root.path}${Platform.pathSeparator}LocalShare${Platform.pathSeparator}clipboard',
    );
    await folder.create(recursive: true);
    final output = File(
      '${folder.path}${Platform.pathSeparator}clipboard_${DateTime.now().microsecondsSinceEpoch}.png',
    );
    final escaped = output.path.replaceAll("'", "''");
    final script =
        '''
\$ErrorActionPreference='SilentlyContinue'
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
\$img=[System.Windows.Forms.Clipboard]::GetImage()
if(\$null -ne \$img){
  \$img.Save('$escaped',[System.Drawing.Imaging.ImageFormat]::Png)
  \$img.Dispose()
  Write-Output 'OK'
}
''';
    final result = await Process.run('powershell.exe', <String>[
      '-NoProfile',
      '-NonInteractive',
      '-STA',
      '-Command',
      script,
    ], runInShell: false).timeout(const Duration(seconds: 8));
    if (result.exitCode == 0 &&
        await output.exists() &&
        await output.length() > 0) {
      return output;
    }
    if (await output.exists()) {
      try {
        await output.delete();
      } catch (_) {}
    }
  } catch (_) {}
  return null;
}
