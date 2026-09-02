import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_colors.dart';
import '../../core/utils/time_utils.dart';
import '../../models/alarm.dart';
import '../../state/app_state.dart';
import 'alarm_editor_screen.dart';

class AlarmsScreen extends StatelessWidget {
  const AlarmsScreen({super.key});

  Future<void> _add(BuildContext context) async {
    await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const AlarmEditorScreen()));
  }

  @override
  Widget build(BuildContext context) {
    final AppState state = context.watch<AppState>();
    return Scaffold(
      appBar: AppBar(
        title: const Text('المنبّه'),
        centerTitle: false,
        actions: <Widget>[
          IconButton(
            tooltip: 'إضافة منبّه',
            onPressed: () => _add(context),
            icon: const Icon(Icons.add_rounded, size: 30),
          ),
          const SizedBox(width: 6),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _add(context),
        child: const Icon(Icons.add_rounded, size: 30),
      ),
      body: state.loading
          ? const Center(child: CircularProgressIndicator())
          : state.alarms.isEmpty
              ? _EmptyState(onAdd: () => _add(context))
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(18, 10, 18, 110),
                  itemCount: state.alarms.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (BuildContext context, int index) => _AlarmTile(alarm: state.alarms[index]),
                ),
    );
  }
}

class _AlarmTile extends StatelessWidget {
  const _AlarmTile({required this.alarm});

  final AlarmModel alarm;

  @override
  Widget build(BuildContext context) {
    final AppState state = context.read<AppState>();
    final Color foreground = alarm.enabled ? AppColors.text : AppColors.textMuted;
    return Material(
      color: Theme.of(context).colorScheme.surfaceContainer,
      borderRadius: BorderRadius.circular(26),
      child: InkWell(
        borderRadius: BorderRadius.circular(26),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => AlarmEditorScreen(existing: alarm)),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
          child: Row(
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      formatMinutes(context, alarm.minutesOfDay),
                      style: Theme.of(context).textTheme.displaySmall?.copyWith(
                            color: foreground,
                            fontWeight: FontWeight.w500,
                          ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      alarm.title.trim().isEmpty ? 'منبّه' : alarm.title.trim(),
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(color: foreground),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      describeWeekdays(alarm.daysOfWeek),
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: alarm.enabled ? AppColors.textMuted : AppColors.textMuted.withValues(alpha: .55),
                          ),
                    ),
                  ],
                ),
              ),
              Switch(value: alarm.enabled, onChanged: (bool value) => state.toggleAlarm(alarm, value)),
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
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 36),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(Icons.alarm_rounded, size: 72, color: AppColors.purple.withValues(alpha: .75)),
            const SizedBox(height: 20),
            Text('لا توجد منبّهات', style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 8),
            Text('اضغط + لإضافة منبّه جديد.', textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodyMedium),
            const SizedBox(height: 24),
            FilledButton.icon(onPressed: onAdd, icon: const Icon(Icons.add_rounded), label: const Text('إضافة منبّه')),
          ],
        ),
      ),
    );
  }
}
