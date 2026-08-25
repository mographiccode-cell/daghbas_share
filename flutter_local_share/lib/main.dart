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
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
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
          appBar: (!wide && peer != null)
              ? null
              : AppBar(
                  backgroundColor: Colors.white,
                  surfaceTintColor: Colors.white,
                  titleSpacing: 16,
                  title: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _AppMark(),
                      SizedBox(width: 10),
                      Text(
                        'LocalShare',
                        style: TextStyle(fontWeight: FontWeight.w800),
                      ),
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
              text:
                  'اربط الهاتف والكمبيوتر مرة واحدة، ثم افتح المحادثة لإرسال النصوص والروابط والملفات.',
            )
          else
            ...paired.map(
              (peer) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _PeerTile(
                  service: service,
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
                  onPair: () =>
                      _showPairDialog(context, service, device, onPeerSelected),
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
                        color: online
                            ? const Color(0xFF20B26B)
                            : const Color(0xFF98A2B3),
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
                          child: Text(
                            peer.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w800),
                          ),
                        ),
                        if (last != null)
                          Text(
                            _formatListTime(last.sentAt),
                            style: const TextStyle(
                              fontSize: 10,
                              color: Color(0xFF98A2B3),
                            ),
                          ),
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
                onSelected: (value) {
                  if (value == 'forget') onForget();
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(
                    value: 'forget',
                    child: Text('إلغاء ربط الجهاز'),
                  ),
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
                Text(
                  device.name,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                Text(
                  device.ip,
                  textDirection: TextDirection.ltr,
                  style: const TextStyle(
                    fontSize: 11,
                    color: Color(0xFF667085),
                  ),
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
    final away =
        scrollController.position.maxScrollExtent - scrollController.offset >
        180;
    if (away != showJumpToLatest && mounted)
      setState(() => showJumpToLatest = away);
  }

  void _jumpToLatest({bool animated = false}) {
    if (!scrollController.hasClients) return;
    final target = scrollController.position.maxScrollExtent;
    if (animated) {
      scrollController.animateTo(
        target,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
      );
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
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _jumpToLatest(animated: true),
    );
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
    final messages = widget.service.messagesFor(widget.peer.deviceId);
    final online = widget.service.isOnline(widget.peer.deviceId);
    if (messages.length != lastMessageCount) {
      final shouldFollow = !showJumpToLatest || lastMessageCount == 0;
      lastMessageCount = messages.length;
      if (shouldFollow)
        WidgetsBinding.instance.addPostFrameCallback(
          (_) => _jumpToLatest(animated: true),
        );
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
                      final next = index + 1 < messages.length
                          ? messages[index + 1]
                          : null;
                      final showDay =
                          previous == null ||
                          !_sameDay(previous.sentAt, message.sentAt);
                      final groupPrev =
                          previous != null &&
                          _sameDay(previous.sentAt, message.sentAt) &&
                          previous.direction == message.direction &&
                          message.sentAt
                                  .difference(previous.sentAt)
                                  .inMinutes
                                  .abs() <=
                              2;
                      final groupNext =
                          next != null &&
                          _sameDay(next.sentAt, message.sentAt) &&
                          next.direction == message.direction &&
                          next.sentAt
                                  .difference(message.sentAt)
                                  .inMinutes
                                  .abs() <=
                              2;
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
                IconButton(
                  onPressed: onBack,
                  tooltip: 'رجوع',
                  icon: const Icon(Icons.arrow_forward_rounded),
                ),
              Stack(
                clipBehavior: Clip.none,
                children: [
                  CircleAvatar(
                    radius: 21,
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
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(
                        color: online
                            ? const Color(0xFF20B26B)
                            : const Color(0xFF98A2B3),
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
                    Text(
                      peer.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(
                      online ? 'متصل • نقل محلي مشفّر' : 'غير متصل حاليًا',
                      style: TextStyle(
                        fontSize: 11.5,
                        color: online
                            ? const Color(0xFF128A50)
                            : const Color(0xFF667085),
                      ),
                    ),
                  ],
                ),
              ),
              const Tooltip(
                message: 'المحتوى مشفّر ومصادق عليه بين الجهازين',
                child: Padding(
                  padding: EdgeInsets.all(10),
                  child: Icon(
                    Icons.lock_outline_rounded,
                    size: 20,
                    color: Color(0xFF128A50),
                  ),
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
                        child: TextField(
                          controller: controller,
                          minLines: 1,
                          maxLines: 6,
                          maxLength: 4096,
                          textInputAction: Platform.isWindows
                              ? TextInputAction.send
                              : TextInputAction.newline,
                          onSubmitted: Platform.isWindows
                              ? (_) {
                                  if (hasText) onSend();
                                }
                              : null,
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
          child: Text(
            _formatDay(date),
            style: const TextStyle(fontSize: 10.5, color: Color(0xFF667085)),
          ),
        ),
      ),
    );
  }
}

class _ChatBubble extends StatelessWidget {
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
          constraints: BoxConstraints(
            maxWidth: MediaQuery.sizeOf(context).width < 600 ? 320 : 520,
          ),
          margin: EdgeInsets.only(top: topGap),
          padding: const EdgeInsets.fromLTRB(11, 8, 11, 7),
          decoration: BoxDecoration(
            color: bubbleColor,
            borderRadius: radius,
            border: Border.all(
              color: mine ? const Color(0xFFC7DFFF) : const Color(0xFFE2E7EE),
            ),
          ),
          child: message.kind == ChatMessageKind.file
              ? _FileMessageContent(
                  service: service,
                  peer: peer,
                  message: message,
                  foreground: foreground,
                )
              : _TextMessageContent(
                  service: service,
                  peer: peer,
                  message: message,
                  foreground: foreground,
                ),
        ),
      ),
    );
  }
}

