from pathlib import Path

root = Path(__file__).resolve().parents[1]
main_path = root / 'lib' / 'main.dart'
service_path = root / 'lib' / 'chat_local_share_service.dart'

main = main_path.read_text(encoding='utf-8')
service = service_path.read_text(encoding='utf-8')

# Imports + startup keepalive.
main = main.replace(
    "import 'package:flutter/services.dart';\n",
    "import 'package:flutter/services.dart';\nimport 'package:window_manager/window_manager.dart';\n",
    1,
)
main = main.replace(
    "import 'local_share_service.dart';\n",
    "import 'clipboard_paste.dart';\nimport 'local_share_service.dart';\n",
    1,
)
main = main.replace(
    "import 'notifications.dart';\n",
    "import 'notifications.dart';\nimport 'runtime_keepalive.dart';\n",
    1,
)
main = main.replace(
    "  WidgetsFlutterBinding.ensureInitialized();\n  await LocalShareNotifications.instance.initialize();",
    "  WidgetsFlutterBinding.ensureInitialized();\n  await LocalShareRuntimeKeepAlive.initializeBeforeRunApp();\n  await LocalShareNotifications.instance.initialize();",
    1,
)

# Shell lifecycle + native Android share receiver.
main = main.replace(
    "class _LocalShareShellState extends State<LocalShareShell>\n    with WidgetsBindingObserver {",
    "class _LocalShareShellState extends State<LocalShareShell>\n    with WidgetsBindingObserver, WindowListener {",
    1,
)
main = main.replace(
    "  late final LocalShareService service;\n  late final LocalShareNotifications notifications;\n",
    "  static const MethodChannel _nativeShareChannel = MethodChannel('local_share/native');\n\n  late final LocalShareService service;\n  late final LocalShareNotifications notifications;\n  final Set<String> _handledShareIds = <String>{};\n",
    1,
)

old_init = """  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    notifications = LocalShareNotifications.instance;
    service = LocalShareService();
    service.onIncomingMessage = _handleIncomingMessage;
    notifications.attachPeerHandler(_openPeerFromNotification);
    service.init();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(notifications.requestPermission());
    });
  }
"""
new_init = """  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (Platform.isWindows) windowManager.addListener(this);
    notifications = LocalShareNotifications.instance;
    service = LocalShareService();
    service.onIncomingMessage = _handleIncomingMessage;
    notifications.attachPeerHandler(_openPeerFromNotification);
    _nativeShareChannel.setMethodCallHandler(_handleNativeShareMethod);
    unawaited(service.init().then((_) => _consumePendingAndroidShares()));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(notifications.requestPermission());
    });
  }

  @override
  void onWindowClose() async {
    if (!Platform.isWindows) return;
    final preventClose = await windowManager.isPreventClose();
    if (preventClose) {
      await LocalShareRuntimeKeepAlive.minimizeWindowsToBackground();
    }
  }

  Future<dynamic> _handleNativeShareMethod(MethodCall call) async {
    if (call.method != 'sharedItems' || call.arguments is! Map) return null;
    final payload = Map<String, dynamic>.from(call.arguments as Map);
    await _handleAndroidShare(payload);
    return null;
  }

  Future<void> _consumePendingAndroidShares() async {
    if (!Platform.isAndroid || !service.initialized) return;
    try {
      final pending = await _nativeShareChannel.invokeMethod<List<dynamic>>(
        'consumeSharedItems',
      );
      for (final item in pending ?? const <dynamic>[]) {
        if (item is Map) {
          await _handleAndroidShare(Map<String, dynamic>.from(item));
        }
      }
    } catch (_) {}
  }

  Future<Peer?> _choosePeerForExternalShare() async {
    final peers = service.pairedPeers;
    if (peers.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('اربط جهازًا أولًا ثم أعد المشاركة.')),
        );
      }
      return null;
    }
    if (peers.length == 1) return peers.first;
    if (!mounted) return null;
    return showModalBottomSheet<Peer>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const ListTile(
              title: Text(
                'إرسال إلى…',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
              subtitle: Text('اختر الجهاز الذي تريد إرسال المحتوى إليه'),
            ),
            ...peers.map(
              (peer) => ListTile(
                leading: const CircleAvatar(child: Icon(Icons.devices_rounded)),
                title: Text(peer.name),
                subtitle: Text(
                  service.isOnline(peer.deviceId) ? 'متصل الآن' : 'غير متصل حاليًا',
                ),
                onTap: () => Navigator.pop(context, peer),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _handleAndroidShare(Map<String, dynamic> payload) async {
    if (!Platform.isAndroid || !service.initialized) return;
    final id = '${payload['id'] ?? ''}'.trim();
    if (id.isEmpty || !_handledShareIds.add(id)) return;
    if (_handledShareIds.length > 100) _handledShareIds.remove(_handledShareIds.first);

    final text = '${payload['text'] ?? ''}'.trim();
    final paths = (payload['paths'] as List<dynamic>? ?? const <dynamic>[])
        .map((value) => '$value')
        .where((value) => value.isNotEmpty)
        .toList(growable: false);
    if (text.isEmpty && paths.isEmpty) return;

    final peer = await _choosePeerForExternalShare();
    if (peer == null) return;
    if (mounted) setState(() => selectedPeerId = peer.deviceId);

    if (text.isNotEmpty) {
      try {
        await service.sendChat(peer, text);
      } catch (_) {}
    }
    for (final path in paths) {
      final file = File(path);
      var sent = false;
      try {
        if (await file.exists()) {
          await service.sendFile(peer, file);
          sent = true;
        }
      } catch (_) {}
      if (sent) {
        try {
          await file.delete();
        } catch (_) {}
      }
    }
  }
"""
if old_init not in main:
    raise SystemExit('initState marker not found')
