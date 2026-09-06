import 'dart:io';

import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

@pragma('vm:entry-point')
void localShareForegroundCallback() {
  FlutterForegroundTask.setTaskHandler(_LocalShareKeepAliveTask());
}

class _LocalShareKeepAliveTask extends TaskHandler {
  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {}

  @override
  void onRepeatEvent(DateTime timestamp) {}

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {}
}

class LocalShareBackgroundRuntime with WindowListener, TrayListener {
  LocalShareBackgroundRuntime._();

  static final LocalShareBackgroundRuntime instance =
      LocalShareBackgroundRuntime._();

  bool _windowsReady = false;
  bool _androidReady = false;
  bool _quitting = false;

  Future<void> initializeBeforeApp() async {
    if (Platform.isWindows) {
      await windowManager.ensureInitialized();
      windowManager.addListener(this);
      trayManager.addListener(this);
      await windowManager.setPreventClose(true);
      _windowsReady = true;
    }

    if (Platform.isAndroid) {
      FlutterForegroundTask.initCommunicationPort();
      FlutterForegroundTask.init(
        androidNotificationOptions: const AndroidNotificationOptions(
          channelId: 'localshare_background_connection',
          channelName: 'اتصال LocalShare في الخلفية',
          channelDescription: 'يبقي LocalShare متصلاً لاستقبال الرسائل والملفات.',
          onlyAlertOnce: true,
        ),
        iosNotificationOptions: IOSNotificationOptions(
          showNotification: false,
          playSound: false,
        ),
        foregroundTaskOptions: ForegroundTaskOptions(
          eventAction: ForegroundTaskEventAction.repeat(30000),
          autoRunOnBoot: false,
          autoRunOnMyPackageReplaced: true,
          allowWakeLock: true,
          allowWifiLock: true,
          allowAutoRestart: true,
          stopWithTask: false,
        ),
      );
      _androidReady = true;
    }
  }

  Future<void> startPersistentConnection() async {
    if (Platform.isAndroid && _androidReady) {
      try {
        if (!await FlutterForegroundTask.isRunningService) {
          await FlutterForegroundTask.startService(
            serviceId: 40404,
            serviceTypes: const [ForegroundServiceTypes.remoteMessaging],
            notificationTitle: 'LocalShare متصل',
            notificationText: 'جاهز لاستقبال الرسائل والملفات في الخلفية',
            callback: localShareForegroundCallback,
          );
        }
      } catch (_) {
        // LocalShare still works in foreground if Android denies the service.
      }
    }

    if (Platform.isWindows && _windowsReady) {
      try {
        final exeDir = File(Platform.resolvedExecutable).parent.path;
        final iconPath = '$exeDir${Platform.pathSeparator}localshare_tray.ico';
        if (File(iconPath).existsSync()) {
          await trayManager.setIcon(iconPath);
        }
        await trayManager.setToolTip('LocalShare — متصل بالشبكة المحلية');
        await trayManager.setContextMenu(
          Menu(
            items: [
              MenuItem(key: 'show_window', label: 'فتح LocalShare'),
              MenuItem.separator(),
              MenuItem(key: 'exit_app', label: 'خروج نهائي'),
            ],
          ),
        );
      } catch (_) {}
    }
  }

  Future<void> showWindowsApp() async {
    if (!Platform.isWindows || !_windowsReady) return;
    await windowManager.show();
    await windowManager.focus();
    await windowManager.setSkipTaskbar(false);
  }

  Future<void> quitWindowsApp() async {
    if (!Platform.isWindows || !_windowsReady || _quitting) return;
    _quitting = true;
    try {
      await windowManager.setPreventClose(false);
      await trayManager.destroy();
      await windowManager.destroy();
    } finally {
      _quitting = false;
    }
  }

  @override
  Future<void> onWindowClose() async {
    if (!Platform.isWindows || _quitting) return;
    if (await windowManager.isPreventClose()) {
      await windowManager.hide();
      await windowManager.setSkipTaskbar(true);
    }
  }

  @override
  void onTrayIconMouseDown() {
    showWindowsApp();
  }

  @override
  void onTrayIconRightMouseDown() {
    trayManager.popUpContextMenu();
  }

  @override
  void onTrayMenuItemClick(MenuItem menuItem) {
    if (menuItem.key == 'show_window') {
      showWindowsApp();
    } else if (menuItem.key == 'exit_app') {
      quitWindowsApp();
    }
  }

  void dispose() {
    if (Platform.isWindows) {
      windowManager.removeListener(this);
      trayManager.removeListener(this);
    }
  }
}
