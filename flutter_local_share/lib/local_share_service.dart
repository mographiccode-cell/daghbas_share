import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'models.dart';

class LocalShareService extends ChangeNotifier {
  static const int serverPort = 40404;
  static const int discoveryPort = 40405;
  static const MethodChannel _native = MethodChannel('local_share/native');

  HttpServer? _server;
  RawDatagramSocket? _discoverySocket;
  Timer? _broadcastTimer;
  Timer? _staleTimer;
  SharedPreferences? _prefs;

  final Map<String, DiscoveredDevice> _discovered = {};
  final Map<String, Peer> _paired = {};
  final List<TransferItem> _transfers = [];

  late Directory receiveDirectory;
  String deviceId = '';
  String deviceName = '';
  String pairCode = '';
  String localIp = '—';
  bool initialized = false;
  bool discoveryAvailable = true;
  String? startupError;

  List<DiscoveredDevice> get discoveredDevices {
    final items = _discovered.values.toList()
      ..sort((a, b) {
        final ap = _paired.containsKey(a.deviceId) ? 0 : 1;
        final bp = _paired.containsKey(b.deviceId) ? 0 : 1;
        if (ap != bp) return ap.compareTo(bp);
        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });
    return items;
  }

  List<Peer> get pairedPeers => _paired.values.toList();
  List<TransferItem> get transfers => List.unmodifiable(_transfers.reversed);

  Future<void> init() async {
    try {
      _prefs = await SharedPreferences.getInstance();
      deviceId = _prefs!.getString('device_id') ?? _randomToken(18);
      await _prefs!.setString('device_id', deviceId);

      final savedName = _prefs!.getString('device_name');
      deviceName = savedName ?? _defaultDeviceName();
      await _prefs!.setString('device_name', deviceName);

      pairCode = (100000 + Random.secure().nextInt(900000)).toString();
      await _loadPeers();
      receiveDirectory = await _resolveReceiveDirectory();
      await receiveDirectory.create(recursive: true);
      localIp = await _bestLocalIp();

      await _startServer();
      await _startDiscovery();
      initialized = true;
      notifyListeners();
    } catch (e) {
      startupError = e.toString();
      initialized = true;
      notifyListeners();
    }
  }

  String _defaultDeviceName() {
    if (Platform.isAndroid) return 'هاتف Android';
    if (Platform.isWindows) {
      final host = Platform.localHostname.trim();
      return host.isEmpty ? 'Windows PC' : host;
    }
    return Platform.localHostname.isEmpty ? 'LocalShare' : Platform.localHostname;
  }

  Future<void> setDeviceName(String value) async {
    final clean = value.trim();
    if (clean.isEmpty || clean == deviceName) return;
    deviceName = clean.length > 32 ? clean.substring(0, 32) : clean;
    await _prefs?.setString('device_name', deviceName);
    _broadcastPresence();
    notifyListeners();
  }

  Peer? peerFor(String deviceId) => _paired[deviceId];

  bool isOnline(String deviceId) {
    final item = _discovered[deviceId];
    if (item == null) return false;
    return DateTime.now().difference(item.lastSeen) < const Duration(seconds: 12);
  }

  Future<Directory> _resolveReceiveDirectory() async {
    if (Platform.isWindows) {
      final downloads = await getDownloadsDirectory();
      if (downloads != null) return Directory('${downloads.path}${Platform.pathSeparator}LocalShare');
    }
    if (Platform.isAndroid) {
      final external = await getExternalStorageDirectory();
      if (external != null) return Directory('${external.path}${Platform.pathSeparator}LocalShare');
    }
    final docs = await getApplicationDocumentsDirectory();
    return Directory('${docs.path}${Platform.pathSeparator}LocalShare');
  }

  Future<String> _bestLocalIp() async {
    try {
      final interfaces = await NetworkInterface.list(type: InternetAddressType.IPv4, includeLoopback: false);
      final addresses = <String>[];
      for (final interface in interfaces) {
        for (final address in interface.addresses) {
          if (!address.isLoopback) addresses.add(address.address);
        }
      }
      for (final ip in addresses) {
        if (ip.startsWith('192.168.') || ip.startsWith('10.') || _isPrivate172(ip)) return ip;
      }
      if (addresses.isNotEmpty) return addresses.first;
    } catch (_) {}
    return '—';
  }

