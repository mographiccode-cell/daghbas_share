import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';

import 'core/theme/app_theme.dart';
import 'screens/alarm_ring_screen.dart';
import 'screens/alarms/alarms_screen.dart';
import 'services/notification_service.dart';
import 'state/app_state.dart';

final GlobalKey<NavigatorState> appNavigatorKey = GlobalKey<NavigatorState>();

class WaqtApp extends StatefulWidget {
  const WaqtApp({super.key});

  @override
  State<WaqtApp> createState() => _WaqtAppState();
}

class _WaqtAppState extends State<WaqtApp> {
  StreamSubscription<NotificationEvent>? _subscription;
  NotificationEvent? _initialEvent;
  bool _initialHandled = false;

  @override
  void initState() {
    super.initState();
    _initialEvent = NotificationService.instance.takeInitialEvent();
    _subscription = NotificationService.instance.events.listen(_handleNotificationEvent);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await NotificationService.instance.requestPermissions();
    });
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  Future<void> _handleNotificationEvent(NotificationEvent event) async {
    Map<String, dynamic> data;
    try {
      data = jsonDecode(event.payload) as Map<String, dynamic>;
    } catch (_) {
      return;
    }
    if (data['type'] != 'alarm') return;
    final int? id = data['id'] as int?;
    if (id == null) return;
    final BuildContext? navContext = appNavigatorKey.currentContext;
    if (navContext == null) return;
    await Navigator.of(navContext).push(MaterialPageRoute<void>(
      fullscreenDialog: true,
      builder: (_) => AlarmRingScreen(alarmId: id, notificationId: event.notificationId),
    ));
  }

  void _tryHandleInitial(AppState state) {
    if (_initialHandled || _initialEvent == null || state.loading) return;
    _initialHandled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) => _handleNotificationEvent(_initialEvent!));
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<AppState>(
      builder: (BuildContext context, AppState state, _) {
        _tryHandleInitial(state);
        return MaterialApp(
          navigatorKey: appNavigatorKey,
          debugShowCheckedModeBanner: false,
          title: 'وقت',
          locale: const Locale('ar'),
          supportedLocales: const <Locale>[Locale('ar'), Locale('en')],
          localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          theme: buildAppTheme(),
          home: const Directionality(textDirection: TextDirection.rtl, child: AlarmsScreen()),
        );
      },
    );
  }
}
