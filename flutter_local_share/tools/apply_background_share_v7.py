from pathlib import Path

root = Path(__file__).resolve().parents[1]
main_path = root / 'lib' / 'main.dart'
main = main_path.read_text(encoding='utf-8')

# Imports.
if "import 'background_runtime.dart';" not in main:
    main = main.replace(
        "import 'local_share_service.dart';\n",
        "import 'background_runtime.dart';\nimport 'clipboard_paste.dart';\nimport 'local_share_service.dart';\n",
        1,
    )
if "import 'share_inbox.dart';" not in main:
    main = main.replace(
        "import 'notifications.dart';\n",
        "import 'notifications.dart';\nimport 'share_inbox.dart';\n",
        1,
    )

old_main = """Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await LocalShareNotifications.instance.initialize();
  runApp(const LocalShareApp());
}
"""
new_main = """Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await LocalSharePlatformRuntime.instance.prepareBeforeApp();
  await LocalShareNotifications.instance.initialize();
  runApp(const LocalShareApp());
}
"""
if old_main in main:
    main = main.replace(old_main, new_main, 1)

# Root back button on Android moves LocalShare to the background instead of
# destroying the activity and therefore the local messaging runtime.
old_home = """      home: const Directionality(
        textDirection: TextDirection.rtl,
        child: LocalShareShell(),
      ),
"""
new_home = """      home: Directionality(
        textDirection: TextDirection.rtl,
        child: Platform.isAndroid
            ? PopScope(
                canPop: false,
                onPopInvokedWithResult: (didPop, result) {
                  if (!didPop) unawaited(_moveAndroidToBackground());
                },
                child: const LocalShareShell(),
              )
            : const LocalShareShell(),
      ),
"""
if old_home in main:
    main = main.replace(old_home, new_home, 1)

old_fields = """  late final LocalShareService service;
  late final LocalShareNotifications notifications;
  String? selectedPeerId;
  String? _pendingNotificationPeerId;
  AppLifecycleState _appLifecycle = AppLifecycleState.resumed;
"""
new_fields = """  late final LocalShareService service;
  late final LocalShareNotifications notifications;
  late final LocalSharePlatformRuntime runtime;
  late final LocalShareShareInbox shareInbox;
  String? selectedPeerId;
  String? _pendingNotificationPeerId;
  AppLifecycleState _appLifecycle = AppLifecycleState.resumed;
  final List<ExternalShareItem> _pendingExternalShares = <ExternalShareItem>[];
  bool _sharePickerOpen = false;
"""
if old_fields in main:
    main = main.replace(old_fields, new_fields, 1)

old_init = """    notifications = LocalShareNotifications.instance;
    service = LocalShareService();
    service.onIncomingMessage = _handleIncomingMessage;
    notifications.attachPeerHandler(_openPeerFromNotification);
    service.init();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(notifications.requestPermission());
    });
"""
new_init = """    notifications = LocalShareNotifications.instance;
    runtime = LocalSharePlatformRuntime.instance;
    shareInbox = LocalShareShareInbox.instance;
    service = LocalShareService();
    service.onIncomingMessage = _handleIncomingMessage;
    notifications.attachPeerHandler(_openPeerFromNotification);
    service.init();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(notifications.requestPermission());
      unawaited(runtime.activate());
      unawaited(shareInbox.attach(_handleExternalShareItems));
    });
"""
if old_init in main:
    main = main.replace(old_init, new_init, 1)

old_dispose = """    service.onIncomingMessage = null;
    notifications.detachPeerHandler(_openPeerFromNotification);
    service.dispose();
"""
new_dispose = """    service.onIncomingMessage = null;
    notifications.detachPeerHandler(_openPeerFromNotification);
    shareInbox.detach(_handleExternalShareItems);
    service.dispose();
"""
if old_dispose in main:
    main = main.replace(old_dispose, new_dispose, 1)

