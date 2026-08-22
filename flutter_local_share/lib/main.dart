import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'local_share_service.dart';
import 'models.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const LocalShareApp());
}

class LocalShareApp extends StatelessWidget {
  const LocalShareApp({super.key});

  @override
  Widget build(BuildContext context) {
    const seed = Color(0xFF1769E0);
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'LocalShare',
      locale: const Locale('ar'),
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: seed),
        scaffoldBackgroundColor: const Color(0xFFF5F7FB),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: const BorderSide(color: Color(0xFFE2E7F0)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: const BorderSide(color: seed, width: 1.5),
          ),
        ),
      ),
      home: const Directionality(
        textDirection: TextDirection.rtl,
        child: LocalShareShell(),
      ),
    );
  }
}

class LocalShareShell extends StatefulWidget {
  const LocalShareShell({super.key});

  @override
  State<LocalShareShell> createState() => _LocalShareShellState();
}

class _LocalShareShellState extends State<LocalShareShell> {
  late final LocalShareService service;
  String? selectedPeerId;

  @override
  void initState() {
    super.initState();
    service = LocalShareService();
    service.init();
  }

  @override
  void dispose() {
    service.dispose();
    super.dispose();
  }

  Peer? get selectedPeer {
    final id = selectedPeerId;
    if (id == null) return null;
    return service.peerFor(id);
  }

  void _selectPeer(Peer peer) {
    setState(() => selectedPeerId = peer.deviceId);
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: service,
      builder: (context, _) {
        if (!service.initialized) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }
        if (service.startupError != null) {
          return Scaffold(
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 560),
                  child: _ErrorCard(message: service.startupError!),
                ),
              ),
            ),
          );
        }

        final width = MediaQuery.sizeOf(context).width;
        final wide = width >= 860;
        final peer = selectedPeer;

        return Scaffold(
          appBar: AppBar(
            backgroundColor: Colors.white,
            surfaceTintColor: Colors.white,
            titleSpacing: 16,
            title: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _AppMark(),
                SizedBox(width: 10),
                Text('LocalShare', style: TextStyle(fontWeight: FontWeight.w800)),
              ],
            ),
            actions: [
              IconButton(
                tooltip: 'تعديل اسم الجهاز',
                onPressed: () => _showDeviceNameDialog(context, service),
                icon: const Icon(Icons.edit_outlined),
              ),
              IconButton(
                tooltip: 'ربط يدوي عبر IP',
                onPressed: () => _showManualIpDialog(context, service),
                icon: const Icon(Icons.add_link_rounded),
              ),
              const SizedBox(width: 8),
            ],
          ),
          body: wide
              ? Row(
                  children: [
                    SizedBox(
                      width: 360,
                      child: _DevicesPane(
                        service: service,
                        selectedPeerId: selectedPeerId,
                        onPeerSelected: _selectPeer,
                      ),
                    ),
                    const VerticalDivider(width: 1),
                    Expanded(
                      child: peer == null
                          ? const _NoChatSelected()
                          : _ChatPane(service: service, peer: peer),
                    ),
                  ],
                )
              : peer == null
                  ? _DevicesPane(
                      service: service,
                      selectedPeerId: selectedPeerId,
                      onPeerSelected: _selectPeer,
                    )
                  : _ChatPane(
                      service: service,
                      peer: peer,
                      onBack: () => setState(() => selectedPeerId = null),
                    ),
        );
      },
    );
  }
}

class _DevicesPane extends StatelessWidget {
  const _DevicesPane({
    required this.service,
    required this.selectedPeerId,
    required this.onPeerSelected,
  });

  final LocalShareService service;
  final String? selectedPeerId;
  final ValueChanged<Peer> onPeerSelected;

