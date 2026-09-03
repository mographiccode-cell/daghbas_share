import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';

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

  ThemeData _lightTheme() {
    const Color blue = Color(0xFF3B7CFF);
    const Color background = Color(0xFFF5F5F7);
    const Color surface = Color(0xFFFFFFFF);
    const Color text = Color(0xFF17171A);
    final ColorScheme scheme = ColorScheme.fromSeed(
      seedColor: blue,
      brightness: Brightness.light,
      surface: surface,
    ).copyWith(
      primary: blue,
      surface: surface,
      onSurface: text,
      outline: const Color(0xFFD8D8DC),
      surfaceContainer: surface,
      surfaceContainerHigh: const Color(0xFFECECEF),
    );
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      colorScheme: scheme,
      scaffoldBackgroundColor: background,
      splashFactory: InkSparkle.splashFactory,
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        foregroundColor: text,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
      ),
      dividerColor: const Color(0xFFE8E8EB),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith<Color?>((states) =>
            states.contains(WidgetState.selected) ? Colors.white : const Color(0xFFF9F9FA)),
        trackColor: WidgetStateProperty.resolveWith<Color?>((states) =>
            states.contains(WidgetState.selected) ? blue : const Color(0xFFD1D1D6)),
        trackOutlineColor: const WidgetStatePropertyAll<Color>(Colors.transparent),
      ),
      snackBarTheme: const SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: Color(0xFF2D2D31),
        contentTextStyle: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        showDragHandle: true,
      ),
      dialogTheme: const DialogThemeData(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surface,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(18), borderSide: BorderSide.none),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(18), borderSide: BorderSide.none),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(18), borderSide: const BorderSide(color: blue, width: 1.5)),
      ),
    );
  }

  ThemeData _darkTheme() {
    const Color blue = Color(0xFF5D8FFF);
    const Color background = Color(0xFF0D0D0F);
    const Color surface = Color(0xFF1C1C1F);
    const Color text = Color(0xFFF5F5F7);
    final ColorScheme scheme = ColorScheme.fromSeed(
      seedColor: blue,
      brightness: Brightness.dark,
      surface: surface,
    ).copyWith(
      primary: blue,
      surface: surface,
      onSurface: text,
      outline: const Color(0xFF3B3B40),
      surfaceContainer: surface,
      surfaceContainerHigh: const Color(0xFF29292D),
    );
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: scheme,
      scaffoldBackgroundColor: background,
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        foregroundColor: text,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
      ),
      dividerColor: const Color(0xFF303034),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith<Color?>((states) =>
            states.contains(WidgetState.selected) ? Colors.white : const Color(0xFFB6B6BB)),
        trackColor: WidgetStateProperty.resolveWith<Color?>((states) =>
            states.contains(WidgetState.selected) ? blue : const Color(0xFF4A4A50)),
        trackOutlineColor: const WidgetStatePropertyAll<Color>(Colors.transparent),
      ),
      snackBarTheme: const SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: Color(0xFFF1F1F3),
        contentTextStyle: TextStyle(color: Color(0xFF17171A), fontWeight: FontWeight.w600),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        showDragHandle: true,
      ),
      dialogTheme: const DialogThemeData(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surface,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(18), borderSide: BorderSide.none),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(18), borderSide: BorderSide.none),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(18), borderSide: const BorderSide(color: blue, width: 1.5)),
      ),
    );
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
          theme: _lightTheme(),
          darkTheme: _darkTheme(),
          themeMode: ThemeMode.system,
          home: const Directionality(textDirection: TextDirection.rtl, child: AlarmsScreen()),
        );
      },
    );
  }
}
