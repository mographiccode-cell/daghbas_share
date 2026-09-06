from pathlib import Path
import re

root = Path(__file__).resolve().parents[1]
main_path = root / 'lib' / 'main.dart'
service_path = root / 'lib' / 'chat_local_share_service.dart'

main = main_path.read_text(encoding='utf-8')
service = service_path.read_text(encoding='utf-8')


def sub_once(text, pattern, replacement, label):
    out, count = re.subn(pattern, replacement, text, count=1, flags=re.S)
    if count != 1:
        raise SystemExit(f'{label}: expected one match, got {count}')
    return out

# ---------------- service: bounded histories + optimistic delivery ----------------
service = service.replace(
    "  static const int _maxChatChars = 4096;\n",
    "  static const int _maxChatChars = 4096;\n"
    "  static const int _maxMessagesPerPeer = 1500;\n"
    "  static const int _maxTransferHistory = 400;\n",
    1,
)

service = sub_once(
    service,
    r"  List<ChatMessage> messagesFor\(String peerId\) => _messages\n      \.where\(\(message\) => message\.peerId == peerId\)\n      \.toList\(growable: false\);",
    """  List<ChatMessage> messagesFor(String peerId) {
    final list = _messages
        .where((message) => message.peerId == peerId)
        .toList(growable: false);
    list.sort((a, b) => a.sentAt.compareTo(b.sentAt));
    return list;
  }

  ChatMessage? lastMessageFor(String peerId) {
    final list = messagesFor(peerId);
    return list.isEmpty ? null : list.last;
  }

  TransferItem? transferForId(String? id) {
    if (id == null || id.isEmpty) return null;
    for (final item in _transfers.reversed) {
      if (item.id == id) return item;
    }
    return null;
  }""",
    'messages helpers',
)

service = service.replace(
    "    _transfers.add(transfer);\n    notifyListeners();",
    "    _transfers.add(transfer);\n    _trimTransfers();\n    notifyListeners();",
)

incoming_pattern = r"    _recentNonces\[replayKey\] = DateTime\.now\(\);\n    _messages\.add\(\n      ChatMessage\(\n        id: id,\n        peerId: peer\.deviceId,\n        peerName: peer\.name,\n        kind: kind,\n        direction: ChatMessageDirection\.receive,\n        sentAt: DateTime\.fromMillisecondsSinceEpoch\(timestamp\),\n        text: text,\n      \),\n    \);\n    notifyListeners\(\);\n    final ack = await _crypto\.macString\("
incoming_replacement = """    _recentNonces[replayKey] = DateTime.now();
    final duplicate = _messages.any(
      (message) => message.peerId == peer.deviceId && message.id == id,
    );
    if (!duplicate) {
      _messages.add(
        ChatMessage(
          id: id,
          peerId: peer.deviceId,
          peerName: peer.name,
          kind: kind,
          direction: ChatMessageDirection.receive,
          sentAt: DateTime.fromMillisecondsSinceEpoch(timestamp),
          text: text,
          deliveryStatus: ChatDeliveryStatus.delivered,
        ),
      );
      _trimMessageHistory(peer.deviceId);
      notifyListeners();
    }
    final ack = await _crypto.macString("""
service = sub_once(service, incoming_pattern, incoming_replacement, 'incoming message dedupe')

