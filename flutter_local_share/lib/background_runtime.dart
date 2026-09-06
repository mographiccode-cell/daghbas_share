import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_background/flutter_background.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

class LocalSharePlatformRuntime with TrayListener, WindowListener {
  LocalSharePlatformRuntime._();

  static final LocalSharePlatformRuntime instance = LocalSharePlatformRuntime._();

  bool _desktopPrepared = false;
  bool _desktopActivated = false;
  bool _allowClose = false;
  bool _androidActivated = false;

  Future<void> prepareBeforeApp() async {
    if (!Platform.isWindows || _desktopPrepared) return;
    await windowManager.ensureInitialized();
    await windowManager.setPreventClose(true);
    _desktopPrepared = true;
  }

  Future<void> activate() async {
    if (Platform.isAndroid) {
      await _activateAndroid();
    } else if (Platform.isWindows) {
      await _activateWindows();
    }
  }

  Future<void> _activateAndroid() async {
    if (_androidActivated) return;
    const config = FlutterBackgroundAndroidConfig(
      notificationTitle: 'LocalShare يعمل في الخلفية',
      notificationText: 'متصل بالشبكة المحلية وجاهز لاستقبال الرسائل والملفات',
      notificationImportance: AndroidNotificationImportance.normal,
      enableWifiLock: true,
    );
    try {
      final initialized = await FlutterBackground.initialize(
        androidConfig: config,
      );
      if (!initialized) return;
      if (!FlutterBackground.isBackgroundExecutionEnabled) {
        final enabled = await FlutterBackground.enableBackgroundExecution();
        if (!enabled) return;
      }
      _androidActivated = true;
    } catch (_) {
      // The foreground UI remains usable even if Android denies background mode.
    }
  }

  Future<void> _activateWindows() async {
    if (_desktopActivated) return;
    if (!_desktopPrepared) await prepareBeforeApp();

    windowManager.addListener(this);
    trayManager.addListener(this);

    final trayDir = Directory(
      '${Directory.systemTemp.path}${Platform.pathSeparator}LocalShare',
    );
    await trayDir.create(recursive: true);
    final trayIcon = File(
      '${trayDir.path}${Platform.pathSeparator}localshare_tray.ico',
    );
    if (!await trayIcon.exists()) {
      await trayIcon.writeAsBytes(base64Decode(_trayIconBase64), flush: true);
    }

    await trayManager.setIcon(trayIcon.path);
    await trayManager.setToolTip('LocalShare — متصل وجاهز للاستقبال');
    await trayManager.setContextMenu(
      Menu(
        items: [
          MenuItem(key: 'show_window', label: 'فتح LocalShare'),
          MenuItem.separator(),
          MenuItem(key: 'exit_app', label: 'إنهاء LocalShare'),
        ],
      ),
    );
    _desktopActivated = true;
  }

  Future<void> showWindow() async {
    if (!Platform.isWindows) return;
    await windowManager.setSkipTaskbar(false);
    await windowManager.show();
    await windowManager.restore();
    await windowManager.focus();
  }

  Future<void> _hideToTray() async {
    if (!Platform.isWindows) return;
    await windowManager.hide();
    await windowManager.setSkipTaskbar(true);
  }

  Future<void> exitWindowsApp() async {
    if (!Platform.isWindows) return;
    _allowClose = true;
    try {
      await trayManager.destroy();
    } catch (_) {}
    await windowManager.setPreventClose(false);
    await windowManager.close();
  }

  @override
  void onWindowClose() {
    if (!_allowClose) unawaited(_hideToTray());
  }

  @override
  void onTrayIconMouseDown() {
    unawaited(showWindow());
  }

  @override
  void onTrayMenuItemClick(MenuItem menuItem) {
    switch (menuItem.key) {
      case 'show_window':
        unawaited(showWindow());
      case 'exit_app':
        unawaited(exitWindowsApp());
    }
  }

