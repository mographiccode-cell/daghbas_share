import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:super_clipboard/super_clipboard.dart';

class ClipboardPasteResult {
  const ClipboardPasteResult({this.files = const [], this.text});
  final List<File> files;
  final String? text;
}

class LocalShareClipboard {
  static Future<ClipboardPasteResult> read() async {
    final clipboard = SystemClipboard.instance;
    if (clipboard == null) return const ClipboardPasteResult();
    final reader = await clipboard.read();
    final files = <File>[];

    for (final item in reader.items) {
      if (item.canProvide(Formats.fileUri)) {
        final uri = await item.readValue(Formats.fileUri);
        if (uri != null && uri.scheme == 'file') {
          final file = File.fromUri(uri);
          if (await file.exists()) files.add(file);
        }
        continue;
      }

      if (item.canProvide(Formats.png)) {
        final file = await _materializePng(item);
        if (file != null) files.add(file);
      }
    }

    if (files.isNotEmpty) return ClipboardPasteResult(files: files);
    final text = await reader.readValue(Formats.plainText);
    return ClipboardPasteResult(text: text);
  }

  static Future<File?> _materializePng(ClipboardDataReader item) async {
    final completer = Completer<File?>();
    final temp = await getTemporaryDirectory();
    final folder = Directory(
      '${temp.path}${Platform.pathSeparator}LocalShare${Platform.pathSeparator}clipboard',
    );
    await folder.create(recursive: true);
    final name = 'pasted-${DateTime.now().microsecondsSinceEpoch}.png';
    final out = File('${folder.path}${Platform.pathSeparator}$name');

    final progress = item.getFile(
      Formats.png,
      (dataFile) async {
        try {
          final sink = out.openWrite();
          await for (final chunk in dataFile.getStream()) {
            sink.add(chunk);
          }
          await sink.flush();
          await sink.close();
          completer.complete(out);
        } catch (_) {
          if (!completer.isCompleted) completer.complete(null);
        }
      },
      onError: (_) {
        if (!completer.isCompleted) completer.complete(null);
      },
    );
    if (progress == null && !completer.isCompleted) return null;
    return completer.future.timeout(
      const Duration(seconds: 10),
      onTimeout: () => null,
    );
  }
}

class SharedContent {
  const SharedContent({this.files = const [], this.text});
  final List<File> files;
  final String? text;
  bool get isEmpty => files.isEmpty && (text == null || text!.trim().isEmpty);
}

class AndroidShareInbox {
  static const MethodChannel _channel = MethodChannel('local_share/native');

  static Future<SharedContent> consume() async {
    if (!Platform.isAndroid) return const SharedContent();
    try {
      final raw = await _channel.invokeMapMethod<String, dynamic>(
        'consumeSharedContent',
      );
      if (raw == null) return const SharedContent();
      final paths = (raw['files'] as List?)
              ?.whereType<String>()
              .map(File.new)
              .toList(growable: false) ??
          const <File>[];
      final text = raw['text'] as String?;
      return SharedContent(files: paths, text: text);
    } catch (_) {
      return const SharedContent();
    }
  }
}
