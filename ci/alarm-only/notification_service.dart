import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import '../models/alarm.dart';
import '../models/medication.dart';
import '../models/task_reminder.dart';

class NotificationEvent {
  const NotificationEvent({
    required this.notificationId,
    required this.payload,
    this.actionId,
  });

  final int notificationId;
  final String payload;
  final String? actionId;
}

class AlarmPermissionStatus {
  const AlarmPermissionStatus({
    required this.notificationsGranted,
    required this.exactAlarmsGranted,
    required this.fullScreenGranted,
  });

  final bool notificationsGranted;
  final bool exactAlarmsGranted;
  final bool fullScreenGranted;

  bool get canScheduleAlarm => notificationsGranted && exactAlarmsGranted;
}

class AlarmSchedulingException implements Exception {
  const AlarmSchedulingException(this.code, this.message);

  final String code;
  final String message;

  @override
  String toString() => message;
}

class NotificationService {
  NotificationService._();

  static final NotificationService instance = NotificationService._();
  static const MethodChannel _audioChannel = MethodChannel('com.waqt.alarm/audio');

  final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();
  final StreamController<NotificationEvent> _events = StreamController<NotificationEvent>.broadcast();
  Stream<NotificationEvent> get events => _events.stream;

  String? _initialPayload;
  int? _initialNotificationId;
  String? _initialActionId;
  bool _initialized = false;

  Future<void> initialize() async {
    if (_initialized) return;
    tz_data.initializeTimeZones();
    await _configureLocalTimeZone();

    const AndroidInitializationSettings android = AndroidInitializationSettings('ic_stat_alarm');
    const DarwinInitializationSettings ios = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );
    const InitializationSettings settings = InitializationSettings(android: android, iOS: ios);

    await _plugin.initialize(
      settings,
      onDidReceiveNotificationResponse: _onResponse,
    );