  @override
  Widget build(BuildContext context) {
    final paired = service.pairedPeers;
    final discoveredUnpaired = service.discoveredDevices
        .where((device) => service.peerFor(device.deviceId) == null)
        .toList();

    return ColoredBox(
      color: const Color(0xFFF8FAFD),
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _MyDeviceCard(service: service),
          const SizedBox(height: 22),
          Row(
            children: [
              const Expanded(
                child: Text(
                  'الأجهزة المرتبطة',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: const Color(0xFFE3E8F0)),
                ),
                child: Text('${paired.length}'),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (paired.isEmpty)
            const _InfoBox(
              icon: Icons.devices_other_rounded,
              text: 'اربط الهاتف والكمبيوتر مرة واحدة، ثم افتح المحادثة لإرسال النصوص والروابط والملفات.',
            )
          else
            ...paired.map(
              (peer) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _PeerTile(
                  peer: peer,
                  online: service.isOnline(peer.deviceId),
                  selected: selectedPeerId == peer.deviceId,
                  onTap: () => onPeerSelected(peer),
                  onForget: () => _confirmForget(context, service, peer),
                ),
              ),
            ),
          const SizedBox(height: 18),
          Row(
            children: [
              const Expanded(
                child: Text(
                  'أجهزة قريبة جديدة',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
                ),
              ),
              if (!service.discoveryAvailable)
                const Tooltip(
                  message: 'الاكتشاف التلقائي غير متاح؛ استخدم الربط اليدوي',
                  child: Icon(Icons.info_outline_rounded, size: 20),
                ),
            ],
          ),
          const SizedBox(height: 10),
          if (discoveredUnpaired.isEmpty)
            const Text(
              'لا توجد أجهزة جديدة حاليًا على نفس شبكة Wi‑Fi.',
              style: TextStyle(color: Color(0xFF667085)),
            )
          else
            ...discoveredUnpaired.map(
              (device) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _DiscoveredTile(
                  device: device,
                  onPair: () => _showPairDialog(context, service, device, onPeerSelected),
                ),
              ),
            ),
          const SizedBox(height: 22),
          _InfoBox(
            icon: Platform.isAndroid
                ? Icons.phone_android_rounded
                : Icons.laptop_windows_rounded,
            text: service.receivePolicyLabel,
          ),
        ],
      ),
    );
  }
}

class _MyDeviceCard extends StatelessWidget {
  const _MyDeviceCard({required this.service});
  final LocalShareService service;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF0D5BD7), Color(0xFF16A6D9)],
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
        ),
        borderRadius: BorderRadius.circular(22),
        boxShadow: const [
          BoxShadow(
            color: Color(0x1F0D5BD7),
            blurRadius: 24,
            offset: Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.shield_rounded, color: Colors.white),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  service.deviceName,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                  ),
                ),
              ),
              Text(
                service.localIp,
                textDirection: TextDirection.ltr,
                style: const TextStyle(color: Color(0xFFDCEEFF), fontSize: 12),
              ),
            ],
          ),
          const SizedBox(height: 15),
          const Text(
            'رمز الربط',
            style: TextStyle(color: Color(0xFFDCEEFF), fontSize: 12),
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              SelectableText(
                service.pairCode,
                textDirection: TextDirection.ltr,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                  fontSize: 28,
                  letterSpacing: 3,
                ),
              ),
              const SizedBox(width: 10),
              IconButton.filledTonal(
                tooltip: 'نسخ الرمز',
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: service.pairCode));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('تم نسخ رمز الربط')),
                  );
                },
                icon: const Icon(Icons.copy_rounded, size: 18),
              ),
            ],
          ),
          const SizedBox(height: 6),
          const Text(
            'اكتب هذا الرمز في الجهاز الآخر. يتغير تلقائيًا كل 5 دقائق.',
            style: TextStyle(color: Color(0xFFDCEEFF), fontSize: 11),
          ),
        ],
      ),
    );
  }
}

class _PeerTile extends StatelessWidget {
  const _PeerTile({
    required this.peer,
    required this.online,
    required this.selected,
    required this.onTap,
    required this.onForget,
  });