# Add Android Share Sheet handling before selectedPeer getter.
marker_peer = """  Peer? get selectedPeer {
"""
share_methods = r'''  void _handleExternalShareItems(List<ExternalShareItem> items) {
    if (items.isEmpty) return;
    _pendingExternalShares.addAll(items.take(20));
    _scheduleExternalSharePicker();
  }

  void _scheduleExternalSharePicker() {
    if (!mounted ||
        !service.initialized ||
        _sharePickerOpen ||
        _pendingExternalShares.isEmpty) {
      return;
    }
    _sharePickerOpen = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_presentExternalSharePicker());
    });
  }

  Future<void> _presentExternalSharePicker() async {
    if (!mounted) {
      _sharePickerOpen = false;
      return;
    }
    final items = List<ExternalShareItem>.from(_pendingExternalShares);
    final peers = service.pairedPeers;
    if (peers.isEmpty) {
      _pendingExternalShares.clear();
      _sharePickerOpen = false;
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('اربط جهازًا أولًا'),
          content: const Text(
            'وصلت مشاركة إلى LocalShare، لكن لا يوجد جهاز مرتبط لإرسالها إليه.',
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('حسنًا'),
            ),
          ],
        ),
      );
      return;
    }

    final peer = await showModalBottomSheet<Peer>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 4, 18, 10),
              child: Row(
                children: [
                  const Icon(Icons.share_rounded),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Text(
                      items.length == 1
                          ? 'إرسال العنصر إلى…'
                          : 'إرسال ${items.length} عناصر إلى…',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            ...peers.map(
              (candidate) => ListTile(
                leading: CircleAvatar(
                  child: Icon(
                    Platform.isWindows
                        ? Icons.phone_android_rounded
                        : Icons.computer_rounded,
                  ),
                ),
                title: Text(candidate.name),
                subtitle: Text(
                  service.isOnline(candidate.deviceId)
                      ? 'متصل الآن'
                      : 'غير متصل حاليًا',
                ),
                trailing: const Icon(Icons.send_rounded),
                onTap: () => Navigator.pop(sheetContext, candidate),
              ),
            ),
            const SizedBox(height: 10),
          ],
        ),
      ),
    );

    _pendingExternalShares.clear();
    _sharePickerOpen = false;
    if (peer == null || !mounted) return;
    setState(() => selectedPeerId = peer.deviceId);
    await _sendExternalShareItems(peer, items);
  }

  Future<void> _sendExternalShareItems(
    Peer peer,
    List<ExternalShareItem> items,
  ) async {
    var failed = 0;
    for (final item in items) {
      try {
        if (item.isText) {
          final text = item.text!.trim();
          for (var offset = 0; offset < text.length; offset += 4000) {
            final end = (offset + 4000).clamp(0, text.length);
            await service.sendChat(peer, text.substring(offset, end));
          }
        } else if (item.isUri) {
          final file = await shareInbox.materialize(item);
          try {
            await service.sendFile(peer, file);
          } finally {
            try {
              if (await file.exists()) await file.delete();
            } catch (_) {}
          }
        }
      } catch (_) {
        failed++;
      }
    }
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    if (failed == 0) {
      messenger.showSnackBar(
        const SnackBar(content: Text('تمت إضافة المشاركة إلى المحادثة')),
      );
    } else {
      messenger.showSnackBar(
        SnackBar(content: Text('تعذر إرسال $failed من العناصر المشتركة')),
      );
    }
  }

'''
if '_handleExternalShareItems(List<ExternalShareItem> items)' not in main:
    if marker_peer not in main:
        raise SystemExit('selectedPeer marker not found')
    main = main.replace(marker_peer, share_methods + marker_peer, 1)

# Schedule pending shares once secure peer loading has finished.
marker_ready = """        final width = MediaQuery.sizeOf(context).width;
"""
ready_insert = """        if (_pendingExternalShares.isNotEmpty && !_sharePickerOpen) {
          _scheduleExternalSharePicker();
        }

        final width = MediaQuery.sizeOf(context).width;
"""
if ready_insert not in main:
    if marker_ready not in main:
        raise SystemExit('ready marker not found')
    main = main.replace(marker_ready, ready_insert, 1)