    final NotificationAppLaunchDetails? launch = await _plugin.getNotificationAppLaunchDetails();
    final NotificationResponse? response = launch?.notificationResponse;
    if (launch?.didNotificationLaunchApp == true && response?.payload != null) {
      _initialPayload = response!.payload;
      _initialNotificationId = response.id;
      _initialActionId = response.actionId;
    }
    _initialized = true;
  }

  Future<void> _configureLocalTimeZone() async {
    try {
      final TimezoneInfo zone = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(zone.identifier));
      return;
    } catch (e) {
      if (kDebugMode) debugPrint('WAQT timezone identifier fallback: $e');
    }

    // Defensive fallback for vendor-specific timezone identifiers.
    // Etc/GMT signs are intentionally reversed by the IANA convention.
    final Duration offset = DateTime.now().timeZoneOffset;
    final int wholeHours = offset.inHours;
    if (offset.inMinutes == wholeHours * 60 && wholeHours >= -14 && wholeHours <= 14) {
      final String zoneName = wholeHours == 0
          ? 'Etc/UTC'
          : wholeHours > 0
              ? 'Etc/GMT-$wholeHours'
              : 'Etc/GMT+${wholeHours.abs()}';
      try {
        tz.setLocalLocation(tz.getLocation(zoneName));
      } catch (_) {}
    }
  }

  Future<AlarmPermissionStatus> currentAlarmPermissionStatus() async {
    await initialize();
    final AndroidFlutterLocalNotificationsPlugin? android = _plugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    if (android == null) {
      return const AlarmPermissionStatus(
        notificationsGranted: true,
        exactAlarmsGranted: true,
        fullScreenGranted: true,
      );
    }

    final bool notifications = await android.areNotificationsEnabled() ?? true;
    final bool exact = await android.canScheduleExactNotifications() ?? true;
    return AlarmPermissionStatus(
      notificationsGranted: notifications,
      exactAlarmsGranted: exact,
      fullScreenGranted: true,
    );
  }

  Future<AlarmPermissionStatus> requestPermissions({bool forAlarm = true}) async {
    await initialize();
    bool notifications = true;
    bool exact = true;
    bool fullScreen = true;

    final AndroidFlutterLocalNotificationsPlugin? android = _plugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    if (android != null) {
      notifications = await android.areNotificationsEnabled() ?? true;
      if (!notifications) {
        notifications = await android.requestNotificationsPermission() ?? false;
      }

      if (forAlarm) {
        exact = await android.canScheduleExactNotifications() ?? true;
        if (!exact) {
          try {
            await android.requestExactAlarmsPermission();
          } catch (_) {}
          exact = await android.canScheduleExactNotifications() ?? false;
        }
        try {
          fullScreen = await android.requestFullScreenIntentPermission() ?? true;
        } catch (_) {
          fullScreen = true;
        }
      }
    }

    final IOSFlutterLocalNotificationsPlugin? ios = _plugin
        .resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>();
    if (ios != null) {
      notifications = await ios.requestPermissions(alert: true, badge: true, sound: true) ?? false;
    }

    return AlarmPermissionStatus(
      notificationsGranted: notifications,
      exactAlarmsGranted: exact,
      fullScreenGranted: fullScreen,
    );
  }

  Future<AlarmPermissionStatus> ensureAlarmPermissions() => requestPermissions(forAlarm: true);

  NotificationEvent? takeInitialEvent() {
    final String? payload = _initialPayload;
    if (payload == null) return null;
    final NotificationEvent event = NotificationEvent(
      notificationId: _initialNotificationId ?? 0,
      payload: payload,
      actionId: _initialActionId,
    );
    _initialPayload = null;
    _initialNotificationId = null;
    _initialActionId = null;
    return event;
  }

  void _onResponse(NotificationResponse response) {
    final String? payload = response.payload;
    if (payload == null) return;
    _events.add(NotificationEvent(
      notificationId: response.id ?? 0,
      payload: payload,
      actionId: response.actionId,
    ));
  }

  Future<void> previewSound(String soundKey) async {
    try {
      await _audioChannel.invokeMethod<void>('previewSound', <String, Object?>{
        'soundKey': _normalizeSoundKey(soundKey),
      });
    } catch (e) {
      if (kDebugMode) debugPrint('WAQT preview sound failed: $e');
    }
  }

  Future<void> stopSoundPreview() async {
    try {
      await _audioChannel.invokeMethod<void>('stopSoundPreview');
    } catch (_) {}
  }

  Future<void> rescheduleAll({
    required List<AlarmModel> alarms,
    required List<MedicationModel> medications,
    required List<TaskReminder> tasks,
  }) async {
    await initialize();
    final List<AlarmModel> enabled = alarms
        .where((AlarmModel item) => item.enabled && item.id != null)
        .toList(growable: false);

    // Check first. Never cancel valid pending alarms and then discover that
    // Android no longer permits exact scheduling.
    if (enabled.isNotEmpty) {
      final AlarmPermissionStatus status = await currentAlarmPermissionStatus();
      if (!status.notificationsGranted) {
        throw const AlarmSchedulingException(
          'notifications_disabled',
          'إشعارات التطبيق غير مسموحة. فعّل الإشعارات حتى يعمل المنبه.',
        );
      }
      if (!status.exactAlarmsGranted) {
        throw const AlarmSchedulingException(
          'exact_alarm_disabled',
          'صلاحية المنبهات الدقيقة غير مفعلة. اسمح للتطبيق بالمنبهات والتذكيرات.',
        );
      }
    }

    await _plugin.cancelAllPendingNotifications();
    if (enabled.isEmpty) return;

    final DateTime now = DateTime.now();
    int scheduledCount = 0;

    for (final AlarmModel alarm in enabled) {
      if (alarm.daysOfWeek.isNotEmpty) {
        final List<int> weekdays = alarm.daysOfWeek.toList()..sort();
        for (int index = 0; index < weekdays.length; index++) {
          final DateTime when = _nextWeekdayTime(
            now: now,
            weekday: weekdays[index],
            minutesOfDay: alarm.minutesOfDay,
          );
          await _scheduleAlarm(
            alarm,
            when,
            index,
            matchDateTimeComponents: DateTimeComponents.dayOfWeekAndTime,
          );
          scheduledCount++;
        }
      } else {
        final DateTime? when = _nextOneTimeAlarm(alarm, now);
        if (when != null) {
          await _scheduleAlarm(alarm, when, 0);
          scheduledCount++;
        }
      }
    }

    final List<PendingNotificationRequest> pending = await _plugin.pendingNotificationRequests();
    if (pending.length < scheduledCount) {
      throw AlarmSchedulingException(
        'schedule_verification_failed',
        'فشل التحقق من جدولة المنبهات. تم تسجيل ${pending.length} من $scheduledCount فقط.',
      );
    }

    if (kDebugMode) {
      debugPrint('WAQT verified $scheduledCount exact alarm notification(s)');
    }
  }

  DateTime? _nextOneTimeAlarm(AlarmModel alarm, DateTime now) {
    final DateTime? saved = alarm.oneTimeAt;
    if (saved != null) {
      return saved.isAfter(now) ? saved : null;
    }
    DateTime candidate = DateTime(
      now.year,
      now.month,
      now.day,
      alarm.minutesOfDay ~/ 60,
      alarm.minutesOfDay % 60,
    );
    if (!candidate.isAfter(now)) candidate = candidate.add(const Duration(days: 1));
    return candidate;
  }

  DateTime _nextWeekdayTime({
    required DateTime now,
    required int weekday,
    required int minutesOfDay,
  }) {
    DateTime day = DateTime(now.year, now.month, now.day);
    final int delta = (weekday - day.weekday) % 7;
    day = day.add(Duration(days: delta));
    DateTime candidate = DateTime(
      day.year,
      day.month,
      day.day,
      minutesOfDay ~/ 60,
      minutesOfDay % 60,
    );
    if (!candidate.isAfter(now)) {
      day = day.add(const Duration(days: 7));
      candidate = DateTime(
        day.year,
        day.month,
        day.day,
        minutesOfDay ~/ 60,
        minutesOfDay % 60,
      );
    }
    return candidate;
  }

  Future<void> _scheduleAlarm(
    AlarmModel alarm,
    DateTime when,
    int index, {
    DateTimeComponents? matchDateTimeComponents,
  }) async {
    final String soundKey = _normalizeSoundKey(alarm.soundKey);
    final bool vibration = alarm.vibration;
    final String channelId = _alarmChannelId(soundKey, vibration);
    await _ensureAlarmChannel(soundKey, vibration);

    final String payload = jsonEncode(<String, Object?>{
      'type': 'alarm',
      'id': alarm.id,
      'scheduledAt': when.millisecondsSinceEpoch,
      'soundKey': soundKey,
      'vibration': vibration,
    });

    final AndroidNotificationSound? sound = _androidSound(soundKey);
    final AndroidNotificationDetails android = AndroidNotificationDetails(
      channelId,
      'منبّهات الاستيقاظ',
      channelDescription: 'تنبيهات الاستيقاظ ذات الأولوية القصوى',
      importance: Importance.max,
      priority: Priority.max,
      category: AndroidNotificationCategory.alarm,
      visibility: NotificationVisibility.public,
      fullScreenIntent: true,
      ongoing: true,
      autoCancel: false,
      playSound: true,
      sound: sound,
      enableVibration: vibration,
      audioAttributesUsage: AudioAttributesUsage.alarm,
      additionalFlags: Int32List.fromList(<int>[4]),
    );

    final tz.TZDateTime zoned = tz.TZDateTime.from(when, tz.local);
    await _plugin.zonedSchedule(
      _notificationId(alarm.id!, index),
      alarm.title.isEmpty ? 'حان وقت المنبه' : alarm.title,
      'اضغط لفتح المنبه وإيقافه',
      zoned,
      NotificationDetails(
        android: android,
        iOS: const DarwinNotificationDetails(presentSound: true),
      ),
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      payload: payload,
      matchDateTimeComponents: matchDateTimeComponents,
    );
  }

  Future<void> _ensureAlarmChannel(String soundKey, bool vibration) async {
    final AndroidFlutterLocalNotificationsPlugin? android = _plugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    if (android == null) return;

    await android.createNotificationChannel(AndroidNotificationChannel(
      _alarmChannelId(soundKey, vibration),
      'منبّهات الاستيقاظ',
      description: 'قناة منبه ${_soundLabel(soundKey)}',
      importance: Importance.max,
      playSound: true,
      sound: _androidSound(soundKey),
      enableVibration: vibration,
      audioAttributesUsage: AudioAttributesUsage.alarm,
    ));
  }

  String _alarmChannelId(String soundKey, bool vibration) {
    final String safe = _normalizeSoundKey(soundKey).replaceAll('waqt_', '');
    return 'waqt_alarm_${safe}_${vibration ? 'vib' : 'novib'}_v3';
  }

  String _normalizeSoundKey(String value) {
    switch (value) {
      case 'waqt_soft':
      case 'waqt_digital':
      case 'system':
      case 'waqt_classic':
        return value;
      default:
        return 'waqt_classic';
    }
  }

  AndroidNotificationSound? _androidSound(String soundKey) {
    switch (_normalizeSoundKey(soundKey)) {
      case 'waqt_soft':
        return const RawResourceAndroidNotificationSound('waqt_soft');
      case 'waqt_digital':
        return const RawResourceAndroidNotificationSound('waqt_digital');
      case 'waqt_classic':
        return const RawResourceAndroidNotificationSound('waqt_classic');
      case 'system':
        return null;
    }
    return const RawResourceAndroidNotificationSound('waqt_classic');
  }

  String _soundLabel(String soundKey) {
    switch (_normalizeSoundKey(soundKey)) {
      case 'waqt_soft':
        return 'هادئة';
      case 'waqt_digital':
        return 'رقمية';
      case 'system':
        return 'النظام';
      default:
        return 'كلاسيكية';
    }
  }

  Future<void> snooze({
    required int currentNotificationId,
    required String payload,
    required Duration duration,
    required String title,
    required String body,
    required bool alarm,
  }) async {
    await _plugin.cancel(currentNotificationId);
    if (!alarm) return;

    String soundKey = 'waqt_classic';
    bool vibration = true;
    int alarmId = 0;
    try {
      final Map<String, dynamic> data = jsonDecode(payload) as Map<String, dynamic>;
      soundKey = (data['soundKey'] as String?) ?? soundKey;
      vibration = (data['vibration'] as bool?) ?? true;
      alarmId = (data['id'] as int?) ?? 0;
    } catch (_) {}

    final AlarmPermissionStatus status = await currentAlarmPermissionStatus();
    if (!status.canScheduleAlarm) {
      throw const AlarmSchedulingException(
        'alarm_permission_revoked',
        'لا يمكن تفعيل الغفوة لأن صلاحية المنبهات غير متاحة.',
      );
    }

    final DateTime when = DateTime.now().add(duration);
    final String normalized = _normalizeSoundKey(soundKey);
    await _ensureAlarmChannel(normalized, vibration);
    final String channelId = _alarmChannelId(normalized, vibration);
    final AndroidNotificationDetails android = AndroidNotificationDetails(
      channelId,
      'منبّهات الاستيقاظ',
      importance: Importance.max,
      priority: Priority.max,
      category: AndroidNotificationCategory.alarm,
      fullScreenIntent: true,
      ongoing: true,
      autoCancel: false,
      playSound: true,
      sound: _androidSound(normalized),
      enableVibration: vibration,
      audioAttributesUsage: AudioAttributesUsage.alarm,
      additionalFlags: Int32List.fromList(<int>[4]),
    );
    final String snoozePayload = jsonEncode(<String, Object?>{
      'type': 'alarm',
      'id': alarmId,
      'scheduledAt': when.millisecondsSinceEpoch,
      'soundKey': normalized,
      'vibration': vibration,
    });
    await _plugin.zonedSchedule(
      400000000 + DateTime.now().millisecondsSinceEpoch.remainder(100000000),
      title,
      body,
      tz.TZDateTime.from(when, tz.local),
      NotificationDetails(android: android, iOS: const DarwinNotificationDetails()),
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      payload: snoozePayload,
    );
  }

  Future<void> cancel(int id) => _plugin.cancel(id);

  int _notificationId(int entityId, int index) {
    return 100000000 + (entityId.remainder(90000) * 1000) + index.remainder(1000);
  }
}