  final Peer peer;
  final bool online;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onForget;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? const Color(0xFFEAF2FF) : Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
          child: Row(
            children: [
              CircleAvatar(
                backgroundColor: online
                    ? const Color(0xFFE6F8EF)
                    : const Color(0xFFF0F2F5),
                child: Icon(
                  Platform.isAndroid ? Icons.phone_android_rounded : Icons.devices_rounded,
                  color: online ? const Color(0xFF128A50) : const Color(0xFF667085),
                ),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(peer.name, style: const TextStyle(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 2),
                    Text(
                      online ? 'متصل الآن' : 'غير ظاهر حاليًا',
                      style: TextStyle(
                        fontSize: 12,
                        color: online ? const Color(0xFF128A50) : const Color(0xFF667085),
                      ),
                    ),
                  ],
                ),
              ),
              PopupMenuButton<String>(
                tooltip: 'خيارات',
                onSelected: (value) {
                  if (value == 'forget') onForget();
                },
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

class _DiscoveredTile extends StatelessWidget {
  const _DiscoveredTile({required this.device, required this.onPair});
  final DiscoveredDevice device;
  final VoidCallback onPair;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE4E8F0)),
      ),
      child: Row(
        children: [
          const CircleAvatar(child: Icon(Icons.devices_rounded)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(device.name, style: const TextStyle(fontWeight: FontWeight.w700)),
                Text(
                  device.ip,
                  textDirection: TextDirection.ltr,
                  style: const TextStyle(fontSize: 11, color: Color(0xFF667085)),
                ),
              ],
            ),
          ),
          FilledButton.tonal(onPressed: onPair, child: const Text('ربط')),
        ],
      ),
    );
  }
}

class _ChatPane extends StatefulWidget {
  const _ChatPane({required this.service, required this.peer, this.onBack});

  final LocalShareService service;
  final Peer peer;
  final VoidCallback? onBack;

  @override
  State<_ChatPane> createState() => _ChatPaneState();
}

class _ChatPaneState extends State<_ChatPane> {
  final TextEditingController controller = TextEditingController();
  bool sending = false;

  @override
  void didUpdateWidget(covariant _ChatPane oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.peer.deviceId != widget.peer.deviceId) controller.clear();
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  Future<void> _sendText() async {
    final text = controller.text.trim();
    if (text.isEmpty || sending) return;
    setState(() => sending = true);
    try {
      await widget.service.sendChat(widget.peer, text);
      controller.clear();
    } catch (e) {
      if (mounted) _showError(context, e);
    } finally {
      if (mounted) setState(() => sending = false);
    }
  }

