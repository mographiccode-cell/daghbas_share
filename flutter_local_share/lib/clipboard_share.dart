import 'dart:io';

import 'package:flutter/services.dart';
import 'package:pasteboard/pasteboard.dart';
import 'package:path_provider/path_provider.dart';

class ClipboardPasteResult {
  const ClipboardPasteResult({this.files = const [], this.text});
  final List<File> files;
  final String? text;
}

class LocalShareClipboard {
  static Future<ClipboardPasteResult> read() async {
    final files = <File>[];

    try {
      final paths = await Pasteboard.files();
      for (final path in paths) {
        if (path.trim().isEmpty) continue;
        final file = File(path);
        if (await file.exists()) files.add(file);
      }
    } catch (_) {}

    if (files.isNotEmpty) return ClipboardPasteResult(files: files);

    try {
      final imageBytes = await Pasteboard.image;
      if (imageBytes != null && imageBytes.isNotEmpty) {
        final temp = await getTemporaryDirectory();
        final folder = Directory(
          '${temp.path}${Platform.pathSeparator}LocalShare${Platform.pathSeparator}clipboard',
        );
        await folder.create(recursive: true);
        final out = File(
          '${folder.path}${Platform.pathSeparator}pasted-${DateTime.now().microsecondsSinceEpoch}.png',
        );
        await out.writeAsBytes(imageBytes, flush: true);
        return ClipboardPasteResult(files: [out]);
      }
    } catch (_) {}

    try {
      final text = await Pasteboard.text;
      if (text != null && text.isNotEmpty) {
        return ClipboardPasteResult(text: text);
      }
    } catch (_) {}

    return const ClipboardPasteResult();
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