main = main.replace(old_init, new_init, 1)

old_dispose = """  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    service.onIncomingMessage = null;
    notifications.detachPeerHandler(_openPeerFromNotification);
    service.dispose();
    super.dispose();
  }
"""
new_dispose = """  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    if (Platform.isWindows) windowManager.removeListener(this);
    _nativeShareChannel.setMethodCallHandler(null);
    service.onIncomingMessage = null;
    notifications.detachPeerHandler(_openPeerFromNotification);
    service.dispose();
    super.dispose();
  }
"""
if old_dispose not in main:
    raise SystemExit('dispose marker not found')
main = main.replace(old_dispose, new_dispose, 1)

# Rich Ctrl+V / clipboard paste in chat.
main = main.replace(
    "    controller.addListener(_refreshComposer);\n    scrollController.addListener(_handleScroll);",
    "    controller.addListener(_refreshComposer);\n    scrollController.addListener(_handleScroll);\n    if (Platform.isWindows) HardwareKeyboard.instance.addHandler(_handleHardwareKey);",
    1,
)
main = main.replace(
    "    controller.removeListener(_refreshComposer);\n    scrollController.removeListener(_handleScroll);",
    "    controller.removeListener(_refreshComposer);\n    scrollController.removeListener(_handleScroll);\n    if (Platform.isWindows) HardwareKeyboard.instance.removeHandler(_handleHardwareKey);",
    1,
)

send_files_marker = """  Future<void> _sendFiles() async {
    if (pickingFiles) return;
    setState(() => pickingFiles = true);
    try {
      await widget.service.pickAndSend(widget.peer);
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _jumpToLatest(animated: true),
      );
    } catch (e) {
      if (mounted) _showError(context, e);
    } finally {
      if (mounted) setState(() => pickingFiles = false);
    }
  }
"""
extra_paste = send_files_marker + """
  bool _handleHardwareKey(KeyEvent event) {
    if (!Platform.isWindows ||
        event is! KeyDownEvent ||
        event.logicalKey != LogicalKeyboardKey.keyV ||
        !HardwareKeyboard.instance.isControlPressed) {
      return false;
    }
    if (ModalRoute.of(context)?.isCurrent != true) return false;
    unawaited(_pasteFromClipboard());
    return true;
  }

  void _insertClipboardText(String value) {
    if (value.isEmpty) return;
    final current = controller.text;
    final selection = controller.selection;
    final start = selection.isValid ? selection.start.clamp(0, current.length) : current.length;
    final end = selection.isValid ? selection.end.clamp(0, current.length) : start;
    final next = current.replaceRange(start, end, value);
    if (next.length > 4096) {
      _showError(context, const FormatException('النص الملصق يتجاوز 4096 حرفًا'));
      return;
    }
    controller.value = TextEditingValue(
      text: next,
      selection: TextSelection.collapsed(offset: start + value.length),
    );
  }

  Future<void> _pasteFromClipboard() async {
    if (pickingFiles) return;
    try {
      final payload = await readClipboardForChat();
      if (payload.hasFiles) {
        if (mounted) setState(() => pickingFiles = true);
        for (final file in payload.files) {
          final temporary = payload.temporaryFiles.contains(file);
          var sent = false;
          try {
            await widget.service.sendFile(widget.peer, file);
            sent = true;
          } catch (e) {
            if (mounted) _showError(context, e);
          }
          if (temporary && sent) {
            try {
              await file.delete();
            } catch (_) {}
          }
        }
        WidgetsBinding.instance.addPostFrameCallback(
          (_) => _jumpToLatest(animated: true),
        );
      } else if ((payload.text ?? '').isNotEmpty) {
        _insertClipboardText(payload.text!);
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('لا يوجد نص أو ملف أو صورة قابلة للصق.')),
        );
      }
    } catch (e) {
      if (mounted) _showError(context, e);
    } finally {
      if (mounted && pickingFiles) setState(() => pickingFiles = false);
    }
  }
"""
if send_files_marker not in main:
    raise SystemExit('send files marker not found')
