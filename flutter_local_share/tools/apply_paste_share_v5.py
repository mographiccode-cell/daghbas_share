from pathlib import Path


def replace_once(text: str, old: str, new: str, label: str) -> str:
    if old not in text:
        raise SystemExit(f'marker not found: {label}')
    return text.replace(old, new, 1)

root = Path('flutter_local_share')

# Version bump.
pubspec = root / 'pubspec.yaml'
text = pubspec.read_text(encoding='utf-8')
text = replace_once(text, 'version: 1.3.1+6', 'version: 1.4.0+7', 'pubspec version')
pubspec.write_text(text, encoding='utf-8')

# Service: reusable file sending, Windows clipboard files, Android file sharing.
service = root / 'lib' / 'chat_local_share_service.dart'
text = service.read_text(encoding='utf-8')
old = '''  Future<void> pickAndSend(Peer peer) async {
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      withData: false,
      withReadStream: false,
    );
    if (result == null) return;
    for (final picked in result.files) {
      final path = picked.path;
      if (path == null || path.isEmpty) continue;
      await sendFile(peer, File(path));
    }
  }

  Future<void> sendFile(
'''
new = '''  Future<void> pickAndSend(Peer peer) async {
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      withData: false,
      withReadStream: false,
    );
    if (result == null) return;
    final files = <File>[];
    for (final picked in result.files) {
      final path = picked.path;
      if (path == null || path.isEmpty) continue;
      files.add(File(path));
    }
    await sendFiles(peer, files);
  }

  Future<void> sendFiles(Peer peer, Iterable<File> files) async {
    for (final file in files) {
      if (!await file.exists()) continue;
      await sendFile(peer, file);
    }
  }

  Future<List<File>> clipboardFiles() async {
    if (!Platform.isWindows) return const <File>[];
    final values = await _native.invokeMethod<List<dynamic>>(
      'getClipboardFiles',
    );
    if (values == null || values.isEmpty) return const <File>[];
    final files = <File>[];
    for (final value in values) {
      final path = value?.toString() ?? '';
      if (path.isEmpty) continue;
      final file = File(path);
      if (await file.exists()) files.add(file);
    }
    return files;
  }

  Future<void> sendFile(
'''
text = replace_once(text, old, new, 'service pickAndSend')
old = '''  Future<void> openLink(String rawUrl) async {
'''
new = '''  Future<void> shareFile(ChatMessage message) async {
    if (!Platform.isAndroid || !message.isFile) return;
    final path = message.localPath;
    if (path == null || path.isEmpty) {
      throw const FileSystemException('الملف غير متاح للمشاركة');
    }
    await _native.invokeMethod<void>('shareFile', {
      'path': path,
      'name': message.fileName ?? 'file',
    });
  }

  Future<void> openLink(String rawUrl) async {
'''
text = replace_once(text, old, new, 'service shareFile')
service.write_text(text, encoding='utf-8')

