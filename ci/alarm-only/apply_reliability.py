from pathlib import Path

# ----- app.dart: request alarm permissions, wait for state load, then reschedule -----
p = Path('app/lib/app.dart')
s = p.read_text()
old = '''    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await NotificationService.instance.requestPermissions();
    });'''
new = '''    WidgetsBinding.instance.addPostFrameCallback((_) => _prepareAlarmSystem());'''
if old not in s:
    raise SystemExit('app permission block not found')
s = s.replace(old, new, 1)

anchor = '''  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }
'''
insert = '''  Future<void> _prepareAlarmSystem() async {
    final AlarmPermissionStatus status =
        await NotificationService.instance.requestPermissions(forAlarm: true);
    if (!mounted) return;

    final AppState state = context.read<AppState>();
    while (state.loading && mounted) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    if (!mounted) return;

    if (!status.canScheduleAlarm) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('فعّل الإشعارات وصلاحية المنبهات والتذكيرات حتى يعمل المنبه بدقة.'),
        duration: Duration(seconds: 5),
      ));
      return;
    }

    try {
      await state.rescheduleAlarms();
    } on AlarmSchedulingException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

'''
if anchor not in s:
    raise SystemExit('app dispose anchor not found')
s = s.replace(anchor, insert + anchor, 1)
p.write_text(s)

# ----- editor: ringtone preview and permission gate -----
p = Path('app/lib/screens/alarms/alarm_editor_screen.dart')
s = p.read_text()
old = "import '../../models/alarm.dart';\nimport '../../state/app_state.dart';"
new = "import '../../models/alarm.dart';\nimport '../../services/notification_service.dart';\nimport '../../state/app_state.dart';"
if old not in s:
    raise SystemExit('editor imports not found')
s = s.replace(old, new, 1)

old = '''  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }'''
new = '''  @override
  void dispose() {
    NotificationService.instance.stopSoundPreview();
    _title.dispose();
    super.dispose();
  }'''
if old not in s:
    raise SystemExit('editor dispose not found')
s = s.replace(old, new, 1)

start = s.index('  Future<void> _chooseSound() async {')
end = s.index('  Future<void> _chooseSnooze() async {', start)
new_choose = '''  Future<void> _chooseSound() async {
    String temporary = _soundKey;
    final String? selected = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (BuildContext sheetContext) {
        const List<String> keys = <String>['waqt_classic', 'waqt_soft', 'waqt_digital', 'system'];
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setSheetState) {
            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Padding(
                      padding: const EdgeInsets.fromLTRB(14, 2, 14, 4),
                      child: Row(
                        children: <Widget>[
                          Expanded(
                            child: Text(
                              'صوت المنبه',
                              style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
                            ),
                          ),
                          TextButton(
                            onPressed: () => Navigator.pop(sheetContext, temporary),
                            child: const Text('تم'),
                          ),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
                      child: Align(
                        alignment: Alignment.centerRight,
                        child: Text(
                          'اضغط على أي نغمة لسماعها قبل الاختيار',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: Theme.of(context).colorScheme.onSurface.withValues(alpha: .55),
                              ),
                        ),
                      ),
                    ),
                    for (final String key in keys)
                      ListTile(
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        leading: Icon(
                          temporary == key ? Icons.volume_up_rounded : Icons.music_note_rounded,
                          color: temporary == key ? _samsungBlue : null,
                        ),
                        title: Text(_soundLabel(key)),
                        trailing: temporary == key
                            ? const Icon(Icons.check_circle_rounded, color: _samsungBlue)
                            : const Icon(Icons.play_circle_outline_rounded),
                        onTap: () async {
                          setSheetState(() => temporary = key);
                          await NotificationService.instance.previewSound(key);
                        },
                      ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
    await NotificationService.instance.stopSoundPreview();
    if (selected != null && mounted) setState(() => _soundKey = selected);
  }

'''
s = s[:start] + new_choose + s[end:]

needle = '''    setState(() => _saving = true);
    final AlarmModel alarm = AlarmModel('''
replacement = '''    final AlarmPermissionStatus permission =
        await NotificationService.instance.ensureAlarmPermissions();
    if (!mounted) return;
    if (!permission.canScheduleAlarm) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('لا يمكن حفظ منبه غير مضمون. فعّل الإشعارات ثم اسمح بالمنبهات والتذكيرات.'),
        duration: Duration(seconds: 5),
      ));
      return;
    }

    await NotificationService.instance.stopSoundPreview();
    setState(() => _saving = true);
    final AlarmModel alarm = AlarmModel('''
if needle not in s:
    raise SystemExit('editor save permission anchor not found')
s = s.replace(needle, replacement, 1)

old = '''    await context.read<AppState>().saveAlarm(alarm);
    if (!mounted) return;
    final String message = _remainingText();
    Navigator.pop(context);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('تم ضبط المنبه • $message')),
    );'''
new = '''    try {
      await context.read<AppState>().saveAlarm(alarm);
    } on AlarmSchedulingException catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(e.message),
        duration: const Duration(seconds: 5),
      ));
      return;
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('تعذر جدولة المنبه. حاول مرة أخرى بعد التحقق من صلاحيات التطبيق.'),
      ));
      return;
    }
    if (!mounted) return;
    final String message = _remainingText();
    Navigator.pop(context);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('تم ضبط المنبه والتحقق من جدولته • $message')),
    );'''
if old not in s:
    raise SystemExit('editor save scheduling block not found')
s = s.replace(old, new, 1)
p.write_text(s)

# ----- list: when re-enabling an alarm, require permissions first -----
p = Path('app/lib/screens/alarms/alarms_screen.dart')
s = p.read_text()
old = "import '../../models/alarm.dart';\nimport '../../state/app_state.dart';"
new = "import '../../models/alarm.dart';\nimport '../../services/notification_service.dart';\nimport '../../state/app_state.dart';"
if old not in s:
    raise SystemExit('alarms screen imports not found')
s = s.replace(old, new, 1)

old = '''              Switch(
                value: alarm.enabled,
                onChanged: (bool value) => state.toggleAlarm(alarm, value),
              ),'''
new = '''              Switch(
                value: alarm.enabled,
                onChanged: (bool value) async {
                  if (value) {
                    final AlarmPermissionStatus permission =
                        await NotificationService.instance.ensureAlarmPermissions();
                    if (!context.mounted) return;
                    if (!permission.canScheduleAlarm) {
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                        content: Text('فعّل الإشعارات وصلاحية المنبهات قبل تشغيل المنبه.'),
                      ));
                      return;
                    }
                  }
                  try {
                    await state.toggleAlarm(alarm, value);
                  } on AlarmSchedulingException catch (e) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
                    }
                  }
                },
              ),'''
if old not in s:
    raise SystemExit('alarm switch block not found')
s = s.replace(old, new, 1)
p.write_text(s)

print('WAQT reliability patches applied')