  Future<void> _sendFiles() async {
    if (sending) return;
    setState(() => sending = true);
    try {
      await widget.service.pickAndSend(widget.peer);
    } catch (e) {
      if (mounted) _showError(context, e);
    } finally {
      if (mounted) setState(() => sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final messages = widget.service.messagesFor(widget.peer.deviceId).reversed.toList();
    final online = widget.service.isOnline(widget.peer.deviceId);
    final activeTransfers = widget.service.transfers
        .where((item) => item.status == TransferStatus.running)
        .toList();

    return Column(
      children: [
        Container(
          color: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              if (widget.onBack != null)
                IconButton(onPressed: widget.onBack, icon: const Icon(Icons.arrow_forward_rounded)),
              CircleAvatar(
                backgroundColor: online ? const Color(0xFFE6F8EF) : const Color(0xFFF0F2F5),
                child: Icon(
                  Icons.devices_rounded,
                  color: online ? const Color(0xFF128A50) : const Color(0xFF667085),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(widget.peer.name, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                    Text(
                      online ? 'اتصال محلي مشفّر • متصل' : 'اتصال محلي مشفّر • بانتظار الجهاز',
                      style: const TextStyle(fontSize: 12, color: Color(0xFF667085)),
                    ),
                  ],
                ),
              ),
              const Tooltip(
                message: 'الرسائل والملفات مشفّرة بين الجهازين',
                child: Icon(Icons.lock_rounded, color: Color(0xFF128A50)),
              ),
            ],
          ),
        ),
        if (activeTransfers.isNotEmpty)
          Container(
            color: const Color(0xFFEAF2FF),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'جارٍ نقل ${activeTransfers.first.fileName} • ${(activeTransfers.first.progress * 100).toStringAsFixed(0)}%',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
          ),
        Expanded(
          child: messages.isEmpty
              ? const _EmptyChat()
              : ListView.builder(
                  reverse: true,
                  padding: const EdgeInsets.fromLTRB(14, 18, 14, 18),
                  itemCount: messages.length,
                  itemBuilder: (context, index) => _ChatBubble(
                    service: widget.service,
                    message: messages[index],
                  ),
                ),
        ),
        Container(
          color: Colors.white,
          padding: EdgeInsets.fromLTRB(
            12,
            10,
            12,
            10 + MediaQuery.viewInsetsOf(context).bottom,
          ),
          child: SafeArea(
            top: false,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                IconButton.filledTonal(
                  tooltip: 'إرسال ملف',
                  onPressed: sending ? null : _sendFiles,
                  icon: const Icon(Icons.attach_file_rounded),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: controller,
                    minLines: 1,
                    maxLines: 5,
                    maxLength: 4096,
                    textInputAction: TextInputAction.newline,
                    decoration: const InputDecoration(
                      hintText: 'اكتب رسالة أو الصق رابطًا…',
                      counterText: '',
                      contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filled(
                  tooltip: 'إرسال',
                  onPressed: sending ? null : _sendText,
                  icon: sending
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.send_rounded),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _ChatBubble extends StatelessWidget {
  const _ChatBubble({required this.service, required this.message});
  final LocalShareService service;
  final ChatMessage message;

  @override
  Widget build(BuildContext context) {
    final mine = message.direction == ChatMessageDirection.send;
    final align = mine ? Alignment.centerRight : Alignment.centerLeft;
    final bubbleColor = mine ? const Color(0xFF1769E0) : Colors.white;
    final foreground = mine ? Colors.white : const Color(0xFF182230);

    return Align(
      alignment: align,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 560),
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: bubbleColor,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(18),
            topRight: const Radius.circular(18),
            bottomLeft: Radius.circular(mine ? 18 : 5),
            bottomRight: Radius.circular(mine ? 5 : 18),
          ),
          border: mine ? null : Border.all(color: const Color(0xFFE3E8F0)),
        ),
        child: message.kind == ChatMessageKind.file
            ? _FileMessageContent(service: service, message: message, foreground: foreground)
            : _TextMessageContent(service: service, message: message, foreground: foreground),
      ),
    );
  }
}

class _TextMessageContent extends StatelessWidget {
  const _TextMessageContent({
    required this.service,
    required this.message,
    required this.foreground,
  });

  final LocalShareService service;
  final ChatMessage message;
  final Color foreground;

  @override
  Widget build(BuildContext context) {
    final isLink = message.kind == ChatMessageKind.link;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SelectableText(
          message.text,
          textDirection: TextDirection.rtl,
          style: TextStyle(color: foreground, height: 1.45),
        ),
        if (isLink) ...[
          const SizedBox(height: 8),
          TextButton.icon(
            style: TextButton.styleFrom(
              foregroundColor: foreground,
              padding: EdgeInsets.zero,
              visualDensity: VisualDensity.compact,
            ),
            onPressed: () async {
              try {
                await service.openLink(message.text);
              } catch (e) {
                if (context.mounted) _showError(context, e);
              }
            },
            icon: const Icon(Icons.open_in_new_rounded, size: 17),
            label: const Text('فتح الرابط'),
          ),
        ],
        const SizedBox(height: 5),
        Text(
          _formatTime(message.sentAt),
          style: TextStyle(color: foreground.withValues(alpha: 0.68), fontSize: 10),
        ),
      ],
    );
  }
}

class _FileMessageContent extends StatelessWidget {
  const _FileMessageContent({
    required this.service,
    required this.message,
    required this.foreground,
  });

  final LocalShareService service;
  final ChatMessage message;
  final Color foreground;

  @override
  Widget build(BuildContext context) {
    final incomingWindowsTemp = Platform.isWindows &&
        message.isIncoming &&
        message.temporary &&
        !message.savedPermanently;
    final androidPermanent = Platform.isAndroid && message.isIncoming && message.savedPermanently;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: foreground.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(Icons.insert_drive_file_rounded, color: foreground),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    message.fileName ?? 'ملف',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: foreground, fontWeight: FontWeight.w800),
                  ),
                  if (message.fileSize != null)
                    Text(
                      formatBytes(message.fileSize!),
                      style: TextStyle(color: foreground.withValues(alpha: 0.72), fontSize: 11),
                    ),
                ],
              ),
            ),
          ],
        ),
        if (incomingWindowsTemp) ...[
          const SizedBox(height: 9),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF1D6),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Text(
              'مؤقت • يُحذف عند إغلاق LocalShare',
              style: TextStyle(color: Color(0xFF8A5A00), fontSize: 11, fontWeight: FontWeight.w700),
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              OutlinedButton.icon(
                onPressed: () => _openFile(context),
                icon: const Icon(Icons.visibility_outlined, size: 17),
                label: const Text('عرض مؤقت'),
              ),
              FilledButton.tonalIcon(
                onPressed: () => _savePermanent(context),
                icon: const Icon(Icons.download_done_rounded, size: 17),
                label: const Text('حفظ دائم'),
              ),
            ],
          ),
        ] else if (androidPermanent) ...[
          const SizedBox(height: 9),
          const Text(
            'تم الحفظ تلقائيًا في Downloads/LocalShare',
            style: TextStyle(color: Color(0xFF128A50), fontSize: 11, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          TextButton.icon(
            onPressed: () => _openFile(context),
            icon: const Icon(Icons.open_in_new_rounded, size: 17),
            label: const Text('فتح الملف'),
          ),
        ] else if (message.savedPermanently && message.isIncoming) ...[
          const SizedBox(height: 8),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.check_circle_rounded, size: 16, color: Color(0xFF128A50)),
              const SizedBox(width: 5),
              const Text(
                'محفوظ بشكل دائم',
                style: TextStyle(color: Color(0xFF128A50), fontSize: 11, fontWeight: FontWeight.w700),
              ),
              const SizedBox(width: 8),
              TextButton(onPressed: () => _openFile(context), child: const Text('فتح')),
            ],
          ),
        ],
        const SizedBox(height: 5),
        Text(
          _formatTime(message.sentAt),
          style: TextStyle(color: foreground.withValues(alpha: 0.68), fontSize: 10),
        ),
      ],
    );
  }

  Future<void> _openFile(BuildContext context) async {
    try {
      await service.openFile(message);
    } catch (e) {
      if (context.mounted) _showError(context, e);
    }
  }

  Future<void> _savePermanent(BuildContext context) async {
    try {
      final saved = await service.savePermanently(message);
      if (saved.isNotEmpty && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('تم الحفظ بشكل دائم: $saved')),
        );
      }
    } catch (e) {
      if (context.mounted) _showError(context, e);
    }
  }
}