service = sub_once(
    service,
    r"  Future<void> sendChat\(Peer peer, String rawText\) async \{.*?\n  \}\n\n(?=  Future<void> pickAndSend)",
    r'''  Future<void> sendChat(Peer peer, String rawText) async {
    final text = rawText.trim();
    if (text.isEmpty) return;
    if (text.length > _maxChatChars) {
      throw const FormatException('الرسالة طويلة جدًا. الحد الأقصى 4096 حرفًا.');
    }
    final message = ChatMessage(
      id: _randomToken(16),
      peerId: peer.deviceId,
      peerName: peer.name,
      kind: classifyChatText(text),
      direction: ChatMessageDirection.send,
      sentAt: DateTime.now(),
      text: text,
      deliveryStatus: ChatDeliveryStatus.sending,
    );
    _messages.add(message);
    _trimMessageHistory(peer.deviceId);
    notifyListeners();
    await _deliverTextMessage(peer, message);
  }

  Future<void> retryMessage(Peer peer, ChatMessage message) async {
    if (!message.canRetry) return;
    message.deliveryStatus = ChatDeliveryStatus.sending;
    message.error = null;
    notifyListeners();
    if (message.kind == ChatMessageKind.file) {
      final path = message.localPath;
      if (path == null || path.isEmpty || !await File(path).exists()) {
        message.deliveryStatus = ChatDeliveryStatus.failed;
        message.error = 'الملف الأصلي لم يعد موجودًا';
        notifyListeners();
        return;
      }
      await sendFile(peer, File(path), existingMessage: message);
      return;
    }
    await _deliverTextMessage(peer, message);
  }

  Future<void> _deliverTextMessage(Peer peer, ChatMessage message) async {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    try {
      final current = await _resolveVerifiedPeer(peer);
      final key = _peerKey(current);
      final nonce = _crypto.b64(_crypto.randomBytes(12));
      final box = await _crypto.encryptPayload(
        sharedKey: key,
        senderId: deviceId,
        receiverId: current.deviceId,
        timestamp: timestamp,
        nonceId: nonce,
        purpose: 'message',
        payload: {
          'id': message.id,
          'kind': message.kind == ChatMessageKind.link ? 'link' : 'text',
          'text': message.text,
        },
      );
      final client = HttpClient()..connectionTimeout = const Duration(seconds: 5);
      try {
        final request = await client.postUrl(
          Uri(scheme: 'http', host: current.ip, port: current.port, path: '/message3'),
        );
        request.headers.contentType = ContentType.json;
        request.write(jsonEncode({
          'deviceId': deviceId,
          'timestamp': timestamp,
          'nonce': nonce,
          'box': box,
        }));
        final response = await request.close().timeout(const Duration(seconds: 10));
        final body = await utf8.decoder.bind(response).join();
        if (response.statusCode != HttpStatus.ok) {
          throw HttpException('Message failed: ${response.statusCode}');
        }
        final decoded = jsonDecode(body);
        if (decoded is! Map<String, dynamic>) {
          throw const PairingException('استجابة الرسالة غير صالحة');
        }
        final expectedAck = await _crypto.macString(
          key,
          'msgack|$protocolVersion|${current.deviceId}|$deviceId|$timestamp|$nonce|${message.id}',
        );
        if (!_crypto.constantTimeEquals(expectedAck, '${decoded['proof'] ?? ''}')) {
          throw const PairingException('تعذر التحقق من وصول الرسالة');
        }
        message.deliveryStatus = ChatDeliveryStatus.delivered;
        message.error = null;
        notifyListeners();
      } finally {
        client.close(force: true);
      }
    } catch (e) {
      message.deliveryStatus = ChatDeliveryStatus.failed;
      message.error = e.toString().replaceFirst('Exception: ', '');
      notifyListeners();
      rethrow;
    }
  }

''',
    'optimistic text send',
)

