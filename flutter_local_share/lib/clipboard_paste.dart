import 'dart:async';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:super_clipboard/super_clipboard.dart';

import 'models.dart';

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
  final clipboard = SystemClipboard.instance;
  if (clipboard == null) {
    return const ClipboardPastePayload(files: [], temporaryFiles: []);
  }

  final reader = await clipboard.read();
  final files = <File>[];
  final temporaryFiles = <File>[];
  var imageIndex = 0;

  for (final item in reader.items) {
    if (item.canProvide(Formats.fileUri)) {
      try {
        final uri = await item.readValue(Formats.fileUri);
        if (uri != null && uri.scheme.toLowerCase() == 'file') {
          final file = File.fromUri(uri);
          if (await file.exists()) {
            files.add(file);
            continue;
          }
        }
      } catch (_) {}
    }

    if (item.canProvide(Formats.png)) {
      final completer = Completer<File?>();
      try {
        final suggested = await item.getSuggestedName();
        final progress = item.getFile(
          Formats.png,
          (readerFile) async {
            try {
              final root = await getTemporaryDirectory();
              final folder = Directory(
                '${root.path}${Platform.pathSeparator}LocalShare${Platform.pathSeparator}clipboard',
              );
              await folder.create(recursive: true);
              imageIndex++;
              var name = safeFileName(
                suggested ??
                    readerFile.fileName ??
                    'clipboard_${DateTime.now().millisecondsSinceEpoch}_$imageIndex.png',
              );
              if (!name.toLowerCase().endsWith('.png')) {
                name = '$name.png';
              }
              final output = File(
                '${folder.path}${Platform.pathSeparator}${DateTime.now().microsecondsSinceEpoch}_$name',
              );
              final sink = output.openWrite();
              await sink.addStream(readerFile.getStream());
              await sink.close();
              if (!completer.isCompleted) completer.complete(output);
            } catch (_) {
              if (!completer.isCompleted) completer.complete(null);
            }
          },
          onError: (_) {
            if (!completer.isCompleted) completer.complete(null);
          },
        );
        if (progress != null) {
          final file = await completer.future.timeout(
            const Duration(seconds: 20),
            onTimeout: () => null,
          );
          if (file != null && await file.exists()) {
            files.add(file);
            temporaryFiles.add(file);
          }
        }
      } catch (_) {}
    }
  }

  String? text;
  if (files.isEmpty && reader.canProvide(Formats.plainText)) {
    try {
      text = await reader.readValue(Formats.plainText);
    } catch (_) {}
  }

  return ClipboardPastePayload(
    files: files,
    temporaryFiles: temporaryFiles,
    text: text,
  );
}
