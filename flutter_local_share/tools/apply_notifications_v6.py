from pathlib import Path

root = Path(__file__).resolve().parents[1]

# --- Service: emit a single incoming event only after a verified message/file is accepted. ---
service_path = root / 'lib' / 'chat_local_share_service.dart'
service = service_path.read_text(encoding='utf-8')

marker = "  final Map<String, DateTime> _recentNonces = {};\n"
replacement = marker + "\n  void Function(ChatMessage message)? onIncomingMessage;\n"
if 'onIncomingMessage;' not in service:
    if marker not in service:
        raise SystemExit('service callback marker not found')
    service = service.replace(marker, replacement, 1)

old = """    if (!duplicate) {
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
"""
new = """    if (!duplicate) {
      final incomingMessage = ChatMessage(
        id: id,
        peerId: peer.deviceId,
        peerName: peer.name,
        kind: kind,
        direction: ChatMessageDirection.receive,
        sentAt: DateTime.fromMillisecondsSinceEpoch(timestamp),
        text: text,
        deliveryStatus: ChatDeliveryStatus.delivered,
      );
      _messages.add(incomingMessage);
      _trimMessageHistory(peer.deviceId);
      notifyListeners();
      onIncomingMessage?.call(incomingMessage);
    }
"""
if 'onIncomingMessage?.call(incomingMessage);' not in service:
    if old not in service:
        raise SystemExit('incoming text marker not found')
    service = service.replace(old, new, 1)

old_file = """      incomingMessage.deliveryStatus = ChatDeliveryStatus.delivered;
      incomingMessage.error = null;
      notifyListeners();

      final ack = await _crypto.macString(
"""
new_file = """      incomingMessage.deliveryStatus = ChatDeliveryStatus.delivered;
      incomingMessage.error = null;
      notifyListeners();
      onIncomingMessage?.call(incomingMessage);

      final ack = await _crypto.macString(
"""
# The text replacement above already creates the same callback string, so inspect the file completion context.
if new_file not in service:
    if old_file not in service:
        raise SystemExit('incoming file completion marker not found')
    service = service.replace(old_file, new_file, 1)

service_path.write_text(service, encoding='utf-8')

# --- UI: initialize notification system, lifecycle-aware suppression, tap-to-open chat. ---
main_path = root / 'lib' / 'main.dart'
main = main_path.read_text(encoding='utf-8')

if "import 'dart:async';" not in main:
    main = main.replace("import 'dart:io';\n", "import 'dart:async';\nimport 'dart:io';\n", 1)

if "import 'notifications.dart';" not in main:
    main = main.replace("import 'models.dart';\n", "import 'models.dart';\nimport 'notifications.dart';\n", 1)

old_main = """void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const LocalShareApp());
}
"""
new_main = """Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await LocalShareNotifications.instance.initialize();
  runApp(const LocalShareApp());
}
"""
if old_main in main:
    main = main.replace(old_main, new_main, 1)

old_class = "class _LocalShareShellState extends State<LocalShareShell> {\n  late final LocalShareService service;\n  String? selectedPeerId;\n"
new_class = """class _LocalShareShellState extends State<LocalShareShell>
    with WidgetsBindingObserver {
  late final LocalShareService service;
  late final LocalShareNotifications notifications;
  String? selectedPeerId;
  String? _pendingNotificationPeerId;
  AppLifecycleState _appLifecycle = AppLifecycleState.resumed;
"""
if old_class in main:
    main = main.replace(old_class, new_class, 1)

old_init = """  @override
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
"""
new_init = """  @override
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

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _appLifecycle = state;
  }

  void _handleIncomingMessage(ChatMessage message) {
    final isViewingConversation =
        _appLifecycle == AppLifecycleState.resumed &&
        selectedPeerId == message.peerId;
    if (!isViewingConversation) {
      unawaited(notifications.showIncoming(message));
    }
  }

  void _openPeerFromNotification(String peerId) {
    _pendingNotificationPeerId = peerId;
    if (!mounted || !service.initialized || service.peerFor(peerId) == null) return;
    setState(() {
      selectedPeerId = peerId;
      _pendingNotificationPeerId = null;
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    service.onIncomingMessage = null;
    notifications.detachPeerHandler(_openPeerFromNotification);
    service.dispose();
    super.dispose();
  }
"""
if '_handleIncomingMessage(ChatMessage message)' not in main:
    if old_init not in main:
        raise SystemExit('main init marker not found')
    main = main.replace(old_init, new_init, 1)

# Resolve a notification tap that arrived while secure peers were still loading.
marker_build = """        if (service.startupError != null) {
          return Scaffold(
"""
insert_build = """        final pendingPeerId = _pendingNotificationPeerId;
        if (pendingPeerId != null &&
            service.peerFor(pendingPeerId) != null &&
            selectedPeerId != pendingPeerId) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            setState(() {
              selectedPeerId = pendingPeerId;
              _pendingNotificationPeerId = null;
            });
          });
        }

        if (service.startupError != null) {
          return Scaffold(
"""
if 'final pendingPeerId = _pendingNotificationPeerId;' not in main:
    if marker_build not in main:
        raise SystemExit('main build marker not found')
    main = main.replace(marker_build, insert_build, 1)

main_path.write_text(main, encoding='utf-8')
print('Applied LocalShare v6 notification integration')
