import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:path_provider/path_provider.dart';
import 'package:super_clipboard/super_clipboard.dart';

import 'local_share_service.dart';
import 'models.dart';

class ChatPasteResult {
  const ChatPasteResult({required this.handled, this.filesSent = 0});

  final bool handled;
  final int filesSent;
}

Future<ChatPasteResult> pasteClipboardIntoChat({
  required LocalShareService service,
  required Peer peer,
  required TextEditingController controller,
}) async {
  final clipboard = SystemClipboard.instance;
  if (clipboard == null) return const ChatPasteResult(handled: false);

  final reader = await clipboard.read();
  var filesSent = 0;

  // Explorer and other file managers expose copied files as one clipboard item
  // per file URI. Send the original file rather than converting image files.
  for (final item in reader.items.take(50)) {
    if (!item.canProvide(Formats.fileUri)) continue;
    final uri = await item.readValue(Formats.fileUri);
    if (uri == null || !uri.isScheme('file')) continue;
    final file = File(uri.toFilePath(windows: Platform.isWindows));
    if (!await file.exists()) continue;
    await service.sendFile(peer, file);
    filesSent++;
  }
  if (filesSent > 0) {
    return ChatPasteResult(handled: true, filesSent: filesSent);
  }

  // Screenshots and copied bitmap content are exposed as PNG by
  // super_clipboard on Windows. Stream to a temporary file to avoid loading
  // large clipboard images into Dart memory.
  for (var index = 0; index < reader.items.length && index < 20; index++) {
    final item = reader.items[index];
    if (!item.canProvide(Formats.png)) continue;
    final image = await _materializeClipboardPng(item, index);
    if (image == null) continue;
    try {
      await service.sendFile(peer, image);
      filesSent++;
    } finally {
      try {
        if (await image.exists()) await image.delete();
      } catch (_) {}
    }
  }
  if (filesSent > 0) {
    return ChatPasteResult(handled: true, filesSent: filesSent);
  }

  if (reader.canProvide(Formats.plainText)) {
    final text = await reader.readValue(Formats.plainText);
    if (text != null && text.isNotEmpty) {
      _insertText(controller, text);
      return const ChatPasteResult(handled: true);
    }
  }

  return const ChatPasteResult(handled: false);
}

Future<File?> _materializeClipboardPng(
  ClipboardDataReader item,
  int index,
) async {
  final completer = Completer<File?>();
  final progress = item.getFile(
    Formats.png,
    (data) async {
      IOSink? sink;
      File? destination;
      try {
        final temp = await getTemporaryDirectory();
        final folder = Directory(
          '${temp.path}${Platform.pathSeparator}LocalShare${Platform.pathSeparator}clipboard',
        );
        await folder.create(recursive: true);
        final suggested = safeFileName(data.fileName ?? 'pasted-image.png');
        final name = suggested.toLowerCase().endsWith('.png')
            ? suggested
            : '$suggested.png';
        destination = File(
          '${folder.path}${Platform.pathSeparator}${DateTime.now().microsecondsSinceEpoch}-$index-$name',
        );
        sink = destination.openWrite();
        var written = 0;
        await for (final chunk in data.getStream()) {
          written += chunk.length;
          if (written > 1024 * 1024 * 1024) {
            throw const FileSystemException(
              'صورة الحافظة أكبر من الحد الآمن البالغ 1 GB',
            );
          }
          sink.add(chunk);
        }
        await sink.flush();
        await sink.close();
        sink = null;
        if (!completer.isCompleted) completer.complete(destination);
      } catch (e, st) {
        try {
          await sink?.close();
        } catch (_) {}
        try {
          if (destination != null && await destination.exists()) {
            await destination.delete();
          }
        } catch (_) {}
        if (!completer.isCompleted) completer.completeError(e, st);
      }
    },
    onError: (error) {
      if (!completer.isCompleted) completer.completeError(error);
    },
  );
  if (progress == null) return null;
  return completer.future.timeout(const Duration(seconds: 30));
}

void _insertText(TextEditingController controller, String raw) {
  final current = controller.value;
  final selection = current.selection;
  final start = selection.isValid ? selection.start : current.text.length;
  final end = selection.isValid ? selection.end : current.text.length;
  final safeStart = start.clamp(0, current.text.length);
  final safeEnd = end.clamp(safeStart, current.text.length);
  final available = 4096 - (current.text.length - (safeEnd - safeStart));
  if (available <= 0) return;
  final inserted = raw.length > available ? raw.substring(0, available) : raw;
  final updated = current.text.replaceRange(safeStart, safeEnd, inserted);
  final cursor = safeStart + inserted.length;
  controller.value = TextEditingValue(
    text: updated,
    selection: TextSelection.collapsed(offset: cursor),
  );
}
