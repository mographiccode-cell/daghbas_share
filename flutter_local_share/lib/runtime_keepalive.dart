import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:window_manager/window_manager.dart';

class LocalShareRuntimeKeepAlive {
  LocalShareRuntimeKeepAlive._();

  static const MethodChannel _nativeChannel = MethodChannel(
    'local_share/native',
  );

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
      return await _nativeChannel.invokeMethod<bool>('startKeepAliveService') ??
          false;
    } catch (_) {
      // Background keepalive is best-effort. Foreground use must remain available.
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