# Ctrl+V interception in the chat state.
old_chat_init = """    controller.addListener(_refreshComposer);
    scrollController.addListener(_handleScroll);
  }
"""
new_chat_init = """    controller.addListener(_refreshComposer);
    scrollController.addListener(_handleScroll);
    if (Platform.isWindows) HardwareKeyboard.instance.addHandler(_handleKeyEvent);
  }
"""
if old_chat_init in main:
    main = main.replace(old_chat_init, new_chat_init, 1)

old_chat_dispose = """    controller.removeListener(_refreshComposer);
    scrollController.removeListener(_handleScroll);
    controller.dispose();
"""
new_chat_dispose = """    controller.removeListener(_refreshComposer);
    scrollController.removeListener(_handleScroll);
    if (Platform.isWindows) HardwareKeyboard.instance.removeHandler(_handleKeyEvent);
    controller.dispose();
"""
if old_chat_dispose in main:
    main = main.replace(old_chat_dispose, new_chat_dispose, 1)

marker_send_text = """  Future<void> _sendText() async {
"""
paste_methods = r'''  bool _handleKeyEvent(KeyEvent event) {
    if (!Platform.isWindows ||
        event is! KeyDownEvent ||
        event.logicalKey != LogicalKeyboardKey.keyV ||
        !HardwareKeyboard.instance.isControlPressed) {
      return false;
    }
    unawaited(_pasteClipboard());
    return true;
  }

  Future<void> _pasteClipboard() async {
    try {
      final result = await pasteClipboardIntoChat(
        service: widget.service,
        peer: widget.peer,
        controller: controller,
      );
      if (!mounted || !result.handled) return;
      if (result.filesSent > 0) {
        WidgetsBinding.instance.addPostFrameCallback(
          (_) => _jumpToLatest(animated: true),
        );
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              result.filesSent == 1
                  ? 'تم إرسال الملف من الحافظة'
                  : 'تم إرسال ${result.filesSent} ملفات من الحافظة',
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) _showError(context, e);
    }
  }

'''
if '_handleKeyEvent(KeyEvent event)' not in main:
    if marker_send_text not in main:
        raise SystemExit('send text marker not found')
    main = main.replace(marker_send_text, paste_methods + marker_send_text, 1)

# Secondary click on desktop uses the same familiar message action menu.
old_gesture = """      child: GestureDetector(
        onLongPress: () => _showMessageActions(context, service, peer, message),
        child: Container(
"""
new_gesture = """      child: GestureDetector(
        onLongPress: () => _showMessageActions(context, service, peer, message),
        onSecondaryTap: () =>
            _showMessageActions(context, service, peer, message),
        child: Container(
"""
if old_gesture in main:
    main = main.replace(old_gesture, new_gesture, 1)

# Replace text/link rendering with a direct green link, as requested.
old_text_block = """        SelectableText(
          message.text,
          textDirection: direction,
          style: TextStyle(color: foreground, height: 1.38, fontSize: 14.5),
        ),
        if (isLink) ...[
          const SizedBox(height: 8),
          InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => _confirmAndOpenLink(context, service, message.text),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0x0D1769E0),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0x221769E0)),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.link_rounded,
                    size: 19,
                    color: Color(0xFF1769E0),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _linkHost(message.text),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textDirection: TextDirection.ltr,
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 12.5,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'فتح الرابط',
                          style: TextStyle(
                            fontSize: 11,
                            color: foreground.withValues(alpha: 0.62),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Icon(Icons.open_in_new_rounded, size: 17),
                ],
              ),
            ),
          ),
        ],
        const SizedBox(height: 4),
        _MessageMeta(message: message, foreground: foreground),
"""
new_text_block = """        if (isLink)
          InkWell(
            borderRadius: BorderRadius.circular(6),
            onTap: () => _openLinkDirect(context, service, message.text),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Text(
                message.text,
                textDirection: TextDirection.ltr,
                style: const TextStyle(
                  color: Color(0xFF168C4B),
                  height: 1.38,
                  fontSize: 14.5,
                  fontWeight: FontWeight.w700,
                  decoration: TextDecoration.underline,
                  decorationColor: Color(0xFF168C4B),
                ),
              ),
            ),
          )
        else
          SelectableText(
            message.text,
            textDirection: direction,
            style: TextStyle(color: foreground, height: 1.38, fontSize: 14.5),
          ),
        const SizedBox(height: 4),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _MessageMeta(message: message, foreground: foreground),
            const SizedBox(width: 3),
            InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () => _copyMessage(context, message),
              child: const Padding(
                padding: EdgeInsets.all(3),
                child: Icon(Icons.copy_rounded, size: 13, color: Color(0xFF667085)),
              ),
            ),
          ],
        ),
"""
if old_text_block in main:
    main = main.replace(old_text_block, new_text_block, 1)