class _NoChatSelected extends StatelessWidget {
  const _NoChatSelected();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.chat_bubble_outline_rounded, size: 70, color: Color(0xFF9AA4B2)),
            SizedBox(height: 14),
            Text('اختر جهازًا لفتح المحادثة', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
            SizedBox(height: 7),
            Text(
              'أرسل نصوصًا وروابط وملفات مباشرة عبر الشبكة المحلية.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Color(0xFF667085)),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyChat extends StatelessWidget {
  const _EmptyChat();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.lock_person_outlined, size: 58, color: Color(0xFF8A94A6)),
            SizedBox(height: 12),
            Text('ابدأ المحادثة الآمنة', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
            SizedBox(height: 6),
            Text(
              'اكتب رسالة أو رابطًا، أو استخدم زر المشبك لإرسال الملفات.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Color(0xFF667085)),
            ),
          ],
        ),
      ),
    );
  }
}

class _InfoBox extends StatelessWidget {
  const _InfoBox({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF0F5FF),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: const Color(0xFF1769E0)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(fontSize: 12, color: Color(0xFF344054), height: 1.4),
            ),
          ),
        ],
      ),
    );
  }
}

class _AppMark extends StatelessWidget {
  const _AppMark();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 38,
      height: 38,
      decoration: BoxDecoration(
        gradient: const LinearGradient(colors: [Color(0xFF0D5BD7), Color(0xFF17B4D9)]),
        borderRadius: BorderRadius.circular(12),
      ),
      child: const Icon(Icons.swap_horiz_rounded, color: Colors.white),
    );
  }
}

