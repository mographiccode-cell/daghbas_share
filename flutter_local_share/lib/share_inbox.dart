import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class ExternalShareItem {
  const ExternalShareItem({
    required this.kind,
    this.text,
    this.uri,
    this.name,
  });

  final String kind;
  final String? text;
  final String? uri;
  final String? name;

  bool get isText => kind == 'text' && text != null && text!.isNotEmpty;
  bool get isUri => kind == 'uri' && uri != null && uri!.isNotEmpty;

  factory ExternalShareItem.fromDynamic(Object? raw) {
    final map = raw is Map ? raw : const <Object?, Object?>{};
    return ExternalShareItem(
      kind: '${map['kind'] ?? ''}',
      text: map['text']?.toString(),
      uri: map['uri']?.toString(),
      name: map['name']?.toString(),
    );
  }
}

class LocalShareShareInbox {
  LocalShareShareInbox._();

  static final LocalShareShareInbox instance = LocalShareShareInbox._();
  static const MethodChannel _channel = MethodChannel('local_share/native');

  ValueChanged<List<ExternalShareItem>>? _handler;
  final List<ExternalShareItem> _buffer = <ExternalShareItem>[];
  bool _initialized = false;
  bool _consuming = false;

  Future<void> attach(ValueChanged<List<ExternalShareItem>> handler) async {
    _handler = handler;
    if (!_initialized && Platform.isAndroid) {
      _channel.setMethodCallHandler((call) async {
        if (call.method == 'sharedItemsAvailable') {
          await consume();
        }
      });
      _initialized = true;
    }
    if (_buffer.isNotEmpty) {
      final pending = List<ExternalShareItem>.from(_buffer);
      _buffer.clear();
      handler(pending);
    }
    await consume();
  }

  void detach(ValueChanged<List<ExternalShareItem>> handler) {
    if (_handler == handler) _handler = null;
  }

  Future<void> consume() async {
    if (!Platform.isAndroid || _consuming) return;
    _consuming = true;
    try {
      final raw = await _channel.invokeMethod<List<dynamic>>('consumeSharedItems');
      if (raw == null || raw.isEmpty) return;
      final items = raw
          .map(ExternalShareItem.fromDynamic)
          .where((item) => item.isText || item.isUri)
          .take(20)
          .toList(growable: false);
      if (items.isEmpty) return;
      final handler = _handler;
      if (handler != null) {
        handler(items);
      } else {
        _buffer.addAll(items);
      }
    } on MissingPluginException {
      // Not running on the Android host override.
    } finally {
      _consuming = false;
    }
  }

  Future<File> materialize(ExternalShareItem item) async {
    if (!Platform.isAndroid || !item.isUri) {
      throw const FileSystemException('عنصر المشاركة ليس ملفًا صالحًا');
    }
    final path = await _channel.invokeMethod<String>('materializeSharedUri', {
      'uri': item.uri,
      'name': item.name,
    });
    if (path == null || path.isEmpty) {
      throw const FileSystemException('تعذر تجهيز الملف المشترك للإرسال');
    }
    final file = File(path);
    if (!await file.exists()) {
      throw const FileSystemException('الملف المشترك لم يعد متاحًا');
    }
    return file;
  }
}