# Copy is available for every message, including file cards (copies filename).
old_copy_condition = """          if (!message.isFile)
            ListTile(
              leading: const Icon(Icons.copy_rounded),
              title: const Text('نسخ'),
              onTap: () => Navigator.pop(context, 'copy'),
            ),
"""
new_copy_condition = """          ListTile(
            leading: const Icon(Icons.copy_rounded),
            title: Text(message.isFile ? 'نسخ اسم الملف' : 'نسخ'),
            onTap: () => Navigator.pop(context, 'copy'),
          ),
"""
if old_copy_condition in main:
    main = main.replace(old_copy_condition, new_copy_condition, 1)

old_copy_action = """  if (action == 'copy') {
    await Clipboard.setData(ClipboardData(text: message.text));
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('تم النسخ')));
    }
  } else if (action == 'open') {
    await _confirmAndOpenLink(context, service, message.text);
"""
new_copy_action = """  if (action == 'copy') {
    await _copyMessage(context, message);
  } else if (action == 'open') {
    await _openLinkDirect(context, service, message.text);
"""
if old_copy_action in main:
    main = main.replace(old_copy_action, new_copy_action, 1)

# Direct safe http(s) link opening and common copy helper. Classification already
# rejects non-http(s) link messages; validate again at the open boundary.
marker_confirm = """Future<void> _confirmAndOpenLink(
"""
helpers = r'''Future<void> _copyMessage(
  BuildContext context,
  ChatMessage message,
) async {
  final value = message.isFile ? (message.fileName ?? 'ملف') : message.text;
  await Clipboard.setData(ClipboardData(text: value));
  if (context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('تم النسخ')),
    );
  }
}

Future<void> _openLinkDirect(
  BuildContext context,
  LocalShareService service,
  String url,
) async {
  final uri = Uri.tryParse(url.trim());
  if (uri == null ||
      uri.host.isEmpty ||
      (uri.scheme.toLowerCase() != 'http' &&
          uri.scheme.toLowerCase() != 'https')) {
    if (context.mounted) _showError(context, 'الرابط غير صالح');
    return;
  }
  try {
    await service.openLink(uri.toString());
  } catch (e) {
    if (context.mounted) _showError(context, e);
  }
}

Future<void> _moveAndroidToBackground() async {
  if (!Platform.isAndroid) return;
  try {
    await const MethodChannel('local_share/native').invokeMethod<void>(
      'moveToBackground',
    );
  } catch (_) {}
}

'''
if 'Future<void> _copyMessage(' not in main:
    if marker_confirm not in main:
        raise SystemExit('link helper marker not found')
    main = main.replace(marker_confirm, helpers + marker_confirm, 1)

main_path.write_text(main, encoding='utf-8')

# Native Android back handling: keep the activity/process alive and move the
# task to the background instead of finishing it.
kotlin_path = root / 'overrides' / 'MainActivity.kt'
kotlin = kotlin_path.read_text(encoding='utf-8')
case_marker = '''                    "consumeSharedItems" -> {
'''
case_code = '''                    "moveToBackground" -> {
                        moveTaskToBack(true)
                        result.success(null)
                    }

'''
if '"moveToBackground" ->' not in kotlin:
    if case_marker not in kotlin:
        raise SystemExit('Kotlin channel marker not found')
    kotlin = kotlin.replace(case_marker, case_code + case_marker, 1)
kotlin_path.write_text(kotlin, encoding='utf-8')
print('Applied LocalShare 1.4 background, share, paste, copy and link UX integration')
