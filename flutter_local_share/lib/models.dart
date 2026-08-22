enum TransferDirection { send, receive }

enum TransferStatus { queued, running, completed, failed }

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

  DiscoveredDevice copyWith({
    String? name,
    String? ip,
    int? port,
    DateTime? lastSeen,
  }) {
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
    required this.outboundToken,
    required this.inboundToken,
  });

  final String deviceId;
  final String name;
  final String ip;
  final int port;
  final String outboundToken;
  final String inboundToken;

  Peer copyWith({
    String? name,
    String? ip,
    int? port,
    String? outboundToken,
    String? inboundToken,
  }) {
    return Peer(
      deviceId: deviceId,
      name: name ?? this.name,
      ip: ip ?? this.ip,
      port: port ?? this.port,
      outboundToken: outboundToken ?? this.outboundToken,
      inboundToken: inboundToken ?? this.inboundToken,
    );
  }

  Map<String, dynamic> toJson() => {
        'deviceId': deviceId,
        'name': name,
        'ip': ip,
        'port': port,
        'outboundToken': outboundToken,
        'inboundToken': inboundToken,
      };

  factory Peer.fromJson(Map<String, dynamic> json) {
    return Peer(
      deviceId: json['deviceId'] as String,
      name: json['name'] as String,
      ip: json['ip'] as String,
      port: (json['port'] as num).toInt(),
      outboundToken: json['outboundToken'] as String,
      inboundToken: json['inboundToken'] as String,
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

String safeFileName(String raw) {
  var name = raw.split(RegExp(r'[\\/]')).last.trim();
  name = name.replaceAll(RegExp(r'[\x00-\x1F<>:"|?*]'), '_');
  if (name.isEmpty || name == '.' || name == '..') {
    return 'received_file';
  }
  if (name.length > 180) {
    final dot = name.lastIndexOf('.');
    final ext = dot > 0 && name.length - dot <= 16 ? name.substring(dot) : '';
    final stemLimit = 180 - ext.length;
    name = '${name.substring(0, stemLimit)}$ext';
  }
  return name;
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