# Main UI: Ctrl+V file paste, visible copy, Android share button.
main = root / 'lib' / 'main.dart'
text = main.read_text(encoding='utf-8')
old = '''    controller.addListener(_refreshComposer);
    scrollController.addListener(_handleScroll);
  }
'''
new = '''    controller.addListener(_refreshComposer);
    scrollController.addListener(_handleScroll);
    if (Platform.isWindows) {
      HardwareKeyboard.instance.addHandler(_handlePasteShortcut);
    }
  }
'''
text = replace_once(text, old, new, 'chat init keyboard')
old = '''    controller.removeListener(_refreshComposer);
    scrollController.removeListener(_handleScroll);
    controller.dispose();
'''
new = '''    controller.removeListener(_refreshComposer);
    scrollController.removeListener(_handleScroll);
    if (Platform.isWindows) {
      HardwareKeyboard.instance.removeHandler(_handlePasteShortcut);
    }
    controller.dispose();
'''
text = replace_once(text, old, new, 'chat dispose keyboard')
old = '''  Future<void> _sendFiles() async {
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

  @override
  Widget build(BuildContext context) {
'''
new = '''  Future<void> _sendFiles() async {
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

  bool _handlePasteShortcut(KeyEvent event) {
    if (!Platform.isWindows || event is! KeyDownEvent) return false;
    if (event.logicalKey != LogicalKeyboardKey.keyV ||
        !HardwareKeyboard.instance.isControlPressed) {
      return false;
    }
    unawaited(_pasteFromClipboard());
    return true;
  }

  Future<void> _pasteFromClipboard() async {
    try {
      final files = await widget.service.clipboardFiles();
      if (files.isNotEmpty) {
        if (pickingFiles) return;
        if (mounted) setState(() => pickingFiles = true);
        try {
          await widget.service.sendFiles(widget.peer, files);
          WidgetsBinding.instance.addPostFrameCallback(
            (_) => _jumpToLatest(animated: true),
          );
        } finally {
          if (mounted) setState(() => pickingFiles = false);
        }
        return;
      }

      final data = await Clipboard.getData(Clipboard.kTextPlain);
      final clipboardText = data?.text;
      if (clipboardText == null || clipboardText.isEmpty) return;
      final current = controller.text;
      var start = controller.selection.isValid
          ? controller.selection.start
          : current.length;
      var end = controller.selection.isValid
          ? controller.selection.end
          : current.length;
      if (start < 0) start = 0;
      if (end < 0) end = 0;
      if (start > current.length) start = current.length;
      if (end > current.length) end = current.length;
      if (start > end) {
        final swap = start;
        start = end;
        end = swap;
      }
      final merged = current.replaceRange(start, end, clipboardText);
      final bounded = merged.length <= 4096 ? merged : merged.substring(0, 4096);
      var caret = start + clipboardText.length;
      if (caret > bounded.length) caret = bounded.length;
      controller.value = TextEditingValue(
        text: bounded,
        selection: TextSelection.collapsed(offset: caret),
      );
    } catch (e) {
      if (mounted) _showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
'''
text = replace_once(text, old, new, 'chat paste methods')
old = '''          _ChatComposer(
            controller: controller,
            pickingFiles: pickingFiles,
            onAttach: _sendFiles,
            onSend: _sendText,
          ),
'''
new = '''          _ChatComposer(
            controller: controller,
            pickingFiles: pickingFiles,
            onAttach: _sendFiles,
            onPaste: Platform.isWindows ? _pasteFromClipboard : null,
            onSend: _sendText,
          ),
'''
text = replace_once(text, old, new, 'composer onPaste')
old = '''  const _ChatComposer({
    required this.controller,
    required this.pickingFiles,
    required this.onAttach,
    required this.onSend,
  });
  final TextEditingController controller;
  final bool pickingFiles;
  final VoidCallback onAttach;
  final VoidCallback onSend;
'''
new = '''  const _ChatComposer({
    required this.controller,
    required this.pickingFiles,
    required this.onAttach,
    required this.onSend,
    this.onPaste,
  });
  final TextEditingController controller;
  final bool pickingFiles;
  final VoidCallback onAttach;
  final VoidCallback onSend;
  final VoidCallback? onPaste;
'''
text = replace_once(text, old, new, 'composer fields')
old = '''                      IconButton(
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
                      Expanded(
'''
new = '''                      IconButton(
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
                      if (onPaste != null)
                        IconButton(
                          tooltip: 'لصق نص أو ملفات (Ctrl+V)',
                          onPressed: pickingFiles ? null : onPaste,
                          icon: const Icon(Icons.content_paste_rounded),
                        ),
                      Expanded(
'''
text = replace_once(text, old, new, 'composer paste button')
old = '''        const SizedBox(height: 4),
        _MessageMeta(message: message, foreground: foreground),
      ],
    );
  }
}

class _FileMessageContent extends StatelessWidget {
'''
new = '''        const SizedBox(height: 4),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _MessageMeta(message: message, foreground: foreground),
            const SizedBox(width: 4),
            IconButton(
              tooltip: 'نسخ الرسالة',
              visualDensity: VisualDensity.compact,
              constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
              padding: EdgeInsets.zero,
              onPressed: () => _copyMessage(context, message),
              icon: const Icon(Icons.copy_rounded, size: 14),
            ),
          ],
        ),
      ],
    );
  }
}

class _FileMessageContent extends StatelessWidget {
'''
text = replace_once(text, old, new, 'visible text copy')
old = '''            if (message.canRetry)
              IconButton(
                tooltip: 'إعادة الإرسال',
                onPressed: () async {
                  try {
                    await service.retryMessage(peer, message);
                  } catch (_) {}
                },
                icon: const Icon(
                  Icons.refresh_rounded,
                  color: Color(0xFFC62828),
                ),
              )
            else if (message.isIncoming && message.canOpenFile)
              IconButton(
                tooltip: 'فتح الملف',
                onPressed: () => _openFile(context),
                icon: const Icon(Icons.open_in_new_rounded),
              ),
'''
new = '''            if (message.canRetry)
              IconButton(
                tooltip: 'إعادة الإرسال',
                onPressed: () async {
                  try {
                    await service.retryMessage(peer, message);
                  } catch (_) {}
                },
                icon: const Icon(
                  Icons.refresh_rounded,
                  color: Color(0xFFC62828),
                ),
              ),
            if (Platform.isAndroid && message.canOpenFile)
              IconButton(
                tooltip: 'مشاركة الملف',
                onPressed: () => _shareFile(context),
                icon: const Icon(Icons.share_rounded),
              ),
            if (message.isIncoming && message.canOpenFile)
              IconButton(
                tooltip: 'فتح الملف',
                onPressed: () => _openFile(context),
                icon: const Icon(Icons.open_in_new_rounded),
              ),
'''
text = replace_once(text, old, new, 'file share button')
old = '''  Future<void> _savePermanent(BuildContext context) async {
'''
new = '''  Future<void> _shareFile(BuildContext context) async {
    try {
      await service.shareFile(message);
    } catch (e) {
      if (context.mounted) _showError(context, e);
    }
  }

  Future<void> _savePermanent(BuildContext context) async {
'''
text = replace_once(text, old, new, 'file share method')
old = '''          if (!message.isFile)
            ListTile(
              leading: const Icon(Icons.copy_rounded),
              title: const Text('نسخ'),
              onTap: () => Navigator.pop(context, 'copy'),
            ),
'''
new = '''          ListTile(
            leading: const Icon(Icons.copy_rounded),
            title: Text(message.isFile ? 'نسخ اسم الملف' : 'نسخ الرسالة'),
            onTap: () => Navigator.pop(context, 'copy'),
          ),
'''
text = replace_once(text, old, new, 'message action copy all')
old = '''          if (message.kind == ChatMessageKind.link)
            ListTile(
              leading: const Icon(Icons.open_in_new_rounded),
              title: const Text('فتح الرابط'),
              onTap: () => Navigator.pop(context, 'open'),
            ),
'''
new = '''          if (message.kind == ChatMessageKind.link)
            ListTile(
              leading: const Icon(Icons.open_in_new_rounded),
              title: const Text('فتح الرابط'),
              onTap: () => Navigator.pop(context, 'open'),
            ),
          if (Platform.isAndroid && message.isFile && message.canOpenFile)
            ListTile(
              leading: const Icon(Icons.share_rounded),
              title: const Text('مشاركة الملف'),
              onTap: () => Navigator.pop(context, 'share-file'),
            ),
'''
text = replace_once(text, old, new, 'message action share')
old = '''  if (action == 'copy') {
    await Clipboard.setData(ClipboardData(text: message.text));
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('تم النسخ')));
    }
  } else if (action == 'open') {
'''
new = '''  if (action == 'copy') {
    await _copyMessage(context, message);
  } else if (action == 'share-file') {
    try {
      await service.shareFile(message);
    } catch (e) {
      if (context.mounted) _showError(context, e);
    }
  } else if (action == 'open') {
'''
text = replace_once(text, old, new, 'message action handlers')
old = '''String _formatTime(DateTime time) {
'''
new = '''Future<void> _copyMessage(BuildContext context, ChatMessage message) async {
  final value = message.isFile ? (message.fileName ?? 'ملف') : message.text;
  await Clipboard.setData(ClipboardData(text: value));
  if (context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message.isFile ? 'تم نسخ اسم الملف' : 'تم نسخ الرسالة')),
    );
  }
}

String _formatTime(DateTime time) {
'''
text = replace_once(text, old, new, 'copy helper')
main.write_text(text, encoding='utf-8')