main = main.replace(send_files_marker, extra_paste, 1)

main = main.replace(
    "            onAttach: _sendFiles,\n            onSend: _sendText,",
    "            onAttach: _sendFiles,\n            onPaste: _pasteFromClipboard,\n            onSend: _sendText,",
    1,
)

composer_ctor = """    required this.onAttach,
    required this.onSend,
  });
  final TextEditingController controller;
  final bool pickingFiles;
  final VoidCallback onAttach;
  final VoidCallback onSend;
"""
composer_new = """    required this.onAttach,
    required this.onPaste,
    required this.onSend,
  });
  final TextEditingController controller;
  final bool pickingFiles;
  final VoidCallback onAttach;
  final VoidCallback onPaste;
  final VoidCallback onSend;
"""
if composer_ctor not in main:
    raise SystemExit('composer constructor marker not found')
main = main.replace(composer_ctor, composer_new, 1)

attach_button = """                      IconButton(
                        tooltip: 'إرسال ملفات',
                        onPressed: pickingFiles ? null : onAttach,
                        icon: pickingFiles
                            ? const SizedBox(
                                width: 19,
                                height: 19,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.attach_file_rounded),
                      ),
"""
paste_button = attach_button + """                      if (Platform.isWindows)
                        IconButton(
                          tooltip: 'لصق ملف أو صورة (Ctrl+V)',
                          onPressed: pickingFiles ? null : onPaste,
                          icon: const Icon(Icons.content_paste_rounded),
                        ),
"""
if attach_button not in main:
    raise SystemExit('attach button marker not found')
main = main.replace(attach_button, paste_button, 1)

# Secondary click for Windows message actions.
main = main.replace(
    "        onLongPress: () => _showMessageActions(context, service, peer, message),\n",
    "        onLongPress: () => _showMessageActions(context, service, peer, message),\n        onSecondaryTap: () => _showMessageActions(context, service, peer, message),\n",
    1,
)

# Replace text message content with direct green URL and visible copy action.
start = main.index('class _TextMessageContent extends StatelessWidget {')
end = main.index('class _FileMessageContent extends StatelessWidget {', start)
new_text_class = r'''class _TextMessageContent extends StatelessWidget {
  const _TextMessageContent({
    required this.service,
    required this.peer,
    required this.message,
    required this.foreground,
  });
  final LocalShareService service;
  final Peer peer;
  final ChatMessage message;
  final Color foreground;

  @override
  Widget build(BuildContext context) {
    final isLink = message.kind == ChatMessageKind.link;
    final direction = _textDirectionFor(message.text);
    const linkGreen = Color(0xFF128A50);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: isLink
                  ? InkWell(
                      borderRadius: BorderRadius.circular(8),
                      onTap: () => _openLinkDirect(context, service, message.text),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: Text(
                          message.text,
                          textDirection: TextDirection.ltr,
                          style: const TextStyle(
                            color: linkGreen,
                            height: 1.38,
                            fontSize: 14.5,
                            decoration: TextDecoration.underline,
                            decorationColor: linkGreen,
                          ),
                        ),
                      ),
                    )
                  : SelectableText(
                      message.text,
                      textDirection: direction,
                      style: TextStyle(color: foreground, height: 1.38, fontSize: 14.5),
                    ),
            ),
            const SizedBox(width: 4),
            IconButton(
              visualDensity: VisualDensity.compact,
              tooltip: 'نسخ الرسالة',
              onPressed: () => _copyMessage(context, message),
              icon: const Icon(Icons.copy_rounded, size: 17),
            ),
          ],
        ),
        if (isLink) ...[
          const SizedBox(height: 6),
          InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => _openLinkDirect(context, service, message.text),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0x0D128A50),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0x33128A50)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.link_rounded, size: 19, color: linkGreen),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _linkHost(message.text),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textDirection: TextDirection.ltr,
                      style: const TextStyle(
                        color: linkGreen,
                        fontWeight: FontWeight.w800,
                        fontSize: 12.5,
                      ),
                    ),
                  ),
                  const Icon(Icons.open_in_new_rounded, size: 17, color: linkGreen),
                ],
              ),
            ),
          ),
        ],
        const SizedBox(height: 4),
        _MessageMeta(message: message, foreground: foreground),
      ],
    );
  }
}

'''
main = main[:start] + new_text_class + main[end:]