  bool _isPrivate172(String ip) {
    final parts = ip.split('.');
    if (parts.length != 4 || parts[0] != '172') return false;
    final second = int.tryParse(parts[1]) ?? -1;
    return second >= 16 && second <= 31;
  }

  Future<void> _startServer() async {
    _server = await HttpServer.bind(InternetAddress.anyIPv4, serverPort, shared: true);
    _server!.listen(_handleRequest, onError: (Object e) {
      startupError = 'Server: $e';
      notifyListeners();
    });
  }

  Future<void> _startDiscovery() async {
    try {
      _discoverySocket = await RawDatagramSocket.bind(
        InternetAddress.anyIPv4,
        discoveryPort,
        reuseAddress: true,
      );
      _discoverySocket!.broadcastEnabled = true;
      _discoverySocket!.listen(_onDiscoveryEvent, onError: (_) {
        discoveryAvailable = false;
        notifyListeners();
      });
      _broadcastTimer = Timer.periodic(const Duration(seconds: 3), (_) => _broadcastPresence());
      _staleTimer = Timer.periodic(const Duration(seconds: 5), (_) => _removeStaleDevices());
      _broadcastPresence();
    } catch (_) {
      discoveryAvailable = false;
      notifyListeners();
    }
  }

  void _onDiscoveryEvent(RawSocketEvent event) {
    if (event != RawSocketEvent.read || _discoverySocket == null) return;
    Datagram? datagram;
    while ((datagram = _discoverySocket!.receive()) != null) {
      final data = datagram!;
      final text = utf8.decode(data.data, allowMalformed: true);
      final parts = text.split('|');
      if (parts.length < 5 || parts[0] != 'LOCALSHARE1') continue;
      final type = parts[1];
      final id = parts[2];
      if (id == deviceId) continue;
      final name = Uri.decodeComponent(parts[3]);
      final port = int.tryParse(parts[4]) ?? serverPort;
      _rememberDiscovered(id, name, data.address.address, port);
      if (type == 'DISCOVER') {
        _sendDiscovery('HERE', data.address);
      }
    }
  }

  void _rememberDiscovered(String id, String name, String ip, int port) {
    _discovered[id] = DiscoveredDevice(
      deviceId: id,
      name: name,
      ip: ip,
      port: port,
      lastSeen: DateTime.now(),
    );
    final peer = _paired[id];
    if (peer != null && (peer.ip != ip || peer.port != port || peer.name != name)) {
      _paired[id] = peer.copyWith(ip: ip, port: port, name: name);
      unawaited(_savePeers());
    }
    notifyListeners();
  }

  void _broadcastPresence() {
    _sendDiscovery('DISCOVER', InternetAddress('255.255.255.255'));
  }

  void _sendDiscovery(String type, InternetAddress address) {
    final socket = _discoverySocket;
    if (socket == null) return;
    final message = 'LOCALSHARE1|$type|$deviceId|${Uri.encodeComponent(deviceName)}|$serverPort';
    try {
      socket.send(utf8.encode(message), address, discoveryPort);
    } catch (_) {}
  }

  void _removeStaleDevices() {
    final now = DateTime.now();
    final before = _discovered.length;
    _discovered.removeWhere((_, value) => now.difference(value.lastSeen) > const Duration(seconds: 18));
    if (_discovered.length != before) notifyListeners();
  }

  Future<void> _handleRequest(HttpRequest request) async {
    try {
      request.response.headers.set('X-LocalShare', '1');
      if (request.method == 'GET' && request.uri.path == '/hello') {
        _jsonResponse(request, HttpStatus.ok, {
          'protocol': 1,
          'deviceId': deviceId,
          'name': deviceName,
          'port': serverPort,
        });
        return;
      }

      if (request.method == 'POST' && request.uri.path == '/pair') {
        await _handlePair(request);
        return;
      }

      if (request.method == 'POST' && request.uri.path == '/upload') {
        await _handleUpload(request);
        return;
      }

      request.response.statusCode = HttpStatus.notFound;
      await request.response.close();
    } catch (e) {
      try {
        request.response.statusCode = HttpStatus.internalServerError;
        request.response.write('transfer_error');
        await request.response.close();
      } catch (_) {}
    }
  }