  static const String _trayIconBase64 =
      'AAABAAUAEBAAAAAAIADPAQAAVgAAABgYAAAAACAAjAIAACUCAAAgIAAAAAAgADQDAACxBAAAMDAAAAAAIACdBAAA5QcAAEBAAAAAACAAbwEAAIIMAACJUE5HDQoaCgAAAA1JSERSAAAAEAAAABAIBgAAAB/z/2EAAAGWSURBVHicpZO/axRREMc/8/bX7cqeBJVEq4M0W9hoKZhK1MLSWtMKgv9Mei38C1LGQhArCRYqVhZiJSLiaZLdu31vxmKzuncJKtx0897M932/830j6w8+GiuEW6X5vwGcA5HT7+JhIgKRG1RadzatlTSGUeLwwU4HEIG5N6ZHYaEgKDy8OWbvTc2HLy3r4wi1JQAnULdGdTFhe6tEe20Cs9bY3ip5dCuw8+wHT18ekMRgNmQg4INxtoi4Xo0w66SYGW2AInNsbjiuTlKevDBShJ6E9DaKQOuNpjXUoJ4pZ3JHG2Dn/nl2Xx+y97bmQhktzEGG/8A5qBtFRLh9reT5/gHTnwGvHXiROZJEyDNZkgA4EZqZcqUquHtjzOXNnMmllNnciKJOc5rA/vuGV++OyDOHmg1sFPABNs4lVJMMF0E1GaFmiHRulAV8+uzxaiDHNi9IEDhslLUy5t6dNR7vfuPrd0+adJQ7FvI7PzGDHmTuDVXIRw5VY/gJjT8WLsygDzVI4q4lHE/7b9t2AoClF/4VK2/jLzgvqtytOUx/AAAAAElFTkSuQmCCiVBORw0KGgoAAAANSUhEUgAAABgAAAAYCAYAAADgdz34AAACU0lEQVR4nOWUO2sUURTHf+fOZGYnWTZEIRtfETXGxgdopWlFsTBfwEasFFSs/ACWgq2FEKxFlIAIYuUXEKwsUikKQrLuM/ucufdYrEt2dyYYlRTigVvMnXvO//7O40rx1idlF83sZvD/WEAEjOySgAjEFppdxduBd+YRETAmvXwDvURZKPpcPBmxXneYX9CkBEQgTpR6y6VX21FpOmILz+4UeXRtD5Wmox0rso2IP/zhCdTaytWzk9y+VMCq4g15CuAUcoHge3D38jRLizlef2jx8FWN6chgVbcXGNz+wIzP0mJue27AOvAMnDsS8rWc0Et+UoyNrQxPsgBWoRAZ9ua3sifS/wfQiZWjsxO8uFdk7VvMjScblJuWUsPhSSr+KIEO0tRylBoW6BcwThTrIAqEekeJAsPKuwYPXlYobVqiQJgwkgqeIhgmEQHPExpNy/7ZCebnAt5/bBEGBs9Ao+PwRMgFgnOKU9AMhcw2VfrFLFUTTh2PeHx/H4vzIaWqpd1RqpsWtZAkSr1p2Ww7ur3sN9Mf3xCBTk85cTjk+vIM83Mhk5Fw/swUC4dCPG/0vHOQC2Htc4+V1TJhICMkmQLWKflJw4XTORptqLWUg0WfYwf9VBqcg3wERvqpEkZrkVkDVYhCIRcariwVuLlc4OmbBs/fVinkPZzbclH6jdCNlXLNpgYuRTCgaHeVWjNhZfU7G5UY3xO+rMdMNx3WpfNtBHw/Pc6ZBMNOCrQ6jqnIZHbJOPm4ZRIMbHDRqchg3daw/Y7t6Ll2fxh8xwJ/Y/++wA8FeQCtQS0OegAAAABJRU5ErkJggolQTkcNChoKAAAADUlIRFIAAAAgAAAAIAgGAAAAc3p69AAAAvtJREFUeJztl8+LHFUQxz9V/WZnOt27cd3dRCUXT4G95CIEVBADgh48KJ4EoydRROLBePSQoxeP7i2gYI6KRhRk8cc/EFAkejN6UHcXZ5idnumemffKQ8+SBLt7dpeFvWzBo6H7vVefqvet6m45++bvxjGaHqfzE4ATgCMFUAGRYwIQgawwfACnB6OYCyDSPFQhHxtPr8ecjpXtXY+L9g/RCBAMJh6mvrxWDTPoDTzPXYi58fYZLq3H7Ox6bLZ+nrm6B2bQaQkLrjkaFwnjqZEVgccebXPz6kO88tEWP9we0XLCqLBGbUhVK3aRsNWf8v4Ly7z1zGm8N6KGtJrBqXYJqwI+GN0ssLHZ59pnXc4sOaa+Oh21GfABVlJlOTmYTn2ASIXVxYiVVPGheX4lQAhG2la+/XnEIDeClWVWZapCVgQurcc8cb5DpPD97RE//prz0x9j0rYSGsRQDWCQtIXNX3K+vDUEBLi7iYrMBGa4SMm7E6LXVnnyfIebt4Zc3tiiNzQWO0LSlkYx1h7BHsRifHeKAFEE2SiU561CpLCNY8EJVz7eYWNzlwcS5dyyMvU2txIqRVhlKqXY/u17Hr+Q8OffY/pZIIrK+y4SBnkgXhBkFoDMEtfkYF8KMyubDQJvvLTCu5fXCEYZoYcQIB8H2k7ws/7gQ9k/DiXCe02AuKP4YFx5eY1nL8bc+Sew0BLSJMJJc4QG5EU9Re0RCDANkHSUD955mKVESRMlLwwVYZgHrMGzAU4hywNXP/yLLA84/T/s3AyowrmzjjSG7V5ZAarwyJqWumgAaCn0h4o2HHR9K6YU3mRiXP+ix6m28PxTS8QdoT8wPv+uTzGx2v6wt348NcazeVWwjRmQ2QY3vumSF4Hf7hS89+oqLlI++arHYOQr03r/HkIaa+37YF9lGGm5UTbyLKWO1198kE+/7rLT87ScNAJg5buhFvAg/wWqzNIpOFeW2CE+gu6zuSK810KgjNiOxjkc4pNsr/SOwvmhAI7aTgBOAP4D5H9EpJMy4b8AAAAASUVORK5CYIKJUE5HDQoaCgAAAA1JSERSAAAAMAAAADAIBgAAAFcC+YcAAARkSURBVHic7ZhPiFV1FMc/53f/zntvZpzJaUwLnJKYpI0ytAkXgS0KXBnYqoI2qWUt2rQrWkS0EalNmzBIwjYty0VQlIGIZFhJRYkho+MbnXHen/vevff3a/F7o6mI9/feax7C+8LbPe65n3O+95zz+8n03nOGe1hq0C/Qq4YAg9YQYNAaAgxaQ4BBa00BREBJf5+5ZgAi0M4MrczgKejX/rImAAK0M3hgnc+mCZ9a0xD5/SnFmgAoBbVEs21zyNED08SBML+U4ylbmV7kO/3ZE7qJ5ykoRcJyQzO7MeCHdzby7W8Jrx2usq7sEXqgDWTaYBy9VRhACVy+lpPm7u71FGR1zXJDow1smQ7YMh0QeMLLHy+QG1uJdSVF6IsTRCEApYRGS7Pv6TE2TfgY41Z6JZCkhpkpHyWQdZLwwo4K5Uj45UKbSqQ4crzGXwspcSDoghDFAATqLcPenWM8uiEo/uZ3CupZem1g9xNldlMG4PjvCb9eaDMSSuE2VdhCnsDFpZyHJn1ybW3hItN5RhTcKJ0SaKW2tQae0MqM85woDKANrB/zbHb6qCiQ61ChX9w6qyoEkGvD2Iji1U+qjMaCAaduZNuoYW4m4r3nJ0lSg6+sld78bJHT59tUYuHMPynlSKF1nwGMgcCHk3+3yF1ThLXbSl0j2ErGnYy//ukih75eZjRW5MZQChW+45QubCFjoBIJcpf2IyKYW/rg6vcSh4IS+OJEnWM/Nzj83QoP3uejta2p1u4rhtMg04Y7RjCAr4RGogl8ua3NtlMYjRVfnqyz5+AlwkCYHvdpZ6ar4bgq6de9UOALy7WcmU0RV5Yz2qm5CcLaUEgzGy4KbNfptSX0vAuJ2N98NWV2c8z7Bzbg+9Kxxc3/SzMLpRQ9Z35VThZalVKgxNqk0dRUSooP3tjIYzMRcaTQ2hD4CtVlerQxhTuRM4ASaCSapGWDrJ/weXf/Bh5/JKTWhFrDsLSS00yMM4AIaA0jsVCKVKGZ4ASgOh/p9tkSc1tjFq7k7NhWYevDIdUlQ+ALYSC8uGuSPHdflbU2lGLh1NmEU2eblGJ1mxV7A+hkf/tsiX3PjlLNoNWGpRU7RW0ngpd2jXe156cZ3B/Chyi+/6lOZURxNyc5W8hTUG/mXEwM1SVDHAq+J9e7qwEuXzVdHRnz3KDHhXozL7xrOQNYjyqmYoEJO3yaCTf5fXK8u4NPmgtTsX3+//IR59owWlYc+3GFM382WVzOeebJMZ7bWeHSoiEIhDwzvHVowc4B1421s7JcWswZLatCa4sTwOowmq+mnL/YRolw8MhllMCenRWuNeFqC07/0aSZGOeVG7kRIwyKncycLWQMhIEQddZqrYWPjlY5N9/mqbkKs5tD4lDhKfc2+t8YRY+VXQ2yWwPEoeLzr67yzYkab78yTRgISUvjtnR3p77uQs2WXeSgeAZ7Vd/uhdLMDjKt1+7loc8XW663Ff3Q8HZ60BoCDFpDgEFrCDBo3fMA/wISqrO/EFRYIwAAAABJRU5ErkJggolQTkcNChoKAAAADUlIRFIAAABAAAAAQAgGAAAAqmlx3gAAATZJREFUeJztmMERgkAQBAfLHPRnXIagGRiBGZiCacnPLPRh8bHgA+z2XjEdAMx0LXvUdYfL66MNs6MD0FgAHYDGAugANBZAB6CxADoAjQXQAWgsgA5AYwF0ABoLoAOM8X6c0t5VUoCUJ6GsAOknIVpEaQEDkRKaECDFSeiW3ApnLqsxjtd+8TOamYAoLIAOQLN5AYuWYBRTy3WNpfdPMxMQUV5qREBUeUnahz15BSKLD5SdgIzyUlEBWeWlZAHPO/vrPEaagIrlpYQlWLX4QOgEVC8vBQpooby04q8wXfh8m3dylDwGM7EAOgDN5gWE3QdMLcW5yyqKsAmoVnSK0E+gBQnhO+B860uLSFuCVSWUvBTNZPPHoAXQAWgsgA5AYwF0ABoLoAPQWAAdgMYC6AA0FkAHoPkCLyQ6Vqgj2IMAAAAASUVORK5CYII=';
}