service = sub_once(
    service,
    r"  Future<void> sendFile\(Peer peer, File file\) async \{.*?\n  \}\n\n(?=  Future<String> savePermanently)",
    r'''  Future<void> sendFile(Peer peer, File file, {ChatMessage? existingMessage}) async {
    if (!await file.exists()) throw const FileSystemException('الملف غير موجود');
    final total = await file.length();
    if (total < 0 || total > _maxFileBytes) {
      throw const FileSystemException('حجم الملف يتجاوز حد الأمان البالغ 50 GB');
    }
    final fileName = safeFileName(file.uri.pathSegments.last);
    final transfer = TransferItem(
      id: _randomToken(12),
      fileName: fileName,
      peerName: peer.name,
      direction: TransferDirection.send,
      totalBytes: total,
      startedAt: DateTime.now(),
      status: TransferStatus.running,
    );
    _transfers.add(transfer);
    _trimTransfers();

    final message = existingMessage ?? ChatMessage(
      id: _randomToken(16),
      peerId: peer.deviceId,
      peerName: peer.name,
      kind: ChatMessageKind.file,
      direction: ChatMessageDirection.send,
      sentAt: DateTime.now(),
      fileName: fileName,
      fileSize: total,
      localPath: file.path,
      temporary: false,
      savedPermanently: true,
      deliveryStatus: ChatDeliveryStatus.sending,
    );
    message.transferId = transfer.id;
    message.deliveryStatus = ChatDeliveryStatus.sending;
    message.error = null;
    if (existingMessage == null) {
      _messages.add(message);
      _trimMessageHistory(peer.deviceId);
    }
    notifyListeners();

    try {
      final current = await _resolveVerifiedPeer(peer);
      final sharedKey = _peerKey(current);
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final transferBase = _crypto.randomBytes(8);
      final transferNonce = _crypto.b64(transferBase);
      final metaHeader = await _crypto.encryptMetadata(
        sharedKey: sharedKey,
        senderId: deviceId,
        receiverId: current.deviceId,
        timestamp: timestamp,
        transferNonce: transferNonce,
        fileName: fileName,
        size: total,
      );
      final transferKey = await _crypto.deriveTransferKey(
        sharedKey,
        timestamp,
        transferBase,
        deviceId,
        current.deviceId,
      );
      final client = HttpClient()..connectionTimeout = const Duration(seconds: 5);
      try {
        final request = await client.postUrl(
          Uri(scheme: 'http', host: current.ip, port: current.port, path: '/upload3'),
        );
        request.headers.set('x-localshare-device', deviceId);
        request.headers.set('x-localshare-time', '$timestamp');
        request.headers.set('x-localshare-transfer', transferNonce);
        request.headers.set('x-localshare-meta', metaHeader);
        request.headers.contentType = ContentType.binary;
        request.contentLength = _crypto.encryptedBodyLength(total);

        var sent = 0;
        var chunkIndex = 0;
        var lastNotify = DateTime.fromMillisecondsSinceEpoch(0);
        final source = await file.open();
        try {
          while (sent < total) {
            final plain = await source.read(min(_chunkSize, total - sent));
            if (plain.isEmpty) throw const FileSystemException('Unexpected end of source file');
            final nonce = _crypto.chunkNonce(transferBase, chunkIndex);
            final aad = _crypto.chunkAad(
              deviceId,
              current.deviceId,
              timestamp,
              transferNonce,
              chunkIndex,
              total,
            );
            final encrypted = await _crypto.cipher.encrypt(
              plain,
              secretKey: SecretKey(transferKey),
              nonce: nonce,
              aad: aad,
            );
            request.add(encrypted.cipherText);
            request.add(encrypted.mac.bytes);
            sent += plain.length;
            chunkIndex++;
            if (chunkIndex % 4 == 0) await request.flush();
            transfer.progress = total == 0 ? 1 : (sent / total).clamp(0.0, 1.0);
            final now = DateTime.now();
            if (now.difference(lastNotify) > const Duration(milliseconds: 120)) {
              lastNotify = now;
              notifyListeners();
            }
          }
        } finally {
          await source.close();
        }

        final response = await request.close().timeout(_idleTimeout);
        final body = await utf8.decoder.bind(response).join();
        if (response.statusCode != HttpStatus.ok) {
          throw HttpException('Transfer failed: ${response.statusCode}');
        }
        final decoded = jsonDecode(body);
        if (decoded is! Map<String, dynamic>) {
          throw const PairingException('استجابة استلام الملف غير صالحة');
        }
        final bytes = (decoded['bytes'] as num?)?.toInt() ?? -1;
        final expectedAck = await _crypto.macString(
          sharedKey,
          'ack|$protocolVersion|${current.deviceId}|$deviceId|$timestamp|$transferNonce|$bytes',
        );
        if (bytes != total ||
            !_crypto.constantTimeEquals(expectedAck, '${decoded['proof'] ?? ''}')) {
          throw const PairingException('تعذر التحقق من استلام الملف على الجهاز الآخر');
        }
      } finally {
        client.close(force: true);
      }

      transfer.progress = 1;
      transfer.status = TransferStatus.completed;
      message.deliveryStatus = ChatDeliveryStatus.delivered;
      message.error = null;
      notifyListeners();
    } catch (e) {
      transfer.status = TransferStatus.failed;
      transfer.error = e.toString();
      message.deliveryStatus = ChatDeliveryStatus.failed;
      message.error = e.toString().replaceFirst('Exception: ', '');
      notifyListeners();
      rethrow;
    }
  }

''',
    'optimistic file send',
)

# trim incoming file messages too
service = service.replace(
    "      notifyListeners();\n\n      final ack = await _crypto.macString(\n        sharedKey,\n        'ack|$protocolVersion|$deviceId|$sourceId|$timestamp|$transferNonce|$received',",
    "      _trimMessageHistory(peer.deviceId);\n      notifyListeners();\n\n      final ack = await _crypto.macString(\n        sharedKey,\n        'ack|$protocolVersion|$deviceId|$sourceId|$timestamp|$transferNonce|$received',",
    1,
)

service = service.replace(
    "  Future<void> forgetPeer(String id) async {",
    """  void _trimMessageHistory(String peerId) {
    final peerMessages = _messages.where((m) => m.peerId == peerId).toList();
    final overflow = peerMessages.length - _maxMessagesPerPeer;
    if (overflow <= 0) return;
    final removeIds = peerMessages.take(overflow).map((m) => m.id).toSet();
    _messages.removeWhere((m) => m.peerId == peerId && removeIds.contains(m.id));
  }

  void _trimTransfers() {
    while (_transfers.length > _maxTransferHistory) {
      final index = _transfers.indexWhere(
        (item) => item.status == TransferStatus.completed || item.status == TransferStatus.failed,
      );
      if (index < 0) break;
      _transfers.removeAt(index);
    }
  }

  Future<void> forgetPeer(String id) async {""",
    1,
)

# ---------------- UI: single mobile header and richer conversation list ----------------
main = main.replace(
    "          appBar: AppBar(\n",
    "          appBar: (!wide && peer != null) ? null : AppBar(\n",
    1,
)

main = main.replace(
    "                child: _PeerTile(\n                  peer: peer,",
    "                child: _PeerTile(\n                  service: service,\n                  peer: peer,",
)