  Future<void> _handlePair(HttpRequest request) async {
    final body = await utf8.decoder.bind(request).join();
    if (body.length > 8192) {
      _jsonResponse(request, HttpStatus.badRequest, {'error': 'invalid_request'});
      return;
    }
    final data = jsonDecode(body) as Map<String, dynamic>;
    final code = '${data['code'] ?? ''}'.trim();
    if (code != pairCode) {
      _jsonResponse(request, HttpStatus.forbidden, {'error': 'wrong_code'});
      return;
    }

    final sourceId = '${data['deviceId'] ?? ''}'.trim();
    final sourceName = '${data['name'] ?? 'Device'}'.trim();
    final sourceAcceptToken = '${data['acceptToken'] ?? ''}'.trim();
    if (sourceId.isEmpty || sourceAcceptToken.length < 20) {
      _jsonResponse(request, HttpStatus.badRequest, {'error': 'invalid_request'});
      return;
    }

    final remoteIp = request.connectionInfo?.remoteAddress.address ?? '';
    final remotePort = (data['port'] as num?)?.toInt() ?? serverPort;
    final myAcceptToken = _randomToken(32);

    _paired[sourceId] = Peer(
      deviceId: sourceId,
      name: sourceName.isEmpty ? 'Device' : sourceName,
      ip: remoteIp,
      port: remotePort,
      outboundToken: sourceAcceptToken,
      inboundToken: myAcceptToken,
    );
    await _savePeers();
    _rememberDiscovered(sourceId, sourceName, remoteIp, remotePort);

    _jsonResponse(request, HttpStatus.ok, {
      'deviceId': deviceId,
      'name': deviceName,
      'port': serverPort,
      'acceptToken': myAcceptToken,
    });
  }

  Future<void> _handleUpload(HttpRequest request) async {
    final token = request.headers.value('x-localshare-token') ?? '';
    Peer? sourcePeer;
    for (final peer in _paired.values) {
      if (peer.inboundToken == token) {
        sourcePeer = peer;
        break;
      }
    }
    if (sourcePeer == null) {
      request.response.statusCode = HttpStatus.unauthorized;
      request.response.write('pair_required');
      await request.response.close();
      return;
    }

    final rawName = request.uri.queryParameters['name'] ?? 'received_file';
    final fileName = safeFileName(rawName);
    final total = int.tryParse(request.uri.queryParameters['size'] ?? '') ?? request.contentLength;
    final destination = await _uniqueFile(fileName);
    final transfer = TransferItem(
      id: _randomToken(10),
      fileName: destination.uri.pathSegments.last,
      peerName: sourcePeer.name,
      direction: TransferDirection.receive,
      totalBytes: total < 0 ? 0 : total,
      startedAt: DateTime.now(),
      status: TransferStatus.running,
      localPath: destination.path,
    );
    _transfers.add(transfer);
    notifyListeners();

    IOSink? sink;
    try {
      sink = destination.openWrite();
      var received = 0;
      var lastNotify = DateTime.fromMillisecondsSinceEpoch(0);
      await for (final chunk in request) {
        sink.add(chunk);
        received += chunk.length;
        if (transfer.totalBytes > 0) {
          transfer.progress = (received / transfer.totalBytes).clamp(0.0, 1.0).toDouble();
        }
        final now = DateTime.now();
        if (now.difference(lastNotify) > const Duration(milliseconds: 120)) {
          lastNotify = now;
          notifyListeners();
        }
      }
      await sink.flush();
      await sink.close();
      sink = null;
      transfer.progress = 1;
      transfer.status = TransferStatus.completed;
      notifyListeners();
      _jsonResponse(request, HttpStatus.ok, {
        'ok': true,
        'name': destination.uri.pathSegments.last,
        'bytes': received,
      });
    } catch (e) {
      await sink?.close();
      transfer.status = TransferStatus.failed;
      transfer.error = e.toString();
      notifyListeners();
      request.response.statusCode = HttpStatus.internalServerError;
      request.response.write('write_failed');
      await request.response.close();
    }
  }

