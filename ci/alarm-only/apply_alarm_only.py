from pathlib import Path

p = Path('app/lib/state/app_state.dart')
s = p.read_text()

old = '''      alarms = await _database.getAlarms();
      medications = await _database.getMedications();
      tasks = await _database.getTasks();
      doseLogs = await _database.getDoseLogs();
      await _notifications.rescheduleAll(
        alarms: alarms,
        medications: medications,
        tasks: tasks,
      );'''
new = '''      alarms = await _database.getAlarms();
      // Alarm-only edition. Scheduling is deliberately deferred until the
      // Android notification/exact-alarm permissions have been checked.
      medications = <MedicationModel>[];
      tasks = <TaskReminder>[];
      doseLogs = <DoseLog>[];'''
if old not in s:
    raise SystemExit('load() scheduling block not found')
s = s.replace(old, new, 1)

old = '''    alarms = await _database.getAlarms();
    medications = await _database.getMedications();
    tasks = await _database.getTasks();
    doseLogs = await _database.getDoseLogs();'''
new = '''    alarms = await _database.getAlarms();
    medications = <MedicationModel>[];
    tasks = <TaskReminder>[];
    doseLogs = <DoseLog>[];'''
if old not in s:
    raise SystemExit('refresh() block not found')
s = s.replace(old, new, 1)

old = '''  Future<void> _reschedule() => _notifications.rescheduleAll(
        alarms: alarms,
        medications: medications,
        tasks: tasks,
      );'''
new = '''  Future<void> rescheduleAlarms() => _notifications.rescheduleAll(
        alarms: alarms,
        medications: const <MedicationModel>[],
        tasks: const <TaskReminder>[],
      );

  Future<void> _reschedule() => rescheduleAlarms();'''
if old not in s:
    raise SystemExit('_reschedule block not found')
s = s.replace(old, new, 1)

p.write_text(s)
print('Alarm-only AppState patch applied')