main = sub_once(
    main,
    r"class _PeerTile extends StatelessWidget \{.*?\n\}\n\n(?=class _DiscoveredTile)",
    r'''class _PeerTile extends StatelessWidget {
  const _PeerTile({
    required this.service,
    required this.peer,
    required this.online,
    required this.selected,
    required this.onTap,
    required this.onForget,
  });

  final LocalShareService service;
  final Peer peer;
  final bool online;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onForget;

  @override
  Widget build(BuildContext context) {
    final last = service.lastMessageFor(peer.deviceId);
    final preview = last == null
        ? (online ? 'متصل الآن' : 'اضغط لفتح المحادثة')
        : _messagePreview(last);
    return Material(
      color: selected ? const Color(0xFFE9F2FF) : Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  CircleAvatar(
                    radius: 23,
                    backgroundColor: const Color(0xFFEAF2FF),
                    child: Icon(
                      Icons.devices_rounded,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                  Positioned(
                    left: -1,
                    bottom: -1,
                    child: Container(
                      width: 13,
                      height: 13,
                      decoration: BoxDecoration(
                        color: online ? const Color(0xFF20B26B) : const Color(0xFF98A2B3),
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 2),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(peer.name, maxLines: 1, overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontWeight: FontWeight.w800)),
                        ),
                        if (last != null)
                          Text(_formatListTime(last.sentAt),
                              style: const TextStyle(fontSize: 10, color: Color(0xFF98A2B3))),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      preview,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        color: last?.deliveryStatus == ChatDeliveryStatus.failed
                            ? const Color(0xFFC62828)
                            : const Color(0xFF667085),
                      ),
                    ),
                  ],
                ),
              ),
              PopupMenuButton<String>(
                tooltip: 'خيارات',
                onSelected: (value) { if (value == 'forget') onForget(); },
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'forget', child: Text('إلغاء ربط الجهاز')),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

''',
    'peer tile',
)

