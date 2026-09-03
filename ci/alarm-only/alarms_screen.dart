import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/alarm.dart';
import '../../state/app_state.dart';
import 'alarm_editor_screen.dart';

class AlarmsScreen extends StatelessWidget {
  const AlarmsScreen({super.key});

  Future<void> _add(BuildContext context) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const AlarmEditorScreen()),
    );
  }

  Future<void> _deleteAll(BuildContext context, List<AlarmModel> alarms) async {
    if (alarms.isEmpty) return;
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: const Text('حذف جميع المنبهات؟'),
        content: const Text('سيتم حذف كل المنبهات المحفوظة في التطبيق.'),
        actions: <Widget>[
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('إلغاء')),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: TextButton.styleFrom(foregroundColor: Theme.of(context).colorScheme.error),
            child: const Text('حذف الكل'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    final AppState state = context.read<AppState>();
    for (final AlarmModel alarm in List<AlarmModel>.from(alarms)) {
      if (alarm.id != null) await state.deleteAlarm(alarm.id!);
    }
  }

  @override
  Widget build(BuildContext context) {
    final AppState state = context.watch<AppState>();
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 16, 8),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      'المنبه',
                      style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                            fontSize: 34,
                            fontWeight: FontWeight.w700,
                            letterSpacing: -.8,
                          ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'إضافة منبه',
                    onPressed: () => _add(context),
                    icon: const Icon(Icons.add_rounded, size: 30),
                  ),
                  PopupMenuButton<String>(
                    tooltip: 'المزيد',
                    icon: const Icon(Icons.more_vert_rounded),
                    onSelected: (String value) {
                      if (value == 'delete_all') _deleteAll(context, state.alarms);
                    },
                    itemBuilder: (_) => const <PopupMenuEntry<String>>[
                      PopupMenuItem<String>(value: 'delete_all', child: Text('حذف جميع المنبهات')),
                    ],
                  ),
                ],
              ),
            ),
            Expanded(
              child: state.loading
                  ? const Center(child: CircularProgressIndicator())
                  : state.alarms.isEmpty
                      ? _EmptyState(onAdd: () => _add(context))
                      : ListView.separated(
                          padding: const EdgeInsets.fromLTRB(16, 10, 16, 28),
                          itemCount: state.alarms.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 10),
                          itemBuilder: (BuildContext context, int index) {
                            return _AlarmTile(alarm: state.alarms[index]);
                          },
                        ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AlarmTile extends StatelessWidget {
  const _AlarmTile({required this.alarm});

  final AlarmModel alarm;

  static const List<int> _weekOrder = <int>[6, 7, 1, 2, 3, 4, 5];
  static const Map<int, String> _dayNames = <int, String>{
    1: 'الاثنين',
    2: 'الثلاثاء',
    3: 'الأربعاء',
    4: 'الخميس',
    5: 'الجمعة',
    6: 'السبت',
    7: 'الأحد',
  };

  String _format12Hour() {
    final int hour24 = alarm.minutesOfDay ~/ 60;
    final int minute = alarm.minutesOfDay % 60;
    final int hour12 = hour24 % 12 == 0 ? 12 : hour24 % 12;
    final String period = hour24 < 12 ? 'صباحًا' : 'مساءً';
    return '${hour12.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')} $period';
  }

  String _repeatText() {
    if (alarm.daysOfWeek.isEmpty) return 'مرة واحدة';
    final Set<int> selected = alarm.daysOfWeek.toSet();
    if (_weekOrder.every(selected.contains)) return 'كل يوم';
    const Set<int> workDays = <int>{7, 1, 2, 3, 4};
    if (selected.length == workDays.length && workDays.every(selected.contains)) {
      return 'الأحد - الخميس';
    }
    return _weekOrder
        .where(selected.contains)
        .map((int day) => _dayNames[day]!)
        .join('، ');
  }

  String _subtitle() {
    final String title = alarm.title.trim();
    final String repeat = _repeatText();
    if (title.isEmpty) return repeat;
    return '$title  •  $repeat';
  }

  @override
  Widget build(BuildContext context) {
    final AppState state = context.read<AppState>();
    final ColorScheme colors = Theme.of(context).colorScheme;
    final Color mainColor = alarm.enabled ? colors.onSurface : colors.onSurface.withValues(alpha: .38);
    final Color secondaryColor = alarm.enabled
        ? colors.onSurface.withValues(alpha: .62)
        : colors.onSurface.withValues(alpha: .28);

    return Material(
      color: colors.surface,
      borderRadius: BorderRadius.circular(28),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => AlarmEditorScreen(existing: alarm)),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 19, 18, 18),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      _format12Hour(),
                      textDirection: TextDirection.ltr,
                      style: Theme.of(context).textTheme.displayMedium?.copyWith(
                            color: mainColor,
                            fontSize: 42,
                            height: 1,
                            fontWeight: FontWeight.w400,
                            letterSpacing: -1.2,
                          ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      _subtitle(),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: secondaryColor,
                            fontSize: 14,
                            height: 1.35,
                          ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 14),
              Switch(
                value: alarm.enabled,
                onChanged: (bool value) => state.toggleAlarm(alarm, value),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onAdd});

  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(32, 20, 32, 80),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Container(
              width: 104,
              height: 104,
              decoration: BoxDecoration(
                color: colors.surface,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.alarm_rounded,
                size: 52,
                color: colors.onSurface.withValues(alpha: .28),
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'لا توجد منبهات',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Text(
              'اضغط على + لإضافة منبه جديد',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: colors.onSurface.withValues(alpha: .55),
                  ),
            ),
            const SizedBox(height: 26),
            FilledButton.icon(
              onPressed: onAdd,
              icon: const Icon(Icons.add_rounded),
              label: const Text('إضافة منبه'),
              style: FilledButton.styleFrom(
                minimumSize: const Size(160, 50),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(25)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