  void _jsonResponse(HttpRequest request, int status, Map<String, dynamic> body) {
    request.response.statusCode = status;
    request.response.headers.contentType = ContentType.json;
    request.response.write(jsonEncode(body));
    unawaited(request.response.close());
  }

  Future<File> _uniqueFile(String fileName) async {
    final separator = Platform.pathSeparator;
    var target = File('${receiveDirectory.path}$separator$fileName');
    if (!await target.exists()) return target;

    final dot = fileName.lastIndexOf('.');
    final stem = dot > 0 ? fileName.substring(0, dot) : fileName;
    final ext = dot > 0 ? fileName.substring(dot) : '';
    var index = 1;
    while (true) {
      target = File('${receiveDirectory.path}$separator$stem ($index)$ext');
      if (!await target.exists()) return target;
      index++;
    }
  }

  Future<void> probeIp(String rawIp) async {
    var ip = rawIp.trim();
    ip = ip.replaceFirst(RegExp(r'^https?://'), '');
    ip = ip.split('/').first;
    if (ip.contains(':')) ip = ip.split(':').first;
    if (ip.isEmpty) throw const FormatException('أدخل عنوان IP صحيح');

    final client = HttpClient()..connectionTimeout = const Duration(seconds: 3);
    try {
      final request = await client.getUrl(Uri.parse('http://$ip:$serverPort/hello'));
      final response = await request.close().timeout(const Duration(seconds: 4));
      if (response.statusCode != HttpStatus.ok) throw const HttpException('No LocalShare server');
      final body = await utf8.decoder.bind(response).join();
      final data = jsonDecode(body) as Map<String, dynamic>;
      final id = '${data['deviceId']}';
      if (id == deviceId) return;
      _rememberDiscovered(
        id,
        '${data['name'] ?? 'Device'}',
        ip,
        (data['port'] as num?)?.toInt() ?? serverPort,
      );
    } finally {
      client.close(force: true);
    }
  }

