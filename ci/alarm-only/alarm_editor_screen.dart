import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_colors.dart';
import '../../core/utils/time_utils.dart';
import '../../models/alarm.dart';
import '../../state/app_state.dart';
import '../../widgets/weekday_selector.dart';

class AlarmEditorScreen extends StatefulWidget {
  const AlarmEditorScreen({super.key, this.existing});

  final AlarmModel? existing;

  @override
  State<AlarmEditorScreen> createState() => _AlarmEditorScreenState();
}

class _AlarmEditorScreenState extends State<AlarmEditorScreen> {
  late final TextEditingController _title;
  late int _minutes;
  late List<int> _days;
  late int _snooze;
  late bool _vibration;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final AlarmModel? alarm = widget.existing;
    _title = TextEditingController(text: alarm?.title ?? '');
    _minutes = alarm?.minutesOfDay ?? _defaultTime();
    _days = List<int>.from(alarm?.daysOfWeek ?? <int>[]);
    _snooze = alarm?.snoozeMinutes ?? 5;
    _vibration = alarm?.vibration ?? true;
  }

  int _defaultTime() {
    final DateTime now = DateTime.now().add(const Duration(minutes: 5));
    return now.hour * 60 + now.minute;
  }

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  Future<void> _pickTime() async {
    final TimeOfDay? result = await showTimePicker(
      context: context,
      initialTime: minutesToTime(_minutes),
      helpText: 'ضبط وقت المنبّه',
      cancelText: 'إلغاء',
      confirmText: 'تم',
    );
    if (result != null) setState(() => _minutes = timeToMinutes(result));
  }

  DateTime _nextOccurrence() {
    final DateTime now = DateTime.now();
    if (_days.isEmpty) {
      DateTime when = dateAtMinutes(now, _minutes);
      if (!when.isAfter(now)) when = when.add(const Duration(days: 1));
      return when;
    }
    DateTime? best;
    for (final int weekday in _days) {
      final int delta = (weekday - now.weekday) % 7;
      final DateTime day = now.add(Duration(days: delta));
      DateTime when = DateTime(day.year, day.month, day.day, _minutes ~/ 60, _minutes % 60);
      if (!when.isAfter(now)) when = when.add(const Duration(days: 7));
      if (best == null || when.isBefore(best)) best = when;
    }
    return best!;
  }

  String _remainingText() {
    final Duration d = _nextOccurrence().difference(DateTime.now());
    final int days = d.inDays;
    final int hours = d.inHours.remainder(24);
    final int minutes = d.inMinutes.remainder(60);
    if (days > 0) return 'سيرن بعد $days يوم و $hours ساعة';
    if (hours > 0) return 'سيرن بعد $hours ساعة و $minutes دقيقة';
    return 'سيرن بعد ${d.inMinutes.clamp(1, 999)} دقيقة';
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    final DateTime? oneTimeAt = _days.isEmpty ? _nextOccurrence() : null;
    final AlarmModel alarm = AlarmModel(
      id: widget.existing?.id,
      title: _title.text.trim(),
      minutesOfDay: _minutes,
      daysOfWeek: _days,
      enabled: widget.existing?.enabled ?? true,
      snoozeMinutes: _snooze,
      mission: AlarmMission.none,
      missionTarget: 3,
      gradualVolume: false,
      vibration: _vibration,
      oneTimeAt: oneTimeAt,
    );
    await context.read<AppState>().saveAlarm(alarm);
    if (!mounted) return;
    final String message = _remainingText();
    Navigator.pop(context);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('تم ضبط المنبّه • $message')));
  }

  Future<void> _delete() async {
    final int? id = widget.existing?.id;
    if (id == null) return;
    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: const Text('حذف المنبّه؟'),
        actions: <Widget>[
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('إلغاء')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('حذف')),
        ],
      ),
    );
    if (confirm == true && mounted) {
      await context.read<AppState>().deleteAlarm(id);
      if (mounted) Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close_rounded)),
        title: Text(widget.existing == null ? 'إضافة منبّه' : 'تعديل المنبّه'),
        actions: <Widget>[
          TextButton(onPressed: _saving ? null : _save, child: const Text('حفظ')),
          const SizedBox(width: 6),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(18, 8, 18, 34),
        children: <Widget>[
          InkWell(
            borderRadius: BorderRadius.circular(28),
            onTap: _pickTime,
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 16),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainer,
                borderRadius: BorderRadius.circular(28),
              ),
              child: Column(
                children: <Widget>[
                  Text(
                    formatMinutes(context, _minutes),
                    style: Theme.of(context).textTheme.displayLarge?.copyWith(fontWeight: FontWeight.w500),
                  ),
                  const SizedBox(height: 8),
                  Text(_remainingText(), style: Theme.of(context).textTheme.bodyMedium),
                ],
              ),
            ),
          ),
          const SizedBox(height: 22),
          Text('التكرار', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 10),
          WeekdaySelector(selected: _days, onChanged: (List<int> value) => setState(() => _days = value)),
          const SizedBox(height: 20),
          _SettingCard(
            child: TextField(
              controller: _title,
              decoration: const InputDecoration(
                border: InputBorder.none,
                labelText: 'اسم المنبّه',
                hintText: 'منبّه',
                prefixIcon: Icon(Icons.label_outline_rounded),
              ),
            ),
          ),
          const SizedBox(height: 10),
          _SettingCard(
            child: SwitchListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 16),
              value: _vibration,
              onChanged: (bool value) => setState(() => _vibration = value),
              title: const Text('اهتزاز'),
              secondary: const Icon(Icons.vibration_rounded, color: AppColors.purple),
            ),
          ),
          const SizedBox(height: 10),
          _SettingCard(
            child: ListTile(
              leading: const Icon(Icons.snooze_rounded, color: AppColors.purple),
              title: const Text('الغفوة'),
              subtitle: Text('$_snooze دقائق'),
              trailing: DropdownButton<int>(
                value: _snooze,
                underline: const SizedBox.shrink(),
                items: <int>[3, 5, 10, 15]
                    .map((int value) => DropdownMenuItem<int>(value: value, child: Text('$value د')))
                    .toList(),
                onChanged: (int? value) => value == null ? null : setState(() => _snooze = value),
              ),
            ),
          ),
          if (widget.existing != null) ...<Widget>[
            const SizedBox(height: 24),
            TextButton.icon(
              onPressed: _delete,
              icon: const Icon(Icons.delete_outline_rounded),
              label: const Text('حذف المنبّه'),
              style: TextButton.styleFrom(foregroundColor: Theme.of(context).colorScheme.error),
            ),
          ],
        ],
      ),
    );
  }
}

class _SettingCard extends StatelessWidget {
  const _SettingCard({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Theme.of(context).colorScheme.surfaceContainer,
      borderRadius: BorderRadius.circular(22),
      child: ClipRRect(borderRadius: BorderRadius.circular(22), child: child),
    );
  }
}