# Android incoming file sharing button next to open.
old_open = """            else if (message.isIncoming && message.canOpenFile)
              IconButton(
                tooltip: 'فتح الملف',
                onPressed: () => _openFile(context),
                icon: const Icon(Icons.open_in_new_rounded),
              ),
"""
new_open = """            else if (message.isIncoming && message.canOpenFile)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (Platform.isAndroid)
                    IconButton(
                      tooltip: 'مشاركة الملف',
                      onPressed: () => _shareFile(context),
                      icon: const Icon(Icons.share_rounded),
                    ),
                  IconButton(
                    tooltip: 'فتح الملف',
                    onPressed: () => _openFile(context),
                    icon: const Icon(Icons.open_in_new_rounded),
                  ),
                ],
              ),
"""
if old_open not in main:
    raise SystemExit('file open marker not found')
main = main.replace(old_open, new_open, 1)

open_file_method = """  Future<void> _openFile(BuildContext context) async {
    try {
      await service.openFile(message);
    } catch (e) {
      if (context.mounted) _showError(context, e);
    }
  }
"""
share_file_method = open_file_method + """
  Future<void> _shareFile(BuildContext context) async {
    try {
      await service.shareFile(message);
    } catch (e) {
      if (context.mounted) _showError(context, e);
    }
  }
"""
if open_file_method not in main:
    raise SystemExit('open file method marker not found')
main = main.replace(open_file_method, share_file_method, 1)

# Direct URL opener + reusable copy helper.
confirm_start = main.index('Future<void> _confirmAndOpenLink(')
actions_start = main.index('Future<void> _showMessageActions(', confirm_start)
new_helpers = r'''Future<void> _openLinkDirect(
  BuildContext context,
  LocalShareService service,
  String url,
) async {
  try {
    await service.openLink(url);
  } catch (e) {
    if (context.mounted) _showError(context, e);
  }
}

Future<void> _copyMessage(BuildContext context, ChatMessage message) async {
  final value = message.isFile ? (message.fileName ?? 'ملف') : message.text;
  await Clipboard.setData(ClipboardData(text: value));
  if (context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message.isFile ? 'تم نسخ اسم الملف' : 'تم نسخ الرسالة')),
    );
  }
}

'''
main = main[:confirm_start] + new_helpers + main[actions_start:]

# Bottom sheet: copy all message types + direct link open.
main = main.replace(
    """          if (!message.isFile)
            ListTile(
              leading: const Icon(Icons.copy_rounded),
              title: const Text('نسخ'),
              onTap: () => Navigator.pop(context, 'copy'),
            ),
""",
    """          ListTile(
            leading: const Icon(Icons.copy_rounded),
            title: Text(message.isFile ? 'نسخ اسم الملف' : 'نسخ الرسالة'),
            onTap: () => Navigator.pop(context, 'copy'),
          ),
""",
    1,
)
main = main.replace(
    """  if (action == 'copy') {
    await Clipboard.setData(ClipboardData(text: message.text));
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('تم النسخ')));
    }
  } else if (action == 'open') {
    await _confirmAndOpenLink(context, service, message.text);
""",
    """  if (action == 'copy') {
    await _copyMessage(context, message);
  } else if (action == 'open') {
    await _openLinkDirect(context, service, message.text);
""",
    1,
)

# Service: share received Android MediaStore files through system share sheet.
service_marker = """  Future<void> openLink(String rawUrl) async {
"""
share_method = """  Future<void> shareFile(ChatMessage message) async {
    if (!Platform.isAndroid || !message.isIncoming || !message.isFile) {
      throw const UnsupportedError('مشاركة الملفات من LocalShare متاحة على Android للملفات المستلمة');
    }
    final uri = message.localPath;
    if (uri == null || !uri.startsWith('content://')) {
      throw const FileSystemException('الملف غير متاح للمشاركة');
    }
    await _native.invokeMethod<void>('shareUri', {
      'uri': uri,
      'name': message.fileName ?? 'LocalShare file',
    });
  }

""" + service_marker
if 'Future<void> shareFile(ChatMessage message)' not in service:
    if service_marker not in service:
        raise SystemExit('service openLink marker not found')
    service = service.replace(service_marker, share_method, 1)

main_path.write_text(main, encoding='utf-8')
service_path.write_text(service, encoding='utf-8')
print('Applied LocalShare 1.4 background/share/paste/link UX patch')