class _ErrorCard extends StatelessWidget {
  const _ErrorCard({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFFFD3D0)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error_outline_rounded, color: Color(0xFFC62828), size: 42),
          const SizedBox(height: 10),
          const Text('تعذر تشغيل LocalShare', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
          const SizedBox(height: 8),
          SelectableText(message, textAlign: TextAlign.center),
        ],
      ),
    );
  }
}

Future<void> _showPairDialog(
  BuildContext context,
  LocalShareService service,
  DiscoveredDevice device,
  ValueChanged<Peer> onPaired,
) async {
  final controller = TextEditingController();
  var busy = false;
  await showDialog<void>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: Text('ربط مع ${device.name}'),
        content: SizedBox(
          width: 360,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('أدخل رمز الربط المكوّن من 6 أرقام الظاهر على الجهاز الآخر.'),
              const SizedBox(height: 14),
              TextField(
                controller: controller,
                autofocus: true,
                keyboardType: TextInputType.number,
                maxLength: 6,
                textDirection: TextDirection.ltr,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: const InputDecoration(labelText: 'رمز الربط', counterText: ''),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: busy ? null : () => Navigator.pop(context), child: const Text('إلغاء')),
          FilledButton(
            onPressed: busy
                ? null
                : () async {
                    setState(() => busy = true);
                    try {
                      final peer = await service.pairDevice(device, controller.text);
                      if (context.mounted) Navigator.pop(context);
                      onPaired(peer);
                    } catch (e) {
                      if (context.mounted) _showError(context, e);
                      setState(() => busy = false);
                    }
                  },
            child: busy
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('ربط'),
          ),
        ],
      ),
    ),
  );
  controller.dispose();
}

Future<void> _showManualIpDialog(BuildContext context, LocalShareService service) async {
  final controller = TextEditingController();
  await showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('البحث بعنوان IP'),
      content: SizedBox(
        width: 380,
        child: TextField(
          controller: controller,
          autofocus: true,
          textDirection: TextDirection.ltr,
          decoration: const InputDecoration(
            labelText: 'عنوان IP المحلي',
            hintText: '192.168.1.20',
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('إلغاء')),
        FilledButton(
          onPressed: () async {
            try {
              await service.probeIp(controller.text);
              if (context.mounted) Navigator.pop(context);
            } catch (e) {
              if (context.mounted) _showError(context, e);
            }
          },
          child: const Text('بحث'),
        ),
      ],
    ),
  );
  controller.dispose();
}

Future<void> _showDeviceNameDialog(BuildContext context, LocalShareService service) async {
  final controller = TextEditingController(text: service.deviceName);
  await showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('اسم هذا الجهاز'),
      content: SizedBox(
        width: 380,
        child: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 32,
          decoration: const InputDecoration(labelText: 'اسم الجهاز'),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('إلغاء')),
        FilledButton(
          onPressed: () async {
            await service.setDeviceName(controller.text);
            if (context.mounted) Navigator.pop(context);
          },
          child: const Text('حفظ'),
        ),
      ],
    ),
  );
  controller.dispose();
}

Future<void> _confirmForget(
  BuildContext context,
  LocalShareService service,
  Peer peer,
) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('إلغاء ربط الجهاز؟'),
      content: Text('سيحتاج ${peer.name} إلى رمز ربط جديد للاتصال مرة أخرى.'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('إلغاء')),
        FilledButton.tonal(
          onPressed: () => Navigator.pop(context, true),
          child: const Text('إلغاء الربط'),
        ),
      ],
    ),
  );
  if (confirmed == true) await service.forgetPeer(peer.deviceId);
}

void _showError(BuildContext context, Object error) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(error.toString().replaceFirst('Exception: ', '')),
      behavior: SnackBarBehavior.floating,
    ),
  );
}

String _formatTime(DateTime time) {
  final local = time.toLocal();
  final hour = local.hour.toString().padLeft(2, '0');
  final minute = local.minute.toString().padLeft(2, '0');
  return '$hour:$minute';
}
