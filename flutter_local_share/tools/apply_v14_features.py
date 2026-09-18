from pathlib import Path

root = Path(__file__).resolve().parents[1]
main_path = root / 'lib' / 'main.dart'
text = main_path.read_text(encoding='utf-8')

# Imports.
if "import 'background_runtime.dart';" not in text:
    text = text.replace("import 'local_share_service.dart';\n", "import 'background_runtime.dart';\nimport 'clipboard_share.dart';\nimport 'local_share_service.dart';\n", 1)
if "package:flutter_foreground_task/flutter_foreground_task.dart" not in text:
    text = text.replace("import 'package:flutter/material.dart';\n", "import 'package:flutter/material.dart';\nimport 'package:flutter_foreground_task/flutter_foreground_task.dart';\nimport 'package:flutter_linkify/flutter_linkify.dart';\n", 1)

# Initialize persistent runtime before the UI.
old = """Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await LocalShareNotifications.instance.initialize();
  runApp(const LocalShareApp());
}
"""
new = """Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await LocalShareBackgroundRuntime.instance.initializeBeforeApp();
  await LocalShareNotifications.instance.initialize();
  runApp(const LocalShareApp());
}
"""
if old in text:
    text = text.replace(old, new, 1)

# Android back minimizes instead of destroying the listening process.
old = """      home: const Directionality(
        textDirection: TextDirection.rtl,
        child: LocalShareShell(),
      ),
"""
new = """      home: Directionality(
        textDirection: TextDirection.rtl,
        child: Platform.isAndroid
            ? const WithForegroundTask(child: LocalShareShell())
            : const LocalShareShell(),
      ),
"""
if old in text:
    text = text.replace(old, new, 1)

# Shell state: share inbox guard.
old = """  AppLifecycleState _appLifecycle = AppLifecycleState.resumed;
"""
new = """  AppLifecycleState _appLifecycle = AppLifecycleState.resumed;
  bool _consumingSharedContent = false;
"""
if old in text and '_consumingSharedContent' not in text:
    text = text.replace(old, new, 1)

# Start service after LocalShare transport is initialized.
old = """    service.onIncomingMessage = _handleIncomingMessage;
    notifications.attachPeerHandler(_openPeerFromNotification);
    service.init();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(notifications.requestPermission());
    });
"""
new = """    service.onIncomingMessage = _handleIncomingMessage;
    notifications.attachPeerHandler(_openPeerFromNotification);
    unawaited(_initializeTransport());
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(notifications.requestPermission());
    });
"""
if old in text:
    text = text.replace(old, new, 1)

marker = """  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _appLifecycle = state;
  }
"""
replacement = """  Future<void> _initializeTransport() async {
    await service.init();
    await LocalShareBackgroundRuntime.instance.startPersistentConnection();
    if (mounted) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        unawaited(_consumeAndroidShareInbox());
      });
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _appLifecycle = state;
    if (state == AppLifecycleState.resumed) {
      unawaited(_consumeAndroidShareInbox());
    }
  }

  Future<void> _consumeAndroidShareInbox() async {
    if (!Platform.isAndroid || _consumingSharedContent || !service.initialized) return;
    _consumingSharedContent = true;
    try {
      final shared = await AndroidShareInbox.consume();
      if (shared.isEmpty || !mounted) return;
      final peers = service.pairedPeers;
      if (peers.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('اربط جهازًا أولًا ثم أعد المشاركة إلى LocalShare')),
        );
        return;
      }

      Peer? target;
      if (peers.length == 1) {
        target = peers.first;
      } else {
        target = await showModalBottomSheet<Peer>(
          context: context,
          showDragHandle: true,
          builder: (sheetContext) => SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const ListTile(
                  title: Text('إرسال المشاركة إلى…', style: TextStyle(fontWeight: FontWeight.w800)),
                  subtitle: Text('اختر الجهاز المستلم'),
                ),
                ...peers.map(
                  (peer) => ListTile(
                    leading: const CircleAvatar(child: Icon(Icons.devices_rounded)),
                    title: Text(peer.name),
                    onTap: () => Navigator.pop(sheetContext, peer),
                  ),
                ),
              ],
            ),
          ),
        );
      }
      if (target == null || !mounted) return;
      setState(() => selectedPeerId = target!.deviceId);
      for (final file in shared.files) {
        try {
          await service.sendFile(target!, file);
        } catch (e) {
          if (mounted) _showError(context, e);
        }
      }
      final sharedText = shared.text?.trim();
      if (sharedText != null && sharedText.isNotEmpty) {
        try {
          await service.sendChat(target!, sharedText);
        } catch (_) {}
      }
    } finally {
      _consumingSharedContent = false;
    }
  }
"""
if marker in text and '_initializeTransport() async' not in text:
    text = text.replace(marker, replacement, 1)