main = sub_once(
    main,
    r"class _ChatPaneState extends State<_ChatPane> \{.*?\n\}\n\n(?=class _ChatBubble)",
    r'''class _ChatPaneState extends State<_ChatPane> {
  final TextEditingController controller = TextEditingController();
  final ScrollController scrollController = ScrollController();
  bool pickingFiles = false;
  bool showJumpToLatest = false;
  int lastMessageCount = 0;

  @override
  void initState() {
    super.initState();
    controller.addListener(_refreshComposer);
    scrollController.addListener(_handleScroll);
  }

  @override
  void didUpdateWidget(covariant _ChatPane oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.peer.deviceId != widget.peer.deviceId) {
      controller.clear();
      lastMessageCount = 0;
      WidgetsBinding.instance.addPostFrameCallback((_) => _jumpToLatest());
    }
  }

  void _refreshComposer() {
    if (mounted) setState(() {});
  }

  void _handleScroll() {
    if (!scrollController.hasClients) return;
    final away = scrollController.position.maxScrollExtent - scrollController.offset > 180;
    if (away != showJumpToLatest && mounted) setState(() => showJumpToLatest = away);
  }

  void _jumpToLatest({bool animated = false}) {
    if (!scrollController.hasClients) return;
    final target = scrollController.position.maxScrollExtent;
    if (animated) {
      scrollController.animateTo(target, duration: const Duration(milliseconds: 220), curve: Curves.easeOut);
    } else {
      scrollController.jumpTo(target);
    }
  }

  @override
  void dispose() {
    controller.removeListener(_refreshComposer);
    scrollController.removeListener(_handleScroll);
    controller.dispose();
    scrollController.dispose();
    super.dispose();
  }

  Future<void> _sendText() async {
    final text = controller.text.trim();
    if (text.isEmpty) return;
    controller.clear();
    WidgetsBinding.instance.addPostFrameCallback((_) => _jumpToLatest(animated: true));
    try {
      await widget.service.sendChat(widget.peer, text);
    } catch (_) {
      // Failure is represented on the message itself with an explicit retry action.
    }
  }

  Future<void> _sendFiles() async {
    if (pickingFiles) return;
    setState(() => pickingFiles = true);
    try {
      await widget.service.pickAndSend(widget.peer);
      WidgetsBinding.instance.addPostFrameCallback((_) => _jumpToLatest(animated: true));
    } catch (e) {
      if (mounted) _showError(context, e);
    } finally {
      if (mounted) setState(() => pickingFiles = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final messages = widget.service.messagesFor(widget.peer.deviceId);
    final online = widget.service.isOnline(widget.peer.deviceId);
    if (messages.length != lastMessageCount) {
      final shouldFollow = !showJumpToLatest || lastMessageCount == 0;
      lastMessageCount = messages.length;
      if (shouldFollow) WidgetsBinding.instance.addPostFrameCallback((_) => _jumpToLatest(animated: true));
    }

    return ColoredBox(
      color: const Color(0xFFF2F5F9),
      child: Column(
        children: [
          _ChatHeader(peer: widget.peer, online: online, onBack: widget.onBack),
          Expanded(
            child: Stack(
              children: [
                if (messages.isEmpty)
                  const _EmptyChat()
                else
                  ListView.builder(
                    controller: scrollController,
                    padding: const EdgeInsets.fromLTRB(12, 14, 12, 18),
                    itemCount: messages.length,
                    itemBuilder: (context, index) {
                      final message = messages[index];
                      final previous = index > 0 ? messages[index - 1] : null;
                      final next = index + 1 < messages.length ? messages[index + 1] : null;
                      final showDay = previous == null || !_sameDay(previous.sentAt, message.sentAt);
                      final groupPrev = previous != null &&
                          _sameDay(previous.sentAt, message.sentAt) &&
                          previous.direction == message.direction &&
                          message.sentAt.difference(previous.sentAt).inMinutes.abs() <= 2;
                      final groupNext = next != null &&
                          _sameDay(next.sentAt, message.sentAt) &&
                          next.direction == message.direction &&
                          next.sentAt.difference(message.sentAt).inMinutes.abs() <= 2;
                      return Column(
                        children: [
                          if (showDay) _DayDivider(date: message.sentAt),
                          _ChatBubble(
                            service: widget.service,
                            peer: widget.peer,
                            message: message,
                            groupWithPrevious: groupPrev,
                            groupWithNext: groupNext,
                          ),
                        ],
                      );
                    },
                  ),
                if (showJumpToLatest)
                  Positioned(
                    left: 16,
                    bottom: 12,
                    child: FloatingActionButton.small(
                      heroTag: 'jump-${widget.peer.deviceId}',
                      tooltip: 'أحدث الرسائل',
                      onPressed: () => _jumpToLatest(animated: true),
                      child: const Icon(Icons.keyboard_arrow_down_rounded),
                    ),
                  ),
              ],
            ),
          ),
          _ChatComposer(
            controller: controller,
            pickingFiles: pickingFiles,
            onAttach: _sendFiles,
            onSend: _sendText,
          ),
        ],
      ),
    );
  }
}

class _ChatHeader extends StatelessWidget {
  const _ChatHeader({required this.peer, required this.online, this.onBack});
  final Peer peer;
  final bool online;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      elevation: 0.5,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Row(
            children: [
              if (onBack != null)
                IconButton(onPressed: onBack, tooltip: 'رجوع', icon: const Icon(Icons.arrow_forward_rounded)),
              Stack(
                clipBehavior: Clip.none,
                children: [
                  CircleAvatar(
                    radius: 21,
                    backgroundColor: const Color(0xFFEAF2FF),
                    child: Icon(Icons.devices_rounded, color: Theme.of(context).colorScheme.primary),
                  ),
                  Positioned(
                    left: -1,
                    bottom: -1,
                    child: Container(
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(
                        color: online ? const Color(0xFF20B26B) : const Color(0xFF98A2B3),
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 2),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(peer.name, maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                    Text(
                      online ? 'متصل • نقل محلي مشفّر' : 'غير متصل حاليًا',
                      style: TextStyle(fontSize: 11.5,
                          color: online ? const Color(0xFF128A50) : const Color(0xFF667085)),
                    ),
                  ],
                ),
              ),
              const Tooltip(
                message: 'المحتوى مشفّر ومصادق عليه بين الجهازين',
                child: Padding(
                  padding: EdgeInsets.all(10),
                  child: Icon(Icons.lock_outline_rounded, size: 20, color: Color(0xFF128A50)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ChatComposer extends StatelessWidget {
  const _ChatComposer({
    required this.controller,
    required this.pickingFiles,
    required this.onAttach,
    required this.onSend,
  });
  final TextEditingController controller;
  final bool pickingFiles;
  final VoidCallback onAttach;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    final hasText = controller.text.trim().isNotEmpty;
    return Material(
      color: Colors.white,
      elevation: 2,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Container(
                  constraints: const BoxConstraints(minHeight: 48),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF5F7FA),
                    borderRadius: BorderRadius.circular(25),
                    border: Border.all(color: const Color(0xFFE3E8EF)),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      IconButton(
                        tooltip: 'إرسال ملفات',
                        onPressed: pickingFiles ? null : onAttach,
                        icon: pickingFiles
                            ? const SizedBox(width: 19, height: 19, child: CircularProgressIndicator(strokeWidth: 2))
                            : const Icon(Icons.attach_file_rounded),
                      ),
                      Expanded(
                        child: TextField(
                          controller: controller,
                          minLines: 1,
                          maxLines: 6,
                          maxLength: 4096,
                          textInputAction: Platform.isWindows ? TextInputAction.send : TextInputAction.newline,
                          onSubmitted: Platform.isWindows ? (_) { if (hasText) onSend(); } : null,
                          decoration: const InputDecoration(
                            hintText: 'رسالة…',
                            filled: false,
                            counterText: '',
                            border: InputBorder.none,
                            enabledBorder: InputBorder.none,
                            focusedBorder: InputBorder.none,
                            contentPadding: EdgeInsets.symmetric(vertical: 13),
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              AnimatedScale(
                scale: hasText ? 1 : 0.92,
                duration: const Duration(milliseconds: 120),
                child: IconButton.filled(
                  tooltip: 'إرسال',
                  onPressed: hasText ? onSend : null,
                  icon: const Icon(Icons.send_rounded),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DayDivider extends StatelessWidget {
  const _DayDivider({required this.date});
  final DateTime date;
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.92),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFFE6EAF0)),
          ),
          child: Text(_formatDay(date), style: const TextStyle(fontSize: 10.5, color: Color(0xFF667085))),
        ),
      ),
    );
  }
}

''',
    'chat pane',
)

