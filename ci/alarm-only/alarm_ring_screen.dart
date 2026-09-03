import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/utils/time_utils.dart';
import '../models/alarm.dart';
import '../services/notification_service.dart';
import '../state/app_state.dart';

class AlarmRingScreen extends StatefulWidget {
  const AlarmRingScreen({
    super.key,
    required this.alarmId,
    required this.notificationId,
  });

  final int alarmId;
  final int notificationId;

  @override
  State<AlarmRingScreen> createState() => _AlarmRingScreenState();
}

class _AlarmRingScreenState extends State<AlarmRingScreen> {
  Timer? _clockTimer;
  DateTime _now = DateTime.now();
  bool _working = false;

  AlarmModel? get _alarm => context.read<AppState>().alarmById(widget.alarmId);

  @override
  void initState() {
    super.initState();
    _clockTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _now = DateTime.now());
    });
  }

  Future<void> _dismiss() async {
    if (_working) return;
    setState(() => _working = true);
    await NotificationService.instance.cancel(widget.notificationId);
    final AlarmModel? alarm = _alarm;
    if (alarm != null && alarm.daysOfWeek.isEmpty && alarm.enabled) {
      await context.read<AppState>().toggleAlarm(alarm, false);
    }
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _snooze() async {
    if (_working) return;
    setState(() => _working = true);
    final AlarmModel? alarm = _alarm;
    final int minutes = alarm?.snoozeMinutes ?? 5;
    final String payload = jsonEncode(<String, Object?>{
      'type': 'alarm',
      'id': widget.alarmId,
      'scheduledAt': DateTime.now().add(Duration(minutes: minutes)).millisecondsSinceEpoch,
    });
    await NotificationService.instance.snooze(
      currentNotificationId: widget.notificationId,
      payload: payload,
      duration: Duration(minutes: minutes),
      title: alarm?.title.trim().isEmpty ?? true ? 'منبه' : alarm!.title.trim(),
      body: 'انتهت الغفوة.',
      alarm: true,
    );
    if (mounted) Navigator.of(context).pop();
  }

  @override
  void dispose() {
    _clockTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final AlarmModel? alarm = context.watch<AppState>().alarmById(widget.alarmId);
    final String title = alarm == null || alarm.title.trim().isEmpty ? 'منبه' : alarm.title.trim();
    final int snooze = alarm?.snoozeMinutes ?? 5;

    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: const Color(0xFF0B0B0D),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 28, 24, 26),
            child: Column(
              children: <Widget>[
                Text(
                  formatShortDate(_now),
                  style: const TextStyle(
                    color: Color(0xFFA7A7AD),
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const Spacer(flex: 2),
                Text(
                  formatClock(_now),
                  textDirection: TextDirection.ltr,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 82,
                    height: 1,
                    fontWeight: FontWeight.w300,
                    letterSpacing: -3,
                  ),
                ),
                const SizedBox(height: 18),
                Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Color(0xFFE8E8EC),
                    fontSize: 20,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const Spacer(flex: 3),
                GestureDetector(
                  onTap: _working ? null : _dismiss,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 160),
                    width: 128,
                    height: 128,
                    decoration: BoxDecoration(
                      color: _working ? const Color(0xFF3A3A3F) : const Color(0xFFF2F2F4),
                      shape: BoxShape.circle,
                    ),
                    child: const Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: <Widget>[
                        Icon(Icons.alarm_off_rounded, color: Color(0xFF17171A), size: 34),
                        SizedBox(height: 7),
                        Text(
                          'إيقاف',
                          style: TextStyle(
                            color: Color(0xFF17171A),
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const Spacer(flex: 2),
                SizedBox(
                  width: double.infinity,
                  height: 58,
                  child: FilledButton(
                    onPressed: _working ? null : _snooze,
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF242428),
                      foregroundColor: Colors.white,
                      disabledBackgroundColor: const Color(0xFF242428),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(29)),
                    ),
                    child: Text(
                      'غفوة $snooze دقائق',
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
