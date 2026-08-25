enum TransferDirection { send, receive }

enum TransferStatus { queued, running, completed, failed }

enum ChatMessageKind { text, link, file, system }

enum ChatMessageDirection { send, receive }

enum ChatDeliveryStatus { sending, delivered, failed }

class DiscoveredDevice {
  const DiscoveredDevice({
    required this.deviceId,
    required this.name,
    required this.ip,
    required this.port,
    required this.lastSeen,
  });

  final String deviceId;
  final String name;
  final String ip;
  final int port;
  final DateTime lastSeen;

  DiscoveredDevice copyWith({String? name, String? ip, int? port, DateTime? lastSeen}) {
    return DiscoveredDevice(
      deviceId: deviceId,
      name: name ?? this.name,
      ip: ip ?? this.ip,
      port: port ?? this.port,
      lastSeen: lastSeen ?? this.lastSeen,
    );
  }
}

class Peer {
  const Peer({
    required this.deviceId,
    required this.name,
    required this.ip,
    required this.port,
    required this.sharedKey,
  });

  final String deviceId;
  final String name;
  final String ip;
  final int port;
  final String sharedKey;

  Peer copyWith({String? name, String? ip, int? port, String? sharedKey}) {
    return Peer(
      deviceId: deviceId,
      name: name ?? this.name,
      ip: ip ?? this.ip,
      port: port ?? this.port,
      sharedKey: sharedKey ?? this.sharedKey,
    );
  }

  Map<String, dynamic> toJson() => {
        'deviceId': deviceId,
        'name': name,
        'ip': ip,
        'port': port,
        'sharedKey': sharedKey,
      };

  factory Peer.fromJson(Map<String, dynamic> json) {
    return Peer(
      deviceId: json['deviceId'] as String,
      name: json['name'] as String,
      ip: json['ip'] as String,
      port: (json['port'] as num).toInt(),
      sharedKey: json['sharedKey'] as String,
    );
  }
}

class TransferItem {
  TransferItem({
    required this.id,
    required this.fileName,
    required this.peerName,
    required this.direction,
    required this.totalBytes,
    required this.startedAt,
    this.progress = 0,
    this.status = TransferStatus.queued,
    this.error,
    this.localPath,
  });

  final String id;
  final String fileName;
  final String peerName;
  final TransferDirection direction;
  final int totalBytes;
  final DateTime startedAt;
  double progress;
  TransferStatus status;
  String? error;
  String? localPath;
}

class ChatMessage {
  ChatMessage({
    required this.id,
    required this.peerId,
    required this.peerName,
    required this.kind,
    required this.direction,
    required this.sentAt,
    this.text = '',
    this.fileName,
    this.fileSize,
    this.localPath,
    this.transferId,
    this.temporary = false,
    this.savedPermanently = false,
    this.deliveryStatus = ChatDeliveryStatus.delivered,
    this.error,
  });

  final String id;
  final String peerId;
  final String peerName;
  final ChatMessageKind kind;
  final ChatMessageDirection direction;
  final DateTime sentAt;
  final String text;
  final String? fileName;
  final int? fileSize;
  String? localPath;
  String? transferId;
  bool temporary;
  bool savedPermanently;
  ChatDeliveryStatus deliveryStatus;
  String? error;

  bool get isIncoming => direction == ChatMessageDirection.receive;
  bool get isMine => direction == ChatMessageDirection.send;
  bool get isFile => kind == ChatMessageKind.file;
  bool get canOpenFile => isFile && localPath != null && localPath!.isNotEmpty;
  bool get canRetry => isMine && deliveryStatus == ChatDeliveryStatus.failed;
}

ChatMessageKind classifyChatText(String value) {
  final text = value.trim();
  final uri = Uri.tryParse(text);
  if (uri != null &&
      (uri.scheme.toLowerCase() == 'http' || uri.scheme.toLowerCase() == 'https') &&
      uri.host.isNotEmpty) {
    return ChatMessageKind.link;
  }
  return ChatMessageKind.text;
}

String safeFileName(String raw) {
  var name = raw.split(RegExp(r'[\\/]')).last.trim();
  name = name.replaceAll(RegExp(r'[\x00-\x1F\x7F<>:"|?*]'), '_');
  name = name.replaceFirst(RegExp(r'[. ]+$'), '');

  if (name.isEmpty || name == '.' || name == '..') return 'received_file';

  final dot = name.lastIndexOf('.');
  final stem = (dot > 0 ? name.substring(0, dot) : name).trim();
  final reserved = RegExp(r'^(CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])$', caseSensitive: false);
  if (reserved.hasMatch(stem)) name = '_$name';

  if (name.length > 180) {
    final extensionIndex = name.lastIndexOf('.');
    final ext = extensionIndex > 0 && name.length - extensionIndex <= 16
        ? name.substring(extensionIndex)
        : '';
    final stemLimit = 180 - ext.length;
    name = '${name.substring(0, stemLimit)}$ext';
    name = name.replaceFirst(RegExp(r'[. ]+$'), '');
  }

  return name.isEmpty ? 'received_file' : name;
}

String formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  const units = ['KB', 'MB', 'GB', 'TB'];
  var value = bytes / 1024.0;
  var index = 0;
  while (value >= 1024 && index < units.length - 1) {
    value /= 1024;
    index++;
  }
  final decimals = value >= 100 ? 0 : value >= 10 ? 1 : 2;
  return '${value.toStringAsFixed(decimals)} ${units[index]}';
}