class _TextMessageContent extends StatelessWidget {
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
      ],
    );
  }
}

class _FileMessageContent extends StatelessWidget {
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
    final incomingWindowsTemp =
        Platform.isWindows &&
        message.isIncoming &&
        message.temporary &&
        !message.savedPermanently;
    final androidPermanent =
        Platform.isAndroid && message.isIncoming && message.savedPermanently;
    final transfer = service.transferForId(message.transferId);
    final running =
        transfer?.status == TransferStatus.running ||
        message.deliveryStatus == ChatDeliveryStatus.sending;
    final progress =
        transfer?.progress ??
        (message.deliveryStatus == ChatDeliveryStatus.delivered ? 1.0 : 0.0);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: const Color(0x141769E0),
                borderRadius: BorderRadius.circular(13),
              ),
              child: Icon(
                _fileIcon(message.fileName),
                color: const Color(0xFF1769E0),
              ),
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
                    textDirection: _textDirectionFor(message.fileName ?? ''),
                    style: TextStyle(
                      color: foreground,
                      fontWeight: FontWeight.w800,
                      fontSize: 13.5,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    message.fileSize == null
                        ? 'ملف'
                        : formatBytes(message.fileSize!),
                    style: TextStyle(
                      color: foreground.withValues(alpha: 0.62),
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
            if (message.canRetry)
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
          ],
        ),
        if (running) ...[
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: progress.clamp(0.0, 1.0),
              minHeight: 4,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '${(progress * 100).toStringAsFixed(0)}% • جارٍ النقل',
            style: const TextStyle(fontSize: 10.5, color: Color(0xFF667085)),
          ),
        ],
        if (incomingWindowsTemp && !running) ...[
          const SizedBox(height: 7),
          Row(
            children: [
              const Icon(
                Icons.schedule_rounded,
                size: 15,
                color: Color(0xFF8A5A00),
              ),
              const SizedBox(width: 5),
              const Expanded(
                child: Text(
                  'مؤقت — يُحذف عند إغلاق LocalShare',
                  style: TextStyle(
                    color: Color(0xFF8A5A00),
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              TextButton(
                onPressed: () => _savePermanent(context),
                child: const Text('حفظ دائم'),
              ),
            ],
          ),
        ] else if (androidPermanent && !running) ...[
          const SizedBox(height: 6),
          const Row(
            children: [
              Icon(
                Icons.check_circle_outline_rounded,
                size: 15,
                color: Color(0xFF128A50),
              ),
              SizedBox(width: 5),
              Expanded(
                child: Text(
                  'محفوظ في Downloads/LocalShare',
                  style: TextStyle(
                    color: Color(0xFF128A50),
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ] else if (message.savedPermanently &&
            message.isIncoming &&
            !running) ...[
          const SizedBox(height: 6),
          const Text(
            'محفوظ بشكل دائم',
            style: TextStyle(
              color: Color(0xFF128A50),
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
        if (message.deliveryStatus == ChatDeliveryStatus.failed &&
            message.error != null) ...[
          const SizedBox(height: 5),
          Text(
            message.isIncoming
                ? 'فشل استلام الملف'
                : 'فشل الإرسال • اضغط إعادة المحاولة',
            style: const TextStyle(
              color: Color(0xFFC62828),
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
        const SizedBox(height: 4),
        _MessageMeta(message: message, foreground: foreground),
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
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('تم حفظ الملف بشكل دائم')));
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
        Text(
          _formatTime(message.sentAt),
          style: TextStyle(
            color: foreground.withValues(alpha: 0.55),
            fontSize: 9.5,
          ),
        ),
        if (icon != null) ...[
          const SizedBox(width: 4),
          Icon(
            icon,
            size: 13,
            color: iconColor ?? foreground.withValues(alpha: 0.5),
          ),
        ],
      ],
    );
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
            Icon(
              Icons.chat_bubble_outline_rounded,
              size: 70,
              color: Color(0xFF9AA4B2),
            ),
            SizedBox(height: 14),
            Text(
              'اختر جهازًا لفتح المحادثة',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
            ),
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
        padding: EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.lock_outline_rounded,
              size: 34,
              color: Color(0xFF98A2B3),
            ),
            SizedBox(height: 9),
            Text(
              'اتصال محلي مشفّر',
              style: TextStyle(
                fontWeight: FontWeight.w800,
                color: Color(0xFF475467),
              ),
            ),
            SizedBox(height: 4),
            Text(
              'أرسل رسالة، رابطًا أو ملفًا',
              style: TextStyle(fontSize: 12, color: Color(0xFF98A2B3)),
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
              style: const TextStyle(
                fontSize: 12,
                color: Color(0xFF344054),
                height: 1.4,
              ),
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
        gradient: const LinearGradient(
          colors: [Color(0xFF0D5BD7), Color(0xFF17B4D9)],
        ),
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
          const Icon(
            Icons.error_outline_rounded,
            color: Color(0xFFC62828),
            size: 42,
          ),
          const SizedBox(height: 10),
          const Text(
            'تعذر تشغيل LocalShare',
            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18),
          ),
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
              const Text(
                'أدخل رمز الربط المكوّن من 6 أرقام الظاهر على الجهاز الآخر.',
              ),
              const SizedBox(height: 14),
              TextField(
                controller: controller,
                autofocus: true,
                keyboardType: TextInputType.number,
                maxLength: 6,
                textDirection: TextDirection.ltr,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: const InputDecoration(
                  labelText: 'رمز الربط',
                  counterText: '',
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: busy ? null : () => Navigator.pop(context),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: busy
                ? null
                : () async {
                    setState(() => busy = true);
                    try {
                      final peer = await service.pairDevice(
                        device,
                        controller.text,
                      );
                      if (context.mounted) Navigator.pop(context);
                      onPaired(peer);
                    } catch (e) {
                      if (context.mounted) _showError(context, e);
                      setState(() => busy = false);
                    }
                  },
            child: busy
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('ربط'),
          ),
        ],
      ),
    ),
  );
  controller.dispose();
}

Future<void> _showManualIpDialog(
  BuildContext context,
  LocalShareService service,
) async {
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
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('إلغاء'),
        ),
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

Future<void> _showDeviceNameDialog(
  BuildContext context,
  LocalShareService service,
) async {
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
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('إلغاء'),
        ),
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
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('إلغاء'),
        ),
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

String _messagePreview(ChatMessage message) {
  if (message.deliveryStatus == ChatDeliveryStatus.failed)
    return 'تعذر الإرسال — اضغط لإعادة المحاولة';
  if (message.kind == ChatMessageKind.file)
    return '📎 ${message.fileName ?? 'ملف'}';
  if (message.kind == ChatMessageKind.link)
    return '🔗 ${_linkHost(message.text)}';
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
  return rtlMatch.start <= latinMatch.start
      ? TextDirection.rtl
      : TextDirection.ltr;
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
  if (RegExp(r'\.(jpg|jpeg|png|gif|webp|bmp)$').hasMatch(lower))
    return Icons.image_outlined;
  if (RegExp(r'\.(mp4|mov|mkv|avi|webm)$').hasMatch(lower))
    return Icons.movie_outlined;
  if (RegExp(r'\.(mp3|wav|m4a|aac|flac)$').hasMatch(lower))
    return Icons.audio_file_outlined;
  if (lower.endsWith('.pdf')) return Icons.picture_as_pdf_outlined;
  if (RegExp(r'\.(zip|rar|7z|tar|gz)$').hasMatch(lower))
    return Icons.folder_zip_outlined;
  return Icons.insert_drive_file_outlined;
}

Future<void> _confirmAndOpenLink(
  BuildContext context,
  LocalShareService service,
  String url,
) async {
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
          SelectableText(
            host,
            textDirection: TextDirection.ltr,
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('إلغاء'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: const Text('فتح'),
        ),
      ],
    ),
  );
  if (ok == true) {
    try {
      await service.openLink(url);
    } catch (e) {
      if (context.mounted) _showError(context, e);
    }
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
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('تم النسخ')));
    }
  } else if (action == 'open') {
    await _confirmAndOpenLink(context, service, message.text);
  } else if (action == 'retry') {
    try {
      await service.retryMessage(peer, message);
    } catch (_) {}
  }
}

String _formatTime(DateTime time) {
  final local = time.toLocal();
  final hour = local.hour.toString().padLeft(2, '0');
  final minute = local.minute.toString().padLeft(2, '0');
  return '$hour:$minute';
}
