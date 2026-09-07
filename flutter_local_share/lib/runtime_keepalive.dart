import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_background/flutter_background.dart';
import 'package:window_manager/window_manager.dart';

class LocalShareRuntimeKeepAlive {
  LocalShareRuntimeKeepAlive._();

  static Future<void> initializeBeforeRunApp() async {
    if (Platform.isWindows) {
      await windowManager.ensureInitialized();
      const options = WindowOptions(
        minimumSize: Size(760, 560),
        center: true,
        skipTaskbar: false,
        title: 'LocalShare',
      );
      await windowManager.waitUntilReadyToShow(options, () async {
        await windowManager.setPreventClose(true);
        await windowManager.show();
        await windowManager.focus();
      });
    }
  }

  static Future<bool> enableAndroidBackgroundAfterLaunch() async {
    if (!Platform.isAndroid) return false;
    try {
      const config = FlutterBackgroundAndroidConfig(
        notificationTitle: 'LocalShare متصل',
        notificationText: 'جاهز لاستقبال الرسائل والملفات عبر الشبكة المحلية',
        notificationImportance: AndroidNotificationImportance.normal,
        enableWifiLock: true,
      );
      final initialized = await FlutterBackground.initialize(
        androidConfig: config,
      );
      if (!initialized) return false;
      if (FlutterBackground.isBackgroundExecutionEnabled) return true;
      return await FlutterBackground.enableBackgroundExecution();
    } catch (_) {
      // Background mode is optional; app startup and foreground messaging must never fail.
      return false;
    }
  }

  static Future<void> minimizeWindowsToBackground() async {
    if (!Platform.isWindows) return;
    try {
      await windowManager.minimize();
    } catch (_) {}
  }

  static Future<void> allowWindowsExit() async {
    if (!Platform.isWindows) return;
    try {
      await windowManager.setPreventClose(false);
    } catch (_) {}
  }
}