# Chat paste helper.
marker = """  Future<void> _sendFiles() async {
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
replacement = marker + """

  Future<void> _pasteFromClipboard() async {
    try {
      final pasted = await LocalShareClipboard.read();
      if (pasted.files.isNotEmpty) {
        for (final file in pasted.files) {
          await widget.service.sendFile(widget.peer, file);
        }
        WidgetsBinding.instance.addPostFrameCallback(
          (_) => _jumpToLatest(animated: true),
        );
        return;
      }
      final value = pasted.text;
      if (value == null || value.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('لا يوجد ملف أو صورة أو نص قابل للصق')),
          );
        }
        return;
      }
      final selection = controller.selection;
      final start = selection.isValid ? selection.start : controller.text.length;
      final end = selection.isValid ? selection.end : controller.text.length;
      final next = controller.text.replaceRange(start, end, value);
      final caret = start + value.length;
      controller.value = TextEditingValue(
        text: next.length > 4096 ? next.substring(0, 4096) : next,
        selection: TextSelection.collapsed(offset: caret.clamp(0, next.length > 4096 ? 4096 : next.length)),
      );
    } catch (e) {
      if (mounted) _showError(context, e);
    }
  }
"""
if marker in text and '_pasteFromClipboard() async' not in text:
    text = text.replace(marker, replacement, 1)

# Composer gets paste callback.
old = """          _ChatComposer(
            controller: controller,
            pickingFiles: pickingFiles,
            onAttach: _sendFiles,
            onSend: _sendText,
          ),
"""
new = """          _ChatComposer(
            controller: controller,
            pickingFiles: pickingFiles,
            onAttach: _sendFiles,
            onPaste: _pasteFromClipboard,
            onSend: _sendText,
          ),
"""
if old in text:
    text = text.replace(old, new, 1)

# Ctrl+V inside the conversation routes files/images to send and text to editor.
old = """    return ColoredBox(
      color: const Color(0xFFF2F5F9),
      child: Column(
"""
new = """    return CallbackShortcuts(
      bindings: <ShortcutActivator, VoidCallback>{
        const SingleActivator(LogicalKeyboardKey.keyV, control: true): _pasteFromClipboard,
      },
      child: ColoredBox(
        color: const Color(0xFFF2F5F9),
        child: Column(
"""
if old in text:
    text = text.replace(old, new, 1)
# Close extra wrapper at end of _ChatPane build. Match the first occurrence immediately before class _ChatHeader.
old = """        ],
      ),
    );
  }
}

class _ChatHeader"""
new = """          ],
        ),
      ),
    );
  }
}

class _ChatHeader"""
if old in text:
    text = text.replace(old, new, 1)

# Composer signature and paste button.
old = """    required this.onAttach,
    required this.onSend,
  });
  final TextEditingController controller;
  final bool pickingFiles;
  final VoidCallback onAttach;
  final VoidCallback onSend;
"""
new = """    required this.onAttach,
    required this.onPaste,
    required this.onSend,
  });
  final TextEditingController controller;
  final bool pickingFiles;
  final VoidCallback onAttach;
  final VoidCallback onPaste;
  final VoidCallback onSend;
"""
if old in text:
    text = text.replace(old, new, 1)

needle = """                      IconButton(
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
replacement = needle + """                      IconButton(
                        tooltip: 'لصق ملف أو صورة أو نص',
                        onPressed: onPaste,
                        icon: const Icon(Icons.content_paste_rounded),
                      ),
"""
if needle in text and "tooltip: 'لصق ملف أو صورة أو نص'" not in text:
    text = text.replace(needle, replacement, 1)

# Inline URLs are always green and clickable, even inside normal text messages.
old = """        SelectableText(
          message.text,
          textDirection: direction,
          style: TextStyle(color: foreground, height: 1.38, fontSize: 14.5),
        ),
"""
new = """        SelectableLinkify(
          text: message.text,
          textDirection: direction,
          options: const LinkifyOptions(humanize: false),
          style: TextStyle(color: foreground, height: 1.38, fontSize: 14.5),
          linkStyle: const TextStyle(
            color: Color(0xFF159447),
            fontWeight: FontWeight.w700,
            decoration: TextDecoration.underline,
            decorationColor: Color(0xFF159447),
          ),
          onOpen: (link) => _confirmAndOpenLink(context, service, link.url),
        ),
"""
if old in text:
    text = text.replace(old, new, 1)

# One-tap copy button beside message status.
old = """        const SizedBox(height: 4),
        _MessageMeta(message: message, foreground: foreground),
"""
new = """        const SizedBox(height: 4),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () async {
                await Clipboard.setData(ClipboardData(text: message.text));
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('تم نسخ الرسالة')),
                  );
                }
              },
              child: const Padding(
                padding: EdgeInsets.all(4),
                child: Icon(Icons.copy_rounded, size: 14, color: Color(0xFF667085)),
              ),
            ),
            const SizedBox(width: 4),
            _MessageMeta(message: message, foreground: foreground),
          ],
        ),
"""
# Replace only first occurrence (text message), not file message.
if old in text and 'تم نسخ الرسالة' not in text:
    text = text.replace(old, new, 1)

main_path.write_text(text, encoding='utf-8')
print('Applied LocalShare 1.4 background/share/paste/link UX patch')