  Future<Peer> pairDevice(DiscoveredDevice device, String code) async {
    final myAcceptToken = _randomToken(32);
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 4);
    try {
      final request = await client.postUrl(Uri.parse('http://${device.ip}:${device.port}/pair'));
      request.headers.contentType = ContentType.json;
      request.write(jsonEncode({
        'code': code.trim(),
        'deviceId': deviceId,
        'name': deviceName,
        'port': serverPort,
        'acceptToken': myAcceptToken,
      }));
      final response = await request.close().timeout(const Duration(seconds: 8));
      final text = await utf8.decoder.bind(response).join();
      if (response.statusCode == HttpStatus.forbidden) {
        throw const PairingException('رمز الربط غير صحيح');
      }
      if (response.statusCode != HttpStatus.ok) {
        throw PairingException('فشل الربط (${response.statusCode})');
      }
      final data = jsonDecode(text) as Map<String, dynamic>;
      final peer = Peer(
        deviceId: '${data['deviceId']}',
        name: '${data['name'] ?? device.name}',
        ip: device.ip,
        port: (data['port'] as num?)?.toInt() ?? device.port,
        outboundToken: '${data['acceptToken']}',
        inboundToken: myAcceptToken,
      );
      _paired[peer.deviceId] = peer;
      await _savePeers();
      notifyListeners();
      return peer;
    } on TimeoutException {
      throw const PairingException('انتهت مهلة الاتصال. تأكد أن الجهازين على نفس الشبكة.');
    } finally {
      client.close(force: true);
    }
  }

  Future<void> forgetPeer(String id) async {
    _paired.remove(id);
    await _savePeers();
    notifyListeners();
  }

  Future<void> pickAndSend(Peer peer) async {
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

  Future<void> sendFile(Peer peer, File file) async {
    if (!await file.exists()) throw const FileSystemException('الملف غير موجود');
    final total = await file.length();
    final fileName = safeFileName(file.uri.pathSegments.last);
    final transfer = TransferItem(
      id: _randomToken(10),
      fileName: fileName,
      peerName: peer.name,
      direction: TransferDirection.send,
      totalBytes: total,
      startedAt: DateTime.now(),
      status: TransferStatus.running,
    );
    _transfers.add(transfer);
    notifyListeners();

    final current = _paired[peer.deviceId] ?? peer;
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 5);
    try {
      final uri = Uri(
        scheme: 'http',
        host: current.ip,
        port: current.port,
        path: '/upload',
        queryParameters: {'name': fileName, 'size': '$total'},
      );
      final request = await client.postUrl(uri);
      request.headers.set('x-localshare-token', current.outboundToken);
      request.headers.contentType = ContentType.binary;
      request.contentLength = total;

      var sent = 0;
      var lastNotify = DateTime.fromMillisecondsSinceEpoch(0);
      final stream = file.openRead().map((chunk) {
        sent += chunk.length;
        transfer.progress = total == 0 ? 1.0 : (sent / total).clamp(0.0, 1.0).toDouble();
        final now = DateTime.now();
        if (now.difference(lastNotify) > const Duration(milliseconds: 120)) {
          lastNotify = now;
          notifyListeners();
        }
        return chunk;
      });
      await request.addStream(stream);
      final response = await request.close();
      await response.drain<void>();
      if (response.statusCode == HttpStatus.unauthorized) {
        throw const PairingException('انتهى الربط. أعد ربط الجهازين.');
      }
      if (response.statusCode != HttpStatus.ok) {
        throw HttpException('Transfer failed: ${response.statusCode}');
      }
      transfer.progress = 1;
      transfer.status = TransferStatus.completed;
      notifyListeners();
    } catch (e) {
      transfer.status = TransferStatus.failed;
      transfer.error = e.toString();
      notifyListeners();
      rethrow;
    } finally {
      client.close(force: true);
    }
  }

  Future<List<FileSystemEntity>> receivedFiles() async {
    if (!await receiveDirectory.exists()) return [];
    final items = await receiveDirectory.list(followLinks: false).where((e) => e is File).toList();
    items.sort((a, b) => b.statSync().modified.compareTo(a.statSync().modified));
    return items;
  }

  Future<String> exportReceivedFile(File file) async {
    if (Platform.isWindows) {
      final target = await FilePicker.platform.saveFile(
        dialogTitle: 'حفظ نسخة من الملف',
        fileName: file.uri.pathSegments.last,
      );
      if (target == null) return '';
      await file.copy(target);
      return target;
    }
    if (Platform.isAndroid) {
      final result = await _native.invokeMethod<String>('exportToDownloads', {
        'path': file.path,
        'name': file.uri.pathSegments.last,
      });
      return result ?? '';
    }
    return '';
  }

  Future<void> _loadPeers() async {
    final raw = _prefs?.getString('paired_peers');
    if (raw == null || raw.isEmpty) return;
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      for (final item in list) {
        final peer = Peer.fromJson(Map<String, dynamic>.from(item as Map));
        _paired[peer.deviceId] = peer;
      }
    } catch (_) {
      await _prefs?.remove('paired_peers');
    }
  }

  Future<void> _savePeers() async {
    final raw = jsonEncode(_paired.values.map((e) => e.toJson()).toList());
    await _prefs?.setString('paired_peers', raw);
  }

  String _randomToken(int length) {
    const alphabet = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_';
    final random = Random.secure();
    return List.generate(length, (_) => alphabet[random.nextInt(alphabet.length)]).join();
  }

  @override
  void dispose() {
    _broadcastTimer?.cancel();
    _staleTimer?.cancel();
    _discoverySocket?.close();
    unawaited(_server?.close(force: true));
    super.dispose();
  }
}

class PairingException implements Exception {
  const PairingException(this.message);
  final String message;
  @override
  String toString() => message;
}
