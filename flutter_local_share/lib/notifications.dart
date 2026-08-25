import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'models.dart';

class LocalShareNotifications {
  LocalShareNotifications._();

  static final LocalShareNotifications instance = LocalShareNotifications._();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  final Set<String> _shownMessageIds = <String>{};

  ValueChanged<String>? onPeerRequested;
  String? _pendingPeerId;
  bool _initialized = false;

  Future<void> initialize() async {
    if (_initialized || (!Platform.isAndroid && !Platform.isWindows)) return;

    const android = AndroidInitializationSettings('ic_launcher');
    const windows = WindowsInitializationSettings(
      appName: 'LocalShare',
      appUserModelId: 'MographicCode.LocalShare.Desktop.1',
      guid: 'b0f62d71-ea29-4fd0-8f32-1769e0f40404',
    );

    await _plugin.initialize(
      settings: InitializationSettings(
        android: Platform.isAndroid ? android : null,
        windows: Platform.isWindows ? windows : null,
      ),
      onDidReceiveNotificationResponse: (response) {
        _handlePayload(response.payload);
      },
    );

    if (Platform.isAndroid) {
      try {
        final launch = await _plugin.getNotificationAppLaunchDetails();
        if (launch?.didNotificationLaunchApp == true) {
          _handlePayload(launch?.notificationResponse?.payload);
        }
      } catch (_) {
        // Launch details are optional; notifications still work without them.
      }
    }

    _initialized = true;
  }

  Future<void> requestPermission() async {
    if (!Platform.isAndroid) return;
    try {
      final android = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      await android?.requestNotificationsPermission();
    } catch (_) {
      // The app remains usable if the user blocks notifications.
    }
  }

  Future<void> showIncoming(ChatMessage message) async {
    if (!_initialized || !message.isIncoming) return;
    if (!_shownMessageIds.add(message.id)) return;

    final body = notificationBodyFor(message);
    final androidDetails = AndroidNotificationDetails(
      'localshare_messages',
      'رسائل LocalShare',
      channelDescription: 'تنبيهات الرسائل والروابط والملفات الواردة',
      importance: Importance.high,
      priority: Priority.high,
      category: AndroidNotificationCategory.message,
      visibility: NotificationVisibility.private,
      playSound: true,
      enableVibration: true,
      autoCancel: true,
      groupKey: 'localshare_${message.peerId}',
      styleInformation: BigTextStyleInformation(body),
    );

    final windowsDetails = WindowsNotificationDetails(
      timestamp: message.sentAt,
      subtitle: notificationSubtitleFor(message),
    );

    try {
      await _plugin.show(
        id: notificationIdFor(message.id),
        title: message.peerName,
        body: body,
        payload: 'peer:${message.peerId}',
        notificationDetails: NotificationDetails(
          android: Platform.isAndroid ? androidDetails : null,
          windows: Platform.isWindows ? windowsDetails : null,
        ),
      );
    } catch (_) {
      // A notification failure must never break message delivery.
      _shownMessageIds.remove(message.id);
    }

    if (_shownMessageIds.length > 2048) {
      _shownMessageIds.remove(_shownMessageIds.first);
    }
  }

  void attachPeerHandler(ValueChanged<String> handler) {
    onPeerRequested = handler;
    final pending = _pendingPeerId;
    if (pending != null) {
      _pendingPeerId = null;
      handler(pending);
    }
  }

  void detachPeerHandler(ValueChanged<String> handler) {
    if (onPeerRequested == handler) onPeerRequested = null;
  }

  void _handlePayload(String? payload) {
    if (payload == null || !payload.startsWith('peer:')) return;
    final peerId = payload.substring(5).trim();
    if (peerId.isEmpty) return;
    final handler = onPeerRequested;
    if (handler != null) {
      handler(peerId);
    } else {
      _pendingPeerId = peerId;
    }
  }
}

String notificationBodyFor(ChatMessage message) {
  if (message.kind == ChatMessageKind.file) {
    final name = _cleanPreview(message.fileName ?? 'ملف', maxLength: 120);
    final size = message.fileSize == null ? '' : ' • ${formatBytes(message.fileSize!)}';
    return '📎 $name$size';
  }

  if (message.kind == ChatMessageKind.link) {
    final uri = Uri.tryParse(message.text.trim());
    final host = uri?.host.isNotEmpty == true ? uri!.host : 'رابط';
    return '🔗 ${_cleanPreview(host, maxLength: 100)}';
  }

  return _cleanPreview(message.text, maxLength: 180);
}

String notificationSubtitleFor(ChatMessage message) {
  switch (message.kind) {
    case ChatMessageKind.file:
      return 'ملف جديد';
    case ChatMessageKind.link:
      return 'رابط جديد';
    case ChatMessageKind.text:
      return 'رسالة جديدة';
    case ChatMessageKind.system:
      return 'LocalShare';
  }
}

int notificationIdFor(String messageId) {
  var hash = 0x811C9DC5;
  for (final unit in messageId.codeUnits) {
    hash ^= unit;
    hash = (hash * 0x01000193) & 0x7FFFFFFF;
  }
  return hash == 0 ? 1 : hash;
}

String _cleanPreview(String value, {required int maxLength}) {
  var text = value
      .replaceAll(RegExp(r'[\x00-\x08\x0B\x0C\x0E-\x1F\x7F]'), '')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  if (text.isEmpty) return 'محتوى جديد';
  if (text.length > maxLength) {
    text = '${text.substring(0, maxLength - 1).trimRight()}…';
  }
  return text;
}