# Android native share sheet with scoped FileProvider fallback.
activity = root / 'overrides' / 'MainActivity.kt'
text = activity.read_text(encoding='utf-8')
text = replace_once(
    text,
    'import android.webkit.MimeTypeMap\n',
    'import android.webkit.MimeTypeMap\nimport androidx.core.content.FileProvider\n',
    'android FileProvider import',
)
old = '''                "openUri" -> {
'''
new = '''                "shareFile" -> {
                    val path = call.argument<String>("path")
                    val requestedName = call.argument<String>("name")
                    if (path.isNullOrBlank()) {
                        result.error("INVALID_PATH", "Missing file path", null)
                        return@setMethodCallHandler
                    }
                    try {
                        shareFile(path, requestedName)
                        result.success(null)
                    } catch (e: Exception) {
                        result.error("SHARE_FAILED", e.message ?: "Unable to share file", null)
                    }
                }

                "openUri" -> {
'''
text = replace_once(text, old, new, 'android share method case')
old = '''    private fun openUri(raw: String) {
'''
new = '''    private fun shareFile(raw: String, requestedName: String?) {
        val shareUri: Uri
        val mime: String
        if (raw.startsWith("content://", ignoreCase = true)) {
            shareUri = Uri.parse(raw)
            mime = contentResolver.getType(shareUri) ?: "application/octet-stream"
        } else {
            val source = File(raw).canonicalFile
            if (!source.exists() || !source.isFile) {
                throw IllegalStateException("File does not exist")
            }
            val allowedRoots = listOfNotNull(
                cacheDir,
                externalCacheDir,
                filesDir,
                getExternalFilesDir(null),
            ).map { it.canonicalFile }
            var shareSource = source
            val insideOwnedStorage = allowedRoots.any { root ->
                source.path == root.path || source.path.startsWith(root.path + File.separator)
            }
            if (!insideOwnedStorage) {
                val shareDir = File(cacheDir, "share-out").apply { mkdirs() }
                shareDir.listFiles()?.filter { it.isFile && System.currentTimeMillis() - it.lastModified() > 86_400_000L }
                    ?.forEach { it.delete() }
                val target = File(
                    shareDir,
                    "${System.currentTimeMillis()}-${sanitizeFileName(requestedName ?: source.name)}",
                )
                source.inputStream().use { input ->
                    target.outputStream().use { output -> input.copyTo(output, 1024 * 1024) }
                }
                shareSource = target
            }
            shareUri = FileProvider.getUriForFile(
                this,
                "$packageName.fileprovider",
                shareSource,
            )
            val extension = shareSource.name.substringAfterLast('.', "").lowercase()
            mime = MimeTypeMap.getSingleton().getMimeTypeFromExtension(extension)
                ?: "application/octet-stream"
        }

        val intent = Intent(Intent.ACTION_SEND).apply {
            type = mime
            putExtra(Intent.EXTRA_STREAM, shareUri)
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        }
        startActivity(Intent.createChooser(intent, "مشاركة الملف"))
    }

    private fun openUri(raw: String) {
'''
text = replace_once(text, old, new, 'android share helper')
activity.write_text(text, encoding='utf-8')

manifest = root / 'overrides' / 'AndroidManifest.xml'
text = manifest.read_text(encoding='utf-8')
old = '''        </activity>
        <meta-data
            android:name="flutterEmbedding"
'''
new = '''        </activity>
        <provider
            android:name="androidx.core.content.FileProvider"
            android:authorities="${applicationId}.fileprovider"
            android:exported="false"
            android:grantUriPermissions="true">
            <meta-data
                android:name="android.support.FILE_PROVIDER_PATHS"
                android:resource="@xml/localshare_file_paths" />
        </provider>
        <meta-data
            android:name="flutterEmbedding"
'''
text = replace_once(text, old, new, 'android FileProvider manifest')
manifest.write_text(text, encoding='utf-8')

print('APPLIED_LOCALSHARE_PASTE_SHARE_V5')