main = sub_once(
    main,
    r"class _ChatBubble extends StatelessWidget \{.*?\n\}\n\n(?=class _TextMessageContent)",
    r'''class _ChatBubble extends StatelessWidget {
  const _ChatBubble({
    required this.service,
    required this.peer,
    required this.message,
    required this.groupWithPrevious,
    required this.groupWithNext,
  });
  final LocalShareService service;
  final Peer peer;
  final ChatMessage message;
  final bool groupWithPrevious;
  final bool groupWithNext;

  @override
  Widget build(BuildContext context) {
    final mine = message.isMine;
    final bubbleColor = mine ? const Color(0xFFDDEBFF) : Colors.white;
    final foreground = const Color(0xFF182230);
    final topGap = groupWithPrevious ? 2.5 : 9.0;
    final radius = BorderRadius.only(
      topLeft: Radius.circular(!mine && groupWithPrevious ? 7 : 18),
      topRight: Radius.circular(mine && groupWithPrevious ? 7 : 18),
      bottomLeft: Radius.circular(!mine && groupWithNext ? 7 : 18),
      bottomRight: Radius.circular(mine && groupWithNext ? 7 : 18),
    );

    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: GestureDetector(
        onLongPress: () => _showMessageActions(context, service, peer, message),
        child: Container(
          constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width < 600 ? 320 : 520),
          margin: EdgeInsets.only(top: topGap),
          padding: const EdgeInsets.fromLTRB(11, 8, 11, 7),
          decoration: BoxDecoration(
            color: bubbleColor,
            borderRadius: radius,
            border: Border.all(color: mine ? const Color(0xFFC7DFFF) : const Color(0xFFE2E7EE)),
          ),
          child: message.kind == ChatMessageKind.file
              ? _FileMessageContent(service: service, peer: peer, message: message, foreground: foreground)
              : _TextMessageContent(service: service, peer: peer, message: message, foreground: foreground),
        ),
      ),
    );
  }
}

''',
    'chat bubble',
)

main = sub_once(
    main,
    r"class _TextMessageContent extends StatelessWidget \{.*?\n\}\n\n(?=class _FileMessageContent)",
    r'''class _TextMessageContent extends StatelessWidget {
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SelectableText(
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
                  const Icon(Icons.link_rounded, size: 19, color: Color(0xFF1769E0)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(_linkHost(message.text), maxLines: 1, overflow: TextOverflow.ellipsis,
                            textDirection: TextDirection.ltr,
                            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12.5)),
                        const SizedBox(height: 2),
                        Text('فتح الرابط', style: TextStyle(fontSize: 11, color: foreground.withValues(alpha: 0.62))),
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
      ],
    );
  }
}

''',
    'text message',
)

