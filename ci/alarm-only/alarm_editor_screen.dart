import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/alarm.dart';
import '../../state/app_state.dart';

class AlarmEditorScreen extends StatefulWidget {
  const AlarmEditorScreen({super.key, this.existing});

  final AlarmModel? existing;

  @override
  State<AlarmEditorScreen> createState() => _AlarmEditorScreenState();
}

class _AlarmEditorScreenState extends State<AlarmEditorScreen> {
  static const Color _samsungBlue = Color(0xFF3B7CFF);
  static const List<int> _weekOrder = <int>[6, 7, 1, 2, 3, 4, 5];
  static const List<String> _weekLabels = <String>['س', 'ح', 'ن', 'ث', 'ر', 'خ', 'ج'];

  late final TextEditingController _title;
  late int _minutes;
  late List<int> _days;
  late int _snooze;
  late bool _vibration;
  late String _soundKey;
  DateTime? _selectedDate;
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
    _soundKey = alarm?.soundKey ?? 'waqt_classic';
    if (_days.isEmpty && alarm?.oneTimeAt != null) {
      final DateTime value = alarm!.oneTimeAt!;
      _selectedDate = DateTime(value.year, value.month, value.day);
    }
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

  DateTime _nextOccurrence() {
    final DateTime now = DateTime.now();
    if (_days.isEmpty) {
      if (_selectedDate != null) {
        return DateTime(
          _selectedDate!.year,
          _selectedDate!.month,
          _selectedDate!.day,
          _minutes ~/ 60,
          _minutes % 60,
        );
      }
      DateTime when = DateTime(now.year, now.month, now.day, _minutes ~/ 60, _minutes % 60);
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
    if (d.isNegative) return 'الوقت المحدد مضى';
    final int days = d.inDays;
    final int hours = d.inHours.remainder(24);
    final int minutes = d.inMinutes.remainder(60);
    if (days > 0) return 'بعد $days يوم و $hours ساعة';
    if (hours > 0) return 'بعد $hours ساعة و $minutes دقيقة';
    return 'بعد ${d.inMinutes.clamp(1, 999)} دقيقة';
  }

  String _dateText(BuildContext context) {
    if (_selectedDate == null) return 'مرة واحدة في أقرب وقت';
    return MaterialLocalizations.of(context).formatMediumDate(_selectedDate!);
  }

  String _soundLabel(String key) {
    switch (key) {
      case 'waqt_soft':
        return 'هادئة';
      case 'waqt_digital':
        return 'رقمية';
      case 'system':
        return 'نغمة النظام';
      case 'waqt_classic':
      default:
        return 'كلاسيكية';
    }
  }

  Future<void> _pickDate() async {
    final DateTime now = DateTime.now();
    final DateTime today = DateTime(now.year, now.month, now.day);
    DateTime initial = _selectedDate ?? today;
    if (initial.isBefore(today)) initial = today;
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: today,
      lastDate: DateTime(today.year + 3, today.month, today.day),
      helpText: 'تحديد تاريخ المنبه',
      cancelText: 'إلغاء',
      confirmText: 'تم',
    );
    if (picked == null) return;
    setState(() {
      _selectedDate = DateTime(picked.year, picked.month, picked.day);
      _days = <int>[];
    });
  }