main = sub_once(
    main,
    r"class _FileMessageContent extends StatelessWidget \{.*?\n\}\n\n(?=class _NoChatSelected)",
    r'''class _FileMessageContent extends StatelessWidget {
  const _FileMessageContent({
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
    final incomingWindowsTemp = Platform.isWindows && message.isIncoming && message.temporary && !message.savedPermanently;
    final androidPermanent = Platform.isAndroid && message.isIncoming && message.savedPermanently;
    final transfer = service.transferForId(message.transferId);
    final running = transfer?.status == TransferStatus.running || message.deliveryStatus == ChatDeliveryStatus.sending;
    final progress = transfer?.progress ?? (message.deliveryStatus == ChatDeliveryStatus.delivered ? 1.0 : 0.0);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(color: const Color(0x141769E0), borderRadius: BorderRadius.circular(13)),
              child: Icon(_fileIcon(message.fileName), color: const Color(0xFF1769E0)),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(message.fileName ?? 'ملف', maxLines: 2, overflow: TextOverflow.ellipsis,
                      textDirection: _textDirectionFor(message.fileName ?? ''),
                      style: TextStyle(color: foreground, fontWeight: FontWeight.w800, fontSize: 13.5)),
                  const SizedBox(height: 2),
                  Text(
                    message.fileSize == null ? 'ملف' : formatBytes(message.fileSize!),
                    style: TextStyle(color: foreground.withValues(alpha: 0.62), fontSize: 11),
                  ),
                ],
              ),
            ),
            if (message.canRetry)
              IconButton(
                tooltip: 'إعادة الإرسال',
                onPressed: () async {
                  try { await service.retryMessage(peer, message); } catch (_) {}
                },
                icon: const Icon(Icons.refresh_rounded, color: Color(0xFFC62828)),
              )
            else if (message.isIncoming && message.canOpenFile)
              IconButton(
                tooltip: 'فتح الملف',
                onPressed: () => _openFile(context),
                icon: const Icon(Icons.open_in_new_rounded),
              ),
          ],
        ),
        if (running) ...[
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(value: progress.clamp(0.0, 1.0), minHeight: 4),
          ),
          const SizedBox(height: 4),
          Text('${(progress * 100).toStringAsFixed(0)}% • جارٍ النقل',
              style: const TextStyle(fontSize: 10.5, color: Color(0xFF667085))),
        ],
        if (incomingWindowsTemp && !running) ...[
          const SizedBox(height: 7),
          Row(
            children: [
              const Icon(Icons.schedule_rounded, size: 15, color: Color(0xFF8A5A00)),
              const SizedBox(width: 5),
              const Expanded(
                child: Text('مؤقت — يُحذف عند إغلاق LocalShare',
                    style: TextStyle(color: Color(0xFF8A5A00), fontSize: 10.5, fontWeight: FontWeight.w700)),
              ),
              TextButton(onPressed: () => _savePermanent(context), child: const Text('حفظ دائم')),
            ],
          ),
        ] else if (androidPermanent && !running) ...[
          const SizedBox(height: 6),
          const Row(
            children: [
              Icon(Icons.check_circle_outline_rounded, size: 15, color: Color(0xFF128A50)),
              SizedBox(width: 5),
              Expanded(
                child: Text('محفوظ في Downloads/LocalShare',
                    style: TextStyle(color: Color(0xFF128A50), fontSize: 10.5, fontWeight: FontWeight.w700)),
              ),
            ],
          ),
        ] else if (message.savedPermanently && message.isIncoming && !running) ...[
          const SizedBox(height: 6),
          const Text('محفوظ بشكل دائم',
              style: TextStyle(color: Color(0xFF128A50), fontSize: 10.5, fontWeight: FontWeight.w700)),
        ],
        if (message.deliveryStatus == ChatDeliveryStatus.failed && message.error != null) ...[
          const SizedBox(height: 5),
          Text('فشل الإرسال • اضغط إعادة المحاولة',
              style: const TextStyle(color: Color(0xFFC62828), fontSize: 10.5, fontWeight: FontWeight.w700)),
        ],
        const SizedBox(height: 4),
        _MessageMeta(message: message, foreground: foreground),
      ],
    );
  }

  Future<void> _openFile(BuildContext context) async {
    try { await service.openFile(message); } catch (e) { if (context.mounted) _showError(context, e); }
  }

  Future<void> _savePermanent(BuildContext context) async {
    try {
      final saved = await service.savePermanently(message);
      if (saved.isNotEmpty && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم حفظ الملف بشكل دائم')));
      }
    } catch (e) {
      if (context.mounted) _showError(context, e);
    }
  }
}

class _MessageMeta extends StatelessWidget {
  const _MessageMeta({required this.message, required this.foreground});
  final ChatMessage message;
  final Color foreground;

  @override
  Widget build(BuildContext context) {
    IconData? icon;
    Color? iconColor;
    if (message.isMine) {
      switch (message.deliveryStatus) {
        case ChatDeliveryStatus.sending:
          icon = Icons.schedule_rounded;
        case ChatDeliveryStatus.delivered:
          icon = Icons.done_all_rounded;
          iconColor = const Color(0xFF1769E0);
        case ChatDeliveryStatus.failed:
          icon = Icons.error_outline_rounded;
          iconColor = const Color(0xFFC62828);
      }
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(_formatTime(message.sentAt), style: TextStyle(color: foreground.withValues(alpha: 0.55), fontSize: 9.5)),
        if (icon != null) ...[
          const SizedBox(width: 4),
          Icon(icon, size: 13, color: iconColor ?? foreground.withValues(alpha: 0.5)),
        ],
      ],
    );
  }
}

''',
    'file message',
)

# Replace empty chat with quieter secure hint
main = sub_once(
    main,
    r"class _EmptyChat extends StatelessWidget \{.*?\n\}\n\n(?=class _InfoBox)",
    r'''class _EmptyChat extends StatelessWidget {
  const _EmptyChat();
  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.lock_outline_rounded, size: 34, color: Color(0xFF98A2B3)),
            SizedBox(height: 9),
            Text('اتصال محلي مشفّر', style: TextStyle(fontWeight: FontWeight.w800, color: Color(0xFF475467))),
            SizedBox(height: 4),
            Text('أرسل رسالة، رابطًا أو ملفًا', style: TextStyle(fontSize: 12, color: Color(0xFF98A2B3))),
          ],
        ),
      ),
    );
  }
}

''',
    'empty chat',
)

# Helpers before existing _formatTime
main = main.replace(
    "String _formatTime(DateTime time) {",
    r'''String _messagePreview(ChatMessage message) {
  if (message.deliveryStatus == ChatDeliveryStatus.failed) return 'تعذر الإرسال — اضغط لإعادة المحاولة';
  if (message.kind == ChatMessageKind.file) return '📎 ${message.fileName ?? 'ملف'}';
  if (message.kind == ChatMessageKind.link) return '🔗 ${_linkHost(message.text)}';
  final clean = message.text.replaceAll(RegExp(r'\s+'), ' ').trim();
  return clean.isEmpty ? 'رسالة' : clean;
}

TextDirection _textDirectionFor(String value) {
  final text = value.trimLeft();
  if (text.isEmpty) return TextDirection.rtl;
  final rtl = RegExp(r'[\u0600-\u06FF\u0750-\u077F\u08A0-\u08FF]');
  final latin = RegExp(r'[A-Za-z0-9]');
  final rtlMatch = rtl.firstMatch(text);
  final latinMatch = latin.firstMatch(text);
  if (rtlMatch == null) return TextDirection.ltr;
  if (latinMatch == null) return TextDirection.rtl;
  return rtlMatch.start <= latinMatch.start ? TextDirection.rtl : TextDirection.ltr;
}

bool _sameDay(DateTime a, DateTime b) {
  final x = a.toLocal();
  final y = b.toLocal();
  return x.year == y.year && x.month == y.month && x.day == y.day;
}

String _formatDay(DateTime time) {
  final d = time.toLocal();
  final now = DateTime.now();
  if (_sameDay(d, now)) return 'اليوم';
  if (_sameDay(d, now.subtract(const Duration(days: 1)))) return 'أمس';
  return '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
}

String _formatListTime(DateTime time) {
  if (_sameDay(time, DateTime.now())) return _formatTime(time);
  final d = time.toLocal();
  return '${d.day}/${d.month}';
}

String _linkHost(String raw) {
  final uri = Uri.tryParse(raw.trim());
  return uri?.host.isNotEmpty == true ? uri!.host : 'رابط';
}

IconData _fileIcon(String? name) {
  final lower = (name ?? '').toLowerCase();
  if (RegExp(r'\.(jpg|jpeg|png|gif|webp|bmp)$').hasMatch(lower)) return Icons.image_outlined;
  if (RegExp(r'\.(mp4|mov|mkv|avi|webm)$').hasMatch(lower)) return Icons.movie_outlined;
  if (RegExp(r'\.(mp3|wav|m4a|aac|flac)$').hasMatch(lower)) return Icons.audio_file_outlined;
  if (lower.endsWith('.pdf')) return Icons.picture_as_pdf_outlined;
  if (RegExp(r'\.(zip|rar|7z|tar|gz)$').hasMatch(lower)) return Icons.folder_zip_outlined;
  return Icons.insert_drive_file_outlined;
}

Future<void> _confirmAndOpenLink(BuildContext context, LocalShareService service, String url) async {
  final host = _linkHost(url);
  final ok = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('فتح رابط خارجي؟'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('سيتم فتح الرابط في المتصفح الافتراضي.'),
          const SizedBox(height: 10),
          SelectableText(host, textDirection: TextDirection.ltr,
              style: const TextStyle(fontWeight: FontWeight.w800)),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('إلغاء')),
        FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('فتح')),
      ],
    ),
  );
  if (ok == true) {
    try { await service.openLink(url); } catch (e) { if (context.mounted) _showError(context, e); }
  }
}

Future<void> _showMessageActions(
  BuildContext context,
  LocalShareService service,
  Peer peer,
  ChatMessage message,
) async {
  final action = await showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    builder: (context) => SafeArea(
      child: Wrap(
        children: [
          if (!message.isFile)
            ListTile(
              leading: const Icon(Icons.copy_rounded),
              title: const Text('نسخ'),
              onTap: () => Navigator.pop(context, 'copy'),
            ),
          if (message.kind == ChatMessageKind.link)
            ListTile(
              leading: const Icon(Icons.open_in_new_rounded),
              title: const Text('فتح الرابط'),
              onTap: () => Navigator.pop(context, 'open'),
            ),
          if (message.canRetry)
            ListTile(
              leading: const Icon(Icons.refresh_rounded),
              title: const Text('إعادة المحاولة'),
              onTap: () => Navigator.pop(context, 'retry'),
            ),
        ],
      ),
    ),
  );
  if (!context.mounted || action == null) return;
  if (action == 'copy') {
    await Clipboard.setData(ClipboardData(text: message.text));
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم النسخ')));
    }
  } else if (action == 'open') {
    await _confirmAndOpenLink(context, service, message.text);
  } else if (action == 'retry') {
    try { await service.retryMessage(peer, message); } catch (_) {}
  }
}

String _formatTime(DateTime time) {''',
    1,
)

main_path.write_text(main, encoding='utf-8')
service_path.write_text(service, encoding='utf-8')
print('Applied LocalShare chat UX v4 patch')