  Future<void> _chooseSound() async {
    final String? selected = await showModalBottomSheet<String>(
      context: context,
      builder: (BuildContext sheetContext) {
        const List<String> keys = <String>['waqt_classic', 'waqt_soft', 'waqt_digital', 'system'];
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 14),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 2, 18, 12),
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: Text(
                      'صوت المنبه',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
                for (final String key in keys)
                  RadioListTile<String>(
                    value: key,
                    groupValue: _soundKey,
                    title: Text(_soundLabel(key)),
                    activeColor: _samsungBlue,
                    onChanged: (String? value) => Navigator.pop(sheetContext, value),
                  ),
              ],
            ),
          ),
        );
      },
    );
    if (selected != null) setState(() => _soundKey = selected);
  }

  Future<void> _chooseSnooze() async {
    final int? selected = await showModalBottomSheet<int>(
      context: context,
      builder: (BuildContext sheetContext) {
        const List<int> values = <int>[3, 5, 10, 15];
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 14),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 2, 18, 12),
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: Text(
                      'الغفوة',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
                for (final int value in values)
                  RadioListTile<int>(
                    value: value,
                    groupValue: _snooze,
                    title: Text('$value دقائق'),
                    activeColor: _samsungBlue,
                    onChanged: (int? result) => Navigator.pop(sheetContext, result),
                  ),
              ],
            ),
          ),
        );
      },
    );
    if (selected != null) setState(() => _snooze = selected);
  }

  Future<void> _save() async {
    if (_saving) return;
    final DateTime next = _nextOccurrence();
    if (!next.isAfter(DateTime.now())) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('اختر وقتًا أو تاريخًا في المستقبل.')),
      );
      return;
    }

    setState(() => _saving = true);
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
      oneTimeAt: _days.isEmpty ? next : null,
      soundKey: _soundKey,
    );
    await context.read<AppState>().saveAlarm(alarm);
    if (!mounted) return;
    final String message = _remainingText();
    Navigator.pop(context);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('تم ضبط المنبه • $message')),
    );
  }

  Future<void> _delete() async {
    final int? id = widget.existing?.id;
    if (id == null) return;
    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: const Text('حذف المنبه؟'),
        actions: <Widget>[
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('إلغاء')),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: TextButton.styleFrom(foregroundColor: Theme.of(context).colorScheme.error),
            child: const Text('حذف'),
          ),
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
    final ColorScheme colors = Theme.of(context).colorScheme;
    final int hour = _minutes ~/ 60;
    final int minute = _minutes % 60;

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
              child: Row(
                children: <Widget>[
                  IconButton(
                    tooltip: 'إلغاء',
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded),
                  ),
                  Expanded(
                    child: Text(
                      widget.existing == null ? 'إضافة منبه' : 'تعديل المنبه',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
                    ),
                  ),
                  TextButton(
                    onPressed: _saving ? null : _save,
                    child: const Text('حفظ', style: TextStyle(fontWeight: FontWeight.w700)),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 6, 16, 30),
                children: <Widget>[
                  Container(
                    height: 220,
                    decoration: BoxDecoration(
                      color: colors.surface,
                      borderRadius: BorderRadius.circular(30),
                    ),
                    child: Column(
                      children: <Widget>[
                        Expanded(
                          child: Directionality(
                            textDirection: TextDirection.ltr,
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: <Widget>[
                                _NumberWheel(
                                  value: hour,
                                  count: 24,
                                  formatter: (int value) => value.toString().padLeft(2, '0'),
                                  onChanged: (int value) => setState(() => _minutes = value * 60 + minute),
                                ),
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 4),
                                  child: Text(
                                    ':',
                                    style: Theme.of(context).textTheme.displayMedium?.copyWith(
                                          fontSize: 46,
                                          fontWeight: FontWeight.w400,
                                        ),
                                  ),
                                ),
                                _NumberWheel(
                                  value: minute,
                                  count: 60,
                                  formatter: (int value) => value.toString().padLeft(2, '0'),
                                  onChanged: (int value) => setState(() => _minutes = hour * 60 + value),
                                ),
                              ],
                            ),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.only(bottom: 16),
                          child: Text(
                            _remainingText(),
                            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                  color: colors.onSurface.withValues(alpha: .55),
                                ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),
                  _RepeatCard(
                    selected: _days,
                    onToggle: (int day) {
                      setState(() {
                        _selectedDate = null;
                        if (_days.contains(day)) {
                          _days = List<int>.from(_days)..remove(day);
                        } else {
                          _days = List<int>.from(_days)..add(day);
                        }
                      });
                    },
                  ),
                  const SizedBox(height: 12),
                  _SettingsGroup(
                    children: <Widget>[
                      ListTile(
                        leading: const Icon(Icons.calendar_month_outlined),
                        title: const Text('التاريخ'),
                        subtitle: Text(_dateText(context)),
                        trailing: const Icon(Icons.chevron_left_rounded),
                        onTap: _pickDate,
                      ),
                      const Divider(height: 1, indent: 56),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: TextField(
                          controller: _title,
                          maxLength: 40,
                          decoration: const InputDecoration(
                            counterText: '',
                            filled: false,
                            border: InputBorder.none,
                            enabledBorder: InputBorder.none,
                            focusedBorder: InputBorder.none,
                            prefixIcon: Icon(Icons.label_outline_rounded),
                            labelText: 'اسم المنبه',
                            hintText: 'منبه',
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _SettingsGroup(
                    children: <Widget>[
                      ListTile(
                        leading: const Icon(Icons.music_note_rounded),
                        title: const Text('صوت المنبه'),
                        subtitle: Text(_soundLabel(_soundKey)),
                        trailing: const Icon(Icons.chevron_left_rounded),
                        onTap: _chooseSound,
                      ),
                      const Divider(height: 1, indent: 56),
                      SwitchListTile(
                        secondary: const Icon(Icons.vibration_rounded),
                        title: const Text('اهتزاز'),
                        value: _vibration,
                        onChanged: (bool value) => setState(() => _vibration = value),
                      ),
                      const Divider(height: 1, indent: 56),
                      ListTile(
                        leading: const Icon(Icons.snooze_rounded),
                        title: const Text('غفوة'),
                        subtitle: Text('$_snooze دقائق'),
                        trailing: const Icon(Icons.chevron_left_rounded),
                        onTap: _chooseSnooze,
                      ),
                    ],
                  ),
                  if (widget.existing != null) ...<Widget>[
                    const SizedBox(height: 18),
                    SizedBox(
                      height: 52,
                      child: TextButton(
                        onPressed: _delete,
                        style: TextButton.styleFrom(
                          foregroundColor: colors.error,
                          backgroundColor: colors.surface,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(26)),
                        ),
                        child: const Text('حذف المنبه', style: TextStyle(fontWeight: FontWeight.w700)),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NumberWheel extends StatelessWidget {
  const _NumberWheel({
    required this.value,
    required this.count,
    required this.formatter,
    required this.onChanged,
  });

  final int value;
  final int count;
  final String Function(int value) formatter;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 92,
      child: CupertinoPicker(
        scrollController: FixedExtentScrollController(initialItem: value),
        itemExtent: 54,
        diameterRatio: 1.3,
        squeeze: 1.05,
        selectionOverlay: Container(
          margin: const EdgeInsets.symmetric(horizontal: 4),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerHigh.withValues(alpha: .72),
            borderRadius: BorderRadius.circular(14),
          ),
        ),
        onSelectedItemChanged: onChanged,
        children: List<Widget>.generate(
          count,
          (int index) => Center(
            child: Text(
              formatter(index),
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    fontSize: 34,
                    fontWeight: FontWeight.w400,
                  ),
            ),
          ),
        ),
      ),
    );
  }
}

class _RepeatCard extends StatelessWidget {
  const _RepeatCard({required this.selected, required this.onToggle});

  final List<int> selected;
  final ValueChanged<int> onToggle;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 15, 16, 16),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text('تكرار', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 14),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: List<Widget>.generate(_AlarmEditorScreenState._weekOrder.length, (int index) {
              final int day = _AlarmEditorScreenState._weekOrder[index];
              final bool active = selected.contains(day);
              return InkWell(
                borderRadius: BorderRadius.circular(22),
                onTap: () => onToggle(day),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  width: 40,
                  height: 40,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: active ? _AlarmEditorScreenState._samsungBlue : colors.surfaceContainerHigh,
                    shape: BoxShape.circle,
                  ),
                  child: Text(
                    _AlarmEditorScreenState._weekLabels[index],
                    style: TextStyle(
                      color: active ? Colors.white : colors.onSurface.withValues(alpha: .68),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              );
            }),
          ),
        ],
      ),
    );
  }
}

class _SettingsGroup extends StatelessWidget {
  const _SettingsGroup({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Theme.of(context).colorScheme.surface,
      borderRadius: BorderRadius.circular(24),
      clipBehavior: Clip.antiAlias,
      child: Column(children: children),
    );
  }
}
